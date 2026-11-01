#!/usr/bin/env bash
# `make gate` after its prerequisites (generate, lint, repo-check, generated-file checks,
# the Personal build): the workstream gate (docs/test-performance.md C1).
#
#   1. Package tests side by side with the App Store build: verify-appstore when a path it
#      guards changed, else the plain Debug-AppStore build. Then the timing-budget tests
#      alone (they must not share the CPU).
#   2. E2E: the smoke set plus the classes UITests/e2e-map.tsv maps the changed paths to.
#      A changed path no line matches runs the full suite.
#
# Changed paths: everything that differs between the merge base with GATE_BASE (default
# origin/main) and the working tree, plus untracked files. `make check` stays the release
# gate and always runs everything.
#
# Environment: GATE_BASE (base ref), E2E_SMOKE (space-separated test IDs, from the Makefile),
# E2E_RUNNER (where E2E runs, scripts/e2e-run.sh; the Makefile defaults it to the VM),
# GATE_DRY_RUN=1 (print the plan, run nothing).
set -euo pipefail
cd "$(dirname "$0")/.."

base="${GATE_BASE:-origin/main}"
map="UITests/e2e-map.tsv"
read -r -a smoke <<<"${E2E_SMOKE:?E2E_SMOKE is not set (run through make gate)}"

if ! merge_base=$(git merge-base "$base" HEAD 2>/dev/null); then
    echo "gate: base ref '$base' not found; set GATE_BASE (for example GATE_BASE=main)" >&2
    exit 2
fi

changed=$(
    {
        git diff --name-only "$merge_base"
        git ls-files --others --exclude-standard
    } | sort -u
)

# Paths whose change needs the full verify-appstore (the App Store flavour's contents).
verify_globs=(
    'Project.swift' 'Tuist/*' 'App/*.entitlements' 'App/Sources/LaunchOptions.swift'
    'Packages/*/Package.swift' 'Packages/SeguePersonalModules/*' 'scripts/verify-*.sh'
    'scripts/lib/verify-common.sh' 'Extensions/*'
)

all=false
needs_verify=false
classes=()
unmapped=()
while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    for glob in "${verify_globs[@]}"; do
        # shellcheck disable=SC2053 # the glob is a pattern on purpose
        [[ "$path" == $glob ]] && needs_verify=true
    done
    matched=false
    while IFS=$'\t' read -r glob targets; do
        [[ -z "$glob" || "$glob" == \#* ]] && continue
        # shellcheck disable=SC2053
        [[ "$path" == $glob ]] || continue
        matched=true
        case "$targets" in
            ALL) all=true ;;
            NONE) ;;
            *) read -r -a found <<<"$targets" && classes+=("${found[@]}") ;;
        esac
    done <"$map"
    $matched || unmapped+=("$path")
done <<<"$changed"
((${#unmapped[@]} == 0)) || all=true

echo "gate: base $base ($(git rev-parse --short "$merge_base")), $(grep -c . <<<"$changed" || true) changed path(s)"
((${#unmapped[@]} == 0)) || printf 'gate: unmapped (full suite): %s\n' "${unmapped[@]}"
$needs_verify && echo "gate: App Store contents may have changed: verify-appstore"

# The E2E selection: classes, then the smoke tests not already inside one of them.
only=()
if $all; then
    echo "gate: E2E: the full suite"
else
    selected=$(printf '%s\n' "${classes[@]}" | sed '/^$/d' | sort -u)
    for class in $selected; do
        only+=("$class")
    done
    for test in "${smoke[@]}"; do
        grep -qx "${test%%/*}" <<<"$selected" || only+=("$test")
    done
    echo "gate: E2E: ${only[*]}"
fi
echo "gate: E2E runner: ${E2E_RUNNER:-host}"

if [[ "${GATE_DRY_RUN:-}" == 1 ]]; then
    exit 0
fi

appstore="make --no-print-directory build-appstore"
$needs_verify && appstore="make --no-print-directory verify-appstore"
scripts/parallel.sh tests "make --no-print-directory test-packages" appstore "$appstore"
make --no-print-directory test-perf

# E2E through the runner port (E2E_RUNNER from the Makefile: the VM by default).
args=()
if ! $all; then
    for id in "${only[@]}"; do
        args+=("-only-testing:SegueUITests/$id")
    done
fi
scripts/e2e-run.sh "${args[@]}"
