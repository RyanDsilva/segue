"""Drafts gold/<slug>.json for every corpus page (P9-4 spec 16.1), independently of the Swift
readers: fields from each site's structured data, chords from the page's own chord markup,
lyric words from the page's own lyric lines. The drafts are then reviewed by hand: every
field value is checked against the page, and `overrides.json` (tracked: no lyrics) holds the
hand corrections, applied last. Lyrics stay in the gitignored gold folder.

Usage: python3 -I research/phase9-import/tools/gold-draft.py
"""

import html
import json
import os
import re
import sys
import urllib.parse

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CREDIT = re.compile(
    r"(?i)^\s*(tabbed|transcribed|submitted|thanks|chords by|capo|tuning|key\b|intro\b|strum|"
    r"tempo|bpm|difficulty|author|e-mail|email|song:|artist:|album:|movie:|singers?:|"
    r"music:|lyrics:|chords?:|tabs?:|www\.|http|note:)"
)
SECTION = re.compile(
    r"(?i)^\s*[\[(]?(intro|verse|chorus|pre-?chorus|bridge|outro|interlude|solo|hook|refrain|"
    r"instrumental|riff|coda|ending|mukhda|antara|break)[ \d]*[\])]?:?\s*(x\d)?\s*$"
)
TABLINE = re.compile(r"^\s*[eBGDAEbgdae]\s*[|:-]")
CHORD = re.compile(
    r"^\(?[A-G](#|b)?(m|maj|min|dim|aug|sus|add|M|\+)?[0-9]*((maj|sus|add|b|#|m|M|\+|-)?[0-9]*)*"
    r"(\([^)]*\))?(/[A-G](#|b)?)?\)?$"
)


def slug(url):
    p = urllib.parse.urlsplit(url)
    return re.sub(r"[^A-Za-z0-9-]", "_", p.netloc + p.path + ("_" + p.query if p.query else ""))[:150]


def words(lines):
    out = []
    for line in lines:
        if not line.strip() or CREDIT.search(line) or TABLINE.search(line) or SECTION.match(line):
            continue
        tokens = line.split()
        if tokens and all(CHORD.match(t) or t in "|-/x2x3x4" for t in tokens):
            continue
        clean = re.sub(r"[^\w\s']", " ", line.lower())
        out += clean.split()
    return out


def misc_split(name, artist):
    if artist and artist.lower().startswith("misc ") and " - " in name:
        movie, title = name.split(" - ", 1)
        return title.strip(), movie.strip()
    return name.strip(), None


def ug(src):
    m = re.search(r'<div class="js-store" data-content="([^"]*)"', src)
    data = json.loads(html.unescape(m.group(1)))["store"]["page"]["data"]
    tab = data.get("tab", {})
    kind = tab.get("type", "")
    if kind.lower() not in ("chords", "ukulele chords"):
        return {"kind": "pro" if kind.lower() in ("pro", "power", "official") else "tab"}
    content = html.unescape(data["tab_view"]["wiki_tab"]["content"]).replace("\r\n", "\n").replace("\r", "\n")
    chords = [c.strip() for c in re.findall(r"\[ch\](.*?)\[/ch\]", content)]
    chords = re.sub(r"\[ch\]([^\[]+)\[/ch\]/\[ch\]([^\[]+)\[/ch\]", r"\1/\2", content)
    chords = [c.strip() for c in re.findall(r"\[ch\](.*?)\[/ch\]", re.sub(
        r"\[ch\]([^\[]+)\[/ch\]/\[ch\]([^\[]+)\[/ch\]", r"[ch]\1/\2[/ch]", content))]
    text = re.sub(r"\[/?(tab|b|i|u)\]", "", content)
    # The chart starts at its first section header; notes above it are not lyrics.
    first = re.search(r"(?m)^\s*\[[A-Za-z][^\]]*\]\s*$", text)
    if first:
        text = text[first.start():]
    text = re.sub(r"\[ch\][^\[]*\[/ch\]", " ", text)
    lyric_lines = [l for l in text.split("\n") if not re.match(r"^\s*\[[^\]]+\]\s*$", l)]
    artist = tab.get("artist_name")
    title, album = misc_split(tab.get("song_name", ""), artist)
    singers = [a["artist"]["name"] for a in (tab.get("recording") or {}).get("recording_artists", [])]
    artists = [artist] if artist and not artist.lower().startswith("misc ") else singers
    return {"kind": "chart", "title": title, "album": album, "artists": artists,
            "capo": (data["tab_view"].get("meta") or {}).get("capo") or None,
            "chords": chords, "lyrics": words(lyric_lines)}


