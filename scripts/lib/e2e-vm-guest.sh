#!/bin/bash
# Runs INSIDE the E2E guest VM (scripts/e2e-vm.sh stages it as products/guest-run.sh and
# runs it through the adapter's vm_exec, in the logged-in user's GUI session).
#
# Usage: guest-run.sh SHARE HOST_BUILD XCTESTRUN RESULT_SUBPATH [-only-testing:...]
#
# Preflight, fail closed (exit 90-92, which the host turns into "rebuild the golden VM"):
#   90  the guest Xcode build differs from the host's (test-without-building needs both equal)
#   91  UI automation mode still asks for a password (XCUITest would hang on the prompt)
#   92  not in the Aqua session (XCUITest cannot drive the UI from a Background session)
#   93  the Retina mode the host asked for (E2E_VM_HIDPI) could not be set
#   94  the staged extra/setup.sh failed
# Otherwise the exit code is xcodebuild's.
set -uo pipefail

share="$1" host_build="$2" xctestrun="$3" result_subpath="$4"
shift 4

guest_build=$(xcodebuild -version | awk '/Build version/{print $3}')
if [[ "$guest_build" != "$host_build" ]]; then
    echo "e2e-vm(guest): Xcode build $guest_build in the guest, $host_build on the host" >&2
    exit 90
fi
if ! automationmodetool 2>&1 | grep -q "DOES NOT REQUIRE"; then
    echo "e2e-vm(guest): automation mode requires authentication:" >&2
    automationmodetool >&2 || true
    exit 91
fi
session=$(launchctl managername 2>/dev/null || echo unknown)
if [[ "$session" != Aqua ]]; then
    echo "e2e-vm(guest): running in the '$session' session, not Aqua" >&2
    exit 92
fi

# Guest output mute does not survive a reboot (spike S1), so every run mutes it: no clicks
# from the metronome tests reach the host speakers. The Cirrus image restores a Terminal
# window at login; close it so it cannot hold focus.
osascript -e 'set volume output muted true' || true
pkill -x Terminal 2>/dev/null || true

# The shares mount at login; wait for them briefly.
for _ in $(seq 1 30); do
    [[ -f "$share/products/$xctestrun" ]] && break
    sleep 2
done

# Run from the guest's own disk, never from the share (a network volume, see the research
# doc 3.3). The test library root /private/tmp/segue-e2e is guest-local.
run="$HOME/segue-run"
out="$HOME/segue-results"
/bin/rm -rf "$run" "$out" /private/tmp/segue-e2e
ditto "$share/products" "$run"
mkdir -p "$out"

# A Retina guest (E2E_VM_HIDPI): switch to the 2x mode the host staged before any test.
if [[ -f "$run/display" ]]; then
    read -r width height <"$run/display"
    "$run/display-mode" "$width" "$height" || exit 93
fi

# The library copy test's staged library (scripts/library-copy-test.sh); TEST_RUNNER_ hands
# it to the UI test runner as SEGUE_COPY_LIBRARY.
if [[ -d "$run/extra/library" ]]; then
    export TEST_RUNNER_SEGUE_COPY_LIBRARY="$run/extra/library"
fi
# Guest-side setup a host script staged (scripts/lib/capture.sh: a default Mac's look for the
# captures), run before the tests.
if [[ -f "$run/extra/setup.sh" ]]; then
    bash "$run/extra/setup.sh" || exit 94
fi
# KEY=VALUE lines a host script staged for the test runner (store-shots.sh vm: the
# screenshot appearance).
if [[ -f "$run/extra/test-env" ]]; then
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[A-Z][A-Z0-9_]*$ ]] && export "TEST_RUNNER_$key=$value"
    done <"$run/extra/test-env"
fi

# A recording of the run (E2E_VM_RECORD, the guide clips and the App Store preview): the
# app's windows in a WxH pt rectangle at the top-left of the visible area, with
# scripts/record-app.swift (ScreenCaptureKit). The Cirrus image grants Screen Recording to
# the Tart guest agent, which runs this script, so no prompt appears.
recorder=""
if [[ -f "$run/record" ]]; then
    read -r rec_width rec_height rec_cursor <"$run/record"
    # macOS also asks, in a UserNotificationCenter alert that takes the keyboard from the
    # app under test, whether a screen recorder may keep bypassing the window picker; a
    # far-future approval for the recorder (and the agent that starts it) answers it ahead.
    approvals="$HOME/Library/Group Containers/group.com.apple.replayd/ScreenCaptureApprovals.plist"
    mkdir -p "$(dirname "$approvals")"
    for client in "$run/record-app" "$(readlink -f /opt/homebrew/bin/tart-guest-agent 2>/dev/null)"; do
        [[ -n "$client" ]] && defaults write "$approvals" "$client" -date "3024-01-01 00:00:00 +0000"
    done
    rect=$(osascript -l JavaScript -e 'ObjC.import("AppKit");
        const s = $.NSScreen.screens.objectAtIndex(0), f = s.frame, v = s.visibleFrame;
        Math.round(v.origin.x) + "," + Math.round(f.size.height - v.origin.y - v.size.height)')
    "$run/record-app" "$out/recording.mov" dev.ryandsilva.segue \
        "$rect,$rec_width,$rec_height" "$rec_cursor" "$out/recording.started" &
    recorder=$!
fi

status=0
xcodebuild test-without-building \
    -xctestrun "$run/$xctestrun" \
    -destination "platform=macOS,arch=arm64" \
    -resultBundlePath "$out/run.xcresult" \
    "$@" || status=$?

if [[ -n "$recorder" ]]; then
    kill -INT "$recorder" 2>/dev/null || true
    wait "$recorder" || true
    for file in recording.mov recording.started; do
        [[ -f "$out/$file" ]] && ditto "$out/$file" "$share/$(dirname "$result_subpath")/$file"
    done
fi
if [[ -d "$out/run.xcresult" ]]; then
    mkdir -p "$(dirname "$share/$result_subpath")"
    ditto "$out/run.xcresult" "$share/$result_subpath"
fi
exit "$status"
