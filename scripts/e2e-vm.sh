#!/usr/bin/env bash
# Runs the XCUITest suite in a throwaway macOS VM so it never takes the owner's screen,
# pointer or keyboard (R180, docs/research/e2e-off-screen.md 5.1). Called by
# scripts/e2e-run.sh for E2E_RUNNER=vm (Tart) or E2E_RUNNER=lume.
#
# Usage: scripts/e2e-vm.sh <tart|lume> [-only-testing:SegueUITests/Class[/test]...]
#   No -only-testing argument runs the full suite.
#
#   1. host: build-for-testing through scripts/xcodebuild.sh (same warning check as today)
#   2. host: stage the .xctestrun and Debug-Personal under ~/Library/Caches/segue-e2e-vm
#      (outside ~/Desktop, so the VM tool never touches a TCC-protected folder)
#   3. host: clone the golden VM per shard, boot it headless with the staging shared
#   4. guest: check Xcode matches the host build, automation mode and the Aqua session;
#      copy the products to the guest disk; xcodebuild test-without-building
#   5. host: the exit code is the guest xcodebuild's; the .xcresult comes back over the
#      results share into .build/results (or SEGUE_RESULT_BUNDLE), merged when sharded
#   6. host: stop and delete the clones and the staging, even on failure or Ctrl-C
#
# Environment:
#   E2E_VM_SHARDS=2      split the selection over two VMs at once (about 12 GB of guests;
#                        opt-in for when the Mac is otherwise idle, never the default)
#   E2E_VM_GOLDEN        golden VM name (default segue-e2e-golden)
#   E2E_VM_TIMEOUT       minutes before a shard's run is killed (default 90)
#   E2E_VM_SKIP_BUILD=1  reuse the products already in .build/DerivedData
#   VM_VNC=1             Tart: serve the guest screen over VNC to watch a run
#   SEGUE_RESULT_BUNDLE  where the result bundle goes (as in scripts/xcodebuild.sh)
#
# Orphans: clones are named segue-e2e-run-<epoch>-<pid>-<shard>. Every run first deletes
# clones whose owning process is gone or that are older than 6 hours (the TTL backstop
# for a killed run), so nothing leaks even past a crash.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=$(pwd)
# shellcheck source=lib/discard.sh
source scripts/lib/discard.sh

adapter="${1:?usage: scripts/e2e-vm.sh <tart|lume> [-only-testing:...]}"
shift
case "$adapter" in
    tart)
        # shellcheck source=lib/e2e-vm-tart.sh
        source scripts/lib/e2e-vm-tart.sh
        ;;
    lume)
        # shellcheck source=lib/e2e-vm-lume.sh
        source scripts/lib/e2e-vm-lume.sh
        ;;
    *)
        echo "e2e-vm: unknown adapter '$adapter' (tart or lume)" >&2
        exit 2
        ;;
esac

golden="${E2E_VM_GOLDEN:-segue-e2e-golden}"
shards="${E2E_VM_SHARDS:-1}"
timeout_min="${E2E_VM_TIMEOUT:-90}"
ttl_hours=6
prefix="segue-e2e-run-"
cache="$HOME/Library/Caches/segue-e2e-vm"
golden_cmd="make e2e-vm-golden"
[[ "$adapter" == tart ]] || golden_cmd="make e2e-vm-golden E2E_RUNNER=$adapter"
derived="${SEGUE_DERIVED_DATA:-.build/DerivedData}"
products_dir="$derived/Build/Products"
scheme="Segue-Personal"
configuration="Debug-Personal"
results=".build/results"
mkdir -p "$results" "$cache"
bundle="${SEGUE_RESULT_BUNDLE:-$results/$(date +%Y%m%d-%H%M%S)-$$.xcresult}"

[[ "$shards" == 1 || "$shards" == 2 ]] || {
    echo "e2e-vm: E2E_VM_SHARDS must be 1 or 2 (macOS allows two guests)" >&2
    exit 2
}

log() { printf 'e2e-vm: %s\n' "$*"; }
elapsed() { printf '%dm%02ds' $(($1 / 60)) $(($1 % 60)); }

vm_tool_check
if ! vm_exists "$golden"; then
    echo "e2e-vm: no golden VM '$golden'; create it with: $golden_cmd" >&2
    exit 1
fi

