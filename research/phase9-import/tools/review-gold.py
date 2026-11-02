"""Gold review tool for the P9-4 import eval (spec 16.1, R194): a local page that shows each
corpus page beside the chart the import expects from it, so the owner can mark it OK, fix the
expected chart, or leave a note. Python standard library only, bound to 127.0.0.1, so no page,
lyric or note ever leaves this Mac; it writes only into the gitignored corpus (gold/<slug>.cho
and gold/<slug>.review.json), plus a refusal kind into tools/gold-overrides.json (no lyrics).

Saved pages are served with a Content-Security-Policy that blocks every script and every
network load, inside a sandboxed iframe, so viewing a page sends nothing anywhere.

Usage: make review-gold   (or: python3 -I research/phase9-import/tools/review-gold.py [port])
"""

import http.server
import json
import os
import re
import sys
import urllib.parse

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
GOLD = os.path.join(ROOT, "gold")
DRAFTS = os.path.join(ROOT, ".build", "gold-drafts")
OVERRIDES = os.path.join(ROOT, "tools", "gold-overrides.json")
KINDS = ["chart", "notFound", "tab", "pro", "removed"]
SLUG = re.compile(r"^[A-Za-z0-9_-]{1,150}$")


def slug(url):
    p = urllib.parse.urlsplit(url)
    return re.sub(r"[^A-Za-z0-9-]", "_", p.netloc + p.path + ("_" + p.query if p.query else ""))[:150]


def items():
    rows = []
    for line in open(os.path.join(ROOT, "urls.tsv"), encoding="utf-8"):
        if line.startswith("#") or not line.strip():
            continue
        site, kind, lang, url, *_ = line.rstrip("\n").split("\t")
        name = slug(url)
        if kind != "page" or not os.path.exists(os.path.join(ROOT, "pages", site, name + ".html")):
            continue
        review = read_json(os.path.join(GOLD, name + ".review.json")) or {}
        draft = read_json(os.path.join(GOLD, name + ".json")) or {}
        rows.append({"slug": name, "site": site, "lang": lang, "url": url,
                     "status": review.get("status", "todo"), "notes": review.get("notes", ""),
                     "kind": review.get("kind") or draft.get("kind", "chart")})
    return rows


def read_json(path):
    try:
        return json.load(open(path, encoding="utf-8"))
    except (OSError, ValueError):
        return None


def expected(name):
    for path in (os.path.join(GOLD, name + ".cho"), os.path.join(DRAFTS, name + ".cho")):
        if os.path.exists(path):
            return open(path, encoding="utf-8").read()
    return ""


def save(name, body):
    status = body.get("action")
    kind = body.get("kind", "chart")
    if status not in ("ok", "fixed", "todo") or kind not in KINDS:
        raise ValueError("bad action or kind")
    os.makedirs(GOLD, exist_ok=True)
    if status in ("ok", "fixed") and kind == "chart":
        with open(os.path.join(GOLD, name + ".cho"), "w", encoding="utf-8") as handle:
            handle.write(body.get("text", ""))
    review = {"status": status, "kind": kind, "notes": body.get("notes", "")[:4000]}
    with open(os.path.join(GOLD, name + ".review.json"), "w", encoding="utf-8") as handle:
        json.dump(review, handle, ensure_ascii=False, indent=1)
    overrides = read_json(OVERRIDES) or {}
    entry = overrides.get(name, {})
    entry["kind"] = kind
    overrides[name] = entry
    with open(OVERRIDES, "w", encoding="utf-8") as handle:
        json.dump(overrides, handle, ensure_ascii=False, indent=1, sort_keys=True)
        handle.write("\n")


