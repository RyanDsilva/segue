#!/usr/bin/env bash
# Release gate for the Mac App Store build (docs/release/specs/WS1-release-pipeline.md 4.7,
# checks 1-13; check 14 is WS3's vendor check). Checks the archive and the exact .pkg that
# scripts/release.sh uploads.
#
#   scripts/verify-archive.sh <xcarchive> <pkg>
#
# Fails closed: an unreadable input or tool output is a failure, never a pass. Prints ok:/FAIL:
# lines like verify-appstore.sh and exits 1 on any failure.
#
# "Bundles" are the app plus every Contents/PlugIns/*.appex. The only allowed extensions are the
# Quick Look preview dev.ryandsilva.segue.quicklook (I-14, built by WS2b) and the Finder
# thumbnails dev.ryandsilva.segue.thumbnail (P9-5 P3), each with its own profile. Gig Mode confirmation runs through Shortcuts Events (Path SE, docs/release/decisions.md
# R59): the app's allowed entitlements include the Apple-events pair (`app_entitlements` in
# scripts/lib/verify-common.sh) and NSAppleEventsUsageDescription is required.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

prefix="verify-archive"
# shellcheck source=lib/verify-common.sh
source scripts/lib/verify-common.sh

team="V6BM673U35"
app_id="dev.ryandsilva.segue"
appex_id="dev.ryandsilva.segue.quicklook"
thumbnail_id="dev.ryandsilva.segue.thumbnail"
app_profile="Segue Mac App Store"
appex_profile="Segue Mac App Store QuickLook"
thumbnail_profile="Segue Mac App Store Thumbnail"
copyright="© 2026 Ryan Rony Dsilva"
buddy=/usr/libexec/PlistBuddy

