# P9-4 - Lyrics search and URL import (Personal build only)

Phase 9 workstream (written 2026-10-31). Rulings: `docs/release/decisions.md` **R176** (v1.0 builds "LRCLIB lyrics search and URL import (Personal build only, so absent from the App Store build) ... each specced with its open questions closed first") and **R179** (this spec's questions closed, section 21: Ultimate Guitar search, one search across four sources, the hidden WebKit loader, components picked by a bake-off), **R182** (the bake-off's questions closed: components, Chordie for URL import only, the fixed group order, chord versions only, the romanizer's location and targets, LRCLIB retries) and **R183** (challenge pages and Ultimate Guitar ranking: Open Here, the loader rules, the Private Access Token spike, the per-song rating prior). Built on: **R133** / **R138** / **R170** (the feature itself: LRCLIB search plus URL import in `SeguePersonalModules`), the Phase 5 rulings in `docs/decisions.md` (package is a folder in this repo; sites are Ultimate Guitar, E-Chords, Chordie plus a generic page reader; enforcement is mechanical, not repo separation), the Language rulings in `docs/decisions.md` (English plus romanized Hindi only, no Devanagari display, no auto-transliteration of pasted text, app-generated Hindi in casual Bollywood romanization, the lyric preservation guard, autocorrect off in lyric text), **R62** / **R97** (the package already holds Settings > AI > Advanced), **R74** / **R98** (paste analytics, `romanHindi`), **R101** / **R121** / **R124** (code wins over the model; the strict lyric guard), **R117** (review sheet design D1), **R109** (nothing about paste or import may disturb a running show), **R154** / **R158** P8-1 Q8 / **R163** (the near-duplicate check and its `nearDuplicate` flag), **R157** / **R163** / **R164** (`RomanNormalizer`), **R172** / **R173** (several artists split from credit lines; Movie / Album as `{album}`; no song length), **R174** (artists come from code only), **R113** (test budget), **R39** (design directions before new UI), **R11** / **R139** (two bundle IDs; App Store only distribution, so the Personal build never ships).

This doc **replaces `docs/phases/5-personal-modules.md`**, which is now a pointer here. Everything in it that still holds has moved into this spec; its section 4.1 (Devanagari romanization research) is re-verified and updated in section 7 below.

**Build order:** three sessions (section 19). **P9-4a** starts first, with the Private Access Token spike as its first step (a0, R183), then corpus, plugin contract, fetcher, page parsers and eval; it touches SegueCore only at `Plugins/` and one `Ingest` entry point. **P9-4b** (LRCLIB, Hindi romanizer) may run beside P9-4a once P9-4a's contract step (step a2) has landed. **P9-4c** (UI, analytics, absence checks, guide, E2E) follows both. Section 21's questions are closed by R179, R182 and R183. **The bake-off (`docs/research/phase9-import-bakeoff.md`) and the prior-art survey (`docs/research/phase9-import-prior-art.md`) are done** (2026-11-01): section 4.4 lists the components they picked, and the techniques they recommend borrowing are folded into sections 6-9, each cited to its source.

## Session rules (apply to every session)

- `cat` and `ls` are aliased to eza and can hang: use `command cat` / `command ls` or the Read / Grep / Glob tools, and pass this warning to any subagent. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-". Ignore `.build/`.
- Sibling Phase 9 workstreams edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, stage only your own hunks, keep the tree compiling between steps.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget (R113): per step only targeted in-process suites (`swift test --filter <Suite>`); tricky pure logic (each parser, the generic reader, the romanizer, query variants, the pacer) gets table-driven in-process tests; UI behaviour gets in-process SegueUI tests. Exactly **one** new XCUITest class (section 15.4) plus one new method in the existing App Store UI target (section 15.5). At the end of each session ONE `make quick`, plus ONE `make e2e-one` per UI test class the session added or changed. No `make gate`, no `make check`, no E2E retry loops (a failure is investigated, not re-run), no scratch-worktree builds. Every build or test runs under `lockf -k .build/make.lock`. Write this budget into any subagent's prompt.
- **No live network in any test.** Every test reaches the network only through an injected transport fed from saved fixtures (section 15). The only code allowed to touch the real network is the shipping `URLSessionTransport` and the manual tools in section 16.4, which are never part of `make quick`, `gate` or `check`.
- Corpus collection (section 16.1) fetches public pages politely: robots.txt honoured (the collector is a crawler) except for the 20 search pages the search readers need, which R184 allows, one request per 5 s per host, a cap per site, and **never any captcha-solving** (none in the app either: the app never clicks a challenge, 8.6). A page blocked to plain requests may be loaded through the app's hidden WebKit loader (8.6); if that is challenged too, Ryan completes the check with Open Here or saves the page from Safari.
- Copyrighted lyrics are never committed (the `research/phase3-eval/pastes` precedent in `.gitignore`). Full fetched pages live in a gitignored folder; committed fixtures are redacted (section 16.2).
- Before using any Apple API not already in the codebase (for example `WKWebView`, `WKWebsiteDataStore(forIdentifier:)` and `removeData(ofTypes:modifiedSince:)`, `WKPreferences.inactiveSchedulingPolicy`, `WKContentRuleListStore`, `callAsyncJavaScript` in a `WKContentWorld`, the `WKNavigationDelegate` frame policy, `URLSessionConfiguration.ephemeral` details, `NSItemProvider` URL drops), run the `apple-api-check` skill.
- Read the `macos-app-architecture` skill before adding the test target, the dependency or any file to `Packages/SeguePersonalModules`.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency, including any case section 21's closed questions do not cover.

## 1. Goal

Ryan finds a song he wants to play. Today he opens the chord site in Safari, selects the page, copies, and pastes it into Segue, which converts it. After P9-4, in the Personal build only, he can:

1. **Search once across Ultimate Guitar, E-Chords and LRCLIB** ("tum hi ho arijit"), with the results grouped by source in that fixed order (R179, R182). Ultimate Guitar is a first-class source: only its chord versions of a song are listed, ranked by a vote-weighted rating, each has a preview, and he picks one, reviews it and imports it. E-Chords results work the same way; Chordie is not searched (its own search is weak today, R182), but its pages import by address; an LRCLIB result gives the plain lyrics as a starting point, already split into sections where the repeats show, with title, artists and Movie / Album filled from the record. Hindi text a source holds in Devanagari arrives in casual Latin romanization ("tum hi ho", "pyaar"), never in Devanagari.
2. **Paste or type a page address** (or drop a link from Safari, or import a saved page file) and Segue reads that one page with a parser made for that site (Ultimate Guitar, E-Chords, Chordie) or a generic reader for any other page, and opens the usual review sheet. A page blocked to plain requests loads through a hidden in-app WebKit view (no captcha-solving); when a page asks for a human check, **Open Here** shows that view in a sheet so Ryan completes the check himself, beside Open in Safari, a saved page and Paste the Page Instead (R179, R183).

Nothing is saved without the review sheet's Accept, exactly as for a paste. The App Store build contains none of this: no code, no menu item, no strings naming the services, checked by `make verify-appstore`.

**In scope:** the plugin contract in SegueCore `Plugins`; one `Ingest` entry point that accepts fields a source already knows; the one search across three sources (Ultimate Guitar, E-Chords, LRCLIB) with Ultimate Guitar's ranked chord versions and previews (sections 6.9-6.11); the page fetcher in the sandbox, the hidden WebKit loader with its persistent cookie store, Open Here and the per-site back-off (8.6, 9); the Private Access Token spike (step a0); the three site parsers and the generic reader; LRCLIB search and fetch with romanized-Hindi query variants and local re-ranking; the deterministic Devanagari romanizer; pacing, retries and in-memory caching; the UI entry points (File menu, the empty library, the New Song sheet, a lone pasted URL, a dropped link, a saved web page file); the review sheet's source line and attribution; analytics (Personal only, closed vocabulary); the `verify-appstore` extension; a fixture corpus of real pages and an offline parse-accuracy eval with targets; a manual parser canary; the in-product help and a draft guide page.

**Out of scope:** a Share extension (R179); search-as-you-type (R179: search runs on Return); a public guide page (R179); storing the source URL (R179); captcha-solving of any kind: the app never clicks, solves or injects into a challenge (R179, R183; Open Here shows it to Ryan, 8.6); the signed Ultimate Guitar mobile API (R182); searching Chordie (R182: its pages still import by address); publishing or flagging lyrics to LRCLIB; synced-lyrics timing in the song (R172 removed song length; LRC timestamps are only a sectioning hint, section 6.6); any change to the App Store build's behaviour; Devanagari handling of pasted text (stays exactly as pasted, per the Language rulings); batch import of many URLs.

**Unchanged:** the paste flow, the review sheet's design (R117) and its Accept / Cancel / Start blank semantics; the deterministic `IngestPipeline` stages and `JunkRules`; the lyric guard; artists from code only (R174); the near-duplicate score and threshold; `RomanNormalizer` (no version bump, so no index rebuild); the entitlements of both flavours.

## 2. Decisions this spec is built on

| Ruling | What it fixes here |
|---|---|
| R176 | In v1.0, Personal build only, absent from the App Store build. |
| R179 | Ultimate Guitar search with ranked versions and previews; one search across UG, Chordie, E-Chords and LRCLIB grouped by source (narrowed by R182 to UG, E-Chords and LRCLIB); a hidden WebKit loader for blocked pages (no captcha-solving), Open in Safari or a saved page as the fallback; licence no object for the Personal build, components picked on quality by the bake-off (4.4); the remaining choices in section 21. |
| R182 | The bake-off's choices (4.4): SwiftSoup 2.14.3 pinned exactly; the native Swift romanizer in `SeguePersonalModules` with the long override spellings and its accuracy targets (7, 16.3); UG's website routes, not the mobile API (6.10); Chordie for URL import only; groups fixed as UG, E-Chords, LRCLIB; only chord versions listed; UG "Misc" singers from structured credits (5.4); robots.txt does not limit searches and loads the owner starts (10); LRCLIB 503 retries (9); ads and trackers blocked in the hidden view (8.6). |
| R183 | Open Here for a challenged page; the loader rules (main-frame-only navigation, one-hour per-site back-off, cold-store warm-up, `cType` early stop; 8.6, 9); the Private Access Token spike first (step a0); UG versions ranked with a per-song scaled prior (6.10). |
| Phase 5 (`docs/decisions.md`) | Package location `Packages/SeguePersonalModules`; sites UG, E-Chords, Chordie, generic; absence enforced mechanically. |
| Language (`docs/decisions.md`) | No Devanagari display; app-generated Hindi in casual romanization; no auto-transliteration of pasted text; lyric guard; autocorrect off in lyric text. |
| R74 / R98 | Paste analytics row 19 and its `romanHindi` flag; the closed vocabulary rules. |
| R101 / R121 / R124 / R174 | Code-found fields win; the model labels only unheaded blocks; strict lyric guard; artists never from the model. |
| R109 | During a show no route opens the review sheet; these entry points are disabled with the existing reason. |
| R117 | The review sheet stays design D1; this spec adds one source line to its header and nothing else. |
| R154 / R158 Q8 / R163 | Near-duplicate warning beside the card, never blocking; `nearDuplicate` flag on song-created events. |
| R172 / R173 | Artists split on ",", "&", "feat.", "ft.", "featuring" in credit lines and headers (a source's artist field is a credit), never "and"; Keep as one in the review; Movie / Album is `{album}`; no song length anywhere (LRCLIB's `duration` is never stored). |
| R113 | Test budget. |
| R39 | 2-3 design directions before the new search sheet is built (step c0). |

## 3. Current code (verified 2026-10-31)

### 3.1 Plugin seam and flavours

- `Packages/SegueCore/Sources/Plugins/PluginRegistry.swift:9-20`: `Plugin` (id, displayName), and `SongImporter` / `LyricsSource` as empty marker protocols ("phase 5 adds their real requirements"). `PluginModule.register(into:)` at :23-26. `PluginRegistry` at :29-62 is a `Mutex`-guarded list with `registerAll(_:)`, `register(_:)` and two getters.
- `Packages/SeguePersonalModules/Sources/SeguePersonalModules/PersonalModules.swift:5-9`: `PersonalModules.register(into:)` registers nothing.
- `Packages/SeguePersonalModules/Package.swift:16-39`: one target, depends on SegueCore, SegueUI, SegueAI and SegueAIEval; **no test target**; strict settings (Swift 6, `ExistentialAny`, warnings as errors).
- `App/Sources/SegueApp.swift:11-13` imports `SeguePersonalModules` under `#if SEGUE_PERSONAL`; :28-29 builds the registry and registers `pluginModules`; :238-244 `pluginModules` is `[PersonalModules.self]` in Personal, `[]` otherwise. **The registry is never passed to SegueUI**: nothing reads `songImporters` or `lyricsSources` today. Note: the old phase 5 plan said "no `#if PERSONAL` in shared code, one `PersonalPlugins.swift` in the Personal target only"; the as-built code uses `#if SEGUE_PERSONAL` in the shared app sources instead (Project.swift compiles `App/Sources/**` into both targets). This spec keeps the as-built pattern: the flag appears only in the App target's composition code (`SegueApp.swift`, `ServicesWiring.swift`), never in a package.
- `App/Sources/SegueApp.swift:112-124`: the existing precedent for Personal-only UI: `ai.advancedSection` is a `(@MainActor () -> AnyView)?` filled under `#if SEGUE_PERSONAL` with `AdvancedModels.section(...)`; `Packages/SegueUI/Sources/SegueUI/Settings/AISettingsView.swift:54` shows it when non-nil (`AppModel+AI.swift:57`).
- `Project.swift:163-206`: `appTarget(name:personal:)`; only the Personal target appends `.external(name: "SeguePersonalModules")` and `SEGUE_PERSONAL` (:203-206). Both targets set `ENABLE_APP_SANDBOX` and `ENABLE_OUTGOING_NETWORK_CONNECTIONS` (A61).
- Entitlements: `App/Segue.entitlements`, `App/Segue-Debug.entitlements` and `App/SegueAppStore.entitlements` all already carry `com.apple.security.network.client` (for the hosted services, R23 / A61). **No entitlement change is needed**, and none may be made: the App Store set is asserted exactly by `scripts/verify-archive.sh` check 4 and `scripts/lib/verify-common.sh` `app_entitlements`.

### 3.2 The App Store absence check

- `scripts/verify-appstore.sh:54-120` `check_personal_free`: build graph, intermediates, link map, every bundle file's bytes (`grep -r -l -a -E "$forbidden"` at :101), `nm` and `otool -L` of every Mach-O. :195-208 runs it for Release-AppStore and Debug-AppStore, plus the Quick Look checks and entitlements.
- `scripts/lib/verify-common.sh:11`: `forbidden='SeguePersonalModules|PersonalModules|SEGUE_PERSONAL|AdvancedModels|AIEval'` (case-sensitive `grep -E`).
- Strings that would collide with new forbidden patterns, checked today: `Ingest/JunkRules.swift:26` contains "ultimate guitar app" (with a space) and `Ingest/MetadataExtractor.swift:283` mentions UG's "Misc " placeholder artist in a comment; many core files contain `inlineChords`, so a bare `echords` pattern would false-match. The comments in `PluginRegistry.swift:6,10,19` name LRCLIB, but comments never reach the binary. Section 13 picks patterns that cannot collide.

### 3.3 The paste and import pipeline

- `Packages/SegueCore/Sources/Ingest/IngestPipeline.swift:8-57` `ingest(_:origin:)`: Normalizer, bracketed chords, FormatDetector, blocks, Segmenter hints, roles, repeat labels, `MetadataAssembly.extract`, then `assemble` (:60-87: render, parse, validate, key inference, refinement questions). Already-ChordPro text is passed through (:19-21).
- `Ingest/IngestTypes.swift:8-12` `IngestOrigin`: `.paste`, `.file(extension:)`. `:217-237` metadata has `album`.
- `Ingest/MetadataAssembly.swift:147-160`: a credit-line or header artist is split with `ArtistNames.split` and the split recorded in `artistSplits`; an `{artist}` directive stays whole. `:77-82` emits one `{artist: }` per artist and `{album}`.
- `Packages/SegueCore/Sources/ChordPro/ArtistNames.swift:23-53` `split(_:)` (never "and", "x", "with", "/"); `:142` `ArtistSplit`.
- `Ingest/MetadataExtractor.swift:275-290` `isPlausibleName`: rejects chord-only text, capo/tuning notes, UG's "Misc ..." placeholder artist, site names, inline chords, legends, tunings and tab. `IngestPipeline.isPlausibleName` (:91-93) is the public door.
- `Ingest/Refinement.swift:21-56` `apply(_:to:)`: labels only for unheaded blocks; a title only where code found none; artists never (R174, comment at :10); a model key only as a suggestion; line classes only for unknown lines; then the per-block and combined lyric guard (:59-125, R124).
- `Ingest/RomanizedHindi.swift:11-38`: detection only (marker words), for the `romanHindi` flag; "nothing is transliterated, translated or respelled".
- `Packages/SegueCore/Sources/Library/RomanNormalizer.swift:18-80`: the search normal form (version 5 at :23; vowel-length folding, w/v, z/j, q/k, ph/f, doubled letters, aspiration, `ie`, final `n`, short-word `ei`/`ae` at word end) plus `loose(_:)` for vowel quality.
- `Packages/SegueCore/Sources/Library/NearDuplicates.swift:10-151`: `NearDuplicateIndex`, `threshold = 0.72` (:44), `match(title:artists:lyrics:contentHash:)` (:112-149) over `RomanNormalizer.loose` titles, artist forms and lyric shingles; `identical(contentHash:)` (:151).

### 3.4 The review sheet and its routes

- `Packages/SegueUI/Sources/SegueUI/Paste/LibraryViewModel+Paste.swift:14-23` `pasteUnavailableReason` / `canPaste` (R109); :26-33 `beginNewSongFlow()` (input state); :38-46 `beginPasteReview(text:source:)`; :60-77 `acceptPasteReview()` (records `songCreated(.newSong, nearDuplicate:)` when the review has no import method); :107-143 `importWithReview(_:method:)`; :203 `makeReview(...)`.
- `Paste/PasteReviewItem.swift:30-90`: one item, built from `IngestPipeline.ingest(original, origin:)` at :83, `RomanizedHindi.isDetected` at :90; near-duplicate state at :56-65 and `refreshNearDuplicate()` at :106; artist splits and Keep as one at :190-215.
- `Paste/PasteReviewModel.swift:43-77` holds the AI `Router`; :173-190 refines items one at a time.
- `Paste/PasteReviewSheet.swift:13-29` `PasteReviewContext`; :218-293 `PasteInputView` ("Paste or type a song", 640 x 440, `.autocorrectionDisabled()`, a multi-line paste into an empty area goes straight to review).
- `App/AppModel+Paste.swift:21-50`: File > New Song and New Song from Clipboard.
- `App/Commands/FileCommands.swift:16-46`: New Song, New Song from Clipboard, Import Songs..., Export Library Archive... (shown only when its hook is set: the precedent for optional menu items), Show in Finder, Move to Trash.
- `App/MenuShortcuts.swift:91-157`: the one shortcut table (New Song Cmd-N, from Clipboard Opt-Cmd-V, Import Songs Shift-Cmd-I, Add Song by Name Cmd-L, ...). Shift-Cmd-U and Shift-Cmd-L are free.
- `Library/LibraryViews.swift:203-210` `pasteFromEmptyState()`; :250-280 the empty library: "No Songs Yet", buttons Paste a Song, New Song, Import Songs..., and "How to bring songs in".

### 3.5 Analytics

- `Packages/SegueCore/Sources/Services/AnalyticsEvent.swift:3-95`: the closed vocabulary (rows 1-30; no `String` anywhere; signal names `Segue.<Area>.<event>`; values match `^[A-Za-z0-9+<>._-]{1,24}$`). `SongSource` at :187-190 (`newSong`, `import`).
- `Services/AnalyticsEvent+AI.swift:7-56`: row 19 `Segue.AI.pasteFinished` (`PasteFinishedSummary`: source, provider, fallback, latency, outcome, correction, romanHindi) and `PasteSource` at :42-56.
- `Services/Ports.swift:9-16`: `AnalyticsSink` receives only rendered `AnalyticsSignal`s, which have no public initialiser: **a plugin cannot invent its own events**; any event it sends must be a core case. Section 12 therefore adds core cases whose values never name a site or service.
- Flavour: `SegueApp.swift:229-235` `flavor`; Personal reports to its own TelemetryDeck app (`Project.swift` `telemetryDeckAppIDPersonal`).

### 3.6 Live probes (2026-10-31, from this Mac)

- **Ultimate Guitar** tab page (`tabs.ultimate-guitar.com/tab/misc-soundtrack/aashiqui-2-tum-hi-ho-chords-1234996`, HTTP 200 to a plain request): the chart is JSON in `<div class="js-store" data-content="...">` (HTML-escaped). Path `store.page.data.tab_view.wiki_tab.content` holds the chart as `[Verse 1]` headers and `[tab][ch]Fm[/ch]\nHum tere bin[/tab]` markup; `store.page.data.tab` holds `song_name` ("Aashiqui 2 - Tum Hi Ho"), `artist_name` ("Misc Soundtrack"), `type` ("Chords"), `tonality_name`, `id` and `recording.recording_artists[].artist.name` (the singer, "Arijit Singh"); `tab_view.meta` holds `capo`, `tonality` and `tuning.value` ("E A D G B E"); `tab` has no `capo` key (bake-off 1.2, correcting this probe). **V**. The film songs' placeholder artist and "Movie - Title" song name are the norm for Bollywood on UG.
- **Chordie** song page (`chordie.com/chord.pere/<source host>/<path>`, HTTP 200): an aggregator that re-renders other sites' charts as `<div class="chordline">` lines with inline chords in `<span class="bracket">[</span><span class="relc|inlc"><span class="absc Gm">Gm</span></span><span class="bracket">]</span>` and `<div class="textline">` for plain lines; the page title is "<Title> <Artist> Chords and Lyrics for Guitar". **V**.
- **E-Chords**: plain requests are hard-blocked (HTTP 403 "Sorry, you have been blocked", a Cloudflare WAF block, not a JavaScript challenge; bake-off 2.2), so every E-Chords request goes through the hidden WebKit loader (8.6). Through it the chart is verified (bake-off 2.2, **V**): a `<pre>` holding chords over lyrics with each chord as `<span data-chord="F#m">F#m</span>`, columns kept by spaces, inline `<b>(2x)</b>` and `<i>Intro:</i>`, tab blocks in a nested `div.tabs`; fields in JSON-LD `MusicComposition` and the inline `window.SONG_METADATA` object (`CAPO`, `CHORDS_KEY`, `ARTIST_NAME`, `NAME`, `TYPE`). A cold cookie store's song page met a managed challenge that did not clear in 25 s (2 of 2); the same page with the earlier clearance cookie loaded in 0.14 s (3 of 3).
- **LRCLIB** `GET /api/search` returned HTTP 502 from Cloudflare three times in a row (01:50 UTC on 2026-11-01, the evening of 2026-10-31 locally): a real outage case the UI must handle (section 6.8). On 2026-11-01 search answered, but about half of ~60 requests got HTTP 503 `ServerOverloaded` with `Retry-After: 1`, sometimes 4 in a row (bake-off 2.3): the retry policy of section 9. The API contract below is from its published docs.
- **Search pages** (bake-off 1.1, 2.1, 2.2, **V**): UG's `search.php?search_type=title&value=<q>` answers a plain request with the results as JSON in the same `js-store` element, at `store.page.data.results`, mixed with marketing rows (6.10); Chordie's `result.php?q=` returned 5 song hits a page and missed exact titles (so Chordie is not searched, R182); E-Chords' search page is a Vue app that calls the site's `/api/search` JSON (6.11).
- robots.txt: UG disallows `/search.php`, `/tab/print?`, `/tab/download` and similar but not `/tab/`; Chordie allows everything but one source path; E-Chords disallows `/search`, `/api/`, `/*/printversion` and similar. robots.txt governs crawlers: it does not limit a search or page load the owner starts in the Personal build (R182, section 10). Corpus collection honours these files except for the 20 search pages R184 allows (16.1).

## 4. Architecture

### 4.1 Where the code goes

```
SegueCore (both flavours)
  Plugins/            contract: SongImporter, SongSearchSource, value types, PluginRegistry (no implementations,
                      no site or service names in any string literal)
  Ingest/             IngestPipeline.ingest(_:origin:source:) - one new entry point (section 5.1)
SegueUI (both flavours)
  Paste/              generic hosting: PluginEntry list in AppDependencies, a source line in the review header,
                      new PasteSource cases routed like a paste
SeguePersonalModules (Personal only)
  Web/                HTTPTransport port, URLSessionTransport, PageLoader port (PlainPageLoader, WebKitPageLoader),
                      ChallengeDetector, ImportContentRules (ad and tracker block list), RequestPacer (with the
                      site back-off), PageCache, PageFetcher
  Web/Search/         UGSearchReader, EChordsSearchReader, VersionRanker
  Web/Parsers/        TabJSONParser (UG), ChordPreParser (E-Chords), ChordSpansParser (Chordie), GenericPageReader,
                      PageParserRegistry (host -> parser, then generic)
  Lyrics/             LRCLIBClient, LyricsQueryVariants, LyricsRanker, LRCSections
  Romanization/       HindiRomanizer + its table and override list (section 7)
  UI/                 WebImportField, SongSearchSheet (grouped results, preview pane), OpenHereSheet, the help popovers
                      (SwiftUI, uses SegueUI theme)
  PersonalModules.swift   registers WebPageImporter and the three SongSearchSources; returns the UI entries
Tests/SeguePersonalModulesTests   new target: fixtures, parser tables, eval scorer (offline)
```

- SegueUI never imports `SeguePersonalModules` (it cannot: the dependency points the other way, `Package.swift:24-27`). The personal package's views use SegueUI's theme and components.
- Third-party components are picked by the bake-off (section 4.4; R179: licence is no object in the Personal build, quality decides; R182: SwiftSoup is the only one). Each one adopted is declared in `Packages/SeguePersonalModules/Package.swift` only, pinned exactly, and imported only in the folder that uses it; a SwiftLint `custom_rules` entry per dependency fails its import anywhere else (the vendor isolation rule).
- Every file with a service or site name in a string literal lives in `SeguePersonalModules`. Core and SegueUI use neutral words ("web page", "lyrics search") in identifiers and copy that ship in the App Store build, and none of them is user-visible there.

### 4.2 The plugin contract (SegueCore `Plugins/PluginRegistry.swift` plus `Plugins/PluginTypes.swift`)

```swift
/// What a source already knows about the song, from structured data on the page or the
/// record (code-found, so it wins over anything the text parser finds: section 5.1).
public struct SourceFields: Sendable, Hashable {
    public var title: String?
    public var artistCredit: String?      // one credit string; split by ArtistNames.split (R172/R173)
    public var album: String?             // Movie / Album, written as {album}
    public var key: String?               // a stated key, parsed with SongKey(parsing:)
    public var capo: Int?
}

/// One page or record turned into text the ingest pipeline reads.
public struct ImportedSong: Sendable, Hashable {
    public var text: String               // chords over lyrics, inline [C]hords, ChordPro or bare lyrics
    public var fields: SourceFields
    public var provenance: Provenance
}

public struct Provenance: Sendable, Hashable {
    public var sourceURL: URL             // shown in the review header, never stored (R179)
    public var reader: ReaderKind         // analytics token, section 12
    public var fellBack: Bool             // a site parser failed its checks and the generic reader answered
    public var romanized: Bool            // Devanagari was romanized (section 7)
    public var loadPath: LoadPath         // .plain, .webKit or .savedFile (8.6)
    public var foundByContentSearch: Bool // the chart was found by the content-search fallback (8.4); the eval and canary report it
    public var attribution: String?       // e.g. "Lyrics from LRCLIB" - set by the plugin, shown in the header
}

public enum ReaderKind: String, Sendable, CaseIterable { case tabJSON, chordPre, chordSpans, genericPage, lyricsRecord }

public protocol SongImporter: Plugin {
    /// Cheap and offline: whether this importer takes the input, and which reader it will try.
    func accepts(_ input: ImportInput) -> ReaderKind?
    func importSong(_ input: ImportInput) async throws(ImportFailure) -> ImportedSong
}
public enum ImportInput: Sendable, Hashable { case url(URL), webPageFile(URL) }

public enum LoadPath: String, Sendable, CaseIterable { case plain, webKit, savedFile }

/// One searchable source (R182: Ultimate Guitar, E-Chords, LRCLIB). Replaces the
/// old empty `LyricsSource` marker.
public protocol SongSearchSource: Plugin {
    var group: SearchGroup { get }        // heading order in the results (6.9)
    func search(_ query: SongQuery) async throws(ImportFailure) -> [SearchCandidate]
    /// The chart or lyrics for one candidate, for the preview pane and then the review.
    func song(for candidate: SearchCandidate) async throws(ImportFailure) -> ImportedSong
}
public enum SearchGroup: Int, Sendable, CaseIterable { case tabJSON, chordPre, lyricsRecord }   // fixed order (R182)
public struct SongQuery: Sendable, Hashable { public var text: String; public var title: String?; public var artist: String? }
public struct SearchCandidate: Sendable, Hashable, Identifiable {
    public var id: String                 // the source's stable record or tab id, as text
    public var title: String; public var artist: String?; public var album: String?
    public var kind: CandidateKind        // .chords or .lyrics: tab-only, Pro, Official and ad rows never become candidates (R182)
    public var version: Int?              // a site's version number of this song ("ver 3")
    public var rating: Double?            // 0-5, as the site shows it
    public var votes: Int?
    public var firstLines: String?        // first 2 lines, romanized when needed, when the search returned them
    public var isInstrumental: Bool
    public var lyrics: String?            // full plain lyrics when the search already returned them (LRCLIB)
    public var pageURL: URL?              // the chart page, for Open in Safari
}

public enum ImportFailure: Error, Sendable, Hashable {
    case offline, timedOut, busy(retryAfter: Duration?), backingOff(retryAfter: Duration), blocked, challenged,
         notFound, notAPage, tooLarge, noChart, unsupportedScript, server(status: Int), cancelled
}
```

- `PluginRegistry` keeps its shape; the empty marker protocols gain these requirements. The `PluginModule` gains nothing: UI entries are composed in the App target (4.3).
- Every type is `Sendable`, and every async call is cancellable (`Task` cancellation maps to `.cancelled`).
- `ImportFailure` is closed: each case has one user message (section 8.7) and one analytics outcome (section 12). `blocked` is a hard block (a 403 with no challenge); `challenged` is a check still up after the wait of 8.6, the only case that offers Open Here; `backingOff` is the per-site back-off of section 9.

### 4.3 UI hosting (the `advancedSection` pattern)

- SegueUI gains `PluginEntries` in `AppDependencies`: `webImport: WebImportEntry?` and `songSearch: SongSearchEntry?`. Each holds the plugin (as `any SongImporter` / `[any SongSearchSource]` from the registry) plus `@MainActor` view builders that return `AnyView` for the personal package's sheet content, and its menu title and shortcut.
- `SegueApp.init` passes `plugins` through: under `#if SEGUE_PERSONAL` it calls `PersonalModules.entries(registry: plugins, ...)`; otherwise both entries are nil. UI code asks "is the entry non-nil?", never checks a build flag.
- With both nil (App Store) every entry point in section 11 is absent: no menu item, no button, no lone-URL banner, no drop target for links, no extra file types in the import panel.

### 4.4 Components (from the bake-off and the prior-art survey, R182)

Filled from `docs/research/phase9-import-bakeoff.md` (2026-11-01) and `docs/research/phase9-import-prior-art.md` (2026-10-31); R182 and R183 close their questions.

| Component | Used by | Choice | Why (measured) |
|---|---|---|---|
| HTML parser / DOM | `GenericPageReader`, the site and search readers (8.4, 6.10, 6.11) | **SwiftSoup 2.14.3** (MIT), **pinned exactly** (R182), imported only in `Web/`; used JSON-first (UG `div.js-store@data-content`, E-Chords JSON-LD and `<pre>`), the DOM walk for the generic reader. For `<pre>` text, walk the text nodes (`TextNode.getWholeText()`): `text(trimAndNormaliseWhitespace: false)` still lost newlines in one `<pre>` | Kept every one of 6 real pages intact at 2.8-10 ms each; Foundation `XMLDocument(.documentTidyHTML)` silently lost data on 2 of 6 (549 chars of a UG chart; an E-Chords `<pre>` cut to 11 chars at its nested `<div>`), which breaks the zero-silent-wrong-charts target (bake-off 4.1). Kanna and Fuzi wrap the same libxml2 parser |
| Devanagari romanizer | section 7 | **A native Swift rule engine**, `Romanization/HindiRomanizer.swift` in `SeguePersonalModules` (R182, closing Q6): spec 7.3 with the bake-off's four rule changes, the long override spellings (woh, nahin, kyun, hain), no dependency, no runtime, no model | On the held-out set (27 lines, 155 words): 90.3% word exact, 95.5% `RomanNormalizer`-equivalent, 87.5% medial schwa, 77.8% lines fully right, against Aksharamukha 76.1% / 93.5%, ICU plus a casual pass 79.4% / 83.9%, IndicXlit 32.3% / 69.7% at 217 ms a line (bake-off 5.3). Aksharamukha stays the reference for its sonority rule (7.3), not shipped |
| Blocked-page loader | 8.6 | The hidden **`WKWebView`** loader on a **dedicated persistent `WKWebsiteDataStore(forIdentifier:)`**, WebKit's own user agent, a `WKContentRuleList` ad and tracker block, the R183 rules, and Open Here | A persistent store with an earlier clearance loaded the E-Chords song page in 0.14 s (3 of 3); a cold ephemeral store stayed challenged for 25 s (2 of 2) (bake-off 3.1). About 250-330 MB while a view exists, zero once torn down |
| Site and search readers | 8.4, 6.10, 6.11 | **Built in-house**, informed by the prior art; no dependency adopted (no Swift package fits; prior-art section 3 item 1) | The closest prior art is `hampterworks/klank` (an import cascade ending in a hidden web view shown on an interactive challenge), with `kmille/freetar`, `ewiner/tabr`, `fwcd/d2`, `nlevin/fretz` and `eloygomes/new-LiveNLoud.app` for the readers and converter (prior-art 1.2-1.4). Their borrowed techniques are cited where they are used |
| Ultimate Guitar route | 6.10, 8.4 | **The website** (`search.php` and tab pages; plain `URLSession`, then the WebKit loader) (R182) | Verified working with an honest user agent (bake-off 1.1). The signed mobile API is not used: it needs UG's Android identity and a key derived from its binary, and it breaks silently on a key change (bake-off 1.3; prior-art 1.1) |
| Lyrics source client | 6.2 | The in-house **`LRCLIBClient`** (three GET routes; no dependency) | The API is unchanged; its 503s need the retry policy of section 9 (bake-off 2.3) |

Each adopted component gets its exact pin in `Packages/SeguePersonalModules/Package.swift`, one SwiftLint import rule and one `THIRD_PARTY_NOTICES.md` row ("Personal build only"; section 10): today that is SwiftSoup alone.

## 5. The shared pipeline

### 5.1 One ingest entry point for sources (SegueCore `Ingest/IngestPipeline+Source.swift`, pure)

`IngestPipeline.ingest(_ text: String, origin: IngestOrigin, source: SourceFields) -> IngestResult`, with `IngestOrigin` gaining `.web` and `.lyrics` (no associated values: the reader kind travels in `Provenance`, not in core's origin).

1. Run the existing `ingest(text, origin:)` unchanged.
2. Overlay the source's fields on `metadata`, field by field, **source first**: a source field that passes `isPlausibleName` (title) or `ArtistNames.cleaned` (artist) replaces the text-found value; a text-found value fills a field the source left empty. Directive fields already in the text (`directiveFields`) stay as written.
3. The artist credit goes through `ArtistNames.split` and is recorded in `artistSplits` exactly like a credit line (R173: a source's artist field is a credit, not an `{artist}` directive), so the review shows the chips and Keep as one.
4. `album` sets `{album}`; `key` sets `{key}` only when `SongKey(parsing:)` reads it (else it is dropped, never guessed); `capo` sets `{capo}` when 1-11.
5. Re-assemble (`assemble`), so the rendered text, document, validation and key inference all see the merged metadata.
6. `consumedLines`: a text line that repeats a source field verbatim (the page's own "Tum Hi Ho Chords by Arijit Singh" heading) is consumed as metadata, as `MetadataAssembly` does for a pasted header.

Already-ChordPro text (a page that serves ChordPro) is passed through untouched, and the source fields are then shown in the review as suggestions only, never written over the file's own directives (R109 spirit: ChordPro arrives byte-for-byte).

### 5.2 Into the review sheet

- `LibraryViewModel.beginSourceReview(_ song: ImportedSong, source: PasteSource)` opens the same `PasteReviewModel` with one `PasteReviewItem` built from `ingest(_:origin:source:)`. `PasteSource` gains `webPage` and `songSearch` (row 19).
- Guards are the paste guards: `canPaste` (R109: never during a show, never over an open review).
- Everything after that is the paste flow: original text on the left (for a web page, the extracted text, not the HTML), result on the right, sparkle marks for AI decisions, the draft card, Accept writes one undoable song, Cancel writes nothing.
- The header gains one quiet source line under the title (section 11.6).

### 5.3 Near-duplicate check (P8-1)

- The item's existing `nearDuplicates` / `refreshNearDuplicate()` runs on the reviewed text, as for any paste: warning beside the card, never blocking Accept, re-checked on edits, `nearDuplicate` flag on `songCreated` at Accept (R163).
- **Before fetching**, every search result row marks a result "In your library" when `NearDuplicateIndex.match(title:artists:lyrics:contentHash:)` over the candidate's title, split artist credit and, when the search returned them, its plain lyrics scores at or above the threshold. Without lyrics the row compares title and artist only through the same index (title similarity gate, then the artist score); the mark is a hint, the full check runs again in the review.
- The URL field does no pre-fetch check (the title is unknown until the page is read).

### 5.4 Several artists and Movie / Album (R172 / R173)

- Source credits split on ",", "&", "feat.", "ft.", "featuring", never "and" (`ArtistNames.split`), shown as chips with Keep as one.
- UG film songs: `TabJSONParser` maps the placeholder artist ("Misc Soundtrack", "Misc Unsigned Bands", any `Misc ...`) to no artist, and a `song_name` of the form "<Movie> - <Title>" to `album` = Movie and `title` = Title (split at the **first** " - " only when the artist is a `Misc` placeholder; otherwise the song name is the title as written). The singer then comes from UG's structured credits, `tab.recording.recording_artists[].artist.name` (code-found data, so R174 holds; R182; bake-off 1.2), the names joined as one credit and split as in 5.1 step 3; with none there, whatever the page text states, else empty: never invented. For the probe page: title "Tum Hi Ho", album "Aashiqui 2", artist "Arijit Singh".
- LRCLIB: `albumName` sets Movie / Album, unless it equals the title or is a generic value ("Single", "Unknown", empty).
- Chordie and the generic reader: title and artist from the page's structured data first (JSON-LD `MusicComposition` / `MusicRecording`, then `og:title`, then the `<title>` pattern "<Title> Chords by <Artist>" or Chordie's "<Title> <Artist> Chords and Lyrics"), each value checked with `isPlausibleName`.

### 5.5 AI refinement (R101 / R121 / R124 / R174)

- Runs exactly as for a paste, on the merged result: labels only for unheaded blocks, title only when neither the source nor the text gave one, never artists, never Movie / Album, a key only as a suggestion, line classes only for unknown lines, and the lyric guard on every block.
- For LRCLIB lyrics (bare lyrics, no chords) the model's only job is section labels for blocks the repeat labelling left unlabelled. A source title always exists, so the model never fills one.
- The romanizer's output is not a "correction": it runs before the review, deterministically, and the lyric guard then protects that text from the model like any pasted lyric.

## 6. Search: LRCLIB lyrics and the chord sites (R179)

### 6.1 The API (from `https://lrclib.net/docs.md`, fetched 2026-10-31) **V**

- Base `https://lrclib.net`. No key; anonymous access allowed. Clients must identify themselves with `User-Agent: <app name> <version> (<homepage or email>)`; `Lrclib-Client` or `X-User-Agent` where the header cannot be set.
- `GET /api/search?q=` (or `track_name`, `artist_name`, `album_name`; `q` wins): a JSON array of at most 20 records, no pagination.
- `GET /api/get/{id}`: one record. `GET /api/get?track_name&artist_name[&album_name&duration]`: best signature match (duration within 2 s); not used here (no song length exists to send).
- Record: `id`, `trackName`, `artistName`, `albumName`, `duration`, `instrumental`, `hasWordSync`, `plainLyrics` (null for instrumentals), `syncedLyrics` (LRC), `lyricsfile` (YAML).
- Rate limits (approximate, "may change at any time"): ~45 requests/min per IP for generic clients, **~90/min for an identified client**, ~180/min with a registered `Lrclib-App-Id`. Over the limit: HTTP 429 with `Retry-After` (seconds) and a JSON body naming the scope; clients **must** honour `Retry-After` plus up to 30% random jitter, or risk a temporary ban. 503 `ServerOverloaded` also carries `Retry-After` (usually 1 s). Edge rejections may not be JSON: rely on status and `Retry-After`, check `Content-Type` before parsing.
- Throttling guidance: send requests sequentially, 200-500 ms apart.
- Licence: the server code is MIT (`github.com/tranxuanthang/lrclib`, checked 2026-10-31). **No content licence or terms of use for the lyrics were found** (docs, `llms.txt`, `llms-full.txt`, a web search): the lyrics are crowdsourced and their copyright belongs to the rights holders. This is why the feature stays Personal (section 10).

### 6.2 The client (`Lyrics/LRCLIBClient.swift`)

- `User-Agent: Segue/<CFBundleShortVersionString> (+https://segue.ryandsilva.dev)`, plus `Lrclib-Client` with the same value (R179: API calls identify as Segue). No App-Id (R179: LRCLIB unregistered).
- Search: `GET /api/search?q=<query>` only (the free-text form handles "tum hi ho arijit"; the structured form is used for a variant only when the user filled the optional Artist field, section 6.4).
- Fetch: the search response already holds full records, so picking a result normally needs **no second request**; `GET /api/get/{id}` only when the search record had `plainLyrics == nil` but `instrumental == false` (a truncated or changed response).
- Decoding is tolerant: unknown fields ignored, missing optional fields nil, a non-JSON or non-array body is `.server(status:)`.
- All requests go through the shared `RequestPacer` (section 9) for host `lrclib.net`.

### 6.3 Romanized-Hindi search (the owner's rule)

LRCLIB's search is a server-side keyword match, so "tuj mai rab" may find nothing while "tujh mein rab" finds the song. Segue cannot change the server; it widens the query deterministically and ranks locally:

1. **Query as typed** first, always.
2. **Variants** (`Lyrics/LyricsQueryVariants.swift`, pure): when the first response has fewer than 5 results **and** the query is romanized Hindi (at least one word in `RomanizedHindi.markers` or the variant table), build at most **two** more queries by swapping each word for its most common attested spelling from a small hand-curated table keyed by `RomanNormalizer`'s normal form (for example normal form `mai` -> "mein", "main"; `tuj` -> "tujh"; `pyar` -> "pyaar"; `dil` -> "dil"; `kabi` -> "kabhi"; `nahi` -> "nahin", "nahi"). Variant 1 uses each word's top spelling; variant 2 the second where one exists. Words not in the table stay as typed. The table is data with tests (add words, never logic), shares its source words with the romanizer's override list (section 7.3), and is licence-clean (hand-curated).
3. **At most 3 queries per search**, sequential, paced, each with the 503 retries of section 9. A variant identical to an earlier query is skipped.
4. **Merge and rank** (`Lyrics/LyricsRanker.swift`, pure, with a per-result score breakdown for tests): results deduplicated by `id`, then by (loose title, loose artist); score = 0.55 x title similarity + 0.25 x artist similarity + 0.10 x lyric-start similarity + 0.10 x "has plain lyrics", where every similarity is computed on `RomanNormalizer.loose` forms with the same word-overlap measure `NearDuplicateIndex` uses for titles. The query's words are matched against title, then artist, then the first lyric line. Instrumental records sort last and cannot be picked.
5. **No AI anywhere in search**: no model rewrites the query or "corrects" a spelling. The user's text is sent as typed, the variants are deterministic and shown ("Also searched: tujh mein rab"), and nothing the user typed is changed in their field.

### 6.4 Search UI (exact behaviour; visual design from step c0)

- Sheet "Find Lyrics" (the menu name R179 fixes; it finds chord charts too), 960 x 600 with the results list on the left and the preview pane on the right (step c0 sets the layout). One search field (placeholder "Song title, artist or a line", focused, `autocorrectionDisabled()`, spell-check off, no smart substitutions) and an optional "Artist" field behind a disclosure, also with autocorrect off.
- Search runs on **Return** or the Search button only (R179). One Return queries all three sources (6.9); while running, a small spinner per group heading, previous results stay greyed. Cancel (Esc) cancels every request in flight.
- Results are **grouped by source** (R179), in the fixed order Ultimate Guitar, E-Chords, LRCLIB (R182: chord sources first, lyrics as the fallback, never reordered by score, so muscle memory holds), each under a heading with its count ("Ultimate Guitar · 6 songs") and its own status line when it failed (6.8), so one source down never hides the others. Chord-site groups list songs, each with its versions nested under it (6.10); the LRCLIB group lists lyric records.
- A row: title (bold), "artist - Movie / Album" (muted), and quiet marks "In your library" (5.3), "Instrumental" (disabled row), "Converted from Devanagari" (when the text needed romanizing, section 7); an LRCLIB row also shows its first two lyric lines (muted, small). Up/Down moves the selection; selecting a version or a lyrics row loads its **preview** in the right pane (the chart as it will import, after the reader and romanization, read-only, with its source line); Return or double-click, or the preview's Review button, opens the review. Under the LRCLIB group, when variants ran: "Also searched: <variant>, <variant>".
- Attribution at the foot of each group: Ultimate Guitar and E-Chords "Chords from <site>. Check them against the recording."; LRCLIB "Lyrics from LRCLIB, a free community database. Check them against the recording.", each with the site link (opens in the browser).
- Picking a result builds `ImportedSong` (for LRCLIB: text = the plain lyrics after romanization and `LRCSections`, fields from the record, provenance `lyricsRecord`; for a chord site: the page through its reader, 8.3) and replaces the sheet with the review sheet (one sheet at a time, like New Song's input state moving to review).

### 6.5 Devanagari results

A record whose `plainLyrics` (or title, artist, album) contains Devanagari letters (U+0900-U+097F) goes through `HindiRomanizer` (section 7) before it is shown or reviewed: the result row's first lines, the title and the lyrics. A record whose text contains any other non-Latin script (Arabic/Urdu, Gurmukhi, ...) beyond a few characters is shown disabled with "In a script Segue doesn't show" (`unsupportedScript`), because the Language rulings allow only Latin text.

### 6.6 Sections from bare lyrics (`Lyrics/LRCSections.swift`, pure)

- `plainLyrics` with blank lines between stanzas goes to the pipeline as is: blocks by blank lines, repeat labelling (R101) names repeated blocks Chorus, the model may label the rest.
- `plainLyrics` with **no blank lines** but `syncedLyrics` present: insert a blank line before any line whose LRC timestamp is at least **5 s** after the previous line's (an instrumental gap usually separates stanzas). Timestamps are used only for this and then discarded: no timing, duration or tempo is stored anywhere (R172).
- Neither: the text goes in as one block; the review shows it unlabelled, as a bare paste would.

### 6.7 What is written

The `.cho` gets `{title}`, one `{artist}` per chip, `{album}` when present, and the lyrics in sections. No chords (LRCLIB has none), no `{duration}`, no source line. The draft card's tags and proficiency work as for any paste.

### 6.8 Failure states (in the sheet, never an alert)

| Case | Message under the field | Action |
|---|---|---|
| No results after all variants | "No lyrics found for "<query>". Try the title only, or another spelling." | none |
| `offline` | "You're offline. Lyrics search needs the internet." | Try Again |
| 503 (`ServerOverloaded`) | retried automatically up to 5 times (section 9); meanwhile the group reads "LRCLIB is busy, retrying..." | Cancel; after the fifth retry fails, the `server` row |
| `busy(retryAfter:)` (429) | "LRCLIB is busy. Try again in <n> seconds." The Search button stays disabled until then. | automatic enable |
| `server` (5xx, 502 as probed) / `timedOut` (15 s) | "LRCLIB isn't answering right now." | Try Again |
| `unsupportedScript` | row disabled, as 6.5 | none |

Each message shows in its own group (6.4), naming that source ("E-Chords isn't answering right now."); the other groups are unaffected. For a chord-site group: a search that is `challenged` even through the WebKit loader (8.6) reads "<site> wants to check you're a person." with **Open Here** (8.6) and **Search in Safari** (opens the site's own search for the query); a hard `blocked` reads "<site> doesn't let apps search it right now." with Search in Safari; a site in its back-off (section 9) reads "<site> asked Segue to wait. Try again after 21:40." with Search in Safari.

### 6.9 One search across three sources (R179, R182)

- `SongSearchSource` (4.2) has three implementations: `UGSearchReader` (6.10), `EChordsSearchReader` (6.11) and the LRCLIB client (6.2-6.3). Chordie is not searched (R182, 6.11). Return runs all three **concurrently** (different hosts), each through the shared `RequestPacer` (section 9), and each group fills as its source answers.
- The romanized-Hindi variants of 6.3 apply to LRCLIB only (its server match is strict); the chord sites receive the query as typed. Nothing the user typed is changed anywhere.
- Per group at most 20 songs; within a group, songs keep the site's own order, then `LyricsRanker`'s title and artist similarity re-sorts them (the same scorer, without the lyric-start term for chord sites).
- Duplicates across groups are not merged: the same song from two sites is two charts, and the grouping is the point (R179).

### 6.10 Ultimate Guitar search (R179, R182, R183, `Web/Search/UGSearchReader.swift`)

- **Route** (R182): UG's website, never the signed mobile API. One request, `GET https://www.ultimate-guitar.com/search.php?search_type=title&value=<query>`, as a plain `URLSession` request (it answers 200 to the honest user agent today, bake-off 1.1); when it is challenged or blocked, the same URL once through the WebKit loader (8.6). The results are the JSON in `<div class="js-store" data-content>` at `store.page.data.results` (with `results_count` and `pagination` beside it). Through WebKit the `js-store` element is gone after hydration (bake-off 1.6), so the reader takes `window.UGAPP.store` first, wrapped as `{store: ...}` so one parser fits both shapes, then the server HTML from an in-page `fetch(location.href)` (prior-art 1.4 item 1: klank `ug_webview.rs:65-73`, georgexu99 `sheet-music-browsarr` `ultimate_guitar.rs:20-25`).
- **Rows kept**: only entries with an integer `id`, a `type`, and a `tab_url` on `tabs.ultimate-guitar.com/tab/`, which drops UG's marketing rows (`marketing_type`, `/pro/?app_utm_...` links; bake-off 1.1, the same filter as `dan-slater/mactabs` `tools/tab-import.py:137-142`). Then **only chord versions are listed** (R182): `type` "Chords" or "Ukulele Chords". Tab, Bass Tab, Pro, Power, Official and Video results are not shown at all; a pasted address of such a page is still refused with a clear message (8.4).
- Fields per result: `song_name` and `artist_name` (with the `Misc ...` rule and the structured singer credits of 5.4, from `recording.recording_artists`), `version`, `rating` (0-5), `votes`, `tonality_name`, `tab_url`, `song_id`.
- **Versions** of one song (same `song_id`) nest under one song row (the owner's parent/child rule): "Chords · ver 3 · ★4.8 · 1,204 votes", with the best version preselected.
- **Ranking** (`VersionRanker`, pure, with a per-version score breakdown that sums to the total; R183): a vote-weighted rating toward a mean of **4.0** (UG's ratings cluster high), `score = v / (v + k) x rating + k / (v + k) x 4.0`, where the prior's weight `k` is set **per song**: the median vote count of that song's listed chord versions, **clamped to 3-50**. A popular song's versions are judged mostly by their votes (k = 50 at most), and a new or less popular song whose versions have a handful of votes uses a small k, so its versions still rank by their own ratings instead of all collapsing toward 4.0. The mean, the clamp bounds and the median rule are named constants with table tests. Example (bake-off 1.1, "tum hi ho", five Chords versions with votes 39 / 833 / 50 / 14 / 23 and ratings 4.68 / 4.84 / 4.84 / 4.79 / 4.52): the median is 39, so k = 39, and the order is v2 (4.80), v3 (4.47), v1 (4.34), v4 (4.21), v5 (4.19). This replaces the fixed 50-vote prior this spec first had (prior-art 1.4 item 7: `ewiner/tabr` `TabSearchService.swift:160-165` uses k = 50 toward 3.5; the bake-off proposed k = 25 toward 4.0).
- Songs order by their best version's score after the similarity re-sort of 6.9. One results page per search (no page-2 request).
- The preview fetches the chosen version's page (one request, paced and cached, 9) and runs `TabJSONParser`. The review's source line reads "From Ultimate Guitar · ver 3 · ★4.8".

### 6.11 E-Chords search (R179, R182) and Chordie (URL import only)

- `EChordsSearchReader` goes **straight to the WebKit loader** (8.6): plain requests to E-Chords are hard-blocked (3.6), so a plain attempt would only waste a request. It loads the search page `https://www.e-chords.com/search-all/<query>` and, once it has loaded, calls the site's own JSON API from inside the page (`callAsyncJavaScript` in a separate `WKContentWorld`): `fetch("/api/search?q=<query>&songs_take=15&lyrics_take=1&artists_take=1&albums_take=1&videos_take=1&composers_take=1")`, where every `*_take` must be 1-30 or the API answers 422 (bake-off 2.2). This is faster and steadier than waiting 5-8 s for the rendered list. Song hits carry `TITULO`, `ARTISTA`, `COD_ARTISTA` and `COD_TITULO` (page `/chords/<COD_ARTISTA>/<COD_TITULO>`) and `QT_HITS`. When the JSON call fails, the reader falls back to the rendered `a.song-item[href^="/chords/"]` rows (`span.artist`, `strong.song`).
- E-Chords has no rating or votes, so `VersionRanker` is not used: hits with the same `RomanNormalizer.loose` title and artist nest under one song (bake-off 2.4), and songs keep the site's order, then the 6.9 similarity re-sort.
- E-Chords' robots.txt disallows `/search` and `/api/`; it does not limit this search, which is one request the owner started with Return (R182; section 10).
- Previews run `ChordPreParser` on the chosen page.
- **Chordie is not searched** (R182): in the bake-off its search returned 5 song hits a page with no pagination and missed exact titles ("tum hi ho" found none of the Tum Hi Ho pages; bake-off 2.1). Its pages still import by address through `ChordSpansParser` (8.4). No `ChordieSearchReader` is built.

## 7. Romanization (replaces phase 5 sections 4 and 4.1)

### 7.1 Rule

LRCLIB, and some web pages, hold Hindi lyrics in Devanagari. The app may not display Devanagari, and the Language rulings require text **the app itself generates** to be in casual Bollywood romanization without diacritics ("tum hi ho", "pyaar", "dil", "hai"). A deterministic `HindiRomanizer` converts it: no language model in the loop, so the output is reproducible and testable.

- It runs only on text Segue fetched (LRCLIB records and web pages, R179). **Pasted text is never transliterated** (Language rulings), and a pasted Devanagari song keeps flowing through the paste path unchanged.
- It touches only Devanagari runs. Latin text, including romanized Hindi and English in mixed lines, passes through byte-identical; digits, punctuation and spacing are kept.
- It never respells Latin words, never "corrects" a romanized Hindi word, and its override list only chooses how a Devanagari word is first written in Latin.
- The review shows "Converted from Devanagari" in the source line (11.6) so the user knows the spelling was generated, and can edit any word before Accept.

### 7.2 Research, re-verified 2026-10-31 on macOS 26.6.2

- **Apple ICU `.toLatin`** (local probe re-run today, `String.applyingTransform(.toLatin, reverse: false)`) is ISO-15919-like, exactly as the 2026-10-17 probe found: `तुम ही हो` -> "tuma hī hō", `चलते` -> "calatē", `आँखें` -> "ām̐khēṁ", `क्यों` -> "kyōṁ", `दीवाना` -> "dīvānā", `प्यार` -> "pyāra", `दिल` -> "dila". With `.stripDiacritics`: "tuma hi ho / calate / amkhem / kyom / divana / pyara / dila". It has no schwa deletion ("tuma", "pyara", "dila"), writes च as "c", writes anusvara and chandrabindu as "m", and loses vowel length. **V**. Verdict unchanged: not a usable base.
- **`indic_transliteration` (sanscript) and `common_maps`**: both **MIT** (GitHub licence metadata, both active in October 2026). **V**. A full-text grep of the sanscript source finds no schwa or inherent-vowel deletion; its `to_lay_indian` (OPTITRANS -> lay Indian, e.g. "kRShNa" -> "krishna") only rewrites a few clusters and lowercases, so it also keeps every final "a" and drops vowel length. **V**. Usable only as a reference for the consonant and matra table.
- **Aksharamukha**: README states GNU AGPL 3.0. **libindic `indic-trans`**: AGPL-3.0 (GitHub metadata). **V**. Licence is no object in the Personal build (R179), so both are bake-off candidates (4.4).
- **IndicXlit** (AI4Bharat): MIT, but an ML model; excluded by the no-model rule. **V**.
- **Google Dakshina** (romanization lexicons with attested casual spellings): **CC BY-SA 4.0** (README); the repository is archived (2020). **V**. Licence is no object in the Personal build (R179): whether its lexicon ships as an override list is a bake-off question (4.4); it is the local eval oracle either way (16.5).
- **The bake-off** (`docs/research/phase9-import-bakeoff.md` section 5, 2026-11-01) scored ten engines on 134 Devanagari lyric lines from 22 songs, each aligned to a published casual romanization of the same song on LRCLIB and hand-reviewed: a dev set (107 lines) for tuning and a held-out set (27 lines, 155 words) never looked at while tuning. Its rule engine v2 (this section's rules plus the changes in 7.3) won on every column but final schwa (section 4.4 has the numbers); R182 picks it, as native Swift.
- Schwa deletion rule family: Narasimhan, Sproat and Kiraz, "Schwa-deletion in Hindi text-to-speech synthesis", *International Journal of Speech Technology* 7, 2004 (published-venue citation; **U**: not re-read for this spec).

### 7.3 Algorithm (`Romanization/HindiRomanizer.swift`, about 300-400 lines plus `HindiRomanizer+Table.swift`; R182)

A pure Swift port, rule for rule, of the bake-off's prototype `segue_rules_v2` (`research/phase9-import/.build/bakeoff/tools/bake.py`, gitignored with the gold data), working on `Unicode.Scalar`s. The four rule changes the bake-off measured (bake-off 5.5) are written into steps 2, 3, 5 and 5b below.

1. **Segment** the text into Devanagari runs and everything else (Unicode scalar ranges U+0900-U+097F and U+A8E0-U+A8FF); only runs are converted, word by word (a word is a maximal run of Devanagari letters and marks).
2. **Override list first**: a hand-curated dictionary of frequent lyric words whose casual spelling the rules would not produce (for example `है` "hai", `हैं` "hain", `में` "mein", `मैं` "main", `क्यों` "kyun", `नहीं` "nahin", `प्यार` "pyaar", `दिल` "dil", `तुम` "tum", `ज़िंदगी` "zindagi", `आँखें` "aankhen", `दीवाना` "deewana", `हूँ` "hoon", `वो` "woh", `हम` "hum"). The function words use the **long spellings** "woh", "nahin", "kyun", "hain" (R182), although most LRCLIB contributors write "wo" / "vo" and "nahi"; they affect only generated text, never pasted text. Seeded with about 300 words from Bollywood lyrics by hand; every entry has a test row.
3. **Graphemes** with a casual map: consonants क k, ख kh, ग g, घ gh, च ch, छ chh, ज j, झ jh, ट t, ठ th, ड d, ढ dh, ण n, त t, थ th, द d, ध dh, न n, प p, फ ph, ब b, भ bh, म m, य y, र r, ल l, व v (w before a vowel at word start where the override list says so), श sh, ष sh, स s, ह h; nukta forms क़ q, ख़ kh, ग़ gh, ज़ z, फ़ f, ड़ d, ढ़ dh (casual "thodi", "chhode", "dhadkan", "badha"; this spec first had "r" and "rh", bake-off 5.5 rule 1). Vowels and matras: अ a, आ/ा aa, इ/ि i, ई/ी ee (word-final "i"), उ/ु u, ऊ/ू oo (word-final "u"), ए/े e, ऐ/ै ai, ओ/ो o, औ/ौ au, ऋ/ृ ri. Virama joins clusters.
4. **Nasals**: anusvara ं and chandrabindu ँ become "n", or "m" before प फ ब भ म.
5. **Schwa deletion**: drop the word-final inherent "a" (except after a cluster that needs it, e.g. a conjunct ending a word). Medial schwa by a **right-to-left pass**: delete the inherent "a" in V C _ C V when the next syllable keeps a vowel, then skip one syllable so no three-consonant cluster forms (`चलते` "chalte", "karna", "marne", "sakte", "dhadkan"; bake-off 5.5 rule 2: 87.5% of held-out medial-schwa words, against 40.6% for this rule as first written). Words of one consonant keep their "a" (`न` "na").
5b. **Casual "eh"**: an inherent "a" before ह becomes "e" when the ह is followed by a consonant or ends the word ("pehla", "kehti", "reh", "mehka", "gehra"; bake-off 5.5 rule 3).
5c. **Further rules the bake-off names** for its remaining held-out errors, each tried on the dev set only and kept if it helps: Aksharamukha's sonority rule for final clusters (`RemoveSchwaHindi`, `PreProcess.py:988`: keep the final schwa only when the cluster rises in `[यरलव] < [नमण] < [शषस] < stops`, so `दर्द` "dard", `फ़र्क` "farq"), च्छ as "cch" ("acche"), and a "y" between vowels ("jaayega").
6. **Output** lowercase, no diacritics, original punctuation and spacing; the first letter of a line is capitalised only if the line was a title or name field.

Tests: a table of a few hundred Devanagari words and 30 full lyric lines with expected casual output (section 15.1), the bake-off's gold through `make eval-import` (16.3), plus a local Dakshina check (16.5).

### 7.4 Where it lives

`SeguePersonalModules/Romanization/` (R182, closing Q6, section 21). It has no caller in the App Store build in v1.0, and keeping it in the personal package means the App Store binary is unchanged by this workstream. It is pure Foundation code with no UI, so moving it down to SegueCore later is one file move.

## 8. URL import

### 8.1 Inputs

- An `http` or `https` URL typed or pasted in the web field (11.3), pasted alone into the New Song text area (11.4), dropped from Safari onto the library (11.5), or chosen with File > Import from Web Page...
- A saved page file (`.html`, `.htm`, `.webarchive`) through Import Songs... or a drop (R179): the same parsers, no network, `loadPath = .savedFile`.
- Anything else (`file:`, `ftp:`, `javascript:`, a host without a dot, an IP literal in a private range, `localhost`) is refused before any request with "Segue imports web pages only (https://...)." Private-range refusal keeps the feature from probing the local network.

### 8.2 The fetcher (`Web/PageFetcher.swift`, `Web/URLSessionTransport.swift`)

- **Sandbox**: outgoing connections are already allowed by `com.apple.security.network.client` and `ENABLE_OUTGOING_NETWORK_CONNECTIONS` in both flavours (3.1). Nothing new is entitled; the App Store build simply contains no fetcher.
- `HTTPTransport` is a port (`func send(_ request: HTTPRequest) async throws(ImportFailure) -> HTTPResponse`), with `URLSessionTransport` (shipping) and `FixtureTransport` (tests, E2E): the injectable IO the deterministic tests need.
- `URLSessionConfiguration.ephemeral` with `httpCookieStorage = nil`, `httpShouldSetCookies = false`, `urlCache = nil`, `httpMaximumConnectionsPerHost = 1`, `waitsForConnectivity = false`, request timeout 15 s, resource timeout 30 s. No cookies, credentials or cache ever touch disk, and the user's Safari session is never used.
- `GET` only, `Accept: text/html,application/xhtml+xml`, `Accept-Language: en`, the identifying User-Agent of 6.2 (R179: API calls identify as Segue). A plain request runs no JavaScript and keeps no cookies; a page blocked to it goes to the hidden WebKit loader (8.6). This reverses the spec's first rule that a page is never loaded in a web view (R179, R182; bake-off section 0 item 1): only the WebKit loader runs a page's scripts, and only for a page or search the owner asked for.
- Redirects: at most 5, `http` -> `https` allowed, `https` -> `http` refused, every hop re-checked against 8.1's scheme and host rules.
- Body cap **5 MB** (streamed; over the cap is `.tooLarge`). `Content-Type` must be `text/html`, `application/xhtml+xml` or `text/plain` (else `.notAPage`). Charset from the header, then `<meta charset>`, then UTF-8 with Windows-1252 fallback (the converter already handles CP1252 quotes).
- HTTP 404/410 -> `.notFound`; 401/403 -> `.blocked` (a 403, challenge or not, first goes once to the WebKit loader, 8.6); 429/503 -> `.busy(retryAfter:)` (LRCLIB's 503 retries are in section 9); other 4xx/5xx -> `.server(status:)`.

### 8.3 Choosing a reader (`Web/Parsers/PageParserRegistry.swift`)

1. By host (exact suffix match, no regex): `ultimate-guitar.com` -> `TabJSONParser`; `e-chords.com` -> `ChordPreParser`, loaded through the WebKit loader directly (8.6: plain requests are hard-blocked); `chordie.com` -> `ChordSpansParser`.
2. The site parser returns an `ImportedSong` or nil. Its result must pass the **sanity checks** (8.5); if it returns nil or fails them, the `GenericPageReader` runs on the same HTML and the provenance records `fellBack = true`.
3. Any other host: `GenericPageReader` directly.
4. If the generic reader also finds no chart: `.noChart` (8.7).

### 8.4 The parsers

Each parser is a pure function `(HTML string, URL) -> ImportedSong?` with no network, so every one runs offline against fixtures.

**`TabJSONParser` (Ultimate Guitar, verified 3.6 and bake-off 1.2).**
- Find `<div class="js-store" data-content="...">` (by attribute, not position; SwiftSoup decodes the attribute's entities), decode as JSON with `JSONSerialization` (tolerant: navigate by key path, never a strict `Codable` model, so added fields cannot break it). In the WebKit path read `window.UGAPP.store` first, wrapped as `{store: ...}` (6.10).
- Chart: `store.page.data.tab_view.wiki_tab.content`. When that path is missing, search the JSON for the first string under a key `content` that holds `[ch]` or `[tab]` and set `Provenance.foundByContentSearch`, so a path move keeps working and the eval and canary still report the drift (prior-art 1.4 item 2: codekoch `UltimateGuitar2Bandhelper` `index.html:473-477`).
- Convert UG markup to text, in this order:
  1. **Rejoin split slash chords and trailing qualities** before stripping tags: `[ch]D[/ch]/[ch]F#[/ch]` and `[ch]D[/ch]/F#` become `D/F#`, `[ch]A[/ch](add9)` becomes `A(add9)` (prior-art 1.4 item 4: LiveNLoud `scraping_service_ultimate_guitar.py:32-43,212-230`).
  2. **Re-space glued chords on chord-only lines only**: `[/ch][ch]` gets a space, and `[/ch]` followed by a word gets a space (prior-art 1.4 item 5: hedwiggggg `ugrip` `App.js:169-171`). Lyric lines are never re-spaced, so lyric columns never move.
  3. `[tab]` / `[/tab]` removed (the pair marks a chord line plus its lyric line, kept as two lines); `[ch]X[/ch]` -> `X` keeping column positions (the markers are laid over already-aligned text, `Simnol22/bibi-tabs` `ultimate_guitar.py:8-9`); a `[tab]` block holding real tablature (`e|---7---8--|`) stays as tab lines for the converter (bake-off 1.2).
  4. `[Verse 1]`-style headers kept (the converter reads them); `[verse]...[/verse]` section tags read as the same sections, and `[b]`, `[i]`, `[u]` control tags stripped (LiveNLoud `:31,44-52`; how common they are is unverified).
  5. **Entities decoded once more in the content field only** (UG double-encodes some; `igrek51/android-songbook` `ug2songbook.py:50-52`, prior-art 1.4 item 6), never the whole JSON twice, so a literal "&amp;" in a lyric survives. `\r\n` normalised.
- Fields: `tab.song_name`, `tab.artist_name` (with the `Misc ...` rule and the structured singer credits of 5.4), `tab.tonality_name` (else `tab_view.meta.tonality`) -> key, **`tab_view.meta.capo`** -> capo (`tab` has no `capo` key; bake-off 1.2). `tab.type` must be "Chords" or "Ukulele Chords" (or absent); "Tab", "Bass Tab", "Pro", "Power", "Official" and "Video" pages (reached by address: search never lists them, 6.10) are refused (R179) with "This page is a tab, not a chord chart" (or "Pro pages have no chord chart Segue can read" for Pro and Power) (`.noChart`), because the chart is notation Segue does not read (Pro/Power content is not in the page at all).
- After UG's in-app navigation the `js-store` attribute can be stale (UG switches songs partly without a real page change; codekoch `README.md:25-37`): a saved page whose `js-store` song differs from the page's own heading is treated as the `js-store` song, and a fixture covers it (15.1).
- Fallback path if `js-store` is missing: the generic reader (UG has served server-rendered `<pre>` pages in the past).

**`ChordSpansParser` (Chordie, verified 3.6).**
- Walk the song container in document order: each `div.chordline` becomes one line in inline-chord form, writing each `span.absc` chord as `[X]` at its position in the text (the `bracket` spans dropped), so `Hey zu [Gm]Hmm Hm[D]m` reaches the converter as inline ChordPro chords; each `div.textline` becomes a plain line (blank text -> blank line).
- Fields: from `<title>` "<Title> <Artist> Chords and Lyrics for Guitar" only when the page's breadcrumb or heading gives the split; else title only, artist from the chart's own credit line if the converter finds one. Chordie re-hosts other sites, so the first lines often carry "By <names>" credits: the converter's credit-line rule already reads those.
- A Chordie page can be a **copyright block notice** instead of a chart, with HTTP 200 ("I have received a letter from someone claiming that this song violates their copyright ..."; bake-off 2.1): the parser reports `.noChart` with "The site has removed this song."

**`ChordPreParser` (E-Chords, verified through the WebKit loader, bake-off 2.2).**
- The chart is the `<pre>`: its text read by walking the text nodes (4.4), each `<span data-chord="X">` kept as `X` at its column, `<b>(2x)</b>` and `<i>Intro:</i>` kept as text for the converter, the nested `div.tabs` block as tab lines.
- Fields: JSON-LD `MusicComposition` (`name`, `composer`, `recordedAs.byArtist.name`), then the inline `window.SONG_METADATA` object (`NAME`, `ARTIST_NAME`, `CHORDS_KEY` -> key, `CAPO` -> capo), each checked with `isPlausibleName`.
- Two traps the bake-off found: the site auto-tags the Hindi word "Ab" as an A-flat chord on a lyric line (`<span data-chord="Ab">Ab</span> tum hi ho`), so a `data-chord` span on a line whose other tokens are words is lyric text; and a contributed page with its chords glued into the words ("EmHum tere bin ab Creh nahi sakte") fails the sanity checks (8.5) instead of importing.

**`GenericPageReader` (any page).**
1. Parse the HTML with SwiftSoup (4.4); drop `script`, `style`, `noscript`, `template`, `svg`, `iframe`, `form`, `nav`, `header`, `footer`, `aside` and elements whose `class`/`id` say ad, comment, share, related, menu, cookie, banner, sidebar.
2. Candidate blocks: every `<pre>`, `<textarea>` and `<code>`, every element whose `class`/`id` contains chord, lyric, tab, song, sheet, chart (including `chordline` / `lyric-line` blocks), and every element with at least 4 `<br>` children (prior-art 1.4 item 11: `nlevin/fretz` `WebSongImporter.swift` `parseEmbeddedChordSheet`).
3. Render each candidate to text: `<br>` and block ends -> newline, whitespace kept inside `<pre>` and elements styled monospace, inline elements whose whole text is a chord token (`ChordLines.kind(of:) != .unknown`) inside a lyric line -> `[X]` at that position (pages that mark chords up inline), entities decoded.
4. Score each candidate with core's line classifier (`FormatDetector.classify`): +3 per chord line followed by a lyric line, +1 per lyric line, +2 per section header, -2 per junk line (`JunkRules`), -1 per line over 200 characters, and a large bonus (+100) for a block whose attributes say ChordPro (fretz); ignore candidates under 4 lines. Pick the highest; when two overlap (a parent and its child) prefer the smaller with at least 90% of the score.
5. Fields: JSON-LD (`MusicComposition`, `MusicRecording`, `CreativeWork` name / byArtist / inAlbum), then `og:title` / `og:description`, then `<h1>`, then `<title>`, each split with the "X Chords by Y", "X - Y Chords", "X Lyrics" patterns and checked with `isPlausibleName`.

### 8.5 Robustness against layout changes

- **Selectors by meaning, not position**: attribute and class lookups, JSON key paths, never "the third div".
- **Sanity checks** on every parser result before it is used: at least 4 non-blank lines; at least 2 lyric lines; when chords are present, at least 80% of chord tokens parse as chords (`ChordLines.kind`); no line made only of site words (`JunkRules`); the title, when given, passes `isPlausibleName`; for `TabJSONParser`, the **chord-integrity check**: the sequence of chord tokens in the converted text must equal the sequence of `[ch]` tokens in the source after the slash-chord rejoin (prior-art 1.4 item 3: LiveNLoud `scraping_service_ultimate_guitar.py:304-341`). A failure falls back to the generic reader (8.3), never to a half-parsed chart.
- **Visible fallback**: the review's source line says "Read with the general page reader" when `fellBack` is true, and analytics carries `fellBack` (12), so a site's layout change shows up both to Ryan and on the dashboard.
- **Corpus regression**: every parser change runs the offline eval (16); a page that passed and now fails is a regression the session fixes before committing.
- **Manual canary** (`make import-canary`, 16.4): fetches one known page per site, runs the parser, prints pass or which check failed. Never in `quick`, `gate` or `check`.

### 8.6 Bot checks, blocked sites and Open Here (R179, R182, R183)

- A plain response that is a challenge page (the detection rule below) or any HTTP 403 is not yet a failure: the same URL loads **once** through the **hidden WebKit loader** (R179). E-Chords goes to the WebKit loader directly (8.3).
- **`WebKitPageLoader`** (`Web/WebKitPageLoader.swift`, `@MainActor`, behind the `PageLoader` port so tests use a fake; bake-off section 3, prior-art section 2):
  - **One on-demand `WKWebView`**, created when a load needs it and not in any window, used for one page at a time behind the `RequestPacer`, and torn down 30 s after its last use so the WebContent process exits (about 250-330 MB in all while a view exists, bake-off 3.1; the 8 GB low-spec budget holds because the steady state is zero). Never during a show (R109). `WKPreferences.inactiveSchedulingPolicy = .none` (macOS 14+), so a hidden view is not throttled while a challenge script runs (prior-art 2.3). If the a3 spike shows a check passes only in a window, the view is hosted in a small real window behind Segue's own (never offscreen, never transparent).
  - **A dedicated persistent cookie store** (R183: later hidden loads reuse a pass): `WKWebsiteDataStore(forIdentifier:)` with a fixed UUID owned by the personal package, so a clearance cookie survives across loads and launches, which is what made the bake-off's E-Chords loads pass (bake-off 3.1); never `.default()` (shared with any other WebKit use in the app) or `.nonPersistent()` (re-challenged every launch, as this spec first had it). After each load the store's disk and memory caches are cleared (`removeData(ofTypes:modifiedSince:)` with `WKWebsiteDataTypeDiskCache` and `WKWebsiteDataTypeMemoryCache`), so only cookies and site storage stay and no page or lyric is kept on disk (section 9). A **Clear Site Data** button in the Personal build's Settings removes the whole store (`removeDataStoreForIdentifier`). The user's Safari session is never used.
  - JavaScript on (a real browser engine is the point), **WebKit's own user agent for the whole session** (no `customUserAgent`: Segue imitates no browser, and Cloudflare fails a check whose agent changes mid-session, prior-art 2.1), media and pop-ups off, downloads refused.
  - **Navigation rule on the main frame only** (R183): the main frame stays within 8.1's scheme and host rules (every hop re-checked); subframes load what the page asks for, so the challenge's own frames (`challenges.cloudflare.com`, `about:blank`, `about:srcdoc`) load. Refusing them guarantees failure (prior-art 2.3, from Cloudflare's WebView rules).
  - **Ads and trackers blocked** (R182) with a `WKContentRuleList` (`Web/ImportContentRules.swift`) compiled once, listing the ad and tracker hosts the sites load (the bake-off saw Google ads, GTM and Clarity on E-Chords). It also removes consent banners, so nothing clicks them (klank's consent auto-clicking is deliberately not copied, prior-art 1.2). **The challenge host `challenges.cloudflare.com` is never blocked** (R183). Step a3 measures the load time and memory it saves.
  - **Cold-store warm-up** (R183): when the store holds no cookies for a site yet, the loader loads that site's home page once before the deep page (the E-Chords home passed with a cold store where the song page was challenged, bake-off 2.2; prior-art 1.4 item 10: LiveNLoud `:476-482`). It counts as one request to the host in the pacer (section 9).
  - **Reading the page**: after navigation finishes and the reader's marker is present (UG `window.UGAPP.store` or the `js-store` element, the E-Chords `<pre>`, for the generic reader document ready plus 1 s), the loader prefers JSON read from inside the page in a separate `WKContentWorld` (`callAsyncJavaScript`: UG's store, E-Chords' `/api/search`, or an in-page `fetch(location.href)` for the server HTML, which rides on the page's own cookies), and falls back to `document.documentElement.outerHTML`. The result goes to the same readers as a plain page (one parser per site, two transports).
- **Challenge detection** (`Web/ChallengeDetector.swift`, pure; the merged rule of prior-art 2.4 from the bake-off's markers, klank `ug_webview.rs:81-85` and FlareSolverr `flaresolverr_service.py:46-54`): a load is challenged when the main response has `cf-mitigated: challenge`, the title contains "Just a moment", "Attention Required" or "Verifying", or the DOM has `#challenge-form`, `#challenge-running`, `#challenge-stage`, `.cf-turnstile`, an `iframe[src*="challenges.cloudflare.com"]` or `input[name="cf-turnstile-response"]`. The loader then reads the challenge type from the page script's `cType: '<type>'` (prior-art 2.4: Scrapling `scrapling/engines/_browsers/_base.py:626-672`):
  - `interactive`: the wait **stops at once** and the load ends `.challenged` (R183), saving a wait only a person can end;
  - `non-interactive`, `managed` or no `cType`: wait up to **12 s** for the challenge to clear on its own (a warm store clears in about 1 s; bake-off 3.3), then `.challenged`.
  A 403 that is not a challenge page (Cloudflare's "Sorry, you have been blocked") ends `.blocked`.
- **No captcha-solving** (R179, R183): no free on-device way exists to pass an interactive check automatically (prior-art 2.3: every free "solver" clicks the checkbox), so the app never clicks a challenge, never injects into its frame, never synthesises input, never retries it in a loop and never waits beyond the limits above.
- **Open Here** (R183): for `.challenged`, the first action shows the same web view, with its page as it is, in a sheet titled "<host> wants to check you're a person", so the owner completes the check himself. When the challenge markers clear and the reader's marker appears, the sheet closes and the import or search continues on its own; Cancel closes the sheet and leaves the other actions. The clearance cookie lands in the persistent store, so later hidden loads reuse the pass. The view is the hidden one, shown: same store, same user agent, no reload.
- **Fallbacks** for `.challenged` and `.blocked` (R179, R183): **Open Here** (challenged only), **Open in Safari** (the page, in the user's browser), **Import a Saved Page...** ("Save the page in Safari with File > Save As, then choose or drop the file here": the saved-file path of 8.1), and **Paste the Page Instead** (select the page in Safari, copy, then New Song from Clipboard, the existing paste flow).
- **Private Access Tokens**: Cloudflare's managed challenge accepts Apple's Private Access Tokens, which can pass a check with no interaction; whether a sandboxed third-party app's `WKWebView` receives them is unknown (prior-art 2.1). Step a0 spikes it first (R183). Nothing in the loader depends on the answer; it says how often Open Here will be needed.
- `loadPath` in `Provenance` records which path read the page (analytics, 12; the review shows nothing extra).

### 8.7 Failure messages (inline in the web field area; the field keeps the URL)

| `ImportFailure` | Message | Actions |
|---|---|---|
| `offline` | "You're offline. Importing a web page needs the internet." | Try Again |
| `timedOut` / `server` | "<host> isn't answering right now." | Try Again, Open in Safari |
| `challenged` (after the WebKit loader's wait, 8.6) | "<host> wants to check you're a person." | Open Here, Open in Safari, Import a Saved Page..., Paste the Page Instead |
| `blocked` (a hard block, 8.6) | "<host> doesn't let apps read this page." | Open in Safari, Import a Saved Page..., Paste the Page Instead |
| `backingOff` (section 9) | "<host> asked Segue to wait. Try again after 21:40." | Open in Safari, Paste the Page Instead |
| `notFound` | "That page doesn't exist anymore." | Open in Safari |
| `notAPage` / `tooLarge` | "That address isn't a web page Segue can read." | none |
| `noChart` | "Segue couldn't find a chord chart on this page." (or the tab-not-chords text of 8.4) | Open in Safari, Paste the Page Instead |
| `busy` | "<host> is busy. Try again in <n> seconds." | automatic enable |

Never an alert, never a crash, never a saved song. The diagnostic log records only the reader kind, the failure case and the HTTP status class, never the URL, host, title or any page text.

## 9. Rate limiting and caching

- **`RequestPacer`** (an actor with an injected `Clock`, so tests are deterministic): one in-flight request per host; minimum gap 300 ms for `lrclib.net`, 2 s for any other host; `Retry-After` honoured with up to 30% jitter (randomness injected).
- **LRCLIB 503 retries** (R182): a 503 is retried automatically up to **5 times**, each after its `Retry-After` (default 1 s) plus jitter, sequential and paced, about 15 s at most in all. The bake-off measured 95% of searches answered this way against 55% with one retry (bake-off 2.3). While it retries, the LRCLIB group reads "LRCLIB is busy, retrying..." with Cancel (6.8); after the fifth failed retry, the `server` message. After a 429 nothing is retried: the host is held for the full `Retry-After` and the UI shows the countdown.
- **Chord-site back-off** (R183; prior-art 1.4 item 9: `ParalelSt/ember` `apps/web/lib/tabFetch/polite.ts:1-20`): when a chord site answers HTTP 403, 429 or 503 on its last load path with no challenge page (a hard block, which Open Here cannot clear), that host gets a **one-hour back-off**: nothing at all is sent to it meanwhile, and its search group and the web field show "<site> asked Segue to wait. Try again after 21:40." (6.8, 8.7). A plain-request block that the WebKit loader then gets past, and a `.challenged` load, do not start it. The back-off lives in memory for the launch and its clock is injected. It protects the owner's IP and cookie reputation, which is what keeps later loads passing.
- No other automatic retries.
- **User actions bound traffic**: one page fetch per Import action (plus at most one WebKit load of the same page and, with a cold store, one warm-up home page, 8.6); per Search, one results request to UG (plus at most one WebKit load), the E-Chords search page plus its one in-page JSON call (two requests), and at most 3 LRCLIB queries, each with its 503 retries (6.3, 6.9); one page request per preview, only for the version the user selects (Up/Down through rows waits 300 ms on a row before fetching, so arrowing past rows sends nothing); no prefetching, no background requests, no polling, no request at launch. A WebKit load counts as one request to its host in the pacer; Open Here sends only what the page itself sends while the owner completes the check.
- **`PageCache`** (in memory only, per launch): the last 20 fetched pages keyed by final URL for 10 minutes, so Cancel then re-import, or a second look, costs nothing; LRCLIB searches keyed by exact query text for 10 minutes, records by id for the launch. Nothing fetched is written to disk outside the song the user accepts (the WebKit store keeps only cookies and site storage, its caches cleared after each load, 8.6), so no copyrighted page or lyric is kept by Segue unless the user saved it into their library.
- Memory: the cache drops entries on `memoryPressure` warnings and is cleared when the library closes.

## 10. Legal and terms (personal use)

- **Licence is no object for the Personal build** (R179): components are picked on quality by the bake-off (4.4), whatever their licence, because the Personal build is never distributed. The App Store build contains none of them.
- **Why Personal only**: LRCLIB publishes no content licence (6.1); the lyrics belong to their rights holders. Ultimate Guitar's terms (`ultimate-guitar.com/about/tos.htm`, read 2026-10-31) say content "may be accessed for your personal, non-commercial use only" (6.3), "you will not duplicate or otherwise reproduce the Content" (6.2) except printing tabs and lyrics for personal, non-commercial use, and that UG's lyric licences cover display "solely on or through the Service" (7.7). **V**. E-Chords and Chordie terms were not read (**U**); Chordie re-hosts other sites' charts. A store build that fetched and stored these would breach those terms; a personal tool that fetches one page Ryan chose, for his own non-commercial use, is the use the owner accepts (`docs/research.md`: "ToS forbids scraping -> URL import is personal-only").
- **robots.txt** governs crawlers. It does not limit a search or page load the owner starts in the Personal build (R182): UG's `/search.php` and E-Chords' `/search` and `/api/` are requested once per Return, paced. The corpus collector, which is a crawler, honours robots.txt except for the 20 search pages R184 allows (16.1).
- The Personal build is never distributed (R139: App Store only, no DMG, no Developer ID), so these features never reach anyone but Ryan.
- Behaviour that keeps it a personal tool: one user-chosen search or page per action, honest identification on every API call and plain request, no captcha-solving (a blocked page gets one load in a real browser engine; a check that needs a person is shown to the owner with Open Here and never clicked by the app, 8.6), no reverse-engineered API key (the UG mobile API is not used, R182), a one-hour back-off after a hard block (9), no crawling or following links (a search reads one results page per site, a preview reads the one chart selected), no bulk or scheduled fetching, nothing cached to disk, no redistribution (Segue has no sharing of fetched content; the user's own library export is their own copy).
- No acknowledgement of LRCLIB or the sites goes into `THIRD_PARTY_NOTICES.md` or the website (both ship with or describe the App Store build, which has none of this). The attribution lives in the Personal build's own sheet (6.4) and source line (11.6). Every third-party component the bake-off adopts (4.4) **does** get a `THIRD_PARTY_NOTICES.md` row, because `scripts/check-docs.sh` check 3 fails without one for any pin in `Tuist/Package.resolved`; the row says "Personal build only". That names a library, not a service or site, so it reveals nothing about these features.

## 11. UI entry points and exact behaviour

All entry points exist only when the matching `PluginEntries` value is non-nil (4.3). All are disabled during a show with the existing reason "Paste is unavailable while a show is running" (R109), and none opens while a review sheet is open (`canPaste`).

### 11.1 File menu (`FileCommands.swift`)

After "Import Songs...":
- **"Import from Web Page..."** Shift-Cmd-U (R179; new `MenuShortcuts.importWebPage`). Opens the New Song sheet with the web field focused (11.3).
- **"Find Lyrics..."** Shift-Cmd-L (R179; new `MenuShortcuts.findLyrics`). Opens the Find Lyrics sheet (6.4), which searches all three sources.

Both rows are added to the shortcut table only in the Personal build's Keyboard Shortcuts list (the table's rows carry an availability closure checked against the entries), and the shortcut-conflict test covers them.

### 11.2 The empty library (`LibraryViews.swift:250-280`)

The action row becomes: Paste a Song, New Song, Import Songs..., and in Personal a second row of two link-style buttons: **"Import from a web page"** and **"Find lyrics"**, under the first row, above "How to bring songs in". The description text gains nothing (the App Store copy stays identical).

### 11.3 The New Song sheet (`PasteInputView`)

In Personal, a single-line field sits above the text area: placeholder "Or paste a page address (https://...)", with an Import button at its right, `autocorrectionDisabled()`. Return in the field imports. While fetching: the button becomes a spinner with Cancel; the text area dims. On success the sheet moves to review (as a paste does). On failure the 8.7 message shows under the field with its actions. The App Store sheet is unchanged (640 x 440); the Personal sheet grows by the field's height (step c0's mockup sets the exact layout).

### 11.4 A lone URL pasted as text

When the text pasted into the New Song text area, the clipboard for New Song from Clipboard, or Cmd-V on the song list is **only** one `http(s)` URL (after trimming), the Personal build does not convert it as a song: it opens the New Song sheet with the URL in the web field and fetches at once (one user action: the paste). The App Store build is unchanged.

### 11.5 A dropped link

Dropping a link (an `NSItemProvider` with a URL type that is `http(s)`, as Safari's address bar and links provide) on the library list or the empty library starts the same fetch in the New Song sheet. File drops keep today's behaviour. App Store: link drops are not accepted (no drop type registered).

### 11.6 The review sheet's source line (R117 design kept)

Under the header title, one muted line, 12.5 pt: for a web page "From <host>" (the host as a link that opens the page in the browser), plus " - read with the general page reader" when `fellBack`; for an Ultimate Guitar version "From Ultimate Guitar · ver 3 · ★4.8" (6.10); for LRCLIB "Lyrics from LRCLIB" (link to the record's LRCLIB page). Plus " - converted from Devanagari" when `romanized`. Nothing else in the review changes.

### 11.7 In-product help

A "?" button in the Find Lyrics sheet and beside the web field opens a popover (the owner's in-product guide rule): what the feature does, that results are a starting point to check, how the groups and versions work, that a page asking for a human check can be opened here to complete it, and that a blocked page can be opened in Safari, saved and imported, or pasted, that nothing is kept unless accepted, and that it exists only in the Personal build.

## 12. Analytics (Personal build only, closed vocabulary, WS3 rules)

Only the personal package emits these, so only the Personal TelemetryDeck app receives them. The cases are core vocabulary (3.5) and ship in both binaries, so **no raw value names a site or service** (R179: analytics name techniques, not sites): readers and search groups are named by technique.

- `PasteSource` (row 19) gains `webPage` and `songSearch`. `SongSource` (row 5) gains `web` (a song accepted from a web page or a lyrics result); `nearDuplicate` works as today.
- **Row 31 `Segue.Import.pageRead`** (one per Import action): `reader: ReaderKind` (`tabJSON`, `chordPre`, `chordSpans`, `genericPage`), `fellBack: Bool`, `contentSearch: Bool` (`foundByContentSearch`), `outcome: WebImportOutcome` (`reviewed`, `noChart`, `blocked`, `challenged`, `backingOff`, `notFound`, `offline`, `busy`, `failed`, `cancelled`), `latency: LatencyBucket`, `entry: WebImportEntryPoint` (`menu`, `emptyState`, `sheetField`, `pastedURL`, `droppedLink`, `savedFile`), `loadPath: LoadPath` (`plain`, `webKit`, `savedFile`), `webKitBlocked: Bool` (the WebKit load still met a challenge), `challenge: ChallengeKind` (`none`, `nonInteractive`, `managed`, `interactive`, `unknown`: the `cType` read, 8.6), `openedHere: Bool` (the owner completed a check with Open Here), `warmUp: Bool` (a cold-store home page load ran first).
- **Row 32 `Segue.Import.searched`** (one per Search): `results: SmallBucket`, `groupsWithResults: SmallBucket` (0-3), `groupsFailed: SmallBucket`, `lyricsRetries: SmallBucket` (LRCLIB 503 retries this search needed), `variants: SmallBucket` (0-2), `outcome: SongSearchOutcome` (`results`, `none`, `busy`, `offline`, `failed`, `cancelled`), `romanHindiQuery: Bool`, `latency: LatencyBucket` (to the first group's answer).
- **Row 33 `Segue.Import.searchPicked`** (daily per group and rank bucket): `group: SearchGroup` (`tabJSON`, `chordPre`, `lyricsRecord`), `rank: SmallBucket` (song rank in its group), `versionRank: SmallBucket` (0 for single-version groups), `previews: SmallBucket` (previews opened before the pick), `fromVariant: Bool`, `romanized: Bool`, `inLibrary: Bool`.
- Row 19's existing fields then tell how the AI refinement and the guard did on these sources, and row 29 (artist split) covers their credits.
- Never recorded: the URL, host, query, title, artist, lyrics, record id, HTTP status code (only the outcome case). Breadcrumbs: none added.
- Throttling follows `AnalyticsEvent+Throttle.swift` (rows 31-32 per occurrence, row 33 daily per rank). The WS3 spec's row table (`docs/release/specs/WS3-services.md` section 5) gains rows 31-33 in step c5; the privacy page needs no change (the App Store build sends none of them).

Metrics this enables: fetch success rate per reader, fallback rate per reader (layout drift), content-search rate (UG path drift), blocked and challenged rates by challenge type, Open Here use and how often it succeeds, warm-up and back-off frequency, LRCLIB retry load, search hit rate with and without variants, how often romanization fires, pick rank (ranker quality), and with row 19 the review acceptance rate and correction rate per source.

## 13. Absence from the App Store build (`make verify-appstore`)

- The code is absent by construction: only the Personal target links `SeguePersonalModules` (`Project.swift:203-206`), and every site and service name lives in that package.
- Step c4 extends `forbidden` in `scripts/lib/verify-common.sh:11` with patterns that cannot collide with core text (3.2): `lrclib|LRCLIB|ultimate-guitar\.com|e-chords\.com|chordie\.com|TabJSONParser|ChordPreParser|ChordSpansParser|GenericPageReader|HindiRomanizer|URLSessionTransport|WebKitPageLoader|UGSearchReader|EChordsSearchReader|VersionRanker|ChallengeDetector|OpenHereSheet`. The names of the bake-off's third-party components (4.4) are deliberately **not** in the list: `scripts/check-docs.sh` check 3 requires every pin in `Tuist/Package.resolved` (which resolves the personal package too) to have a row in `THIRD_PARTY_NOTICES.md`, and that file ships in the App Store bundle, so their names would be false hits. Their symbols are still covered: the link map and `nm` checks match the package's own type names above, and each component is reachable only through them. The bundle-wide byte grep, the link map and `nm` then fail the build if any of them leaks into Release-AppStore or Debug-AppStore.
- Before the change, run the extended pattern over today's App Store products to prove zero hits (no false positives), and record the run in the commit message.
- The App Store UI test (15.5) proves no entry point is visible. `verify-archive.sh` check 4's exact entitlement set needs no change.

## 14. Accessibility

- Every new control has a label and an identifier in `AccessibilityID+Paste.swift` (`pasteWebField`, `pasteWebImport`, `pasteWebMessage`, `findLyricsField`, `findLyricsArtist`, `findLyricsResults`, `findLyricsGroup(<group>)`, `findLyricsResult(<n>)`, `findLyricsVersion(<n>)`, `findLyricsPreview`, `findLyricsAttribution`, `reviewSourceLine`, `emptyLibraryWebImport`, `emptyLibraryFindLyrics`, `webOpenHere`, `openHereSheet`, `clearSiteData`). The Open Here sheet is a labelled region ("Check from <host>") whose web content is reachable by VoiceOver as any web view, so the owner can complete an accessible check.
- Group headings are headers ("Ultimate Guitar, 6 songs"); song rows read as "<title>, <artist>, <album>. 3 versions. In your library."; version rows as "Chords, version 3, rated 4.8 from 1,204 votes"; LRCLIB rows have the first lines as the hint. The preview pane is a labelled read-only region. Failure messages are announced (`AccessibilityNotification.Announcement`).
- Full keyboard use: Tab order field -> Artist -> results -> preview; Up/Down in results (through groups, songs and versions; Left/Right collapse and expand a song's versions); Return picks; Esc cancels a running request first, then closes.

## 15. Tests (R113 budget)

### 15.1 SeguePersonalModules, in-process (new test target `SeguePersonalModulesTests`, Swift Testing)

- Add the target to `Packages/SeguePersonalModules/Package.swift` with `Tests/Fixtures` as a resource, and add the package to `make test-packages` (Makefile `test-packages`, step a1). A test helper fails any test that constructs `URLSessionTransport` (the only real-network type), so a test cannot reach the network by accident.
- **Parsers, table-driven over the committed redacted fixtures** (16.2): each fixture page -> expected `ImportedSong` (text and fields) for `TabJSONParser`, `ChordSpansParser`, `ChordPreParser`, `GenericPageReader`; plus malformed variants made from them in code (the `js-store` attribute removed, JSON truncated, class names renamed, an empty `<pre>`) that must fall back or fail cleanly, never crash or return a half chart. The UG cases of 8.4: slash-chord rejoin and trailing qualities, glued-chord re-spacing on chord-only lines only, `[verse]` and `[b]/[i]/[u]` tags, content-field entity decoding (a literal "&amp;" survives), the content-search fallback setting `foundByContentSearch`, the `UGAPP.store` wrapper, capo from `tab_view.meta`, singer credits from `recording_artists`, and a stale `js-store` after UG's in-app navigation. The E-Chords "Ab" lyric trap and glued page; the Chordie copyright notice.
- **Sanity checks and fallback**: a parser result failing each check (the chord-integrity check included) routes to the generic reader with `fellBack`.
- **Search readers** over committed redacted search pages (16.2): `UGSearchReader` (marketing rows dropped, only chord versions listed, versions nested by `song_id`, ratings, votes), `EChordsSearchReader` (the `/api/search` JSON and the rendered fallback, nesting); `VersionRanker` table (the per-song prior: the median, the clamp at 3 and at 50, the "tum hi ho" order of 6.10, the breakdown sums to the score, ties); the three-group merge in its fixed order with one group failing.
- **Load path** with a fake `PageLoader`: a plain challenge page or 403 routes once to the WebKit loader; E-Chords goes there directly; a cold store runs the warm-up once; `cType` interactive ends at once as `.challenged`, non-interactive waits to the limit; a `.challenged` result offers Open Here and the three fallbacks; a hard 403 is `.blocked` without Open Here; no second WebKit load; `loadPath` recorded. `ChallengeDetector` and the main-frame navigation decision are pure functions with tables (challenge host and `about:` subframes allowed, a main-frame hop to another host refused), and the compiled rule list's source is checked to leave `challenges.cloudflare.com` unblocked. The real `WKWebView` path is exercised only by the manual canary (16.4) and the hands-on walk, never by an automated test (no live network).
- **Fetcher with `FixtureTransport`**: redirects (limit, https->http refused), size cap, content types, charset detection, each status mapping, challenge-page detection, private-host refusal.
- **`RequestPacer`** with an injected clock and seeded randomness: per-host gaps, `Retry-After` plus jitter bounds, LRCLIB's five 503 retries and their cancellation, the 429 hold, the one-hour site back-off (starts on a hard block only, holds every request to that host, ends after the hour).
- **LRCLIB client** over recorded JSON responses (real response shapes, redacted lyrics): decode, tolerant fields, instrumental, null lyrics -> `/api/get/{id}`, non-JSON 502 body.
- **`LyricsQueryVariants`** and **`LyricsRanker`** tables: "tuj mai rab" produces "tujh mein rab"; English queries produce no variants; ranking breakdowns sum to the score; dedup.
- **`LRCSections`**: gap threshold, no synced lyrics, blank lines present.
- **`HindiRomanizer`**: a few hundred word rows plus 30 lines; the bake-off's rule cases (ड़ "d", the right-to-left medial-schwa pass, casual "eh"); Latin and mixed lines byte-identical; digits and punctuation kept; every override entry, with the long spellings of R182.

### 15.2 SegueCore, in-process

- `IngestPipeline.ingest(_:origin:source:)`: source fields win; text fills gaps; the credit splits with `artistSplits`; `{album}`; an unparsable key dropped; ChordPro passthrough untouched; the page heading line consumed. Table-driven in `IngestTests`.
- `Refinement.apply` on a source result: no artist or album change from the model; title unchanged when the source gave one.
- Analytics: rows 31-33 render to valid signal names and values (the existing vocabulary test pattern), and no raw value contains a site or service name (a test over `allCases`).

### 15.3 SegueUI, in-process

- `beginSourceReview` opens one item with the right `PasteSource`, honours `canPaste` and R109; Accept records `songCreated(.web, nearDuplicate:)`.
- The lone-URL rule (11.4): only a single trimmed `http(s)` URL routes to the web field, and only when the web entry exists.
- With nil entries (App Store composition) no web or lyrics affordance is produced by the view models.

### 15.4 E2E: `SegueWebImportE2ETests` (new, one class, one test, P9-4c)

On the Personal flavour with a Debug-only launch option (`-SegueImportFixtures <dir>`, compiled only under `#if DEBUG && SEGUE_PERSONAL`, so `check_no_test_hooks` keeps Release clean) that swaps in `FixtureTransport` serving the redacted UG and LRCLIB fixtures and a fake `PageLoader`: clean library -> File > Import from Web Page... -> paste the fixture URL -> review shows title "Tum Hi Ho", Movie / Album "Aashiqui 2", the source line, sections -> Accept -> the song is in the library; then File > Find Lyrics... -> "tum hi ho" -> the Ultimate Guitar and LRCLIB groups show results (fixture search pages, with a fake `PageLoader` for E-Chords that serves a `challenged` group showing Open Here) -> select the top UG version -> the preview shows the chart -> Return -> review shows the "ver 3" source line -> Cancel; then pick the first LRCLIB result -> review shows the attribution line and labelled sections -> Cancel writes nothing. The library is reset to the known clean baseline before the run.

### 15.5 App Store UI test (one method in the existing `SegueAppStoreUITests` target)

Launch the App Store flavour on an empty library: the File menu has no "Import from Web Page..." or "Find Lyrics..."; the empty library has no web or lyrics buttons; pasting a lone URL into New Song converts it as text, as today.

### 15.6 Per session

One `make quick` at the end of each session; one `make e2e-one TEST=SegueWebImportE2ETests` in P9-4c; one `make e2e-one` for the App Store method; one `make verify-appstore` in P9-4c step c4. Nothing else.

## 16. Corpus and eval

### 16.1 Collecting real pages (owner's rule: grow the corpus by fetching)

- Step a3 first moves the bake-off's saved pages (`research/phase9-import/.build/bakeoff/`: UG, Chordie, E-Chords and LRCLIB captures, gold romanizations) into the gitignored corpus folders below.
- `scripts/collect-import-corpus.sh` (P9-4a step a3, manual): reads `research/phase9-import/urls.tsv` (site, URL, language tag), fetches each page with the shipping User-Agent, honours robots.txt (except the search pages below, R184), waits 5 s between requests to a host, saves to `research/phase9-import/pages/<site>/<slug>.html` (**gitignored**, like `research/phase3-eval/pastes`), and logs challenge pages as skipped (no retry, no workaround).
- Target size: **60 pages**: 15 UG, 15 Chordie, 15 E-Chords (loaded through the WebKit loader, 8.6, because plain requests are hard-blocked; any it cannot load are cleared by Ryan with Open Here or saved from Safari, and the step hands Ryan the list of URLs and the exact steps), 15 generic from at least 8 other sites (Hindi chord blogs, other chord sites). At least half are Bollywood / Hindi film songs (romanized Hindi lyrics, "Misc Soundtrack" credits, several singers), the rest English; include a page with a capo, one with a key change, one tab-only UG page, one Pro page, one page with inline chord markup.
- Search pages: 10 saved results pages each for UG and E-Chords (half Hindi queries; Chordie is not searched, R182), with the expected results list written by hand, for the search readers (6.10, 6.11). Both sites' robots.txt disallow their search routes; the collector fetches exactly these 20 pages anyway, paced, gitignored and never committed (R184).
- LRCLIB: 30 recorded search responses (`research/phase9-import/lrclib/<query>.json`, gitignored): 15 Hindi queries typed in casual spellings, including 5 deliberately "wrong" spellings to test variants, and 15 English; at least 5 records in Devanagari.
- Gold files: for each page, the expected `.cho` (title, artists, album, key, capo, sections, chords, lyrics) written by hand in step a3 and checked by Ryan for a sample of 10 (gitignored with the pages: they contain lyrics).

### 16.2 Committed fixtures (redacted)

`scripts/redact-import-fixture.swift` turns a page and its gold into a committed fixture under `Packages/SeguePersonalModules/Tests/Fixtures/web/`: markup, attributes, JSON structure, chords, section headers, whitespace and line lengths kept; every lyric word replaced by a deterministic placeholder of the same length and case pattern (with a fixed seed, so romanized-Hindi shape like "Hum tere bin" becomes "Lor ipsu met"), titles and names replaced by placeholders. Hindi romanizer fixtures use public domain or self-written Devanagari lines. About 20 redacted pages (at least 4 per reader) and 3 redacted search pages each for UG and E-Chords are committed; the parser and search reader tests (15.1) run on these. R179 confirms the rule: lyric-redacted committed fixtures, full pages kept locally only.

### 16.3 The eval (`make eval-import`, manual, offline)

- A small executable target in the personal package (`segue-import-eval`) runs every reader on every gitignored page (or, without them, the committed fixtures) and scores against gold. Never in `quick`, `gate` or `check`.
- Per page and per field: title, artists (as a set), album, key, capo: exact after `RomanNormalizer.loose`; lyric words: word-level accuracy (1 - word edit distance / gold words); chords: token F1 and placement (a chord within one character of its gold column, or on the same syllable for inline charts); sections: label accuracy per block; junk: count of junk lines left in.
- **A page passes** when title is right, artists right, lyric word accuracy >= 99%, chord F1 >= 98% with placement >= 95%, and no junk line remains.
- Output: a table per reader, the failing pages with the first failing field, and code-only versus with-model accuracy per field (the model run uses `make eval-ai`'s provider setup when the model is present), so the AI step is measured, not assumed.

**Targets (gate for P9-4a done; R179: they stand as written):** site readers (UG, Chordie, E-Chords) **>= 95%** of their pages pass; generic reader **>= 80%** of generic pages pass; **zero** silent wrong charts: every failing page either falls back or reports `.noChart` / a review that differs from gold only in fields the user sees highlighted (no page produces an unflagged wrong title or artist). LRCLIB: the correct record is in the top 3 for >= 90% of the 30 queries and top 1 for >= 75%; variants rescue at least 4 of the 5 misspelled queries. Romanizer (R182): **>= 90% word exact and >= 95% `RomanNormalizer`-equivalent word agreement on a held-out gold set never used for tuning** (the bake-off's 27-line, 155-word held-out set, grown with new songs; the dev and held-out split kept in the gitignored corpus). The bake-off's prototype measures 90.3% and 95.5%, so the Swift port must at least match it.

### 16.4 Canary

`make import-canary` (manual, live network): one known public page per site plus one LRCLIB search; prints pass or the failing check per reader. Run by Ryan when a fetch fails in daily use, and once before v1.0 submission.

### 16.5 Romanizer oracle (local only)

`scripts/eval-romanizer.sh` downloads Dakshina's Hindi romanization lexicon into `.build/` (CC BY-SA, never committed) and reports how often the romanizer's output (`HindiRomanizer`, 4.4) is one of the attested casual spellings for the 2,000 most frequent words. Reported in the P9-4b commit; target >= 75% (casual spelling is genuinely varied).

## 17. Guide pages

- The public guide (`segue.ryandsilva.dev/guide`) documents the App Store build, which has none of this, and publishing how-to pages for scraping chord sites would advertise a ToS breach: **no public page** (R179).
- In-product help (11.7) is the guide for the owner.
- A draft page `guide/src/content/docs/web-import.mdx` with `draft: true` frontmatter (Starlight excludes draft pages from production builds; step c6 verifies that on Starlight 0.42.6 with `bun run build` and confirms the page is absent from `dist/`) documents both features with screenshots for local reading (`bun run dev`). If draft pages are not excluded, the page goes to `docs/personal/web-import.md` instead and the step says so.
- `paste-a-song.mdx` gains nothing.

## 18. Files owned

- New: `docs/phases/9-workstreams/P9-4-lyrics-and-url-import.md` (this spec); everything under `Packages/SeguePersonalModules/Sources/SeguePersonalModules/{Web,Web/Search,Lyrics,Romanization,UI}/`; `Packages/SeguePersonalModules/Tests/`; `research/phase9-import/` (README, `urls.tsv`; pages and gold gitignored); `scripts/collect-import-corpus.sh`, `scripts/redact-import-fixture.swift`, `scripts/eval-romanizer.sh`; `Packages/SegueCore/Sources/Plugins/PluginTypes.swift`; `Packages/SegueCore/Sources/Ingest/IngestPipeline+Source.swift`; `Packages/SegueCore/Sources/Services/AnalyticsEvent+Import.swift`; `UITests/SegueWebImportE2ETests.swift`; the draft guide page.
- Changed (own hunks only): `Plugins/PluginRegistry.swift`, `Ingest/IngestTypes.swift` (origins), `Services/AnalyticsEvent.swift` (rows 31-33, `SongSource.web`), `AnalyticsEvent+AI.swift` (`PasteSource`), `AnalyticsEvent+Throttle.swift`; SegueUI `Paste/*` (source review, the web field host, source line), `App/AppDependencies` (entries), `App/Commands/FileCommands.swift`, `App/MenuShortcuts.swift`, `Library/LibraryViews.swift`, `AccessibilityID+Paste.swift`; `App/Sources/SegueApp.swift` (entries wiring, the Debug fixture option); `Packages/SeguePersonalModules/Package.swift`; `Makefile` (`test-packages`, `eval-import`, `import-canary`); `scripts/lib/verify-common.sh` (`forbidden`); `.gitignore` (corpus folders); `.swiftlint.yml` (the SwiftSoup import rule); `THIRD_PARTY_NOTICES.md` (the SwiftSoup row, section 10); the Personal build's Settings (Clear Site Data, through the existing Personal settings hook); `UITests/AppStore/` (one method); `docs/release/specs/WS3-services.md` (rows 31-33).
- Pointer: `docs/phases/5-personal-modules.md` (replaced by a pointer to this spec).

## 19. Sessions and steps

### P9-4a - corpus, contract, fetcher, page readers, eval

- **a0** **Private Access Token spike, the first build step** (R183): in the sandboxed Personal build, load Cloudflare's Private Access Token demo page (not a site Segue imports from) in a hidden `WKWebView` on a dedicated store, and record whether a token was issued and the check passed with no interaction, in `research/phase9-import/README.md`. It needs an Apple ID signed in on this Mac (it already is if Ryan uses iCloud; tell him if it is not). About ten minutes; whatever the answer, the loader of 8.6 stands. Section 4.4 is already filled from the bake-off.
- **a1** Package setup: test target, `make test-packages` entry, SwiftSoup 2.14.3 pinned exactly (4.4) with its isolation lint rule and `THIRD_PARTY_NOTICES.md` row (10). `make quick`-level compile only.
- **a2** Contract: `PluginTypes.swift`, the protocol requirements, `IngestOrigin.web` / `.lyrics`, `IngestPipeline.ingest(_:origin:source:)` with its tests (15.2). Lands early so P9-4b can start.
- **a3** Corpus: move the bake-off's saved pages in (16.1), `urls.tsv` (agents pick representative public pages per 16.1), the collector run, the search pages of 16.1, the E-Chords list handed to Ryan with the Open Here and Safari steps (a manual action for Ryan: say so clearly and keep building), gold files, the redactor and the committed fixtures. Then the spikes the prior-art survey recommends (its section 3 item 7), on a cold, challenged page under the pacing rules: the hidden view with `inactiveSchedulingPolicy = .none`, a real window kept behind Segue's, and visible; the hidden view inside the Personal build's sandbox (no new entitlement expected, 3.1); and the ad and tracker rule list's effect on load time and WebContent memory. Results go in `research/phase9-import/README.md`; a result that changes 8.6 is a stop-and-ask.
- **a4** `HTTPTransport`, `URLSessionTransport`, `FixtureTransport`, `PageLoader` with `PlainPageLoader` and `WebKitPageLoader` (8.6: the persistent store and its cache clearing, the main-frame navigation rule, `ImportContentRules`, the warm-up, `ChallengeDetector` with `cType`), `PageFetcher`, `RequestPacer` (LRCLIB's 503 retries, the site back-off), `PageCache` with tests.
- **a5** `TabJSONParser` (with the 8.4 conversion steps and the content-search fallback), `ChordSpansParser`, `ChordPreParser` (from the WebKit-loaded pages; Ryan's saved pages only for any it cannot load, and if those have not arrived, build the other steps first and leave this one last), sanity checks with the chord-integrity check, fallback, with tests.
- **a6** `GenericPageReader` with tests.
- **a6b** `UGSearchReader`, `EChordsSearchReader`, `VersionRanker` (the per-song prior) with tests (6.10, 6.11).
- **a7** `segue-import-eval` and `make eval-import`; iterate the readers until the 16.3 page targets pass; record the table in `research/phase9-import/README.md`.
- **a8** `make import-canary`. End: one `make quick`.

### P9-4b - LRCLIB and romanization

- **b1** `HindiRomanizer` ported rule for rule from the bake-off's prototype (7.3), its table and override list, tests; the bake-off's gold through `make eval-import` with the held-out set kept out of tuning (16.3); `eval-romanizer.sh` run reported.
- **b2** `LRCLIBClient` on the pacer, recorded responses (16.1), decode tests; the live API shape re-checked once with a single manual request (LRCLIB was returning 502 on 2026-10-31).
- **b3** `LyricsQueryVariants`, `LyricsRanker`, `LRCSections`, script checks, with tests; the LRCLIB eval targets in `make eval-import`.
- **b4** The three `SongSearchSource`s (LRCLIB plus the UG and E-Chords search readers) and `WebPageImporter` registered in `PersonalModules.register(into:)`. End: one `make quick`.

### P9-4c - UI, analytics, absence checks, guide, E2E

- **c0** Design directions (R39): 2-3 mockups of the Find Lyrics sheet (the three fixed groups, nested versions, the preview pane, the retrying and back-off lines), of the New Song sheet with the web field, and of the Open Here sheet (Apple-native, dark-first, Linear/Things references), Ryan picks before c2.
- **c1** `PluginEntries` in `AppDependencies`, wiring in `SegueApp.swift`, `beginSourceReview`, the source line, `PasteSource` / `SongSource` cases; SegueUI tests (15.3).
- **c2** The sheets in the personal package per the picked direction; File menu items and shortcuts; the empty-library buttons; the lone-URL paste; link drops; saved-file import (R179); the Open Here sheet and the blocked fallbacks; Clear Site Data in the Personal build's Settings; help popovers; accessibility.
- **c3** Analytics rows 31-33 with their vocabulary tests; WS3 row table.
- **c4** `forbidden` extended (13), proven with zero false positives, then one `make verify-appstore`.
- **c5** E2E class (15.4) and the App Store method (15.5), one `make e2e-one` each.
- **c6** Draft guide page and its build check; screenshots for it captured from the Personal build.
- End: one `make quick`; launch the Personal build for Ryan's hands-on walk through both features.

## 20. Done criteria

- In the Personal build: one search returns Ultimate Guitar, E-Chords and LRCLIB results grouped by source in that order, only UG chord versions, ranked by the per-song vote-weighted rating, with a preview each; a UG, Chordie, E-Chords (plain, WebKit-loaded or saved page) and generic page each import into the review sheet with the right fields; LRCLIB results open lyrics, Hindi in casual romanization; everything lands only through Accept; R109 holds during a show.
- Every failure in 6.8 and 8.7 shows its message and actions; no alert, crash or saved song from a failure; no captcha-solving anywhere; a page still challenged after its one WebKit load offers Open Here, Open in Safari, a saved page and paste, and a check completed with Open Here lets later hidden loads pass; a hard block starts the one-hour back-off.
- The Private Access Token spike (a0) and the a3 spikes are recorded in `research/phase9-import/README.md`.
- No live network in any test; parser, fetcher, pacer, ranker, variants and romanizer suites green; `make quick` green.
- `make eval-import` meets every 16.3 target, the romanizer's held-out targets included; the romanizer meets 16.5.
- `make verify-appstore` passes with the extended `forbidden`; the App Store UI method passes; the App Store build's behaviour is unchanged.
- Analytics rows 31-33 in the vocabulary, emitted only by the personal package, no site or service name in any raw value.
- `docs/phases/5-personal-modules.md` is a pointer to this spec; section 4.4 is filled from the bake-off.

## 21. Closed questions (R179, R182, R183, 2026-11-01)

1. **Committed fixtures:** lyric-redacted committed fixtures, full pages kept locally (R179; 16.2).
2. **HTML parser:** SwiftSoup 2.14.3, pinned exactly (R182; 4.4). Licence is no object for the Personal build (R179).
3. **User-Agent:** API calls identify as Segue (R179; 6.2, 8.2). The hidden WebKit loader keeps WebKit's own user agent all session and imitates no browser (8.6).
4. **LRCLIB App-Id:** LRCLIB unregistered (R179; 6.2).
5. **Romanize Devanagari from web pages:** yes, fetched text is romanized, pasted text never (R179; 7.1).
6. **Where the romanizer lives:** `SeguePersonalModules`, as native Swift rules with no dependency (R182; 7.3, 7.4, 4.4).
7. **Record the source:** the source URL is not stored (R179; 4.2).
8. **Analytics tokens:** technique names, not sites (R179; section 12).
9. **Share extension:** none (R179; section 1).
10. **Guide pages:** no public guide page (R179; section 17).
11. **Search trigger:** Return (R179; 6.4).
12. **Eval targets:** the spec's accuracy targets stand (R179; 16.3, 16.5); the romanizer's are >= 90% word exact and >= 95% `RomanNormalizer`-equivalent on a held-out set (R182; 16.3).
13. **Synced-lyrics gaps:** stanzas split at gaps of 5 s or more (R179; 6.6).
14. **UG tab-only and Pro pages:** never listed in search (R182; 6.10); refused with a clear message when opened by address (R179; 8.4).
15. **Saved web page files:** `.html`, `.htm` and `.webarchive` import (R179; 8.1).
16. **Shortcuts:** Shift-Cmd-U Import from Web Page, Shift-Cmd-L Find Lyrics (R179; 11.1).
17. **E-Chords search and robots.txt:** robots.txt does not limit user-initiated searches or loads in the Personal build, so E-Chords is searched on the owner's Return (R182; 6.11, 10).

**Bake-off questions** (`docs/research/phase9-import-bakeoff.md` section 6), closed by R182 and R183: the reversed WebKit rule is folded in (1; 8.2, 8.6); robots.txt as in 17 (2); UG's website route, not the signed mobile API (3; 6.10); a persistent cookie store, which R183's "later hidden loads reuse the pass" requires (4; 8.6); Open Here (5, by R183; 8.6); Chordie for URL import only (6; 6.11); groups fixed as UG, E-Chords, LRCLIB (7; 6.4); only chord versions listed (8; 6.10); the romanizer's targets (9; 16.3); the long override spellings woh, nahin, kyun, hain (10; 7.3); UG "Misc" singers from the structured credits (11; 5.4); native Swift romanizer rules (12; 7.3); SwiftSoup 2.14.3 (13; 4.4); LRCLIB's five 503 retries (14; 9); ads and trackers blocked in the hidden view (15; 8.6).

**Prior-art questions** (`docs/research/phase9-import-prior-art.md` section 4), closed by R183: "Open Here" as an action beside Open in Safari and Paste the Page Instead, never shown automatically and never clicked by the app (1; 8.6); the navigation rule applies to the main frame only, with challenge frames and the challenge host allowed, by the ad blocker too (2; 8.6); a one-hour per-site back-off, shown in the source's group (3; 9); the rating prior toward 4.0, its weight scaled per song by the median vote count, clamped to 3-50 (4; 6.10); the cold-store home-page warm-up (5; 8.6); the Private Access Token spike first in the build (6; step a0). The signed mobile API is not used (R182), so no route depends on it (7).

New in R179, differing from or beyond the spec as first written: Ultimate Guitar search with versions ranked by rating and votes, a preview each (6.10); one search grouped by source (6.4, 6.9, 6.11); blocked pages load through a hidden in-app WebKit view with no captcha-solving, Open in Safari or a saved page as the fallback (8.6, replacing "the page is never loaded in a web view"); components picked by the bake-off (4.4).

New in R182 and R183: Chordie dropped from search; the fixed group order; only chord versions listed; the persistent WebKit store, ad blocking, main-frame-only navigation, warm-up, `cType` early stop and Open Here (8.6); the per-site back-off and LRCLIB's five retries (9); the per-song rating prior (6.10); the bake-off's components and romanizer rules (4.4, 7.3); the Private Access Token spike (a0).

Closed by R184: the corpus collector fetches the 20 search pages despite robots.txt (16.1); the back-off starts only on a hard block, E-Chords loads straight through WebKit, the store keeps cookies and clears caches, and the challenge wait is 12 s (8.6, 9). No questions remain open.
