#!/usr/bin/env bash
# The one entry point for running the XCUITest suite (R180): `make e2e`, `e2e-smoke`,
# `e2e-one`, `e2e-vm`, `gate` and `check` all come through here, so the runner is chosen in
# one place and every runner takes the same selection.
#
# Usage: scripts/e2e-run.sh [-only-testing:SegueUITests/Class[/test]...]   (none: full suite)
#
# E2E_RUNNER picks the adapter:
#   host  xcodebuild test on this Mac, as before (takes the screen, pointer and keyboard)
#   vm    build here, test in a throwaway Tart VM clone (scripts/e2e-vm.sh, lib/e2e-vm-tart.sh)
#   lume  the same flow on Lume, the MIT escape hatch (lib/e2e-vm-lume.sh)
# The Makefile sets the default per target (vm for e2e, e2e-smoke and gate; host for
# e2e-one); called directly the default is host.
set -euo pipefail
cd "$(dirname "$0")/.."

case "${E2E_RUNNER:-host}" in
    host) exec scripts/xcodebuild.sh -scheme Segue-Personal -configuration Debug-Personal test "$@" ;;
    vm | tart) exec scripts/e2e-vm.sh tart "$@" ;;
    lume) exec scripts/e2e-vm.sh lume "$@" ;;
    *)
        echo "e2e-run: E2E_RUNNER must be host, vm or lume (got '${E2E_RUNNER}')" >&2
        exit 2
        ;;
esac
