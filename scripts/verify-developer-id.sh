#!/usr/bin/env bash
# Checks an exported Developer ID Segue.app before it goes into a DMG and to Apple's notary
# service (docs/release/decisions.md R200, scripts/dmg.sh).
#
#   scripts/verify-developer-id.sh <Segue.app> <personal|appstore> [--development-signed]
#
# 1. right product: the flavour's bundle ID, and exactly its Quick Look preview and
#    thumbnail extensions
# 2. version: Config/Version.xcconfig in the app and every extension
# 3. signatures: codesign --verify --deep --strict, and on every bundle and Mach-O file the
#    Developer ID Application identity, the team, the hardened runtime and a secure timestamp
#    (what notarization requires)
# 4. entitlements: the app's release set (`app_entitlements`, scripts/lib/verify-common.sh)
#    and sandbox-only extensions; never get-task-allow, never a temporary exception
# 5. contents: no test hooks or Debug dylib; the App Store flavour has no personal code;
#    the Help Book and the stamped resource bundle; no quarantine attribute
#
# --development-signed (scripts/dmg.sh --dry-run on a Mac without the Developer ID identity):
# the app was exported with the archive's own Apple Development signature, so the identity and the timestamp
# are reported but not required, and the identifiers that development signing adds
# (get-task-allow, application-identifier, team-identifier) are notes, not failures.
# Everything else is checked exactly as in a real run. Fails closed: anything unreadable
# is a failure.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

prefix="verify-developer-id"
# shellcheck source=lib/verify-common.sh
source scripts/lib/verify-common.sh

team="V6BM673U35"
identity="Developer ID Application: Ryan Rony Dsilva ($team)"
buddy=/usr/libexec/PlistBuddy

