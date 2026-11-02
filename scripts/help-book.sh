#!/usr/bin/env bash
# The app's offline Apple Help Book (P9-5 3.3): the user guide built a second time in help
# mode (HELP_BOOK=1) and packaged by guide/scripts/helpbook.mjs into
# Derived/HelpBook/Segue.help, which both app targets copy into Contents/Resources.
#
#   scripts/help-book.sh          build it unless Derived/HelpBook/source.sha256 already
#                                 matches the sources (a no-op build costs one hash)
#   scripts/help-book.sh --check  fail if the book is missing or stale
#
# scripts/xcodebuild.sh runs it before every build, so `make build`, verify-appstore, E2E,
# docs-shots and the release archive all ship a current book; the Xcode build itself never
# runs Node (its build phase only checks the book is there). Builds share one lock so two
# concurrent builds never write the book at once.
set -euo pipefail
cd "$(dirname "$0")/.."

derived=Derived/HelpBook
book="$derived/Segue.help"
stamp="$derived/source.sha256"

current_hash() {
    mise exec -- node guide/scripts/helpbook.mjs --hash
}

up_to_date() {
    [[ -r "$book/Contents/Info.plist" && -r "$book/Contents/Resources/en.lproj/Segue.helpindex" \
        && -r "$stamp" ]] && [[ "$(command cat "$stamp")" == "$(current_hash)" ]]
}

if [[ "${1:-}" == "--check" ]]; then
    if up_to_date; then
        echo "help-book: ok: $book matches the guide sources"
        exit 0
    fi
    echo "help-book: FAIL: $book is missing or stale; run make help-book" >&2
    exit 1
fi

mkdir -p "$derived"
# The lock is held for the whole build; the second caller then finds the book current.
if [[ -z "${SEGUE_HELP_BOOK_LOCKED:-}" ]]; then
    exec lockf -k "$derived/.lock" env SEGUE_HELP_BOOK_LOCKED=1 "$0" "$@"
fi
if up_to_date; then
    exit 0
fi
echo "help-book: building $book from guide/"
(
    cd guide
    mise exec -- pnpm install --frozen-lockfile --silent
    HELP_BOOK=1 ASTRO_TELEMETRY_DISABLED=1 mise exec -- pnpm --silent exec astro build >/dev/null
)
mise exec -- node guide/scripts/helpbook.mjs
