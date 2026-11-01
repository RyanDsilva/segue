# P9-4 - Lyrics search and URL import (Personal build only)

Phase 9 workstream (written 2026-10-31). Ruling: `docs/release/decisions.md` **R176** (v1.0 builds "LRCLIB lyrics search and URL import (Personal build only, so absent from the App Store build) ... each specced with its open questions closed first"). Built on: **R133** / **R138** / **R170** (the feature itself: LRCLIB search plus URL import in `SeguePersonalModules`), the Phase 5 rulings in `docs/decisions.md` (package is a folder in this repo; sites are Ultimate Guitar, E-Chords, Chordie plus a generic page reader; enforcement is mechanical, not repo separation), the Language rulings in `docs/decisions.md` (English plus romanized Hindi only, no Devanagari display, no auto-transliteration of pasted text, app-generated Hindi in casual Bollywood romanization, the lyric preservation guard, autocorrect off in lyric text), **R62** / **R97** (the package already holds Settings > AI > Advanced), **R74** / **R98** (paste analytics, `romanHindi`), **R101** / **R121** / **R124** (code wins over the model; the strict lyric guard), **R117** (review sheet design D1), **R109** (nothing about paste or import may disturb a running show), **R154** / **R158** P8-1 Q8 / **R163** (the near-duplicate check and its `nearDuplicate` flag), **R157** / **R163** / **R164** (`RomanNormalizer`), **R172** / **R173** (several artists split from credit lines; Movie / Album as `{album}`; no song length), **R174** (artists come from code only), **R113** (test budget), **R39** (design directions before new UI), **R11** / **R139** (two bundle IDs; App Store only distribution, so the Personal build never ships).

This doc **replaces `docs/phases/5-personal-modules.md`**, which is now a pointer here. Everything in it that still holds has moved into this spec; its section 4.1 (Devanagari romanization research) is re-verified and updated in section 7 below.

**Build order:** three sessions (section 19). **P9-4a** (corpus, plugin contract, fetcher, page parsers, eval) starts first and touches SegueCore only at `Plugins/` and one `Ingest` entry point. **P9-4b** (LRCLIB, Hindi romanizer) may run beside P9-4a once P9-4a's contract step (step a2) has landed. **P9-4c** (UI, analytics, absence checks, guide, E2E) follows both. The open questions in section 21 are closed before P9-4a starts (R176).

## Session rules (apply to every session)

- `cat` and `ls` are aliased to eza and can hang: use `command cat` / `command ls` or the Read / Grep / Glob tools, and pass this warning to any subagent. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-". Ignore `.build/`.
- Sibling Phase 9 workstreams edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, stage only your own hunks, keep the tree compiling between steps.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget (R113): per step only targeted in-process suites (`swift test --filter <Suite>`); tricky pure logic (each parser, the generic reader, the romanizer, query variants, the pacer) gets table-driven in-process tests; UI behaviour gets in-process SegueUI tests. Exactly **one** new XCUITest class (section 15.4) plus one new method in the existing App Store UI target (section 15.5). At the end of each session ONE `make quick`, plus ONE `make e2e-one` per UI test class the session added or changed. No `make gate`, no `make check`, no E2E retry loops (a failure is investigated, not re-run), no scratch-worktree builds. Every build or test runs under `lockf -k .build/make.lock`. Write this budget into any subagent's prompt.
- **No live network in any test.** Every test reaches the network only through an injected transport fed from saved fixtures (section 15). The only code allowed to touch the real network is the shipping `URLSessionTransport` and the manual tools in section 16.4, which are never part of `make quick`, `gate` or `check`.
- Corpus collection (section 16.1) fetches public pages politely: robots.txt honoured, one request per 5 s per host, a cap per site, and **never any attempt to get past a bot check or challenge page** (none in the app either, section 8.6). A blocked site's pages are saved by Ryan from Safari instead.
- Copyrighted lyrics are never committed (the `research/phase3-eval/pastes` precedent in `.gitignore`). Full fetched pages live in a gitignored folder; committed fixtures are redacted (section 16.2).
- Before using any Apple API not already in the codebase (for example `XMLDocument`, `URLSessionConfiguration.ephemeral` details, `NSItemProvider` URL drops), run the `apple-api-check` skill.
- Read the `macos-app-architecture` skill before adding the test target, the dependency or any file to `Packages/SeguePersonalModules`.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency, including any section 21 question still open when a step reaches it.

## 1. Goal

Ryan finds a song he wants to play. Today he opens the chord site in Safari, selects the page, copies, and pastes it into Segue, which converts it. After P9-4, in the Personal build only, he can:

1. **Paste or type a page address** (or drop a link from Safari) and Segue fetches that one page, reads the chart with a parser made for that site (Ultimate Guitar, E-Chords, Chordie) or a generic reader for any other page, and opens the usual review sheet.
2. **Search LRCLIB for lyrics** by title and artist ("tum hi ho arijit"), pick a result, and get the plain lyrics as a starting point in the same review sheet, already split into sections where the repeats show, with title, artists and Movie / Album filled from the record. Hindi lyrics that LRCLIB holds in Devanagari arrive in casual Latin romanization ("tum hi ho", "pyaar"), never in Devanagari.

Nothing is saved without the review sheet's Accept, exactly as for a paste. The App Store build contains none of this: no code, no menu item, no strings naming the services, checked by `make verify-appstore`.

**In scope:** the plugin contract in SegueCore `Plugins`; one `Ingest` entry point that accepts fields a source already knows; the page fetcher in the sandbox; the three site parsers and the generic reader; LRCLIB search and fetch with romanized-Hindi query variants and local re-ranking; the deterministic Devanagari romanizer; pacing, retries and in-memory caching; the UI entry points (File menu, the empty library, the New Song sheet, a lone pasted URL, a dropped link, a saved web page file); the review sheet's source line and attribution; analytics (Personal only, closed vocabulary); the `verify-appstore` extension; a fixture corpus of real pages and an offline parse-accuracy eval with targets; a manual parser canary; the in-product help and a draft guide page.

**Out of scope:** a Share extension (open question 9); search-as-you-type; publishing or flagging lyrics to LRCLIB; synced-lyrics timing in the song (R172 removed song length; LRC timestamps are only a sectioning hint, section 6.6); any change to the App Store build's behaviour; Devanagari handling of pasted text (stays exactly as pasted, per the Language rulings); batch import of many URLs.

**Unchanged:** the paste flow, the review sheet's design (R117) and its Accept / Cancel / Start blank semantics; the deterministic `IngestPipeline` stages and `JunkRules`; the lyric guard; artists from code only (R174); the near-duplicate score and threshold; `RomanNormalizer` (no version bump, so no index rebuild); the entitlements of both flavours.

## 2. Decisions this spec is built on

| Ruling | What it fixes here |
|---|---|
| R176 | In v1.0, Personal build only, absent from the App Store build. |
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

- **Ultimate Guitar** tab page (`tabs.ultimate-guitar.com/tab/misc-soundtrack/aashiqui-2-tum-hi-ho-chords-1234996`, HTTP 200 to a plain request): the chart is JSON in `<div class="js-store" data-content="...">` (HTML-escaped). Path `store.page.data.tab_view.wiki_tab.content` holds the chart as `[Verse 1]` headers and `[tab][ch]Fm[/ch]\nHum tere bin[/tab]` markup; `store.page.data.tab` holds `song_name` ("Aashiqui 2 - Tum Hi Ho"), `artist_name` ("Misc Soundtrack"), `type` ("Chords"), `tonality_name`, `capo`, `id`; `tab_view.meta.tuning.value` ("E A D G B E"). **V**. The film songs' placeholder artist and "Movie - Title" song name are the norm for Bollywood on UG.
- **Chordie** song page (`chordie.com/chord.pere/<source host>/<path>`, HTTP 200): an aggregator that re-renders other sites' charts as `<div class="chordline">` lines with inline chords in `<span class="bracket">[</span><span class="relc|inlc"><span class="absc Gm">Gm</span></span><span class="bracket">]</span>` and `<div class="textline">` for plain lines; the page title is "<Title> <Artist> Chords and Lyrics for Guitar". **V**.
- **E-Chords**: every request from this Mac got Cloudflare's "Just a moment..." challenge page (HTTP 403). Its chart markup is therefore **not verified** here (historically a `<pre id="core">` block with chords in inline tags: **U**). This is also what the app will often see: section 8.6.
- **LRCLIB** `GET /api/search` returned HTTP 502 from Cloudflare three times in a row (01:50 UTC on 2026-11-01, the evening of 2026-10-31 locally): a real outage case the UI must handle (section 6.8). The API contract below is from its published docs.
- robots.txt: UG disallows `/tab/print?`, `/tab/download` and similar but not `/tab/`; Chordie allows everything but one source path; E-Chords disallows `/search`, `/api/`, `/*/printversion` and similar. The app fetches only the single page the user chose; corpus collection honours these files.

