#!/usr/bin/env bash
# Repo text and metadata checks that run anywhere (macOS or the Linux CI):
#
#   1. No em dash (U+2014) in any tracked or new, non-ignored text file. Use "-" instead.
#      Byte-exact parser fixtures are exempt: they are test input, not prose.
#   2. Every JSON source and generated JSON file parses, and so does every YAML file under
#      .github/ (issue forms, labels, Dependabot; actionlint covers the workflows in depth).
#   3. Every pin in Tuist/Package.resolved appears, with its exact version, in
#      THIRD_PARTY_NOTICES.md (or THIRD_PARTY_NOTICES-Personal.md for Personal-only pins), so a dependency bump cannot leave the notices stale.
#
# Usage: scripts/check-docs.sh   (or `make docs-check`). Needs git, jq and yq (.mise.toml).
set -euo pipefail
cd "$(dirname "$0")/.."

failures=0
fail() {
    echo "docs-check: $*" >&2
    failures=$((failures + 1))
}

# 1. Em dashes. --untracked also covers new files that are not ignored yet.
emdash=$(printf '\342\200\224') # U+2014 in octal bytes, so bash 3.2 works too
if hits=$(git grep -n -I --untracked -F -e "$emdash" -- . \
    ':(exclude)Packages/SegueCore/Tests/Fixtures/**' \
    ':(exclude)research/phase3-spikes/fixtures/**'); then
    while IFS= read -r hit; do
        fail "em dash (use \"-\"): $hit"
    done <<<"$hits"
fi

# 2. JSON parses.
while IFS= read -r file; do
    if ! jq empty "$file" 2>/dev/null; then
        fail "invalid JSON: $file"
    fi
done < <(git ls-files --cached --others --exclude-standard -- \
    'content/*.json' 'website/*.json' 'design/*.json')

while IFS= read -r file; do
    if ! yq -e 'true' "$file" >/dev/null 2>&1; then
        fail "invalid YAML: $file"
    fi
done < <(git ls-files --cached --others --exclude-standard -- '.github/*.yml' '.github/**/*.yml')

# 3. Third-party notices name every resolved pin at its exact version.
notices=THIRD_PARTY_NOTICES.md
# Components only the never-distributed Personal build links (P9-4): their notices ship in
# the Personal app only, so the App Store bundle never names them.
personal_notices=THIRD_PARTY_NOTICES-Personal.md
while IFS=$'\t' read -r location version; do
    repo_url="${location%.git}"
    if ! cat "$notices" "$personal_notices" | grep -F -- "$repo_url" | grep -q -F -- "| $version |"; then
        fail "$notices (or $personal_notices) has no row for $repo_url at $version (Tuist/Package.resolved)"
    fi
done < <(jq -r '.pins[] | [.location, .state.version] | @tsv' Tuist/Package.resolved)

if ((failures > 0)); then
    echo "docs-check: $failures problem(s)" >&2
    exit 1
fi
echo "docs-check: ok"
