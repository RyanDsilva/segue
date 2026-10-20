#!/usr/bin/env bash
# The user guide's captures (docs/release/specs/WS6-user-guide.md sections 5 and 6), from the
# App Store flavour on a clean Welcome library.
#
#   scripts/docs-shots.sh shots [id,id]   screenshots: the GuideShots UI tests in dark, then
#                                         light; scripts/docs-shots.swift writes the AVIFs
#                                         and guide/src/data/shots.json
#   scripts/docs-shots.sh clips [id,id]   clips: each GuideClips test recorded with
#                                         `screencapture -v`, cut to the storyboard, encoded
#                                         with ffmpeg (mise) to guide/public/clips/<id>.mp4
#
# Needs a logged-in session on a Retina display (the shots fail on a non-Retina capture) and,
# for clips, Screen Recording permission for the terminal ([RYAN], once). Never part of
# `make check`, `make gate` or CI. Make targets: `make docs-shots`, `make docs-clips`.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=lib/discard.sh
source scripts/lib/discard.sh

mode="${1:-}"
only="${2:-}"
out=".build/docs-shots"
# The window the tests place (GuideShotCase.windowFrame: 1280x800 pt at the top-left of the
# screen's visible area, clear of the menu bar and Dock), as a screencapture -R rect.
visible_rect() {
    osascript -l JavaScript -e 'ObjC.import("AppKit");
        const s = $.NSScreen.screens.objectAtIndex(0), f = s.frame, v = s.visibleFrame;
        Math.round(v.origin.x) + "," + Math.round(f.size.height - v.origin.y - v.size.height) + ",1280,800"'
}

run_tests() { # <appearance> <only-testing...>
    local appearance="$1"
    shift
    local bundle="$out/$appearance.xcresult"
    discard "$bundle"
    TEST_RUNNER_SEGUE_SHOT_APPEARANCE="$appearance" SEGUE_RESULT_BUNDLE="$bundle" \
        scripts/xcodebuild.sh -scheme Segue-AppStore -configuration Debug-AppStore \
        test-without-building "$@"
    discard "$out/raw-$appearance"
    xcrun xcresulttool export attachments --path "$bundle" \
        --output-path "$out/raw-$appearance" --schema-version 0.4.0 >/dev/null
}

build() {
    scripts/xcodebuild.sh -scheme Segue-AppStore -configuration Debug-AppStore build-for-testing
}

case "$mode" in
shots)
    mkdir -p "$out"
    build
    for appearance in dark light; do
        run_tests "$appearance" -only-testing:SegueAppStoreUITests/GuideShots
    done
    scripts/docs-shots.swift --raw "$out/raw-dark" --raw "$out/raw-light" \
        ${only:+--only "$only"}
    ;;
clips)
    mkdir -p "$out/clips"
    build
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
        discard "$raw"
        # Record long enough for the launch plus the storyboard; the test's clip-start and
        # clip-end markers (wall-clock times) then cut it to the storyboard.
        started=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
        screencapture -v -C -V 60 -R"$(visible_rect)" "$raw" &
        recorder=$!
        run_tests dark "-only-testing:SegueAppStoreUITests/GuideClips/$test"
        wait "$recorder" || true
        [[ -s "$raw" ]] || { echo "docs-clips: no recording for $id (Screen Recording permission?)" >&2; exit 1; }
        scripts/docs-clips-encode.sh "$raw" "$id" "$started" "$out/raw-dark"
    done
    ;;
*)
    echo "usage: scripts/docs-shots.sh shots|clips [id,id]" >&2
    exit 2
    ;;
esac
