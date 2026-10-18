#!/usr/bin/env bash
# Runs independent jobs side by side and fails if any of them failed (docs/test-performance.md
# A6/A7). Every output line is prefixed with its job's name, each job's wall time is
# reported, and the script waits for all jobs even after one fails, so no build is left
# running in the background.
#
# Usage: scripts/parallel.sh <name> <command> [<name> <command>...]
# Each command runs in `bash -c` from the repo root with `-eu -o pipefail`.
set -euo pipefail
cd "$(dirname "$0")/.."

if (($# == 0 || $# % 2 != 0)); then
    echo "usage: scripts/parallel.sh <name> <command> [<name> <command>...]" >&2
    exit 2
fi

names=()
pids=()
while (($# > 0)); do
    name="$1" command="$2"
    shift 2
    (
        start=$SECONDS
        status=0
        bash -eu -o pipefail -c "$command" 2>&1 | while IFS= read -r line; do
            printf '[%s] %s\n' "$name" "$line"
        done || status=$?
        printf '[%s] finished in %ds (exit %d)\n' "$name" $((SECONDS - start)) "$status"
        exit "$status"
    ) &
    names+=("$name")
    pids+=("$!")
done

failed=()
for index in "${!pids[@]}"; do
    if ! wait "${pids[$index]}"; then
        failed+=("${names[$index]}")
    fi
done

if ((${#failed[@]} > 0)); then
    echo "parallel: failed: ${failed[*]}" >&2
    exit 1
fi
