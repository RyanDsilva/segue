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
#   2. Fails unless the signed entitlements of every Release or AppStore product
#      (Release-AppStore, Debug-AppStore, Release-Personal) are exactly the app's set
#      (`app_entitlements` in scripts/lib/verify-common.sh: sandbox, user-selected files,
#      app-scope bookmarks, `network.client` (A61), and the Shortcuts Events Apple-events pair
#      (R59)), plus only the get-task-allow that local development signing adds. So the E2E
#      temporary exception, or any other extra key, fails.
#   3. Fails if the Release-AppStore binary carries a test hook (a launch-option flag,
#      RecordingShortcutRunner) or an editor perf notice (WS1 4.8a/4.8f).
#   4. Fails if the embedded SegueUI resource bundle lacks the real identifier or the app's
#      copyright and version (B-6).
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

# check_quicklook <configuration>: the App Store app embeds exactly SegueQuickLook.appex (WS2b
# 4.7, I-14) with the App Store extension ID, signed with the sandbox entitlement, with no
# personal-package symbols, and its SegueUI resource bundle stamped like the app's.
check_quicklook() {
    local config="$1" app="$products/$1/Segue.app" plugins appex id ent
    plugins=$(cd "$app/Contents/PlugIns" 2>/dev/null && find . -maxdepth 1 -name '*.appex' \
        | sed 's|^\./||' | sort | tr '\n' ' ')
    if [[ "$plugins" != "SegueQuickLook.appex " ]]; then
        fail "$config: PlugIns must hold exactly SegueQuickLook.appex (found: ${plugins:-none})"
        return
    fi
    appex="$app/Contents/PlugIns/SegueQuickLook.appex"
    id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$appex/Contents/Info.plist" \
        2>/dev/null || true)
    if [[ "$id" == "dev.ryandsilva.segue.quicklook" ]]; then
        pass "$config: Quick Look extension is $id"
    else
        fail "$config: Quick Look extension identifier is '${id:-unreadable}'"
    fi
    if ent=$(codesign -d --entitlements - --xml "$appex" 2>/dev/null | plutil -convert json -o - - \
        2>/dev/null) && [[ $(jq -r '."com.apple.security.app-sandbox"' <<<"$ent") == "true" ]] \
        && [[ $(jq -r 'del(."com.apple.security.app-sandbox", ."com.apple.security.get-task-allow")
            | keys | length' <<<"$ent") == "0" ]]; then
        pass "$config: Quick Look extension is sandboxed with nothing else"
    else
        fail "$config: Quick Look extension entitlements are not exactly the sandbox: ${ent:-unreadable}"
    fi
    local binary hits=""
    for binary in "$appex"/Contents/MacOS/*; do
        if nm -a "$binary" 2>/dev/null | grep -E -q "$forbidden"; then
            hits+="$binary"$'\n'
        fi
    done
    if [[ -n "$hits" ]]; then
        fail "$config: personal-package symbols in the Quick Look extension:"$'\n'"$hits"
    else
        pass "$config: no personal-package symbols in the Quick Look extension"
    fi
    check_resource_bundle "$config Quick Look" "$appex"
}

# check_entitlements <configuration>: the signed entitlements must be exactly
# `app_entitlements`, ignoring only get-task-allow (local development signing adds it; the
# exported store build is checked without it by verify-archive check 4). Fails closed when
# the entitlements cannot be read.
check_entitlements() {
    local config="$1" app="$products/$1/Segue.app" got want
    [[ -d "$app" ]] || { fail "$config: no product at $app"; return; }
    if ! got=$(codesign -d --entitlements - --xml "$app" 2>/dev/null \
        | plutil -convert json -o - - 2>/dev/null \
        | jq -S 'del(."com.apple.security.get-task-allow")') || [[ -z "$got" ]]; then
        fail "$config: could not read signed entitlements"
        return
    fi
    want=$(app_entitlements)
    if [[ "$got" == "$want" ]]; then
        pass "$config: signed entitlements are exactly the app's set ($(jq 'length' <<<"$got") keys)"
    else
        fail "$config: signed entitlements differ from the app's set:"$'\n'"$(diff <(echo "$want") <(echo "$got"))"
    fi
}

# check_apple_events_usage <configuration>: Path SE needs the Automation prompt's text.
check_apple_events_usage() {
    local config="$1" plist="$products/$1/Segue.app/Contents/Info.plist" value
    value=$(/usr/libexec/PlistBuddy -c "Print :NSAppleEventsUsageDescription" "$plist" 2>/dev/null) || value=""
    if [[ -n "$value" ]]; then
        pass "$config: NSAppleEventsUsageDescription is set"
    else
        fail "$config: NSAppleEventsUsageDescription missing (Path SE, R59)"
    fi
}

for config in Release-AppStore Debug-AppStore; do
    build Segue-AppStore "$config"
    check_personal_free "$config"
    check_entitlements "$config"
done
check_apple_events_usage Release-AppStore
check_quicklook Release-AppStore
check_no_test_hooks Release-AppStore "$products/Release-AppStore/Segue.app/Contents/MacOS/Segue"
check_resource_bundle Release-AppStore "$products/Release-AppStore/Segue.app"

build Segue-Personal Release-Personal
check_entitlements Release-Personal

if ((failures > 0)); then
    echo "verify-appstore: $failures check(s) failed" >&2
    exit 1
fi
echo "verify-appstore: all checks passed"
