# Phase 9 research - Personal-build import bake-off (2026-11-01)

Research and bake-off for P9-4 (`docs/phases/9-workstreams/P9-4-lyrics-and-url-import.md`) after the owner's new rulings for the **Personal build only** (never distributed, isolated in `SeguePersonalModules`, absent from the App Store build):

- licence is no object: components are picked on quality alone;
- Ultimate Guitar (UG) is first-class: in-app UG search (title -> versions with rating and votes, chords vs tab, preview, pick, review, import);
- one search across UG, Chordie, E-Chords and LRCLIB at once, results grouped by source;
- pages blocked to plain requests are loaded in a hidden in-app WebKit view, like the owner opening the page, then parsed. No captcha solving.

**V** = verified here (probe, measurement or source read, date given), **U** = unverified. All probes ran from this Mac on 2026-11-01 between 05:20 and 06:40 UTC (2026-10-31 evening local), with the User-Agent `Segue/0.9 research probe (+https://segue.ryandsilva.dev; personal use)` for plain requests, about 5 s between requests to a host, 13 UG requests, 7 Chordie, 3 plain E-Chords, 14 WebKit page loads, ~60 LRCLIB.

**Test data** (gitignored, contains copyrighted lyrics, never commit): `research/phase9-import/.build/bakeoff/` (ignored by the repo-wide `.build/` rule; `make clean-local` does not touch it). `ug/`, `chordie/`, `echords/` (plain and `wk/` WebKit captures, server HTML fetched from inside the page, PNG snapshots), `lrclib/` and `lrclib-heldout/` (raw search responses), `gold/` and `gold-heldout/` (gold romanizations, per-engine outputs), `tools/` (every harness script used here, so each number below can be re-run). P9-4a step a3 should move the pages into the planned `research/phase9-import/pages/` once its `.gitignore` rule lands.

## Recommendations in one screen

| Area | Winner | Integration |
|---|---|---|
| UG search | The web search page `search.php`, reading the JSON UG embeds in `<div class="js-store" data-content>` (`store.page.data.results`) | Plain `URLSession` first (works today, V); the hidden WebKit view as fallback when UG starts challenging. Not the signed mobile API (section 1.3). |
| UG chart | Tab page `js-store` JSON (`tab_view.wiki_tab.content`), plus `tab_view.meta` for capo and `tab.recording.recording_artists` for the singer | As spec, with two field fixes (section 1.2). |
| E-Chords | Hidden WebKit view with a persistent, app-owned cookie store; search via the site's own `/api/search` JSON called from inside the page; chart from `<pre>` with `<span data-chord>` | Plain requests are hard-blocked (403, V). |
| Chordie | Plain `URLSession`; `result.php?q=` for search, `div.chordline/textline` for charts | Search quality is currently poor (section 2.1). |
| LRCLIB | Unchanged API; but 503 is common, so retries must be more than one | Section 2.3. |
| Hidden WebKit | One on-demand offscreen `WKWebView` on a dedicated `WKWebsiteDataStore(forIdentifier:)`, torn down after use | Section 3. |
| HTML parser | **SwiftSoup 2.14.3** (MIT), JSON-first extraction | `XMLDocument` HTML mode silently lost data on 2 of 6 real pages (section 4). |
| Romanizer | **A native Swift rule engine** (spec 7.3, with four fixes measured here) plus an override list | 95.5% word agreement (RomanNormalizer-equivalent) and 90.3% exact on a held-out set; beats Aksharamukha, ICU, sanscript, uroman, epitran and IndicXlit (section 5). |

## 0. Where the owner's new rulings change the spec (to fold into P9-4)

1. **Spec 8.2 "No JavaScript runs: the page is never loaded in a web view" and 8.6 "never waits it out, never imitates a browser"** are reversed by the WebKit ruling. 8.6's "never solve a CAPTCHA" and "never retry a challenge in a loop" survive. Section 3 gives the replacement rules.
2. **UG search is new scope**, and UG's `robots.txt` **disallows `/search.php`** (V, section 1.4). The spec's "corpus collection honours robots.txt" rule cannot hold for search; open question 2.
3. **E-Chords `robots.txt` disallows `/search` and `/api/`** (V), the two routes its own search page uses. Same question.
4. **Spec 8.4 field paths need fixes** (V): capo is `tab_view.meta.capo`, not `tab.capo`; the singer of a "Misc Soundtrack" film song is in `tab.recording.recording_artists[].artist.name` (code-found structured data, so R174-compliant), so spec 5.4's "the singer is whatever the page text states" can do better.
5. **Spec 7.3 romanizer table**: ड़ and ढ़ should map to "d" and "dh" (casual "thodi", "dhadkan", "badha"), not "r" and "rh"; three more rule changes in section 5.5.
6. **Spec 9 pacer**: "after a 503 one automatic retry" is too few for LRCLIB today (section 2.3).

## 1. Ultimate Guitar search feasibility

### 1.1 The search page (V, 2026-11-01)

