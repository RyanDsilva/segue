# Phase 9 research - Personal-build import prior art (2026-10-31)

Follow-up to `docs/research/phase9-import-bakeoff.md`, for P9-4 (`docs/phases/9-workstreams/P9-4-lyrics-and-url-import.md`). It answers the owner's two questions for the **Personal build only** (`SeguePersonalModules`, never in the App Store build; licence no object):

1. What open-source prior art exists for getting Ultimate Guitar (UG) data, which route each project uses, and what is worth borrowing.
2. How open-source tools get past Cloudflare's "Just a moment..." page, and what a native macOS app can do on its own, for free, for loads the owner starts himself (E-Chords first).

**Method.** GitHub repo search (13 queries) and code search (about 30 queries on markers such as `X-UG-API-KEY`, `UGT_ANDROID`, `wiki_tab`, `js-store`, per-language `tabs.ultimate-guitar.com`), plus the Raycast extensions monorepo and Obsidian's `community-plugins.json`. 80 UG repos and 7 anti-bot tools were shallow-cloned into the session scratchpad and **read at source**. Each was classified by grepping for route markers and then reading the files cited below. Stars, licence and last commit come from `gh api` and `git log -1` on 2026-10-31. Nothing was run against UG, E-Chords or any Cloudflare site. The optional warm-store WKWebView re-run was **not** done: the bake-off moved its WebKit store to the Trash, so any "re-run" would have been a cold load, which proves nothing new (section 2.6).

**Typed findings.** Every row has a **kind** from the closed set below, plus `repo:path:line` citations into the cloned sources.

| Kind | Meaning |
|---|---|
| `route-web` | Fetches UG's web pages (`search.php`, `/tab/...`) and reads the `js-store` JSON |
| `route-mobile` | Calls the signed Android API `api.ultimate-guitar.com/api/v1/...` |
| `route-browser` | Drives a real browser (Selenium, Puppeteer, Playwright, nodriver, a WebView) |
| `route-user` | Runs in or after the user's own browser: an extension, a bookmarklet, a pasted page source, a saved page file |
| `route-bypass` | Gets around Cloudflare at the network level (TLS impersonation, a proxy, pinning the origin IP) |
| `parser` | Converts UG's `[ch]`/`[tab]` markup or UG plain text, with no fetching of its own |
| `adjacent` | A launcher or notes plugin (Raycast, Alfred, Obsidian) |
| `dead` | Targets a UG page shape that no longer exists |

**Verdicts** use the owner's four outcomes: **adopt / fork or vendor / build informed by it / build from scratch**. Nothing on this list is a Swift package Segue could depend on (SwiftSoup was already adopted by the bake-off), so **no row is "adopt"**. **Works?** is judged from the code and the issue tracker, not from a live run: **V-src** means the source matches the page shape the bake-off verified on 2026-11-01, and **U** means not checked.

## Answers in one screen

1. **UG prior art.** 52 of the 80 read projects touch UG's **web pages** (`search.php` and/or the `js-store` JSON, the route the bake-off picked), some of them through a browser. 14 use the **signed mobile API**, Tabs-Lite (173 stars) being the main shipping app. About 12 drive a real browser (Selenium, Puppeteer, Playwright or a WebView). Counts come from grepping route markers, so one repo can count in two routes. The project closest to Segue's plan is `hampterworks/klank` (Tauri, 3 stars): an import cascade of mobile API, then the website, then a **hidden WebView that is shown only when an interactive challenge appears** (section 1.2). Swift prior art exists (`nlevin/fretz`, `ewiner/tabr`, `szylica/ChordScroller`, `fwcd/d2`, `dan-slater/mactabs`), but none is a better base than building our own readers, informed by them. Section 1.4 lists eleven techniques worth borrowing.
2. **The "Just a moment..." page.** A real WebKit view with a **persistent** cookie store clears Cloudflare's non-interactive and most managed challenges without any help. The bake-off showed this, and every free tool works on the same principle: be a real, unautomated browser and keep the `cf_clearance` cookie. **No free tool solves an interactive Turnstile checkbox.** Each "free solver" read here does one thing: it finds the widget and sends a trusted mouse click (or Tab+Space) at its checkbox. A native app *could* fake that with synthesised `NSEvent`s, but that is the app solving the check, which the spec forbids. It is also brittle. **The feasible free path:**
   - a persistent `WKWebsiteDataStore(forIdentifier:)`;
   - not throttling the view (`WKPreferences.inactiveSchedulingPolicy = .none`, macOS 14+, checked in the SDK);
   - a navigation policy that lets the challenge's own frames load;
   - at most one wait, then stop;
   - showing the same view to the owner for an interactive check (klank's pattern; this is the bake-off's open question 5).

   Apple's **Private Access Tokens** are a free, on-device signal that Cloudflare's managed challenge accepts. Whether they reach a third-party app's WKWebView on macOS is **U**, and worth a ten-minute spike.

## 1. Ultimate Guitar prior art

### 1.1 The three routes, as the sources show them

| Route | How it works (V-src) | Fields it gets | State in 2026 |
|---|---|---|---|
| Web `search.php` + tab page | GET `www.ultimate-guitar.com/search.php?search_type=title&value=<q>[&type=300][&page=N]` and `tabs.ultimate-guitar.com/tab/...`. Then parse `<div class="js-store" data-content="...">` (HTML-escaped JSON) at `store.page.data.results` / `.tab` / `.tab_view` | results: id, type, version, rating, votes, tab_url, marketing rows mixed in. Tab: `wiki_tab.content`, `meta.capo`, `meta.tonality`, `meta.tuning`, `versions[]`, `applicature`, `strummings[].bpm` | Works from a residential IP (bake-off V). From datacenter IPs and non-browser TLS stacks it gets 403s that come and go: freetar #43 (2024) and #90 (2026-07, "TLS Signature detection by cloudflare") |
| Signed mobile API | `api.ultimate-guitar.com/api/v1/{tab/search, tab/info, tab/suggestion, tab/url, tab/explore, common/hello}` with `User-Agent: UGT_ANDROID/<ver> (...)`, `X-UG-CLIENT-ID: <16 hex>` and `X-UG-API-KEY: md5(deviceId + "YYYY-MM-DD:" + UTC hour + "createLog()")` | Flat JSON: content, capo (int), tonality_name, tuning, versions[], recording.recording_artists, applicature, urlWeb | Works for a shipping app (Tabs-Lite v4.1.0, 2026-01-25, no auth issues open). A 498 status means the key scheme changed |
| Real browser | Selenium, Puppeteer (stealth or "real-browser"), Playwright, nodriver, FlareSolverr, or a WebView. Reads `window.UGAPP.store` (after hydration) or `.js-store` | Same as the web route | Works but is heavy; UG's own `UGAPP` on the mobile web lacks versions and votes (`mikemikk/UltimateTab src/lib/core/tab.ts:202`) |

**A key-format trap in the mobile route** (V-src, found by comparing implementations):
- **No leading zero on the hour:** Tabs-Lite `BackendConnection.kt:634` (`"yyyy-MM-dd:H"`), equin `ug-client.ts:18` ("UTC hour int, no leading 0", "verified empirically"), Pilfer `api.go:79` (`%d`), penultimate `ug-api.ts:15`, cavic19 `api.ts:48`, akash-kamat `crypto.js:29`, Band-hq `_ug-client.js:15`, LiveNLoud `scraping_service_ultimate_guitar.py:98`, ericbrison `cors-proxy.mjs:11` and TicoRicoRay `ug_fetch.py:57` all format the hour this way.
- **Zero-padded hour:** klank `ug_mobile_api.rs:21` uses `%H`, and its test expects `...:07createLog()`. If the server checks the exact string, klank's mobile stage would fail between 00:00 and 09:59 UTC (U).
- **Tabs-Lite's guard against clock skew:** it takes the hour from the server's `/common/hello` timestamp, not the local clock (`BackendConnection.kt:656-690`), and re-signs once on a 498 (`:559-587`).

### 1.2 Closest to Segue: `hampterworks/klank` (V-src, 3 stars, Tauri/Rust, no licence file, last commit 2026-09-23)

An ordered cascade of import stages, each returning `Success / Skip / RetryNext(err) / Fatal` (`crates/core/src/import/mod.rs:39-62,107-118`, `src/import/mod.rs:36`):

