#!/usr/bin/env bash
# SegueUI's String Catalog (P9-5 4.3): every UI string the compiler extracts from a build of
# the package (Swift Build writes one .stringsdata per source file) is in
# Packages/SegueUI/Sources/SegueUI/Localizable.xcstrings, and nothing stale is left there.
#
#   scripts/strings.sh          sync the catalog from the last build (`make strings` builds)
#   scripts/strings.sh --check  fail if syncing would change the committed catalog
#
# v1.0 is English only (R179): the catalog's English values are its keys, so a missing key
# never changes what the app shows; the check keeps the catalog complete for translation.
set -euo pipefail
cd "$(dirname "$0")/.."

catalog=Packages/SegueUI/Sources/SegueUI/Localizable.xcstrings
objects=Packages/SegueUI/.build/out/Intermediates.noindex/SegueUI.build/Debug/SegueUI-t.build/Objects-normal/arm64

# Only the files of sources that still exist (a deleted file's .stringsdata lingers).
data=()
while IFS= read -r -d '' file; do
    source=$(/usr/bin/plutil -extract source raw -o - "$file" 2>/dev/null) || continue
    [[ -f "$source" ]] && data+=(--stringsdata "$file")
done < <(find "$objects" -name '*.stringsdata' -print0 2>/dev/null)
if ((${#data[@]} == 0)); then
    echo "strings: no .stringsdata under $objects; build SegueUI with Swift Build first" >&2
    exit 1
fi

if [[ "${1:-}" == "--check" ]]; then
    scratch=$(mktemp -d)
    cp "$catalog" "$scratch/Localizable.xcstrings"
    xcrun xcstringstool sync "$scratch/Localizable.xcstrings" "${data[@]}"
    if ! cmp -s "$catalog" "$scratch/Localizable.xcstrings"; then
        echo "strings: FAIL: $catalog is out of date with the code; run make strings" >&2
        diff <(grep '^    "' "$catalog") <(grep '^    "' "$scratch/Localizable.xcstrings") | head -20 >&2 || true
        exit 1
    fi
    echo "strings: ok: $catalog has every UI string and nothing stale"
    exit 0
fi
xcrun xcstringstool sync "$catalog" "${data[@]}"
echo "strings: synced $catalog"