# Fail closed on an Xcode mismatch before booting anything (the guest re-checks for real).
host_xcode=$(xcodebuild -version | awk '/^Xcode/{print $2}')
host_build=$(xcodebuild -version | awk '/Build version/{print $3}')
stamp="$cache/$golden.xcode"
if [[ -f "$stamp" && "$(command cat "$stamp")" != "$host_build" ]]; then
    echo "e2e-vm: golden VM has Xcode build $(command cat "$stamp"), the host has $host_xcode ($host_build)." >&2
    echo "e2e-vm: rebuild the golden VM with: $golden_cmd" >&2
    exit 1
fi

# Deletes a directory tree outright (staging is a throwaway copy of build output; the
# Trash, scripts/lib/discard.sh, would fill with 0.6 GB per run).
wipe() {
    local path
    for path in "$@"; do
        [[ -e "$path" ]] && find "$path" -depth -delete 2>/dev/null
    done
    return 0
}

# TTL backstop: delete clones and staging left by killed runs. Both are named
# <epoch>-<pid>[-shard]; one is stale when its owner is gone or it is older than the TTL.
now=$(date +%s)
stale() {
    local born="${1%%-*}" rest="${1#*-}" owner
    owner="${rest%%-*}"
    ! [[ "$born" =~ ^[0-9]+$ && "$owner" =~ ^[0-9]+$ ]] ||
        ! kill -0 "$owner" 2>/dev/null || ((now - born >= ttl_hours * 3600))
}
while IFS= read -r orphan; do
    if [[ -n "$orphan" ]] && stale "${orphan#"$prefix"}"; then
        log "deleting orphaned clone $orphan"
        vm_delete "$orphan"
    fi
done < <(vm_list_runs "$prefix")
for dir in "$cache"/runs/*; do
    if [[ -d "$dir" ]] && stale "$(basename "$dir")"; then
        wipe "$dir"
    fi
done

# One VM run at a time per Mac (the golden is shared, and macOS caps guests at two).
lock="$cache/lock"
if ! mkdir "$lock" 2>/dev/null; then
    holder=$(command cat "$lock/pid" 2>/dev/null || echo "")
    if [[ -n "$holder" ]] && kill -0 "$holder" 2>/dev/null; then
        echo "e2e-vm: another VM run (pid $holder) is in progress" >&2
        exit 1
    fi
    wipe "$lock"
    mkdir "$lock"
fi
echo $$ >"$lock/pid"

run_id="$now-$$"
stage="$cache/runs/$run_id"
clones=()
vm_pids=()
# shellcheck disable=SC2329 # invoked by the EXIT trap
cleanup() {
    local status=$? name pid
    trap - EXIT INT TERM
    for name in "${clones[@]}"; do
        vm_delete "$name"
    done
    for pid in "${vm_pids[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    wipe "$stage" "$lock"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

start=$SECONDS

# 1. Build on the host (signing keys never enter the guest).
if [[ "${E2E_VM_SKIP_BUILD:-}" != 1 ]]; then
    log "build-for-testing on the host"
    SEGUE_RESULT_BUNDLE="$results/$(date +%Y%m%d-%H%M%S)-$$-build.xcresult" \
        scripts/xcodebuild.sh -scheme "$scheme" -configuration "$configuration" build-for-testing
fi
xctestrun=$(cd "$products_dir" && find . -maxdepth 1 -name "${scheme}_*.xctestrun" | sed 's|^\./||' | head -1)
if [[ -z "$xctestrun" ]]; then
    echo "e2e-vm: no ${scheme}_*.xctestrun in $products_dir (run without E2E_VM_SKIP_BUILD)" >&2
    exit 1
fi
build_done=$SECONDS

# 2. Stage outside ~/Desktop. Static libraries and module files are build inputs only.
mkdir -p "$stage/products" "$stage/results"
rsync -a --exclude '*.swiftmodule' --exclude '*.a' \
    "$products_dir/$configuration" "$stage/products/"
cp "$products_dir/$xctestrun" "$stage/products/"
cp scripts/lib/e2e-vm-guest.sh "$stage/products/guest-run.sh"
staged=$SECONDS
log "staged $(du -sh "$stage/products" | cut -f1) in $(elapsed $((staged - build_done)))"

# The selection: the -only-testing arguments, or every class for a sharded full suite.
selection=("$@")
split=()
if ((shards == 2)); then
    if ((${#selection[@]} == 0)); then
        # Weighted by test count per class, so the two shards take about the same time.
        while IFS= read -r class; do
            selection+=("-only-testing:SegueUITests/$class")
        done < <(scripts/lib/e2e-classes.sh weighted)
    fi
    # Greedy: each item goes to the lighter shard (classes arrive heaviest first).
    weight0=0 weight1=0 shard0=() shard1=()
    for item in "${selection[@]}"; do
        id="${item#-only-testing:SegueUITests/}"
        w=1
        [[ "$id" == */* ]] || w=$(scripts/lib/e2e-classes.sh count "$id")
        if ((weight0 <= weight1)); then
            shard0+=("$item")
            weight0=$((weight0 + w))
        else
            shard1+=("$item")
            weight1=$((weight1 + w))
        fi
    done
    split=("${shard0[*]}" "${shard1[*]}")
    log "two shards: $weight0 and $weight1 tests (by count)"
