#!/usr/bin/env bash
# Creates (or re-creates) the golden VM that scripts/e2e-vm.sh clones per run (R180,
# docs/research/e2e-off-screen.md 5.1-5.2). `make e2e-vm-golden` runs it; it is also the
# command the runner names when the guest and host Xcode differ.
#
# Tart: pulls ghcr.io/cirruslabs/macos-tahoe-xcode:<host Xcode version> (about 69 GB the
# first time; Cirrus has automation mode, TCC, auto-login and no screen lock pre-done,
# SIP off in the guest only), clones it to E2E_VM_GOLDEN, sizes it, boots it once to stop
# the login Terminal window coming back and to switch off Spotlight indexing and automatic
# updates, checks the preconditions, and shuts it down. Lume: no prebuilt Xcode image exists; this only sizes
# and checks a golden VM built by hand (research doc 5.5).
#
# Environment: E2E_RUNNER (vm or lume, default vm), E2E_VM_GOLDEN (default
# segue-e2e-golden), E2E_VM_CPU (4), E2E_VM_MEMORY (MB, 6144), E2E_VM_DISPLAY (1920x1200px).
set -euo pipefail
cd "$(dirname "$0")/.."

runner="${E2E_RUNNER:-vm}"
case "$runner" in
    vm | tart)
        adapter=tart
        # shellcheck source=lib/e2e-vm-tart.sh
        source scripts/lib/e2e-vm-tart.sh
        ;;
    lume)
        adapter=lume
        # shellcheck source=lib/e2e-vm-lume.sh
        source scripts/lib/e2e-vm-lume.sh
        ;;
    *)
        echo "e2e-vm-golden: E2E_RUNNER must be vm or lume" >&2
        exit 2
        ;;
esac

golden="${E2E_VM_GOLDEN:-segue-e2e-golden}"
cpu="${E2E_VM_CPU:-4}"
memory="${E2E_VM_MEMORY:-6144}"
# Pixels: with the default point units the guest kept 1024x768 at 2x (spike S1).
display="${E2E_VM_DISPLAY:-1920x1200px}"
cache="$HOME/Library/Caches/segue-e2e-vm"
mkdir -p "$cache"
host_xcode=$(xcodebuild -version | awk '/^Xcode/{print $2}')
host_build=$(xcodebuild -version | awk '/Build version/{print $3}')
image=$(vm_image_for_xcode "$host_xcode")
stamp="$cache/$golden.xcode"

vm_tool_check
if vm_exists "$golden" && [[ -f "$stamp" && "$(command cat "$stamp")" == "$host_build" ]]; then
    echo "e2e-vm-golden: $golden already matches Xcode $host_xcode ($host_build); re-checking it"
elif [[ "$adapter" == tart ]]; then
    if vm_exists "$golden"; then
        echo "e2e-vm-golden: replacing $golden (built for $(command cat "$stamp" 2>/dev/null || echo "an unknown Xcode"))"
        vm_delete "$golden"
    fi
    echo "e2e-vm-golden: pulling $image (about 69 GB the first time; keep the Mac awake)"
    caffeinate -i -w $$ &
    vm_pull_golden "$image" "$golden"
elif ! vm_exists "$golden"; then
    vm_pull_golden "$image" "$golden"
fi

vm_set "$golden" "$cpu" "$memory" "$display"

log="$cache/golden-boot.log"
empty="$cache/golden-share"
mkdir -p "$empty/products" "$empty/results"
vm_start "$golden" "$empty/products" "$empty/results" "$log"
trap 'vm_stop "$golden"; kill "$vm_pid" 2>/dev/null || true' EXIT
for _ in $(seq 1 90); do
    vm_exec "$golden" true >/dev/null 2>&1 && break
    sleep 2
done

# Each line is checked; a failure leaves the golden unstamped, so runs refuse it.
provision=$(
    command cat <<'EOF'
set -euo pipefail
echo "session: $(launchctl managername)"
pkill -x Terminal || true
defaults write -g NSQuitAlwaysKeepsWindows -bool false
defaults write com.apple.Terminal NSQuitAlwaysKeepsWindows -bool false
sudo mdutil -a -i off >/dev/null
sudo softwareupdate --schedule off >/dev/null 2>&1 || true
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool false
automationmodetool | grep "DOES NOT REQUIRE"
DevToolsSecurity -status
csrutil status
xcodebuild -version
EOF
)
vm_exec "$golden" bash -c "$provision" || {
    echo "e2e-vm-golden: a provisioning check failed (output above)" >&2
    exit 1
}
guest_build=$(vm_exec "$golden" xcodebuild -version | awk '/Build version/{print $3}')
if [[ "$guest_build" != "$host_build" ]]; then
    echo "e2e-vm-golden: the image has Xcode build $guest_build, the host $host_build" >&2
    exit 1
fi
vm_exec "$golden" sudo shutdown -h now >/dev/null 2>&1 || true
for _ in $(seq 1 30); do
    kill -0 "$vm_pid" 2>/dev/null || break
    sleep 2
done
echo "$host_build" >"$stamp"
echo "e2e-vm-golden: $golden ready ($cpu vCPU, $memory MB, $display, Xcode $host_xcode $host_build)"