def echords(src):
    pre = re.search(r"(?s)<pre[^>]*>(.*?)</pre>", src.replace("\r\n", "\n").replace("\r", "\n"))
    if not pre:
        return {"kind": "notFound"}
    body = pre.group(1)
    chords = re.findall(r'data-chord="([^"]+)"', body)
    plain = html.unescape(re.sub(r"<[^>]+>", "", body))
    meta = dict(re.findall(r"\b(NAME|ARTIST_NAME|CAPO|CHORDS_KEY)\s*:\s*'([^']*)'", src))
    ld = re.search(r'(?s)<script type="application/ld\+json">(.*?)</script>', src)
    name, artist = meta.get("NAME"), meta.get("ARTIST_NAME")
    if ld:
        try:
            item = json.loads(ld.group(1))
            name = item.get("name") or name
            artist = ((item.get("recordedAs") or {}).get("byArtist") or {}).get("name") or artist
        except ValueError:
            pass
    title, album = misc_split(name or "", artist)
    lines = plain.split("\n")
    return {"kind": "chart", "title": title, "album": album,
            "artists": [artist] if artist and not artist.lower().startswith("misc ") else [],
            "chords": chords, "lyrics": words(lines)}


def chordie(src):
    if "claiming that this song violates their copyright" in src:
        return {"kind": "removed"}
    lines = re.findall(r'(?s)<div class="(chordline|textline)">(.*?)</div>', src)
    if not lines:
        return {"kind": "notFound"}
    chords, text = [], []
    for _, body in lines:
        chords += re.findall(r'<span class="absc [^"]*">([^<]+)</span>', body)
        plain = re.sub(r'<span class="bracket">[^<]*</span>', "", body)
        plain = re.sub(r'<span class="absc [^"]*">[^<]+</span>', "", plain)
        text.append(html.unescape(re.sub(r"<[^>]+>", "", plain)))
    h1 = re.search(r'(?s)<h1[^>]*>(.*?)<a[^>]*>\s*<span>(.*?)</span>', src)
    title = html.unescape(re.sub(r"<[^>]+>", "", h1.group(1))).replace("\xa0", " ").strip() if h1 else None
    artist = html.unescape(h1.group(2)).strip() if h1 else None
    return {"kind": "chart", "title": title, "album": None, "artists": [artist] if artist else [],
            "chords": chords, "lyrics": words(text)}


def generic(src):
    title = re.search(r"(?is)<h1[^>]*>(.*?)</h1>", src) or re.search(r"(?is)<title>(.*?)</title>", src)
    return {"kind": "chart", "title": html.unescape(re.sub(r"<[^>]+>", "", title.group(1))).strip() if title else None,
            "artists": [], "album": None}


def main():
    overrides = json.load(open(os.path.join(ROOT, "tools", "gold-overrides.json"), encoding="utf-8"))
    os.makedirs(os.path.join(ROOT, "gold"), exist_ok=True)
    for line in open(os.path.join(ROOT, "urls.tsv"), encoding="utf-8"):
        if line.startswith("#") or not line.strip():
            continue
        site, kind, lang, url, *_ = line.rstrip("\n").split("\t")
        if kind != "page":
            continue
        path = os.path.join(ROOT, "pages", site, slug(url) + ".html")
        if not os.path.exists(path):
            continue
        src = open(path, encoding="utf-8", errors="replace").read()
        gold = {"ug": ug, "echords": echords, "chordie": chordie}.get(site, generic)(src)
        gold.update(overrides.get(slug(url), {}))
        json.dump(gold, open(os.path.join(ROOT, "gold", slug(url) + ".json"), "w", encoding="utf-8"),
                  ensure_ascii=False, indent=1)
        print(site, slug(url)[:50], gold.get("kind"), "|", gold.get("title"), "|",
              gold.get("artists"), "|", gold.get("album"), "|", gold.get("capo"), "|",
              len(gold.get("chords") or []), len(gold.get("lyrics") or []))


if __name__ == "__main__":
    sys.exit(main())
