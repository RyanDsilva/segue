#!/usr/bin/env bash
# The App Store screenshots and preview (docs/release/specs/WS5-store-listing.md sections 8
# and 9), from the App Store flavour on the screenshot library (Welcome songs plus the
# screenshot-only songs and "JamFest Opener").
#
#   scripts/store-shots.sh shots     AppStoreScreenshotTests in dark, then light; export;
#                                    compose with store/screenshots.json into
#                                    .build/screenshots/final/en-US/*.png (2880x1800, sRGB,
#                                    no alpha), the contact sheet and the A/B/C direction
#                                    samples; verify
#   scripts/store-shots.sh compose   compose and verify again from the last raw captures
#   scripts/store-shots.sh vm <Class/test>  re-capture selected shots only in the VM, dark and light,
#                                    into raw-vm-<appearance>, which compose prefers over
#                                    the full captures; then compose
#   scripts/store-shots.sh preview-edit  edit the last recording again (no capture)
#   scripts/store-shots.sh preview   record AppStorePreviewTests (scripts/lib/record.sh), cut
#                                    it to the test's markers and edit it with
#                                    scripts/make-preview.sh
#
# Both run where E2E_RUNNER says (scripts/lib/capture.sh): `vm`, the Makefile default, in a
# throwaway Retina 1920x1200 pt E2E VM clone, off the screen (the guest records its own
# screen for the preview); `host` on this Mac's screen (a Retina main display: the tests fail
# on any other capture size; the preview needs Screen Recording permission for the
# terminal, [RYAN] once). Never part of `make check`, `make gate` or CI. Make targets:
# `make screenshots`, `make preview`.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=lib/discard.sh
source scripts/lib/discard.sh
# shellcheck source=lib/record.sh
source scripts/lib/record.sh
# shellcheck source=lib/capture.sh
source scripts/lib/capture.sh

mode="${1:-}"
out=".build/screenshots"

run_tests() { # <bundle> <appearance> <only-testing>
    capture_run "$1" "$2" "-only-testing:$3"
}

export_attachments() { # <bundle> <folder>
    capture_export "$1" "$2"
}

compose() {
    discard "$out/final"
    local vm_raw=()
    for appearance in dark light; do
        [[ -d "$out/raw-vm-$appearance" ]] && vm_raw+=(--raw "$out/raw-vm-$appearance")
    done
    scripts/compose-screenshots.swift --raw "$out/raw-dark" --raw "$out/raw-light" ${vm_raw[@]+"${vm_raw[@]}"} \
        --captions store/screenshots.json --tokens design/tokens.json \
        --fonts Packages/SegueUI/Sources/SegueUI/Theme/Fonts \
        --out "$out/final" --contact-sheet "$out/contact-sheet.png" \
        --directions "$out/directions"
    scripts/compose-screenshots.swift --verify "$out/final"
}

case "$mode" in
shots)
    mkdir -p "$out"
    capture_build
    # A full capture replaces any earlier per-shot re-captures.
    discard "$out/raw-vm-dark" "$out/raw-vm-light"
    for appearance in dark light; do
        run_tests "$out/$appearance.xcresult" "$appearance" \
            SegueAppStoreUITests/AppStoreScreenshotTests
        export_attachments "$out/$appearance.xcresult" "$out/raw-$appearance"
    done
    compose
    ;;
compose)
    compose
    ;;
vm)
    test="${2:?usage: scripts/store-shots.sh vm <Class/test>, e.g. AppStoreScreenshotTests/test10Songbook}"
    capture_runner=vm
    capture_build
    for appearance in dark light; do
        run_tests "$out/vm-$appearance.xcresult" "$appearance" "SegueAppStoreUITests/$test"
        export_attachments "$out/vm-$appearance.xcresult" "$out/raw-vm-$appearance"
    done
    compose
    ;;
preview)
    preview=".build/preview"
    mkdir -p "$preview"
    capture_build
    # The stage and builder windows the test places: 1440x810 pt (16:9) at the top-left of
    # the screen's visible area. The whole run is recorded, no pointer; the test's markers
    # cut it to the storyboard.
    raw="$preview/raw.mov"
    capture_record "$raw" 1440 810 0 "$preview/run.xcresult" dark \
        -only-testing:SegueAppStoreUITests/AppStorePreviewTests
    export_attachments "$preview/run.xcresult" "$preview/attachments"
    marker() { # <name>: the marker's epoch time from the exported attachments
        local file
        # shellcheck disable=SC2016 # $name is a jq variable
        file=$(mise exec -- jq -r --arg name "$1" \
            '[.[].attachments[] | select(.suggestedHumanReadableName | startswith($name))][0].exportedFileName' \
            "$preview/attachments/manifest.json")
        [[ -n "$file" && "$file" != null ]] || { echo "store-shots: no $1 marker" >&2; exit 1; }
        tr -d '[:space:]' <"$preview/attachments/$file"
    }
    start=$(marker clip-start)
    end=$(marker clip-end)
    # The cut, kept for `make preview-edit` (re-edit without re-recording).
    printf '%s %s\n' "$(perl -e "printf '%.3f', $start - $recorded_started")" \
        "$(perl -e "printf '%.3f', $end - $start")" >"$preview/cut.txt"
    # Caption timings from the scene markers (scene-<caption id>), relative to clip-start.
    mise exec -- jq -r '.previewCaptions[].id' store/screenshots.json >"$preview/ids.txt"
    : >"$preview/timings.txt"
    previous="" previous_at=""
    while read -r id; do
        at=$(perl -e "printf '%.3f', $(marker "scene-$id") - $start")
        [[ -z "$previous" ]] || echo "$previous $previous_at $at" >>"$preview/timings.txt"
        previous="$id" previous_at="$at"
    done <"$preview/ids.txt"
    echo "$previous $previous_at $(perl -e "printf '%.3f', $end - $start")" >>"$preview/timings.txt"
    read -r from length <"$preview/cut.txt"
    scripts/make-preview.sh "$raw" "$from" "$length" "$preview/timings.txt"
    ;;
preview-edit)
    # Edit again from the last recording (.build/preview/raw.mov and its cut); for a manual
    # QuickTime take (WS5 9.3), save it as raw.mov and write "<from> <length>" to cut.txt.
    read -r from length <.build/preview/cut.txt
    scripts/make-preview.sh .build/preview/raw.mov "$from" "$length" .build/preview/timings.txt
    ;;
*)
    echo "usage: scripts/store-shots.sh shots|compose|vm <Class/test>|preview|preview-edit" >&2
    exit 2
    ;;
esac
