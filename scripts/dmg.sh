#!/usr/bin/env bash
# Developer ID distribution (docs/release/decisions.md R200): a notarized, stapled DMG with a
# drag-to-Applications window, for either flavour.
#
#   dmg.sh personal [--dry-run]   the Personal build (dev.ryandsilva.segue.personal), for
#                                 Ryan's own Macs only; never shared
#   dmg.sh appstore [--dry-run]   the App Store flavour (dev.ryandsilva.segue), for friends
#
# Steps: archive (or reuse one), export with Config/ExportOptions-DeveloperID.plist (manual
# signing with the named Developer ID Application identity; hardened runtime and a secure
# timestamp on every binary), scripts/verify-developer-id.sh, notarize and staple the app,
# build the DMG around the stapled app (dmgbuild, scripts/lib/dmg-settings.py), sign it,
# notarize and staple it, then check it the way a receiving Mac does (stapler validate,
# spctl -t install on the DMG, spctl -t exec on the app inside it).
#
# Outputs, per marketing version and flavour:
#   .build/dist/Segue-<version>-<flavour>.dmg       plus .sha256 and the notary logs
#   .build/archives/Segue-<ver>-<build>.xcarchive   App Store flavour: the same archive
#                                                   scripts/release.sh uploads, reused if
#                                                   present
#   .build/archives/Segue-Personal-<ver>-<build>.xcarchive
#
# Credentials (R200): notarytool reads the keychain profile `segue-notary`, created once by
# Ryan in Terminal.app (docs/release/v1.0-readiness.md 2.12). No password or key ever passes
# through this script; a missing identity or profile stops it with the setup step.
#
# --dry-run proves everything but the notary service: it archives into
# .build/archives/dry-run (never reused by a real run), exports, verifies, builds and signs
# the DMG, skips notarizing and stapling, and shows that Gatekeeper rejects the result (as
# it must for an un-notarized DMG). With the Developer ID identity installed it exports
# and signs exactly as a real run; without it, it exports the archive's own Apple
# Development signature (method mac-application), verifies with the identity and timestamp
# relaxed, and signs the DMG with Apple Development. Output:
# .build/dist/Segue-<version>-<flavour>.dry-run.dmg, never shippable.
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck source=lib/discard.sh
source scripts/lib/discard.sh
# shellcheck source=lib/archive.sh
source scripts/lib/archive.sh

team="V6BM673U35"
identity="Developer ID Application: Ryan Rony Dsilva ($team)"
dev_identity_prefix="Apple Development: Ryan Rony Dsilva"
notary_profile="segue-notary"
export_options="Config/ExportOptions-DeveloperID.plist"
steps_doc="docs/release/v1.0-readiness.md section 2.12"
# dmgbuild and its two dependencies, pinned (all MIT).
dmgbuild=(mise exec -- uvx --quiet --from dmgbuild==1.6.7 --with ds-store==1.3.3 --with mac-alias==2.2.3 dmgbuild)

die() {
    echo "dmg: error: $*" >&2
    exit 1
}
say() { echo "dmg: $*"; }