PAGE_POLICY = "default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:"


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def send(self, status, body, kind, extra=None):
        data = body.encode("utf-8") if isinstance(body, str) else body
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Referrer-Policy", "no-referrer")
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(data)

    def allowed(self):
        # Only this page may call the API (a DNS-rebinding or cross-site request is refused).
        return self.headers.get("Host", "").startswith(("127.0.0.1:", "localhost:"))

    def do_GET(self):
        if not self.allowed():
            return self.send(403, "forbidden", "text/plain")
        path = urllib.parse.urlsplit(self.path).path
        if path == "/":
            return self.send(200, APP, "text/html; charset=utf-8",
                             {"Content-Security-Policy": "default-src 'self'; style-src 'unsafe-inline'; "
                                                         "script-src 'unsafe-inline'; frame-src 'self'"})
        if path == "/api/items":
            return self.send(200, json.dumps(items()), "application/json")
        match = re.match(r"^/(page|api/item)/([^/]+)$", path)
        if match and SLUG.match(match.group(2)):
            name = match.group(2)
            if match.group(1) == "api/item":
                return self.send(200, json.dumps({"text": expected(name)}), "application/json")
            for row in items():
                if row["slug"] == name:
                    page = open(os.path.join(ROOT, "pages", row["site"], name + ".html"), "rb").read()
                    return self.send(200, page, "text/html; charset=utf-8",
                                     {"Content-Security-Policy": PAGE_POLICY})
        return self.send(404, "not found", "text/plain")

    def do_POST(self):
        if not self.allowed() or self.headers.get("Content-Type") != "application/json":
            return self.send(403, "forbidden", "text/plain")
        match = re.match(r"^/api/item/([^/]+)$", urllib.parse.urlsplit(self.path).path)
        if not match or not SLUG.match(match.group(1)):
            return self.send(404, "not found", "text/plain")
        length = min(int(self.headers.get("Content-Length", "0")), 2_000_000)
        try:
            save(match.group(1), json.loads(self.rfile.read(length)))
        except (ValueError, KeyError) as error:
            return self.send(400, str(error), "text/plain")
        return self.send(200, "{}", "application/json")