else
    split=("${selection[*]}")
fi

# 3-5. One clone per shard, all at once.
run_shard() {
    local index="$1" name="$2" args="$3" shard_start=$SECONDS status=0 watchdog
    local shard_results="$stage/results/$index"
    local share
    share=$(vm_share_root)
    mkdir -p "$shard_results"
    vm_clone "$golden" "$name" >/dev/null
    vm_start "$name" "$stage/products" "$stage/results" "$stage/vm-$index.log"
    echo "$vm_pid" >"$stage/vm-$index.pid"
    local ready=false
    for _ in $(seq 1 90); do
        if vm_exec "$name" true >/dev/null 2>&1; then
            ready=true
            break
        fi
        sleep 2
    done
    if ! $ready; then
        echo "e2e-vm: $name did not come up within 180 s; tool log:" >&2
        command cat "$stage/vm-$index.log" >&2 || true
        return 1
    fi
    log "[$index] $name booted in $(elapsed $((SECONDS - shard_start)))"
    # The watchdog stops the VM if the run hangs, which ends vm_exec with a failure.
    # It polls in short sleeps so killing it never leaves a long sleep process behind.
    (
        deadline=$((SECONDS + timeout_min * 60))
        while ((SECONDS < deadline)); do sleep 5; done
        echo "e2e-vm: [$index] timed out after $timeout_min min" >&2
        vm_stop "$name"
    ) &
    watchdog=$!
    # shellcheck disable=SC2086 # args is a space-separated list of -only-testing flags
    vm_exec "$name" bash "$share/products/guest-run.sh" "$share" "$host_build" "$xctestrun" \
        "results/$index/run.xcresult" $args || status=$?
    kill "$watchdog" 2>/dev/null || true
    log "[$index] tests finished in $(elapsed $((SECONDS - shard_start))) (exit $status)"
    return "$status"
}

pids=()
for index in "${!split[@]}"; do
    name="$prefix$run_id-$index"
    clones+=("$name")
    if ((shards == 2)); then
        (run_shard "$index" "$name" "${split[$index]}" 2>&1 | sed -u "s/^/[vm$index] /") &
    else
        run_shard "$index" "$name" "${split[$index]}" &
    fi
    pids+=("$!")
done
status=0
for pid in "${pids[@]}"; do
    wait "$pid" || status=$?
done
for f in "$stage"/vm-*.pid; do
    [[ -f "$f" ]] && vm_pids+=("$(command cat "$f")")
done

# Guest exit codes 90-92 are the fail-closed preflight checks (scripts/lib/e2e-vm-guest.sh).
if ((status >= 90 && status <= 92)); then
    echo "e2e-vm: the guest failed its preflight (exit $status); rebuild it with: $golden_cmd" >&2
fi

# Results: one bundle where the host runner would put it (merged across shards).
found=()
for index in "${!split[@]}"; do
    [[ -d "$stage/results/$index/run.xcresult" ]] && found+=("$stage/results/$index/run.xcresult")
done
if ((${#found[@]} == 1)); then
    mv "${found[0]}" "$bundle"
elif ((${#found[@]} > 1)); then
    xcrun xcresulttool merge "${found[@]}" --output-path "$bundle" >/dev/null
fi
if [[ -d "$bundle" ]]; then
    log "result bundle: $repo/$bundle"
elif ((status == 0)); then
    echo "e2e-vm: the guest produced no result bundle" >&2
    status=1
fi
prune_results "$results" 10 || true

log "total $(elapsed $((SECONDS - start))) (build $(elapsed $((build_done - start))), exit $status)"
exit "$status"
