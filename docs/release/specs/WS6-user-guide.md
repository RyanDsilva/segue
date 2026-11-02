# WS6 - User guide (segue.ryandsilva.dev/guide)

Status: **final.** Ryan resolved the open questions on 2026-10-19 (R127, recorded at the end).
Spec date: 2026-10-19. Target: Segue **1.0** (formerly 0.5, R176), ships with the release (R126).

This is the brief for one focused build session (or two, see section 11). It must be executable standalone. Read these first:

- `docs/release/decisions.md` - canonical. This spec follows **R126** and builds on R21, R27, R29, R36, R38, R39, R43/R55/R57 (site direction and restraint), R46, R48, R50, R79 (release order), R113 (test budget). Where this spec and the decisions file disagree, the decisions file wins: stop and ask Ryan.
- `docs/release/specs/WS4-website.md` - the site this guide joins: generator (`scripts/gen-site.swift`, `make site`, `make site-check`), URL contract (section 2), theme (5.2), Apple marketing rules (7), checks (8.1), `_headers` (9.3), help outline (9.7, superseded here), Cloudflare setup (R-3).
- `docs/release/specs/WS5-store-listing.md` sections 8 and 9 - the screenshot and preview capture design. The guide's capture layer is the **same** layer (section 5 below).
- `docs/phases/3-ai-entry-and-assistant.md` (sections 6-10, 16.0) and `docs/phases/3-workstreams/P3-*.md` - the phase 3 features the guide covers.
- `docs/brand.md`, `design/tokens.json`, `website/assets/css/tokens.css`.

**Rules for the implementing agent**

- Sibling agents may be editing other files concurrently (e.g. `Packages/SegueCore/Sources/Ingest`). Expect a dirty `git status`; never revert or "fix" files you do not own; stage only your own files, by pathspec.
- `cat` and `ls` are aliased to eza and can hang: use `command cat`, `command ls` or the Read tool. Pass this on to any subagent.
- Never `rm -rf`: use `trash`. No em dashes anywhere (copy, code, comments): use "-".
- Commits: local, signed (`git commit -S`), conventional messages, no co-author lines, one commit per step in section 11. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging, tell the orchestrator, wait. Never push, never touch Cloudflare (those are [RYAN] steps, section 12).
- Tools only through mise (`mise exec --`); nothing global. `ASTRO_TELEMETRY_DISABLED=1` on every Astro run (Astro collects telemetry by default).
- Write every page from the **built App Store flavour** (`Debug-AppStore`), opening each feature as you document it. Every menu name, button title and key must match the build exactly. Never document Personal-only features (custom MLX models in Settings > AI > Advanced, URL import, LRCLIB). Sound (hearing chords, walk-ups and fills, play-along, Settings > Audio; P8-6) is in both flavours and is documented.

---

## 0. Decisions applied

| Ruling | What it means here |
|---|---|
| R126 | Guide at `/guide`, same Cloudflare Pages project and deploy as `website/`; `/help/*` redirects to it; Astro Starlight; `make docs-shots` from the real app (Welcome library, light and dark); a few short silent clips (paste a song, build a set, go on stage); in-app Help buttons and tips open exact guide pages; ships with 0.5. |
| R21, R29 | `/help` was the help home. It becomes a redirect (section 7.3). The site's page list gains `/guide`. |
| R27, R38 | Static only, Cloudflare Pages, Cloudflare Web Analytics only (cookieless, injected at the edge). No other analytics, no cookies. |
| R36 | Appearance follows the system in the app by default; the guide's theme behaviour is open question 2. |
| R39 | 2-3 directions shown before building: section 3 and the renders listed there. |
| R55, R57 | Restraint: short, visual, few words. The guide matches the landing page's tokens, type and rounded tiles, not a generic docs look. |
| R48, R50 | CI stays lightweight Linux: the guide build and its static checks join the Site workflow; Dependabot covers `guide/`. |
| R79 | The guide's screenshots need the post-walkthrough UI; when it lands is open question 8. |
| R113 | Targeted checks per step, ONE `make quick` at the end, no `make gate` (section 11). |
| P3-9 step 2 | The phase 3 help-page bullet of P3-9 ("help pages for paste/import ... the metronome") **moves to WS6**. P3-9 keeps the privacy policy, support FAQ, changelog and claims-audit parts and must not edit `website/help/`. |

---

## 1. Goal and non-goals

1. A task-oriented user guide that gets a musician from first launch to the end of a gig: short pages, one job each, real screenshots, three short clips.
2. It never goes stale silently: screenshots are regenerated from the real app by one command; the keyboard reference is generated from the app's own tables; every app deep link is checked against the built guide.
3. It looks like Segue's site (dark-first, Schibsted Grotesk, tokens, one coral cue) and costs nothing to run.
4. The app links into it precisely: Help menu, Help buttons on sheets and Settings panes, tips, What's New.

**Non-goals:** localisation; versioned docs; comments, ratings or "was this helpful" (needs a backend, R23); a blog; any server code; an in-app web view (links open in the default browser, as today); documenting Personal-only features.

---

## 2. Information architecture

### 2.1 Rules

- **Flat URLs.** Every page is `/guide/<slug>`; groups exist only in the sidebar. Moving a page between groups never changes its URL. `/guide` itself is Getting started.
- **One task per page**, titled as the task ("Paste a song from a chord site"), 150-400 words, 1-4 screenshots, at most one clip. Steps are numbered lists; reference detail goes in short H2 sections below the steps.
- **Every H2 has a stable id** (Starlight slugs headings). Ids used by the app are the contract in section 7.1; renaming such a heading is caught by `make site-check`.
- **Order of the sidebar = the musician's workflow** from the landing page (R55): bring your songs in, make each chart yours, build the set, play the show; then settings and reference.

### 2.2 Pages

Shot ids name files in `guide/public/shots/` (section 5.6); every shot exists in `dark` and `light` unless marked (stage shots are always dark, one file). Clips are in section 6.

**Start here**

| Slug | Title | Purpose and sections (H2 ids) | Shots / clip |
|---|---|---|---|
| `/guide` | Getting started | What Segue is in two sentences; four workflow tiles (one per group, each opening its first page); "Your first show in five steps" (`#first-show`): pick a folder, the Welcome library, paste a song, build a set, go on stage; "Deleted something?" (`#trash`) one line, links back-up. | `start-library` (main window, Welcome library), tiles reuse `paste-review`, `card`, `builder-arrange`, `stage`; clip `go-on-stage` |
| `welcome-library` | The Welcome library | The four original songs and the Welcome Set; try things on them; Settings > Data > Remove Welcome Songs keeps edited ones (`#remove`); Help > Welcome to Segue... reopens the cards (`#welcome-cards`). | `welcome-cards` |
| `library-folder` | Your library folder | Where songs live: `.cho` files, the Segue details file, setlists, `shows/`, `filters/` (`#files`); change the folder (`#change`); Finder: Show in Finder, Open With, Quick Look (`#finder`); search by any line, romanized Hindi spellings (`#search`); Rebuild Index (`#rebuild`); iCloud Drive and other synced folders, the warning banner (`#file-sync`, P9-6 5.4). | `library-search` (search `kitabon`) |

