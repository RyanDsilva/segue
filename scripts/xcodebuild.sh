#!/usr/bin/env bash
# Runs xcodebuild against the generated workspace and fails if Xcode recorded any warning
# (compiler warnings are already errors; this also catches linker, asset and
# project-settings warnings). Usage: scripts/xcodebuild.sh <xcodebuild args...>
#
# Destination: SEGUE_DESTINATION overrides the default `platform=macOS,arch=arm64` (the
# release archive passes `generic/platform=macOS`; ARCHS = arm64 keeps it one slice).
#
# Signing: automatic signing needs -allowProvisioningUpdates so Xcode can create or refresh
# the certificate and provisioning profiles from the command line.
#
# Result bundles: each run writes one to .build/results; only the newest $keep_results are
# kept (older ones go to the Trash, see scripts/lib/discard.sh), so they do not pile up.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=lib/discard.sh
source scripts/lib/discard.sh

derived="${SEGUE_DERIVED_DATA:-.build/DerivedData}"
destination="${SEGUE_DESTINATION:-platform=macOS,arch=arm64}"
results=".build/results"
keep_results=10
mkdir -p "$results"
bundle="$results/$(date +%Y%m%d-%H%M%S)-$$.xcresult"

status=0
xcodebuild \
    -workspace Segue.xcworkspace \
    -destination "$destination" \
    -derivedDataPath "$derived" \
    -resultBundlePath "$bundle" \
    -allowProvisioningUpdates \
    "$@" || status=$?

if [[ -d "$bundle" ]]; then
    summary=$(xcrun xcresulttool get build-results --path "$bundle")
    # Fail closed: an unreadable summary is an error, never "0 warnings".
    if ! warnings=$(/usr/bin/plutil -extract warningCount raw -o - - <<<"$summary"); then
        echo "error: could not read warningCount from $bundle" >&2
        exit 1
    fi
    if [[ "$warnings" != "0" ]]; then
        echo "error: build recorded $warnings warning(s):" >&2
        /usr/bin/plutil -extract warnings json -o - - <<<"$summary" >&2 || true
        [[ $status -eq 0 ]] && status=1
    fi
elif [[ $status -eq 0 ]]; then
    echo "error: xcodebuild produced no result bundle at $bundle" >&2
    status=1
fi

# Housekeeping never changes the build verdict.
prune_results "$results" "$keep_results" || true

exit $status