## 4. Architecture

### 4.1 Where the code goes

```
SegueCore (both flavours)
  Plugins/            contract: SongImporter, LyricsSource, value types, PluginRegistry (no implementations,
                      no site or service names in any string literal)
  Ingest/             IngestPipeline.ingest(_:origin:source:) - one new entry point (section 5.1)
SegueUI (both flavours)
  Paste/              generic hosting: PluginEntry list in AppDependencies, a source line in the review header,
                      new PasteSource cases routed like a paste
SeguePersonalModules (Personal only)
  Web/                HTTPTransport port, URLSessionTransport, RequestPacer, PageCache, PageFetcher
  Web/Parsers/        TabJSONParser (UG), ChordPreParser (E-Chords), ChordSpansParser (Chordie), GenericPageReader,
                      PageParserRegistry (host -> parser, then generic)
  Lyrics/             LRCLIBClient, LyricsQueryVariants, LyricsRanker, LRCSections
  Romanization/       HindiRomanizer + its table and override list (section 7)
  UI/                 WebImportField, LyricsSearchSheet, the help popovers (SwiftUI, uses SegueUI theme)
  PersonalModules.swift   registers WebPageImporter and LRCLIBLyricsSource; returns the UI entries
Tests/SeguePersonalModulesTests   new target: fixtures, parser tables, eval scorer (offline)
```

- SegueUI never imports `SeguePersonalModules` (it cannot: the dependency points the other way, `Package.swift:24-27`). The personal package's views use SegueUI's theme and components.
- The only third-party dependency added is the HTML parser (open question 2, recommended SwiftSoup, MIT, pinned exactly), declared in `Packages/SeguePersonalModules/Package.swift` only and imported only in `Web/Parsers/`. A SwiftLint `custom_rules` entry fails `import SwiftSoup` anywhere else (the vendor isolation rule).
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
    public var sourceURL: URL             // shown in the review header, never written to the .cho (Q7)
    public var reader: ReaderKind         // analytics token, section 12
    public var fellBack: Bool             // a site parser failed its checks and the generic reader answered
    public var romanized: Bool            // Devanagari was romanized (section 7)
    public var attribution: String?       // e.g. "Lyrics from LRCLIB" - set by the plugin, shown in the header
}

public enum ReaderKind: String, Sendable, CaseIterable { case tabJSON, chordPre, chordSpans, genericPage, lyricsRecord }

public protocol SongImporter: Plugin {
    /// Cheap and offline: whether this importer takes the input, and which reader it will try.
    func accepts(_ input: ImportInput) -> ReaderKind?
    func importSong(_ input: ImportInput) async throws(ImportFailure) -> ImportedSong
}
public enum ImportInput: Sendable, Hashable { case url(URL), webPageFile(URL) }

public protocol LyricsSource: Plugin {
    func search(_ query: LyricsQuery) async throws(ImportFailure) -> [LyricsCandidate]
    func song(for candidate: LyricsCandidate) async throws(ImportFailure) -> ImportedSong
}
public struct LyricsQuery: Sendable, Hashable { public var text: String; public var title: String?; public var artist: String? }
public struct LyricsCandidate: Sendable, Hashable, Identifiable {
    public var id: String                 // the source's stable record id, as text
    public var title: String; public var artist: String?; public var album: String?
    public var firstLines: String         // first 2 lines, romanized when needed, for the result row
    public var isInstrumental: Bool
    public var lyrics: String?            // full plain lyrics when the search already returned them
}

public enum ImportFailure: Error, Sendable, Hashable {
    case offline, timedOut, busy(retryAfter: Duration?), blocked, notFound,
         notAPage, tooLarge, noChart, unsupportedScript, server(status: Int), cancelled
}
```

- `PluginRegistry` keeps its shape; the empty marker protocols gain these requirements. The `PluginModule` gains nothing: UI entries are composed in the App target (4.3).
- Every type is `Sendable`, and every async call is cancellable (`Task` cancellation maps to `.cancelled`).
- `ImportFailure` is closed: each case has one user message (section 8.7) and one analytics outcome (section 12).

### 4.3 UI hosting (the `advancedSection` pattern)

- SegueUI gains `PluginEntries` in `AppDependencies`: `webImport: WebImportEntry?` and `lyricsSearch: LyricsSearchEntry?`. Each holds the plugin (as `any SongImporter` / `any LyricsSource` from the registry) plus `@MainActor` view builders that return `AnyView` for the personal package's sheet content, and its menu title and shortcut.
- `SegueApp.init` passes `plugins` through: under `#if SEGUE_PERSONAL` it calls `PersonalModules.entries(registry: plugins, ...)`; otherwise both entries are nil. UI code asks "is the entry non-nil?", never checks a build flag.
- With both nil (App Store) every entry point in section 11 is absent: no menu item, no button, no lone-URL banner, no drop target for links, no extra file types in the import panel.

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

- `LibraryViewModel.beginSourceReview(_ song: ImportedSong, source: PasteSource)` opens the same `PasteReviewModel` with one `PasteReviewItem` built from `ingest(_:origin:source:)`. `PasteSource` gains `webPage` and `lyricsSearch` (row 19).
- Guards are the paste guards: `canPaste` (R109: never during a show, never over an open review).
- Everything after that is the paste flow: original text on the left (for a web page, the extracted text, not the HTML), result on the right, sparkle marks for AI decisions, the draft card, Accept writes one undoable song, Cancel writes nothing.
- The header gains one quiet source line under the title (section 11.6).

### 5.3 Near-duplicate check (P8-1)

- The item's existing `nearDuplicates` / `refreshNearDuplicate()` runs on the reviewed text, as for any paste: warning beside the card, never blocking Accept, re-checked on edits, `nearDuplicate` flag on `songCreated` at Accept (R163).
- **Before fetching**, the LRCLIB result list marks a result "In your library" when `NearDuplicateIndex.match(title:artists:lyrics:contentHash:)` over the candidate's title, split artist credit and, when the search returned them, its plain lyrics scores at or above the threshold. Without lyrics the row compares title and artist only through the same index (title similarity gate, then the artist score); the mark is a hint, the full check runs again in the review.
- The URL field does no pre-fetch check (the title is unknown until the page is read).

### 5.4 Several artists and Movie / Album (R172 / R173)

- Source credits split on ",", "&", "feat.", "ft.", "featuring", never "and" (`ArtistNames.split`), shown as chips with Keep as one.
- UG film songs: `TabJSONParser` maps the placeholder artist ("Misc Soundtrack", "Misc Unsigned Bands", any `Misc ...`) to no artist, and a `song_name` of the form "<Movie> - <Title>" to `album` = Movie and `title` = Title (split at the **first** " - " only when the artist is a `Misc` placeholder; otherwise the song name is the title as written). For the probe page: title "Tum Hi Ho", album "Aashiqui 2", no artist. The singer is then whatever the page text states, else empty: never invented.
- LRCLIB: `albumName` sets Movie / Album, unless it equals the title or is a generic value ("Single", "Unknown", empty).
- Chordie and the generic reader: title and artist from the page's structured data first (JSON-LD `MusicComposition` / `MusicRecording`, then `og:title`, then the `<title>` pattern "<Title> Chords by <Artist>" or Chordie's "<Title> <Artist> Chords and Lyrics"), each value checked with `isPlausibleName`.

### 5.5 AI refinement (R101 / R121 / R124 / R174)

- Runs exactly as for a paste, on the merged result: labels only for unheaded blocks, title only when neither the source nor the text gave one, never artists, never Movie / Album, a key only as a suggestion, line classes only for unknown lines, and the lyric guard on every block.
- For LRCLIB lyrics (bare lyrics, no chords) the model's only job is section labels for blocks the repeat labelling left unlabelled. A source title always exists, so the model never fills one.
- The romanizer's output is not a "correction": it runs before the review, deterministically, and the lyric guard then protects that text from the model like any pasted lyric.