APP = r"""<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Gold Review</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
:root { --bg:#16171a; --panel:#1e2024; --line:#2c2f35; --text:#e7e8ea; --muted:#8b9099;
  --accent:#7aa2f7; --ok:#7bc47f; --fix:#e5b567; --todo:#5c616b; color-scheme: dark; }
@media (prefers-color-scheme: light) { :root { --bg:#f6f6f7; --panel:#fff; --line:#dcdde0;
  --text:#1c1d20; --muted:#6b7079; --accent:#3b6fd8; color-scheme: light; } }
* { box-sizing: border-box; } body { margin:0; background:var(--bg); color:var(--text);
  font: 13px/1.4 -apple-system, BlinkMacSystemFont, sans-serif; height:100vh; display:grid;
  grid-template-columns: 260px 1fr 1fr; }
nav { border-right:1px solid var(--line); overflow:auto; }
nav header { padding:12px 14px; color:var(--muted); font-size:12px; position:sticky; top:0;
  background:var(--bg); border-bottom:1px solid var(--line); }
.row { padding:7px 14px; cursor:pointer; display:flex; gap:8px; align-items:center;
  white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.row.sel { background:var(--panel); box-shadow: inset 2px 0 var(--accent); }
.dot { width:7px; height:7px; border-radius:50%; flex:none; background:var(--todo); }
.dot.ok { background:var(--ok); } .dot.fixed { background:var(--fix); }
.site { color:var(--muted); width:52px; flex:none; }
iframe { width:100%; height:100%; border:0; background:#fff; }
section { display:flex; flex-direction:column; border-left:1px solid var(--line); min-width:0; }
.bar { padding:10px 14px; display:flex; gap:8px; align-items:center; border-bottom:1px solid var(--line); }
.bar .url { color:var(--muted); overflow:hidden; text-overflow:ellipsis; white-space:nowrap; flex:1; }
textarea { flex:1; resize:none; background:var(--panel); color:var(--text); border:0;
  padding:12px 14px; font: 12px/1.45 ui-monospace, Menlo, monospace; outline:none; }
#notes { flex:none; height:70px; border-top:1px solid var(--line); font-family:inherit; }
button, select { background:var(--panel); color:var(--text); border:1px solid var(--line);
  border-radius:6px; padding:5px 10px; font:inherit; cursor:pointer; }
button.primary { background:var(--accent); border-color:var(--accent); color:#fff; }
kbd { color:var(--muted); font-size:11px; }
</style></head><body>
<nav><header id="count">Loading</header><div id="list"></div></nav>
<iframe id="page" sandbox title="Saved page (no scripts, no network)"></iframe>
<section>
  <div class="bar"><span class="url" id="url"></span>
    <select id="kind" title="What the import must do with this page">
      <option value="chart">chart</option><option value="notFound">no chart</option>
      <option value="tab">tab page</option><option value="pro">Pro page</option>
      <option value="removed">removed</option></select>
    <button id="ok" class="primary" title="Expected chart is right (Cmd-Return)">OK</button>
    <button id="fix" title="Save the edited chart (Cmd-S)">Save Fix</button></div>
  <textarea id="text" spellcheck="false" autocorrect="off" autocapitalize="off"
    aria-label="Expected chart (ChordPro)"></textarea>
  <textarea id="notes" placeholder="Notes" aria-label="Notes"></textarea>
  <div class="bar"><kbd>J / K next and previous (outside the editor) - Cmd-Return OK - Cmd-S save fix</kbd></div>
</section>
<script>
let items = [], index = 0, original = "";
const $ = (id) => document.getElementById(id);
async function load() {
  items = await (await fetch("/api/items")).json();
  render(); select(Math.max(0, items.findIndex((i) => i.status === "todo")));
}
function render() {
  const done = items.filter((i) => i.status !== "todo").length;
  $("count").textContent = `${done} of ${items.length} reviewed`;
  $("list").innerHTML = "";
  items.forEach((item, n) => {
    const row = document.createElement("div");
    row.className = "row" + (n === index ? " sel" : "");
    row.innerHTML = `<span class="dot ${item.status}"></span><span class="site"></span><span></span>`;
    row.children[1].textContent = item.site;
    row.children[2].textContent = decodeURIComponent(item.url.split("/").slice(-2).join("/"));
    row.onclick = () => select(n);
    $("list").appendChild(row);
  });
}
async function select(n) {
  index = n; const item = items[n]; render();
  $("page").src = "/page/" + item.slug; $("url").textContent = item.url;
  $("kind").value = item.kind; $("notes").value = item.notes || "";
  original = (await (await fetch("/api/item/" + item.slug)).json()).text;
  $("text").value = original;
  $("list").children[n]?.scrollIntoView({ block: "nearest" });
}
async function save(action) {
  const item = items[index];
  const body = { action, kind: $("kind").value, text: $("text").value, notes: $("notes").value };
  const reply = await fetch("/api/item/" + item.slug, { method: "POST",
    headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  if (!reply.ok) { alert("Not saved: " + await reply.text()); return; }
  Object.assign(item, { status: action, kind: body.kind, notes: body.notes });
  select(Math.min(items.length - 1, index + 1));
}
$("ok").onclick = () => save($("text").value === original ? "ok" : "fixed");
$("fix").onclick = () => save("fixed");
document.addEventListener("keydown", (e) => {
  if (e.metaKey && e.key === "Enter") { e.preventDefault(); $("ok").click(); }
  else if (e.metaKey && e.key === "s") { e.preventDefault(); $("fix").click(); }
  else if (!["TEXTAREA", "SELECT"].includes(document.activeElement.tagName)) {
    if (e.key === "j") select(Math.min(items.length - 1, index + 1));
    if (e.key === "k") select(Math.max(0, index - 1));
  }
});
load();
</script></body></html>"""


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"Gold review at http://127.0.0.1:{port}  (Ctrl-C to stop; writes only research/phase9-import/gold)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