usage() {
    echo "usage: scripts/verify-developer-id.sh <Segue.app> <personal|appstore> [--development-signed]" >&2
    exit 2
}
[[ $# -ge 2 && $# -le 3 ]] || usage
app="$1"
flavour="$2"
dev_signed=0
if [[ $# -eq 3 ]]; then
    [[ "$3" == "--development-signed" ]] || usage
    dev_signed=1
fi
case "$flavour" in
personal) app_id="dev.ryandsilva.segue.personal" ;;
appstore) app_id="dev.ryandsilva.segue" ;;
*) usage ;;
esac

if [[ ! -r "$app/Contents/Info.plist" ]]; then
    fail "inputs: $app is not a readable app bundle"
    exit 1
fi

scratch=$(mktemp -d "${TMPDIR:-/tmp}/segue-verify-developer-id.XXXXXX")
trap 'find "$scratch" -depth -delete 2>/dev/null || true' EXIT

plist_get() { "$buddy" -c "Print :$2" "$1" 2>/dev/null; }
bundle_id() { plist_get "$1/Contents/Info.plist" CFBundleIdentifier; }
short() { echo "${1#"$app/"}"; }
note() { echo "$prefix: note: $*"; }

bundles=("$app")
for appex in "$app"/Contents/PlugIns/*.appex; do
    [[ -d "$appex" ]] && bundles+=("$appex")
done
machos=()
while IFS= read -r -d '' file; do
    if file -b "$file" 2>/dev/null | grep -q 'Mach-O'; then
        machos+=("$file")
    fi
done < <(find "$app" -type f -print0)
((${#machos[@]} > 0)) || fail "inputs: no Mach-O files found in $app"

# MARK: 1. Right product

check_1() {
    local got want ok=1 bundle
    got=$(bundle_id "$app")
    [[ "$got" == "$app_id" ]] || { fail "1: app is '$got', not $app_id ($flavour)"; ok=0; }
    want=$(printf '%s\n' "$app_id.quicklook" "$app_id.thumbnail" | sort)
    got=$(for bundle in "${bundles[@]:1}"; do bundle_id "$bundle"; done | sort)
    [[ "$got" == "$want" ]] || { fail "1: extensions are '$(tr '\n' ' ' <<<"$got")', want '$(tr '\n' ' ' <<<"$want")'"; ok=0; }
    ((ok)) && pass "1: $app_id ($flavour) with its preview and thumbnail extensions"
}

# MARK: 2. Version

check_2() {
    local marketing build bundle v b ok=1
    if ! read -r marketing build < <(scripts/bump-version.sh show) || [[ -z "${build:-}" ]]; then
        fail "2: cannot read Config/Version.xcconfig"
        return
    fi
    for bundle in "${bundles[@]}"; do
        v=$(plist_get "$bundle/Contents/Info.plist" CFBundleShortVersionString)
        b=$(plist_get "$bundle/Contents/Info.plist" CFBundleVersion)
        [[ "$v" == "$marketing" && "$b" == "$build" ]] || { fail "2: $(short "$bundle") is $v ($b), want $marketing ($build)"; ok=0; }
    done
    ((ok)) && pass "2: $marketing ($build) in the app and every extension"
}

# MARK: 3. Signatures

check_3() {
    if codesign --verify --deep --strict "$app" 2>"$scratch/verify.txt"; then
        pass "3: codesign --verify --deep --strict"
    else
        fail "3: codesign --verify failed: $(command cat "$scratch/verify.txt")"
    fi
    local code info authority teamid flags bad="" untimed="" authorities=""
    for code in "${bundles[@]}" "${machos[@]}"; do
        if ! info=$(codesign -dvv "$code" 2>&1); then
            bad+="$(short "$code"): unsigned or unreadable"$'\n'
            continue
        fi
        authority=$(sed -n 's/^Authority=//p' <<<"$info" | head -n 1)
        teamid=$(sed -n 's/^TeamIdentifier=//p' <<<"$info")
        flags=$(sed -n -E 's/^CodeDirectory .*flags=(0x[0-9a-f]+)\(([^)]*)\).*/\2/p' <<<"$info")
        authorities+="${authority:-ad hoc}"$'\n'
        [[ "$teamid" == "$team" ]] || bad+="$(short "$code"): team '$teamid'"$'\n'
        [[ ",$flags," == *",runtime,"* ]] || bad+="$(short "$code"): no hardened runtime (flags '$flags')"$'\n'
        if ((!dev_signed)) && [[ "$authority" != "$identity" ]]; then
            bad+="$(short "$code"): signed by '$authority'"$'\n'
        fi
        grep -q '^Timestamp=' <<<"$info" || untimed+="$(short "$code") "
    done
    if [[ -n "$bad" ]]; then
        fail "3: signatures:"$'\n'"$bad"
    else
        local count=$((${#bundles[@]} + ${#machos[@]}))
        pass "3: $count code objects: team $team, hardened runtime, signed by $(sort -u <<<"$authorities" | sed '/^$/d' | paste -s -d '|' -)"
    fi
    if [[ -n "$untimed" ]]; then
        if ((dev_signed)); then
            note "3: no secure timestamp (expected for the archive's development signature): $untimed"
        else
            fail "3: no secure timestamp on: $untimed"
        fi
    else
        pass "3: every code object has a secure timestamp"
    fi
}

# MARK: 4. Entitlements

# Keys development signing adds that the Developer ID export must not carry.
signing_keys='["com.apple.security.get-task-allow","com.apple.application-identifier","com.apple.developer.team-identifier"]'

check_4() {
    local bundle id want got extra
    for bundle in "${bundles[@]}"; do
        id=$(bundle_id "$bundle")
        if ! codesign -d --entitlements - --xml "$bundle" >"$scratch/ent.plist" 2>/dev/null \
            || ! got=$(plutil -convert json -o - "$scratch/ent.plist" 2>/dev/null | jq -S .) \
            || [[ -z "$got" ]]; then
            fail "4: cannot read the signed entitlements of $(short "$bundle")"
            continue
        fi
        if [[ "$bundle" == "$app" ]]; then
            want=$(app_entitlements)
        else
            want=$(jq -n -S '{"com.apple.security.app-sandbox": true}')
        fi
        extra=$(jq -r --argjson keys "$signing_keys" 'keys - (keys - $keys) | join(" ")' <<<"$got")
        if [[ -n "$extra" ]]; then
            if ((dev_signed)); then
                note "4: $id carries development-signing keys a Developer ID export drops: $extra"
            else
                fail "4: $id carries $extra (notarization rejects get-task-allow; the identifiers need a profile)"
            fi
            got=$(jq -S --argjson keys "$signing_keys" 'with_entries(select(.key as $k | $keys | index($k) | not))' <<<"$got")
        fi
        if [[ "$got" == "$want" ]]; then
            pass "4: $id entitlements are exactly the release set ($(jq 'length' <<<"$got") keys)"
        else
            fail "4: $id entitlements differ from the release set:"$'\n'"$(diff <(echo "$want") <(echo "$got"))"
        fi
    done
}

# MARK: 5. Contents

check_5() {
    local bundle exe debug hits
    debug=$(find "$app" -name '*.debug.dylib' -print)
    if [[ -n "$debug" ]]; then
        fail "5: Debug build (debug dylib present): $debug"
    else
        pass "5: no debug dylib"
    fi
    for bundle in "${bundles[@]}"; do
        if exe=$(plist_get "$bundle/Contents/Info.plist" CFBundleExecutable); then
            check_no_test_hooks "5: $(basename "$bundle")" "$bundle/Contents/MacOS/$exe"
        else
            fail "5: no CFBundleExecutable in $(short "$bundle")"
        fi
    done
    if [[ "$flavour" == appstore ]]; then
        hits=$(grep -r -l -a -E "$forbidden" "$app" 2>/dev/null)
        if [[ -n "$hits" ]]; then
            fail "5: personal-package strings in the App Store flavour:"$'\n'"$hits"
        else
            pass "5: no personal-package strings in the App Store flavour"
        fi
    fi
    check_resource_bundle "5" "$app"
    check_help_book "5" "$app"
    hits=$(xattr -r -l "$app" 2>/dev/null | grep -F 'com.apple.quarantine')
    if [[ -n "$hits" ]]; then
        fail "5: com.apple.quarantine in the export:"$'\n'"$hits"
    else
        pass "5: no quarantine attributes"
    fi
}

for check in 1 2 3 4 5; do
    "check_$check"
done

if ((failures > 0)); then
    echo "$prefix: $failures check(s) failed" >&2
    exit 1
fi
if ((dev_signed)); then
    echo "$prefix: all checks passed (development-signed: identity and timestamp not required)"
else
    echo "$prefix: all checks passed"
fi