**Bring songs in**

| Slug | Title | Purpose and sections | Shots / clip |
|---|---|---|---|
| `paste-a-song` | Paste a song from a chord site | Copy a chord sheet, `⌥⌘V` (or the empty-library button, or `⌘V` in the song list) (`#paste`); the review sheet: preview, metadata block (song card), section labels, sparkle marks for what AI decided (`#review`); fix a label (`#fix-labels`); "Refining with..." and what produced the result (`#ai`); paste is off during a show (`#during-a-show`). | `paste-review`, `paste-review-labels` (crop with a sparkle); clip `paste-a-song` |
| `import-files` | Import files | Formats (`#formats`: `.cho`, `.chordpro`, `.chopro`, `.pro`, `.txt`, `.crd`); drag onto the library or File > Import Songs... `⇧⌘I` (`#drag`); files that need converting go through one review sheet with a checkbox per file (`#batch`); copies, never moves (`#copy`); Open With Segue (`#open-with`); files that can't be read (`#problems`). | `import-batch` |
| `new-song` | Start a song from scratch | New Song `⌘N` opens the paste flow; "Start blank" opens an empty editor with the song card (`#blank`). | `new-song` |

**Make each chart yours**

| Slug | Title | Purpose and sections | Shots / clip |
|---|---|---|---|
| `song-card` | The song card | Title, artists, Movie / Album, key, tempo (tap tempo, `#tempo`), capo, time signature, proficiency, tags; set essentials (key and tempo) and their dots (`#essentials`); the Missing essentials filter. | `card` |
| `edit-a-song` | Edit a song | Visual and Text modes (`#modes`); move a chord by dragging (`#chords`); autosave and `⌘S` (`#autosave`); undo; spell-check off in lyrics (`#spelling`); file changed on disk. | `editor-visual` |
| `sections` | Sections and the section band | Select lines, press V / C / B / I or a chip (`#make`); drag a band's edge (`#resize`); relabel; collapse repeats on stage (`#repeats`). | `band` (crop) |
| `section-notes` | Section notes | One note per section; "Show on stage only" (`#stage-only`); how notes show on stage. | `notes-sheet`, `notes-stage` (dark only) |
| `text-mode` | Text mode, the slash menu and ChordPro | The `/` menu (`#slash`); `{` completion and value help (`#completion`); key validation fix (`#key-check`); a 6-line ChordPro example written for Segue (`#chordpro`). | `slash-menu` (crop) |
| `transpose` | Transpose, capo and diagrams | Change key or capo for this view only (`#transpose`); shapes vs concert pitch (`#capo`); Nashville numbers (`#nashville`); guitar and piano diagrams, your own shapes (`#diagrams`). | `transpose`, `diagrams` (crop) |

**Build the set**

| Slug | Title | Purpose and sections | Shots / clip |
|---|---|---|---|
| `build-a-set` | Build a set for a gig | New Setlist `⇧⌘N`; Pick (`⌘1`): Space ticks, `⌘A` ticks the filtered list, tick order is set order (`#pick`); Arrange (`⌘2`): `⌥↑` `⌥↓` and drag (`#arrange`); add from the main library with multi-select (`#from-library`); each song once per set (`#once`); per-show key and capo (`#key-and-capo`); undo. | `builder-pick`, `builder-arrange`; clip `build-a-set` |
| `set-assistant` | Ask the assistant for a set | Type a request above the set, Build (`#build`); chips and removing them (`#chips`); why a song was picked (`#why`); lock rows, Rebuild (`#lock`); songs with no time are left out (`#left-out`); request words Segue understands (`#words`); suggested chips come only from the downloaded model (`#model-chips`). | `assistant-bar`, `assistant-why` (crop) |
| `running-time` | Breaks, changeover and running time | Insert Break `⇧⌘B`, per-part totals (`#breaks`); break length (`#break-length`); changeover time and its default (`#changeover`); each song's time from its tempo and bars; songs with no time stay unknown, the "N unknown" button lists them with a Tempo field (`#unknown`). | `timeline`, `missing-times` (crop) |
| `arrange-sections` | Arrange sections for one gig | Arrange Sections... `⇧⌘A`: tick, repeat, reorder for this slot only (`#arrange`); the song file never changes, Reset to full song (`#reset`); the slot's time in the footer (`#slot-time`); out of date (`#out-of-date`); Play Again Later (`#play-again`). | `arrange-sheet` |
| `smart-filters` | Tags and smart filters | Tags on the card (`#tags`); rename, merge, delete (`#manage`); a smart filter from conditions (`#smart`); Missing essentials (`#missing`). | `filter-editor` |

**Play the show**

| Slug | Title | Purpose and sections | Shots / clip |
|---|---|---|---|
| `go-on-stage` | Go on stage | Start Show `⌘↩` and the pre-show checklist (`#start`, `#checklist`); move through the set, pedals (`#navigate`); minimum lyric size and auto-fit (`#minimum-size`); auto-scroll (`#auto-scroll`); columns and zoom (`#view`); break interstitial (`#breaks`); end the show `⌘.` (`#end`); resume after a quit (`#resume`). | `checklist`, `stage` (dark), `stage-break` (dark); clip `go-on-stage` |
| `requests` | Take a request mid-set | Quick search `⌘K` or `/`, Return / `⌥↩` / `⌘↩` (`#search`); the request queue, Q and R (`#queue`); no repeats in a show, Move to Next (`#no-repeats`). | `stage-search` (dark) |
| `metronome` | The metronome | The pulse (M) for this show (`#pulse`); hidden without a tempo (`#no-tempo`); compound meters (`#meters`); the click in rehearsals only (K) (`#click`); Settings > Live default. | `metronome` (dark crop) |
| `rehearse` | Rehearse a set | Rehearse `⌥⌘↩`; what differs from a show (`#differences`). | none |
| `gig-mode` | Gig Mode Shortcuts | Off until set up (`#set-up`); the Shortcuts to create (`#create`); Settings > Live, Test (`#test`); the checklist row ticks only after a real run, Done (`#checklist`); why Shortcuts flashes (`#focus`). | `settings-live` |
| `gig-log` | After the show: the gig log | What is saved; save or discard a changed order (`#order`); edit a past gig (`#edit`). | `gig-log` |

