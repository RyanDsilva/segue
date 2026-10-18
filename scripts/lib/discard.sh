#!/usr/bin/env bash
# Shared by scripts/xcodebuild.sh and scripts/clean-local.sh. Source it from the repo root.
#
# discard PATH...
#   Moves each existing path to the Trash with macOS /usr/bin/trash, so a wrong prune is
#   recoverable from Finder. trash can fail where there is no Finder session or Trash to
#   move into (a sandboxed agent shell, ssh, a volume without .Trashes); then the path is
#   removed file by file with `find -delete`, quietly. That fallback only ever sees
#   git-ignored build output (result bundles, scratch dirs, logs), which is regenerated.
discard() {
    local path
    for path in "$@"; do
        [[ -e "$path" || -L "$path" ]] || continue
        if ! /usr/bin/trash "$path" >/dev/null 2>&1; then
            find "$path" -depth -delete 2>/dev/null || true
        fi
    done
}

# prune_results DIR KEEP
#   Keeps the newest KEEP .xcresult bundles in DIR and discards the rest. Bundle names
#   start with a sortable timestamp (scripts/xcodebuild.sh), so name order is age order.
prune_results() {
    local dir="$1" keep="$2" bundle
    local -a bundles=()
    [[ -d "$dir" ]] || return 0
    while IFS= read -r bundle; do
        bundles+=("$bundle")
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -name '*.xcresult' | LC_ALL=C sort -r)
    if ((${#bundles[@]} > keep)); then
        discard "${bundles[@]:keep}"
    fi
}
