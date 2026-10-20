// Static checks for the user guide (WS6 4.7). Runs on Linux (the Site CI job) and locally
// in `make site-check`. Usage: node guide/scripts/check.mjs [--strict]
//   --strict also refuses screenshot and clip placeholders (shots not captured yet).
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const guide = join(root, 'guide');
const built = join(root, 'website', 'guide');
const strict = process.argv.includes('--strict');
const problems = [];
const fail = (message) => problems.push(message);
const rel = (path) => relative(root, path);

/** Every file under `dir` (recursively) whose name passes `keep`. */
function files(dir, keep = () => true) {
  if (!existsSync(dir)) return [];
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return entry.name === 'node_modules' ? [] : files(path, keep);
    return keep(entry.name) ? [path] : [];
  });
}

// 1. The Node pin Cloudflare Pages reads (.node-version) matches the mise pin.
const misePin = /^node = "([^"]+)"/m.exec(readFileSync(join(root, '.mise.toml'), 'utf8'))?.[1];
const nodeVersion = readFileSync(join(root, '.node-version'), 'utf8').trim();
if (misePin !== nodeVersion) fail(`.node-version is ${nodeVersion}, .mise.toml pins node ${misePin}`);
const engines = JSON.parse(readFileSync(join(guide, 'package.json'), 'utf8')).engines?.node;
if (engines !== misePin) fail(`guide/package.json engines.node is ${engines}, .mise.toml pins node ${misePin}`);

// 2. Source: no em dash anywhere; no colour literals in the stylesheets (tokens only).
const sources = files(join(guide, 'src')).concat(files(join(guide, 'scripts')), [join(guide, 'astro.config.mjs')]);
for (const path of sources) {
  if (/\.(avif|mp4|png)$/.test(path)) continue;
  const text = readFileSync(path, 'utf8');
  if (text.includes('\u2014')) fail(`${rel(path)}: contains an em dash (U+2014); use "-"`);
  if (path.endsWith('.css') && /#[0-9a-fA-F]{3,8}\b|\brgba?\(/.test(text)) {
    fail(`${rel(path)}: colour literal; use var(--token) from tokens.css`);
  }
}

// 3. Pages: every sidebar slug has a page, every page has a 50-160 character description.
const config = readFileSync(join(guide, 'astro.config.mjs'), 'utf8');
const sidebarSlugs = [...config.matchAll(/'([a-z0-9-]+)'/g)]
  .map((match) => match[1])
  .filter((slug) => existsSync(join(guide, 'src/content/docs', `${slug}.mdx`)) || slug === 'index');
const pages = files(join(guide, 'src/content/docs'), (name) => name.endsWith('.mdx'));
for (const path of pages) {
  const text = readFileSync(path, 'utf8');
  const slug = path.split('/').pop().replace(/\.mdx$/, '');
  if (!sidebarSlugs.includes(slug)) fail(`${rel(path)}: not in the sidebar (astro.config.mjs)`);
  const description = /^description: (.*)$/m.exec(text)?.[1] ?? '';
  if (description.length < 50 || description.length > 160) {
    fail(`${rel(path)}: description must be 50-160 characters (has ${description.length})`);
  }
}

