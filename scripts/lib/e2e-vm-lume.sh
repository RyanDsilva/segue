#!/usr/bin/env bash
# The Lume adapter of the E2E VM runner (scripts/e2e-vm.sh, E2E_RUNNER=lume): the MIT
# licence escape hatch behind the same contract as scripts/lib/e2e-vm-tart.sh (read the
# contract there). Lume is pinned in .mise.toml. Source it from the repo root.
#
# UNVERIFIED end to end (docs/research/e2e-off-screen.md 5.5): Lume has no prebuilt Xcode
# image, so its golden VM is built by hand once (`lume create --ipsw latest --unattended
# tahoe`, Xcode matching the host, `automationmodetool enable-automationmode-without-
# authentication`, `lume sip` off for TCC writes) and named LUME_GOLDEN. Lume runs commands
# over SSH, which lands in a Background session rather than Aqua, so vm_exec wraps each
# command in a one-shot LaunchAgent in gui/<uid> and polls for its exit status.
#
# Lume shares one directory per VM, so PRODUCTS and RESULTS must be siblings: their parent
# is shared read-write and the guest sees products/ and results/ under it.

LUME_USER="${LUME_USER:-lume}"
LUME_PASSWORD="${LUME_PASSWORD:-lume}"

lume_cmd() {
    mise exec -- lume "$@"
}

vm_tool_check() {
    if ! lume_cmd --version >/dev/null 2>&1; then
        echo "e2e-vm: lume is not installed; run \`mise install\` in the repo" >&2
        return 1
    fi
    lume_cmd config telemetry disable >/dev/null 2>&1 || true
}

vm_exists() {
    lume_cmd get "$1" >/dev/null 2>&1
}

vm_clone() {
    lume_cmd clone "$1" "$2"
}

vm_start() {
    local name="$1" products="$2" results="$3" log="$4" parent
    parent=$(dirname "$products")
    if [[ "$(dirname "$results")" != "$parent" ]]; then
        echo "e2e-vm(lume): products and results must share a parent folder" >&2
        return 1
    fi
    lume_cmd run "$name" --display none --shared-dir "$parent:rw" >"$log" 2>&1 &
    vm_pid=$!
}

# One-shot LaunchAgent in the GUI session: the command's output goes to a log file next to
# it, its exit status to a marker file; the host side polls the marker and prints the log.
vm_exec() {
    local name="$1" id
    shift
    id="segue-e2e-exec-$$-$RANDOM"
    local quoted
    quoted=$(printf '%q ' "$@")
    local script
    script=$(
        command cat <<EOF
set -eu
dir=/tmp/$id; mkdir -p "\$dir"
printf '%s\n' '#!/bin/bash' "($quoted) >\"\$dir/out\" 2>&1; echo \\\$? >\"\$dir/status\"" >"\$dir/run.sh"
chmod +x "\$dir/run.sh"
/usr/libexec/PlistBuddy -c "Add :Label string $id" -c "Add :ProgramArguments array" \
    -c "Add :ProgramArguments:0 string \$dir/run.sh" "\$dir/agent.plist" >/dev/null
launchctl bootstrap gui/\$(id -u) "\$dir/agent.plist"
while [[ ! -f "\$dir/status" ]]; do sleep 2; done
launchctl bootout gui/\$(id -u)/$id 2>/dev/null || true
command cat "\$dir/out"
exit "\$(command cat "\$dir/status")"
EOF
    )
    # The script travels base64-encoded inside the command line (no reliance on SSH stdin).
    lume_ssh "$name" "echo $(base64 <<<"$script" | tr -d '\n') | base64 -D | bash"
}

lume_ssh() {
    local name="$1"
    shift
    lume_cmd ssh "$name" --user "$LUME_USER" --password "$LUME_PASSWORD" --timeout 0 "$@"
}

vm_share_root() {
    echo "/Volumes/My Shared Files"
}

vm_stop() {
    vm_exists "$1" || return 0
    lume_cmd stop "$1" >/dev/null 2>&1 || true
}

vm_delete() {
    vm_exists "$1" || return 0
    vm_stop "$1"
    lume_cmd delete "$1" --force >/dev/null 2>&1 || true
}

vm_list_runs() {
    lume_cmd ls --format json 2>/dev/null | mise exec -- jq -r '.[].name' | grep "^$1" || true
}

vm_set() {
    lume_cmd set "$1" --cpu "$2" --memory "${3}MB" --display "$4"
}

vm_image_for_xcode() {
    echo "(none: build a Lume golden VM with Xcode $1 by hand, docs/research/e2e-off-screen.md 5.5)"
}

vm_pull_golden() {
    echo "e2e-vm(lume): no prebuilt Xcode image exists for Lume; build $2 by hand" >&2
    return 1
}
