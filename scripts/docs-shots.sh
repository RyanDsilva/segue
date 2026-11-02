#!/usr/bin/env bash
# The user guide's captures (docs/release/specs/WS6-user-guide.md sections 5 and 6), from the
# App Store flavour on a clean Welcome library.
#
#   scripts/docs-shots.sh shots [id,id]   screenshots: the GuideShots UI tests in dark, then
#                                         light; scripts/docs-shots.swift writes the AVIFs
#                                         and guide/src/data/shots.json
#   scripts/docs-shots.sh clips [id,id]   clips: each GuideClips test recorded with ffmpeg
#                                         (scripts/lib/record.sh), cut to the storyboard, encoded
#                                         with ffmpeg (mise) to guide/public/clips/<id>.mp4
#
# Both run where E2E_RUNNER says (scripts/lib/capture.sh): `vm`, the Makefile default, in a
# throwaway Retina E2E VM clone, off the screen (the guest records its own screen); `host`
# on this Mac's screen (a Retina main display: the shots fail on a non-Retina capture;
# clips need Screen Recording permission for the terminal, [RYAN] once). Never part of
# `make check`, `make gate` or CI. Make targets: `make docs-shots`, `make docs-clips`.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=lib/discard.sh
source scripts/lib/discard.sh
# shellcheck source=lib/record.sh
source scripts/lib/record.sh
# shellcheck source=lib/capture.sh
source scripts/lib/capture.sh

mode="${1:-}"
only="${2:-}"
out=".build/docs-shots"

run_tests() { # <appearance> <only-testing...>
    local appearance="$1" status=0
    shift
    capture_run "$out/$appearance.xcresult" "$appearance" "$@" || status=$?
    # Exported even after a failure, so the shots that did pass can be looked at.
    [[ -d "$out/$appearance.xcresult" ]] && capture_export "$out/$appearance.xcresult" "$out/raw-$appearance"
    return "$status"
}

case "$mode" in
shots)
    mkdir -p "$out"
    capture_build
    for appearance in dark light; do
        run_tests "$appearance" -only-testing:SegueAppStoreUITests/GuideShots
    done
    scripts/docs-shots.swift --raw "$out/raw-dark" --raw "$out/raw-light" \
        ${only:+--only "$only"}
    ;;
clips)
    mkdir -p "$out/clips"
    capture_build
    for id in paste-a-song build-a-set go-on-stage; do
        case "$id" in
        paste-a-song) test=testPasteASong ;;
        build-a-set) test=testBuildASet ;;
        go-on-stage) test=testGoOnStage ;;
        esac
        if [[ -n "$only" && ",$only," != *",$id,"* ]]; then
            continue
        fi
        raw="$out/clips/$id.mov"
        # The recording starts with the app's first window; the test's clip-start and
        # clip-end markers (wall-clock times) then cut it to the storyboard.
        capture_record "$raw" 1280 800 1 "$out/dark.xcresult" dark \
            "-only-testing:SegueAppStoreUITests/GuideClips/$test"
        capture_export "$out/dark.xcresult" "$out/raw-dark"
        scripts/docs-clips-encode.sh "$raw" "$id" "$recorded_started" "$out/raw-dark"
    done
    ;;
*)
    echo "usage: scripts/docs-shots.sh shots|clips [id,id]" >&2
    exit 2
    ;;
esac
