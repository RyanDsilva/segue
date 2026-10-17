#!/usr/bin/env bash
# Runs xcodebuild against the generated workspace and fails if Xcode recorded any warning
# (compiler warnings are already errors; this also catches linker, asset and
# project-settings warnings). Usage: scripts/xcodebuild.sh <xcodebuild args...>
#
# Signing: automatic signing needs -allowProvisioningUpdates so Xcode can create or refresh
# the certificate and provisioning profiles from the command line.
set -euo pipefail
cd "$(dirname "$0")/.."

derived="${SEGUE_DERIVED_DATA:-.build/DerivedData}"
results=".build/results"
mkdir -p "$results"
bundle="$results/$(date +%Y%m%d-%H%M%S)-$$.xcresult"

status=0
xcodebuild \
    -workspace Segue.xcworkspace \
    -destination 'platform=macOS,arch=arm64' \
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

exit $status