- `GET https://www.ultimate-guitar.com/search.php?search_type=title&value=<query>` returns HTTP 200 to a plain `URLSession`-style request with the honest UA above (3 of 3 searches: "tum hi ho", "wonderwall" with `title=wonderwall&type=300`, "tujhe dekha to"). Server: Cloudflare, `cf-cache-status: DYNAMIC`, no challenge. The embedded config says `"is_bot": true` for our UA, yet serves the page anyway.
- The results are JSON inside `<div class="js-store" data-content="...">` (HTML-escaped), at `store.page.data`: `search_query`, `results_count`, `results[]`, `pagination {total, current}`, `order[]` (Relevance, ABC, "High rated"), `filters.types[]` (each with a count and a URL: Chords `type=300`, Tab `type=200`, Official `type=900`, ...).
- Page size: ~30-50 results per page (33 for "tum hi ho", 54 of 69 for "wonderwall" chords, 2 pages). Pagination is `&page=N`.
- Each tab result (V field list): `id`, `song_id`, `song_name`, `artist_name`, `artist_id`, `type` ("Chords", "Tabs", "Pro", "Ukulele Chords", "Official", ...), `version`, `votes`, `rating` (0-5), `tonality_name`, `difficulty`, `date`, `tab_url`, `tab_access_type` ("public"), `status`, `verified`, `version_description`, `recording.recording_artists[].artist.name` (the singer, e.g. "Arijit Singh" for "Aashiqui 2 - Tum Hi Ho" by "Misc Soundtrack"), `album_cover`, `localized_song_name`.
- Mixed into `results` are **marketing entries** with a different shape (`marketing_type` "TabPro" or "official", `tab_url` pointing at `/pro/?app_utm_...`, keys `app_link`, `device`, `tracks`): they are ads for UG's paid products and must be filtered out (rule: keep only entries with an integer `id`, `type` present and `tab_url` on `tabs.ultimate-guitar.com/tab/`).
- What UG's own ranking looks like for a Bollywood query: 13 "Chords" results for "tum hi ho", with the film's five Chords versions (v1-v5) carrying votes 39 / **833** / 50 / 14 / 23 and ratings 4.68 / **4.84** / 4.84 / 4.79 / 4.52. Picking "the best" needs votes as well as rating (section 2.4).
- Preview: the search result has no chart text, so a preview costs one tab-page request (paced, cached for the session).

### 1.2 The tab page (V)

- Re-verified spec 3.6: `store.page.data.tab_view.wiki_tab.content` holds `[Verse 1]` headers and `[tab][ch]Em[/ch] ...\r\nHum tere bin ...[/tab]` markup; `[tab]` blocks also hold real tablature (`e|---7---8--|`) for intros, which the converter must treat as tab lines.
- **Fixes to spec 8.4**: capo is `tab_view.meta.capo` (1 on page 1244521) with `meta.tonality` and `meta.tuning.value`; `tab` has no `capo` key. `tab.recording.recording_artists` gives the singer. `tab_view.has_chord_pro` exists (U what it serves).
- `tab_view.versions` lists the sibling versions, so the review can offer "other versions" without a new search (U: shape not inspected).

### 1.3 Prior art: open-source UG clients (V, GitHub metadata 2026-11-01)

| Project | What it uses | Notes |
|---|---|---|
| `kmille/freetar` (788 stars, Python, pushed 2026-09-25) | `search.php` and tab pages, BeautifulSoup on `div.js-store` | The closest match to our approach; a desktop Safari UA string; has its own proxy fallback. |
| `Pilfer/ultimate-guitar-scraper` (133, Go, 2023) | Signed mobile API `api.ultimate-guitar.com/api/v1/...` | Documents the key: `X-UG-API-KEY = md5(deviceId + "YYYY-MM-DD:HH" (UTC) + "createLog()")`, `X-UG-CLIENT-ID = deviceId` (`pkg/ultimateguitar/api.go:76-106`, `reversing-notes/search.md`). |
| `More-Than-Solitaire/Tabs-Lite` (173, Kotlin Android app, Apache-2.0, 2026-04) | Mobile API `api/v1/tab/search?title=&page=&type[]=300&official[]=0`, `tab/suggestion?q=` (max 5 chars) | `BackendConnection.kt:193-280`. A shipping app on this route. |
| `zachpmanson/penultimate-guitar` (TS, 2026-09) | Mobile API search and info | |
| `Conchylicultor/equin` research note `research/2026-06-23-sonata-ug-search-import.md` | Mobile API search with an Android UA `UGT_ANDROID/4.11.1` | Notes the response shape is undocumented and must be checked live. |
| Others: `joncardasis/ultimate-api` (Python), `jabbey1/UGDownloader`, `cavic19/ultimate-guitar-scraper-ts`, `hampterworks/klank` (Rust `ug_mobile_api.rs`), `libf-de/KordBook` (Kotlin), `8bury/musicsheetgrep` (Go) | Mix of both routes | Existence proofs; none is a dependency candidate for a Swift app. |

**Verdict**: build our own, informed by freetar (web JSON route). The mobile API is cleaner JSON but requires impersonating UG's Android app (its UA and a key derived from a string in its binary): that is closer to "circumventing content protection" in UG's terms (1.5) than a browser-like page load, and it can break silently on a key change. Not probed (deliberately). Open question 3.

### 1.4 Rate limits and robots (V for robots, U for limits)