## 6. LRCLIB lyrics search

### 6.1 The API (from `https://lrclib.net/docs.md`, fetched 2026-10-31) **V**

- Base `https://lrclib.net`. No key; anonymous access allowed. Clients must identify themselves with `User-Agent: <app name> <version> (<homepage or email>)`; `Lrclib-Client` or `X-User-Agent` where the header cannot be set.
- `GET /api/search?q=` (or `track_name`, `artist_name`, `album_name`; `q` wins): a JSON array of at most 20 records, no pagination.
- `GET /api/get/{id}`: one record. `GET /api/get?track_name&artist_name[&album_name&duration]`: best signature match (duration within 2 s); not used here (no song length exists to send).
- Record: `id`, `trackName`, `artistName`, `albumName`, `duration`, `instrumental`, `hasWordSync`, `plainLyrics` (null for instrumentals), `syncedLyrics` (LRC), `lyricsfile` (YAML).
- Rate limits (approximate, "may change at any time"): ~45 requests/min per IP for generic clients, **~90/min for an identified client**, ~180/min with a registered `Lrclib-App-Id`. Over the limit: HTTP 429 with `Retry-After` (seconds) and a JSON body naming the scope; clients **must** honour `Retry-After` plus up to 30% random jitter, or risk a temporary ban. 503 `ServerOverloaded` also carries `Retry-After` (usually 1 s). Edge rejections may not be JSON: rely on status and `Retry-After`, check `Content-Type` before parsing.
- Throttling guidance: send requests sequentially, 200-500 ms apart.
- Licence: the server code is MIT (`github.com/tranxuanthang/lrclib`, checked 2026-10-31). **No content licence or terms of use for the lyrics were found** (docs, `llms.txt`, `llms-full.txt`, a web search): the lyrics are crowdsourced and their copyright belongs to the rights holders. This is why the feature stays Personal (section 10).

### 6.2 The client (`Lyrics/LRCLIBClient.swift`)

- `User-Agent: Segue/<CFBundleShortVersionString> (+https://segue.ryandsilva.dev)`, plus `Lrclib-Client` with the same value. No App-Id (open question 4).
- Search: `GET /api/search?q=<query>` only (the free-text form handles "tum hi ho arijit"; the structured form is used for a variant only when the user filled the optional Artist field, section 6.4).
- Fetch: the search response already holds full records, so picking a result normally needs **no second request**; `GET /api/get/{id}` only when the search record had `plainLyrics == nil` but `instrumental == false` (a truncated or changed response).
- Decoding is tolerant: unknown fields ignored, missing optional fields nil, a non-JSON or non-array body is `.server(status:)`.
- All requests go through the shared `RequestPacer` (section 9) for host `lrclib.net`.

### 6.3 Romanized-Hindi search (the owner's rule)

LRCLIB's search is a server-side keyword match, so "tuj mai rab" may find nothing while "tujh mein rab" finds the song. Segue cannot change the server; it widens the query deterministically and ranks locally:

1. **Query as typed** first, always.
2. **Variants** (`Lyrics/LyricsQueryVariants.swift`, pure): when the first response has fewer than 5 results **and** the query is romanized Hindi (at least one word in `RomanizedHindi.markers` or the variant table), build at most **two** more queries by swapping each word for its most common attested spelling from a small hand-curated table keyed by `RomanNormalizer`'s normal form (for example normal form `mai` -> "mein", "main"; `tuj` -> "tujh"; `pyar` -> "pyaar"; `dil` -> "dil"; `kabi` -> "kabhi"; `nahi` -> "nahin", "nahi"). Variant 1 uses each word's top spelling; variant 2 the second where one exists. Words not in the table stay as typed. The table is data with tests (add words, never logic), shares its source words with the romanizer's override list (section 7.3), and is licence-clean (hand-curated).
3. **At most 3 requests per search**, sequential, paced (section 9). A variant identical to an earlier query is skipped.
4. **Merge and rank** (`Lyrics/LyricsRanker.swift`, pure, with a per-result score breakdown for tests): results deduplicated by `id`, then by (loose title, loose artist); score = 0.55 x title similarity + 0.25 x artist similarity + 0.10 x lyric-start similarity + 0.10 x "has plain lyrics", where every similarity is computed on `RomanNormalizer.loose` forms with the same word-overlap measure `NearDuplicateIndex` uses for titles. The query's words are matched against title, then artist, then the first lyric line. Instrumental records sort last and cannot be picked.
5. **No AI anywhere in search**: no model rewrites the query or "corrects" a spelling. The user's text is sent as typed, the variants are deterministic and shown ("Also searched: tujh mein rab"), and nothing the user typed is changed in their field.

### 6.4 Search UI (exact behaviour; visual design from step c0)

