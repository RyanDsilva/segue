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

# The library copy test's staged library (scripts/library-copy-test.sh); TEST_RUNNER_ hands
# it to the UI test runner as SEGUE_COPY_LIBRARY.
if [[ -d "$run/extra/library" ]]; then
    export TEST_RUNNER_SEGUE_COPY_LIBRARY="$run/extra/library"
fi

status=0
xcodebuild test-without-building \
    -xctestrun "$run/$xctestrun" \
    -destination "platform=macOS,arch=arm64" \
    -resultBundlePath "$out/run.xcresult" \
    "$@" || status=$?

if [[ -d "$out/run.xcresult" ]]; then
    mkdir -p "$(dirname "$share/$result_subpath")"
    ditto "$out/run.xcresult" "$share/$result_subpath"
fi
exit "$status"