- No published rate limit (U). Cloudflare fronts everything (`__cf_bm` cookie, `cf_turnstile_site_key` and `captcha_id` in the page config, so a challenge is one config switch away).
- `robots.txt` (V): `Disallow: /search.php`, `/explore`, `/pro/`, `/tab-pro/download`, `/tab/applicature/transpose`; `/tab/` itself is allowed.
- Recommended pacing: one search request per user search, a page-2 request only on "More", previews one at a time, at least 2 s between UG requests (spec 9's per-host gap).

### 1.5 Terms (V, `ultimate-guitar.com/about/tos.htm` re-read 2026-11-01)

Content "may be accessed for your personal, non-commercial use only" (6.3); no duplication except printing tabs and lyrics for personal non-commercial use (6.2); "you will not attempt to ... circumvent or modify any Content protection methods" (6.2); no "reverse engineer, decompile ... the Service or any related software". No clause naming robots or scrapers was found. A personal tool that loads the page the owner asked for, in a real browser engine, and keeps one chart he accepts, is inside "personal, non-commercial use"; solving or bypassing a bot check, or using the reverse-engineered mobile key, is the part the terms speak against.

### 1.6 URLSession vs WKWebView on UG (V)

- Plain request: 200 for search and tab pages (above).
- WKWebView (default WebKit UA, ephemeral store): 200 in 0.47 s, loaded in 1.6 s, no challenge. **After hydration the `js-store` div is gone from the DOM** (the React app consumes it), so the WebKit path must not parse `outerHTML` for it: either read the server HTML by calling `fetch(location.href)` from inside the page (`callAsyncJavaScript`, which carries the page's cookies; verified on E-Chords, section 2.2) or read `window.UGAPP.store` (referenced in the page scripts; U as an object path).

## 2. Multi-site search

### 2.1 Chordie (V)

- Search: `GET https://www.chordie.com/result.php?q=<free text>` (the home page form). robots.txt allows it (only `editsong.php`, `removesong.php`, `/admin/`, one source path disallowed).
- Markup per hit: `div.songList` > `div.songListContent` > `a[href^="/chord.pere/"]` with `<span>Title</span>&nbsp;&nbsp;<span>Artist</span>`, a first-lines snippet link, a type label (`CHORDS`) and the chord set as `span.label`; rating in `div.rateStar` (a number like "2.3" and a star width percent). Sections "SONGS" with "Showing hit 1-5 of N".
- **Quality today is poor** (V): only 5 song hits per page with no visible pagination link; "tum hi ho" returned none of the actual "Tum Hi Ho" pages (it matched lyric text: "Tum Meri Ho", "Alfazon Ki Tarah"); "wonderwall oasis" returned no Wonderwall; "wonderwall" returned it third. The site shows a banner "Site is back up running again ... Working on getting search back up" (dated 25.10).
- Chart pages match spec 3.6 (`div.chordline` with `span.absc`, `div.textline`). New case (V): a page can be a **copyright block notice** instead of a chart ("I have received a letter from someone claiming that this song violates their copyright ... block this song", Wonderwall page) with HTTP 200; the parser must report `.noChart` with that reason.

### 2.2 E-Chords (V)

- **Plain requests are hard-blocked**: HTTP 403 "Attention Required! | Cloudflare ... Sorry, you have been blocked" for both the home page and the search page with the honest UA. This is a WAF block, not a JavaScript challenge, so no plain-request strategy works.
- **Hidden WKWebView** (default WebKit UA, no window, `.prohibited` activation policy):
  - cold, ephemeral store, home page: 200 in 0.34 s, `cf_clearance` cookie set silently, done in 1.7 s;
  - cold, ephemeral store, a **song page** after ~10 loads: `cf-mitigated: challenge` "Just a moment...", the managed challenge re-ran every ~5-9 s and never cleared in 25 s (twice, with and without an offscreen `NSWindow`; `document.visibilityState` stays "hidden" for an app that is not frontmost, U whether a visible window would pass);
  - **persistent store holding the earlier clearance**: the same song page 200 in 0.14 s, no challenge (3 of 3 later loads).
  So **cookie persistence decides success**; an ephemeral store is the wrong default (section 3).
- Search: the search page `/search-all/<q>` is a Vue app that fetches `GET /api/search?q=<q>&songs_take=15&lyrics_take=12&artists_take=..&albums_take=..&videos_take=..&composers_take=..` (every `*_take` must be 1-30 or the API answers 422). Called from inside the page it returns JSON `{songs:{hits,total}, lyrics, artists, albums, videos, composers}`; a song hit has `ID_MUSICA`, `TITULO`, `ARTISTA`, `COD_TITULO`, `COD_ARTISTA` (page URL `/chords/<COD_ARTISTA>/<COD_TITULO>`), `QT_HITS` (all-time views), `QT_HITS_SEMANA`, `AUTOR` (composer), `INSTRUMENTOS[].LEVEL` (difficulty 1-5). **No rating or votes.** Rendered DOM equivalent: `a.song-item[href^="/chords/"]` with `span.artist` and `strong.song`, ready only ~5-8 s after load (a loading overlay first), so the in-page `fetch` of the JSON is faster and steadier than waiting for the DOM.
- Chart page (server HTML, 3 pages): `<pre>` holds chords over lyrics with each chord as `<span data-chord="F#m">F#m</span>`, column positions kept by spaces, `<b>(2x)</b>` and `<i>Intro:</i>` inline, tab blocks in a nested `div.tabs` inside the `<pre>`. Fields: JSON-LD `MusicComposition` (`name`, `composer`, `recordedAs.byArtist.name`) and `window.SONG_METADATA` (`CAPO`, `CHORDS_KEY`, `ARTIST_NAME`, `NAME`, `TYPE`). Two data-quality traps found: the site auto-tags the Hindi word "Ab" as an A-flat chord on a lyric line (`<span data-chord="Ab">Ab</span> tum hi ho`), and one contributed page (`/chords/arijit-singh/tum-hi-ho`) has its chords glued into the words ("EmHum tere bin ab Creh nahi sakte"), which the site itself renders that way (snapshot `echords/wk/snap-...arijit-singh_tum-hi-ho.png`). The parser treats a `data-chord` span on a line whose other tokens are words as lyric text, and the sanity checks (spec 8.5) reject the glued page.
- Terms not read (U).

### 2.3 LRCLIB (V)

- Search worked at 05:3x UTC (spec 3.6 saw 502 earlier); 20 records per query as documented; records carry both Devanagari and Latin uploads of the same song (for "tum hi ho": 7 Devanagari, 10 Latin of 20).
- **HTTP 503 `ServerOverloaded` with `Retry-After: 1` and a JSON body was frequent**: about half of ~60 requests at 1.5-2.5 s spacing, sometimes 4 in a row for one query even after waiting `Retry-After` x 1.3 + 2 s. Recommend: up to 3 automatic retries on 503 honouring `Retry-After` plus jitter (still sequential and paced), then the 6.8 "isn't answering" message; 429 stays at no automatic retry.
- Of the 29 Hindi film-song queries that answered, every one had Devanagari records (median 12 of 20), so romanization will fire on most Hindi searches.

### 2.4 One search across all sources: merge and ranking design

- **Fan-out**: one request per source, in parallel across hosts (each host still serialised by the pacer): UG `search.php`, Chordie `result.php`, LRCLIB `/api/search` (plus its variants, spec 6.3), E-Chords through the hidden view. Results stream into their group as each source answers; each group shows its own spinner and its own failure line (spec 6.8 / 8.7 messages per source). Expected wall time (V timings): UG ~0.5-1 s, Chordie ~0.5 s, LRCLIB 0.3 s to several s under 503, E-Chords 1.5-3 s warm (cold WebKit start included).
- **Groups by source** (owner's ruling), fixed order UG, E-Chords, Chordie, LRCLIB lyrics (chord sources first, lyrics last; open question 7), each showing its top 5 with "Show all".
- **Versions nest under their song** (parent/child): UG versions of one `song_id`, and E-Chords hits with the same normalized title and artist, collapse to one row whose best version is preselected; the other versions are children with their own rating, votes and type.
- **Per-row score with a breakdown** (sums to the total, kept for tests and a debug popover), all text similarity on `RomanNormalizer.loose` forms with the `NearDuplicateIndex` word-overlap measure, so "tujhe dekha toh" matches "Tujhe Dekha To":
  - title similarity 0.45, against the title after the UG "Movie - Title" split (and against the movie, so "aashiqui 2" finds the film's songs);
  - artist similarity 0.15, against artist, `recording_artists` (UG), album (LRCLIB);
  - quality 0.30, per source: UG Bayesian rating `(v / (v + 25)) x rating + (25 / (v + 25)) x 4.0`, scaled to 0-1 (833 votes at 4.84 beats 50 at 4.84 beats 0 votes); E-Chords `log10(1 + QT_HITS) / 5` capped at 1; Chordie its 0-5 rating / 5; LRCLIB 1 when it has plain lyrics;
  - type 0.10: Chords / Ukulele Chords 1, LRCLIB plain lyrics 0.6, Tab 0 (shown, not importable, spec Q14), Pro / Official / Video hidden.
- "In your library" mark from `NearDuplicateIndex` as in spec 5.3, for every source.
- No AI anywhere in search (spec 6.3 rule 5); the query variants of spec 6.3 apply to LRCLIB only (UG and E-Chords already match loosely on their side; Chordie is free text).

## 3. The hidden WebKit view on macOS in a sandboxed app

### 3.1 Measured (V, unsandboxed CLI probe on this Mac, macOS 26.6.2; `tools/wkfetch.swift`)

| Case | Result |
|---|---|
| E-Chords home, cold ephemeral store | 200, no challenge, 1.7 s to loaded, `cf_clearance` set |
| E-Chords search page | 200; results via XHR after 5-8 s |
| E-Chords song page, cold ephemeral store (after ~10 loads in 15 min) | `cf-mitigated: challenge`, reload loop every 5-9 s, not cleared in 25 s (2 of 2 runs) |
| Same page, persistent store with earlier clearance | 200 in 0.11-0.24 s, loaded in ~1 s (3 of 3) |
| UG search page | 200, 1.6 s, no challenge |
| Memory per live view | WebContent 164-243 MB RSS, Networking 39-52 MB, GPU 34-36 MB, host +~10 MB: **about 250-330 MB** while a view exists |

### 3.2 Design

- **One hidden fetcher, on demand**: a `WKWebView` created when a fetch needs it, not in a window (or in a borderless offscreen window if testing shows Turnstile needs one, U), used for one page at a time behind the same `RequestPacer`, and torn down 30 s after the last use so the WebContent process (the 160-240 MB) exits. On an 8 GB MacBook Neo that keeps the steady state at zero and the peak near 300 MB, below the on-device model's budget; never during a show (R109).
- **Dedicated persistent cookie store**: `WKWebsiteDataStore.dataStoreForIdentifier(UUID)` (macOS 14+, V in the installed SDK `WKWebsiteDataStore.h:109`, with `removeDataStoreForIdentifier` at :117), a fixed UUID owned by the Personal module, so clearance cookies persist across launches (the measured key to success), stay separate from any other web view, live in the app's sandbox container, and a "Clear site data" button in Settings > Advanced can wipe them. Not `.default()` (shared with any other WebKit use in the app), not `.nonPersistent()` (re-challenged every launch).
- **User-Agent**: WebKit's own default (no `customUserAgent`), which is what "like the owner opening the page" means; the honest `Segue/...` UA stays on `URLSession` requests (spec Q3). Setting the Segue UA in the web view would only invite the WAF block.
- **Reading the page**: after navigation finishes, prefer JSON: `callAsyncJavaScript` in a separate `WKContentWorld` running `fetch(url)` for the server HTML or the site's JSON API, or reading a known global; fall back to `document.documentElement.outerHTML`. Then parse with the same parsers as `URLSession` pages (one parser per site, two transports).
- **Ad and tracker blocking** with a `WKContentRuleList` for the import view (U: should cut load time and the WebContent footprint; the E-Chords page pulls Google ads, GTM, Clarity).
- **Sandbox**: the app already has `com.apple.security.network.client` (spec 3.1), which WebKit's Networking process needs; no new entitlement (U: verify in the Personal build, the probe was unsandboxed). No WebKit is linked in the App Store build (the code lives in the personal package; WebKit is not used anywhere in the repo today, V).

### 3.3 Detecting "still challenged" and falling back

A load is **challenged** when any of: the main response has `cf-mitigated: challenge` (V header), the title is "Just a moment..." or "Attention Required! | Cloudflare" (V), the DOM has `#challenge-form`, `#challenge-stage`, `.cf-turnstile` or an iframe from `challenges.cloudflare.com`, or the main frame reloads more than twice without the site's expected selector appearing. Wait up to **12 s** (the persistent store clears in ~1 s when it clears at all; a cold managed challenge that will pass usually does so in 2-5 s, U), never click anything, never inject into the challenge frame. Still challenged: `.blocked` with the spec 8.7 actions **Open in Safari** and **Paste the Page Instead**, plus (open question 5) **"Open here"**: show the same view in a visible sheet so the owner himself completes the check, after which the cookie persists and later hidden loads pass.

## 4. HTML parsing

### 4.1 Bench on the saved real pages (V, `tools/parsebench.swift`, release build)

| Page | SwiftSoup 2.14.3 | Foundation `XMLDocument(.documentTidyHTML)` | String scan, no DOM |
|---|---|---|---|
| UG search "tum hi ho" (118 KB) | 33 results, 10 ms (first call) | 33 results, 10 ms | 33, 17 ms |
| UG search "wonderwall" (151 KB) | 54 results, 2.8 ms | 54, 5.5 ms | 54, 12 ms |
| UG tab page (146 KB) | chart 3,399 chars, 2.9 ms | **chart 2,850 chars: 549 chars silently lost**, 5.2 ms | 3,399, 11 ms |
| Chordie song (45 KB) | 63 lines, inline chords right, 4.6 ms | 63 lines, right, 4.8 ms | n/a |
| E-Chords server HTML (347 KB) | `<pre>` 1,164 chars, JSON-LD read, 5.0 ms | **`<pre>` 11 chars**: tidy closed the `<pre>` at its nested `<div>`, 14 ms | n/a |
| E-Chords WebKit DOM (447 KB) | `<pre>` 1,125 chars, 7.6 ms | **11 chars**, 19 ms | n/a |

- `XMLDocument`'s HTML mode is libxml2 through tidy-style repair: on 2 of 6 real pages it returned a wrong answer with no error, which breaks the spec's "zero silent wrong charts" target. Kanna and Fuzi (both MIT) wrap the same libxml2 HTML parser (judged from their sources and metadata, not run: U); Kanna last pushed 2026-02, Fuzi 2024-07.
- SwiftSoup (MIT, 5.1k stars, 2.14.3 released 2026-10-16, so 15 days old today and inside the "at least two weeks" pin rule) follows jsoup's HTML5-style tree builder and kept every page intact. One caveat seen: `Element.text(trimAndNormaliseWhitespace: false)` still lost newlines in one `<pre>`; walk the text nodes (`TextNode.getWholeText()`) for `<pre>` content.
- **Recommendation**: SwiftSoup, used JSON-first: UG reads `div.js-store@data-content` (attribute value already entity-decoded by SwiftSoup) then `JSONSerialization`; E-Chords reads JSON-LD and `<pre>`; the generic reader walks the DOM. Keep the spec's isolation lint rule.

## 5. Devanagari-to-roman transliteration bake-off

### 5.1 Data and gold (V)

- Lyrics: LRCLIB search responses for 29 Hindi film-song queries (42 tried, 13 gave up on repeated 503s) (`lrclib/`, `lrclib-heldout/`). For each song, the best Devanagari record was aligned line by line to a **published Latin (casual) record of the same song on LRCLIB** using a candidate-neutral consonant-skeleton match (`tools/align.py`), then kept only where every word's skeleton agreed (`tools/gold.py`), then hand-reviewed: obvious typos in the published romanization were corrected (15 dev lines, 11 held-out lines, each kept with its `source_words` in the gold file, e.g. "muskhurana" -> "muskurana", "muje" -> "mujhe", two swapped lines fixed). Casual variants were left as published ("nahi", "wo", "tumse").
- **Dev set**: 107 lines, 544 words, 17 songs. **Held-out set**: 27 lines, 155 words, 5 more songs fetched after the rule fixes, never looked at while tuning. Total 134 lines, 699 words, 22 songs. Sources (LRCLIB record ids, Devanagari / Latin): Ae Dil Hai Mushkil 7372789 / 17981198; Apna Bana Le 32251543 / 31118084; Chaiyya Chaiyya 37780155 / 35357696; Gerua 11150933 / 13402402; Hawayein 33009754 / 21858681; Ilahi 23504915 / 35458952; Jeene Laga Hoon 38330990 / 33685322; Kesariya 36901201 / 15642523; Khairiyat 35325305 / 36937506; Kun Faya Kun 35123147 / 3428684; Lag Ja Gale 36765008 / 34539540; O Re Piya 39129202 / 35581582; Pal Pal Dil Ke Paas 32563684 / 25170780; Pehla Nasha 38942464 / 12394723; Tum Hi Ho 23257987 / 28844519; Tum Mile 21032711 / 12801594; Tum Se Hi 36322873 / 34291699; Zehnaseeb 34336900 / 33449494. Held-out: Agar Tum Saath Ho 5505022 / 28353962; Channa Mereya 39697097 / 13485249; Mere Haath Mein 38513982 / 21231247; Tera Hone Laga Hoon 12019364 / 18216583; Tujh Mein Rab Dikhta Hai 38057544 / 14413596.
- Limits: one published romanization per line is one person's casual spelling; LRCLIB contributors are not the owner. The "normalized" column below forgives exactly the variation `RomanNormalizer` already treats as the same word in Segue's search, which is the practical test ("will Ryan's search and near-duplicate check see it as the word he would type").

### 5.2 Metrics

- **Word exact**: output word equals the gold word. **Word normalized**: equal after `RomanNormalizer.normalize` (a Python port of SegueCore v5). **Attested**: the output is a spelling some LRCLIB contributor used for that Devanagari word anywhere in the 248 dev aligned pairs.
- **Schwa checks**: final schwa (words ending in a bare consonant: does the output end in "a" exactly when the gold does; 135 dev / 49 held-out words) and medial schwa (words with a consonant-consonant sequence where a schwa may be deleted, scored normalized; 115 / 32 words). Lines fully right = every word normalized-equal.
- Casual post-pass (used for the scholarly engines, `casual_from_scholarly` in `tools/bake.py`): ISO/IAST letters to casual (ā aa, ī ee, c ch, ch chh, ś/ṣ sh, ṁ/m̐ n or m before p/b/m), word-final aa -> a, ee -> i, oo -> u. "+ final-schwa" drops a word-final short "a" when the Devanagari word ends in a bare consonant.

### 5.3 Results, held-out set (27 lines, 155 words; the decisive table)

| Engine | Word exact | Word normalized | Attested | Final schwa | Medial schwa | Lines right | Speed |
|---|---|---|---|---|---|---|---|
| **Swift-able rule engine v2** (spec 7.3 + fixes, 15 overrides) | **90.3%** | **95.5%** | **91.6%** | 95.9% | **87.5%** | **77.8%** | 0.03 ms/line (Python) |
| Aksharamukha 2.3 RomanColloquial + `RemoveSchwaHindi` | 76.1% | 93.5% | 77.4% | 100% | 84.4% | 70.4% | 2.1 ms |
| Aksharamukha RomanReadable + `RemoveSchwaHindi` + casual pass | 86.5% | 91.6% | 87.7% | 100% | 81.2% | 63.0% | 1.0 ms |
| Spec 7.3 rules as written (prototype) | 81.9% | 86.5% | 83.2% | 95.9% | 40.6% | 55.6% | 0.02 ms |
| Apple ICU `toLatin` + casual pass + final schwa | 79.4% | 83.9% | 80.0% | 100% | 28.1% | 48.1% | 0.1 ms (Swift) |
| sanscript 2.3.82 IAST + casual pass + final schwa | 79.4% | 83.9% | 80.0% | 100% | 28.1% | 48.1% | 0.04 ms |
| uroman 1.3.1.1 | 47.1% | 78.7% | 51.0% | 95.9% | 12.5% | 33.3% | 0.45 ms |
| unidecode (baseline) | 43.2% | 76.8% | 47.1% | (n/a: drops all vowels) | 21.9% | 18.5% | 0.01 ms |
| IndicXlit indic2en v1.0 (beam 4) | 32.3% | 69.7% | 40.0% | 100% | 53.1% | 25.9% | **217 ms** |
| epitran 1.35.3 hin-Deva (IPA) + casual map | 58.1% | 60.6% | 59.4% | 18.4% | 62.5% | 11.1% | 0.09 ms |
| ICU `toLatin` + strip diacritics (spec 7.2 probe) | 50.3% | 51.0% | 51.0% | 0% | 3.1% | 3.7% | 0.1 ms (Swift) |
| sanscript ITRANS raw | 49.7% | 50.3% | 50.3% | 2.0% | 9.4% | 11.1% | 0.04 ms |

Dev set (107 lines, 544 words; the v2 fixes were found on it, so v2's dev number is optimistic): v2 81.2% exact / 94.3% normalized / 93.9% medial schwa; Aksharamukha colloquial 73.2% / 89.7% / 83.5%; spec 7.3 as written 77.4% / 90.6% / 79.1%; ICU + casual + final 72.1% / 85.5% / 54.8%; IndicXlit 27.2% / 64.2% / 59.1%; ICU stripped 49.6% / 59.4% / 40.9%. Full tables: `gold*/bakeoff-detail.json` and the harness output.

Example (held-out, "पर अब जो होता है वो पहले ना होता था", gold "par ab jo hota hai vo pehle naa hota tha"): v2 "par ab jo hota hai woh pehle na hota tha"; Aksharamukha "par ab jo hota hai vo pahle na hota tha"; ICU stripped "para aba jo hota hai vo pahale na hota tha"; IndicXlit "parr abb joe hotaa haye voe pahale naa hotaa thaa".

### 5.4 What each candidate is (licence noted only for the record; the owner ruled it no object)

- **IndicXlit** (AI4Bharat, MIT, `ai4bharat-transliteration` 1.1.3): a fairseq transformer; the Indic-to-English direction was trained on names and dictionary pairs, so it anglicises ("ray", "joe", "leey", "humsuffer"). Worst useful accuracy, 217 ms/line, 130 MB checkpoint plus PyTorch, peak RSS 489 MB on this Mac (V). In-app it would need a Core ML conversion of a fairseq beam-search decoder (encoder and decoder exported separately, beam search re-written in Swift; U effort, days) for a model that loses. Its checkpoint also needed `torch.serialization.add_safe_globals([argparse.Namespace])` to load with PyTorch 2.14's safe loader. **Out.**
- **Aksharamukha** (AGPL-3.0, pure Python, 2.2 MB, 2026-08): the best off-the-shelf engine; its `RemoveSchwaHindi` pre-option (`PreProcess.py:988`) is a regex schwa-deletion pass with a useful idea worth porting: keep the final schwa after a consonant cluster only when the cluster rises in a sonority pyramid (`[यरलव] < [नमण] < [शषस] < stops`), so "दर्द" and "फ़र्क" end "dard", "farq". In-app it needs an embedded CPython (Python.framework, roughly 30-60 MB, U) or a JS port in JavaScriptCore (no official JS build, U). Second place; used as the reference implementation, not shipped.
- **indic_transliteration / sanscript** (MIT, Python and a JS build): scheme tables only, no schwa deletion (V, re-confirms spec 7.2). Usable as the consonant/matra table reference.
- **Apple ICU** (`String.applyingTransform(.toLatin)`, system, 0 bytes, 10 ms for 107 lines in Swift (0.1 ms/line)): ISO-15919-like; with the casual pass and final-schwa drop it reaches 84% normalized but cannot do medial schwa (28%); as a base for our rules it adds nothing a 60-entry table does not.
- **uroman** (ISI, Python), **unidecode**, **epitran** (MIT, G2P to IPA with partial schwa deletion): niche candidates checked for completeness; all below ICU-plus-pass on lines fully right.
- **Google Dakshina** lexicon: kept as the spec's local oracle (spec 16.5), not run here (U).

### 5.5 The winner: a native Swift rule engine (V on held-out data; Swift port U)

`tools/bake.py` `segue_rules_v2` is the spec 7.3 algorithm with these changes, each a generic rule (no song-specific entries):

1. ड़ -> "d", ढ़ -> "dh" (casual "thodi", "chhode", "dhadkan", "badha"); spec says "r", "rh".
2. Medial schwa: a proper right-to-left pass (delete the inherent "a" in V C _ C V when the next syllable keeps a vowel, then skip one syllable so no three-consonant cluster forms). The spec 7.3 text's rule as prototyped scored 40.6% on held-out medial-schwa words; this pass scores 87.5% ("karna", "marne", "sakte", "dhadkan").
3. Casual "ah" -> "eh" before a consonant or word end ("pehla", "kehti", "reh", "mehka", "gehra").
4. Override list as specced, plus "हम" -> "hum".

Remaining held-out errors (7 of 155 words): final clusters ("darda", "farka": port Aksharamukha's sonority rule, item 5 to add), "achchhe" vs "acche" (casual writes च्छ as "cch"; add the rule), "hamasfar" (medial schwa across a nukta cluster), "jaaega" vs "jaayega" (casual inserts "y" between vowels: add), "woh" vs "vo" (an override style choice, open question 10), "jammon" (anusvara before म).

**Integration**: `Romanization/HindiRomanizer.swift` in `SeguePersonalModules`, pure Swift on `Unicode.Scalar`s, about 300-400 lines plus the table, no dependency, no runtime, no model: microseconds per line, zero memory concern on the 8 GB MacBook Neo, deterministic, and table-driven tests per spec 15.1. Port the Python prototype rule for rule, run the same 134-line gold through `make eval-import` (gitignored data), and keep the held-out set out of tuning. Target (spec 16.3): >= 90% word agreement; v2 already measures 90.3% exact and 95.5% normalized on held-out, so propose the target as **>= 90% exact and >= 95% normalized on a held-out set** (open question 9).

## 6. Open questions for the owner (each with a recommendation)

1. **Fold the reversed WebKit rule into the spec** (spec 8.2 / 8.6 / 10)? Recommend yes: hidden WebKit allowed for pages and searches the owner asked for; still no captcha solving, no clicking challenge widgets, no retry loops beyond the 12 s wait, and the honest UA stays on plain requests.
2. **robots.txt and in-app search.** UG disallows `/search.php`, E-Chords disallows `/search` and `/api/`. robots.txt governs crawlers; one search the owner typed is a browser-like user action. Recommend: in-app user-initiated searches may use them (one request per search, paced), the corpus collector (spec 16.1) still honours robots.txt, and the spec says so explicitly.
3. **UG route.** (a) web `search.php` and tab pages via `URLSession`, WebKit fallback; (b) the signed mobile API (Tabs-Lite route); (c) both. Recommend (a): verified working, no impersonation of UG's app, no reverse-engineered key; (b) as a research ticket only if (a) starts failing.
4. **Persistent cookie store for the hidden view.** Recommend a dedicated `WKWebsiteDataStore(forIdentifier:)` with a fixed UUID, persistent, with "Clear site data" in Settings > Advanced (Personal). The measurement shows an ephemeral store gets re-challenged.
5. **"Open here" for a challenged page**: show the same web view in a visible sheet so the owner completes the check himself (then hidden loads pass on that cookie). Is that inside "no captcha solving"? Recommend yes (a human solving it is not the app solving it), as a third action beside Open in Safari and Paste the Page Instead.
6. **Chordie search**: it is currently weak (5 hits, misses exact titles) and Chordie re-hosts other sites' charts. Recommend: keep Chordie in the all-sites search but collapsed by default and ranked last among chord sources, re-evaluated by the import canary; URL import of Chordie pages unchanged.
7. **Group order** in the all-sites results. Recommend fixed: UG, E-Chords, Chordie, LRCLIB lyrics (chords first, lyrics as the fallback), not reordered by score, so muscle memory holds.
8. **Show UG tab-only versions** in search? Recommend shown in a song's version list, greyed with "Tab", not importable (spec Q14 refusal kept); Pro, Official and marketing entries hidden entirely.
9. **Romanizer target** (spec Q12): recommend >= 90% exact and >= 95% RomanNormalizer-equivalent word agreement on a held-out gold set never used for tuning, with the dev/held-out split kept in the gitignored corpus.
10. **Override spellings style**: the spec's overrides use "woh", "nahin", "kyun", "hain"; LRCLIB contributors mostly wrote "wo"/"vo", "nahi". Which does Ryan type? Recommend asking him for his spelling of ~20 function words once, and using those (they only affect generated text, never pasted text).
11. **Singer for UG film songs**: use `recording.recording_artists` (code-found structured data) as the artist credit when UG's artist is a "Misc ..." placeholder? Recommend yes (R174 holds: code, not model).
12. **Romanizer engine**: native Swift rules (recommended) vs embedding Aksharamukha in CPython. Recommend Swift rules: better measured accuracy, no runtime, and Aksharamukha stays the reference for the sonority rule.
13. **HTML parser**: SwiftSoup 2.14.3 pinned exactly (recommended) vs `XMLDocument`, which lost data silently on 2 of 6 real pages.
14. **LRCLIB 503 policy**: up to 3 automatic retries on 503 (Retry-After plus jitter, sequential) instead of the spec's one. Recommend yes.
15. **Ad and tracker blocking in the hidden view** (`WKContentRuleList`). Recommend yes, measured in P9-4a (U benefit), because it lowers time and memory and keeps the owner's import traffic from feeding ad networks.

## 7. Method notes and caveats

- WebKit numbers come from an unsandboxed command-line probe with `.prohibited` activation policy; the Personal app will run sandboxed and may be frontmost, which can change the challenge outcome (U). The challenge escalation on E-Chords appeared after ~10 loads in 15 minutes of probing, so real single-song use should see the clean case more often (U).
- The probe's WebKit data (`~/Library/WebKit/wkfetch`, `~/Library/Caches/wkfetch`, `~/Library/HTTPStorages/wkfetch.binarycookies`) was moved to the Trash after the run.
- Scratch environments (Python 3.12 venv with the candidates, a Python 3.10 venv with IndicXlit and PyTorch, the SwiftSoup bench package) live in the session scratchpad only; nothing was added to the project's dependencies.
