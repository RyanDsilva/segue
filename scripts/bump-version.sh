#!/usr/bin/env bash
# The only writer of Config/Version.xcconfig (docs/release/specs/WS1-release-pipeline.md 4.7).
#
#   bump-version.sh show                 print "MARKETING_VERSION CURRENT_PROJECT_VERSION"
#   bump-version.sh build                CURRENT_PROJECT_VERSION += 1, then commit
#   bump-version.sh marketing X.Y[.Z]    set MARKETING_VERSION (strictly greater), then commit
#
# Never lowers either value and never resets the build number. `build` and `marketing` make
# one signed commit of the version file alone; they refuse if it already has uncommitted
# changes (other dirty files are fine). Environment:
#   SEGUE_VERSION_FILE=<path>   operate on another file (scratch-copy testing)
#   SEGUE_BUMP_NO_COMMIT=1      edit only, no commit
set -euo pipefail
cd "$(dirname "$0")/.."

file="${SEGUE_VERSION_FILE:-Config/Version.xcconfig}"

die() {
    echo "bump-version: $*" >&2
    exit 1
}

# read_key <key>: the value of `KEY = value` in the version file (exactly one line).
read_key() {
    local values
    values=$(sed -n -E "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*([^[:space:]]+)[[:space:]]*$/\\1/p" "$file")
    [[ -n "$values" && "$values" != *$'\n'* ]] || die "$file: expected exactly one $1 line"
    echo "$values"
}

# write_key <key> <value>: replace the key's value in place.
write_key() {
    local tmp
    tmp=$(mktemp)
    sed -E "s/^([[:space:]]*$1[[:space:]]*=[[:space:]]*).*$/\\1$2/" "$file" >"$tmp"
    mv "$tmp" "$file"
}

valid_marketing() { [[ "$1" =~ ^(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*)){0,2}$ ]]; }
valid_build() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }

# greater <a> <b>: true when version a > b, numerically per component (missing = 0).
greater() {
    local -a a b
    IFS=. read -r -a a <<<"$1"
    IFS=. read -r -a b <<<"$2"
    local i x y
    for i in 0 1 2; do
        x=${a[i]:-0}
        y=${b[i]:-0}
        ((10#$x > 10#$y)) && return 0
        ((10#$x < 10#$y)) && return 1
    done
    return 1
}

[[ -r "$file" ]] || die "cannot read $file"
marketing=$(read_key MARKETING_VERSION)
build=$(read_key CURRENT_PROJECT_VERSION)
valid_marketing "$marketing" || die "$file: MARKETING_VERSION '$marketing' is not 1-3 integers"
valid_build "$build" || die "$file: CURRENT_PROJECT_VERSION '$build' is not a positive integer"

# commit_bump: one signed commit of the version file alone.
commit_bump() {
    [[ "${SEGUE_BUMP_NO_COMMIT:-}" == 1 ]] && return
    local m b
    m=$(read_key MARKETING_VERSION)
    b=$(read_key CURRENT_PROJECT_VERSION)
    git commit -S -m "release: bump to $m ($b)" -- "$file"
}

# refuse_dirty: the version file must be clean before a committing bump.
refuse_dirty() {
    [[ "${SEGUE_BUMP_NO_COMMIT:-}" == 1 ]] && return
    if ! git diff --quiet HEAD -- "$file"; then
        die "$file has uncommitted changes; commit or revert them first"
    fi
}

case "${1:-}" in
show)
    echo "$marketing $build"
    ;;
build)
    [[ $# -eq 1 ]] || die "usage: bump-version.sh build"
    refuse_dirty
    write_key CURRENT_PROJECT_VERSION $((10#$build + 1))
    echo "bump-version: build $build -> $((10#$build + 1)) (marketing $marketing)"
    commit_bump
    ;;
marketing)
    [[ $# -eq 2 ]] || die "usage: bump-version.sh marketing X.Y[.Z]"
    new="$2"
    valid_marketing "$new" || die "'$new' is not at most three non-negative integers (ITMS-90060)"
    greater "$new" "$marketing" || die "'$new' is not greater than the current $marketing"
    refuse_dirty
    write_key MARKETING_VERSION "$new"
    echo "bump-version: marketing $marketing -> $new (build $build)"
    commit_bump
    ;;
*)
    die "usage: bump-version.sh show | build | marketing X.Y[.Z]"
    ;;
esac
