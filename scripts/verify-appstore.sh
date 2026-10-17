#!/usr/bin/env bash
# Builds the App Store flavor and fails if anything from SeguePersonalModules leaks into it.
#
# Stage-1 stub: only builds the scheme. The symbol/path/link-map assertions are added by
# the verify-appstore work item.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/xcodebuild.sh -scheme Segue-AppStore -configuration Release-AppStore build

echo "verify-appstore: TODO assert no SeguePersonalModules symbols/paths in the product" >&2
