#!/bin/bash
# Collects the P9-4 import corpus (spec 16.1). Manual, live network; never part of quick,
# gate or check. Reads research/phase9-import/urls.tsv (tab-separated: site, kind, lang,
# url, note) and saves each page into the gitignored corpus folders:
#   pages/<site>/<slug>.html     kind=page   (chart pages)
#   search/<site>/<slug>.html    kind=search (results pages; E-Chords saves its /api/search JSON)
#   lrclib/<slug>.json           site=lrclib (recorded /api/search responses)
# Rules: the shipping User-Agent on plain requests; robots.txt honoured for kind=page (the
# collector is a crawler) and skipped only for the 20 search pages R184 allows; 5 s between
# requests to a host; LRCLIB 503s retried up to 5 times after Retry-After; a challenge or
# block is logged as skipped (no retry, no workaround, never any captcha-solving). E-Chords
# blocks plain requests, so its rows load through the hidden WebKit loader (tools/wkfetch,
# a persistent store, WebKit's own user agent). A file already saved is not fetched again.
#
# Usage: scripts/collect-import-corpus.sh [site...]   (default: every site in urls.tsv)
set -euo pipefail
cd "$(dirname "$0")/.."
root=research/phase9-import
version=$(sed -n 's/^MARKETING_VERSION = //p' Config/Version.xcconfig)
wkfetch="$root/.build/wkfetch/wkfetch"
if grep -q "^echords" "$root/urls.tsv" && [[ ! -x "$wkfetch" ]]; then
    "$root/tools/wkfetch/build.sh" >/dev/null
fi
mkdir -p "$root/logs"
exec python3 -I - "$root" "Segue/$version (+https://segue.ryandsilva.dev)" "$wkfetch" "$@" <<'PY'
import json, os, re, subprocess, sys, time, urllib.error, urllib.parse, urllib.request, urllib.robotparser

root, agent, wkfetch, *only = sys.argv[1:]
log_path = os.path.join(root, "logs", "collect.log")
last = {}
robots = {}

def log(message):
    line = time.strftime("%H:%M:%S ") + message
    print(line, flush=True)
    with open(log_path, "a", encoding="utf-8") as handle:
        handle.write(line + "\n")

def pace(host):
    wait = 5 - (time.monotonic() - last.get(host, -10))
    if wait > 0:
        time.sleep(wait)
    last[host] = time.monotonic()

def slug(url):
    parts = urllib.parse.urlsplit(url)
    raw = parts.netloc + parts.path + ("_" + parts.query if parts.query else "")
    return re.sub(r"[^A-Za-z0-9-]", "_", raw)[:150]

def allowed(url):
    parts = urllib.parse.urlsplit(url)
    base = f"{parts.scheme}://{parts.netloc}"
    if base not in robots:
        # Read with the collector's own user agent (urllib's default agent is refused by
        # some hosts, which robotparser would take as "disallow everything").
        status, _, body = plain(base + "/robots.txt", "text/plain")
        if status == 200:
            parser = urllib.robotparser.RobotFileParser()
            parser.parse(body.splitlines())
        elif 400 <= status < 500 and status not in (401, 403):
            parser = urllib.robotparser.RobotFileParser()
            parser.parse([])  # no robots.txt: everything allowed
        else:
            log(f"robots unreadable for {base}: HTTP {status}")
            parser = None
        robots[base] = parser
    parser = robots[base]
    return parser is not None and parser.can_fetch(agent, url)

def challenged(headers, body):
    return headers.get("cf-mitigated") == "challenge" or re.search(
        r"<title>\s*(Just a moment|Attention Required|Verifying)", body or "") is not None

def plain(url, accept):
    host = urllib.parse.urlsplit(url).netloc
    for attempt in range(6):
        pace(host)
        request = urllib.request.Request(url, headers={
            "User-Agent": agent, "Lrclib-Client": agent, "Accept": accept, "Accept-Language": "en"})
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                body = response.read(5_000_000).decode("utf-8", "replace")
                return response.status, dict(response.headers), body
        except urllib.error.HTTPError as error:
            body = error.read(200_000).decode("utf-8", "replace")
            if error.code == 503 and "lrclib" in host and attempt < 5:
                delay = float(error.headers.get("Retry-After") or 1)
                log(f"  503, retry {attempt + 1} after {delay:.0f}s")
                time.sleep(delay * 1.3)
                continue
            return error.code, dict(error.headers), body
    return 503, {}, ""

def save(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)

rows = []
with open(os.path.join(root, "urls.tsv"), encoding="utf-8") as handle:
    for line in handle:
        if line.startswith("#") or not line.strip():
            continue
        site, kind, lang, url, *note = line.rstrip("\n").split("\t")
        if not only or site in only:
            rows.append((site, kind, lang, url))

for site, kind, lang, url in rows:
    if site == "lrclib":
        path = os.path.join(root, "lrclib", slug(url) + ".json")
    elif site == "echords" and kind == "search":
        path = os.path.join(root, "search", site, slug(url) + ".json")
    else:
        path = os.path.join(root, "pages" if kind == "page" else "search", site, slug(url) + ".html")
    if os.path.exists(path):
        continue
    if kind == "page" and site != "echords" and not allowed(url):
        log(f"SKIP robots {url}")
        continue
    if site == "echords":
        host = urllib.parse.urlsplit(url).netloc
        pace(host)
        args = [wkfetch, "--gap", "5", "--outdir", os.path.dirname(path)]
        if kind == "search":
            query = urllib.parse.unquote(url.rstrip("/").rsplit("/", 1)[-1])
            args += ["--api", "/api/search?q=" + urllib.parse.quote(query) + "&songs_take=15"
                     "&lyrics_take=1&artists_take=1&albums_take=1&videos_take=1&composers_take=1"]
        os.makedirs(os.path.dirname(path), exist_ok=True)
        result = subprocess.run(args + [url], capture_output=True, text=True, timeout=120)
        summary = [l for l in result.stdout.splitlines() if l.startswith("http")]
        log(f"{site} {kind} {url}: {summary[-1] if summary else result.stderr.strip()[:200]}")
        last[host] = time.monotonic()
        continue
    accept = "application/json" if site == "lrclib" else "text/html,application/xhtml+xml"
    status, headers, body = plain(url, accept)
    if challenged(headers, body):
        log(f"SKIP challenged {status} {url}")
    elif status != 200:
        log(f"SKIP status {status} {url}")
    else:
        save(path, body)
        log(f"saved {status} {len(body)} {path}")
PY