// 4. Shots and clips: every id used exists on disk in each appearance the manifest lists;
//    budgets; --strict refuses ids not captured yet.
const manifest = JSON.parse(readFileSync(join(guide, 'src/data/shots.json'), 'utf8'));
const used = { shots: new Set(), clips: new Set() };
for (const path of pages) {
  const text = readFileSync(path, 'utf8');
  for (const match of text.matchAll(/<Shot\s[^>]*?id="([^"]+)"/g)) used.shots.add(match[1]);
  for (const match of text.matchAll(/<Tile\s[^>]*?shot="([^"]+)"/g)) used.shots.add(match[1]);
  for (const match of text.matchAll(/<Clip\s[^>]*?id="([^"]+)"/g)) used.clips.add(match[1]);
}
const kb = (path) => statSync(path).size / 1024;
let shotTotal = 0;
for (const id of used.shots) {
  const entry = manifest.shots[id];
  if (!entry) {
    if (strict) fail(`shot "${id}" is used but not captured yet (run make docs-shots)`);
    continue;
  }
  const names = entry.appearances.length === 1 ? [`${id}.avif`] : entry.appearances.map((a) => `${id}-${a}.avif`);
  for (const name of names) {
    const path = join(guide, 'public/shots', name);
    if (!existsSync(path)) {
      fail(`guide/public/shots/${name} is missing (listed in shots.json)`);
      continue;
    }
    shotTotal += kb(path);
    if (kb(path) > 150) fail(`guide/public/shots/${name} is ${Math.round(kb(path))} KB (budget 150 KB)`);
  }
}
if (shotTotal > 8 * 1024) fail(`shots total ${Math.round(shotTotal)} KB (budget 8 MB)`);
let clipTotal = 0;
for (const id of used.clips) {
  if (!manifest.clips[id]) {
    if (strict) fail(`clip "${id}" is used but not recorded yet (run make docs-clips)`);
    continue;
  }
  for (const name of [`${id}.mp4`, `${id}.avif`]) {
    const path = join(guide, 'public/clips', name);
    if (!existsSync(path)) fail(`guide/public/clips/${name} is missing (listed in shots.json)`);
    else clipTotal += kb(path);
  }
  const mp4 = join(guide, 'public/clips', `${id}.mp4`);
  if (existsSync(mp4) && kb(mp4) > 1536) fail(`guide/public/clips/${id}.mp4 is ${Math.round(kb(mp4))} KB (budget 1.5 MB)`);
}
if (clipTotal > 5 * 1024) fail(`clips total ${Math.round(clipTotal)} KB (budget 5 MB)`);

// 5. Keyboard reference: generated from the app; every LiveCommand appears once.
const keyboard = JSON.parse(readFileSync(join(guide, 'src/data/keyboard.json'), 'utf8'));
const liveCommand = readFileSync(join(root, 'Packages/SegueCore/Sources/Shows/LiveCommand.swift'), 'utf8');
const enumBody = liveCommand.slice(liveCommand.indexOf('public enum LiveCommand'), liveCommand.indexOf('/// Who handles a command.'));
const commandCount = [...enumBody.matchAll(/^\s+case [a-zA-Z]+$/gm)].length;
const stageRows = keyboard.stage.reduce((sum, group) => sum + group.rows.length, 0);
if (stageRows !== commandCount) fail(`keyboard.json has ${stageRows} stage rows, LiveCommand has ${commandCount} cases (make guide-keys)`);
if (!keyboard.menus.length) fail('keyboard.json has no menu shortcuts');

// 6. Build output: same-origin assets only, no inline scripts or style attributes (CSP),
//    no cookies, no em dash.
if (!existsSync(join(root, 'website', 'guide.html'))) {
  fail('website/guide.html is missing: run make guide first');
} else {
  for (const path of [join(root, 'website', 'guide.html'), ...files(built, (name) => name.endsWith('.html'))]) {
    const html = readFileSync(path, 'utf8');
    if (html.includes('\u2014')) fail(`${rel(path)}: contains an em dash (U+2014)`);
    if (/\sstyle="/.test(html)) fail(`${rel(path)}: style attribute (blocked by the guide CSP)`);
    for (const match of html.matchAll(/<script\b([^>]*)>/g)) {
      if (!/\ssrc="/.test(match[1])) fail(`${rel(path)}: inline <script> (blocked by the guide CSP)`);
    }
    if (/<style\b/.test(html)) fail(`${rel(path)}: inline <style> (blocked by the guide CSP)`);
    for (const match of html.matchAll(/<(script|link|img|source|video|iframe)\b([^>]*)>/g)) {
      if (match[1] === 'link' && /\srel="(canonical|alternate|sitemap)"/.test(match[2])) continue;
      const url = /\s(?:src|href|srcset|poster)="([^"]+)"/.exec(match[2])?.[1] ?? '';
      if (/^(https?:)?\/\//.test(url)) fail(`${rel(path)}: external asset ${url}`);
    }
    const canonical = /<link rel="canonical" href="([^"]+)"/.exec(html)?.[1] ?? '';
    if (/\.html$/.test(canonical)) fail(`${rel(path)}: canonical ${canonical} names the file, not the URL`);
  }
  for (const path of files(built, (name) => name.endsWith('.js'))) {
    if (readFileSync(path, 'utf8').includes('document.cookie')) fail(`${rel(path)}: touches document.cookie`);
  }
}

if (problems.length) {
  for (const problem of problems) console.error(`guide-check: ${problem}`);
  process.exit(1);
}
console.log(`guide-check: ok (${pages.length} pages, ${used.shots.size} shots, ${used.clips.size} clips${strict ? ', strict' : ''})`);
