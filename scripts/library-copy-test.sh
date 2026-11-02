#!/usr/bin/env bash
# The library copy test (R197; docs/release/v1.0-readiness.md 2.1): the current build opens a
# COPY of the owner's real library inside the E2E VM, runs every first-open upgrade on it
# (the timings folder to the Trash, the {duration} cleanup offer, sidecar and other schema
# migrations, the library identity and minReaderVersion of R196), and the result is diffed
# against an untouched copy for the owner to read.
#
#   scripts/library-copy-test.sh [<library folder>]      default: ~/Music/Segue
#
# The original folder is only ever read (cp), and its file listing and checksums are
# compared before and after, so the run proves it was not touched. Everything runs in a
# throwaway Tart VM through scripts/e2e-vm.sh (never XCUITest on the host). Output, all
# under .build (gitignored; song text never leaves the Mac):
#   .build/library-copy-test/<stamp>/pristine        the untouched copy
#   .build/library-copy-test/<stamp>/after-<scenario> the library after 1.0 opened it
#   .build/library-copy-test/<stamp>/trash-<scenario> what 1.0 moved to the Trash
#   .build/library-copy-test/<stamp>/report.md       the readable diff
# Make target: `make library-copy-test`.
set -euo pipefail
cd "$(dirname "$0")/.."

source_dir="${1:-$HOME/Music/Segue}"
[[ -d "$source_dir" ]] || { echo "library-copy-test: no library at $source_dir" >&2; exit 1; }
source_dir=$(cd "$source_dir" && pwd)
out=".build/library-copy-test/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out/extra"
out=$(cd "$out" && pwd)

fingerprint() { # <dir>: every file with its size and SHA-256, sorted
    (cd "$1" && find . -type f -print0 | sort -z | xargs -0 shasum -a 256)
}

fingerprint "$source_dir" >"$out/source-before.sha256"
cp -Rp "$source_dir" "$out/pristine"
cp -Rp "$source_dir" "$out/extra/library"
echo "library-copy-test: copied $source_dir ($(du -sh "$source_dir" | cut -f1)) to $out"

status=0
E2E_VM_EXTRA="$out/extra" SEGUE_RESULT_BUNDLE="$out/run.xcresult" \
    scripts/e2e-vm.sh tart -only-testing:SegueUITests/SegueLibraryCopyE2ETests || status=$?

fingerprint "$source_dir" >"$out/source-after.sha256"
if ! cmp -s "$out/source-before.sha256" "$out/source-after.sha256"; then
    echo "library-copy-test: WARNING: $source_dir changed during the run (another app?):" >&2
    diff "$out/source-before.sha256" "$out/source-after.sha256" >&2 || true
fi
[[ -d "$out/run.xcresult" ]] || { echo "library-copy-test: no result bundle (exit $status)" >&2; exit 1; }

xcrun xcresulttool export attachments --path "$out/run.xcresult" \
    --output-path "$out/attachments" --schema-version 0.4.0 >/dev/null
# name -> exported file, one line each.
mise exec -- jq -r '.[].attachments[]? | "\(.suggestedHumanReadableName)\t\(.exportedFileName)"' \
    "$out/attachments/manifest.json" >"$out/attachments/index.tsv"
attachment() { # <name prefix>: the exported file of the first attachment with that name
    awk -F'\t' -v want="$1" 'index($1, want) == 1 { print $2; exit }' "$out/attachments/index.tsv"
}

report="$out/report.md"
{
    echo "# Library copy test, $(date '+%Y-%m-%d %H:%M')"
    echo
    echo "Build: $(scripts/bump-version.sh show | tr ' ' '/') (marketing/build), commit $(git rev-parse --short HEAD)."
    echo "Source: \`$source_dir\` (only read; its checksums before and after the run are"
    if cmp -s "$out/source-before.sha256" "$out/source-after.sha256"; then
        echo "identical)."
    else
        echo "DIFFERENT, see the warning in the run log)."
    fi
    echo "Test result: exit $status (0 = both scenarios passed)."
    echo
    echo "Everything below compares \`pristine/\` (the untouched copy) with the copy after 1.0 opened it."
    echo "\`.DS_Store\` is ignored."
} >"$report"

for scenario in open duration; do
    after="$out/after-$scenario" trash="$out/trash-$scenario"
    for pair in "library-after-$scenario:$after" "trash-$scenario:$trash"; do
        name="${pair%%:*}" dest="${pair#*:}"
        file=$(attachment "$name")
        mkdir -p "$dest"
        if [[ -n "$file" ]]; then
            ditto -x -k "$out/attachments/$file" "$dest"
            # The zip holds the folder itself; flatten one level when it does.
            inner=$(find "$dest" -mindepth 1 -maxdepth 1)
            if [[ $(echo "$inner" | wc -l) -eq 1 && -d "$inner" ]]; then
                ditto "$inner" "$dest" && command rm -r "$inner"
            fi
        fi
    done
    {
        echo
        if [[ "$scenario" == open ]]; then
            echo "## Scenario 1: open, answer the notes, one save that ends where it started"
        else
            echo "## Scenario 2: the {duration} cleanup, answered Remove"
            injected=$(attachment injected-duration)
            [[ -n "$injected" ]] && echo && echo "Before launch the test $(command cat "$out/attachments/$injected")."
        fi
        notes=$(attachment notes-shown)
        echo
        echo "One-time notes shown:"
        echo
        if [[ -n "$notes" ]]; then sed 's/^/- /' "$out/attachments/$notes"; else echo "- (not recorded)"; fi
        echo
        if [[ -z "$(find "$after" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
            echo "No library came back from this scenario (see the test result)."
            continue
        fi
        echo "Files (A added, D removed, M changed):"
        echo
        echo '```'
        diff -rq -x .DS_Store "$out/pristine" "$after" \
            | sed -E -e "s|^Only in $out/pristine(/?)([^:]*): (.*)|D \2\1\3|" \
                -e "s|^Only in $after(/?)([^:]*): (.*)|A \2\1\3|" \
                -e "s|^Files $out/pristine/(.*) and .* differ$|M \1|" \
            | sed -E 's|^([ADM]) /|\1 |' | sort -k2 || true
        echo '```'
        echo
        echo "Moved to the Trash:"
        echo
        echo '```'
        (cd "$trash" 2>/dev/null && find . -type f ! -name .DS_Store | sed 's|^\./||' | sort) || true
        echo '```'
        echo
        echo "Text changes (binary files such as the old search index are listed above only):"
        echo
        echo '```diff'
        diff -ruN -x .DS_Store -x '*.sqlite*' -x '*.lock' "$out/pristine" "$after" \
            | sed -e "s|$out/pristine/|a/|g" -e "s|$after/|b/|g" || true
        echo '```'
    } >>"$report"
done

echo "library-copy-test: report at $report (exit $status)"
exit "$status"
