#!/bin/bash
# R35 probe run (docs/release/specs/WS1-release-pipeline.md 4.10, section 5 step 8.3).
# Usage: run.sh <shortcut name> <event|permission>
# Launches the probe through LaunchServices so TCC attributes the Automation request to the
# probe app, not Terminal, then prints its one JSON line.
set -euo pipefail

if [[ $# -ne 2 ]]; then
	echo "usage: $0 <shortcut name> <event|permission>" >&2
	exit 2
fi

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
app="$root/.build/shortcuts-probe/ShortcutsEventsProbe.app"
results="$root/.build/shortcuts-probe/results"
[[ -d "$app" ]] || { echo "probe app missing; run 'make probe-shortcuts' first" >&2; exit 1; }

mkdir -p "$results"
slug=$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')
out="$results/$(date +%Y%m%d-%H%M%S)-$slug-$2.json"
open -W -n --stdout "$out" --stderr "$out" "$app" --args "$1" "$2"
command cat "$out"
