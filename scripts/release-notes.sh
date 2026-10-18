#!/usr/bin/env bash
# Prints the GitHub Release notes (Markdown) for a version tag, from the published changelog
# website/changelog.json (generated from content/changelog.json by scripts/gen-site.swift,
# drafts removed). Used by .github/workflows/release.yml; run it locally to preview:
#
#   scripts/release-notes.sh v0.5.0           the notes body (or `make release-notes TAG=v0.5.0`)
#   scripts/release-notes.sh --title v0.5.0   the release title, "Segue 0.5 - First beta"
#
# The tag must be vX.Y.Z and must match MARKETING_VERSION in Config/Version.xcconfig. The
# changelog and the marketing version drop a trailing ".0" (0.5, 0.5.1), so v0.5.0 matches
# "0.5". Fails if the release is missing from the published changelog (still a draft, or
# never written), so a tag can never produce an empty release.
set -euo pipefail
cd "$(dirname "$0")/.."

mode=notes
if [[ "${1:-}" == --title ]]; then
    mode=title
    shift
fi
tag="${1:-}"
if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "release-notes: usage: scripts/release-notes.sh [--title] vX.Y.Z (got \"$tag\")" >&2
    exit 2
fi
full="${tag#v}"
short="${full%.0}"

marketing=$(sed -n 's/^MARKETING_VERSION *= *\([0-9.]*\) *$/\1/p' Config/Version.xcconfig)
if [[ "$marketing" != "$short" && "$marketing" != "$full" ]]; then
    echo "release-notes: $tag does not match MARKETING_VERSION = $marketing (Config/Version.xcconfig)" >&2
    exit 1
fi

origin=$(jq -r '.site.origin' content/site.json)
changelog=website/changelog.json

release=$(jq -c --arg short "$short" --arg full "$full" \
    '[.releases[] | select(.version == $short or .version == $full)] | first // empty' "$changelog")
if [[ -z "$release" ]]; then
    echo "release-notes: $changelog has no published release $short. Add it to content/changelog.json" >&2
    echo "release-notes: with \"draft\": false, run \`make site\`, commit, then tag again." >&2
    exit 1
fi

if [[ "$mode" == title ]]; then
    jq -r '"Segue \(.version) - \(.title)"' <<<"$release"
    exit 0
fi

jq -r --arg origin "$origin" '
    def section($kind; $heading):
        [.highlights[] | select(.kind == $kind)] as $items
        | if ($items | length) == 0 then empty
          else "### \($heading)\n\n" + ($items | map(
            "- \(.text)" + (if .help then " ([Help](\($origin)\(.help)))" else "" end)
          ) | join("\n"))
          end;
    [
        "Released \(.date).",
        (.summary // empty),
        section("new"; "New"),
        section("improved"; "Improved"),
        section("fixed"; "Fixed"),
        "Full changelog: \($origin)/changelog"
    ] | join("\n\n")
' <<<"$release"