if [[ $# -ne 2 ]]; then
    echo "usage: scripts/verify-archive.sh <xcarchive> <pkg>" >&2
    exit 2
fi
archive="$1"
pkg="$2"

if [[ ! -r "$archive/Info.plist" || ! -d "$archive/Products/Applications/Segue.app" ]]; then
    fail "inputs: $archive is not a readable Segue archive"
fi
if [[ ! -r "$pkg" ]]; then
    fail "inputs: cannot read $pkg"
fi
if ((failures > 0)); then
    echo "verify-archive: cannot continue" >&2
    exit 1
fi

scratch=$(mktemp -d "${TMPDIR:-/tmp}/segue-verify-archive.XXXXXX")
trap 'find "$scratch" -depth -delete 2>/dev/null || true' EXIT

archive_app="$archive/Products/Applications/Segue.app"

# Expand the pkg so every check reads exactly what gets uploaded.
app=""
if pkgutil --expand-full "$pkg" "$scratch/pkg" >/dev/null 2>&1; then
    app=$(find "$scratch/pkg" -maxdepth 4 -type d -name Segue.app -path '*/Payload/*' | head -n 1)
fi
if [[ -z "$app" || ! -d "$app" ]]; then
    fail "inputs: could not expand $pkg or find Segue.app in its payload"
    echo "verify-archive: cannot continue" >&2
    exit 1
fi
pass "inputs: expanded $(basename "$pkg")"

# The bundles in the pkg (app first) and every Mach-O file in them.
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
if ((${#machos[@]} == 0)); then
    fail "inputs: no Mach-O files found in the app"
fi

plist_get() { "$buddy" -c "Print :$2" "$1" 2>/dev/null; }
bundle_id() { plist_get "$1/Contents/Info.plist" CFBundleIdentifier; }
main_binary() {
    local exe
    exe=$(plist_get "$1/Contents/Info.plist" CFBundleExecutable) || return 1
    echo "$1/Contents/MacOS/$exe"
}
short() { echo "${1#"$scratch/pkg/"}"; }

# MARK: 1. Right product

check_1() {
    local id scheme ok=1
    id=$(plist_get "$archive/Info.plist" ApplicationProperties:CFBundleIdentifier)
    scheme=$(plist_get "$archive/Info.plist" SchemeName)
    [[ "$id" == "$app_id" ]] || { fail "1: archive ApplicationProperties.CFBundleIdentifier is '$id'"; ok=0; }
    [[ "$scheme" == "Segue-AppStore" ]] || { fail "1: archive SchemeName is '$scheme'"; ok=0; }
    [[ "$(bundle_id "$archive_app")" == "$app_id" ]] || { fail "1: archive app is not $app_id"; ok=0; }
    [[ "$(bundle_id "$app")" == "$app_id" ]] || { fail "1: pkg app is not $app_id"; ok=0; }
    local bundle
    for bundle in "${bundles[@]:1}"; do
        id=$(bundle_id "$bundle")
        [[ "$id" == "$appex_id" || "$id" == "$thumbnail_id" ]] \
            || { fail "1: unexpected extension $(short "$bundle") ($id)"; ok=0; }
    done
    ((ok)) && pass "1: $app_id from Segue-AppStore, $((${#bundles[@]} - 1)) extension(s)"
}

# MARK: 2. No personal code

check_2() {
    local hits bundle binary symbol_hits=""
    hits=$(grep -r -l -a -E "$forbidden" "$app" 2>/dev/null)
    if [[ -n "$hits" ]]; then
        fail "2: personal-package strings in:"$'\n'"$hits"
    else
        pass "2: no personal-package strings anywhere in the bundles"
    fi
    for binary in "${machos[@]}"; do
        if ! nm -a "$binary" >"$scratch/nm" 2>/dev/null || ! otool -L "$binary" >"$scratch/otool" 2>/dev/null; then
            fail "2: cannot read symbols or libraries of $(short "$binary")"
            continue
        fi
        if grep -E -q "$forbidden" "$scratch/nm" "$scratch/otool"; then
            symbol_hits+="$(short "$binary")"$'\n'
        fi
    done
    if [[ -n "$symbol_hits" ]]; then
        fail "2: personal-package symbols or linked libraries in:"$'\n'"$symbol_hits"
    else
        pass "2: no personal-package symbols or linked libraries"
    fi
}

# MARK: 3. Not a Debug build, no test hooks

check_3() {
    local debug bundle binary
    debug=$(find "$app" -name '*.debug.dylib' -print)
    if [[ -n "$debug" ]]; then
        fail "3: Debug build (debug dylib present): $debug"
    else
        pass "3: no debug dylib"
    fi
    for bundle in "${bundles[@]}"; do
        if binary=$(main_binary "$bundle"); then
            check_no_test_hooks "3: $(basename "$bundle")" "$binary"
        else
            fail "3: no CFBundleExecutable in $(short "$bundle")"
        fi
    done
}

# MARK: 4. Entitlements exact

# expected_entitlements <bundle id>: the exact signed set as sorted JSON.
expected_entitlements() {
    local id="$1"
    if [[ "$id" == "$app_id" ]]; then
        app_entitlements | jq -S --arg app "$team.$id" --arg team "$team" '. + {
            "com.apple.application-identifier": $app,
            "com.apple.developer.team-identifier": $team
        }'
    else
        jq -n -S --arg app "$team.$id" --arg team "$team" '{
            "com.apple.security.app-sandbox": true,
            "com.apple.application-identifier": $app,
            "com.apple.developer.team-identifier": $team
        }'
    fi
}

check_4() {
    local bundle id want got
    for bundle in "${bundles[@]}"; do
        id=$(bundle_id "$bundle")
        if ! codesign -d --entitlements - --xml "$bundle" >"$scratch/ent.plist" 2>/dev/null \
            || ! got=$(plutil -convert json -o - "$scratch/ent.plist" 2>/dev/null | jq -S .) \
            || [[ -z "$got" ]]; then
            fail "4: cannot read the signed entitlements of $(short "$bundle")"
            continue
        fi
        want=$(expected_entitlements "$id")
        if [[ "$got" == "$want" ]]; then
            pass "4: $id entitlements are exactly the allowed set ($(jq 'length' <<<"$got") keys)"
        else
            fail "4: $id entitlements differ from the allowed set:"$'\n'"$(diff <(echo "$want") <(echo "$got"))"
        fi
    done
}

# MARK: 5. Signatures

check_5() {
    local bundle info authority teamid sig
    if codesign --verify --deep --strict "$app" 2>"$scratch/verify.txt"; then
        pass "5: codesign --verify --deep --strict"
    else
        fail "5: codesign --verify failed: $(command cat "$scratch/verify.txt")"
    fi
    for bundle in "${bundles[@]}"; do
        if ! info=$(codesign -dvv "$bundle" 2>&1); then
            fail "5: cannot read the signature of $(short "$bundle")"
            continue
        fi
        authority=$(sed -n 's/^Authority=//p' <<<"$info" | head -n 1)
        teamid=$(sed -n 's/^TeamIdentifier=//p' <<<"$info")
        if [[ "$authority" == "Apple Distribution: "* && "$teamid" == "$team" ]]; then
            pass "5: $(basename "$bundle") signed by $authority"
        else
            fail "5: $(basename "$bundle") signed by '$authority' (team '$teamid')"
        fi
    done
    if sig=$(pkgutil --check-signature "$pkg" 2>&1) \
        && grep -q -E "(3rd Party Mac Developer Installer|Mac Installer Distribution): .*\\($team\\)" <<<"$sig"; then
        pass "5: pkg signed by $(grep -o -E '(3rd Party Mac Developer Installer|Mac Installer Distribution): [^)]*\)' <<<"$sig" | head -n 1)"
    else
        fail "5: pkg is not signed with the Mac Installer Distribution identity:"$'\n'"$sig"
    fi
}

# MARK: 6. Profiles

check_6() {
    local bundle id want profile name expires now
    now=$(date -u +%s)
    for bundle in "${bundles[@]}"; do
        id=$(bundle_id "$bundle")
        case "$id" in
            "$app_id") want="$app_profile" ;;
            "$thumbnail_id") want="$thumbnail_profile" ;;
            *) want="$appex_profile" ;;
        esac
        profile="$scratch/profile-$id.plist"
        if ! security cms -D -i "$bundle/Contents/embedded.provisionprofile" >"$profile" 2>/dev/null; then
            fail "6: $id has no readable Contents/embedded.provisionprofile"
            continue
        fi
        local problems=""
        name=$(plist_get "$profile" Name)
        [[ "$name" == "$want" ]] || problems+="Name '$name' (want '$want'); "
        plist_get "$profile" TeamIdentifier | grep -q -F "$team" || problems+="TeamIdentifier lacks $team; "
        [[ "$(plist_get "$profile" Entitlements:com.apple.application-identifier)" == "$team.$id" ]] \
            || problems+="application-identifier does not match $team.$id; "
        expires=$(plutil -extract ExpirationDate raw -o - "$profile" 2>/dev/null)
        expires=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$expires" +%s 2>/dev/null) || expires=0
        ((expires > now)) || problems+="expired or unreadable ExpirationDate; "
        plist_get "$profile" ProvisionedDevices >/dev/null && problems+="has ProvisionedDevices (not a distribution profile); "
        if [[ -n "$problems" ]]; then
            fail "6: $id profile: $problems"
        else
            pass "6: $id embeds '$name', valid until $(plutil -extract ExpirationDate raw -o - "$profile")"
        fi
    done
}

