#!/bin/bash
# The P9-4 parser canary (spec 16.4): fetches one known public page per site and runs the
# Personal build's reader on it, plus one LRCLIB search; prints PASS or the failing check per
# reader. Manual and live (about six requests, paced); never in quick, gate or check. Run it
# when an import fails in daily use, and once before a release.
set -euo pipefail
cd "$(dirname "$0")/.."
out=.build/canary
mkdir -p "$out"
version=$(sed -n 's/^MARKETING_VERSION = //p' Config/Version.xcconfig)
agent="Segue/$version (+https://segue.ryandsilva.dev)"
wkfetch=research/phase9-import/.build/wkfetch/wkfetch
[[ -x "$wkfetch" ]] || research/phase9-import/tools/wkfetch/build.sh >/dev/null
(cd Packages/SeguePersonalModules && swift build --disable-index-store --product segue-import-eval >/dev/null)
eval_bin=Packages/SeguePersonalModules/.build/debug/segue-import-eval
failures=0

check() {
    local name="$1" url="$2" file="$out/$1.html"
    if [[ "$name" == echords ]]; then
        "$wkfetch" --outdir "$out" "$url" | grep -E "^http" || true
        file=$(command ls -t "$out"/www_e-chords_com_*.html 2>/dev/null | head -1)
    else
        curl -sS -m 30 -A "$agent" -H "Accept: text/html" -o "$file" "$url" || true
    fi
    printf '%-8s ' "$name"
    if [[ -s "${file:-}" ]] && "$eval_bin" --page "$file" --url "$url"; then :; else
        [[ -s "${file:-}" ]] || echo "FAIL: nothing fetched"
        failures=$((failures + 1))
    fi
    sleep 5
}

check ug "https://tabs.ultimate-guitar.com/tab/misc-soundtrack/aashiqui-2-tum-hi-ho-chords-1244521"
check chordie "https://www.chordie.com/chord.pere/www.guitaretab.com/b/beatles/1169.html"
check echords "https://www.e-chords.com/chords/oasis/wonderwall"
check generic "https://www.guitartabs.cc/tabs/o/oasis/wonderwall_crd_ver_8.html"

printf '%-8s ' lrclib
if curl -sS -m 30 -A "$agent" -H "Lrclib-Client: $agent" "https://lrclib.net/api/search?q=tum+hi+ho" -o "$out/lrclib.json" \
    && python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); assert isinstance(d,list) and d and "plainLyrics" in d[0]; print("PASS search: %d records" % len(d))' "$out/lrclib.json"; then :; else
    echo "FAIL: no usable search answer (LRCLIB is often 503; retry later)"
    failures=$((failures + 1))
fi
trash "$out" >/dev/null 2>&1 || true
exit $((failures > 0))
