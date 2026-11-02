#!/usr/bin/env bash
# Shared by scripts/docs-shots.sh (guide shots and clips) and scripts/store-shots.sh (App
# Store screenshots and preview): runs the App Store flavour's capture tests in one
# appearance, on the runner E2E_RUNNER picks. Source it from the repo root, after
# scripts/lib/discard.sh and scripts/lib/record.sh.
#
#   E2E_RUNNER=vm (the Makefile default)  a throwaway Tart clone with a Retina 1920x1200 pt
#       display (scripts/e2e-vm.sh, E2E_VM_HIDPI), off the screen; the products are built
#       here once (capture_build) and staged for each run
#   E2E_RUNNER=host                       this Mac's screen, as before (needs a Retina main
#       display and takes the pointer and keyboard)
#
#   capture_build
#   capture_run <bundle.xcresult> <dark|light> -only-testing:SegueAppStoreUITests/...
#   capture_export <bundle.xcresult> <folder>   the attachments and their manifest.json
#   capture_record <movie.mov> <width> <height> <cursor 0|1> <bundle> <appearance> \
#                  -only-testing:...
#       capture_run while recording the app's windows in a <width>x<height> pt rectangle at
#       the top-left of the screen's visible area (scripts/record-app.swift); then
#       `recorded_started` holds the first frame's wall-clock time on the machine that ran
#       the tests (the clock their markers use). On the host the terminal needs Screen
#       Recording permission ([RYAN], once); the VM's guest agent already has it.

capture_runner="${E2E_RUNNER:-host}"
case "$capture_runner" in
    host | vm | tart) ;;
    *)
        echo "capture: E2E_RUNNER must be vm or host (got '$capture_runner')" >&2
        exit 2
        ;;
esac
# The guest display: room for the 1440x900 pt store window and the 1280x800 pt guide window
# below the menu bar, at 2x.
capture_hidpi="1920x1200"

capture_build() {
    scripts/xcodebuild.sh -scheme Segue-AppStore -configuration Debug-AppStore build-for-testing
}

capture_run() { # <bundle> <appearance> <only-testing...>
    local bundle="$1" appearance="$2" extra status=0
    shift 2
    discard "$bundle"
    if [[ "$capture_runner" == host ]]; then
        TEST_RUNNER_SEGUE_SHOT_APPEARANCE="$appearance" SEGUE_RESULT_BUNDLE="$bundle" \
            scripts/xcodebuild.sh -scheme Segue-AppStore -configuration Debug-AppStore \
            test-without-building "$@"
        return
    fi
    # The appearance reaches the guest's test runner through the staged extra folder.
    extra=$(mktemp -d "${TMPDIR:-/tmp}/segue-capture.XXXXXX")
    echo "SEGUE_SHOT_APPEARANCE=$appearance" >"$extra/test-env"
    # A default Mac's look: the E2E image turns on keyboard navigation (focus rings on the
    # first button of every sheet) and, with no trackpad, always shows scroll bars.
    printf '%s\n' "defaults write -g AppleKeyboardUIMode -int 0" \
        "defaults write -g AppleShowScrollBars -string WhenScrolling" >"$extra/setup.sh"
    # The products capture_build made: without this a run that lands in guest slot 1 would
    # look for them in slot 1's own DerivedData.
    SEGUE_DERIVED_DATA="${SEGUE_DERIVED_DATA:-.build/DerivedData}" \
        E2E_VM_SCHEME=Segue-AppStore E2E_VM_CONFIGURATION=Debug-AppStore \
        E2E_VM_HIDPI="$capture_hidpi" E2E_VM_EXTRA="$extra" E2E_VM_SKIP_BUILD=1 \
        SEGUE_RESULT_BUNDLE="$bundle" scripts/e2e-vm.sh tart "$@" || status=$?
    discard "$extra"
    return "$status"
}

capture_export() { # <bundle> <folder>
    discard "$2"
    xcrun xcresulttool export attachments --path "$1" --output-path "$2" \
        --schema-version 0.4.0 >/dev/null
}

capture_record() { # <movie> <width> <height> <cursor> <bundle> <appearance> <only-testing...>
    local movie="$1" width="$2" height="$3" cursor="$4" status=0 rect
    shift 4
    discard "$movie" "$movie.started"
    recorded_started=""
    if [[ "$capture_runner" == host ]]; then
        rect=$(osascript -l JavaScript -e 'ObjC.import("AppKit");
            const s = $.NSScreen.screens.objectAtIndex(0), f = s.frame, v = s.visibleFrame;
            Math.round(v.origin.x) + "," + Math.round(f.size.height - v.origin.y - v.size.height)')
        record_start "$movie" "$rect,$width,$height" "$cursor"
        capture_run "$@" || status=$?
        record_stop
    else
        E2E_VM_RECORD="$width $height $cursor" SEGUE_RECORDING="$movie" capture_run "$@" ||
            status=$?
        recorded_started=$(tr -d '[:space:]' <"$movie.started" 2>/dev/null || true)
    fi
    ((status == 0)) || return "$status"
    [[ -s "$movie" && -n "$recorded_started" ]] || {
        echo "capture: no recording in $movie (Screen Recording permission?)" >&2
        return 1
    }
}
