#!/usr/bin/env bash
# Shared by scripts/verify-appstore.sh and scripts/verify-archive.sh so their checks cannot
# drift. Source it from the repo root after defining `prefix` (the line prefix, e.g.
# "verify-appstore"). Provides `forbidden`, `perf_strings`, `test_hook_strings`,
# `app_entitlements`, `fail`, `pass`, `failures`, `check_no_test_hooks`,
# `check_resource_bundle` and `check_third_party_notices`.

# Anything that can only come from the personal package or its compilation condition.
forbidden='SeguePersonalModules|PersonalModules|SEGUE_PERSONAL'

# Editor performance notices that exist in Debug builds only (WS1 4.8a).
perf_strings=('slow key' 'slow keystroke' 'slow run loop turn')

# Test-only hooks that must never ship (WS1 4.8f, B-7): every launch-option flag in
# App/Sources/LaunchOptions.swift (extracted from the source, so new flags are covered
# automatically), the UI-testing flag, and the recording Shortcut runner. WS5 adds its own
# flag strings here only if they are not already LaunchOptions keys.
test_hook_strings() {
    local source="App/Sources/LaunchOptions.swift" flags
    flags=$(grep -o -E '"-Segue[A-Za-z]+"' "$source" | tr -d '"' | sort -u) || true
    if [[ -z "$flags" ]]; then
        echo "error: no launch-option flags found in $source" >&2
        return 1
    fi
    printf '%s\n' "$flags" "-SegueUITesting" "RecordingShortcutRunner"
}

# app_entitlements: the app's own entitlements as sorted JSON, the same in both flavors'
# Release builds (App/SegueAppStore.entitlements, App/Segue.entitlements). Signing adds the
# identifiers on top (verify-archive) or get-task-allow for local development builds
# (verify-appstore); anything else is a failure. The Apple-events pair is Path SE
# (docs/release/decisions.md R59): Gig Mode Shortcuts run through Shortcuts Events, limited
# to its one Apple-published access group. The app group is the downloaded-model store shared
# by both flavors (docs/release/decisions.md R67, R100): team-prefixed, so macOS needs no portal
# registration and no profile entry for it.
app_entitlements() {
    jq -n -S '{
        "com.apple.security.app-sandbox": true,
        "com.apple.security.files.user-selected.read-write": true,
        "com.apple.security.files.bookmarks.app-scope": true,
        "com.apple.security.network.client": true,
        "com.apple.security.automation.apple-events": true,
        "com.apple.security.scripting-targets": {
            "com.apple.shortcuts.events": ["com.apple.shortcuts.run"]
        },
        "com.apple.security.application-groups": ["V6BM673U35.dev.ryandsilva.segue.models"]
    }'
}

failures=0
fail() {
    echo "${prefix:-verify}: FAIL: $*" >&2
    failures=$((failures + 1))
}
pass() {
    echo "${prefix:-verify}: ok: $*"
}

# check_no_test_hooks <label> <binary>: fails if the binary carries any perf notice or
# test-hook string. Fails closed when the binary or the string list cannot be read.
check_no_test_hooks() {
    local label="$1" binary="$2" hooks hits=""
    if [[ ! -r "$binary" ]]; then
        fail "$label: cannot read $binary"
        return
    fi
    if ! hooks=$(test_hook_strings); then
        fail "$label: could not build the test-hook string list"
        return
    fi
    local needle
    while IFS= read -r needle; do
        if grep -a -q -F -e "$needle" "$binary"; then
            hits+="$needle"$'\n'
        fi
    done < <(printf '%s\n' "${perf_strings[@]}" "$hooks")
    if [[ -n "$hits" ]]; then
        fail "$label: test-only strings in $binary:"$'\n'"$hits"
    else
        pass "$label: no perf notices or test-hook strings in the binary"
    fi
}

# check_resource_bundle <label> <app>: the embedded SegueUI resource bundle carries the real
# identifier and the app's copyright and version (B-6, scripts/stamp-resource-bundle.sh),
# not Tuist's placeholders. Fails closed on an unreadable plist.
check_resource_bundle() {
    local label="$1" app="$2"
    local app_plist="$app/Contents/Info.plist"
    local bundle_plist="$app/Contents/Resources/SegueUI_SegueUI.bundle/Contents/Info.plist"
    local key want got problems=""
    if [[ ! -r "$app_plist" || ! -r "$bundle_plist" ]]; then
        fail "$label: cannot read $app_plist or $bundle_plist"
        return
    fi
    if ! got=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$bundle_plist" 2>/dev/null) \
        || [[ "$got" != "dev.ryandsilva.segue.SegueUI.resources" ]]; then
        problems+="CFBundleIdentifier='${got:-}' "
    fi
    for key in NSHumanReadableCopyright CFBundleShortVersionString CFBundleVersion; do
        want=$(/usr/libexec/PlistBuddy -c "Print :$key" "$app_plist" 2>/dev/null) || want=""
        got=$(/usr/libexec/PlistBuddy -c "Print :$key" "$bundle_plist" 2>/dev/null) || got=""
        if [[ -z "$want" || "$got" != "$want" ]]; then
            problems+="$key='$got' (app '$want') "
        fi
    done
    if [[ -n "$problems" ]]; then
        fail "$label: SegueUI resource bundle plist is not stamped: $problems"
    else
        pass "$label: SegueUI resource bundle has the real identifier, copyright and version"
    fi
}

# check_third_party_notices <label> <app>: the notices accompany the binary (MIT, OFL 1.1)
# though the app shows none in its UI: THIRD_PARTY_NOTICES.md in Contents/Resources and the
# full licence texts in the SegueUI resource bundle.
check_third_party_notices() {
    local label="$1" app="$2" file missing=""
    local resources="$app/Contents/Resources"
    for file in THIRD_PARTY_NOTICES.md SegueUI_SegueUI.bundle/Contents/Resources/Licenses/GRDB.txt \
        SegueUI_SegueUI.bundle/Contents/Resources/Licenses/Tonic.txt \
        SegueUI_SegueUI.bundle/Contents/Resources/Licenses/Sentry.txt \
        SegueUI_SegueUI.bundle/Contents/Resources/Fonts/OFL.txt; do
        [[ -s "$resources/$file" ]] || missing+="$file "
    done
    if [[ -n "$missing" ]]; then
        fail "$label: third-party notices missing from the bundle: $missing"
    else
        pass "$label: third-party notices and licence texts ship in the bundle"
    fi
}
