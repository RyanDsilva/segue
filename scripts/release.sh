#!/usr/bin/env bash
# Mac App Store release pipeline (docs/release/specs/WS1-release-pipeline.md 4.7; rulings R12,
# R13, R46 in docs/release/decisions.md).
#
#   release.sh archive              archive Segue-AppStore (Release-AppStore), export the signed
#                                   .pkg, run scripts/verify-archive.sh. No credentials.
#   release.sh validate [--dry-run] archive (or reuse a verified one), then App Store Connect
#                                   validation with the API key from 1Password.
#   release.sh upload [--dry-run]   validate, upload that same .pkg, tag the source commit
#                                   (signed, local, never pushed), upload the dSYMs to Sentry.
#
# Outputs, per version and build from Config/Version.xcconfig (scripts/bump-version.sh):
#   .build/archives/Segue-<ver>-<build>.xcarchive
#   .build/archives/Segue-<ver>-<build>.provenance   commit and tree state it was built from
#   .build/export/Segue-<ver>-<build>/Segue.pkg
# `archive` refuses to rebuild an existing archive (make bump first, or trash it); if only
# the export is missing (an earlier export failed) it resumes from the archive. validate and
# upload reuse an existing archive and .pkg after re-running verify-archive on them, so
# `make archive && make validate && make upload` checks and ships one build.
#
# Credentials (R46): validate and upload read the API key with the 1Password CLI `op` and must
# run in Ryan's Terminal.app (op cannot reach the desktop app from an agent shell). There is
# no plaintext fallback. --dry-run (make validate DRY_RUN=1) does everything except reading
# the key, talking to App Store Connect, tagging and the dSYM upload, and prints the commands
# the real run would execute. 1Password item: SEGUE_ASC_OP_VAULT (default Private) /
# SEGUE_ASC_OP_ITEM (default "Segue ASC API Key") with fields key_id, issuer_id and the file
# attachment AuthKey.p8.
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck source=lib/discard.sh
source scripts/lib/discard.sh

team="V6BM673U35"
appstore_id="dev.ryandsilva.segue"
export_options="Config/ExportOptions-AppStore.plist"
buddy=/usr/libexec/PlistBuddy
# The [RYAN] steps live in docs/release/specs/WS1-release-pipeline.md section 3.
steps_doc="docs/release/specs/WS1-release-pipeline.md section 3"

die() {
    echo "release: error: $*" >&2
    exit 1
}
say() { echo "release: $*"; }

command_name="${1:-}"
dry_run=0
case "$command_name" in
archive) [[ $# -eq 1 ]] || die "usage: release.sh archive" ;;
validate | upload)
    shift
    for arg in "$@"; do
        case "$arg" in
        --dry-run) dry_run=1 ;;
        *) die "usage: release.sh $command_name [--dry-run]" ;;
        esac
    done
    ;;
*) die "usage: release.sh archive | validate [--dry-run] | upload [--dry-run]" ;;
esac

read -r marketing build < <(scripts/bump-version.sh show)
[[ -n "${marketing:-}" && -n "${build:-}" ]] || die "could not read the version (bump-version.sh show)"
name="Segue-$marketing-$build"
archive=".build/archives/$name.xcarchive"
provenance=".build/archives/$name.provenance"
export_dir=".build/export/$name"
pkg="$export_dir/Segue.pkg"
tag="v$marketing+$build"