usage() { die "usage: dmg.sh personal|appstore [--dry-run]"; }
[[ $# -ge 1 && $# -le 2 ]] || usage
flavour="$1"
dry_run=0
# 1 = export and sign with the Developer ID identity; a dry run without it clears this.
devid=1
if [[ $# -eq 2 ]]; then
    [[ "$2" == "--dry-run" ]] || usage
    dry_run=1
fi

read -r marketing build < <(scripts/bump-version.sh show)
[[ -n "${marketing:-}" && -n "${build:-}" ]] || die "could not read the version (bump-version.sh show)"

archives=".build/archives"
exports=".build/export"
derived=".build/DerivedData-release"
suffix=""
if ((dry_run)); then
    archives=".build/archives/dry-run"
    exports=".build/export/dry-run"
    derived=".build/DerivedData-dmg-dry-run"
    suffix=".dry-run"
fi
case "$flavour" in
personal)
    scheme="Segue-Personal"
    configuration="Release-Personal"
    app_id="dev.ryandsilva.segue.personal"
    archive_name="Segue-Personal-$marketing-$build"
    volume="Segue Personal $marketing (owner only)"
    ;;
appstore)
    scheme="Segue-AppStore"
    configuration="Release-AppStore"
    app_id="dev.ryandsilva.segue"
    # The name scripts/release.sh uses, so friends get the binary TestFlight gets.
    archive_name="Segue-$marketing-$build"
    volume="Segue $marketing"
    ;;
*) usage ;;
esac
archive="$archives/$archive_name.xcarchive"
provenance="$archives/$archive_name.provenance"
export_dir="$exports/Segue-$flavour-$marketing-$build-developer-id"
dist=".build/dist"
dmg="$dist/Segue-$marketing-$flavour$suffix.dmg"

scratch=$(mktemp -d "${TMPDIR:-/tmp}/segue-dmg.XXXXXX")
mounted=""
cleanup() {
    if [[ -n "$mounted" ]]; then
        hdiutil detach -quiet "$mounted" >/dev/null 2>&1 || hdiutil detach -quiet -force "$mounted" >/dev/null 2>&1 || true
    fi
    find "$scratch" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT

if [[ "$flavour" == personal ]]; then
    say "=================================================================="
    say " PERSONAL BUILD ($app_id): for Ryan's own Macs only."
    say " Never share it, upload it or hand it to a friend; friends get"
    say " \`make dmg FLAVOUR=appstore\`."
    say "=================================================================="
fi

# MARK: - Preflight (R200: fail clearly, with the exact setup step)

has_identity() {
    security find-identity -v -p codesigning | grep -q -F "\"$1"
}

# probe_signing: signs a scratch copy of /usr/bin/true with the identity. A new private
# key's first use waits on a keychain prompt (SecurityAgent) that an agent shell cannot
# answer, which would hang the export inside xcodebuild; this gives up after 20 s instead.
probe_signing() {
    local probe="$scratch/probe-signing" pid
    cp /usr/bin/true "$probe"
    codesign --force --sign "$identity" --timestamp=none "$probe" >/dev/null 2>&1 &
    pid=$!
    for _ in $(seq 1 40); do
        if ! kill -0 "$pid" 2>/dev/null; then
            wait "$pid"
            return
        fi
        sleep 0.5
    done
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 1
}

# notary_state: prints ok, missing or unusable (with notarytool's message on stderr).
notary_state() {
    local output
    if output=$(xcrun notarytool history --keychain-profile "$notary_profile" --output-format json 2>&1); then
        echo ok
    elif grep -q -i "No Keychain password item found" <<<"$output"; then
        echo missing
    else
        echo "$output" >&2
        echo unusable
    fi
}

notary_setup_hint() {
    echo "  In Terminal.app (not an agent shell), once per Mac:" >&2
    echo "    xcrun notarytool store-credentials $notary_profile --apple-id <your Apple ID email> --team-id $team" >&2
    echo "  It prompts for an app-specific password (account.apple.com > Sign-In and Security >" >&2
    echo "  App-Specific Passwords); see $steps_doc." >&2
}

preflight() {
    local problems=0 state
    if has_identity "$identity"; then
        if probe_signing; then
            say "preflight: signing identity '$identity' present and usable"
        else
            problems=1
            devid=0
            echo "dmg: preflight: '$identity' is installed, but signing with it waits on a keychain" >&2
            echo "  prompt (\"codesign wants to sign using key ... in your keychain\"). Allow it once:" >&2
            echo "  in Terminal.app run" >&2
            echo "    f=\$(mktemp) && cp /usr/bin/true \"\$f\" && codesign --force --sign \"$identity\" --timestamp=none \"\$f\"" >&2
            echo "  and answer the prompt with your login password and Always Allow (see $steps_doc)." >&2
        fi
    else
        problems=1
        devid=0
        echo "dmg: preflight: no '$identity' identity in the keychain." >&2
        echo "  Create it: Xcode > Settings > Accounts > your Apple Account > team Ryan Rony Dsilva >" >&2
        echo "  Manage Certificates... > + > Developer ID Application (see $steps_doc)." >&2
    fi
    state=$(notary_state)
    case "$state" in
    ok) say "preflight: notary keychain profile '$notary_profile' works" ;;
    missing)
        problems=1
        echo "dmg: preflight: no notarytool keychain profile '$notary_profile'." >&2
        notary_setup_hint
        ;;
    *)
        problems=1
        echo "dmg: preflight: the keychain profile '$notary_profile' exists but the notary service refused it" >&2
        echo "  (message above: offline, a revoked app-specific password, or an unsigned agreement in" >&2
        echo "  developer.apple.com > Account). To replace the password, re-run:" >&2
        notary_setup_hint
        ;;
    esac
    if ((problems)); then
        if ((dry_run)); then
            say "preflight: dry run continues without them; a real run stops here"
        else
            die "preflight failed; nothing was built. Do the step(s) above, then re-run."
        fi
    fi
}

