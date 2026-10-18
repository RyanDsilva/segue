#!/usr/bin/env bash
# Syncs GitHub labels to .github/labels.yml with the gh CLI (creates missing labels and
# updates colour and description of existing ones).
#
#   scripts/sync-labels.sh             apply to the repo gh resolves from the git remote
#   DRY_RUN=1 scripts/sync-labels.sh   print the gh commands instead of running them
#   PRUNE=1 scripts/sync-labels.sh     also delete labels that are not in labels.yml
#                                      (GitHub's defaults: bug, enhancement, ...)
#   REPO=owner/name                    target another repo
#
# Changes GitHub settings: run it only with Ryan's go-ahead (docs/github-setup.md).
# Needs gh (authenticated) and yq (pinned in .mise.toml; `make labels-sync` provides it).
set -euo pipefail
cd "$(dirname "$0")/.."

file=.github/labels.yml
repo_args=()
if [[ -n "${REPO:-}" ]]; then
    repo_args=(--repo "$REPO")
fi

run() {
    if [[ -n "${DRY_RUN:-}" ]]; then
        printf '%q ' "$@"
        printf '\n'
    else
        "$@"
    fi
}

wanted=()
while IFS=$'\t' read -r name color description; do
    wanted+=("$name")
    run gh label create "$name" --color "$color" --description "$description" --force \
        ${repo_args[@]+"${repo_args[@]}"}
done < <(yq -r '.[] | [.name, .color, .description] | @tsv' "$file")

if [[ -n "${PRUNE:-}" ]]; then
    while IFS= read -r existing; do
        keep=no
        for name in "${wanted[@]}"; do
            if [[ "$name" == "$existing" ]]; then
                keep=yes
                break
            fi
        done
        if [[ "$keep" == no ]]; then
            run gh label delete "$existing" --yes ${repo_args[@]+"${repo_args[@]}"}
        fi
    done < <(gh label list --limit 500 --json name --jq '.[].name' ${repo_args[@]+"${repo_args[@]}"})
fi
