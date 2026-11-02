// Packages the help-mode guide build (HELP_BOOK=1 astro build, P9-5 3.3) as the app's
// offline Apple Help Book, Derived/HelpBook/Segue.help. One source, two outputs: the website
// guide is unchanged. Usage (from `make help-book`): node guide/scripts/helpbook.mjs
//
//   - every /guide/... URL becomes relative (Help Viewer loads file: URLs inside the bundle);
//     links to site pages outside the guide (/privacy, /support, /) become absolute web URLs;
//   - every page gets an Apple Help anchor named after its slug, and every heading id one
//     named <slug>-<id> (SegueLinks.Guide.helpAnchor), plus <meta name="robots"
//     content="anchors"> so hiutil indexes them; the home page carries AppleTitle;
//   - scripts and the Pagefind search box are dropped (Help Viewer has its own search);
//   - each footer names the app version and links "Read this guide online";
//   - the site fonts are copied in with their licence;
//   - hiutil builds the search index; source.sha256 records what the book was built from
//     (`make help-book-check` compares it).
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import {
  copyFileSync,
  cpSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const derived = join(root, 'Derived', 'HelpBook');
const site = join(derived, 'site');
const book = join(derived, 'Segue.help');
const lproj = join(book, 'Contents', 'Resources', 'en.lproj');
const webOrigin = 'https://segue.ryandsilva.dev';
const bookID = 'dev.ryandsilva.segue.help';
const bookTitle = 'Segue Help';

/** Every file under `dir`, recursively (paths). */
function files(dir) {
  if (!existsSync(dir)) return [];
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return entry.name === 'node_modules' ? [] : files(path);
    return [path];
  });
}

/** The inputs the book is built from; a change to any of them makes the book stale. */
function sourceHash() {
  const guide = join(root, 'guide');
  const inputs = [
    ...files(join(guide, 'src')),
    ...files(join(guide, 'public')),
    join(guide, 'astro.config.mjs'),
    join(guide, 'scripts', 'helpbook.mjs'),
    join(guide, 'pnpm-lock.yaml'),
    join(root, 'website', 'assets', 'css', 'tokens.css'),
    join(root, 'Config', 'Version.xcconfig'),
  ].sort();
  const hash = createHash('sha256');
  for (const path of inputs) {
    hash.update(relative(root, path));
    hash.update('\0');
    hash.update(readFileSync(path));
    hash.update('\0');
  }
  return hash.digest('hex');
}

if (process.argv.includes('--hash')) {
  process.stdout.write(`${sourceHash()}\n`);
  process.exit(0);
}

const version = /^MARKETING_VERSION = (.+)$/m.exec(
  readFileSync(join(root, 'Config', 'Version.xcconfig'), 'utf8'),
)?.[1]?.trim();
if (!version) {
  console.error('helpbook: no MARKETING_VERSION in Config/Version.xcconfig');
  process.exit(1);
}
if (!existsSync(join(site, 'index.html'))) {
  console.error('helpbook: Derived/HelpBook/site is missing; run HELP_BOOK=1 astro build first');
  process.exit(1);
}

const pages = new Set(readdirSync(site).filter((name) => name.endsWith('.html')).map((name) => name.slice(0, -5)));

/** One URL as the book needs it (pages are all at the top of en.lproj). */
function rewriteURL(url) {
  if (!url.startsWith('/') || url.startsWith('//')) return url;
  const [path, hash = ''] = url.split('#');
  const fragment = hash ? `#${hash}` : '';
  if (path === '/guide' || path === '/guide/') return `index.html${fragment}`;
  if (path.startsWith('/guide/')) {
    const rest = path.slice('/guide/'.length);
    if (pages.has(rest)) return `${rest}.html${fragment}`;
    return `${rest}${fragment}`;
  }
  // Outside the guide: the website (privacy, support, the home page).
  return `${webOrigin}${url}`;
}

/** Rewrites href, src, poster and srcset attributes. */
function rewriteAttributes(html) {
  return html
    .replace(/\b(href|src|poster)="([^"]*)"/g, (_, name, value) => `${name}="${rewriteURL(value)}"`)
    .replace(/\bsrcset="([^"]*)"/g, (_, value) =>
      `srcset="${value
        .split(',')
        .map((part) => {
          const [url, ...rest] = part.trim().split(/\s+/);
          return [rewriteURL(url), ...rest].join(' ');
        })
        .join(', ')}"`,
    );
}

const anchors = new Map();
function addAnchor(name, page) {
  if (anchors.has(name)) {
    console.error(`helpbook: anchor "${name}" is in both ${anchors.get(name)} and ${page}`);
    process.exit(1);
  }
  anchors.set(name, page);
}