# MARK: - Archive and export

ensure_archive() {
    if [[ -d "$archive" ]]; then
        local got_scheme got_version
        got_scheme=$(/usr/libexec/PlistBuddy -c "Print :SchemeName" "$archive/Info.plist" 2>/dev/null) || got_scheme=""
        got_version=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" "$archive/Info.plist" 2>/dev/null) || got_version=""
        [[ "$got_scheme" == "$scheme" && "$got_version" == "$build" ]] \
            || die "$archive is from scheme '$got_scheme' build '$got_version', not $scheme $build; move it to the Trash"
        say "reusing $archive (built from $(sed -n 's/^commit=//p' "$provenance" 2>/dev/null || echo "an unknown commit"))"
        return
    fi
    archive_build "$scheme" "$configuration" "$archive" "$provenance" "$derived"
}

export_app() {
    local tmp_export options="$export_options"
    tmp_export="$exports/.$(basename "$export_dir").partial"
    discard "$tmp_export" "$export_dir"
    mkdir -p "$exports"
    if ((!devid)); then
        # The archive as signed (Apple Development, hardened runtime): no Developer ID yet.
        options="$scratch/ExportOptions-dry-run.plist"
        plutil -create xml1 "$options"
        plutil -insert method -string mac-application "$options"
        plutil -insert destination -string export "$options"
        say "exporting the archive as signed (dry run: method mac-application)"
    else
        say "exporting with $export_options (manual signing, $identity)"
    fi
    xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$options" \
        -exportPath "$tmp_export"
    [[ -d "$tmp_export/Segue.app" ]] || die "export finished without $tmp_export/Segue.app"
    mv "$tmp_export" "$export_dir"
}

# MARK: - Notary service

# notarize FILE LOG: submit, wait, save Apple's log to LOG; fails unless Accepted. A log
# with issues (warnings) is shown even when Accepted.
notarize() {
    local file="$1" log="$2" output id status
    say "notarizing $(basename "$file") (waits for Apple; usually a few minutes)"
    output=$(xcrun notarytool submit "$file" --keychain-profile "$notary_profile" --wait \
        --output-format json) || true
    id=$(jq -r '.id // empty' <<<"$output" 2>/dev/null) || id=""
    status=$(jq -r '.status // empty' <<<"$output" 2>/dev/null) || status=""
    [[ -n "$id" ]] || die "notarytool submit gave no submission id: $output"
    xcrun notarytool log "$id" --keychain-profile "$notary_profile" "$log" >/dev/null \
        || say "warning: could not fetch the notary log for $id"
    if [[ "$status" != "Accepted" ]]; then
        [[ -s "$log" ]] && jq '.issues' "$log" >&2
        die "notarization of $(basename "$file") is '$status' (submission $id); log: $log"
    fi
    if [[ -s "$log" ]] && [[ "$(jq '.issues | length' "$log" 2>/dev/null || echo 0)" != 0 ]]; then
        say "notary accepted $(basename "$file") with issues:"
        jq '.issues' "$log"
    fi
    say "notarized: $(basename "$file") (submission $id)"
}

staple() {
    xcrun stapler staple "$1" >/dev/null || die "stapler could not staple $1"
    xcrun stapler validate "$1" >/dev/null || die "stapler validate failed on $1"
    say "stapled and validated: $(basename "$1")"
}

# MARK: - DMG

notice_text() {
    command cat <<EOF
PERSONAL BUILD: OWNER ONLY

This is Segue's Personal flavour ($app_id), version $marketing ($build).
It includes the Personal-only modules and is for Ryan's own Macs.
Do not share it, upload it or give it to anyone.

Friends get the App Store flavour: Segue-$marketing-appstore.dmg.
EOF
}

build_dmg() {
    local app="$1" out="$2" stage="$scratch/stage" notice_args=()
    mkdir -p "$stage" "$(dirname "$out")"
    ditto "$app" "$stage/Segue.app"
    if [[ "$flavour" == personal ]]; then
        notice_text >"$stage/Personal build - owner only.txt"
        notice_args=(-D "notice=$stage/Personal build - owner only.txt")
    fi
    discard "$out"
    say "building the DMG ($volume)"
    "${dmgbuild[@]}" -s scripts/lib/dmg-settings.py -D "app=$stage/Segue.app" \
        -D "icon=$stage/Segue.app/Contents/Resources/Segue.icns" "${notice_args[@]}" \
        "$volume" "$out" >/dev/null
    [[ -s "$out" ]] || die "dmgbuild wrote no $out"
}