# Scratch space for this run (temp export options, the API key). Removed file by file on
# exit; never under the repo.
scratch=$(mktemp -d "${TMPDIR:-/tmp}/segue-release.XXXXXX")
cleanup() {
    [[ -f "$scratch/AuthKey.p8" ]] && rm -f -P "$scratch/AuthKey.p8"
    find "$scratch" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT

# MARK: - Signing assets (export only; the archive signs automatically, B-1)

# installed_profile <name>: prints the path of an installed, unexpired provisioning profile
# with that exact Name for the team; fails when there is none.
installed_profile() {
    local want="$1" dir file decoded found="" now
    now=$(date -u +%s)
    for dir in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" \
        "$HOME/Library/MobileDevice/Provisioning Profiles"; do
        [[ -d "$dir" ]] || continue
        for file in "$dir"/*.provisionprofile; do
            [[ -f "$file" ]] || continue
            decoded="$scratch/profile.plist"
            security cms -D -i "$file" >"$decoded" 2>/dev/null || continue
            [[ "$("$buddy" -c "Print :Name" "$decoded" 2>/dev/null)" == "$want" ]] || continue
            "$buddy" -c "Print :TeamIdentifier" "$decoded" 2>/dev/null | grep -q -F "$team" || continue
            local expires
            expires=$(plutil -extract ExpirationDate raw -o - "$decoded" 2>/dev/null) || continue
            expires=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$expires" +%s 2>/dev/null) || continue
            ((expires > now)) || continue
            found="$file"
        done
    done
    [[ -n "$found" ]] || return 1
    echo "$found"
}

# require_identities: both distribution identities are in the keychain (R12).
require_identities() {
    security find-identity -v -p codesigning | grep -q -F "Apple Distribution: Ryan Rony Dsilva ($team)" \
        || die "no 'Apple Distribution: Ryan Rony Dsilva ($team)' identity in the keychain." \
            "Do [RYAN] step 3 (Apple Distribution certificate) in $steps_doc."
    local installer
    installer=$("$buddy" -c "Print :installerSigningCertificate" "$export_options")
    security find-identity -v | grep -q -F "$installer: Ryan Rony Dsilva ($team)" \
        || die "no '$installer: Ryan Rony Dsilva ($team)' identity in the keychain." \
            "Do [RYAN] step 4 (Mac Installer Distribution certificate) in $steps_doc."
    say "signing identities: Apple Distribution and Mac Installer Distribution present"
}

# profile_name_for <bundle id>: the profile ExportOptions names for that bundle.
profile_name_for() {
    "$buddy" -c "Print :provisioningProfiles:$1" "$export_options" 2>/dev/null
}

# require_profile <bundle id>: the profile for that bundle is installed.
require_profile() {
    local id="$1" profile path
    profile=$(profile_name_for "$id") \
        || die "$export_options has no provisioning profile for $id; add one (and its [RYAN] step) first"
    path=$(installed_profile "$profile") \
        || die "provisioning profile '$profile' (for $id) is not installed or has expired." \
            "Do [RYAN] step 6 (App IDs and profiles: '$profile') in $steps_doc, then double-click" \
            "the downloaded .provisionprofile."
    say "profile '$profile' for $id: $(basename "$path")"
}

# archive_bundle_ids: the app and every embedded extension in the archive.
archive_bundle_ids() {
    local app="$archive/Products/Applications/Segue.app" appex
    "$buddy" -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist"
    for appex in "$app"/Contents/PlugIns/*.appex; do
        [[ -d "$appex" ]] || continue
        "$buddy" -c "Print :CFBundleIdentifier" "$appex/Contents/Info.plist"
    done
}

# MARK: - Archive and export

build_archive() {
    local tmp_archive=".build/archives/.$name.partial.xcarchive"
    mkdir -p .build/archives
    discard "$tmp_archive"

    say "generating the workspace"
    mise exec -- tuist generate --no-open

    say "archiving Segue-AppStore (Release-AppStore) as $name"
    SEGUE_DESTINATION='generic/platform=macOS' SEGUE_DERIVED_DATA=.build/DerivedData-release \
        scripts/xcodebuild.sh \
        -scheme Segue-AppStore -configuration Release-AppStore \
        -archivePath "$tmp_archive" archive
    [[ -d "$tmp_archive" ]] || die "xcodebuild reported success but wrote no archive"
    mv "$tmp_archive" "$archive"

    local dirty
    dirty=$(git status --porcelain | wc -l | tr -d ' ')
    {
        echo "commit=$(git rev-parse HEAD)"
        echo "dirty_paths=$dirty"
        echo "built=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$provenance"
    if [[ "$dirty" != 0 ]]; then
        say "note: the working tree had $dirty uncommitted path(s) when archiving (see $provenance)"
    fi
}

export_pkg() {
    local tmp_export=".build/export/.$name.partial" options="$scratch/ExportOptions.plist" id
    discard "$tmp_export"
    mkdir -p .build/export

    # One profile per bundle that is actually in the archive (I-14): the Quick Look
    # extension's entry is dropped from a temp copy until WS2b embeds it.
    cp "$export_options" "$options"
    local -a present=()
    while IFS= read -r id; do present+=("$id"); done < <(archive_bundle_ids)
    local listed
    listed=$("$buddy" -c "Print :provisioningProfiles" "$options" \
        | sed -n -E 's/^[[:space:]]+([^[:space:]]+) = .*/\1/p')
    for id in $listed; do
        if [[ " ${present[*]} " != *" $id "* ]]; then
            "$buddy" -c "Delete :provisioningProfiles:$id" "$options"
            say "export options: no $id bundle in the archive, its profile entry is not used"
        fi
    done
    for id in "${present[@]}"; do
        require_profile "$id"
    done

    say "exporting the Mac App Store .pkg (manual signing)"
    xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$options" \
        -exportPath "$tmp_export"
    [[ -f "$tmp_export/Segue.pkg" ]] || die "export finished without $tmp_export/Segue.pkg"
    mv "$tmp_export" "$export_dir"
}

verify() {
    scripts/verify-archive.sh "$archive" "$pkg"
}

# ensure_archive <reuse>: produce (or, with reuse=1, reuse) a verified archive and .pkg.
ensure_archive() {
    local reuse="$1"
    if [[ -d "$archive" && -f "$pkg" ]]; then
        if [[ "$reuse" == 1 ]]; then
            say "reusing $archive and $pkg (built from $(sed -n 's/^commit=//p' "$provenance" 2>/dev/null || echo "an unknown commit"))"
            verify
            return
        fi
        die "$archive already exists for $marketing ($build). Run \`make bump\` for a new" \
            "build, or move the archive and $export_dir to the Trash to rebuild this one."
    fi
    require_identities
    require_profile "$appstore_id"
    if [[ -d "$archive" ]]; then
        say "resuming: $archive exists, exporting it"
    else
        [[ -e "$export_dir" ]] && die "$export_dir exists without its archive; move it to the Trash first"
        build_archive
    fi
    export_pkg
    verify
}

# MARK: - App Store Connect API key (R13, R46)

ensure_op() {
    if ! command -v op >/dev/null 2>&1; then
        die "the 1Password CLI (op) is not installed or not on PATH. Run this in Terminal.app" \
            "with 1Password installed (R46); there is no plaintext-key fallback."
    fi
    if ! op whoami >/dev/null 2>&1; then
        die "1Password CLI is not signed in. Unlock 1Password (and turn on Settings > Developer >" \
            "Integrate with 1Password CLI), then re-run in Terminal.app. Agent shells cannot use" \
            "op (R46)."
    fi
}

vault="${SEGUE_ASC_OP_VAULT:-Private}"
item="${SEGUE_ASC_OP_ITEM:-Segue ASC API Key}"
key_id=""
issuer=""
key_file="$scratch/AuthKey.p8"

load_api_key() {
    ensure_op
    op read --out-file "$key_file" --file-mode 0600 "op://$vault/$item/AuthKey.p8" >/dev/null \
        || die "could not read the AuthKey.p8 attachment from op://$vault/$item (see [RYAN] step 7)"
    key_id=$(op read "op://$vault/$item/key_id") || die "could not read key_id from op://$vault/$item"
    issuer=$(op read "op://$vault/$item/issuer_id") || die "could not read issuer_id from op://$vault/$item"
    [[ -n "$key_id" && -n "$issuer" && -s "$key_file" ]] || die "op://$vault/$item is incomplete"
    say "API key $key_id loaded from 1Password into a private temp file"
}

altool() {
    xcrun altool "$@" --api-key "$key_id" --api-issuer "$issuer" --p8-file-path "$key_file"
}

show_dry() {
    say "dry run: would run: $*"
}

# MARK: - Commands

run_validate() {
    if ((dry_run)); then
        show_dry "op read op://$vault/$item/{AuthKey.p8,key_id,issuer_id}"
        show_dry "xcrun altool --validate-app $pkg --api-key <key_id> --api-issuer <issuer_id> --p8-file-path <tmp>/AuthKey.p8"
        if command -v op >/dev/null 2>&1 && op whoami >/dev/null 2>&1; then
            say "dry run: op is signed in here"
        else
            say "dry run: op is not usable in this shell; the real run must be in Terminal.app (R46)"
        fi
        return
    fi
    [[ -n "$key_id" ]] || load_api_key
    say "validating $pkg with App Store Connect"
    altool --validate-app "$pkg"
    say "validation passed: $marketing ($build)"
}

upload_preflight() {
    git diff --quiet HEAD -- Config/Version.xcconfig \
        || die "Config/Version.xcconfig has uncommitted changes; commit it (make bump) first"
    git diff --cached --quiet || die "the index has staged changes; commit or unstage them first"
    if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
        die "tag $tag exists: build $build was already uploaded. Run \`make bump\` for a new build."
    fi
}

run_upload() {
    upload_preflight
    ((dry_run)) || ensure_op
    ensure_archive 1
    run_validate

    local commit
    commit=$(sed -n 's/^commit=//p' "$provenance" 2>/dev/null) || true
    [[ -n "$commit" ]] || die "no source commit recorded in $provenance"
    if ((dry_run)); then
        show_dry "xcrun altool --upload-package $pkg --api-key <key_id> --api-issuer <issuer_id> --p8-file-path <tmp>/AuthKey.p8 --wait"
        show_dry "git tag -s $tag -m \"App Store Connect upload $marketing ($build)\" $commit"
        scripts/upload-dsyms.sh --dry-run "$archive"
        return
    fi

    say "uploading $pkg (this waits for App Store Connect processing)"
    altool --upload-package "$pkg" --wait
    say "uploaded $marketing ($build) from commit $commit"

    local output
    if ! output=$(git tag -s "$tag" -m "App Store Connect upload $marketing ($build)" "$commit" 2>&1); then
        echo "$output" >&2
        if grep -q 'failed to fill whole buffer' <<<"$output"; then
            die "1Password is locked, so the tag could not be signed. Unlock it and run:" \
                "git tag -s $tag -m \"App Store Connect upload $marketing ($build)\" $commit" \
                "(never an unsigned tag), then make upload-dsyms ARCHIVE=$archive"
        fi
        die "could not create the signed tag $tag; create it by hand (signed) before anything else"
    fi
    say "tagged $tag (signed, local only; never pushed)"

    # dSYMs to Sentry (WS3 6.5). A failure here does not undo the App Store upload.
    if ! scripts/upload-dsyms.sh "$archive"; then
        die "the App Store upload and tag succeeded but the dSYM upload failed. Retry with:" \
            "make upload-dsyms ARCHIVE=$archive"
    fi
    say "done: $marketing ($build), commit $commit, tag $tag. Next: TestFlight ([RYAN] step 12)."
}

case "$command_name" in
archive) ensure_archive 0 ;;
validate)
    ((dry_run)) || ensure_op
    ensure_archive 1
    run_validate
    ;;
upload) run_upload ;;
esac