**Settings and data**

| Slug | Title | Purpose and sections | Shots / clip |
|---|---|---|---|
| `ai` | AI in Segue | What AI does and does not do (refines pastes and set requests, deterministic first; never writes lyrics) (`#what`); the one toggle (`#toggle`); Apple's on-device model and why it may be unavailable, per reason (`#apple`); the optional local model: download, size, memory, delete (`#local-model`); what goes online: only the model download, from Hugging Face, when you click (`#online`). | `settings-ai` (no model), `settings-ai-installed` |
| `privacy-settings` | Privacy settings | The two first-run questions; Settings > Privacy; links `/privacy`. | `settings-privacy` |
| `back-up` | Back up and restore | Export Library Archive (`#export`); the Trash and Undo (`#trash`); Reset All Settings (`#reset`). | none |

**Reference**

| Slug | Title | Purpose and sections | Shots / clip |
|---|---|---|---|
| `keyboard` | Keyboard shortcuts | Generated tables (section 4.6): menus by menu (`#menus`), stage keys by group (`#stage`), plus a short verified hand table "In the editor and builder" (`#editing`). | none |
| `troubleshooting` | Troubleshooting | Search looks wrong; a file can't be read; Apple's model unavailable; a Shortcut doesn't run; resume didn't appear; contact (`/support`). | none |

27 pages, about 40 shot ids, 3 clips.

---

## 3. Visual directions (R39, pick in open question 1)

