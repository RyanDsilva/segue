#!/usr/bin/env bash
# The XCUITest classes of SegueUITests and their test counts, read from the sources (the
# App Store capture target, UITests/AppStore, is a different target and left out). Used by
# scripts/e2e-vm.sh to split the suite over two VMs (E2E_VM_SHARDS=2).
#
# Usage: scripts/lib/e2e-classes.sh weighted     classes, heaviest first
#        scripts/lib/e2e-classes.sh count CLASS  that class's test count (1 if unknown)
set -euo pipefail
cd "$(dirname "$0")/../.."

counts() {
    # shellcheck disable=SC2016 # $2 and friends are awk fields
    find UITests -maxdepth 1 -name '*.swift' -print0 | sort -z | xargs -0 awk '
        /^(final )?class [A-Za-z0-9_]+/ { sub(/^final /, ""); split($2, a, ":"); type = a[1] }
        /^extension [A-Za-z0-9_]+/ { split($2, a, ":"); type = a[1] }
        /^[[:space:]]+(@MainActor[[:space:]]+)?func test[A-Za-z0-9_]*\(/ { if (type != "") n[type]++ }
        END { for (t in n) print n[t], t }'
}

case "${1:-}" in
    weighted) counts | sort -k1,1nr -k2 | awk '{print $2}' ;;
    count) counts | awk -v c="${2:?class}" '$2 == c {print $1; found = 1} END {if (!found) print 1}' ;;
    *)
        echo "usage: scripts/lib/e2e-classes.sh weighted | count CLASS" >&2
        exit 2
        ;;
esac