- Sheet "Find Lyrics", 640 x 480 like the New Song sheet. One search field (placeholder "Song title, artist or a line", focused, `autocorrectionDisabled()`, spell-check off, no smart substitutions) and an optional "Artist" field behind a disclosure, also with autocorrect off.
- Search runs on **Return** or the Search button only (open question 11). While running: a small spinner in the field, previous results stay greyed. Cancel (Esc) cancels the request.
- Results: up to 20 rows: title (bold), "artist - Movie / Album" (muted), first two lyric lines (muted, small), and quiet marks "In your library" (5.3), "Instrumental" (disabled row), "Converted from Devanagari" (when the lyrics needed romanizing, section 7). Up/Down moves the selection; Return or double-click opens the review. Under the list, when variants ran: "Also searched: <variant>, <variant>".
- Attribution line at the bottom left: "Lyrics from LRCLIB, a free community database. Check them against the recording." with the LRCLIB link (opens in the browser).
- Picking a result builds `ImportedSong` (text = the plain lyrics after romanization and `LRCSections`; fields from the record; provenance `lyricsRecord`) and replaces the sheet with the review sheet (one sheet at a time, like New Song's input state moving to review).

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
| `busy(retryAfter:)` (429, 503) | "LRCLIB is busy. Try again in <n> seconds." The Search button stays disabled until then. | automatic enable |
| `server` (5xx, 502 as probed) / `timedOut` (15 s) | "LRCLIB isn't answering right now." | Try Again |
| `unsupportedScript` | row disabled, as 6.5 | none |

## 7. Romanization (replaces phase 5 sections 4 and 4.1)

### 7.1 Rule

LRCLIB, and some web pages, hold Hindi lyrics in Devanagari. The app may not display Devanagari, and the Language rulings require text **the app itself generates** to be in casual Bollywood romanization without diacritics ("tum hi ho", "pyaar", "dil", "hai"). A deterministic `HindiRomanizer` converts it: no language model in the loop, so the output is reproducible and testable.

- It runs only on text Segue fetched (LRCLIB records; web pages, open question 5). **Pasted text is never transliterated** (Language rulings), and a pasted Devanagari song keeps flowing through the paste path unchanged.
- It touches only Devanagari runs. Latin text, including romanized Hindi and English in mixed lines, passes through byte-identical; digits, punctuation and spacing are kept.
- It never respells Latin words, never "corrects" a romanized Hindi word, and its override list only chooses how a Devanagari word is first written in Latin.
- The review shows "Converted from Devanagari" in the source line (11.6) so the user knows the spelling was generated, and can edit any word before Accept.

### 7.2 Research, re-verified 2026-10-31 on macOS 26.6.2

- **Apple ICU `.toLatin`** (local probe re-run today, `String.applyingTransform(.toLatin, reverse: false)`) is ISO-15919-like, exactly as the 2026-10-17 probe found: `तुम ही हो` -> "tuma hī hō", `चलते` -> "calatē", `आँखें` -> "ām̐khēṁ", `क्यों` -> "kyōṁ", `दीवाना` -> "dīvānā", `प्यार` -> "pyāra", `दिल` -> "dila". With `.stripDiacritics`: "tuma hi ho / calate / amkhem / kyom / divana / pyara / dila". It has no schwa deletion ("tuma", "pyara", "dila"), writes च as "c", writes anusvara and chandrabindu as "m", and loses vowel length. **V**. Verdict unchanged: not a usable base.
- **`indic_transliteration` (sanscript) and `common_maps`**: both **MIT** (GitHub licence metadata, both active in October 2026). **V**. A full-text grep of the sanscript source finds no schwa or inherent-vowel deletion; its `to_lay_indian` (OPTITRANS -> lay Indian, e.g. "kRShNa" -> "krishna") only rewrites a few clusters and lowercases, so it also keeps every final "a" and drops vowel length. **V**. Usable only as a reference for the consonant and matra table.
- **Aksharamukha**: README states GNU AGPL 3.0. **libindic `indic-trans`**: AGPL-3.0 (GitHub metadata). **V**. Avoid both.
- **IndicXlit** (AI4Bharat): MIT, but an ML model; excluded by the no-model rule. **V**.
- **Google Dakshina** (romanization lexicons with attested casual spellings): **CC BY-SA 4.0** (README); the repository is archived (2020). **V**. Share-alike would attach to a derived word list, so it is used **only as a local eval oracle** (gitignored download), never shipped and never committed.
- Schwa deletion rule family: Narasimhan, Sproat and Kiraz, "Schwa-deletion in Hindi text-to-speech synthesis", *International Journal of Speech Technology* 7, 2004 (published-venue citation; **U**: not re-read for this spec).

### 7.3 Algorithm (`Romanization/HindiRomanizer.swift`, about 300 lines plus `HindiRomanizer+Table.swift`)

1. **Segment** the text into Devanagari runs and everything else (Unicode scalar ranges U+0900-U+097F and U+A8E0-U+A8FF); only runs are converted, word by word (a word is a maximal run of Devanagari letters and marks).
2. **Override list first**: a hand-curated dictionary of frequent lyric words whose casual spelling the rules would not produce (for example `है` "hai", `हैं` "hain", `में` "mein", `मैं` "main", `क्यों` "kyun", `नहीं` "nahin", `प्यार` "pyaar", `दिल` "dil", `तुम` "tum", `ज़िंदगी` "zindagi", `आँखें` "aankhen", `दीवाना` "deewana", `हूँ` "hoon", `वो` "woh"). Seeded with about 300 words from Bollywood lyrics by hand; every entry has a test row.
3. **Graphemes** with a casual map: consonants क k, ख kh, ग g, घ gh, च ch, छ chh, ज j, झ jh, ट t, ठ th, ड d, ढ dh, ण n, त t, थ th, द d, ध dh, न n, प p, फ ph, ब b, भ bh, म m, य y, र r, ल l, व v (w before a vowel at word start where the override list says so), श sh, ष sh, स s, ह h; nukta forms क़ q, ख़ kh, ग़ gh, ज़ z, फ़ f, ड़ r, ढ़ rh. Vowels and matras: अ a, आ/ा aa, इ/ि i, ई/ी ee (word-final "i"), उ/ु u, ऊ/ू oo (word-final "u"), ए/े e, ऐ/ै ai, ओ/ो o, औ/ौ au, ऋ/ृ ri. Virama joins clusters.
4. **Nasals**: anusvara ं and chandrabindu ँ become "n", or "m" before प फ ब भ म.
5. **Schwa deletion**: drop the word-final inherent "a" (except after a cluster that needs it, e.g. a conjunct ending a word); drop a medial inherent "a" in a V C _ C V context when the following syllable carries a full vowel (`चलते` -> "chalte", `समझना` -> "samajhna" stays because of the cluster rule table). Words of one consonant keep their "a" (`न` "na").
6. **Output** lowercase, no diacritics, original punctuation and spacing; the first letter of a line is capitalised only if the line was a title or name field.

Tests: a table of a few hundred Devanagari words and 30 full lyric lines with expected casual output (section 15.1), plus a local Dakshina check (16.5).

### 7.4 Where it lives

`SeguePersonalModules/Romanization/` (open question 6). It has no caller in the App Store build in v1.0, and keeping it in the personal package means the App Store binary is unchanged by this workstream. It is pure Foundation code with no UI, so moving it down to SegueCore later is one file move.

## 8. URL import

### 8.1 Inputs

- An `http` or `https` URL typed or pasted in the web field (11.3), pasted alone into the New Song text area (11.4), dropped from Safari onto the library (11.5), or chosen with File > Import from Web Page...
- A saved page file (`.html`, `.htm`, `.webarchive`) through Import Songs... or a drop (open question 15): the same parsers, no network.
- Anything else (`file:`, `ftp:`, `javascript:`, a host without a dot, an IP literal in a private range, `localhost`) is refused before any request with "Segue imports web pages only (https://...)." Private-range refusal keeps the feature from probing the local network.

### 8.2 The fetcher (`Web/PageFetcher.swift`, `Web/URLSessionTransport.swift`)

- **Sandbox**: outgoing connections are already allowed by `com.apple.security.network.client` and `ENABLE_OUTGOING_NETWORK_CONNECTIONS` in both flavours (3.1). Nothing new is entitled; the App Store build simply contains no fetcher.
- `HTTPTransport` is a port (`func send(_ request: HTTPRequest) async throws(ImportFailure) -> HTTPResponse`), with `URLSessionTransport` (shipping) and `FixtureTransport` (tests, E2E): the injectable IO the deterministic tests need.
- `URLSessionConfiguration.ephemeral` with `httpCookieStorage = nil`, `httpShouldSetCookies = false`, `urlCache = nil`, `httpMaximumConnectionsPerHost = 1`, `waitsForConnectivity = false`, request timeout 15 s, resource timeout 30 s. No cookies, credentials or cache ever touch disk, and the user's Safari session is never used.
- `GET` only, `Accept: text/html,application/xhtml+xml`, `Accept-Language: en`, the identifying User-Agent of 6.2 (open question 3). No JavaScript runs: the page is never loaded in a web view.
- Redirects: at most 5, `http` -> `https` allowed, `https` -> `http` refused, every hop re-checked against 8.1's scheme and host rules.
- Body cap **5 MB** (streamed; over the cap is `.tooLarge`). `Content-Type` must be `text/html`, `application/xhtml+xml` or `text/plain` (else `.notAPage`). Charset from the header, then `<meta charset>`, then UTF-8 with Windows-1252 fallback (the converter already handles CP1252 quotes).
- HTTP 404/410 -> `.notFound`; 401/403 -> `.blocked`; 429/503 -> `.busy(retryAfter:)`; other 4xx/5xx -> `.server(status:)`.

### 8.3 Choosing a reader (`Web/Parsers/PageParserRegistry.swift`)

1. By host (exact suffix match, no regex): `ultimate-guitar.com` -> `TabJSONParser`; `e-chords.com` -> `ChordPreParser`; `chordie.com` -> `ChordSpansParser`.
2. The site parser returns an `ImportedSong` or nil. Its result must pass the **sanity checks** (8.5); if it returns nil or fails them, the `GenericPageReader` runs on the same HTML and the provenance records `fellBack = true`.
3. Any other host: `GenericPageReader` directly.
4. If the generic reader also finds no chart: `.noChart` (8.7).

### 8.4 The parsers

Each parser is a pure function `(HTML string, URL) -> ImportedSong?` with no network, so every one runs offline against fixtures.

**`TabJSONParser` (Ultimate Guitar, verified 3.6).**
- Find `<div class="js-store" data-content="...">` (by attribute, not position), HTML-unescape, decode as JSON with `JSONSerialization` (tolerant: navigate by key path, never a strict `Codable` model, so added fields cannot break it).
- Chart: `store.page.data.tab_view.wiki_tab.content`. Convert UG markup to text: `[tab]` / `[/tab]` removed (the pair marks a chord line plus its lyric line, kept as two lines), `[ch]X[/ch]` -> `X` keeping column positions (the chord line is monospace-aligned in UG's text), `[Verse 1]`-style headers kept (the converter reads them), `\r\n` normalised.
- Fields: `tab.song_name`, `tab.artist_name` (with the `Misc ...` rule of 5.4), `tab.tonality_name` -> key, `tab.capo` -> capo. `tab.type` must be "Chords" or "Ukulele Chords" (or absent); "Tab", "Bass Tab", "Pro", "Power" and "Video" pages are refused with "This page is a tab, not a chord chart" (`.noChart`), because the chart is notation Segue does not read (Pro/Power content is not in the page at all).
- Fallback path if `js-store` is missing: the generic reader (UG has served server-rendered `<pre>` pages in the past).

**`ChordSpansParser` (Chordie, verified 3.6).**
- Walk the song container in document order: each `div.chordline` becomes one line in inline-chord form, writing each `span.absc` chord as `[X]` at its position in the text (the `bracket` spans dropped), so `Hey zu [Gm]Hmm Hm[D]m` reaches the converter as inline ChordPro chords; each `div.textline` becomes a plain line (blank text -> blank line).
- Fields: from `<title>` "<Title> <Artist> Chords and Lyrics for Guitar" only when the page's breadcrumb or heading gives the split; else title only, artist from the chart's own credit line if the converter finds one. Chordie re-hosts other sites, so the first lines often carry "By <names>" credits: the converter's credit-line rule already reads those.

**`ChordPreParser` (E-Chords, unverified 3.6).**
- Built in P9-4a step a4 from pages Ryan saves in Safari (File > Save As, Page Source) because plain requests meet a challenge page. Expected shape (to verify): one `<pre>` holding chords over lyrics with chords wrapped in inline tags; the parser keeps the `<pre>` text with tags stripped and column positions intact. Fields from the page heading.
- If the saved pages show a different shape, the step implements that shape and records it here.

**`GenericPageReader` (any page).**
1. Parse the HTML with the chosen parser (open question 2); drop `script`, `style`, `noscript`, `template`, `svg`, `iframe`, `form`, `nav`, `header`, `footer`, `aside` and elements whose `class`/`id` say ad, comment, share, related, menu, cookie, banner, sidebar.
2. Candidate blocks: every `<pre>`, every element whose `class`/`id` contains chord, lyric, tab, song, sheet, chart, and every element with at least 4 `<br>` children.
3. Render each candidate to text: `<br>` and block ends -> newline, whitespace kept inside `<pre>` and elements styled monospace, inline elements whose whole text is a chord token (`ChordLines.kind(of:) != .unknown`) inside a lyric line -> `[X]` at that position (pages that mark chords up inline), entities decoded.
4. Score each candidate with core's line classifier (`FormatDetector.classify`): +3 per chord line followed by a lyric line, +1 per lyric line, +2 per section header, -2 per junk line (`JunkRules`), -1 per line over 200 characters; ignore candidates under 4 lines. Pick the highest; when two overlap (a parent and its child) prefer the smaller with at least 90% of the score.
5. Fields: JSON-LD (`MusicComposition`, `MusicRecording`, `CreativeWork` name / byArtist / inAlbum), then `og:title` / `og:description`, then `<h1>`, then `<title>`, each split with the "X Chords by Y", "X - Y Chords", "X Lyrics" patterns and checked with `isPlausibleName`.

### 8.5 Robustness against layout changes

- **Selectors by meaning, not position**: attribute and class lookups, JSON key paths, never "the third div".
- **Sanity checks** on every parser result before it is used: at least 4 non-blank lines; at least 2 lyric lines; when chords are present, at least 80% of chord tokens parse as chords (`ChordLines.kind`); no line made only of site words (`JunkRules`); the title, when given, passes `isPlausibleName`. A failure falls back to the generic reader (8.3), never to a half-parsed chart.
- **Visible fallback**: the review's source line says "Read with the general page reader" when `fellBack` is true, and analytics carries `fellBack` (12), so a site's layout change shows up both to Ryan and on the dashboard.
- **Corpus regression**: every parser change runs the offline eval (16); a page that passed and now fails is a regression the session fixes before committing.
- **Manual canary** (`make import-canary`, 16.4): fetches one known page per site, runs the parser, prints pass or which check failed. Never in `quick`, `gate` or `check`.

### 8.6 Bot checks and blocked sites

- A response that is a challenge page (HTTP 403/503 with `cf-mitigated: challenge`, or a body containing the Cloudflare "Just a moment..." title, or a CAPTCHA form) is `.blocked`. The app never retries it, never waits it out, never imitates a browser to get past it, and never asks the user to solve it inside Segue.
- The message offers the two honest paths that already work: **Open in Safari** (the page, in the user's browser) and **Paste the page instead** (select the page in Safari, copy, then New Song from Clipboard, the existing paste flow), plus, for a saved page, "Or save the page in Safari and drop the file here" when open question 15 lands.

### 8.7 Failure messages (inline in the web field area; the field keeps the URL)

| `ImportFailure` | Message | Actions |
|---|---|---|
| `offline` | "You're offline. Importing a web page needs the internet." | Try Again |
| `timedOut` / `server` | "<host> isn't answering right now." | Try Again, Open in Safari |
| `blocked` | "<host> doesn't let apps read this page." | Open in Safari, Paste the Page Instead |
| `notFound` | "That page doesn't exist anymore." | Open in Safari |
| `notAPage` / `tooLarge` | "That address isn't a web page Segue can read." | none |
| `noChart` | "Segue couldn't find a chord chart on this page." (or the tab-not-chords text of 8.4) | Open in Safari, Paste the Page Instead |
| `busy` | "<host> is busy. Try again in <n> seconds." | automatic enable |

Never an alert, never a crash, never a saved song. The diagnostic log records only the reader kind, the failure case and the HTTP status class, never the URL, host, title or any page text.

## 9. Rate limiting and caching

- **`RequestPacer`** (an actor with an injected `Clock`, so tests are deterministic): one in-flight request per host; minimum gap 300 ms for `lrclib.net`, 2 s for any other host; `Retry-After` honoured with up to 30% jitter (randomness injected); after a 429 the host is held for the full `Retry-After` and the UI shows the countdown; after a 503 one automatic retry once `Retry-After` (default 1 s) has passed, then the failure. No other automatic retries.
- **User actions bound traffic**: one page fetch per Import action; at most 3 LRCLIB requests per Search (6.3); no prefetching, no background requests, no polling, no request at launch.
- **`PageCache`** (in memory only, per launch): the last 20 fetched pages keyed by final URL for 10 minutes, so Cancel then re-import, or a second look, costs nothing; LRCLIB searches keyed by exact query text for 10 minutes, records by id for the launch. Nothing fetched is written to disk outside the song the user accepts, so no copyrighted page or lyric is kept by Segue unless the user saved it into their library.
- Memory: the cache drops entries on `memoryPressure` warnings and is cleared when the library closes.

## 10. Legal and terms (personal use)

- **Why Personal only**: LRCLIB publishes no content licence (6.1); the lyrics belong to their rights holders. Ultimate Guitar's terms (`ultimate-guitar.com/about/tos.htm`, read 2026-10-31) say content "may be accessed for your personal, non-commercial use only" (6.3), "you will not duplicate or otherwise reproduce the Content" (6.2) except printing tabs and lyrics for personal, non-commercial use, and that UG's lyric licences cover display "solely on or through the Service" (7.7). **V**. E-Chords and Chordie terms were not read (**U**); Chordie re-hosts other sites' charts. A store build that fetched and stored these would breach those terms; a personal tool that fetches one page Ryan chose, for his own non-commercial use, is the use the owner accepts (`docs/research.md`: "ToS forbids scraping -> URL import is personal-only").
- The Personal build is never distributed (R139: App Store only, no DMG, no Developer ID), so these features never reach anyone but Ryan.
- Behaviour that keeps it a personal tool: one user-chosen page per action, honest identification, no circumvention of bot checks (8.6), no crawling or following links, no bulk or scheduled fetching, nothing cached to disk, no redistribution (Segue has no sharing of fetched content; the user's own library export is their own copy).
- No acknowledgement of LRCLIB or the sites goes into `THIRD_PARTY_NOTICES.md` or the website (both ship with or describe the App Store build, which has none of this). The attribution lives in the Personal build's own sheet (6.4) and source line (11.6). SwiftSoup (if adopted) **does** get a `THIRD_PARTY_NOTICES.md` row, because `scripts/check-docs.sh` check 3 fails without one for any pin in `Tuist/Package.resolved`; the row says "Personal build only". That names a parser library, not a service or site, so it reveals nothing about these features.

## 11. UI entry points and exact behaviour

All entry points exist only when the matching `PluginEntries` value is non-nil (4.3). All are disabled during a show with the existing reason "Paste is unavailable while a show is running" (R109), and none opens while a review sheet is open (`canPaste`).

### 11.1 File menu (`FileCommands.swift`)

After "Import Songs...":
- **"Import from Web Page..."** Shift-Cmd-U (new `MenuShortcuts.importWebPage`). Opens the New Song sheet with the web field focused (11.3).
- **"Find Lyrics..."** Shift-Cmd-L (new `MenuShortcuts.findLyrics`). Opens the Find Lyrics sheet (6.4).

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

Under the header title, one muted line, 12.5 pt: for a web page "From <host>" (the host as a link that opens the page in the browser), plus " - read with the general page reader" when `fellBack`; for LRCLIB "Lyrics from LRCLIB" (link to the record's LRCLIB page). Plus " - converted from Devanagari" when `romanized`. Nothing else in the review changes.

### 11.7 In-product help

A "?" button in the Find Lyrics sheet and beside the web field opens a popover (the owner's in-product guide rule): what the feature does, that results are a starting point to check, that blocked sites can be pasted instead, that nothing is kept unless accepted, and that it exists only in the Personal build.

## 12. Analytics (Personal build only, closed vocabulary, WS3 rules)

Only the personal package emits these, so only the Personal TelemetryDeck app receives them. The cases are core vocabulary (3.5) and ship in both binaries, so **no raw value names a site or service** (open question 8): readers are named by technique.

- `PasteSource` (row 19) gains `webPage` and `lyricsSearch`. `SongSource` (row 5) gains `web` (a song accepted from a web page or a lyrics result); `nearDuplicate` works as today.
- **Row 31 `Segue.Import.pageRead`** (one per Import action): `reader: ReaderKind` (`tabJSON`, `chordPre`, `chordSpans`, `genericPage`), `fellBack: Bool`, `outcome: WebImportOutcome` (`reviewed`, `noChart`, `blocked`, `notFound`, `offline`, `busy`, `failed`, `cancelled`), `latency: LatencyBucket`, `entry: WebImportEntryPoint` (`menu`, `emptyState`, `sheetField`, `pastedURL`, `droppedLink`, `savedFile`).
- **Row 32 `Segue.Import.lyricsSearched`** (one per Search): `results: SmallBucket`, `variants: SmallBucket` (0-2), `outcome: LyricsSearchOutcome` (`results`, `none`, `busy`, `offline`, `failed`, `cancelled`), `romanHindiQuery: Bool`, `latency: LatencyBucket`.
- **Row 33 `Segue.Import.lyricsPicked`** (daily per rank bucket): `rank: SmallBucket`, `fromVariant: Bool`, `romanized: Bool`, `inLibrary: Bool`.
- Row 19's existing fields then tell how the AI refinement and the guard did on these sources, and row 29 (artist split) covers their credits.
- Never recorded: the URL, host, query, title, artist, lyrics, record id, HTTP status code (only the outcome case). Breadcrumbs: none added.
- Throttling follows `AnalyticsEvent+Throttle.swift` (rows 31-32 per occurrence, row 33 daily per rank). The WS3 spec's row table (`docs/release/specs/WS3-services.md` section 5) gains rows 31-33 in step c5; the privacy page needs no change (the App Store build sends none of them).

Metrics this enables: fetch success rate per reader, fallback rate per reader (layout drift), blocked rate, search hit rate with and without variants, how often romanization fires, pick rank (ranker quality), and with row 19 the review acceptance rate and correction rate per source.

## 13. Absence from the App Store build (`make verify-appstore`)

- The code is absent by construction: only the Personal target links `SeguePersonalModules` (`Project.swift:203-206`), and every site and service name lives in that package.
- Step c4 extends `forbidden` in `scripts/lib/verify-common.sh:11` with patterns that cannot collide with core text (3.2): `lrclib|LRCLIB|ultimate-guitar\.com|e-chords\.com|chordie\.com|TabJSONParser|ChordPreParser|ChordSpansParser|GenericPageReader|HindiRomanizer|URLSessionTransport`. `SwiftSoup` is deliberately **not** in the list: `scripts/check-docs.sh` check 3 requires every pin in `Tuist/Package.resolved` (which resolves the personal package too) to have a row in `THIRD_PARTY_NOTICES.md`, and that file ships in the App Store bundle, so the name would be a false hit. Its symbols are still covered: the link map and `nm` checks match the package's own type names above, and SwiftSoup is reachable only through them. The bundle-wide byte grep, the link map and `nm` then fail the build if any of them leaks into Release-AppStore or Debug-AppStore.
- Before the change, run the extended pattern over today's App Store products to prove zero hits (no false positives), and record the run in the commit message.
- The App Store UI test (15.5) proves no entry point is visible. `verify-archive.sh` check 4's exact entitlement set needs no change.

## 14. Accessibility

- Every new control has a label and an identifier in `AccessibilityID+Paste.swift` (`pasteWebField`, `pasteWebImport`, `pasteWebMessage`, `findLyricsField`, `findLyricsArtist`, `findLyricsResults`, `findLyricsResult(<n>)`, `findLyricsAttribution`, `reviewSourceLine`, `emptyLibraryWebImport`, `emptyLibraryFindLyrics`).
- Result rows read as "<title>, <artist>, <album>. In your library." with the first lines as the hint. Failure messages are announced (`AccessibilityNotification.Announcement`).
- Full keyboard use: Tab order field -> Artist -> results; Up/Down in results; Return picks; Esc cancels a running request first, then closes.

## 15. Tests (R113 budget)

### 15.1 SeguePersonalModules, in-process (new test target `SeguePersonalModulesTests`, Swift Testing)

- Add the target to `Packages/SeguePersonalModules/Package.swift` with `Tests/Fixtures` as a resource, and add the package to `make test-packages` (Makefile `test-packages`, step a1). A test helper fails any test that constructs `URLSessionTransport` (the only real-network type), so a test cannot reach the network by accident.
- **Parsers, table-driven over the committed redacted fixtures** (16.2): each fixture page -> expected `ImportedSong` (text and fields) for `TabJSONParser`, `ChordSpansParser`, `ChordPreParser`, `GenericPageReader`; plus malformed variants made from them in code (the `js-store` attribute removed, JSON truncated, class names renamed, an empty `<pre>`) that must fall back or fail cleanly, never crash or return a half chart.
- **Sanity checks and fallback**: a parser result failing each check routes to the generic reader with `fellBack`.
- **Fetcher with `FixtureTransport`**: redirects (limit, https->http refused), size cap, content types, charset detection, each status mapping, challenge-page detection, private-host refusal.
- **`RequestPacer`** with an injected clock and seeded randomness: per-host gaps, `Retry-After` plus jitter bounds, the single 503 retry, cancellation.
- **LRCLIB client** over recorded JSON responses (real response shapes, redacted lyrics): decode, tolerant fields, instrumental, null lyrics -> `/api/get/{id}`, non-JSON 502 body.
- **`LyricsQueryVariants`** and **`LyricsRanker`** tables: "tuj mai rab" produces "tujh mein rab"; English queries produce no variants; ranking breakdowns sum to the score; dedup.
- **`LRCSections`**: gap threshold, no synced lyrics, blank lines present.
- **`HindiRomanizer`**: a few hundred word rows plus 30 lines; Latin and mixed lines byte-identical; digits and punctuation kept; every override entry.

### 15.2 SegueCore, in-process

- `IngestPipeline.ingest(_:origin:source:)`: source fields win; text fills gaps; the credit splits with `artistSplits`; `{album}`; an unparsable key dropped; ChordPro passthrough untouched; the page heading line consumed. Table-driven in `IngestTests`.
- `Refinement.apply` on a source result: no artist or album change from the model; title unchanged when the source gave one.
- Analytics: rows 31-33 render to valid signal names and values (the existing vocabulary test pattern), and no raw value contains a site or service name (a test over `allCases`).

### 15.3 SegueUI, in-process

- `beginSourceReview` opens one item with the right `PasteSource`, honours `canPaste` and R109; Accept records `songCreated(.web, nearDuplicate:)`.
- The lone-URL rule (11.4): only a single trimmed `http(s)` URL routes to the web field, and only when the web entry exists.
- With nil entries (App Store composition) no web or lyrics affordance is produced by the view models.

### 15.4 E2E: `SegueWebImportE2ETests` (new, one class, one test, P9-4c)

On the Personal flavour with a Debug-only launch option (`-SegueImportFixtures <dir>`, compiled only under `#if DEBUG && SEGUE_PERSONAL`, so `check_no_test_hooks` keeps Release clean) that swaps in `FixtureTransport` serving the redacted UG and LRCLIB fixtures: clean library -> File > Import from Web Page... -> paste the fixture URL -> review shows title "Tum Hi Ho", Movie / Album "Aashiqui 2", the source line, sections -> Accept -> the song is in the library; then File > Find Lyrics... -> "tum hi ho" -> pick the first result -> review shows the attribution line and labelled sections -> Cancel writes nothing. The library is reset to the known clean baseline before the run.

### 15.5 App Store UI test (one method in the existing `SegueAppStoreUITests` target)

Launch the App Store flavour on an empty library: the File menu has no "Import from Web Page..." or "Find Lyrics..."; the empty library has no web or lyrics buttons; pasting a lone URL into New Song converts it as text, as today.

### 15.6 Per session

One `make quick` at the end of each session; one `make e2e-one TEST=SegueWebImportE2ETests` in P9-4c; one `make e2e-one` for the App Store method; one `make verify-appstore` in P9-4c step c4. Nothing else.

## 16. Corpus and eval

### 16.1 Collecting real pages (owner's rule: grow the corpus by fetching)

- `scripts/collect-import-corpus.sh` (P9-4a step a3, manual): reads `research/phase9-import/urls.tsv` (site, URL, language tag), fetches each page with the shipping User-Agent, honours robots.txt, waits 5 s between requests to a host, saves to `research/phase9-import/pages/<site>/<slug>.html` (**gitignored**, like `research/phase3-eval/pastes`), and logs challenge pages as skipped (no retry, no workaround).
- Target size: **60 pages**: 15 UG, 15 Chordie, 15 E-Chords (saved by Ryan from Safari, because plain requests are challenged: the step hands Ryan the list of URLs and the exact Safari steps), 15 generic from at least 8 other sites (Hindi chord blogs, other chord sites). At least half are Bollywood / Hindi film songs (romanized Hindi lyrics, "Misc Soundtrack" credits, several singers), the rest English; include a page with a capo, one with a key change, one tab-only UG page, one Pro page, one page with inline chord markup.
- LRCLIB: 30 recorded search responses (`research/phase9-import/lrclib/<query>.json`, gitignored): 15 Hindi queries typed in casual spellings, including 5 deliberately "wrong" spellings to test variants, and 15 English; at least 5 records in Devanagari.
- Gold files: for each page, the expected `.cho` (title, artists, album, key, capo, sections, chords, lyrics) written by hand in step a3 and checked by Ryan for a sample of 10 (gitignored with the pages: they contain lyrics).

### 16.2 Committed fixtures (redacted)

`scripts/redact-import-fixture.swift` turns a page and its gold into a committed fixture under `Packages/SeguePersonalModules/Tests/Fixtures/web/`: markup, attributes, JSON structure, chords, section headers, whitespace and line lengths kept; every lyric word replaced by a deterministic placeholder of the same length and case pattern (with a fixed seed, so romanized-Hindi shape like "Hum tere bin" becomes "Lor ipsu met"), titles and names replaced by placeholders. Hindi romanizer fixtures use public domain or self-written Devanagari lines. About 20 redacted pages (at least 4 per reader) are committed; the parser tests (15.1) run on these. Open question 1 asks whether this redaction rule stands.

### 16.3 The eval (`make eval-import`, manual, offline)

- A small executable target in the personal package (`segue-import-eval`) runs every reader on every gitignored page (or, without them, the committed fixtures) and scores against gold. Never in `quick`, `gate` or `check`.
- Per page and per field: title, artists (as a set), album, key, capo: exact after `RomanNormalizer.loose`; lyric words: word-level accuracy (1 - word edit distance / gold words); chords: token F1 and placement (a chord within one character of its gold column, or on the same syllable for inline charts); sections: label accuracy per block; junk: count of junk lines left in.
- **A page passes** when title is right, artists right, lyric word accuracy >= 99%, chord F1 >= 98% with placement >= 95%, and no junk line remains.
- Output: a table per reader, the failing pages with the first failing field, and code-only versus with-model accuracy per field (the model run uses `make eval-ai`'s provider setup when the model is present), so the AI step is measured, not assumed.

**Targets (gate for P9-4a done):** site readers (UG, Chordie, E-Chords) **>= 95%** of their pages pass; generic reader **>= 80%** of generic pages pass; **zero** silent wrong charts: every failing page either falls back or reports `.noChart` / a review that differs from gold only in fields the user sees highlighted (no page produces an unflagged wrong title or artist). LRCLIB: the correct record is in the top 3 for >= 90% of the 30 queries and top 1 for >= 75%; variants rescue at least 4 of the 5 misspelled queries. Romanizer: >= 90% word agreement with the hand-written gold lines.

### 16.4 Canary

`make import-canary` (manual, live network): one known public page per site plus one LRCLIB search; prints pass or the failing check per reader. Run by Ryan when a fetch fails in daily use, and once before v1.0 submission.

### 16.5 Romanizer oracle (local only)

`scripts/eval-romanizer.sh` downloads Dakshina's Hindi romanization lexicon into `.build/` (CC BY-SA, never committed) and reports how often the romanizer's output is one of the attested casual spellings for the 2,000 most frequent words. Reported in the P9-4b commit; target >= 75% (casual spelling is genuinely varied).

## 17. Guide pages

- The public guide (`segue.ryandsilva.dev/guide`) documents the App Store build, which has none of this, and publishing how-to pages for scraping chord sites would advertise a ToS breach: **no public page** (open question 10).
- In-product help (11.7) is the guide for the owner.
- A draft page `guide/src/content/docs/web-import.mdx` with `draft: true` frontmatter (Starlight excludes draft pages from production builds; step c6 verifies that on Starlight 0.42.6 with `bun run build` and confirms the page is absent from `dist/`) documents both features with screenshots for local reading (`bun run dev`). If draft pages are not excluded, the page goes to `docs/personal/web-import.md` instead and the step says so.
- `paste-a-song.mdx` gains nothing.

## 18. Files owned

- New: `docs/phases/9-workstreams/P9-4-lyrics-and-url-import.md` (this spec); everything under `Packages/SeguePersonalModules/Sources/SeguePersonalModules/{Web,Lyrics,Romanization,UI}/`; `Packages/SeguePersonalModules/Tests/`; `research/phase9-import/` (README, `urls.tsv`; pages and gold gitignored); `scripts/collect-import-corpus.sh`, `scripts/redact-import-fixture.swift`, `scripts/eval-romanizer.sh`; `Packages/SegueCore/Sources/Plugins/PluginTypes.swift`; `Packages/SegueCore/Sources/Ingest/IngestPipeline+Source.swift`; `Packages/SegueCore/Sources/Services/AnalyticsEvent+Import.swift`; `UITests/SegueWebImportE2ETests.swift`; the draft guide page.
- Changed (own hunks only): `Plugins/PluginRegistry.swift`, `Ingest/IngestTypes.swift` (origins), `Services/AnalyticsEvent.swift` (rows 31-33, `SongSource.web`), `AnalyticsEvent+AI.swift` (`PasteSource`), `AnalyticsEvent+Throttle.swift`; SegueUI `Paste/*` (source review, the web field host, source line), `App/AppDependencies` (entries), `App/Commands/FileCommands.swift`, `App/MenuShortcuts.swift`, `Library/LibraryViews.swift`, `AccessibilityID+Paste.swift`; `App/Sources/SegueApp.swift` (entries wiring, the Debug fixture option); `Packages/SeguePersonalModules/Package.swift`; `Makefile` (`test-packages`, `eval-import`, `import-canary`); `scripts/lib/verify-common.sh` (`forbidden`); `.gitignore` (corpus folders); `.swiftlint.yml` (the SwiftSoup import rule); `THIRD_PARTY_NOTICES.md` (the SwiftSoup row, section 10); `UITests/AppStore/` (one method); `docs/release/specs/WS3-services.md` (rows 31-33).
- Pointer: `docs/phases/5-personal-modules.md` (replaced by a pointer to this spec).

## 19. Sessions and steps

### P9-4a - corpus, contract, fetcher, page readers, eval

- **a1** Package setup: test target, `make test-packages` entry, the HTML parser dependency (open question 2) pinned exactly with its isolation lint rule, its `THIRD_PARTY_NOTICES.md` row (10). `make quick`-level compile only.
- **a2** Contract: `PluginTypes.swift`, the protocol requirements, `IngestOrigin.web` / `.lyrics`, `IngestPipeline.ingest(_:origin:source:)` with its tests (15.2). Lands early so P9-4b can start.
- **a3** Corpus: `urls.tsv` (agents pick representative public pages per 16.1), the collector run, the E-Chords list handed to Ryan with Safari steps (a manual action for Ryan: say so clearly and keep building), gold files, the redactor and the committed fixtures.
- **a4** `HTTPTransport`, `URLSessionTransport`, `FixtureTransport`, `PageFetcher`, `RequestPacer`, `PageCache` with tests.
- **a5** `TabJSONParser`, `ChordSpansParser`, `ChordPreParser` (from Ryan's saved pages; if they have not arrived, build the other steps first and leave this one last), sanity checks, fallback, with tests.
- **a6** `GenericPageReader` with tests.
- **a7** `segue-import-eval` and `make eval-import`; iterate the readers until the 16.3 page targets pass; record the table in `research/phase9-import/README.md`.
- **a8** `make import-canary`. End: one `make quick`.

### P9-4b - LRCLIB and romanization

- **b1** `HindiRomanizer`, its table and override list, tests; `eval-romanizer.sh` run reported.
- **b2** `LRCLIBClient` on the pacer, recorded responses (16.1), decode tests; the live API shape re-checked once with a single manual request (LRCLIB was returning 502 on 2026-10-31).
- **b3** `LyricsQueryVariants`, `LyricsRanker`, `LRCSections`, script checks, with tests; the LRCLIB eval targets in `make eval-import`.
- **b4** `LRCLIBLyricsSource` and `WebPageImporter` registered in `PersonalModules.register(into:)`. End: one `make quick`.

### P9-4c - UI, analytics, absence checks, guide, E2E

- **c0** Design directions (R39): 2-3 mockups of the Find Lyrics sheet and of the New Song sheet with the web field (Apple-native, dark-first, Linear/Things references), Ryan picks before c2.
- **c1** `PluginEntries` in `AppDependencies`, wiring in `SegueApp.swift`, `beginSourceReview`, the source line, `PasteSource` / `SongSource` cases; SegueUI tests (15.3).
- **c2** The sheets in the personal package per the picked direction; File menu items and shortcuts; the empty-library buttons; the lone-URL paste; link drops; saved-file import if open question 15 is yes; help popovers; accessibility.
- **c3** Analytics rows 31-33 with their vocabulary tests; WS3 row table.
- **c4** `forbidden` extended (13), proven with zero false positives, then one `make verify-appstore`.
- **c5** E2E class (15.4) and the App Store method (15.5), one `make e2e-one` each.
- **c6** Draft guide page and its build check; screenshots for it captured from the Personal build.
- End: one `make quick`; launch the Personal build for Ryan's hands-on walk through both features.

## 20. Done criteria

- In the Personal build: a UG, Chordie, E-Chords (saved page or reachable) and generic page each import into the review sheet with the right fields; LRCLIB search finds and opens lyrics, Hindi in casual romanization; everything lands only through Accept; R109 holds during a show.
- Every failure in 6.8 and 8.7 shows its message and actions; no alert, crash or saved song from a failure; no bot-check circumvention anywhere.
- No live network in any test; parser, fetcher, pacer, ranker, variants and romanizer suites green; `make quick` green.
- `make eval-import` meets every 16.3 target; the romanizer meets 16.5.
- `make verify-appstore` passes with the extended `forbidden`; the App Store UI method passes; the App Store build's behaviour is unchanged.
- Analytics rows 31-33 in the vocabulary, emitted only by the personal package, no site or service name in any raw value.
- `docs/phases/5-personal-modules.md` is a pointer to this spec; the open questions below are closed in `docs/release/decisions.md` before P9-4a starts.

## 21. Open questions (close before P9-4a, each with a recommendation)

1. **Committed fixtures: full pages or redacted?** The repo's rule (`.gitignore`, "copyrighted lyrics ... must never be committed") conflicts with committing real pages. (a) full pages gitignored locally, redacted structure-preserving copies committed (16.2); (b) commit full pages (the repo is private today); (c) commit nothing, tests need the local corpus. **Recommend (a)**: real markup and chord placement stay under test on every machine, and no lyric is ever committed.
2. **HTML parser.** (a) SwiftSoup (MIT, pure Swift jsoup port, 2.14.3 released 2026-10-16, pinned exactly to the newest release at least two weeks old at build time), Personal package only (it still needs a "Personal build only" row in `THIRD_PARTY_NOTICES.md`, section 10); (b) Foundation `XMLDocument` with `.documentTidyHTML` (no dependency, libxml2's HTML parser, weaker on broken HTML5); (c) a hand-written tolerant tokenizer. **Recommend (a)** for the generic reader's DOM walking; the App Store build is untouched.
3. **User-Agent for page fetches.** (a) honest `Segue/<version> (+https://segue.ryandsilva.dev)` everywhere, and a site that refuses gets the paste fallback; (b) a Safari-like UA for pages. **Recommend (a)**: LRCLIB requires identification, and imitating a browser edges toward the circumvention 8.6 rules out. UG answered a plain request on 2026-10-31.
4. **Register an LRCLIB App-Id?** (a) no, the identified anonymous limit (~90/min per IP) is far above a person's use; (b) register for ~180/min and an authorisation document. **Recommend (a)**.
5. **Romanize Devanagari found on web pages too?** (a) yes, the app fetched it, same as LRCLIB; (b) LRCLIB only, pages keep Devanagari (which the app may not display). **Recommend (a)**; pasted text stays untouched either way.
6. **Where the romanizer lives.** (a) `SeguePersonalModules` (only caller in v1.0, App Store binary unchanged); (b) SegueCore, as the old phase 5 plan said. **Recommend (a)**; it moves down in one step if an App Store use appears.
7. **Record where a song came from?** (a) nothing stored: the source line shows in the review only; (b) a sidecar `source` field (schema bump); (c) a `{meta: source <url>}` line in the `.cho`. **Recommend (a)**: no schema bump, no URL in the user's files, and a chart is edited into the owner's own version anyway.
8. **Analytics tokens.** (a) technique names (`tabJSON`, `chordPre`, `chordSpans`, `genericPage`, `lyricsRecord`) so the App Store binary carries no site or service names and `forbidden` can include them; (b) site names (`ultimateGuitar`, ...) for readable dashboards. **Recommend (a)**; the mapping is one comment in `ReaderKind`.
9. **Share extension.** (a) not in v1.0: the lone-URL paste and link drop cover "send this page to Segue"; (b) build a Personal-only Share extension now (a second appex, the Quick Look-only `PlugIns` check stays App Store only). **Recommend (a)**.
10. **Guide pages.** (a) no public page; in-product help plus a Starlight draft page; (b) a public page marked "Personal build". **Recommend (a)**.
11. **Search trigger.** (a) Return / Search button only; (b) as-you-type with a 600 ms debounce. **Recommend (a)**: fewer requests, no partial-word queries, nothing to rate-limit.
12. **Eval targets.** Confirm 16.3 (site readers 95% pass, generic 80%, zero silent wrong charts, LRCLIB top-3 90% / top-1 75%, variants 4 of 5) and 16.5 (romanizer 90% on gold lines, 75% Dakshina agreement), or name others. **Recommend as written**.
13. **Synced-lyrics gaps.** (a) split stanzas at gaps of 5 s or more when the plain lyrics have no blank lines, timestamps then discarded; (b) never use synced lyrics. **Recommend (a)**.
14. **UG tab-only and Pro pages.** (a) refuse with "This page is a tab, not a chord chart"; (b) import the text of tab pages as an Instrumental block. **Recommend (a)**: Segue's tab handling is for tab lines inside a chord chart, and Pro pages carry no chart in the HTML.
15. **Saved web page files.** (a) in Personal, Import Songs... and drops also accept `.html`, `.htm`, `.webarchive` and read them with the same parsers (the honest path for challenge-protected sites such as E-Chords); (b) URLs only. **Recommend (a)**.
16. **Shortcuts.** Shift-Cmd-U for Import from Web Page... and Shift-Cmd-L for Find Lyrics... (both free in `MenuShortcuts.swift`), or none. **Recommend as proposed**.