Renders (1440x1000, a Getting started page and a task page, dark and light, built from Segue's tokens and fonts with real app captures) are in the session scratchpad: `/private/tmp/claude-501/-Users-ryan-Desktop-Projects-setlist/11e6f3f5-3259-4d95-a8b2-e97811cddc3b/scratchpad/ws6/` (`a-starlight-*.png`, `b-article-*.png`, `c-tiles-*.png`, `contact-sheet.png`; the HTML sources sit next to them). All three are buildable with Starlight: A is Starlight's own layout re-skinned; B and C are Starlight with component overrides.

- **A "Starlight, branded".** Starlight's three columns (sidebar, content, "On this page"), top bar with wordmark, search and site links. Steps as outlined number circles, a coral-ruled aside, prev/next cards. Most familiar docs layout, least override work, most "generic docs".
- **B "Support article".** Apple Support style: no sidebar on articles; one centred 700 px column, breadcrumb, large headline, plain numbered steps, screenshots wider than the text with a soft shadow, hairline note, "Related" list. The guide home is a search-first hub with four workflow tiles and a "Start here" list. Calm and very readable; navigation between neighbouring tasks is weaker.
- **C "Tiles" (Linear / Things).** A quiet tinted sidebar with numbered workflow groups (1 Bring songs in ... 4 Play the show), content with large rounded `surface-alt` panels (the landing page's C Keynote tiles) holding screenshots inset, steps as solid numbered rows with a hairline, a soft coral callout, prev/next cards. Getting started is a 2x2 grid of workflow tiles with a screen each. Closest to the landing page.

Common to all: tokens only (no hex in hand-written CSS, WS4 check 5), Schibsted Grotesk 400/600/700/800 from `/assets/fonts/`, coral only for the cue dot, the active marker and callout accents, `<kbd>` keycaps, 16 px side gutter on phones and no horizontal scroll at 320 px, focus ring `2px solid var(--cue)`, motion only under `prefers-reduced-motion: no-preference`.

---

## 4. Build and deploy

### 4.1 Toolchain

- Node and pnpm already pinned in `.mise.toml` (`node = "26.12.0"`, `pnpm = "12.14.0"`). No new runtime. Bun is not used (pnpm is already the site's tool).
- Packages (pin exact versions at implementation; current on 2026-10-19): `astro 7.4.1` (engines: node >= 22.22), `@astrojs/starlight 0.42.6` (peer astro ^7.2.10; brings `pagefind 1.5.2` and `@astrojs/sitemap`), `starlight-links-validator 0.27.0`. Nothing else unless a step needs it.
- `guide/package.json`: `"private": true`, `"packageManager": "pnpm@12.14.0"`, `"engines": {"node": "26.12.0"}`, exact versions (no `^`), `pnpm-lock.yaml` committed, `pnpm install --frozen-lockfile` everywhere.
- Repo root `.node-version` containing `26.12.0` (Cloudflare Pages reads it); `make guide-check` fails if it differs from the mise pin.

### 4.2 Layout

```
guide/                               source (committed)
  package.json pnpm-lock.yaml astro.config.mjs tsconfig.json
  src/content/docs/                  one .mdx per page (index.mdx = Getting started)
  src/content.config.ts              Starlight docs collection
  src/components/                    Shot.astro, Clip.astro, Keys.astro, Steps.astro, KeyboardTables.astro, AppleModelName.astro, overrides (SiteTitle, Footer, ThemeSelect/ThemeProvider per question 2)
  src/styles/guide.css               imports ../../website/assets/css/tokens.css; maps Starlight's --sl-* variables to tokens
  src/data/keyboard.json             GENERATED by the SegueUI export test (4.6), committed
  src/data/shots.json                GENERATED by make docs-shots (manifest, 5.6), committed
  public/shots/*.avif                GENERATED by make docs-shots, committed (5.6)
  public/clips/*.mp4                 GENERATED by make docs-clips, committed (6)
website/guide/                       BUILD OUTPUT (gitignored), Astro outDir
```

`.gitignore` gains `website/guide/`, `guide/node_modules/`, `guide/.astro/`. `.htmlvalidateignore` (or the config's ignore) excludes `website/guide/**`: html-validate keeps checking only hand-written pages.

### 4.3 `astro.config.mjs` essentials

- `site: 'https://segue.ryandsilva.dev'`, `base: '/guide'`, `outDir: '../website/guide'`, `trailingSlash: 'never'`, `build.format: 'file'` (flat `.html` files, WS4 section 2: no trailing slash, no redirect hop).
- `build.inlineStylesheets: 'never'` and `vite.build.assetsInlineLimit: 0`, so no inline `<style>` or `<script>` lands in the output (CSP, 4.5).
- Starlight: `title: 'Segue Guide'`, `disable404Route: true` (the site's `/404.html` serves every unknown path), `pagefind: true`, `expressiveCode: false` (no syntax highlighting needed; drops its JS and CSS), `lastUpdated: false`, no `editLink`, no `social`, `favicon: '/favicon.svg'`, `customCss: ['./src/styles/guide.css']`, the sidebar from section 2.2 written out explicitly (no autogenerate, so order is deliberate), `plugins: [starlightLinksValidator({ errorOnRelativeLinks: true })]`.
- **Verify the guide root.** With `build.format: 'file'` Astro writes the root page as `website/guide/index.html`, which Pages serves at `/guide/` and may redirect `/guide` to. In `make site-serve`, check `curl -sI localhost:8788/guide`: a 200 is the goal. If it 308s, add a post-build step in `make guide` that moves `website/guide/index.html` to `website/guide.html` (asset URLs are absolute, so nothing else changes) and re-check. Record the result in the commit message.

### 4.4 How the guide reaches the deployed site

**Cloudflare Pages builds it from source** (no build output committed). The Pages project does not exist yet (WS4 R-3 is still a [RYAN] step), so its setup changes before it is created:

- Build command: `scripts/pages-build.sh` (committed, so the logic is git-tracked and the dashboard holds one line). The script: checks `node --version` matches `.node-version`; runs `npx --yes pnpm@12.14.0 --dir guide install --frozen-lockfile` and `ASTRO_TELEMETRY_DISABLED=1 npx --yes pnpm@12.14.0 --dir guide build`; fails loudly on any error. It never touches `website/` outside `website/guide/`.
- Build output directory: `website` (unchanged). Root directory: empty (repo root).
- Build watch paths: include `website/*`, `guide/*`, `scripts/pages-build.sh`, `.node-version`.
- [VERIFY] at implementation: Cloudflare's current Pages build image honours `.node-version` with `26.12.0`. If it cannot provide that version, stop and ask Ryan (fallbacks: a `NODE_VERSION` variable in the dashboard, or lowering the pin for the whole repo).
- The build agent edits WS4 R-3 and release README section 2.4 to the values above (docs only); Ryan does the dashboard (section 12).

**Site CI workflow** (`.github/workflows/site.yml`): a new job `guide` (ubuntu, mise-action with `node pnpm`, `MISE_EXEC_AUTO_INSTALL: "false"` as today): `make guide` (install frozen, build, links validator) then `make guide-check` (the Linux-runnable checks in 4.7). Same pinned action SHAs as the existing jobs. Dependabot gains an `npm` entry for `/guide` (weekly, grouped).

**Local:** `make guide` (build into `website/guide/`), `make guide-dev` (Astro dev server with hot reload at `localhost:4321/guide`), `make site-serve` (wrangler on `website/`, now depends on `make guide`, so redirects, `_headers` and the guide are previewed together exactly as Pages serves them).

### 4.5 Privacy, scripts and `_headers`

- **No cookies.** Starlight sets none; Pagefind sets none. With the theme select kept (question 2, option b) Starlight stores the choice in `localStorage` only. `make guide-check` greps the built JS for `document.cookie` and fails on a hit.
- **Analytics:** Cloudflare Web Analytics only, injected at the edge into every HTML response, `/guide` included. Nothing in source.
- **The landing site's "no JavaScript of our own" rule** (WS4 goal 4, check 3) cannot hold for the guide: Starlight's search, mobile menu and table of contents are scripts. They are bundled, first-party, served from `/guide/_astro/` and `/guide/pagefind/`, with no third-party code. Open question 7 confirms this exception, scoped to `/guide/*` only.
- **Search works fully static and offline-capable:** Pagefind builds its index at build time into `website/guide/pagefind/`; queries run in the browser (WebAssembly) against same-origin files. No search service.
- `_headers` gains a `/guide/*` block that **detaches** the site CSP and sets the guide's (Cloudflare `_headers` combines values of matching rules; `! Content-Security-Policy` removes the inherited one):

```
/guide/*
  ! Content-Security-Policy
  Content-Security-Policy: default-src 'none'; script-src 'self' 'wasm-unsafe-eval' https://static.cloudflareinsights.com; connect-src 'self' https://cloudflareinsights.com; img-src 'self'; media-src 'self'; style-src 'self'; font-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'; upgrade-insecure-requests
```

  Verify in headless Chrome against `make site-serve` that every guide page loads with **zero CSP violations** in the console (search opened and queried, mobile menu opened, a clip played). If Starlight emits `style=` attributes or an inline script that cannot be externalised, prefer an override component that removes it; only if that is impossible, add the narrowest source (`'sha256-...'` hash, or `style-src-attr 'unsafe-inline'`) and say so in the commit. WS4 check 9 ("`_headers` contains exactly the CSP line") is updated to expect both blocks.
- `robots.txt` gains `Sitemap: https://segue.ryandsilva.dev/guide/sitemap-index.xml` (Starlight's own sitemap); `website/sitemap.xml` stays the landing site's.

### 4.6 Keyboard reference generated from the app

- A new in-process SegueUI test, `GuideKeyboardExportTests`, builds `guide/src/data/keyboard.json` from `MenuShortcuts.all` (menu, title, `displayText`, system flag) and `KeyHelp.groups(InputBindingTable.defaults)` (group, command title, keycaps). With `SEGUE_WRITE_GUIDE_DATA=1` it writes the file; without it, it asserts the committed file is byte-identical and fails with "run make guide-keys". So `make quick` and `make test-packages` catch drift.
- `make guide-keys`: runs that one test with the variable set.
- `KeyboardTables.astro` renders the JSON as `<kbd>` tables. The "In the editor and builder" table (section band V/C/B/I, Pick Space and `⌘A`, quick search Return / `⌥↩` / `⌘↩`) is hand-written because those keys live in view code, not a table; each row is verified in the build during the claims audit.
- The in-app `?` overlay and Help > Keyboard Shortcuts already read the same sources, so app and guide cannot disagree.

### 4.7 Checks (keeping `make site-check` meaningful)

`make site-check` now runs `make guide` first, then `gen-site.swift --check`, which changes as follows:

- **Link check (check 1) walks `website/guide/**/*.html` too**, resolving `/guide/...` URLs and `#ids` against the built pages. So every `SegueLinks.swift` URL (section 7.1 writes guide links as full string literals, which the existing scanner already picks up), every `content/changelog.json` `help` path and every redirect target in `_redirects` must resolve against the real guide output.
- Checks 2, 3, 5 and 6 (page basics, no scripts, hand-written CSS literals, `<img>` attributes) skip `website/guide/` (generated); the guide gets its own checks in `make guide-check`: no external `src`/`href` for scripts, styles, fonts, images or media; no `document.cookie`; no em dash in `guide/src/**` or the built HTML; no hex/rgb literal in `guide/src/styles/`; `.node-version` equals the mise pin; every `<Shot id>` and `<Clip id>` used in `.mdx` exists in `shots.json` and on disk in every appearance it declares; shot and clip size budgets (5.6, 6); `keyboard.json` parses and has every `LiveCommand`.
- The section 2 contract list in `gen-site.swift` (`Spec.contractLinks`) is replaced by the guide contract from section 7.1.
- `content/changelog.json` `help` may start with `/guide` (gen-site validation and the WS2b `WhatsNewTests` prefix rule both change); existing `/help/...` values are rewritten to guide URLs.
- `make check` keeps `site-check`; `make quick` stays app-only apart from the keyboard export test.

---

## 5. Screenshot pipeline: `make docs-shots`

### 5.1 Driver: XCUITest on the App Store flavour (shared with WS5)

| Option | Verdict |
|---|---|
| **XCUITest flows** (`SegueAppStoreUITests`, App Store flavour) | **Chosen.** The real app with real chrome, sheets, popovers and menus; the same launch flags and target WS5 uses for store screenshots (one capture layer, R10); element screenshots give exact crops; assertions catch a wrong state. |
| In-process `NSHostingView` renders (`SmartFilterRenderTests` style) | Only as a fallback for a state XCUITest cannot hold still (none known). They miss window chrome, sheet presentation and materials, render at the host's scale, and can drift from the shipped composition. |
| AppleScript / System Events | Rejected: needs Accessibility permission, cannot assert state, brittle to timing. |

The capture layer is WS5 section 8.2-8.3: target `SegueAppStoreUITests` (sources `UITests/AppStore/**` + `UITests/E2ESupport.swift`, scheme `Segue-AppStore`, `Debug-AppStore`), and the Debug-only flags `-SegueScreenshotLibrary YES`, `-SegueAppearance dark|light` (exists), `-SegueWindowFrame`, `-SegueStageWindowed YES`, `-SegueFixedClock`. Whichever of WS5 and WS6 lands first builds it exactly as WS5 specifies (open question 3); the other only adds its own tests and plan. Every new flag string goes into `scripts/verify-appstore.sh`'s grep list (WS1 B-7).

### 5.2 Deterministic content

- **Welcome library only** for songs with lyrics (R19, R126): the four Welcome songs and the Welcome Set, via `-SegueScreenshotLibrary YES`. No real song titles or lyrics anywhere. WS5's screenshot-only songs (titles and chords only, A48) may appear in lists once Ryan has approved their titles; until then lists show the Welcome songs only.
- **Guide fixtures** (new, Debug-only, `App/Sources/Debug/GuideFixtures.swift`, compiled only under `#if DEBUG`, applied by a new `-SegueGuideFixtures YES` flag after the screenshot library is written):
  - a chord-site-style paste of a Welcome song (our own text: header line, chord-over-lyric layout, a couple of junk lines such as "Transpose" that the converter removes), put on the pasteboard by the test;
  - a recorded refinement for that paste replayed by the existing `ScriptedProvider`, so the review sheet shows sparkle marks and "Refining with..." deterministically (new flag `-SegueScriptedAI <fixture-name>`; test runs otherwise get no providers);
  - tags and proficiencies on the Welcome songs, one smart filter, one break row and changeover in a copy of the Welcome Set, one past gig in `shows/` dated by the fixed clock;
  - the model store states for Settings > AI (not installed / installed) through the existing scripted store.
- `-SegueFixedClock 2026-11-20T20:00:00Z` for every capture (gig log dates, show clock, "last played").
- Consent declined, tips hidden, What's New and review prompt suppressed (the WS5 composite already does this). One test turns tips on for the `tips` shot only, if a tip is pictured.

### 5.3 Appearance, window, scale

- Two test-plan configurations, `Dark` and `Light` (environment `SEGUE_SHOT_APPEARANCE`), as WS5. Stage shots are captured once (always dark).
- Main window `-SegueWindowFrame 0,40,1280,800` (points). The guide column is about 720-860 px wide, so most shots are **element crops** displayed near 1:1 and stay legible; full-window shots are few (`start-library`, `builder-*`).
- Retina only: the test asserts the captured image is exactly 2x the element's point size and fails otherwise (an external non-Retina display would silently halve quality).
- Pointer moved off the window before each capture; no hover or focus rings unless the shot is about focus.

### 5.4 Test structure

- `UITests/AppStore/Guide/GuideShots*.swift`, one class per sidebar group, one test per page, each driving to a state and calling `shoot(id:, element:)`, which attaches `XCUIElement.screenshot()` as `guide-<id>-<appearance>` (`.keepAlways`) plus a JSON attachment `guide-<id>-<appearance>.frames` with the frames of named callout targets (accessibility identifiers) relative to the captured element.
- Test plan `UITests/AppStore/GuideShots.xctestplan`: parallel off, no retries (a flaky shot is a bug), system screenshots deleted on success. `make e2e` and `make gate` never run it.

### 5.5 Make target

```make
docs-shots: ## Guide screenshots from the App Store flavour (needs the screen; ONLY=<id,...> for a subset)
	SEGUE_RESULT_BUNDLE=.build/docs-shots/run.xcresult $(XCODEBUILD) -scheme Segue-AppStore \
	  -configuration Debug-AppStore -testPlan GuideShots test $(if $(ONLY),...)
	xcrun xcresulttool export attachments --path .build/docs-shots/run.xcresult \
	  --output-path .build/docs-shots/raw --schema-version 0.4.0
	scripts/docs-shots.swift --raw .build/docs-shots/raw --out guide/public/shots \
	  --manifest guide/src/data/shots.json
```

(`.build/docs-shots` is moved to the Trash with `trash` at the start, never `rm -rf`.) Not part of `check`, `gate` or CI: it needs a logged-in session with a Retina screen.

> *As built (2026-11-01): `make docs-shots` and `make docs-clips` run in a throwaway Retina E2E VM clone by default (`scripts/lib/capture.sh`, `docs/research/e2e-off-screen.md` 7.2), dark then light, and bring the attachments back to the host for `docs-shots.swift`; `E2E_RUNNER=host` keeps the screen path. No screen and no Screen Recording grant needed.*

### 5.6 `scripts/docs-shots.swift` and outputs

- Swift script (AppKit/ImageIO only, like `gen-icon.swift`), reading the xcresult manifest by attachment-name prefix.
- **Format: AVIF**, written by ImageIO (`public.avif` is a writable type on macOS 26; checked 2026-10-19), quality about 0.8, sRGB, no metadata. Every browser the guide targets (Safari 16+, current Chrome and Firefox) shows AVIF, and UI crops land around 30-90 KB. The guide serves the files as-is from `public/` (no Astro image pipeline, no `sharp` in the Pages build).
- **Write only on real change:** decode the existing file and compare pixels; keep the old file when fewer than 0.5% of pixels differ by more than 8/255. Re-running on an unchanged UI produces no git diff, so history only grows when the UI actually changed.
- Names: `<id>-<appearance>.avif` (`paste-review-dark.avif`), stage shots `<id>.avif`.
- `shots.json`: per id, the appearances present, pixel size, point size and callout frames as fractions of the image. `Shot.astro` renders `<picture>` with `<source media="(prefers-color-scheme: dark)">` (or the theme-attribute variant if question 2 keeps the toggle), explicit `width`/`height`, `loading="lazy"`, `alt` from the page, and numbered callouts (open question 6).
- **Budgets** (checked by `make guide-check`): each shot at most 150 KB, all shots at most 8 MB.

---

## 6. Clips: `make docs-clips`

- Three clips, each 8-15 s, silent, dark appearance: `paste-a-song` (copy the fixture paste, `⌥⌘V`, review sheet, sparkles settle, Import), `build-a-set` (Pick: Space through four songs, `⌘2`, `⌥↓` one row, Insert Break, total updates), `go-on-stage` (`⌘↩`, checklist, Start, stage, `→`, `⌘K` request, Return).
- Capture as WS5 9.3: an XCUITest per clip (`GuideClips.xctestplan`) with explicit `hold(seconds:)` pacing, while `screencapture -v` records the window rectangle (cursor visible, so clicks read). [RYAN] grants Screen Recording to the terminal once (shared with WS5's preview).
- Encode with ffmpeg via mise (WS5 9.4 adds it; whoever lands first pins it): crop to the window, scale to 1280 px wide, 30 fps, H.264 High, CRF about 28, `yuv420p`, `-an` (no audio track), `-movflags +faststart`; poster = the last frame as AVIF through `docs-shots.swift --poster`. One format (MP4 H.264) plays everywhere.
- Budget: each clip at most 1.5 MB, all clips at most 5 MB. Clips are regenerated only by `make docs-clips` (never by `docs-shots`), so they change rarely.
- `Clip.astro`: `<video muted loop playsinline preload="none" poster=... width height>` with a caption naming the steps in text; playback per open question 5. WS4's "stills only, no video loops" (A53) applies to the landing page's product art and stays; R126 explicitly adds clips to the guide.

---

## 7. In-app deep links

### 7.1 `SegueLinks` changes

- `SegueLinks.help` becomes `https://segue.ryandsilva.dev/guide` (Help > Segue Help, About panel's Help link). `SegueLinksTests` updates its expected path.
- New `public enum Guide: String, CaseIterable` inside `SegueLinks`, one case per linked page or anchor, each raw value a **full URL string literal** (so `gen-site.swift --check`'s existing scanner resolves every one against the built guide), plus `var url: URL`. `helpPage(_:)` is removed (no free-form paths).
- An in-process test asserts every case parses and starts with `SegueLinks.site`.

### 7.2 Surface map

| App surface | Control (new unless noted) | Guide URL |
|---|---|---|
| Help > Segue Help (exists) | menu item | `/guide` |
| Help > Keyboard Shortcuts window | footer link "All shortcuts" | `/guide/keyboard` |
| Empty library state | "How to bring songs in" link under the paste button | `/guide/paste-a-song` |
| Paste review sheet (single and batch) | standard `?` help button, bottom left | `/guide/paste-a-song#review` (batch: `/guide/import-files#batch`) |
| Song card | `?` in the card's header menu | `/guide/song-card` |
| Section Notes sheet | `?` help button | `/guide/section-notes` |
| Set builder, Arrange, assistant bar | `?` at the bar's end | `/guide/set-assistant` |
| "N unknown" unknown-time popover | "Running time" help | `/guide/running-time#unknown` |
| Arrange Sections sheet | `?` help button | `/guide/arrange-sections` |
| Smart filter editor sheet | `?` help button | `/guide/smart-filters#smart` |
| Pre-show checklist | `?` help button | `/guide/go-on-stage#checklist` |
| Settings > Live | `?` at the bottom of the pane | `/guide/go-on-stage#minimum-size`; Gig Mode Shortcuts section: `/guide/gig-mode` |
| Settings > AI | `?` at the bottom of the pane | `/guide/ai` |
| Settings > Privacy (exists: policy links) | `?` at the bottom of the pane | `/guide/privacy-settings` |
| Settings > Data | `?` at the bottom of the pane | `/guide/back-up` |
| Tips: Paste any chord sheet / Search by any line / Change the key / Move a chord / Start the show / Gig Mode | a "Learn More" tip action | `/guide/paste-a-song`, `/guide/library-folder#search`, `/guide/transpose#transpose`, `/guide/edit-a-song#chords`, `/guide/go-on-stage`, `/guide/gig-mode` |
| File-sync folder banner (P9-6 5.4) | "Learn More" | `/guide/library-folder#file-sync` |
| What's New highlights (exists) | "Learn More" | the highlight's `help` path, now `/guide/...` |

- The `?` buttons are the macOS standard help button (SwiftUI `HelpLink` or the bordered circular `?`), with an accessibility label "Help: <page title>", opening through `WorkspaceActions` (recorded by `-SegueWorkspaceLog` in tests). No help buttons on stage (nothing distracting during a show; tips are already off there).
- Coverage: one in-process SegueUI test per surface that asserts the button exists and the action opens the right `Guide` case (the workspace recorder), plus one existing E2E class touched only if a control cannot be reached in-process (R113).

### 7.3 Redirects from `/help/*`

`gen-site.swift` writes these into `_redirects` (generated, from a `redirects` list added to `content/site.json`), and the old pages `website/help.html`, `website/help/*.html` and `content/partials/help-nav.html` are moved to the Trash. Their text is the starting point for the matching guide pages.

```
/help                /guide                    301
/help/library        /guide/library-folder     301
/help/import         /guide/import-files       301
/help/editor         /guide/edit-a-song        301
/help/setlists       /guide/build-a-set        301
/help/live           /guide/go-on-stage        301
/help/shortcuts      /guide/gig-mode           301
/help/keyboard       /guide/keyboard           301
/help/*              /guide                    301
```

Fragments survive a redirect in browsers. The old anchors were never shipped (no released app, site not live), so only anchors that still exist on the target page carry over; nothing else needs preserving. The site header's "Help" nav item becomes "Guide" (`/guide`), and the footer's Help link likewise.

---

## 8. Copy rules

- **Short, visual, Ryan's voice:** second person, present tense, plain words, no marketing adjectives. Lead with the action ("Copy a chord sheet and press `⌥⌘V`"). One idea per sentence; one screenshot beats a paragraph. R57's "too much text" applies here too.
- UI names exactly as in the build, bold for controls (**Build**), "Menu > Item" for menus, `<kbd>` for keys with the menu glyphs (⌘ ⌥ ⇧ ↩).
- **Claims audit (WS4 section 12):** every statement is checked in the App Store build before launch. No accuracy figures for AI, no "anonymous" (WS4 check 11), "never uploaded" only in the privacy policy's words, nothing Personal-only, no unreleased features.
- AI wording: say what happens on the Mac and when anything goes online (only the optional model download from Hugging Face, on a click). Never imply lyrics are rewritten.
- **"Apple Intelligence"** is pending the P3-9 research ticket (trademark usage). Until it rules, every mention of Apple's model goes through one component, `AppleModelName.astro` (default text: "Apple's on-device model"), so the ruling is a one-line change. The app's own unavailability messages (spec 4.2) are quoted exactly as the build shows them.
- No real song titles or lyrics in text or images; examples use the Welcome songs or text written for Segue (a romanized Hindi example uses "Kitaabon Wali Gali"). Search examples follow the app's tip ("pyar and pyaar").
- Accessibility: every screenshot has meaningful `alt`; clips have a text caption listing the steps; nothing relies on colour alone.

---

## 9. Owned files

Create: `guide/**` (except generated data written by the tools below), `scripts/pages-build.sh`, `scripts/docs-shots.swift`, `scripts/docs-clips.sh`, `.node-version`, `UITests/AppStore/Guide/**`, `UITests/AppStore/GuideShots.xctestplan`, `UITests/AppStore/GuideClips.xctestplan`, `App/Sources/Debug/GuideFixtures.swift`, `Packages/SegueUI/Tests/SegueThemeTests/GuideKeyboardExportTests.swift`, `Packages/SegueUI/Tests/SegueThemeTests/GuideLinksTests.swift`.

Edit: `Makefile` (`guide`, `guide-dev`, `guide-check`, `guide-keys`, `docs-shots`, `docs-clips`; `site-serve` and `site-check` depend on `guide`), `.gitignore`, `.htmlvalidateignore`, `.github/workflows/site.yml`, `.github/dependabot.yml`, `scripts/gen-site.swift` (guide link walking, check scoping, redirects, contract list, changelog prefix, `_headers` check), `scripts/verify-appstore.sh` (new flag strings), `content/site.json` (redirects), `content/changelog.json` (help paths), `content/partials/header.html` and `footer.html`, `website/_headers`, `website/robots.txt`, `App/Sources/LaunchOptions.swift` (`-SegueGuideFixtures`, `-SegueScriptedAI`; plus the WS5 capture flags if question 3 gives them to WS6), `Project.swift` (only if WS6 builds the shared target), `Packages/SegueUI/Sources/SegueUI/App/SegueLinks.swift`, `Tips.swift`, the help-button call sites in section 7.2, `SegueLinksTests.swift`, `WhatsNew` prefix rule and its tests; docs: WS4 sections 2, 3, 8.1, 9.3, 9.7 and R-3 (superseded notes pointing here), release README 2.4 and the spec table, P3-9 step 2 (help bullet moved here).

Delete (to the Trash): `website/help.html`, `website/help/`, `content/partials/help-nav.html`.

---

## 10. Test budget (R113)

- Per step: only the targeted checks for that step (`make guide`, `make guide-check`, the one new SegueUI test file via `swift test --filter`, `make site-check` once the guide builds).
- `make docs-shots` and `make docs-clips` are run as many times as the pixel review needs, but only for the ids being fixed (`ONLY=`); the full set once at the end.
- End of the workstream: ONE `make quick`, ONE `make e2e-one` per UI test class added or changed (none expected beyond the guide capture classes, which run through `docs-shots`, not `e2e`). **No `make gate`** (the orchestrator runs it per wave). No retry loops.

---

## 11. Steps for the build agent

Each step is one signed commit.

1. **Skeleton.** `guide/` with pinned packages and lockfile, `astro.config.mjs` (4.3), `.node-version`, `.gitignore`, `.htmlvalidateignore`, Makefile targets `guide`, `guide-dev`, `guide-check` (static part). One placeholder page. Verify the root URL behaviour (4.3) and the `_headers` `/guide/*` block in `make site-serve`, zero CSP violations in headless Chrome.
2. **Theme.** The chosen direction (question 1): `guide.css` mapping Starlight variables to tokens, fonts from `/assets/fonts/`, overrides (`SiteTitle` with the wordmark and cue dot, `Footer` with the site small print, theme behaviour per question 2), `Shot`, `Clip`, `Steps`, `Keys` components. Pixel-check Getting started and one task page against the chosen render in both schemes, at 1440, 1024 and 375 px.
3. **Site integration.** `gen-site.swift` changes (4.7), redirects (7.3), header/footer nav, `robots.txt`, changelog prefix, the old help pages and partial to the Trash, `scripts/pages-build.sh`, Site workflow job, Dependabot. `make site-check` green.
4. **Capture layer** (only if question 3 assigns it to WS6): WS5 8.2-8.3 flags, target and scheme test action, exactly as specified there, plus `verify-appstore` grep strings.
5. **Fixtures and shots.** `GuideFixtures.swift`, `-SegueGuideFixtures`, `-SegueScriptedAI`, the `GuideShots` classes, `scripts/docs-shots.swift`, `make docs-shots`. Review every shot at 100% in both appearances (WS5 8.8 list: clipping, truncation, stray rings, personal paths, wrong selection colour); fix problems in the app or the fixture, never in post.
6. **Keyboard reference.** `GuideKeyboardExportTests`, `make guide-keys`, `keyboard.json`, `KeyboardTables.astro`.
7. **Pages.** All section 2.2 pages, written from the App Store build, each feature opened as it is documented; the hand-written editor/builder key table verified key by key.
8. **Clips.** `GuideClips`, `make docs-clips`, encoding and budgets.
9. **Deep links.** `SegueLinks.Guide`, `SegueLinks.help`, help buttons and tip actions (7.2), `GuideLinksTests`; `make site-check` proves every link resolves.
10. **Docs.** WS4, README, P3-9 notes (section 9). Then ONE `make quick` and the end-of-workstream report: what was built, shot and clip sizes, anything verified differently from this spec, and the [RYAN] steps.

Two sessions if needed: steps 1-3 and 6 (no app capture) in the first; 4-5 and 7-10 in the second.

---

## 12. [RYAN] manual steps

1. Pick a direction and answer the open questions below.
2. When creating the Pages project (WS4 R-3, release README 2.4), use the build values in section 4.4 instead of "Build command: empty", and add the extra watch paths. If the project already exists by then, change them under Settings > Build.
3. Grant Screen Recording to the terminal app that runs `make docs-clips` (once; shared with WS5's preview).
4. Read the guide in the browser once before launch (it joins the R56-style walkthrough).

---

## 13. Acceptance

- `https://segue.ryandsilva.dev/guide` (locally: `make site-serve`, `localhost:8788/guide`) serves Getting started; every section 2.2 page exists with its H2 ids; `/help` and every `/help/*` 301 to the mapped guide page.
- Starlight search finds a term from every page with no network request beyond the site's origin; no cookies are set (DevTools Application tab empty for cookies); zero CSP violations on every page; only Cloudflare's beacon is third-party, and only in production.
- Dark and light both render to the chosen direction at 1440, 1024 and 375 px; no horizontal scroll at 320 px; keyboard navigation and focus rings work; `alt` on every shot.
- `make docs-shots` on an unchanged app leaves `git status` clean; every shot is Retina, from the App Store flavour, Welcome library only, and within budget; clips within budget and silent.
- `keyboard.json` is generated and the export test fails when it is stale.
- Every `SegueLinks` URL, changelog `help` path and redirect target resolves against the built guide (`make site-check`); every surface in 7.2 opens its page (in-process tests).
- The Site CI job builds the guide and runs its checks on Linux; `make quick` green.
- Nothing in the guide fails the claims audit; no Personal-only feature, real song, "anonymous" or em dash appears.

---

## 14. Risks

- **Pages build image and Node 26.** If Pages cannot install the pinned Node, the guide build fails on deploy (4.4 says stop and ask).
- **Starlight inline output vs the CSP.** Starlight may need an inline theme script or style attributes; 4.5 prefers overrides, then narrow hashes.
- **Capture flakiness on a laptop** (display scaling, an external monitor, notifications). The scale assertion and no-retry plan surface it; run captures with only the built-in Retina display and Do Not Disturb on.
- **Repo growth from binaries.** Bounded by AVIF, write-on-real-change and the budgets; clips change only on purpose.
- **Shared capture layer with WS5.** Two specs touching the same flags and target; question 3 assigns ownership so only one builds it.
- **Starlight upgrades** can change markup the theme overrides rely on; versions are pinned and Dependabot PRs are checked with `make guide` plus a visual pass.

---

## As built (2026-10-19)

What landed, and where it differs from the sections above (this list wins where they disagree):

- **Landed:** the guide site (direction C, system appearance only), all 27 pages written from the App Store build's UI strings, `/help` redirects, Guide nav, the guide CSP, CI job, Dependabot, the generated keyboard reference (menus, editor keys, stage keys), `SegueLinks.Guide` with Help buttons (paste review, batch import, section notes, smart filter editor, Arrange Sections sheet, pre-show checklist, set assistant bar, unknown-time list, song card, Settings > Live / AI / Privacy / Data, Gig Mode section, Keyboard Shortcuts window, empty library link) and Learn More on all six tips, the capture layer and `make docs-shots` / `make docs-clips`, and a first set of 17 captures. The song card's own Help button (trailing end of the token row; off on the paste review's draft card, whose sheet has one) landed at the wave 3 gate.
- **Formats and URLs:** Astro `build.format: 'preserve'` (not `'file'`, which made Starlight write `.html` into every link); the guide home is moved to `website/guide.html` by `guide/scripts/postbuild.mjs`, so `/guide` serves without a redirect; canonical and search-result URLs drop `.html` (Head and Search overrides).
- **Heading ids:** `{#id}` heading attributes through Astro 7's Satteri processor (`headingAttributes: true`); syntax highlighting is off (it writes style attributes).
- **CSP:** both `/guide` and `/guide/*` rules detach the site CSP; `img-src 'self' data:` (Pagefind draws its icons as data: images). Starlight's Search, MobileMenuToggle, Sidebar, Footer, PageTitle, Head, SiteTitle, ThemeProvider and ThemeSelect are overridden so no inline script, inline style or style attribute ships; zero CSP violations measured in headless Chrome.
- **Capture layer:** the appearance reaches the tests as `TEST_RUNNER_SEGUE_SHOT_APPEARANCE` (xcodebuild passes `TEST_RUNNER_*` to the runner), so there are no test plans; `-SegueWindowFrame` is relative to the screen's visible area (a Dock on the left covered the window otherwise); the stage window is titled ("Perform") when windowed, so stage shots include a thin title bar until a crop is added. `-SegueGuideFixtures` is built (see below).
- **Final captures (2026-10-20):** all 34 shots (dark and light; stage shots once) and the three clips are committed; `make guide-check STRICT=1` passes. Fixes made for them: the capture stage is the same borderless window as on stage, at the frame (no "Perform" title bar; tests find it by its live view); the stage status line has an id and stage shots wait for it to fade; card callouts point at the token chips (`segue.songCard.token.*`), paste-review at the original, result and footer, assistant-bar at the request, chips and total; `-SegueGuideFixtures YES` (App/Sources/Debug/GuideFixtures.swift) writes the fixture paste's recorded Apple model answer (segue-eval, apple-fm 26.6.2) and three import files into the container and points `-SegueScriptedAI` and `-SegueImportPanelPaths` at them, so the review shows real AI marks; `-SegueClockRate` makes the captured gig last minutes; the fixed clock is 7:30 PM on 20 November 2026 in California; the screenshot library adds WS5's screenshot-only songs and "JamFest Opener", so tests open setlists by name. The clips are recorded with `scripts/record-app.swift` (Segue's windows only), see WS5 9.2 as built.

## Resolved questions (R127, 2026-10-19)

1. Visual direction: **C "Tiles"**.
2. Theme: **follows the system only**, no toggle; screenshots switch with `<picture>`.
3. Shared capture layer: **WS6 builds it**, exactly as WS5 8.2-8.3 specify.
4. Storage: **committed AVIF shots and MP4 clips** with the section 5.6 and 6 budgets.
5. Clips: **click to play**, muted, looping, with a poster; no JavaScript.
6. Callouts: **numbered coral dots** placed from the element frames recorded at capture.
7. JavaScript: **Starlight's own bundled scripts under `/guide/*` only** (search works), with the 4.5 CSP.
8. Order: the site, theme, IA, all page copy, redirects, deep links, CI and the `docs-shots`/`docs-clips` tooling land now; the final screenshots and clips are generated after Ryan's R56 walkthrough fix round (placeholders or current captures until then).
