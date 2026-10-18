#!/usr/bin/env bash
# Shared by scripts/verify-appstore.sh and scripts/verify-archive.sh so their checks cannot
# drift. Source it from the repo root after defining `prefix` (the line prefix, e.g.
# "verify-appstore"). Provides `forbidden`, `perf_strings`, `test_hook_strings`, `fail`,
# `pass`, `failures` and `check_no_test_hooks`.

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
