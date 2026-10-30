#!/usr/bin/env bash
# Look up a Swift API in the installed macOS SDK's .swiftinterface files and
# print each matching declaration with the availability attributes that apply
# to it (its own and its enclosing extension's), so deprecations, renames and
# minimum OS versions come from the SDK that will actually build the app.
#
# Usage: sdk-api.sh [-m Module[,Module]] [-n max] [-l] <regex>
#   <regex>  extended regex matched against declaration lines,
#            e.g. 'func onChange' or 'struct NavigationSplitView'
#   -m       limit to modules (default: all; SwiftUI also searches SwiftUICore)
#   -n       stop after this many matches (default 25)
#   -l       list the module names the SDK provides and exit
set -euo pipefail

modules="" max=25 list=0
while getopts "m:n:lh" opt; do
	case "$opt" in
	m) modules="$OPTARG" ;;
	n) max="$OPTARG" ;;
	l) list=1 ;;
	h | *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
	esac
done
shift $((OPTIND - 1))

sdk="$(xcrun --sdk macosx --show-sdk-path)"
echo "SDK: $(basename "$sdk") ($(xcodebuild -version 2>/dev/null | head -1))" >&2

# Trailing slash: the SDK path is a symlink and find must follow it.
files=()
while IFS= read -r f; do files+=("$f"); done < <(find "$sdk/" -name 'arm64e-apple-macos.swiftinterface' -not -path '*/iOSSupport/*' 2>/dev/null | sort)

module_of() { basename "$(dirname "$1")" .swiftmodule; }

if [[ "$list" == 1 ]]; then
	for f in "${files[@]}"; do module_of "$f"; done | sort -u | column
	exit 0
fi
[[ $# -eq 1 ]] || { echo "usage: sdk-api.sh [-m Module] [-n max] [-l] <regex>" >&2; exit 2; }
pattern="$1"

if [[ -n "$modules" ]]; then
	wanted=",${modules},"
	[[ "$wanted" == *,SwiftUI,* ]] && wanted="${wanted}SwiftUICore,"
	selected=()
	for f in "${files[@]}"; do
		[[ "$wanted" == *",$(module_of "$f"),"* ]] && selected+=("$f")
	done
	[[ ${#selected[@]} -gt 0 ]] || { echo "no such module in this SDK (try -l)" >&2; exit 1; }
	files=("${selected[@]}")
fi

found=0
for f in "${files[@]}"; do
	# Cheap prefilter before the awk pass.
	grep -Eq "$pattern" "$f" || continue
	# The pattern goes through the environment: awk -v would eat its backslashes.
	out="$(PAT="$pattern" awk -v mod="$(module_of "$f")" -v max="$((max - found))" '
		BEGIN { pat = ENVIRON["PAT"] }
		function keep(a) { return a ~ /macOS|anyAppleOS|@available\(\*/ }
		function flag(s) { return s ~ /deprecated|unavailable|obsoleted|renamed/ ? "  [DEPRECATED/RENAMED]" : "" }
		# A line that is only attributes (@frozen, @MainActor, ...), not a declaration.
		function attronly(s) {
			return s ~ /^[ \t]*@[A-Za-z_]/ && s !~ /(^|[ \t])(func|var|let|struct|class|enum|protocol|actor|init|subscript|typealias|associatedtype|case|macro)[ \t(<]/
		}
		# #if compiler(...) branches repeat a declaration with ~Sendable; print it once.
		function first(key) {
			gsub(/~Swift(\.|::)[A-Za-z]+/, "", key); gsub(/::/, ".", key); gsub(/[ \t:,{]/, "", key)
			if (key in seen) return 0
			seen[key] = 1; return 1
		}
		function hidden(s) { return s ~ /(^|[ \t])(internal|private|fileprivate)[ \t]/ || s ~ /(struct|class|enum|protocol|func|var) _/ }
		/^#/ { next }
		/^@available/ { top = top (keep($0) ? $0 "\n" : ""); next }
		/^[^ \t}]/ && attronly($0) { next }
		/^[^ \t}]/ {
			ctx = $0; ctxattr = top; top = ""
			if ($0 ~ pat && $0 !~ /^extension/ && !hidden($0) && first($0)) {
				sub(/[ \t]*\{[ \t]*$/, "")
				printf "== %s%s\n%s%s\n\n", mod, flag(ctxattr), ctxattr, $0
				if (++n >= max) exit
			}
			next
		}
		/^[ \t]+@available/ { own = own (keep($0) ? $0 "\n" : ""); next }
		/^[ \t]+[^ \t]/ && attronly($0) { next }
		/^[ \t]+[^ \t]/ {
			if ($0 ~ pat && ctx !~ /^import/ && !hidden($0) && !hidden(ctx) && first(ctx $0)) {
				sub(/[ \t]*\{[ \t]*$/, "")
				printf "== %s  in: %s%s\n%s%s%s\n\n", mod, ctx, flag(ctxattr own), ctxattr, own, $0
				if (++n >= max) exit
			}
			own = ""
		}
		END { exit n == 0 ? 1 : 0 }
	' "$f" || true)"
	[[ -n "$out" ]] || continue
	printf '%s\n\n' "$out"
	found=$((found + $(grep -c '^== ' <<<"$out")))
	if [[ "$found" -ge "$max" ]]; then
		echo "(stopped at $max matches; narrow the regex or raise -n)" >&2
		break
	fi
done

if [[ "$found" == 0 ]]; then
	echo "no declaration matches '$pattern' (it may not exist in this SDK, or try a looser regex)" >&2
	exit 1
fi
