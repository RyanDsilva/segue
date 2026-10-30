#!/usr/bin/env bash
# Type-check a small Swift snippet against the installed macOS SDK at a given
# deployment target, so availability errors and deprecation warnings come from
# the compiler that will build the app rather than from memory.
#
# Usage: typecheck.sh [-t 26.0] [-6|-5] <file.swift | ->
#   -t   macOS deployment target (default: the SDK version; pass the project's)
#   -5   Swift 5 language mode (default is Swift 6, strict concurrency)
# The snippet may import SDK frameworks only, not the project's own modules.
# Exit status is the compiler's; any warning lines are printed.
set -euo pipefail

target="" mode=6
while getopts "t:56h" opt; do
	case "$opt" in
	t) target="$OPTARG" ;;
	5) mode=5 ;;
	6) mode=6 ;;
	h | *) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
	esac
done
shift $((OPTIND - 1))
[[ $# -eq 1 ]] || { echo "usage: typecheck.sh [-t 26.0] [-5|-6] <file.swift | ->" >&2; exit 2; }

sdk="$(xcrun --sdk macosx --show-sdk-path)"
[[ -n "$target" ]] || target="$(xcrun --sdk macosx --show-sdk-version)"

src="$1"
if [[ "$src" == "-" ]]; then
	tmp="$(mktemp -d)"
	trap 'rm -rf "$tmp"' EXIT
	src="$tmp/snippet.swift"
	command cat >"$src"
fi

echo "swiftc -typecheck: $(basename "$sdk"), macOS $target, Swift $mode" >&2
xcrun swiftc -typecheck -sdk "$sdk" -target "arm64-apple-macos$target" \
	-swift-version "$mode" -diagnostic-style llvm "$src"
