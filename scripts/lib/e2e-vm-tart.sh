#!/usr/bin/env bash
# The Tart adapter of the E2E VM runner (scripts/e2e-vm.sh, E2E_RUNNER=vm). Source it from
# the repo root. Tart is pinned in .mise.toml (R180, docs/research/e2e-off-screen.md).
#
# Adapter contract (the Lume adapter, scripts/lib/e2e-vm-lume.sh, defines the same):
#   vm_tool_check                      fail when the CLI is missing
#   vm_exists NAME                     0 when a local VM of that name exists
#   vm_clone SOURCE NAME               copy-on-write clone of the powered-off golden VM
#   vm_start NAME PRODUCTS RESULTS LOG boot headless in the background; PRODUCTS is shared
#                                      read-only as "products", RESULTS read-write as "results"
#   vm_exec NAME CMD...                run CMD in the guest's GUI (Aqua) session, streaming
#                                      its output; returns CMD's exit code
#   vm_share_root                      where the shares appear inside the guest
#   vm_stop NAME / vm_delete NAME      power off / remove (both quiet when already gone)
#   vm_list_runs PREFIX                local VM names starting with PREFIX
#   vm_set NAME CPU MEM_MB DISPLAY     size the (golden) VM
#
# `tart exec` reaches the guest agent, which Cirrus images run as a global LaunchAgent,
# so commands land in the logged-in admin's Aqua session (spike S1.4, verified).

tart_cmd() {
    mise exec -- tart "$@"
}

vm_tool_check() {
    if ! tart_cmd --version >/dev/null 2>&1; then
        echo "e2e-vm: tart is not installed; run \`mise install\` in the repo" >&2
        return 1
    fi
}

vm_exists() {
    tart_cmd list --source local --quiet 2>/dev/null | grep -qx "$1"
}

vm_clone() {
    tart_cmd clone "$1" "$2"
}

vm_start() {
    local name="$1" products="$2" results="$3" log="$4" vnc=()
    [[ "${VM_VNC:-}" == 1 ]] && vnc=(--vnc)
    # --no-graphics: no window on the host. Audio stays connected (the engine path is
    # exercised); the guest script mutes the output at the start of every run.
    tart_cmd run "$name" --no-graphics "${vnc[@]}" --no-clipboard \
        --dir "products:$products:ro" --dir "results:$results" \
        >"$log" 2>&1 &
    vm_pid=$!
}

vm_exec() {
    local name="$1"
    shift
    tart_cmd exec "$name" "$@"
}

vm_share_root() {
    echo "/Volumes/My Shared Files"
}

vm_stop() {
    vm_exists "$1" || return 0
    tart_cmd stop --timeout 20 "$1" >/dev/null 2>&1 || true
}

vm_delete() {
    vm_exists "$1" || return 0
    vm_stop "$1"
    tart_cmd delete "$1" >/dev/null 2>&1 || true
}

vm_list_runs() {
    tart_cmd list --source local --quiet 2>/dev/null | grep "^$1" || true
}

vm_set_display() {
    tart_cmd set "$1" --display "$2"
}

vm_set() {
    tart_cmd set "$1" --cpu "$2" --memory "$3" --display "$4"
}

# The image the golden VM is cloned from: the Cirrus prebuilt matching an Xcode version.
vm_image_for_xcode() {
    echo "ghcr.io/cirruslabs/macos-tahoe-xcode:$1"
}

vm_pull_golden() {
    local image="$1" golden="$2"
    tart_cmd clone "$image" "$golden"
}
