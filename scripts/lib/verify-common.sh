#!/usr/bin/env bash
# Shared by scripts/verify-appstore.sh and scripts/verify-archive.sh so their checks cannot
# drift. Source it from the repo root after defining `prefix` (the line prefix, e.g.
# "verify-appstore"). Provides `forbidden`, `perf_strings`, `test_hook_strings`,
# `app_entitlements`, `fail`, `pass`, `failures`, `check_no_test_hooks`,
# `check_resource_bundle`, `check_third_party_notices`, `check_sound_bank` and
# `check_help_book`.

# Anything that can only come from the personal package or its compilation condition,
# including Settings > AI > Advanced custom models and the eval code "Check this model" runs
# (R62, R97: Personal only).
# SwiftSoup is the personal package's own dependency (P9-4); its notices ship only in the
# Personal app (THIRD_PARTY_NOTICES-Personal.md), so the App Store bundle never names it.
# P9-4 spec 13: the web import and song search, named so no core or SegueUI text can collide
# (a bare `echords` would match core's `inlineChords`; "ultimate guitar app" in JunkRules has a
# space, not the host's hyphen).
forbidden='SeguePersonalModules|PersonalModules|SEGUE_PERSONAL|AdvancedModels|AIEval|SwiftSoup|THIRD_PARTY_NOTICES-Personal|lrclib|LRCLIB|ultimate-guitar\.com|e-chords\.com|chordie\.com|TabJSONParser|ChordPreParser|ChordSpansParser|GenericPageReader|HindiRomanizer|URLSessionTransport|WebKitPageLoader|UGSearchReader|EChordsSearchReader|VersionRanker|ChallengeDetector|OpenHereSheet|FindLyricsModel|WebImportModel|ImportFixtureSet|SegueImportFixtures'

# Editor performance notices that exist in Debug builds only (WS1 4.8a).
perf_strings=('slow key' 'slow keystroke' 'slow run loop turn')

# Test-only hooks that must never ship (WS1 4.8f, B-7): every launch-option flag in
# App/Sources/LaunchOptions*.swift (extracted from the source, so new flags are covered
# automatically), the UI-testing flag, the recording Shortcut runner, and one of the Debug-only
# screenshot songs (App/Sources/Debug/ScreenshotSongs.swift, WS5 8.4.1), so they never ship.
# WS5 adds its own flag strings here only if they are not already LaunchOptions keys.
test_hook_strings() {
    local flags
    flags=$(grep -h -o -E '"-Segue[A-Za-z]+"' App/Sources/LaunchOptions*.swift | tr -d '"' | sort -u) || true
    if [[ -z "$flags" ]]; then
        echo "error: no launch-option flags found in App/Sources/LaunchOptions*.swift" >&2
        return 1
    fi
    printf '%s\n' "$flags" "-SegueUITesting" "RecordingShortcutRunner" "Lanterns on Pier Nine"
}

# app_entitlements: the app's own entitlements as sorted JSON, the same in both flavors'
# Release builds (App/SegueAppStore.entitlements, App/Segue.entitlements). Signing adds the
# identifiers on top (verify-archive) or get-task-allow for local development builds
# (verify-appstore); anything else is a failure. The Apple-events pair is Path SE
# (docs/release/decisions.md R59): Gig Mode Shortcuts run through Shortcuts Events, limited
# to its one Apple-published access group. The app group is the downloaded-model store shared
# by both flavors (docs/release/decisions.md R67, R100): team-prefixed, so macOS needs no portal
# registration and no profile entry for it. Printing is the PDF preview's Print... (P9-1 spec 10).
app_entitlements() {
    jq -n -S '{
        "com.apple.security.app-sandbox": true,
        "com.apple.security.files.user-selected.read-write": true,
        "com.apple.security.files.bookmarks.app-scope": true,
        "com.apple.security.network.client": true,
        "com.apple.security.print": true,
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
        SegueUI_SegueUI.bundle/Contents/Resources/Licenses/FluidR3.txt \
        SegueUI_SegueUI.bundle/Contents/Resources/Fonts/OFL.txt; do
        [[ -s "$resources/$file" ]] || missing+="$file "
    done
    if [[ -n "$missing" ]]; then
        fail "$label: third-party notices missing from the bundle: $missing"
    else
        pass "$label: third-party notices and licence texts ship in the bundle"
    fi
}

# check_sound_bank <label> <app>: the 11 MB sound bank (P8-6 section 12) ships exactly once,
# at Contents/Resources/SegueSounds.sf2, and nowhere else in the app: not in the SegueUI
# resource bundle and not in the Quick Look extension, which copies that bundle and never
# plays a sound.
check_sound_bank() {
    local label="$1" app="$2" copies
    copies=$(find "$app" -iname '*.sf2' -o -iname '*.sf3' -o -iname '*.dls' | sort)
    if [[ "$copies" == "$app/Contents/Resources/SegueSounds.sf2" ]]; then
        pass "$label: the sound bank ships once, at Contents/Resources/SegueSounds.sf2"
    else
        fail "$label: the sound bank must ship exactly once, at Contents/Resources:"$'\n'"${copies:-none}"
    fi
}

# guide_help_anchors: the Help Book anchor of every SegueLinks.Guide page (P9-5 3.4), from
# the raw values in SegueLinks.swift: the page slug, `<slug>-<id>` for a heading, `index` for
# the home. Mirrors `SegueLinks.Guide.helpAnchor`.
guide_help_anchors() {
    sed -n -E 's|^ *case [A-Za-z]+ = "https://segue\.ryandsilva\.dev/guide/?([^"]*)"$|\1|p' \
        Packages/SegueUI/Sources/SegueUI/App/SegueLinks.swift \
        | sed -E 's|^$|index|; s|#|-|'
}

# check_help_book <label> <app>: the offline Help Book (P9-5 3.3) ships in
# Contents/Resources/Segue.help, the Info.plist names it, it has its search index, and every
# in-app Help anchor is in it. Fails closed on anything unreadable.
check_help_book() {
    local label="$1" app="$2" book="$2/Contents/Resources/Segue.help" anchors anchor missing=""
    local pages="$book/Contents/Resources/en.lproj"
    if [[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleHelpBookFolder" "$app/Contents/Info.plist" 2>/dev/null)" != "Segue.help" \
        || "$(/usr/libexec/PlistBuddy -c "Print :CFBundleHelpBookName" "$app/Contents/Info.plist" 2>/dev/null)" != "dev.ryandsilva.segue.help" \
        || "$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$book/Contents/Info.plist" 2>/dev/null)" != "dev.ryandsilva.segue.help" ]]; then
        fail "$label: the Help Book is missing or not named in Info.plist ($book)"
        return
    fi
    if [[ ! -s "$pages/Segue.helpindex" || ! -s "$pages/index.html" ]]; then
        fail "$label: the Help Book has no index.html or Segue.helpindex"
        return
    fi
    if ! anchors=$(guide_help_anchors) || [[ -z "$anchors" ]]; then
        fail "$label: could not read the guide anchors from SegueLinks.swift"
        return
    fi
    while IFS= read -r anchor; do
        grep -q -r -F "<a name=\"$anchor\"></a>" "$pages" --include='*.html' || missing+="$anchor "
    done <<<"$anchors"
    if [[ -n "$missing" ]]; then
        fail "$label: Help anchors missing from the book: $missing"
    else
        pass "$label: the Help Book ships with every in-app anchor ($(wc -l <<<"$anchors" | tr -d ' '))"
    fi
}
