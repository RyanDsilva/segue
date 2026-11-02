#!/usr/bin/env bash
# Opens a DMG on a clean Mac the way a friend's Mac would (R200): in a throwaway clone of the
# golden E2E VM (Tart, R180), the DMG lands in ~/Downloads with the quarantine attribute a
# browser download carries, and Gatekeeper must accept it and the app copied out of it.
#
#   scripts/dmg-gatekeeper-vm.sh <dmg> [--expect-reject]
#
# Guest checks, in order: Gatekeeper assessments are on; `spctl -a -vvv -t install` accepts
# the quarantined DMG as Notarized Developer ID; the app copied to /Applications (still
# quarantined) passes `spctl -t exec`, `stapler validate` and `syspolicy_check
# distribution`; then the app is opened and the guest screen captured after 15 s, to
# .build/dist/<dmg>.first-launch.png (and the DMG's Finder window to <dmg>.dmg-window.png). A notarized app shows only macOS's standard "downloaded
# from the Internet" confirmation on first launch, never "cannot be opened" or "Apple could
# not verify". The verdict is spctl's and stapler's; the screenshot is for a human to look at.
#
# --expect-reject inverts the verdict: the DMG must be refused (proves the check bites, on a
# dry-run DMG). Exit 0 = verdict as expected.
#
# The clone is named segue-dmg-gk-<epoch>-<pid>, is stopped and deleted on exit (also on
# failure or Ctrl-C), and the staging under ~/Library/Caches (outside the TCC-protected
# Desktop) goes with it. macOS runs at most two VMs at once: this fails clearly when both
# slots are taken (e.g. by an E2E run).
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=lib/e2e-vm-tart.sh
source scripts/lib/e2e-vm-tart.sh

die() {
    echo "dmg-gatekeeper-vm: error: $*" >&2
    exit 1
}
say() { echo "dmg-gatekeeper-vm: $*"; }