sign_dmg() {
    local dmg_file="$1" signer="$identity" timestamp=(--timestamp)
    if ((!devid)); then
        signer=$(security find-identity -v -p codesigning | sed -n -E "s/.*\"(${dev_identity_prefix}[^\"]*)\".*/\1/p" | head -n 1)
        [[ -n "$signer" ]] || signer="-"
        timestamp=(--timestamp=none)
    fi
    codesign --force --sign "$signer" "${timestamp[@]}" "$dmg_file"
    codesign --verify --strict "$dmg_file" || die "the DMG's signature does not verify"
    say "signed the DMG with '$signer'"
}

# indent LABEL TEXT: prints each line of TEXT as "  LABEL: line".
indent() {
    local line
    while IFS= read -r line; do echo "  $1: $line"; done <<<"$2"
}

# check_gatekeeper DMG: what a receiving Mac checks. Real run: everything must pass. Dry
# run: the same commands, and an un-notarized DMG must be rejected.
check_gatekeeper() {
    local dmg_file="$1" output ok=1
    output=$(spctl -a -vvv -t install "$dmg_file" 2>&1) || ok=0
    indent "spctl install" "$output"
    mounted=$(hdiutil attach -nobrowse -readonly -noautoopen "$dmg_file" | sed -n -E 's|.*(/Volumes/.*)$|\1|p' | tail -n 1)
    [[ -n "$mounted" && -d "$mounted/Segue.app" ]] || die "could not mount $dmg_file or find Segue.app in it"
    local inner
    inner=$(spctl -a -vvv -t exec "$mounted/Segue.app" 2>&1) || ok=0
    indent "spctl exec (app in the DMG)" "$inner"
    [[ -L "$mounted/Applications" ]] || die "the DMG has no Applications link"
    if ((dry_run)); then
        hdiutil detach -quiet "$mounted" && mounted=""
        if ((ok)); then
            die "dry run: Gatekeeper accepted an un-notarized DMG; the check proves nothing"
        fi
        say "dry run: Gatekeeper rejects the un-notarized DMG, as it must"
        return
    fi
    xcrun stapler validate "$mounted/Segue.app" >/dev/null || ok=0
    hdiutil detach -quiet "$mounted" && mounted=""
    xcrun stapler validate "$dmg_file" >/dev/null || ok=0
    grep -q 'source=Notarized Developer ID' <<<"$output" || ok=0
    grep -q 'source=Notarized Developer ID' <<<"$inner" || ok=0
    ((ok)) || die "Gatekeeper or stapler rejected $dmg_file (see above)"
    say "Gatekeeper: DMG and app accepted as Notarized Developer ID, tickets stapled"
}

# MARK: - Run

preflight
ensure_archive
export_app
app="$export_dir/Segue.app"
verify_args=("$app" "$flavour")
((devid)) || verify_args+=(--development-signed)
scripts/verify-developer-id.sh "${verify_args[@]}"

mkdir -p "$dist"
logs="$dist/Segue-$marketing-$flavour$suffix"
if ((!dry_run)); then
    ditto -c -k --keepParent "$app" "$scratch/Segue.zip"
    notarize "$scratch/Segue.zip" "$logs.app-notary.json"
    staple "$app"
else
    say "dry run: would run: xcrun notarytool submit <Segue.zip> --keychain-profile $notary_profile --wait; xcrun stapler staple $app"
fi

partial="$dist/.$(basename "$dmg").partial.dmg"
build_dmg "$app" "$partial"
sign_dmg "$partial"
if ((!dry_run)); then
    notarize "$partial" "$logs.dmg-notary.json"
    staple "$partial"
else
    say "dry run: would run: xcrun notarytool submit $(basename "$dmg") --keychain-profile $notary_profile --wait; xcrun stapler staple $(basename "$dmg")"
fi
check_gatekeeper "$partial"

discard "$dmg"
mv "$partial" "$dmg"
(cd "$dist" && shasum -a 256 "$(basename "$dmg")" >"$(basename "$dmg").sha256")
say "done: $dmg ($(du -h "$dmg" | cut -f1 | tr -d ' '), sha256 $(cut -d' ' -f1 "$dmg.sha256"))"
if [[ "$flavour" == personal ]]; then
    say "PERSONAL BUILD: owner only. Install it on your own Macs; never share it."
fi
if ((dry_run)); then
    say "dry run: NOT notarized; never share $dmg"
fi
