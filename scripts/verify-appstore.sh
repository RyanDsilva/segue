#!/usr/bin/env bash
# Proves the App Store flavor is clean (docs/phases/0-walking-skeleton.md, docs/decisions.md
# "Phase 0 build rulings"):
#
#   1. Builds Segue-AppStore in Release-AppStore and Debug-AppStore with a link map, and fails
#      if anything from SeguePersonalModules appears in
#        - the build graph (the build description Xcode planned for that build),
#        - the per-configuration intermediates and products,
#        - the linker map,
#        - the .app bundle (any file: binary strings, symbols, resources) or its linked
#          libraries.
#   2. Fails if the E2E temporary-exception entitlement is in the signed entitlements of any
#      Release or AppStore product (Release-AppStore, Debug-AppStore, Release-Personal), or if
#      `network.client` is missing from them (A61: both flavors make outgoing connections).
#   3. Fails if the Release-AppStore binary carries a test hook (a launch-option flag,
#      RecordingShortcutRunner) or an editor perf notice (WS1 4.8a/4.8f).
#
# The flavors have separate bundle IDs (docs/release/decisions.md R11): the App Store build is
# dev.ryandsilva.segue (App/SegueAppStore.entitlements), Personal is
# dev.ryandsilva.segue.personal (App/Segue.entitlements).
#
# Uses its own DerivedData (SEGUE_VERIFY_DERIVED_DATA, default .build/DerivedData-verify) so
# Personal builds never share intermediates with the checked App Store build.
set -euo pipefail
cd "$(dirname "$0")/.."

derived="${SEGUE_VERIFY_DERIVED_DATA:-.build/DerivedData-verify}"
products="$derived/Build/Products"
intermediates="$derived/Build/Intermediates.noindex"

# `forbidden`, the test-hook strings and fail/pass come from the shared library so this
# script and verify-archive.sh cannot drift.
prefix="verify-appstore"
# shellcheck source=lib/verify-common.sh
source scripts/lib/verify-common.sh
# The Debug-only E2E sandbox exception (App/Segue-Debug.entitlements).
exception='com\.apple\.security\.temporary-exception'

# build <scheme> <configuration>: builds with a link map so the linker inputs are recorded.
build() {
    SEGUE_DERIVED_DATA="$derived" scripts/xcodebuild.sh \
        -scheme "$1" -configuration "$2" \
        LD_GENERATE_MAP_FILE=YES \
        build
}

# check_personal_free <configuration>: every App Store leak check for one configuration.
check_personal_free() {
    local config="$1" app="$products/$1/Segue.app" hits
    [[ -d "$app" ]] || { fail "$config: no product at $app"; return; }

    # Build graph: every build description Xcode planned that produces this configuration's
    # app (incremental builds reuse a description, so match by product, not by mtime).
    local manifests
    manifests=$(grep -l -F "Build/Products/$config/Segue.app" \
        "$intermediates"/XCBuildData/*.xcbuilddata/manifest.json 2>/dev/null || true)
    if [[ -z "$manifests" ]]; then
        fail "$config: no build description found under $intermediates/XCBuildData"
    else
        hits=$(tr '\n' '\0' <<<"$manifests" | xargs -0 grep -l -E "$forbidden" || true)
        if [[ -n "$hits" ]]; then
            fail "$config: build graph references the personal package:"$'\n'"$hits"
        else
            pass "$config: build graph has no personal-package tasks"
        fi
    fi

    # Intermediates and products for this configuration.
    hits=$(find "$intermediates" "$products/$config" -path "*/$config/*" \
        -iname '*SeguePersonalModules*' -print 2>/dev/null | head -n 5)
    if [[ -n "$hits" ]]; then
        fail "$config: personal-package build outputs present:"$'\n'"$hits"
    else
        pass "$config: no personal-package intermediates or products"
    fi

    # Link map(s) for the app executable.
    local maps
    maps=$(find "$intermediates" -path "*/$config/SegueAppStore.build/*" \
        -name '*LinkMap*.txt' -print 2>/dev/null)
    if [[ -z "$maps" ]]; then
        fail "$config: no link map generated for SegueAppStore"
    else
        while IFS= read -r map; do
            if grep -E -q "$forbidden" "$map"; then
                fail "$config: link map references the personal package ($map)"
            else
                pass "$config: link map clean ($(basename "$map"))"
            fi
        done <<<"$maps"
    fi

    # The bundle: every file's bytes, the executable's symbols and its linked libraries.
    hits=$(grep -r -l -a -E "$forbidden" "$app" 2>/dev/null || true)
    if [[ -n "$hits" ]]; then
        fail "$config: bundle files mention the personal package:"$'\n'"$hits"
    else
        pass "$config: no personal-package strings anywhere in the bundle"
    fi
    # Every Mach-O in Contents/MacOS (Debug splits the code into Segue.debug.dylib).
    local binary symbol_hits=""
    for binary in "$app"/Contents/MacOS/*; do
        if nm -a "$binary" 2>/dev/null | grep -E -q "$forbidden" \
            || otool -L "$binary" 2>/dev/null | grep -E -q "$forbidden"; then
            symbol_hits+="$binary"$'\n'
        fi
    done
    if [[ -n "$symbol_hits" ]]; then
        fail "$config: personal-package symbols or linked libraries in:"$'\n'"$symbol_hits"
    else
        pass "$config: no personal-package symbols or linked libraries"
    fi
}

# check_no_exception <configuration>: the signed entitlements must not carry the E2E
# temporary exception and must carry network.client. Requires the sandbox key so a failed
# extraction cannot pass.
check_no_exception() {
    local config="$1" app="$products/$1/Segue.app" entitlements
    [[ -d "$app" ]] || { fail "$config: no product at $app"; return; }
    if ! entitlements=$(codesign -d --entitlements - --xml "$app" 2>/dev/null); then
        fail "$config: could not read signed entitlements"
        return
    fi
    if ! grep -q 'com.apple.security.app-sandbox' <<<"$entitlements"; then
        fail "$config: signed entitlements unreadable or not sandboxed"
    elif grep -E -q "$exception" <<<"$entitlements"; then
        fail "$config: signed entitlements carry the temporary-exception entitlement"
    else
        pass "$config: signed entitlements have no temporary exception"
    fi
    if grep -q 'com.apple.security.network.client' <<<"$entitlements"; then
        pass "$config: signed entitlements carry network.client"
    else
        fail "$config: signed entitlements lack network.client"
    fi
}

for config in Release-AppStore Debug-AppStore; do
    build Segue-AppStore "$config"
    check_personal_free "$config"
    check_no_exception "$config"
done
check_no_test_hooks Release-AppStore "$products/Release-AppStore/Segue.app/Contents/MacOS/Segue"

build Segue-Personal Release-Personal
check_no_exception Release-Personal

if ((failures > 0)); then
    echo "verify-appstore: $failures check(s) failed" >&2
    exit 1
fi
echo "verify-appstore: all checks passed"
