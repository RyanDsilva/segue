#!/usr/bin/env bash
# Phase 0 verification task "Shortcut from full screen" (docs/phases/0-walking-skeleton.md):
# with Segue full screen, open shortcuts://run-shortcut?name=<name> and record whether the
# Shortcuts app comes forward or leaves a visible window.
#
# Usage: scripts/verify-shortcut-focus.sh "<shortcut name>" [path/to/Segue.app]
#
# Needs (one-time, manual):
#   - a user Shortcut with that name (a harmless one, e.g. a single "Wait 1 second" action);
#     the Shortcuts CLI can run but not create shortcuts, so this cannot be automated;
#   - Accessibility permission for the terminal running this script (System Settings >
#     Privacy & Security > Accessibility), used only to toggle Segue's full screen.
#
# Samples the frontmost app (lsappinfo) and Shortcuts' on-screen windows (CGWindowList)
# every 0.25 s for 8 s after opening the URL, then prints a verdict. Exit status: 0 when
# Segue keeps focus and no Shortcuts window appears, 2 when Shortcuts steals focus or shows
# a window, 1 on setup errors.
set -euo pipefail
cd "$(dirname "$0")/.."

name="${1:?usage: scripts/verify-shortcut-focus.sh \"<shortcut name>\" [Segue.app]}"
app="${2:-.build/DerivedData/Build/Products/Debug-Personal/Segue.app}"

if ! shortcuts list | grep -Fxq "$name"; then
    echo "error: no Shortcut named '$name' (shortcuts list). Create it in Shortcuts first." >&2
    exit 1
fi
[[ -d "$app" ]] || { echo "error: $app not found; run 'make build' first." >&2; exit 1; }

frontmost() {
    lsappinfo info -only name "$(lsappinfo front)" | sed -E 's/.*"LSDisplayName"="([^"]*)".*/\1/'
}

# Number of normal-layer, on-screen windows owned by Shortcuts (a tiny CGWindowList probe,
# compiled once so sampling stays fast).
probe_dir=$(mktemp -d)
trap 'rm -f "$probe_dir/probe.swift" "$probe_dir/probe"; rmdir "$probe_dir"' EXIT
cat >"$probe_dir/probe.swift" <<'SWIFT'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
    as? [[String: Any]] ?? []
print(list.filter {
    ($0[kCGWindowOwnerName as String] as? String) == "Shortcuts"
        && ($0[kCGWindowLayer as String] as? Int) == 0
}.count)
SWIFT
xcrun swiftc -O -o "$probe_dir/probe" "$probe_dir/probe.swift"
shortcuts_windows() {
    "$probe_dir/probe"
}

set_full_screen() {
    osascript -e "tell application \"System Events\" to tell process \"Segue\" to set value of \
attribute \"AXFullScreen\" of window 1 to $1" >/dev/null
}

is_full_screen() {
    osascript -e "tell application \"System Events\" to tell process \"Segue\" to get value of \
attribute \"AXFullScreen\" of window 1" 2>/dev/null || echo "unknown"
}

shortcuts_was_running=no
pgrep -xq Shortcuts && shortcuts_was_running=yes

echo "Launching $app"
open "$app"
for _ in $(seq 1 40); do
    [[ "$(frontmost)" == "Segue" ]] && break
    sleep 0.25
done
[[ "$(frontmost)" == "Segue" ]] || { echo "error: Segue did not come to the front" >&2; exit 1; }

if ! set_full_screen true; then
    echo "error: could not enter full screen; grant Accessibility to this terminal" >&2
    exit 1
fi
sleep 2
echo "Segue full screen: $(is_full_screen); Shortcuts already running: $shortcuts_was_running"

encoded=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$name")
echo "Opening shortcuts://run-shortcut?name=$encoded"
open "shortcuts://run-shortcut?name=$encoded"

stole=no
for _ in $(seq 1 32); do
    front=$(frontmost)
    windows=$(shortcuts_windows)
    printf '  t+%ss front=%s shortcutsWindows=%s\n' "$SECONDS" "$front" "$windows"
    if [[ "$front" != "Segue" || "$windows" != "0" ]]; then
        stole=yes
    fi
    sleep 0.25
done
echo "Segue still full screen afterwards: $(is_full_screen); frontmost now: $(frontmost)"

set_full_screen false || true
if [[ "$stole" == "yes" ]]; then
    echo "RESULT: Shortcuts came forward or showed a window (focus stolen)."
    exit 2
fi
echo "RESULT: Segue kept focus; no Shortcuts window appeared."