[[ $# -ge 1 && $# -le 2 ]] || die "usage: scripts/dmg-gatekeeper-vm.sh <dmg> [--expect-reject]"
dmg="$1"
expect=accept
if [[ $# -eq 2 ]]; then
    [[ "$2" == "--expect-reject" ]] || die "usage: scripts/dmg-gatekeeper-vm.sh <dmg> [--expect-reject]"
    expect=reject
fi
[[ -f "$dmg" ]] || die "no DMG at $dmg"
golden="${E2E_VM_GOLDEN:-segue-e2e-golden}"

vm_tool_check || exit 1
vm_exists "$golden" || die "no golden VM '$golden'; run \`make e2e-vm-golden\` first"
running=$(tart_cmd list --source local --format json | jq '[.[] | select(.Running == true)] | length')
((running < 2)) || die "both VM slots are in use ($running running); wait for them to finish"

name="segue-dmg-gk-$(date +%s)-$$"
stage="$HOME/Library/Caches/segue-dmg-vm/$name"
vm_pid=""
# shellcheck disable=SC2329 # invoked by the EXIT trap
cleanup() {
    local status=$?
    trap - EXIT INT TERM
    vm_delete "$name"
    if [[ -n "$vm_pid" ]]; then
        kill "$vm_pid" 2>/dev/null || true
    fi
    find "$stage" -depth -delete 2>/dev/null || true
    rmdir "$(dirname "$stage")" 2>/dev/null || true
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

mkdir -p "$stage/products" "$stage/results"
dmg_name=$(basename "$dmg")
cp "$dmg" "$stage/products/$dmg_name"
command cat >"$stage/products/guest.sh" <<'GUEST'
#!/bin/bash
# Runs in the guest's Aqua session as the logged-in admin. $1 = the DMG's file name.
set -uo pipefail
share="/Volumes/My Shared Files"
dl="$HOME/Downloads/$1"
results="$share/results"
verdict=0
step() { echo "guest: $*"; }

step "macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
if ! spctl --status 2>&1 | grep -q 'assessments enabled'; then
    step "Gatekeeper is off in this image; turning it on"
    sudo -n spctl --global-enable 2>&1 || sudo -n spctl --master-enable 2>&1 || { step "FAIL: cannot enable Gatekeeper"; exit 1; }
fi
step "Gatekeeper: $(spctl --status 2>&1)"

# The image grants the Tart guest agent Screen Recording, but its first capture raises
# macOS's monthly "bypass the system private window picker" reminder, which would cover the
# second screenshot. Recording that the reminder was just shown keeps it away.
python3 - "$(python3 -c 'import os; print(os.path.realpath("/opt/homebrew/bin/tart-guest-agent"))')" <<'PY'
import datetime, os, plistlib, sys
folder = os.path.expanduser("~/Library/Group Containers/group.com.apple.replayd")
os.makedirs(folder, exist_ok=True)
now = datetime.datetime.now(datetime.timezone.utc)
with open(os.path.join(folder, "ScreenCaptureApprovals.plist"), "wb") as f:
    plistlib.dump({sys.argv[1]: {
        "kScreenCaptureAlertableUsageCount": 1,
        "kScreenCaptureApprovalLastAlerted": now,
        "kScreenCaptureApprovalLastUsed": now,
        "kScreenCapturePrivacyHintDate": now + datetime.timedelta(days=30),
        "kScreenCapturePrivacyHintPolicy": 2592000,
    }}, f)
PY

# A browser download: the file in ~/Downloads with Safari's quarantine record
# (flags 0083 = downloaded, Gatekeeper not yet passed).
cp "$share/products/$1" "$dl"
xattr -w com.apple.quarantine "0083;$(printf %x "$(date +%s)");Safari;$(uuidgen)" "$dl"
step "quarantine: $(xattr -p com.apple.quarantine "$dl")"

out=$(spctl -a -vvv -t install "$dl" 2>&1) || verdict=1
echo "$out" | sed 's/^/  spctl install: /'
grep -q 'source=Notarized Developer ID' <<<"$out" || verdict=1

mnt=$(hdiutil attach -readonly -noautoopen "$dl" | sed -n -E 's|.*(/Volumes/.*)$|\1|p' | tail -n 1)
if [[ -z "$mnt" || ! -d "$mnt/Segue.app" ]]; then
    step "FAIL: could not mount the DMG or find Segue.app"
    exit 1
fi
# The window a friend sees on double-click, for a human to check the layout.
open "$mnt"
sleep 8
screencapture -x "$results/dmg-window.png" || step "note: no screenshot of the DMG window"
rm -rf /Applications/Segue.app
ditto "$mnt/Segue.app" /Applications/Segue.app
hdiutil detach -quiet -force "$mnt" || true
if ! xattr -p com.apple.quarantine /Applications/Segue.app >/dev/null 2>&1; then
    # Finder copies carry the image's quarantine; make sure ditto's copy does too.
    xattr -w com.apple.quarantine "0083;$(printf %x "$(date +%s)");Safari;$(uuidgen)" /Applications/Segue.app
fi
step "app quarantine: $(xattr -p com.apple.quarantine /Applications/Segue.app)"

out=$(spctl -a -vvv -t exec /Applications/Segue.app 2>&1) || verdict=1
echo "$out" | sed 's/^/  spctl exec: /'
grep -q 'source=Notarized Developer ID' <<<"$out" || verdict=1
out=$(xcrun stapler validate /Applications/Segue.app 2>&1) || verdict=1
echo "$out" | sed 's/^/  stapler: /'
out=$(syspolicy_check distribution /Applications/Segue.app 2>&1) || verdict=1
echo "$out" | sed 's/^/  syspolicy_check: /'

# `open` waits while a Gatekeeper dialog is up, so it runs in the background.
open /Applications/Segue.app &
opener=$!
sleep 15
screencapture -x "$results/first-launch.png" || step "note: no screenshot of the first launch"
kill "$opener" 2>/dev/null || true
exit "$verdict"
GUEST
chmod +x "$stage/products/guest.sh"

say "cloning $golden as $name"
vm_clone "$golden" "$name" >/dev/null
vm_start "$name" "$stage/products" "$stage/results" "$stage/vm.log"
ready=false
for _ in $(seq 1 90); do
    if vm_exec "$name" true >/dev/null 2>&1; then
        ready=true
        break
    fi
    sleep 2
done
$ready || die "$name did not come up within 180 s: $(command cat "$stage/vm.log" 2>/dev/null)"
say "$name booted; opening $dmg_name as a download"

status=0
vm_exec "$name" bash "$(vm_share_root)/products/guest.sh" "$dmg_name" || status=$?

mkdir -p .build/dist
for shot in dmg-window first-launch; do
    if [[ -s "$stage/results/$shot.png" ]]; then
        cp "$stage/results/$shot.png" ".build/dist/$dmg_name.$shot.png"
        say "$shot on the clean Mac: .build/dist/$dmg_name.$shot.png"
    fi
done

if [[ "$expect" == accept ]]; then
    ((status == 0)) || die "Gatekeeper on the clean Mac did not accept $dmg_name (see above)"
    say "PASS: Gatekeeper accepts $dmg_name and its app as Notarized Developer ID on a clean Mac"
else
    ((status != 0)) || die "expected Gatekeeper to refuse $dmg_name, but it was accepted"
    say "PASS: Gatekeeper refuses $dmg_name on a clean Mac, as expected for an un-notarized DMG"
fi
