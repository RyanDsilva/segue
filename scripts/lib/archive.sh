#!/usr/bin/env bash
# Shared by scripts/release.sh (the App Store .pkg) and scripts/dmg.sh (the Developer ID
# DMGs, R200) so both archive the same way. Source it from the repo root after
# scripts/lib/discard.sh and after defining `say` and `die`.
#
# archive_build SCHEME CONFIGURATION ARCHIVE PROVENANCE DERIVED_DATA
#   Generates the workspace, archives SCHEME in CONFIGURATION (signed automatically with
#   Apple Development, B-1; the export re-signs it) into a partial path, moves it to
#   ARCHIVE only when xcodebuild succeeded, and writes PROVENANCE: the commit, how many
#   paths were uncommitted, and when.
archive_build() {
    local scheme="$1" configuration="$2" archive="$3" provenance="$4" derived="$5"
    local tmp_archive
    tmp_archive="$(dirname "$archive")/.$(basename "$archive" .xcarchive).partial.xcarchive"
    mkdir -p "$(dirname "$archive")"
    discard "$tmp_archive"

    say "generating the workspace"
    mise exec -- tuist generate --no-open

    say "archiving $scheme ($configuration) as $(basename "$archive" .xcarchive)"
    SEGUE_DESTINATION='generic/platform=macOS' SEGUE_DERIVED_DATA="$derived" \
        scripts/xcodebuild.sh \
        -scheme "$scheme" -configuration "$configuration" \
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