# MARK: 7. Version sanity

check_7() {
    local marketing build ok=1 where plist v b bundle
    if ! read -r marketing build < <(scripts/bump-version.sh show) || [[ -z "${build:-}" ]]; then
        fail "7: cannot read Config/Version.xcconfig"
        return
    fi
    [[ "$marketing" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || { fail "7: MARKETING_VERSION '$marketing'"; ok=0; }
    [[ "$build" =~ ^[0-9]+$ ]] || { fail "7: CURRENT_PROJECT_VERSION '$build'"; ok=0; }
    v=$(plist_get "$archive/Info.plist" ApplicationProperties:CFBundleShortVersionString)
    b=$(plist_get "$archive/Info.plist" ApplicationProperties:CFBundleVersion)
    [[ "$v" == "$marketing" && "$b" == "$build" ]] || { fail "7: archive Info.plist says $v ($b)"; ok=0; }
    for bundle in "$archive_app" "$archive_app"/Contents/PlugIns/*.appex "${bundles[@]}"; do
        [[ -d "$bundle" ]] || continue
        plist="$bundle/Contents/Info.plist"
        where=$(short "$bundle")
        v=$(plist_get "$plist" CFBundleShortVersionString)
        b=$(plist_get "$plist" CFBundleVersion)
        [[ "$v" == "$marketing" && "$b" == "$build" ]] || { fail "7: $where is $v ($b)"; ok=0; }
    done
    ((ok)) && pass "7: $marketing ($build) in the xcconfig, archive, pkg and every bundle"
}

# MARK: 8. Info.plist keys

check_8() {
    local plist="$app/Contents/Info.plist" problems="" value
    value=$(plist_get "$plist" ITSAppUsesNonExemptEncryption)
    [[ "$value" == "false" ]] || problems+="ITSAppUsesNonExemptEncryption='$value'; "
    value=$(plist_get "$plist" LSApplicationCategoryType)
    [[ "$value" == "public.app-category.music" ]] || problems+="LSApplicationCategoryType='$value'; "
    value=$(plist_get "$plist" NSHumanReadableCopyright)
    [[ "$value" == "$copyright" ]] || problems+="NSHumanReadableCopyright='$value'; "
    value=$(plist_get "$plist" LSMinimumSystemVersion)
    [[ "$value" == "26.0" ]] || problems+="LSMinimumSystemVersion='$value'; "
    value=$(plist_get "$plist" CFBundleDisplayName)
    [[ "$value" == "Segue" ]] || problems+="CFBundleDisplayName='$value'; "
    plist_get "$plist" NSMainStoryboardFile >/dev/null && problems+="NSMainStoryboardFile present; "
    value=$(plist_get "$plist" NSAppleEventsUsageDescription)
    [[ -n "$value" ]] || problems+="NSAppleEventsUsageDescription missing (Path SE, R59); "
    if [[ ! -r "$plist" ]]; then
        fail "8: cannot read $plist"
    elif [[ -n "$problems" ]]; then
        fail "8: Info.plist: $problems"
    else
        pass "8: Info.plist keys (encryption, category, copyright, minimum OS, display name, Apple events)"
    fi
    check_resource_bundle "8" "$app"
    check_third_party_notices "8" "$app"
    check_sound_bank "8" "$app"
    # The offline Help Book with every in-app Help anchor (P9-5 3.3).
    check_help_book "8" "$app"
}

# MARK: 9. Privacy manifest

check_9() {
    local manifest="$app/Contents/Resources/PrivacyInfo.xcprivacy" declared binary
    if [[ ! -f "$manifest" ]] || ! plutil -lint "$manifest" >/dev/null 2>&1; then
        fail "9: Contents/Resources/PrivacyInfo.xcprivacy missing or invalid"
        return
    fi
    if ! declared=$(plutil -convert json -o - "$manifest" \
        | jq -r '.NSPrivacyAccessedAPITypes[]?.NSPrivacyAccessedAPIType' 2>/dev/null); then
        fail "9: cannot read NSPrivacyAccessedAPITypes"
        return
    fi
    : >"$scratch/undefined"
    for binary in "${machos[@]}"; do
        if ! nm -u "$binary" >>"$scratch/undefined" 2>/dev/null; then
            fail "9: cannot read undefined symbols of $(short "$binary")"
            return
        fi
    done
    local -a categories=(UserDefaults FileTimestamp SystemBootTime DiskSpace ActiveKeyboards)
    local -a patterns=(
        'NSUserDefaults'
        'NSURLContentModificationDateKey|NSURLCreationDateKey|NSFileModificationDate|NSFileCreationDate|^_f?stat$|^_lstat$|^_fstatat$|^_getattrlist|^_fgetattrlist'
        '^_mach_absolute_time$|systemUptime'
        '^_f?statv?fs$|NSFileSystemFreeSize|NSFileSystemSize|NSURLVolumeAvailableCapacity'
        'activeInputModes'
    )
    local i category used ok=1
    # nm -u prints one symbol per line, possibly indented; strip to the bare name.
    sed -E 's/^[[:space:]]+//' "$scratch/undefined" | sort -u >"$scratch/symbols"
    for i in "${!categories[@]}"; do
        category="NSPrivacyAccessedAPICategory${categories[i]}"
        used=$(grep -E "${patterns[i]}" "$scratch/symbols" | head -n 3 | tr '\n' ' ')
        if [[ -n "$used" ]] && ! grep -q -x -F "$category" <<<"$declared"; then
            fail "9: $category used ($used) but not declared"
            ok=0
        elif [[ -z "$used" ]] && grep -q -x -F "$category" <<<"$declared"; then
            echo "verify-archive: warning: 9: $category declared but no matching symbol found"
        fi
    done
    ((ok)) && pass "9: privacy manifest valid and covers every required-reason API the binaries use"
}

# MARK: 10. Icons

check_10() {
    local icns="$app/Contents/Resources/Segue.icns" size missing=""
    if ! iconutil -c iconset -o "$scratch/Segue.iconset" "$icns" >/dev/null 2>&1; then
        fail "10: cannot read Contents/Resources/Segue.icns"
    else
        for size in 16x16 16x16@2x 32x32 32x32@2x 128x128 128x128@2x 256x256 256x256@2x \
            512x512 512x512@2x; do
            [[ -f "$scratch/Segue.iconset/icon_$size.png" ]] || missing+="$size "
        done
        if [[ -n "$missing" ]]; then
            fail "10: Segue.icns lacks: $missing"
        else
            pass "10: Segue.icns has all ten sizes (16 through 512@2x)"
        fi
    fi
    local widths
    if ! widths=$(xcrun assetutil --info "$app/Contents/Resources/Assets.car" 2>/dev/null \
        | jq -r '.[] | select(.AssetType == "Icon Image" and .Name == "Segue") | .PixelWidth'); then
        fail "10: cannot read Assets.car"
        return
    fi
    if grep -q -x 512 <<<"$widths" && grep -q -x 1024 <<<"$widths"; then
        pass "10: Assets.car has app-icon renditions at 512 and 1024 px"
    else
        fail "10: Assets.car app-icon renditions lack 512 or 1024 px (have: $(tr '\n' ' ' <<<"$widths"))"
    fi
}

# MARK: 11. Architectures

check_11() {
    local binary archs bad=""
    for binary in "${machos[@]}"; do
        archs=$(lipo -archs "$binary" 2>/dev/null) || archs="unreadable"
        [[ "$archs" == "arm64" ]] || bad+="$(short "$binary"): $archs"$'\n'
    done
    if [[ -n "$bad" ]]; then
        fail "11: not arm64-only:"$'\n'"$bad"
    else
        pass "11: all ${#machos[@]} Mach-O file(s) are arm64 only"
    fi
}

# MARK: 12. Quarantine

check_12() {
    local hits
    hits=$( (xattr -r -l "$app" "$archive_app"; xattr -l "$pkg") 2>/dev/null | grep -F 'com.apple.quarantine')
    if [[ -n "$hits" ]]; then
        fail "12: com.apple.quarantine found:"$'\n'"$hits"
    else
        pass "12: no quarantine attributes in the app, archive or pkg"
    fi
}

# MARK: 13. dSYM

check_13() {
    local bundle binary dsym want got name
    for bundle in "${bundles[@]}"; do
        name=$(basename "$bundle")
        dsym="$archive/dSYMs/$name.dSYM"
        binary=$(main_binary "$bundle") || { fail "13: no executable in $name"; continue; }
        if [[ ! -d "$dsym" ]]; then
            fail "13: missing dSYMs/$name.dSYM"
            continue
        fi
        want=$(dwarfdump --uuid "$binary" 2>/dev/null | awk '{print $2}' | sort)
        got=$(dwarfdump --uuid "$dsym" 2>/dev/null | awk '{print $2}' | sort)
        if [[ -n "$want" && "$want" == "$got" ]]; then
            pass "13: dSYMs/$name.dSYM matches the binary ($(tr '\n' ' ' <<<"$want"))"
        else
            fail "13: dSYMs/$name.dSYM UUIDs '$got' do not match the binary's '$want'"
        fi
    done
}

# MARK: 14. Hosted services (WS3 spec 3.7)

# The App Store TelemetryDeck App ID, read from its one source (Project.swift).
expected_telemetry_app_id() {
    sed -n -E 's/^let telemetryDeckAppIDAppStore = "([0-9A-Fa-f-]+)"$/\1/p' Project.swift
}

check_14() {
    local plist="$app/Contents/Info.plist" dsn host app_id expected binary ok=1
    dsn=$(plist_get "$plist" SegueSentryDSN)
    if [[ ! "$dsn" =~ ^https://[0-9a-f]+@([a-z0-9.-]+)/[0-9]+$ ]]; then
        fail "14: SegueSentryDSN '$dsn' is not a Sentry DSN"
        ok=0
    else
        host="${BASH_REMATCH[1]}"
        if [[ "$host" != *.sentry.io || "$host" == *.de.* ]]; then
            fail "14: Sentry host '$host' is not the US region (R33)"
            ok=0
        fi
    fi
    app_id=$(plist_get "$plist" SegueTelemetryDeckAppID)
    expected=$(expected_telemetry_app_id)
    if [[ -z "$expected" ]]; then
        fail "14: cannot read telemetryDeckAppIDAppStore from Project.swift"
        ok=0
    elif [[ ! "$app_id" =~ ^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$ \
        || "$app_id" != "$expected" ]]; then
        fail "14: SegueTelemetryDeckAppID '$app_id' is not the App Store app's ($expected)"
        ok=0
    fi
    if ! binary=$(main_binary "$app"); then
        fail "14: no app executable"
        return
    fi
    # A stripped Release binary keeps Swift type names in its metadata and ObjC class names
    # as strings, so read both the symbol table and the raw bytes.
    if ! nm -a "$binary" >"$scratch/nm14" 2>/dev/null; then
        fail "14: cannot read the symbols of $(short "$binary")"
        return
    fi
    local name
    for name in SentrySDK TelemetryDeckIngestSink; do
        if ! grep -q -F "$name" "$scratch/nm14" && ! grep -q -a -F "$name" "$binary"; then
            fail "14: $name is not in the app binary (vendor services not linked)"
            ok=0
        fi
    done
    # Our own ingest client only (R34): no TelemetryDeck SDK module (mangled `13TelemetryDeck`)
    # and no TelemetryClient.
    if grep -q -E '13TelemetryDeck|TelemetryClient' "$scratch/nm14" \
        || grep -q -a -E '13TelemetryDeck[A-Z0-9_]|TelemetryClient' "$binary"; then
        fail "14: the TelemetryDeck SDK is linked (R34 forbids it)"
        ok=0
    fi
    ((ok)) && pass "14: US Sentry DSN, App Store TelemetryDeck app, Sentry and our ingest client linked, no TelemetryDeck SDK"
}

for check in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do
    "check_$check"
done

if ((failures > 0)); then
    echo "verify-archive: $failures check(s) failed" >&2
    exit 1
fi
echo "verify-archive: all checks passed"
