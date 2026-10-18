#!/usr/bin/env bash
# Moves known throwaway local build clutter to the Trash (`make clean-local`). Everything
# here is git-ignored and regenerated on demand; nothing tracked is touched.
#
# Removed: per-agent SwiftPM scratch (Packages/*/.build-*), per-agent DerivedData copies
# (.build/DerivedData-*), result bundles beyond the newest 10, the old editor screenshot
# export, XCUITest attachment exports (.build/att-*), run logs, the one-off export-shots.sh,
# and the Cloudflare Pages emulator state (.wrangler).
#
# Kept: the live .build/DerivedData (scripts/xcodebuild.sh) and .build/DerivedData-verify
# (scripts/verify-appstore.sh), the live SwiftPM caches (Packages/*/.build), Tuist/.build,
# the rest of .build/screenshots, design/icon/previews and .build/make.lock.
#
# Refuses to run while a build is going, so it never pulls a directory from under xcodebuild.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=lib/discard.sh
source scripts/lib/discard.sh

if pgrep -x xcodebuild >/dev/null || pgrep -x swift-build >/dev/null; then
    echo "clean-local: a build is running (xcodebuild or swift-build); try again when it ends" >&2
    exit 1
fi

shopt -s nullglob
targets=(Packages/*/.build-*/ .build/att-*/ .build/*.log .build/*.log.build)
for dir in .build/DerivedData-*/; do
    [[ "$dir" == ".build/DerivedData-verify/" ]] || targets+=("$dir")
done
for path in .build/screenshots/editor .build/export-shots.sh .wrangler; do
    [[ -e "$path" ]] && targets+=("$path")
done

before=$(du -sk . | cut -f1)
if ((${#targets[@]} > 0)); then
    printf 'clean-local: %s\n' "${targets[@]%/}"
    discard "${targets[@]%/}"
fi
prune_results .build/results 10
after=$(du -sk . | cut -f1)
echo "clean-local: freed $(((before - after) / 1024)) MB in the repo (in the Trash until it is emptied)"