function processPage(slug, html) {
  const anchor = slug === 'index' ? 'index' : slug;
  const webURL = slug === 'index' ? `${webOrigin}/guide` : `${webOrigin}/guide/${slug}`;
  addAnchor(anchor, slug);
  let out = html
    // No scripts in the book: they are site niceties, and module scripts do not load from
    // file: URLs. The search box needs Pagefind, which the book does not ship.
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/g, '')
    .replace(/<site-search\b[\s\S]*?<\/site-search>/g, '')
    .replace(/<link rel="sitemap"[^>]*>/g, '')
    .replace(/<link rel="shortcut icon"[^>]*>/g, '');
  out = rewriteAttributes(out);
  const absolute = /\b(?:href|src|poster|srcset)="\/[^"]*"/.exec(out);
  if (absolute) {
    console.error(`helpbook: ${slug}.html still has an absolute URL: ${absolute[0]}`);
    process.exit(1);
  }
  // Page and heading anchors (Apple Help anchors are <a name>).
  out = out.replace(/<h([1-6]) id="([^"]+)"/g, (match, _level, id) => {
    if (id === '_top') return match;
    const name = `${anchor}-${id}`;
    addAnchor(name, slug);
    return `<a name="${name}"></a>${match}`;
  });
  out = out.replace(/<body([^>]*)>/, `<body$1><a name="${anchor}"></a>`);
  const meta = ['<meta name="robots" content="anchors">'];
  if (slug === 'index') meta.push(`<meta name="AppleTitle" content="${bookTitle}">`);
  out = out.replace(/<head>/, `<head>${meta.join('')}`);
  out = out.replace(
    /<\/footer>/,
    `<p class="small-print help-book-online">This guide describes Segue ${version}.` +
      `<span class="sep" aria-hidden="true">·</span><a href="${webURL}">Read this guide online</a></p></footer>`,
  );
  return out;
}

// Fresh book every run.
rmSync(book, { recursive: true, force: true });
mkdirSync(lproj, { recursive: true });

for (const name of readdirSync(site)) {
  if (name.startsWith('sitemap')) continue;
  const from = join(site, name);
  if (name.endsWith('.html')) {
    const slug = name.slice(0, -5);
    writeFileSync(join(lproj, name), processPage(slug, readFileSync(from, 'utf8')));
  } else if (statSync(from).isDirectory()) {
    cpSync(from, join(lproj, name), { recursive: true });
  }
}
// The stylesheets sit in _astro/; the fonts they name come from the website.
for (const path of files(join(lproj, '_astro'))) {
  if (!path.endsWith('.css')) continue;
  const css = readFileSync(path, 'utf8').replace(/url\(\/assets\/fonts\//g, 'url(../assets/fonts/');
  if (/url\(\//.test(css)) {
    console.error(`helpbook: ${relative(root, path)} still has an absolute url()`);
    process.exit(1);
  }
  writeFileSync(path, css);
}
const fonts = join(root, 'website', 'assets', 'fonts');
mkdirSync(join(lproj, 'assets', 'fonts'), { recursive: true });
for (const name of readdirSync(fonts)) {
  if (name.endsWith('.woff2') || name === 'OFL.txt') copyFileSync(join(fonts, name), join(lproj, 'assets', 'fonts', name));
}

const plist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleIdentifier</key>
	<string>${bookID}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Segue</string>
	<key>CFBundlePackageType</key>
	<string>BNDL</string>
	<key>CFBundleShortVersionString</key>
	<string>${version}</string>
	<key>CFBundleSignature</key>
	<string>hbwr</string>
	<key>CFBundleVersion</key>
	<string>${version}</string>
	<key>HPDBookAccessPath</key>
	<string>index.html</string>
	<key>HPDBookIndexPath</key>
	<string>Segue.helpindex</string>
	<key>HPDBookTitle</key>
	<string>${bookTitle}</string>
	<key>HPDBookType</key>
	<string>3</string>
</dict>
</plist>
`;
writeFileSync(join(book, 'Contents', 'Info.plist'), plist);

// The search index (anchors included, English stopwords). Written beside the pages, then
// moved in, so hiutil does not index its own output.
const index = join(derived, 'Segue.helpindex');
execFileSync('/usr/bin/hiutil', ['-I', 'lsm', '-Caf', index, '-s', 'en', '-l', 'en', lproj], { stdio: 'inherit' });
renameSync(index, join(lproj, 'Segue.helpindex'));

writeFileSync(join(derived, 'anchors.txt'), `${[...anchors.keys()].sort().join('\n')}\n`);
writeFileSync(join(derived, 'source.sha256'), `${sourceHash()}\n`);
console.log(`helpbook: Segue.help for Segue ${version}, ${pages.size} pages, ${anchors.size} anchors`);
