#!/usr/bin/env bash
# Builds the website's subset WOFF2 web fonts from the OFL TTFs bundled with the app:
#
#   Packages/SegueUI/Sources/SegueUI/Theme/Fonts/SchibstedGrotesk-*.ttf
#     -> website/assets/fonts/schibsted-grotesk-{400,600,700,800}.woff2
#
# and writes content/fonts.lock.json (source and output SHA-256 plus the fonttools version),
# which `scripts/gen-site.swift --check` verifies. Also copies OFL.txt next to the fonts.
# The OFL has no Reserved Font Name, so the subset keeps the family name.
#
# fonttools runs through uvx (uv comes from .mise.toml); nothing is installed globally.
# Usage: scripts/gen-webfonts.sh   (or `make site-fonts`)

set -euo pipefail

FONTTOOLS_VERSION="4.67.0"
UNICODES="U+0000-00FF,U+0131,U+0152-0153,U+02C6,U+02DA,U+02DC,U+2013-2014,U+2018-201E,U+2020-2022,U+2026,U+2030,U+2039-203A,U+20AC,U+2122,U+2190-2193,U+2212"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

src_dir="Packages/SegueUI/Sources/SegueUI/Theme/Fonts"
out_dir="website/assets/fonts"
lock="content/fonts.lock.json"
mkdir -p "$out_dir" content

sha() { shasum -a 256 "$1" | awk '{print $1}'; }

entries=()
for pair in 400:Regular 600:SemiBold 700:Bold 800:ExtraBold; do
	weight="${pair%%:*}"
	style="${pair#*:}"
	src="$src_dir/SchibstedGrotesk-$style.ttf"
	out="$out_dir/schibsted-grotesk-$weight.woff2"
	mise exec -- uvx --from "fonttools[woff]==$FONTTOOLS_VERSION" pyftsubset "$src" \
		--output-file="$out" --flavor=woff2 --layout-features='*' --no-hinting \
		--desubroutinize --unicodes="$UNICODES"
	size=$(wc -c <"$out" | tr -d ' ')
	if ((size >= 30720)); then
		echo "error: $out is $size bytes; the budget is under 30 KB per weight" >&2
		exit 1
	fi
	entries+=("$(printf '    { "weight": %s, "source": "%s", "sourceSha256": "%s", "output": "%s", "outputSha256": "%s" }' \
		"$weight" "$src" "$(sha "$src")" "$out" "$(sha "$out")")")
	echo "gen-webfonts: $out ($size bytes)"
done

cp "$src_dir/OFL.txt" "$out_dir/OFL.txt"

{
	printf '{\n  "schema": 1,\n  "fonttools": "%s",\n  "unicodes": "%s",\n  "fonts": [\n' \
		"$FONTTOOLS_VERSION" "$UNICODES"
	last=$((${#entries[@]} - 1))
	for i in "${!entries[@]}"; do
		if ((i < last)); then printf '%s,\n' "${entries[$i]}"; else printf '%s\n' "${entries[$i]}"; fi
	done
	printf '  ]\n}\n'
} >"$lock"
echo "gen-webfonts: wrote $lock"