1. `UgMobileApi`: `tab/info` with a device ID kept on disk (`ug_mobile_api.rs:17-20,65-74,156-170`).
2. `UgWebsite`: a plain GET with a Chrome UA. HTTP 403, 429 or 503, or no `js-store`, means `Challenged` and moves to the next stage (`ug_website.rs:60-75`). The `js-store` extraction is a string scan that needs no DOM, because the inner quotes are entity-escaped (`:86-99`).
3. `UgWebview`, the last resort: a `WebviewWindow` built **hidden** (`.visible(false).focused(false).skip_taskbar(true)`, `ug_webview.rs:266-273`; on macOS, Tauri's WRY engine is a WKWebView), plus one injected script that:
   - reads `window.UGAPP.store` first, then `.js-store`, and re-wraps the result as `{store: ...}` so a single parser fits both (`:65-73`);
   - watches with a MutationObserver plus a 150 ms poll (`:92-104`);
   - treats a page as challenged when the title contains "just a moment", "attention required" or "verifying", or the DOM has `#challenge-form`, `#challenge-running`, a `challenges.cloudflare.com` iframe or `.cf-turnstile`, **checked only after 4 s** so the automatic pass gets its chance (`:81-97`);
   - on a challenge, **reveals the hidden window** so the user can complete it (`report_ug_challenge`, `:218-229`);
   - auto-clicks cookie-consent buttons, including inside CMP iframes (`:42-62`). Segue should *not* copy this: an ad and tracker block list (bake-off question 15) removes the consent banner instead;
   - gives up after 40 s (`:291-306`).

Verdict: **build informed by it.** It is the same architecture R179 chose, with the "show it to the user" step the spec currently forbids (open question 1).

### 1.3 Typed inventory (read at source)

Route, works?, parsing (markup, capo, key, versions) and technique. Stars, licence and last commit as of 2026-10-31.

**Web route (`route-web`)**

| Repo | Stars / lic / last | Works? | Parsing | Technique worth noting | Verdict |
|---|---|---|---|---|---|
| `kmille/freetar` (Python, Flask) | 788 / GPL-3.0 / 2026-09-25 | V-src. Maintainer: "working again" 2026-09-25 (#90) | Regex `[ch]root quality /bass[/ch]` into spans; `[tab]` stripped; capo and tuning from `tab_view.meta`; `versions` with Official dropped (`freetar/ug.py:58-88`) | Defaults to its own proxy `proxy.freetar.de` unless `FREETAR_LOCAL=1` (`ug.py:114-121,198-203`); the history shows Tor tried and dropped against IP blocks (#43). Search drops `Pro` and `Official` (`:131-137`) | build informed by it |
| `zachpmanson/penultimate-guitar` (TS, Next) | 11 / MIT / 2026-09-01 | V-src | Tab page via `js-store` with `meta.capo` and `versions` (`src/server/ug-interface/ug-interface.ts:28-65`) | **Uses both routes**: web for search and tab pages (`:93-103`, Firefox UA), mobile API for "assign track" and id lookups (`ug-api.ts:218-250`, `src/server/routers/tab.ts:87,251`); caches tabs in its own DB | build informed by it |
| `ewiner/tabr` (Swift, macOS app) | 0 / MIT / 2026-10-26 | V-src | `js-store` via `JSONSerialization`; capo from `meta.capo` then `tab.capo` (`Sources/Tabr/TabSearchService.swift:308-355`) | Native `URLSession` + Chrome UA (`:171-175`). **Bayesian version rank, prior k=50, mean 3.5** (`:160-165`), the same shape as spec 6.10; title and artist word-overlap score (`:140-158`) | build informed by it |
| `fwcd/d2` (Swift, Discord bot) | 17 / GPL-3.0 / 2025-02-25 | V-src | SwiftSoup `getElementsByClass("js-store")` (`Sources/D2NetAPIs/UltimateGuitar/Query/UltimateGuitarQuery.swift:18`); a Codable `wiki_tab` model; tests on `[tab][ch]` lines (`Tests/.../UltimateGuitarTabParserTests.swift:55`) | The same SwiftSoup-plus-JSON pattern the bake-off chose, in Swift | build informed by it |
| `dan-slater/mactabs` (Swift app + Python tool) | 0 / MIT / 2026-10-17 | V-src | `tools/tab-import.py:54-57` regex for `js-store`; capo from `meta.capo`, else `tab.capo` (`:166`); refuses a missing `wiki_tab` as "paywalled or official" (`:161-163`) | Search keeps only `tab_url` on `tabs.ultimate-guitar.com/` (`:137-142`), the same marketing-row filter the bake-off found | build informed by it |
| `nlevin/fretz` (Swift, iOS) | 1 / none / 2026-07-27 | V-src | `App/Import/WebSongImporter.swift` `parseUltimateGuitar`: `[ch]X[/ch]` becomes `[X]` inline (it loses the column alignment of chord-over-lyric lines), section headers become `{start_of_verse: ...}`, capo and tempo from `strummings[0].bpm` | **A generic chord-sheet finder for any page**: it scores every `<pre>/<textarea>/<code>` and any `chordline`/`lyric-line` class block by chord count (at least 3) and line count (at least 4), +100 when the attributes say ChordPro (`parseEmbeddedChordSheet`). A strong design for spec 8.3's `GenericPageReader`. Strict Codable on UG (fragile, which spec 8.4 already avoids) | build informed by it |
| `bjesus/chords` (Rust, GNOME) | 2 / GPL-3.0 / 2026-07-13 | V-src | `src/data/api.rs:45-237` `js-store` and `meta.capo` | `route-bypass`: **pins both UG hostnames to an IP hidden by XOR** (`src/data/net.rs:1-37`), going past Cloudflare to what looks like the origin. Do not copy: it gets around protection and breaks silently | build from scratch (nothing to take) |
| `MaxJW/justchords` (TS) | 0 / MIT / 2026-08-20 | V-src | key = `tab.tonality_name`, else `meta.tonality`; capo from `meta` (`server/src/ug/scraper.ts:70-82`) | Clear error text for a layout change (`:38`) | build informed by it |
| `crmne/omarchy-ultimate-guitar` (Python + QML) | 5 / MIT / 2026-10-28 | V-src | `js-store` regex (`bin/ug-tabs:35`); `versions` capped and shaped (`:312-328`) | **A redirect guard**: only `*.ultimate-guitar.com` URLs pass, and redirects are re-checked (`:66-91`), which matches spec 8.1's host rule | build informed by it |
| `Simnol22/bibi-tabs` (Python) | 0 / none / 2026-08-02 | V-src | One file holds everything site-specific; `[/?(ch|tab)]` stripped (`bibi/ultimate_guitar.py:1-30`) | States the alignment rule: the markers "are laid over already-aligned text, so removing them leaves the columns intact" (`:8-9`) | build informed by it |
| `ParalelSt/ember` (TS + Tauri) | 0 / custom / 2026-10-31 | V-src | Tab types 200 and 400 only; public access only; Pro and Official are link-outs (`apps/web/lib/tabFetch/ug.ts:1-19`) | **A polite fetcher**: one queue per site, a 2 s gap, and **a one-hour back-off after 403, 429 or 503** with nothing sent meanwhile (`apps/web/lib/tabFetch/polite.ts:1-20`); clock and fetch injected for tests | build informed by it |
| `igrek51/android-songbook` `scripts/ug2songbook.py` | 40 / GPL-3.0 / 2026-07-08 | V-src | `js-store` regex, then **`html.unescape` twice** ("double-encoded entities are common on UG", `:50-52`) | `cloudscraper` with a Chrome profile (`:27-30`), so also `route-bypass` | build informed by it |
| `atomantic/PortOS` `server/services/brainSongbookImport.js` | 74 / MIT / 2026-10-31 | V-src | A cascade of extractors: UG `js-store` first, falling through if the shape drifts (`:10,47-60`) | An honest bot UA `PortOS-SongBook/1.0` (`:166`) | build informed by it |
| `libf-de/KordBook` (Kotlin MP) | 0 / none / 2024-07-19 | V-src | `UltimateGuitarFetcher.kt:236,298` (web) **and** `UltimateGuitarApiFetcher.kt:68,223,253,312` (mobile) | Two interchangeable fetchers behind one source interface | build informed by it |
| `jethrokuan/ugapi`, `jethrokuan/jita` (Python) | 2, 2 / none / 2021 | V-src (shape) | `meta.tonality` and `meta.capo` (`ugapi/server.py:110-120`) | - | build informed by it |
| `moizuwu/music_display` (Rust) | 0 / none / 2026-10-31 | V-src | `src/ug.rs:73-75` string scan | A **diagnostic CLI** that names which step failed ("no js-store ... blocked, captcha, or format changed", `:417-445`); model for the parser canary | build informed by it |
| `ChurchApps/FreeShow` (Electron) | 1360 / GPL-3.0 / 2026-10-30 | V-src | `src/electron/utils/LyricSearch.ts:186` | A second search URL form, `search.php?title=<t>&type=300` (`:209`) | build informed by it |
| `ChurchApps/Chordo` (Svelte) | 9 / GPL-3.0 / 2026-10-30 | V-src | `src/lib/utils/webPuller.ts:169` index scan | - | build informed by it |
| `perivar/chordmaster` (RN) | 0 / none / 2024-12-23 | U | `packages/utils/src/utils/scrapeUtils.ts:123`; `CustomUltimateGuitarFormatter.ts` cites UG's own formatting rubric (`:95`) | - | build informed by it |
| `Terpsichord/project-canens` (Rust) | 1 / Apache-2.0 / 2026-10-25 | V-src | `frontend/src/tabs/scraper.rs:27,72-83` with a context error per step | - | build from scratch |
| `Dook97/ugfzf` (C#) | 1 / GPL-3.0 / 2023-07-13 | V-src | `UGScraper/PageScraper.cs:57-58` path lookup `tab_view.meta.tuning.value` | - | build from scratch |
| `TomGUN02/UltimateGuitar-Scraper` (C#) | 2 / MIT / 2023-08-25 | V-src | `MainWindow.xaml.cs:79,248-253` | - | build from scratch |
| `RyannKim327/UltimateGuitar-Project` (TS) | 14 / none / 2026-05-23 | V-src | `src/actions/fetch_chords.ts:52-56` | - | build from scratch |
| `dd-dreams/BUGS` (Python) | 5 / MIT / 2023-12-06 | V-src | `src/scraper.py:68-78` | An unsigned web **suggestions** endpoint `/static/article/suggestions/{0}/{1}.js` (`src/constants/other.py:4`, U alive) | build informed by it |
| `fridasor/tabscraper` (Python) | 5 / MIT / 2026-08-20 | V-src | Regex for capo on the *still-escaped* string (`tabber.py:183-184`), which is fragile | - | build from scratch |
| `benjamenalford/UGPrint`, `hubanton/Ultimate-Guitar-to-PDF`, `ltpitt/ultimateguitar-tab-to-pdf` (Python) | 2-10 / mixed | V-src | Strip all four markers (`UGPrint.py:13-18`) | - | build from scratch |
| `Gojobriel/ultimate-guitar-scraper` (Python) | 2 / custom / 2026-02-08 | V-src | `js-store`, else the `window.UGAPP.store.page` inline script (`ug_api/ug_scraper.py:98,187`) | Detects Cloudflare, then **falls back to Playwright** (`:74-80`) | build informed by it |
| `edgarberlinck/songbook` (Rust, Tauri) | 0 / MIT / 2026-07-27 | V-src | Writes `{capo: N}` ChordPro (`src-tauri/core/src/application/song_service.rs:149-150`) | Detects the Cloudflare page and **gives up with a clear message** (`src-tauri/core/src/infrastructure/ultimate_guitar_importer.rs:36-39`), as spec 8.7 does | build informed by it |
| `Rtnkr/chords-pro-convertor` (Vercel fn) | 0 / none / 2026-08-09 | V-src | `api/ug-tab.js:55-77`, host allow-list (`:37-41`) | - | build from scratch |
| `peeveen/ugfetcher` (Kotlin) | 0 / none / 2025-02-28 | V-src | Two outputs, ChordPro `{capo:N}` and "CAPO N" text (`src/main/kotlin/Song.kt:62-117`) | - | build from scratch |
| `madriesen/ulitimate-guitar-tab-converter` (TS) | 0 / none / 2025-01-25 | U | `js-store` to an output format | - | build from scratch |
| `tablatures/tablatures-api` (Python) | 3 / none / 2026-03-26 | U | `search.php` + `js-store` | - | build from scratch |
| `xilefmusics/worshipviewer` (Rust/WASM + TS) | 3 / AGPL-3.0 / 2026-10-23 | V-src | `frontend/crates/chordlib-wasm/src/lib.rs:433` parses `js-store` from **pasted page source** | Also `route-user`: guided "View Source (Option-Cmd-U), Cmd-A, Cmd-C, paste" (`frontend/app/src/components/songs/UltimateGuitarImportSheet.tsx:323-351`); the model for spec 8.7's "Paste the Page Instead" | build informed by it |
| `iliagerman/smart-guitar` (Python) | 0 / none / 2026-10-30 | V-src | `backend/src/guitar_player/services/ug_chord_fetcher.py:36` | `route-bypass`: **`curl_cffi` with `impersonate="chrome"`** "to bypass Cloudflare" (`:3,17,226,263`) | build from scratch (do not copy) |

**Mobile API (`route-mobile`)**

| Repo | Stars / lic / last | Works? | Parsing | Technique | Verdict |
|---|---|---|---|---|---|
| `More-Than-Solitaire/Tabs-Lite` (Kotlin, Android, Play Store app) | 173 / Apache-2.0 / 2026-04-17 | V-src, a shipping app | `[ch]`/`[tab]` rendered in its own views; capo and tonality from `tab/info` | `tab/search?title=&page=&type[]=300&official[]=0` (`BackendConnection.kt:246`), `tab/suggestion` (`:201`). **Key hour from the server (`/common/hello`)** and one re-sign on 498 (`:559-690`). User-made tabs live in its own Firestore (`:83-190`) | build informed by it |
| `sayandey021/Chord-Studio` | 1 / Apache-2.0 / 2026-10-29 | V-src | Same as Tabs-Lite | A Tabs-Lite fork with a desktop (Compose) target (`desktopApp/.../BackendConnection.kt`) | build informed by it |
| `Pilfer/ultimate-guitar-scraper` (Go) | 133 / none / 2023-11-27 | U (2023) | `cmd/fetch-tab-by-id.go:46-48` strips markers | **Reverse-engineering notes** with about 40 endpoints (`pkg/ultimateguitar/paths.go:80-112`, `reversing-notes/*.md`); typed `tab/info` with `versions`, `recording`, `applicature` (`types.go:160-234`) | build informed by it |
| `Conchylicultor/equin` (TS) | 13 / Apache-2.0 / 2026-10-31 | V-src | zod schemas that tolerate missing fields (`ug-client.ts:28-60`) | "FRAGILE BY DESIGN ... no fallback", 498 treated as a canary (`plugins/apps/plugins/sonata/plugins/sources/plugins/ultimate-guitar/server/internal/ug-client.ts:9-21`; `CLAUDE.md:165-179`) | build informed by it |
| `hampterworks/klank` | see 1.2 | V-src | `ug_mobile_api.rs:130-150` | Zero-padded hour (the trap in 1.1) | build informed by it |
| `akash-kamat/ultimate-guitar-scrapper-js`, `cavic19/ultimate-guitar-scraper-ts`, `8bury/musicsheetgrep` | 0-1 / none / 2025-2026 | U | Ports of Pilfer | - | build from scratch |
| `nickprocenko/Band-hq`, `ericbrison/songchords` (Netlify CORS proxy), `TicoRicoRay/NewSong` (also logs in, `ug_fetch.py:111`) | 0 / none / 2026 | U | `TicoRicoRay` `format_to_chordpro` (`ug_fetch.py:196`) | - | build from scratch |
| `eloygomes/new-LiveNLoud.app` (Python) | 0 / none / 2026-10-19 | V-src | **The best `[ch]` converter read** (`Server/sustenido/python/scraping_service_ultimate_guitar.py`): joins split slash chords (`[ch]D[/ch]/[ch]F#[/ch]` and `[ch]D[/ch]/F#`, `:32-39,212-224`), pulls a trailing quality like `[ch]A[/ch](add9)` into the chord (`:40-43`), keeps chord-only rows' spacing exactly, and places inline `[ch]` on lyric lines by offset (`:242-301`); handles `[verse]...[/verse]` section tags and `[b] [i] [u] [c]` control tags (`:31,44-52`) | **A chord-integrity check**: the converted chord token sequence must equal the source's `[ch]` sequence, or it refuses (`:304-341`). Also `route-browser`: Selenium **visits the home page first** (cookie warm-up) and then the tab (`:471-500`); mobile `tab/url?url=` resolves a URL to an id (`:508-512`) | build informed by it |
| `zachpmanson/penultimate-guitar` | see web table | | | | |

**Real browser (`route-browser`)**

| Repo | Stars / lic / last | Works? | Notes | Verdict |
|---|---|---|---|---|
| `mikemikk/UltimateTab` (TS) and `Cesc1986/SongHub`, `cs898/UltimateTab-sonrise-edition` (near-identical `src/lib/core/tab.ts`, so forks or copies) | 13, 12, 0 / MIT / 2025-2026 | U | `puppeteer-real-browser` + `rebrowser-puppeteer-core` (`src/lib/api/request.ts:11-12`); reads `window.UGAPP.store.page.data` after waiting out the "Cloudflare bot detection page" (`src/lib/core/tab.ts:34-40`); notes that the mobile view's `UGAPP` lacks versions and votes (`:202`) | build informed by it |
| `szylica/ChordScroller` (Swift, iOS) | 0 / none / 2026-06-15 | V-src | **A visible WKWebView** with an iPhone Safari UA (`MusicReader/SongImporterView.swift:23-30`); reads `.js-store`, else `window.UGAPP.store`, else an inline-script regex (`:167-188`); retries 5 times at 1.5 s (`:193-208`) | build informed by it |
| `georgexu99/sheet-music-browsarr` (Rust) | 1 / none / 2026-07-07 | V-src | Direct first, then FlareSolverr; **re-wraps `UGAPP.store` as `{store: ...}`** because FlareSolverr returns the hydrated DOM (`src/sources/ultimate_guitar.rs:20-25`); **re-uses the cleared `cf_clearance` with the solver's exact UA** in plain requests (`:243-296`); treats UG as a "deferred" source so a 5-45 s solve never blocks first paint | build informed by it |
| `jabbey1/UGDownloader` | 166 / none / 2024-12-23 | U | Selenium + seleniumbase GUI downloader | build from scratch |
| `seanfhear/tab-scraper` | 101 / none / 2022-01-17 | U | Selenium Firefox (`src/utils.py:7-14`) | build from scratch |
| `RiggiG/ug-archive` | 7 / GPL-3.0 / 2025-08-29 | U | Selenium on UG's **mobile site** with a mobile UA (`main.py:3,303`) | build from scratch |
| `danield2255/UltimateGuitarChordParser` | 13 / none / 2026-03-24 | U | seleniumbase `SB` (`chordParser.py:9`); derives key and capo from chords (`:11`) | build from scratch |
| `chordmark/ultimate-guitar-api` | 1 / none / 2024-06-01 | U | `puppeteer-extra` Stealth + Adblocker; types into the home page's search form (`index.ts:3-13,46-54`) | build from scratch |
| `Riffjordan12/Tab-scraper-cli` | 1 / none / 2026-05-27 | dead-ish | Puppeteer; regex `window.UGAPP.store.page = {...}` (`MultiTabDownloader/index.js:119`), the old inline-script shape | build from scratch |
| `verbiiz/GuitarTabsParser` | 14 / MIT / 2018-10-10 | `dead` | Puppeteer, `window.UGAPP.store.page` assignment (`node/ugs/utils.js:109`) | build from scratch |

**User-side (`route-user`)**

| Repo | Stars / lic / last | Notes | Verdict |
|---|---|---|---|
| `codekoch/UltimateGuitar2Bandhelper` (one HTML page) | 5 / none / 2026-07-04 | Three inputs: a bookmarklet run on the UG page, a **saved-page drop** (reads `js-store`), or pasted page text. **Finds the chart by a deep search for any key `content` that holds `[ch]`, `[tab]` or a section header**, not by path; metadata the same way (`index.html:465-497`). README: **"UG switches songs partly without a real page change"**, so the `js-store` attribute can be stale after in-app navigation (`README.md:25-37`) | build informed by it |
| `vvatelot/livestage` | 0 / none / 2026-06-16 | A bookmarklet: `window.UGAPP.store`, then four `js-store` selectors, then an inline-script regex (`apps/web/public/ug-import-bookmarklet.js:77-130`); server import needs "a proxy that bypasses Cloudflare" (`apps/web/.env.example:9`) | build informed by it |
| `heavy-matill/UltimateGuitar2ChordPro` | 0 / none / 2026-08-06 | A Chrome content script on `*://*.ultimate-guitar.com/tab/*` with ChordSheetJS (`manifest.json:18`) | build from scratch |
| `hedwiggggg/ugrip` (web app) | 81 / MIT / 2020-07-31 | Paste a URL; parses `js-store`; **re-spaces glued chords**: `[/ch][ch]` becomes `[/ch] [ch]`, and `[/ch]` followed by a word gets a space (`src/App.js:169-171`) | build informed by it |
| `maikudou/ug` (extension) | 0 / MIT / 2022-08-24 | Grabs Guitar Pro downloads through the logged-in user's cookies (`src/chrome/bg.ts:60-77`). Out of scope (no GP import) | build from scratch |
| `soupy-boy/tabs-lite-ug-import`, `brege/tabslx` | 4, 0 | Move favourites between UG and Tabs-Lite exports | build from scratch |

**Parsers and converters (`parser`)**

| Repo | Stars / lic / last | Notes | Verdict |
|---|---|---|---|
| `martijnversluis/ChordSheetJS` | 445 / GPL-2.0 / 2026-10-30 | `UltimateGuitarParser` for UG's plain-text copy format: `[Verse]`, `[Chorus]`, `[Intro]` and similar become ChordPro sections; `x2` repeat suffix; `Key: Capo:` metadata lines; a chord-line regex that also accepts Do/Re/Mi names (`src/parser/ultimate_guitar_parser.ts:20-30`); `buildVisualColumnMap` for wide characters (`src/parser/parser_helpers.ts:19-32`) | build informed by it |
| `nmevenkamp/ultimateguitar2chordpro`, `alexj136/ug2chordpro`, `DocFaust/chordpro-converter`, `nastroj/kytario-chord-converter`, `bkeepers/chord-editor` (archived) | 0-8 / mixed | Two-line chord-over-lyric to ChordPro from copied text; nothing beyond Segue's existing paste converter | build from scratch |
| `ultimate-guitar/Tabdown` (UG's own) | 89 / BSD-3 / 2017-02-21 | UG's 2017 markup proposal (`[Am]` inline, `[chord]: fingering`). It is **not** the `[ch]`/`[tab]` format the site serves | build from scratch |

**Launchers and notes plugins (`adjacent`)**

| Item | Finding | Verdict |
|---|---|---|
| Raycast `extensions/chords-and-tabs` (MIT, author BossElijah) | Searches Guitaretab and Songsterr only; **no UG** (`package.json` commands) | build from scratch |
| `simeg/alfred-workflow-ultimate-guitar` | 3 / 2017; a binary `.alfredworkflow` that opens UG search in a browser | build from scratch |
| `Tide-Trends/tabs-and-chords` (Swift menu bar app) | Opens `search.php?...value=` in the browser (`Sources/TabsAndChords/Preferences.swift:13`); link-out only | build from scratch |
| Obsidian community plugins | 19 music-related plugins listed (for example `chord-sheets`, `leadsheet`, `stage-binder`, `repertoire`, `chopro-viewer`). None describes importing from UG (descriptions only; sources not read, **U**) | build from scratch |

**`dead`**: `joncardasis/ultimate-api` (122 stars, 2017) parses the pre-2018 server-rendered tab header HTML (`server/parser.py:27-55`); `trdarr/ugproxy` (2018) reads `data['data']['tab_view']` without `store.page` (`ugproxy/ultimateguitar.py:41`); `alewin/CliChords` (archived 2019); `ltworf/ultimateultimateguitar` (archived 2024). Verdict for all: build from scratch.

### 1.4 Techniques to borrow (each traced to source above)

1. **Read `UGAPP.store` first, then `js-store`, re-wrapped as `{store: ...}`** in the WebKit path (klank `ug_webview.rs:65-73`, browsarr `ultimate_guitar.rs:20-25`). The bake-off found the `js-store` div gone after hydration; this one-line wrapper lets `TabJSONParser` stay single-shape. Keep the in-page `fetch(location.href)` from the bake-off as the second option.
2. **Search the JSON for the chart by content, not path**, as a fallback when `tab_view.wiki_tab.content` is missing: the first string under a key `content` that holds `[ch]` or `[tab]` (codekoch `index.html:473-477`). It survives a path move without a code change. Flag it in the parse result so the canary sees the drift.
3. **A chord-integrity check** after conversion: the sequence of chord tokens in the output must equal the `[ch]` tokens in the source, or the import is refused as `.noChart` (LiveNLoud `:304-341`). This fits spec 8.5's "zero silent wrong charts" target cheaply.
4. **Rejoin split slash chords and trailing qualities** before stripping tags: `[ch]D[/ch]/[ch]F#[/ch]` and `[ch]D[/ch]/F#` become `D/F#`; `[ch]A[/ch](add9)` becomes `A(add9)` (LiveNLoud `:32-43,212-230`). Also expect `[verse]...[/verse]` section tags and `[b] [i] [u]` alongside `[Verse 1]` headers (U how common).
5. **Re-space glued chords** (`[/ch][ch]` gets a space; `[/ch]` followed by a word gets a space; hedwiggggg `App.js:169-171`). Only do this on chord-only lines, so lyric columns never move.
6. **Decode entities in two places**: the attribute (SwiftSoup does it), then the chart text, which can still hold entities (android-songbook `ug2songbook.py:50-52`). Decode the content field only, never the whole JSON twice, so literal "&amp;" text survives.
7. **Bayesian rating with k=50** (tabr `:160-165`) confirms spec 6.10's prior. The bake-off proposed k=25 toward 4.0; keep it a table-tested constant (open question 4).
8. **The mobile route, if it is ever built** (a research ticket only): hour without a leading zero, the server's hour from `/common/hello`, one re-sign on 498, the device ID kept, and 498 surfaced as a canary (Tabs-Lite, equin). The `tab/url?url=` endpoint maps a pasted URL to an id (LiveNLoud `:508-512`).
9. **A one-hour per-site back-off after 403, 429 or 503**, with nothing sent meanwhile (ember `polite.ts:1-20`). It is stronger than spec 9's per-host gap, and it protects the owner's IP and cookie reputation, which is what keeps the clean case clean.
10. **The cookie warm-up visit**: load the site's home page before a deep page in a cold store (LiveNLoud `:476-482`). It matches the bake-off: the E-Chords home passed cold, the song page was challenged cold.
11. **The generic chord-sheet candidate scorer** for `GenericPageReader` (fretz `parseEmbeddedChordSheet`): `<pre>`, `<textarea>` and `<code>` blocks plus `chordline`/`lyric-line` class blocks, scored by chord count and line count, with a large bonus for ChordPro-marked blocks.

Not to borrow: origin-IP pinning (bjesus), TLS impersonation (`curl_cffi`, `cloudscraper`), shared proxies (freetar), consent auto-clicking (klank), the signed mobile key as the default route (spec question 3 stays at web-first).

### 1.5 E-Chords prior art (side finding, code search `e-chords.com/chords`)

This is thin, and all of it uses plain requests from before E-Chords' Cloudflare block:
- `dickymoore/CampfireSongbookBuilder` (0 stars, MIT, 2026-07-12) uses `soup.find('pre', class_='core')` (`app/fetch_data.py:164-183`);
- `moolordking/ChordScraper` (0 stars, 2023) splits the page at `<pre id="core"` (`bin/scraper.py:52-54`) with a Chrome UA;
- `KellyOgilvie/music-machines` (2023) uses `User-Agent: Mozilla/5.0` (`data_tools/chord_scraper.py:19`);
- `anthedung/guitarios` (2016) is a crawl list only.

None handles the 403 the bake-off saw, the `/api/search` JSON, or `data-chord` spans. Verdict for all: build from scratch. The bake-off's own E-Chords findings remain the reference.

## 2. Clearing "Just a moment..." on E-Chords (user-started loads)

### 2.1 What Cloudflare documents (V, docs read 2026-10-31)

- Challenge pages come in three types: **Non-interactive** ("the visitor must wait until their browser finishes processing the JavaScript"), **Managed** (Cloudflare picks per visitor; most humans pass without acting, but some "may be asked to perform an interaction such as checking a box") and **Interactive** ([challenge pages](https://developers.cloudflare.com/cloudflare-challenges/challenge-types/challenge-pages/)).
- **`cf_clearance`** lasts for the zone's "Challenge Passage" period, unless Cloudflare decides the session is suspicious. It is "securely tied to the specific visitor and device it was issued to, preventing reuse across machines" ([clearance](https://developers.cloudflare.com/cloudflare-challenges/concepts/clearance/)). FlareSolverr's README adds that cookies stop working when the User-Agent differs ("If they don't match you will see the challenge").
- **Turnstile in WebViews is a supported setup**: JavaScript and DOM storage on, cookies and storage **kept across the session** (the iOS example uses the default persistent data store), a **"Consistent User Agent throughout the session"** ("Changing the User Agent during a session causes Turnstile challenges to fail"), and the view must be able to load `challenges.cloudflare.com`, **`about:blank` and `about:srcdoc`**; strict CSP or domain allow-lists break it ([mobile implementation](https://developers.cloudflare.com/turnstile/get-started/mobile-implementation/)).
- **Private Access Tokens** (Apple, macOS 13+): Cloudflare built them into Managed Challenge so that a PAT-capable device skips the interactive step ("will eliminate nearly 100% of CAPTCHAs served to these users", [Cloudflare blog](https://blog.cloudflare.com/eliminating-captchas-on-iphones-and-macs-using-new-standard/)). Apple said in WWDC22 session 10077 that "tokens are available if you use WebKit or URLSession" ([WWDC notes](https://wwdcnotes.com/documentation/wwdc22-10077-replace-captchas-with-private-access-tokens/)). This needs an Apple ID signed in. **Whether a sandboxed third-party Mac app's WKWebView gets them today is U** (no current Apple doc found). P9-4a step a0 (2026-11-01, `research/phase9-import/README.md`): on this Mac no client presented a token to Cloudflare's PAT demo origin, Safari included, so it is still U for app web views; the Safari baseline has to pass first (Automatic Verification).

### 2.2 The open-source tools, read at source

| Tool | Stars / lic / last push | What it does about a non-interactive or managed challenge | What it does about an interactive Turnstile | Fit for a native macOS app | Verdict |
|---|---|---|---|---|---|
| FlareSolverr | 16.1k / MIT / 2026-10-24 | A proxy service running Selenium + undetected-chromedriver; waits while challenge selectors are present (`src/flaresolverr_service.py:46`) | "none of the captcha solvers work"; optional `tabs_till_verify` presses Tab N times and Space, then reads `cf-turnstile-response` (`:294-340`) | A separate Chrome + Python service, x64 binaries, ~hundreds of MB per browser | build informed by it (detection list only) |
| cloudscraper | 6.8k / MIT / 2025-06-10 | Runs Cloudflare's JS in an interpreter (js2py, Node, V8) inside `requests` | Turnstile "Requires external configuration (proxies/API keys)", meaning **paid solver services** (2captcha and others) | Python only; replaces the browser rather than being one; ruled out (paid solvers) | build from scratch (nothing to take) |
| undetected-chromedriver | 12.9k / GPL-3.0 / 2025-07-05 | Patches chromedriver's automation tells | none | Chrome + Python | build from scratch |
| nodriver / zendriver | 4.9k / AGPL-3.0 / 2026-10-26; 1.5k / AGPL-3.0 | CDP without WebDriver; headful Chrome | `Tab.verify_cf()`: **template-matches a screenshot of the checkbox and clicks it** with a CDP mouse event (`nodriver/core/tab.py:1701-1738`) | Chrome + Python | build from scratch |
| puppeteer-real-browser | 1.6k / MIT / 2025-09-03 | Real Chrome + rebrowser patches | `checkTurnstile`: finds a ~300 px wide childless div or the `cf-turnstile-response` parent and **clicks at x+30, mid-height** every tick (`lib/esm/module/turnstile.mjs:1-60`); patches `MouseEvent.screenX/Y` because CDP-injected clicks report `screenX == clientX`, a known bot tell (`pageController.mjs:47-58`) | Node + Chrome | build from scratch |
| Scrapling | 91k / BSD-3 / 2026-10-31 | **Reads the challenge type from the page's `cType: '<type>'`** ("non-interactive", "managed", "interactive") or an embedded Turnstile script (`scrapling/engines/_browsers/_base.py:626-672`); waits up to 10 s for non-interactive (`_stealth.py:154-166`) | Clicks the box at a randomised offset (`_stealth.py:206-209`) | Python + Playwright/Camoufox | build informed by it (`cType` detection only) |
| camoufox | 13k / MPL-2.0 / 2026-10-31 | A Firefox fork that answers fingerprint APIs from C++ with generated device profiles, driven over Juggler | Clicking is left to the caller | A whole bundled browser | build from scratch |
| playwright-stealth (two forks), puppeteer-extra stealth, rebrowser-patches, patchright, Selenium-Driverless (archived), SeleniumBase UC/CDP mode, DrissionPage, CF-Clearance-Scraper, CloudflareBypassForScraping | 0.3k-13k / mostly MIT | JS patches over automation tells, or driving a real browser without automation flags | Same click-the-box approach where any is offered (CloudflareBypassForScraping and CF-Clearance-Scraper use DrissionPage/nodriver clicks, per their READMEs; not read line by line, U) | Chrome-family automation stacks | build from scratch |
| browser-use | 120k / MIT / 2026-10-31 | An LLM agent over a local or cloud Chromium | The README sells "stealth, CAPTCHA solving and residential proxies" as **the paid cloud** ($0.02 per browser-hour); the local library has none | Ruled out (paid for the part that matters, and an LLM in the loop) | build from scratch |
| Hidden or visible WebView apps: klank (1.2), ChordScroller, georgexu99's notes | - | A real engine passes the automatic cases; georgexu99 found **Chrome for Testing under Xvfb fails Turnstile while branded Chrome passes**, and headless fails (`musescore-pdf-worker/Dockerfile:1-35`, `worker.py:39-43`) | klank **shows the window to the user**; nothing clicks for him | Native, which is exactly our case | build informed by it |

What every free tool has in common: the automatic pass comes from **being a real, unautomated browser engine on a residential IP, with persistent cookies and a stable UA**. For the interactive box, **someone or something has to click**. No free tool has a non-click "solver" for Turnstile; the only non-click options are the paid services (ruled out).

### 2.3 Answers

**(a) Does a real WebKit view with persistent cookies clear the non-interactive JS challenge? Largely yes (V for the warm case, U for cold).**
- Bake-off evidence:
  - cold store, home page: passed silently, with `cf_clearance` set in 1.7 s;
  - warm store: 3 of 3 song-page loads passed in about 0.14 s;
  - cold song page, after about 10 loads in 15 min: stayed in the managed-challenge reload loop for 25 s, twice.
- That failing probe ran under three conditions that cut against it:
  - `.prohibited` activation policy, so the app was never frontmost;
  - no window, or a borderless window parked at x=-20000, so `document.visibilityState` was "hidden" (`tools/wkfetch.swift:18-35,111`);
  - the default `inactiveSchedulingPolicy`. The SDK says a view "detached from all windows" is throttled or suspended when idle (`WKPreferences.h:56-70`, macOS 14+, SDK 27.0; it also says views are not idle "when ... loading web pages", so the effect during the challenge's own reloads is U).

  A challenge script that times its proof-of-work or rendering checks can fail in a throttled, hidden view and pass in a visible one. **U, and it is the first spike for P9-4a:** the same cold song page, (1) hidden in a detached view with `.none`, (2) in a real on-screen window kept out of sight, (3) visible.
- Two spec conflicts follow from Cloudflare's WebView rules (V, docs):
  - **Spec 8.6's "navigation limited to the same scheme and host rules as 8.1" must apply to the main frame only.** The challenge loads `challenges.cloudflare.com`, `about:blank` and `about:srcdoc` frames; refusing them guarantees failure.
  - **The bake-off's planned `WKContentRuleList` ad blocker must allow `challenges.cloudflare.com`.**
- Keep WebKit's default UA all session (already the plan) and never send the same `cf_clearance` from `URLSession` with a different UA. Copying the cookie into `URLSession` *with* WebKit's UA (browsarr's replay, `ultimate_guitar.rs:243-296`) might work, since both use Apple's network stack, but it is replay, not browsing (U, not recommended). The bake-off's **in-page `fetch` for the E-Chords JSON API** is the clean form: every request comes from the cleared page itself.

**(b) An interactive Turnstile checkbox: the app cannot pass it without clicking it.**
- From inside the page: the widget sits in a cross-origin `challenges.cloudflare.com` iframe inside a closed shadow root. Injected JavaScript cannot reach it, and any JS click is `isTrusted == false`.
- From the native side: the only lever is synthesising `NSEvent` mouse events into Segue's own view at the box's location, the WebKit equivalent of puppeteer-real-browser's x+30 click. That is feasible, but it is **the app solving the check**: spec 8.6 and R179 forbid it, and the UG terms language the bake-off quoted ("circumvent ... Content protection methods") applies to such sites in spirit. It is also brittle: Cloudflare scores pointer movement, and the tools above already have to patch `screenX`.
- **Ruled out.** The honest options: stop with `.blocked` and offer **Open in Safari** / **Paste the Page Instead** (spec 8.7), or **show the same web view to the owner** (klank's reveal). He ticks the box himself, the clearance lands in the persistent store, and later hidden loads pass. The bake-off already put this to the owner as open question 5. The spec text "never shown for the user to solve" (8.6 / R179) currently forbids it, so it needs his ruling (question 1 below).

**(c) An on-device, free, no-paid-service way from a native macOS app.** Ranked by how feasible each is:

| Option | Feasible / brittle | Notes |
|---|---|---|
| Persistent `WKWebsiteDataStore(forIdentifier:)`, default UA, JS on, challenge frames allowed, one view at a time, paced, a 1-hour back-off after a block | **Feasible, the core** | V for the warm case; it is the bake-off design with the two fixes in (a) |
| Warm-up: if a deep page is challenged in a cold store, load the site's home page once, then retry the page once | Feasible, cheap | Matches the bake-off (home passes cold) and LiveNLoud `:476-482`. It counts as one extra paced request to the host, so it must be written into spec 9's budget |
| Not throttling the view: `inactiveSchedulingPolicy = .none` and/or hosting it in a real window | Feasible; effect U | The first spike. If a window is needed, a small window behind Segue's own (not offscreen, not transparent) is the honest form |
| Reading `cType` from the challenge HTML (Scrapling `_base.py:644-651`) to split "wait" (non-interactive, managed) from "stop now" (interactive) | Feasible | Saves the full wait on a page that can only be passed by a human, and gives analytics a real reason code |
| Private Access Tokens | Feasible if Apple routes them to app WebViews (U) | No code to write; needs a signed-in Apple ID. A spike with Cloudflare's PAT demo page settles it in minutes |
| "Open here": show the view, the owner ticks the box | Feasible, robust | Needs the owner's ruling (question 1) |
| Synthesised clicks on the checkbox | Feasible but **ruled out** | Spec and terms; brittle |
| Bundling Chrome or Firefox automation (nodriver, camoufox, FlareSolverr) | Brittle, heavy, ruled out | Adds 150-300 MB, Python, version pinning (georgexu99 had to pin a branded Chrome build); it still cannot pass the interactive box without clicking |
| TLS impersonation, origin-IP pinning, paid solvers, residential proxies | **Ruled out** | Not free and local, or a direct circumvention |

### 2.4 Detecting state (merged rule for `WebKitPageLoader`)

Challenged when any of these hold:
- the main response has `cf-mitigated: challenge`;
- the title contains "Just a moment", "Attention Required" or "Verifying";
- the DOM has `#challenge-form`, `#challenge-running`, `#challenge-stage`, `.cf-turnstile`, an `iframe[src*="challenges.cloudflare.com"]` or `input[name="cf-turnstile-response"]`.

This merges the bake-off's markers with klank `ug_webview.rs:81-85` and FlareSolverr `flaresolverr_service.py:46-54`.

How to act on it:
- Read `cType` from the page script. If `interactive`, stop at once.
- If `non-interactive` or `managed`, wait up to the agreed limit (bake-off: 12 s; klank checks after 4 s and gives up at 40 s; Scrapling 10 s). Never click, never inject into the challenge frame.
- A load that ends `.blocked` starts the per-host back-off (1.4 item 9).

### 2.5 Feasible vs brittle, in plain words

What will work most days: E-Chords loads in Segue's hidden browser like a page the owner opened, because the browser remembers the "you passed" cookie between launches and the page's own JSON calls ride on it. What will fail sometimes: a fresh cookie store after "Clear site data", heavy use in a short time, or Cloudflare tightening E-Chords' rule. Then the page asks for a human tick. Segue then either hands the page to Safari or a paste, or (if the owner allows it) shows him the same page so he ticks it once. After that tick the cookie is stored again and later hidden loads pass. Nothing free makes that tick go away, except possibly Apple's Private Access Tokens, which Segue gets for free if Apple passes them to app web views.

### 2.6 What was and was not run

- Nothing was run against UG, E-Chords, Chordie or any Cloudflare site; every claim about a third-party tool comes from its source or README.
- The warm-store WKWebView re-run was skipped. The bake-off's WebKit data (`~/Library/WebKit/wkfetch` and friends) was moved to the Trash after its run, so "warm" no longer exists, and one cold load repeats a case already measured. The spikes in 2.3 (scheduling policy, window, PAT) are the useful next loads; they belong to P9-4a step a3 under the spec's pacing rules.
- `inactiveSchedulingPolicy` and `dataStoreForIdentifier` were checked in the installed SDK (MacOSX 27.0, `WKPreferences.h:56-70`, `WKWebsiteDataStore.h:109`). Run `apple-api-check` again before use, as the spec requires.

## 3. Recommendations

1. **No dependency to adopt.** Build `UGSearchReader`, `TabJSONParser` and `WebKitPageLoader` ourselves, informed by klank (cascade and reveal), freetar, tabr and fretz (Swift shapes) and LiveNLoud (converter and integrity check).
2. **Fold these into P9-4 before P9-4a step a5**:
   - in the WebKit path, read `UGAPP.store` (wrapped) before `js-store`;
   - fall back to a content-based search for the chart (flagged for the canary);
   - add the chord-integrity check to spec 8.5;
   - rejoin slash chords and trailing qualities, and handle `[verse]` and `[b]/[i]/[u]` tags, in the `[ch]` converter;
   - decode entities in the content field;
   - add a fixture for UG's in-app SPA navigation (stale `js-store`).
3. **Fix spec 8.6's navigation rule** to apply to the main frame only, and allow `challenges.cloudflare.com`, `about:blank` and `about:srcdoc` subframes. Make the ad block list exempt the challenge host.
4. **Change the WebKit loader's store** from `nonPersistent()` (spec 8.6 as written) to the bake-off's `dataStoreForIdentifier` (bake-off question 4). This research confirms it as the single most important lever.
5. **Add a one-hour per-host back-off** after 403, 429, 503 or `.blocked`, and a one-time home-page warm-up retry for a challenged deep page, both counted by the pacer.
6. **Branch on `cType`**: stop at once on `interactive`; wait (bake-off 12 s) on `non-interactive` and `managed`.
7. **Run three cheap spikes in P9-4a step a3**: scheduling policy and window hosting on a cold challenged page; Private Access Tokens through a WKWebView on Cloudflare's PAT demo page; the Personal build's sandbox.
8. **Keep the mobile API as a research ticket only** (bake-off question 3), with this doc's notes (hour format, server time, 498 canary) attached.

## 4. Open questions for the owner

1. **Show the challenge to you?** Spec 8.6 and R179 say the challenge is "never shown for the user to solve". klank's pattern, and bake-off question 5's "Open here", show the same view so you tick the box yourself; the cookie then serves later hidden loads. Options:
   - (a) allow "Open here" as a third action beside Open in Safari and Paste the Page Instead (**recommended**);
   - (b) keep the spec: never show it;
   - (c) show it automatically when `cType` is interactive, without a button.
2. **Main-frame-only navigation rule** (recommendation 3): allow the challenge's own frames? Recommend yes; without it the automatic pass cannot work.
3. **Back-off length**: one hour after a block (ember) vs only spec 9's per-host gap. Recommend one hour per host, shown in the group's failure line ("E-Chords asked Segue to wait; try again after 21:40").
4. **Rating prior**: tabr and spec 6.10 use k=50; the bake-off proposed k=25 with mean 4.0. Recommend k=50 with mean 4.0 (UG's ratings cluster high), as a table-tested constant.
5. **Warm-up visit**: allow one extra home-page load when a deep page is challenged in a cold store? Recommend yes, counted by the pacer.
6. **Private Access Tokens**: run the PAT spike against Cloudflare's demo page (not a site we import from)? Recommend yes. Note: it needs your Apple ID signed in on the test Mac, which it already is if you use iCloud.
7. **Mobile API research ticket**: create it now, blocked on "web route fails", or not at all? Recommend create and block it, so the notes in 1.1 and 1.4 item 8 are not lost.

## Appendix A. Long tail found by search, not read at source

Every repo the searches returned that is not in section 1.3, kept per the "never prune" rule. **Not read, so nothing is taken from them: verdict build from scratch** unless a later pass reads one. Columns: repo, stars, last push, language, licence, description (from GitHub).

| Repo | Stars | Last push | Language | Licence | Description |
|---|---|---|---|---|---|
| `noahmaranesi/Ultimate-Guitar-Hack` | 108 | 2021-09-30 | - | none | The first tool to download any Guitar Pro file, including 'Official' f |
| `cemolcay/ChordDetector` | 98 | 2019-12-04 | Swift | mit | A tiny menu bar app detecting the chords of the songs you are listenin |
| `ultimate-guitar/Tabdown` | 89 | 2017-02-21 | - | bsd-3-clause | Tabdown is an open mark-up language for text tabs & chords. |
| `gusper/SongTxt-vscode` | 35 | 2025-11-19 | TypeScript | mit | Visual Studio Code extension that adds support for editing text files  |
| `aguaviva/GuitarTuner` | 22 | 2019-07-21 | HTML | none | Ultimate Online Guitar Tuner.  |
| `jers0/ultimate-guitar-scraper` | 21 | 2017-05-05 | JavaScript | mit | A scraper for http://ultimate-guitar.com |
| `ccabrales/TabHero` | 16 | 2019-03-03 | Python | mit | Python command line tool to search and download guitar tabs from ultim |
| `AvocadosConstant/ultimate-guitar-minimalizer` | 12 | 2017-05-31 | JavaScript | none | Ultimate Guitar is a horrible website. This chrome extension gets rid  |
| `vincepii/uguitar-python` | 12 | 2015-12-07 | Python | none | python bindings for ultimate-guitar |
| `xeloader/modest-guitar` | 11 | 2026-06-15 | JavaScript | none | Chrome extension for Ultimate-Guitar to show tabs in multiple columns  |
| `hubanton/Ultimate-Guitar-to-PDF` | 10 | 2024-05-21 | Python | mit | Converts UG-Tabs to a PDF using Python |
| `sergilazaro/GreasemonkeyUltimateGuitarRocksmith` | 9 | 2022-06-16 | JavaScript | mit | Greasemonkey script for UltimateGuitar tabs |
| `tsundokul/ug-pro-gpx-save` | 9 | 2022-06-02 | JavaScript | mit | Firefox Extension - Download ultimate-guitar.com Official GPX Tabs [Pr |
| `borismus/smusique-extension` | 7 | 2012-02-05 | JavaScript | none | Chrome extension to do client side scraping from ultimate-guitar and i |
| `moottier/ultimate-guitar-downloader` | 7 | 2022-03-16 | Python | apache-2.0 | Download tabs from ultimate-guitar.com |
| `andrewschalk/Nice-Tabs` | 5 | 2024-01-09 | Python | mit | Download Ultimate Guitar tabs into a clean printable PDF |
| `l3ku/ultimate-guitar-tabs-chords` | 5 | 2019-01-11 | PHP | lgpl-3.0 | DEPRECATED: A WordPress plugin that fetches tabs and chords from Ultim |
| `shiningjason/chordify-api` | 4 | 2019-02-14 | JavaScript | none | Scrape chords from ultimate-guitar |
| `victorfontes/python-ultimate-guitar` | 4 | 2022-12-08 | Python | bsd-2-clause | python-ultimate-guitar description |
| `20wontons/anfootball` | 3 | 2023-06-23 | Python | mit | a discord bot that pulls chords and tabs from ultimate-guitar.com (now |
| `atockar/UltimateGuitar` | 3 | 2015-10-08 | Python | none | Includes all code for creating relational database from ultimate-guita |
| `bendalton/tabapp` | 3 | 2008-11-14 | ActionScript | none | An application that allows you to quickly view your favorite tabs from |
| `micaharvey/Ultimate-Guitar-Chord-Scraper` | 3 | 2015-12-29 | Python | none | Python script for tech savvy guitarists.  Replaces ultimate-guitar.com |
| `moocarme/RiffChruncher` | 3 | 2016-10-22 | OpenEdge ABL | none | Independent project looking to grab tabs off 'ultimate-guitar.com' for |
| `RichVarney/ultimate-scraper` | 3 | 2022-01-08 | Python | mit | Scrape tabs from ultimate guitar |
| `RythenGlyth/UltimateGuitarGuitarProDownloader` | 3 | 2023-01-04 | JavaScript | none |  |
| `blacklight/ultimate-guitar-mytabs` | 2 | 2023-01-18 | JavaScript | gpl-3.0 | Browser script to scrape and download your saved UltimateGuitar tabs t |
| `dcw102213006/Ultimate_guitar_analytic` | 2 | 2019-05-13 | Jupyter Notebook | none |  |
| `dcw102213006/Ultimate_guitar_analytic_0812` | 2 | 2019-08-12 | Jupyter Notebook | none |  |
| `doorlay/tabify-ug-scraper` | 2 | 2021-12-03 | Python | none | A Flask API that scrapes guitar tabs from Ultimate-Guitar.com. |
| `fschmnn/ultimate-guitar-scrapper` | 2 | 2017-09-02 | Jupyter Notebook | none | A jupyter notebook to convert content from https://www.ultimate-guitar |
| `g14p/ug-songsearch` | 2 | 2026-02-14 | Shell | gpl-3.0 | # Ultimate Guitar Song Search |
| `knightsforce/ultimate-guitar` | 2 | 2017-04-09 | JavaScript | none |  |
| `mihirtiwari/guitar-tabs` | 2 | 2022-12-07 | Python | mit | Scrapes Ultimate Guitar for tabs.  |
| `mjain123/ultimate-guitar` | 2 | 2020-09-22 | JavaScript | none |  |
| `nkoleske/ultimate-guitar-userscript` | 2 | 2022-10-03 | JavaScript | none | modifies tabs on ultimate-guitar.com to display in a dual column forma |
| `NoctalIvan/ultimate-guitar-crawler` | 2 | 2022-02-02 | JavaScript | none | Export your Ultimate Guitar playlist in CSV and in JSON via the ultima |
| `ovangle/chordia` | 2 | 2023-01-19 | TypeScript | none | Manage ultimate-guitar tabs |
| `ShaunSHamilton/UltimateGuitarScraper` | 2 | 2019-08-08 | Python | none | Python script that places UG tabs in a playlist |
| `Sinnaj94/api_ultimate_guitar` | 2 | 2017-05-20 | Python | none | an API for ultimate guitar |
| `younggeun0/ultimate_guitar_chord_scraper` | 2 | 2023-09-24 | Python | none | 파이썬 토이 프로젝트 - ultimate-guitar.com 기타 코드 스 |
| `777388/GuitarMan_chromeExtention` | 1 | 2023-12-31 | JavaScript | none | They're gonna take over this extension, I want you to use them to lear |
| `aberonni/ultimate-guitar-randomiser-extension` | 1 | 2025-10-17 | JavaScript | none | Adds a "Random tab" button to the "My tabs" page on Ultimate-Guitar.co |
| `achimgrothkopp-ux/songtabs-app` | 1 | 2026-05-16 | Python | gpl-3.0 | Offline-Songtext-App mit Gitarrenakkorden für Android (Kivy/KivyMD, U |
| `adebiasi/SongsAnalyzer` | 1 | 2023-10-24 | Python | gpl-3.0 | Simple program to automatically retreive songs data (lyrics + guitar c |
| `aopsmathguy/ChordMaker` | 1 | 2026-05-13 | JavaScript | none | A simple Chrome extension to download worship chord sheets as pdfs fro |
| `babe221-bot/gh-repo-clone-Pilfer-ultimate-guitar-scraper` | 1 | 2025-07-09 | - | gpl-3.0 |  |
| `bbevren/ultimate-guitar-scraper` | 1 | 2019-01-28 | - | none | [shot down] A scraper for https://www.ultimate-guitar.com |
| `carlqt/ug_tabs` | 1 | 2014-12-09 | Ruby | none | Search for tabs in ultimate guitar and save it to a text file. |
| `emjrymer/UltimateGuitar` | 1 | 2016-05-04 | JavaScript | none |  |
| `ijesh/GuitarTabFilter` | 1 | 2013-04-02 | Python | none | Filtering chord tabs from all the different links from UltimateGuitar. |
| `jmdagamewiz/ultimate-guitar-scraper` | 1 | 2021-01-03 | Python | none | A command line application that scrapes information from a valid ultim |
| `jrwaller/ugdownloader` | 1 | 2017-09-20 | JavaScript | none | Chrome extension that enables downloading of publisher removed guitar  |
| `ltpitt/ultimateguitar-tab-to-pdf` | 1 | 2026-06-25 | Python | mit | Always wanted to have a nice, neat pdf from ultimate guitar for your s |
| `Major-Project-EED-402/UltimateGuitarHeroWebExtraction` | 1 | 2023-10-16 | Jupyter Notebook | none |  |
| `maspayn3/cli-ug` | 1 | 2022-06-14 | Python | none | Command line based web scraper that scrapes ultimateguitar.com tab she |
| `NicotheMcCoy/ChordCrawler` | 1 | 2023-11-01 | Python | mit | ChordCrawler is a specialized web scraper designed to seamlessly extra |
| `Reaaaale/UltimateGuitar-API` | 1 | 2025-09-06 | Python | none | API per lo scraping degli accordi dal link di ultimate guitar |
| `Riffjordan12/Ultipy` | 1 | 2022-07-04 | - | none | A Ultimate Guitar Scraper/Displayer |
| `rlecellier/ultimateGuitareScraper` | 1 | 2022-03-25 | JavaScript | none |  |
| `Tabster/Tabster.Plugin.UltimateGuitar` | 1 | 2016-04-19 | C# | apache-2.0 | Supports ultimate-guitar.com tab searching and downloading. |
| `talsafran/tabgrab` | 1 | 2013-12-12 | Ruby | none | Scrapes the shit out of UltimateGuitar. |
| `Tylermhh/ultimateGuitarClone` | 1 | 2023-07-27 | JavaScript | none |  |
| `achinthyasoordelu/tabify` | 0 | 2021-12-17 | Python | none | Get UltimateGuitar page for currently playing Spotify song |
| `AliKamil/Capo` | 0 | 2016-02-25 | PHP | other | Capo test case for UltimateGuitar.com |
| `andrejjovanovic/slopsmith-plugin-ug` | 0 | 2026-05-19 | - | none | Slopsmith plugin: Create CDLC from Ultimate Guitar tabs |
| `aniakchak09/UltimateGuitarShuffle` | 0 | 2026-04-22 | Python | none |  |
| `bstevia/baliset` | 0 | 2026-07-31 | TypeScript | none | Guitar Tab Heatmap Extension for Ultimateguitar |
| `CZGabry/UltimateGuitarTuner` | 0 | 2024-08-14 | TypeScript | none |  |
| `DanteDeRuwe/UGYT` | 0 | 2018-08-16 | JavaScript | none | An extension that adds the option on an UltimateGuitar page to listen  |
| `ddxMusic68/ultimateGuitarDownloader` | 0 | 2026-10-27 | Python | none | this lets you get the pdf download from ultimate guitar without paying |
| `eliyahupeleg/UltimateGuitar` | 0 | 2020-04-02 | - | none | downloading all the chords from ultimate guitar to txt files and into  |
| `ghth-admin/fretonator` | 0 | 2020-06-07 | - | none | The ultimate interactive free guitar theory tool. |
| `Jericho1337/Simple-UltimateGuitar-PDFDownloader` | 0 | 2026-09-19 | JavaScript | mit | An ultimate guitar tab viewer and downloader written in react |
| `kjranyone/UltimateGuitarTrainer` | 0 | 2026-03-02 | - | none | Literally-it means exactly what it says. |
| `matt-whitehead/ugscrape` | 0 | 2019-04-25 | Python | other | A simple Python library for scraping chords from ultimateguitar.com |
| `maxiicano/tabblatureforyou` | 0 | 2021-10-04 | HTML | none | Website that recommends a new guitar tab to learn. Database by Ultimat |
| `niks8990/UltimateGuitarTest` | 0 | 2017-05-20 | Swift | none |  |
| `OtavioWeber/ugRandomizer` | 0 | 2017-08-07 | C# | none | Opens a random chord from your UltimateGuitar's favorites list. |
| `scoutrul/ultimateguitar` | 0 | 2017-03-24 | JavaScript | none |  |
| `Senneer/ultimateguitarTest` | 0 | 2016-10-05 | CSS | none |  |
| `shottyshotts/ultimaterguitar` | 0 | 2016-02-20 | CSS | none | Ultimater Guitar project for MHacks |
| `sidneytma/ChordFrequency` | 0 | 2024-01-03 | Jupyter Notebook | none | An exploratory project examining the frequency of chords in popular so |
| `TamsinHuggins/pop-chord-analysis-ultimateguitar` | 0 | 2024-02-26 | Jupyter Notebook | none | Portfolio project showcasing collaborative project management, web-scr |
| `thefernanbri/UGTabsNotice` | 0 | 2023-07-04 | HTML | none | It notifies you daily which are the new official tabs available on the |
| `tim-tom-88/UG-tab-search` | 0 | 2026-04-02 | JavaScript | none | Pull song title from YT Music and search for it on UltimateGuitar |
