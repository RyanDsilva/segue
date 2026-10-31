# Phase 3 - AI entry & set assistant

**Status (2026-10-19):** canonical spec, rewritten after the phase 3 spikes and Ryan's rulings R61-R79 (2026-10-18), then updated with R80-R103 (2026-10-18/19: metadata entry and fast set building, the answers to the section 16.1 questions, converter rulings, live-mode repeats, About panel) in `docs/release/decisions.md`. Phase 3 ships **in v0.5, in both flavours, before the App Store upload** (R61). Where this doc and an earlier phase 3 ruling in `docs/decisions.md` disagree, R61-R103 win; the superseded entries carry pointer lines. Where this doc and `docs/00-vision.md` disagree on phase 3, R61-R103 win (the vision's AI and library rows carry pointers). P3-1 has landed (commit 55d8701) and P3-A Part 1 is done (`docs/research/phase3-mlx-in-app.md`).

Depends on: phase 0 (Core package, ChordPro parser, library + index), phase 1 (MusicTheory, `KeyDetector`), phase 2 (setlists, shows, tags/proficiency basics), and the release build-out (WS1-WS5, `docs/release/`). Inputs: `docs/research/phase3-ai.md` (sources), `docs/research/phase3-spikes.md` (measured results, harness in `research/phase3-spikes/`), `docs/research/phase3-mlx-in-app.md` (P3-A: MLX inside the shipped app).

Workstream specs, one per implementation session: `docs/phases/3-workstreams/P3-*.md` (section 15).

---

## 1. Goal

Make adding a song take under a minute from any messy source, make entering a song's metadata and sections a matter of controls rather than remembered syntax, and make building a set fast by picking (or by a one-line request). On-device, free, and working offline once a model is present. AI is an enhancement, never a requirement: with no model at all, every feature still works.

## 2. Scope per flavour

| Feature | App Store flavour | Personal flavour | Ruling |
|---|---|---|---|
| Paste cleanup: deterministic converter + always-on review sheet | yes | yes | R63, R101 |
| File import incl. `.crd` through the converter; a batch lands in ONE review sheet | yes | yes | R76, R96 |
| New song starts with the paste flow, with "Start blank" | yes | yes | R83 |
| Apple Foundation Models (FM) refinement | yes | yes | R62 |
| ONE curated MLX model, downloaded on user request, loaded per paste or request | yes | yes | R62, R64, R94 |
| Any `mlx-community` model (Settings > AI > Advanced, in `SeguePersonalModules`) + "Check this model" | **no** | yes | R62, R97 |
| Song card: metadata as controls that write the directives and sidecar; set essentials marked | yes | yes | R80 |
| Text mode `/` slash menu + `{` completion fixes (incl. key validation) | yes | yes | R81 |
| Visual-editor section band (select lines, V/C/B/I, drag edges) | yes | yes | R82 |
| One section note (`{comment}` + cues merged) with "Show on stage only" | yes | yes | R87 |
| Set builder Pick / Arrange, Library multi-select + Add to Setlist | yes | yes | R84 |
| Break rows with per-part totals; changeover time in totals | yes | yes | R85, R86 |
| Set assistant (lexicon + async model chips) and NL picks | yes | yes | R65, R92 |
| Tags (starter suggestions) + smart filters | yes | yes | R71, R72 |
| Settings > AI pane (sixth pane), one AI toggle | yes (no Advanced) | yes (with Advanced) | R73, R93 |
| AI analytics events (opt-in, closed vocabulary) | yes | yes | R74, R98 |
| Visual metronome on stage (sound in rehearsal only) | yes | yes | R90 |
| No repeats within a show (live mode) | yes | yes | R102 |
| About panel, variant A (native, one row of links) | yes | yes | R103 |
| URL import, LRCLIB | no | phase 5 | R61 |

Not in 0.5: a local AI stats screen or metrics database (R74), metronome sound during a show (R90), "Detect sections" on existing songs, macOS 27 `LanguageModel` / `MLXFoundationModels` (revisited in 0.6, R77), Private Cloud Compute.

## 3. Design principle: deterministic first, model last

Code handles everything code can handle. Models only refine: section labels for blocks without a header, the title when code found none (artists come from code only, R174), and lines code could not classify (R63). The model **never outputs lyric text**: every output refers to blocks or lines by index, so lyrics cannot be respelled by construction (spike section 1). The lyric guard stays as a backstop.

```
raw text (paste, .txt, .crd)
 -> Normalizer        (code)  HTML residue, tabs->spaces, CRLF, smart quotes in non-lyric lines, ads,
                               "Tabbed by"/rating/nav junk, page controls and widgets (Transpose, Font
                               Size, Display Settings, share bars, views, post dates: R124),
                               chord-site headers (Singer: | Music: | Lyrics:)
 -> FormatDetector    (code)  ChordPro | chords-over-lyrics | bare lyrics | mixed; per line:
                               chordLine / lyricLine / headerLine ([Verse], Chorus:, V1, Mukhda:) /
                               directive / tab / blank / unknown
 -> Segmenter + hints (code)  blocks on blank lines, lone header merged into the next block; per-block
                               hints: header label, "same lyrics as block N", chords only, tab, no chords
 -> Converter         (code)  chords-over-lyrics -> ChordPro by column alignment (a chord over a space
                               attaches to the next word); headers -> sections; an unheaded block whose
                               lyrics repeat an earlier block -> both labelled Chorus (R101); other
                               unlabelled blocks -> {start_of_verse} placeholders; unknown lines
                               (tuning, strumming) -> {comment} (R101)
 -> Validator         (code)  every chord parses (MusicTheory, strict: "Do" is never a chord);
                               collect unknown lines and unparseable tokens
 -> Metadata          (code)  {title}/{artist}/{key}/{capo}/{tempo} directives, "Title - Artist" header
                               lines, "Key: G", "Capo 2", "Scale: Am"; credits Singer -> artist,
                               Music -> composer, Lyrics -> lyricist, Movie -> album (R101); with a
                               capo, {key} is the shapes key (R101)
 == review sheet opens HERE with the deterministic result (instant, never behind a spinner) ==
 -> AI refinement     (model, async)  only: labels for unheaded blocks, the title when code found
                               none, unknown-line classes; results stream into the open sheet
 -> Lyric guard       (code)  the lyric token sequence of the assembled result must equal the
                               converter's (flat words; regrouping into sections is not a change);
                               any difference rejects the AI result for that block only (R124)
 -> Key inference     (code)  stated key wins; else KeyDetector; a model key is used only when
                               KeyDetector.isAmbiguous and the model's key is in the top two. A
                               detected key is shown in the review sheet's song card only and is
                               never written into the .cho unless the user picks it (R101)
 -> Review sheet      (UI)    original vs result side by side (layout "a", decisions.md), AI decisions
                               marked apart from rule-based conversion; Accept / Edit / Cancel.
                               Nothing reaches the library without Accept.
```

**Romanized Hindi.** Lyrics may be Hindi in Latin script with casual spelling. Nothing transliterates, translates or respells lyrics: the Normalizer touches only whitespace, HTML residue and quote characters outside lyric lines; outputs are by index; the lyric guard backs it up. A line is a chord line only if most tokens parse as chords and none is on a small romanized Hindi / English stop list ("Main", "Bas", "Do", "Am" in context, "Hai", "Na"). Prompts say lyrics may be romanized Hindi or English and ask only for labels and metadata. Sections stay Verse / Chorus / Bridge / custom; `Mukhda:` maps to chorus and `Antara N:` to verse as header hints, with the original header text kept as the section label.

ChordSheetJS (MIT) heuristics for chord-line detection and alignment are a reference only.

## 4. AI provider port (R77)

Port types and `ScriptedProvider` live in **SegueCore** (new module `ModelPort`); the FM and MLX adapters and the model downloader live in the new package **`Packages/SegueAI`**. One code path on macOS 26; the macOS 27 `LanguageModel` protocol and `MLXFoundationModels` are revisited in 0.6.

```swift
// SegueCore / ModelPort
protocol LanguageModelProvider: Sendable {
    var id: ProviderID { get }                       // .foundationModels, .mlx(ModelRef)
    func availability() async -> ProviderAvailability // .available, .unavailable(UnavailableCause)
    func run<T: ModelTask>(_ task: T) async throws(ProviderError) -> ModelResult<T.Output>
}
struct ModelResult<O> { let output: O; let metrics: CallMetrics }   // latency, tokens, retries
enum ProviderError { case unsupportedLanguage, guardrail, refusal, decodingFailure,
                     incompleteOutput, contextOverflow, rateLimited, busy, timeout,
                     notInstalled, other }      // typed fallback reasons (no strings)
```

- **Tasks** are typed values in Core: `SectionLabelTask` (blocks + hints -> exact-count `[label]`), `MetadataTask` (top/bottom chord-free blocks + chord list -> title, artist, key), `AmbiguousLineTask` (unknown lines -> class), `SetRequestTask` (unmapped words + the library's actual tags -> suggested chips). Outputs are plain Core structs with **no optionals** (`""`/0 sentinels, normalised in code: "Unknown" -> empty, artist equal to title -> empty).
- **One `@Generable` wire type per task**, in SegueAI, mapped to the Core output. The MLX JSON Schema is **derived from that type's `GenerationSchema`** (it is `Codable`), plus the dynamic constraints the spike validated: exact array counts (`DynamicGenerationSchema` on FM, `minItems = maxItems = n` on MLX), bounded integers, `.anyOf` enums, `.maximumCount` on every unbounded array. No hand-written second schema, no parse-and-retry.
- **FM adapter**: `SystemLanguageModel.default`, a fresh session per call, `.greedy`, never concurrent calls on one session. Budget from runtime values: `contextSize - tokenCount(instructions) - tokenCount(schema) - maxResponseTokens - margin`, with `tokenCount` behind `if #available(macOS 26.4, *)` and a chars/3 fallback (no fixed "~2,500 tokens"). Sheets over budget (more than about 35 blocks) chunk on block boundaries with the hints kept, only when MLX is absent (chunking costs about 18 points, spike 2.1 F).
- **MLX adapter**: `mlx-swift-lm` with `MLXGuidedGeneration` (`GrammarConstraint(jsonSchema:)` + `GuidedGenerationLoop`, greedy). A no-free-whitespace grammar (compact JSON or EBNF), bounded ints and fixed counts; one retry with a whitespace bias on `incompleteOutput`. `Memory.cacheLimit` set (512 MB start; without it the footprint reached 11.6 GB). **Residency (R94): loaded per paste or set request and unloaded right after**; never loaded during a show. Integration rules proven by P3-A in section 4.3.
- **`ScriptedProvider`** replays **recorded real outputs** keyed by task + input hash (`Tests/Fixtures/paste/recorded/<provider>/`), recorded by the manual eval target (`make eval-ai RECORD=1`). All automated tests use it; a missing recording is a test failure, never a silent pass.

### 4.1 Routing (R63, supersedes the FM-first rule)

Per paste: **curated MLX if installed -> else FM if available -> else deterministic converter alone.** A provider failure on a call falls through to the next provider in the same order for that call (FM: `unsupportedLanguage`, `guardrail`, `refusal`, `decodingFailure`, `contextOverflow`; `rateLimited`/`busy` after one spaced retry). The review sheet is always shown, whichever path produced the result.

- Hinglish needs no special route: on MLX it scored 100% on the songs it completed; on FM the language rejection is deterministic and costs about 3 ms (spike 2.2), so FM -> deterministic is cheap.
- **No model is loaded during a show** (R65), and **paste is disabled while a show is running** (R95; scope of "paste" per open question 26).
- **AI toggle off** (R93, "Use AI to refine pastes and set requests"): the router returns the deterministic result without asking any provider.
- **Set requests** (`SetRequestTask`) route the same way: curated MLX if installed, else FM (R92).
- The router is config-driven (one order list per task in a bundled config file), with the R63 order as the default.

### 4.2 FM unavailable (R69)

Per `SystemLanguageModel.Availability.UnavailableReason`, a reason-specific inline note, never a nag prompt:

| Reason | Note | Action |
|---|---|---|
| `appleIntelligenceNotEnabled` | "Turn on Apple Intelligence in System Settings to use it for cleanup." | **Open System Settings** (Apple Intelligence & Siri pane) |
| `modelNotReady` | "Apple Intelligence is still getting ready. Segue will use it once it is." | Open System Settings |
| `deviceNotEligible` | "This Mac doesn't support Apple Intelligence." | none |
| unknown future reason | "Apple Intelligence isn't available right now." | Open System Settings |

Shown in Settings > AI, in the review sheet footer when the result came from code only, and in the set assistant's chip area. Copy is drafted here and finalised in P3-9 (Apple Intelligence trademark usage is a WS5-stage question, section 16.2).

### 4.3 MLX inside the shipped app (P3-A, R100)

Proven in an archived, sandboxed, hardened Release-AppStore build (`docs/research/phase3-mlx-in-app.md`): Metal kernels compile, the model loads from the app-group store (0.8-1.2 s), a guided label call takes about 3 s warm, no sandbox violation, no hardened-runtime exception. P3-3 must carry these over:

- `make bootstrap` checks the Xcode **Metal Toolchain** component (`xcodebuild -showComponent MetalToolchain`) and installs it; the README toolchain line names it.
- Zero-warning gate: `MTL_COMPILER_FLAGS = $(inherited) -Wno-c++17-extensions -Wno-c++20-extensions` in Tuist's `PackageSettings.baseSettings`; `_NumericsShims` in the quiet-libtool list; `SegueAI` in the first-party strict list.
- Load models with **`LLMModelFactory.shared.loadContainer(from:using:)`** directly (the class-name registry lookup fails in a static, dead-stripped binary).
- Segue's own tokenizer loader (`AutoTokenizer.from(modelFolder:)` + a bridge to `MLXLMCommon.Tokenizer`), **no `MLXHuggingFace`**.
- The **no-free-whitespace grammar** is required (the guided output pretty-printed JSON in the app too).
- Package tests stay **MLX-free** (SwiftPM cannot build the metallib); MLX runs only through xcodebuild or `make eval-ai`.
- Every call runs at **`.userInitiated`**, holds a **`ProcessInfo` activity**, and has a **timeout** mapped to `ProviderError.timeout` (one call stalled 1,054 s under swap).
- Privacy manifest: **`NSPrivacyAccessedAPICategoryDiskSpace`, reason E174.1** (MLX's checkpoint code and Segue's free-space check).
- Cost: `.pkg` +8.5 MB, `.app` +21 MB, a Release archive about 2x slower.
- Notices: a row per resolved pin (12, including swift-syntax) plus the vendored MLX C++, mlx-c, metal-cpp, {fmt}, nlohmann/json, XGrammar (+ NOTICE), DLPack, PicoJSON, and the Qwen (Apache-2.0) model licence.
- Curated model pin: `mlx-community/Qwen3-4B-Instruct-2507-4bit` at revision **`50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b`**, per-file sizes and SHA256 in the P3-A doc section 7.

## 5. Curated model, download and store

### 5.1 Curated model (R64)

**Candidate:** `mlx-community/Qwen3-4B-Instruct-2507-4bit` (upstream `Qwen/Qwen3-4B-Instruct-2507`, Apache-2.0, not gated, 2.28 GB download, about 3 GB peak RAM, about 6.5 s per song on an M1 Pro). **Not locked.** It is locked only after the spike scorer is re-run (P3-A) on **10-20 of Ryan's own real pastes** (UG and other sites, some Hinglish) and reaches the **>= 90%** bar (section labels and title/artist, as in section 14.1). The pastes live in the gitignored `research/phase3-eval/pastes/` (format in its README); they contain copyrighted lyrics and are never committed, quoted in docs or sent anywhere. If Qwen3-4B misses the bar, P3-A reports per-failure kinds and the next candidates (Gemma 4 E2B, Qwen3.5-4B) to Ryan; nothing is swapped without his ruling.

### 5.2 Download (R66)

- Never automatic. Settings > AI shows name, licence (upstream), download size, RAM need, free disk; the user clicks **Download**; progress, cancel, resume; **Delete**.
- Direct from `huggingface.co` (`/resolve/<pinned revision>/<file>`), no mirror, nothing bundled. The app carries a **manifest** per curated model: repo, pinned commit revision, and per file its size and SHA256 (from the Hub's LFS metadata). A file is accepted only when its SHA256 matches; a mismatch deletes it and fails the download.
- **R54 header stripping applies**: no `Accept-Language`, no device `User-Agent` (a fixed `Segue/<version>` one), on every hop including the CDN redirect. Uses the vendor HTTP client pattern from WS3.
- Low RAM (R68): show the memory need; on Macs under 16 GB, a warning ("Needs about 3 GB of memory while it works. On this Mac other apps may slow down."). Never blocked.

### 5.3 Store (R67)

- **Shared between the two flavours** through an **app-group container**: entitlement `com.apple.security.application-groups` = `V6BM673U35.dev.ryandsilva.segue.models` in all three entitlements files, at `<group container>/Library/Application Support/Models/<repo>/<revision>/`. `scripts/lib/verify-common.sh` (`app_entitlements`, feeding `verify-archive` check 4 and `verify-appstore`) and the entitlements comments change in the same commit. **Proven by P3-A (R100):** both flavours read one store; the team-prefixed id needs no portal registration and the existing "Segue Mac App Store" profile needs no regeneration. Still open: App Store Connect acceptance, checked at the first real `make validate` (Ryan, R46); if it is ever rejected, add App Groups to the App ID and regenerate the profile.
- Excluded from backup (`isExcludedFromBackup`), never inside the library folder, never in `LibraryArchive`. Reset All Settings resets AI prefs but **keeps downloaded models** (R73). **Delete** removes the model directly after a confirmation, not via the Trash (R99).
- A download in progress is held by a file lock in the group container, so the two flavours never download at once.

## 6. Paste and import UX

### 6.1 Entry points (R75)

- **File > New Song from Clipboard** (`⌥⌘V`). P3-4 verifies it is free: no clash in `MenuShortcuts.all` (the clash test), and no clash with the text system's Paste Style (`⌥⌘V` maps to `pasteFont:` only through a Format menu, which Segue does not have; P3-4 confirms in the editor).
- A **"Paste a Song"** button in the empty-library state.
- **`⌘V` while the song list has focus** (never when a text field or the editor has focus).
- **File > New Song** (`⌘N`) and every other "New Song" control open the **paste flow** (R83): the review sheet in an input state ("Paste or type a song"; `⌘V` pastes, the clipboard is never read before that), with a **"Start blank"** link that creates an empty song and opens the editor with the song card focused on Title.
- **File > Import Songs...** and drag and drop (existing, WS2a): `.cho/.chopro/.chordpro/.pro` that are already ChordPro import directly (A29); `.txt` and **`.crd`** (R76) that need conversion go through the converter and the review sheet. **Several conversion files open ONE review sheet** (R96): a list of every converted file, each with a checkbox (ticked by default) and its own preview and song card; **Import N Songs** imports the ticked ones together, unticked ones are not imported. `SongFileTypes.importExtensions` gains `crd`.
- **During a show** (R95) the paste routes are disabled, with the reason in the menu item's tooltip and the button's help text (exact scope: open question 26).

### 6.2 Review sheet

- Opens with the deterministic result immediately; AI decisions stream in as they arrive (MLX warm: about 4.4 s labels + 1.8 s metadata; FM: 5-30 s) with a quiet "Refining with <provider>..." line, never a blocking spinner. The user can edit or Accept before refinement finishes (refinement then stops).
- Side by side (layout "a"): original left, result right; AI-decided labels and metadata marked apart from rule-based conversion; unknown lines and unparseable tokens flagged.
- The metadata block is **the song card** (R80, section 16.0.1, built by P3-10) in draft mode: it edits the pending result, not a file. A detected key shows as a suggestion and is written only if the user picks it (R101). Tags with starter suggestions.
- Accept writes `.cho` + sidecar through `LibraryStore.commitImport` (the `prepareImport`/`commitImport` split already exists). Cancel leaves the library untouched.
- The footer names what produced the result ("Labels by Qwen3-4B", "Labels by Apple Intelligence", "Converted without AI") and shows the R69 note when relevant, plus a **quiet one-line download link** to Settings > AI when the result came from FM or code and the curated model is not installed (R93). No popups or tips offer the download.
- With the AI toggle off (R93) the sheet shows the deterministic result and the footer says "Converted without AI (AI is off in Settings)".

## 7. Set assistant (R65)

Request -> instant code lexicon -> chips -> deterministic builder; an async model pass adds **suggested** chips.

1. **Lexicon (code, instant):** numbers and set lengths ("45 min", "10 songs"), keys ("in G", "no Bb"), BPM as an **explicit tempo filter** ("under 100 bpm", R92), proficiency phrases ("know well" -> Ready+, "know cold" -> Pro), tag names as written in the library (fold-insensitive, romanization-tolerant via `RomanNormalizer`), slot phrases ("open strong", "finish big") **only when the request says them** (R92), smart filter names ("from Wedding set"). Fills the chips immediately.
2. **Async model pass:** only when words remain unmapped and the AI toggle is on (R93), after the user stops typing (0.8 s) or presses Return. It maps the leftover words onto the library's **actual** tags and the fixed chip vocabulary; results appear as dashed "suggested" chips the user accepts or ignores. Provider (R92): **curated MLX if installed, else FM**, loaded per request (R94). Never blocks; cancelled when the request changes.
3. **Chips** are editable; with no AI, chips are filled by hand. "Songs I know well" maps to proficiency >= Ready; Learning is excluded by default.
4. **Score (code):** weighted signals - proficiency, tag match, recently-played penalty (global across gigs, decaying with days since last played, not venue-aware), slot fit from tags (only when asked, R92: open with `upbeat`, close with `crowd pleaser`/`singalong` when those tags exist), key flow. Tempo never scores; it only filters (R92). Weights in config. Every candidate carries a **score breakdown** (signal -> weighted contribution, summing to the total), shown in a popover (hover and keyboard/VoiceOver reachable).
5. **Pack (code):** greedy fill to the target time (tolerance +/- 3 min default), then a local-swap pass for flow: penalise the same key back to back and adjacent capo/tuning changes, small bonus for closely related keys. **A song appears at most once per setlist** (a hard invariant enforced in the setlist model, from Ryan's walkthrough): the packer never proposes a duplicate and treats it as an invariant, not a score term. Each song counts its time (section 8) plus the setlist's changeover (R86); songs with no time are left out and named.
6. **Result** opens as a draft setlist in the builder's Arrange mode (R84); the user drags, locks songs, and hits **Rebuild** to re-pack around the locked ones. A draft has one part; in a setlist that already has break rows (R85), Rebuild keeps the break rows and locked songs where they are and re-packs the unlocked slots.
7. **Deterministic:** the builder takes an injectable seed; same library + request + seed gives the same set.

**NL picks.** In the library search field: lexicon chips instantly, model suggestions async as above. **On stage** (quick search during a show): lexicon + text search only; **no model is loaded during a show**. Adding on stage follows R102 (no repeats within a show, built by P3-15): a song already played or still upcoming is refused with a message, and an upcoming one is offered "Move to Next" instead.

Tempo is an explicit filter only (R92).

## 8. Song times (R172)

A slot's time is never made up (the phase 2 rule).

- **Source:** the song's tempo times the bars of the passes the slot plays, from `SongTimeline` (R172, P8-8 section 5). A Skip pass adds nothing; a time that rests on default chord lengths reads "~3:40".
- **Unknown stays unknown:** a song with no tempo or no chords shows `--:--` on the row, totals `≥38:20 + 2 unknown` (phase 2 notation, unchanged). The "N unknown" part of every total is a **button** that lists exactly which songs have no time, with a Tempo field to type or tap one (section 16.0.5).
- **Changeover** (R86): a per-setlist value with a global default (Settings > General, default 0 s) is added after every song but the last of each part; totals include it and say so in their help text.
- **Shows and rehearsals** keep recording what was played and when (phase 2 files, gig log), but nothing feeds back into a song's time.

## 9. Tags and smart filters (R71, R72)

- Tags stay free-form in the sidecar (existing field); autocomplete from tags in use; rename/merge across the library.
- **Starter tags:** an empty tag vocabulary suggests `upbeat`, `ballad`, `crowd pleaser`, `singalong`, `original`, `cover` in the tag picker (manual pick only; nothing pre-applied; they disappear once the user has their own tags; the seed tag "Welcome" does not count as the user's own).
- **Smart filter** = a saved predicate over tags (all/any/none), proficiency, key, tempo range, last played before/after, never played. Stored as library files **`filters/<slug>.filter.json`** (versioned JSON, `schemaVersion: 1`, ULID id). `LibraryRoot` gains `filtersDirectory`; `LibraryArchive.includedFolders` gains `filters`. Deleting a filter moves it to the Trash (R15). Evaluated against the index.
- Sidebar section **Smart Filters**; a filter is usable as a set-assistant input chip. `SongFilter` (phase 2 simple filtering) stays the in-memory matcher the smart filter compiles to.

## 10. Settings > AI (R73)

A **sixth pane**, "AI", after Live (General, Appearance, Live, AI, Privacy, Data):

- Apple Intelligence status with the R69 note and Open System Settings.
- The curated model card: name, licence with link, download size, RAM need, free disk, Download / progress / Cancel / Delete (direct removal after a confirmation, R99), low-RAM warning (R68), "candidate" wording until R64 locks it. The download is offered as a quiet link, never a popup (R93).
- **One toggle, "Use AI to refine pastes and set requests", default on** (R93). Off: no provider is called for pastes or set requests.
- **Advanced** (Personal flavour only, R62): enter an `mlx-community/...` repo id; the app fetches the model card, shows size and the **upstream** licence (`base_model` card, not only the mlx-community card), downloads only on click; "Check this model" runs the bundled original fixtures through it and shows its score next to the curated model's (not blocked if lower). One active MLX model at a time. The code lives in **`SeguePersonalModules`** (R97), mechanically excluded from the App Store flavour (`make verify-appstore` symbol check extended).
- Reset All Settings resets AI prefs, keeps models (R73).

## 11. Analytics (R74, analytics only)

No local stats screen and no local metrics database. Opt-in (existing consent), closed vocabulary, non-personal TelemetryDeck events, extending `AnalyticsEvent` and the `IngestBody` allowlist under their existing rules (no `String` payloads; values match `^[A-Za-z0-9+<>._-]{1,24}$`):

| Signal | Parameters (all enums/buckets/Bool) |
|---|---|
| `Segue.AI.pasteFinished` | source (`clipboard`/`newSong`/`emptyState`/`listPaste`/`fileTxt`/`fileCrd`/`fileCho`: an already-ChordPro file reviewed because it looks like a library song, P8-1), provider (`mlx`/`fm`/`none`), fallback (`none`/`aiOff`/`notInstalled`/`fmOff`/`fmNotReady`/`fmIneligible`/`unsupportedLang`/`guardrail`/`decoding`/`overBudget`/`busy`/`timeout`/`other`), latency bucket, outcome (`accepted`/`cancelled`/`unticked` for a batch file left out), correction bucket (`none`/`small`/`medium`/`large`: edit distance of AI-touched labels and metadata between proposal and Accept), **`romanHindi` (Bool, R98)**: the converter's romanized-Hindi detection fired |
| `Segue.AI.modelDownload` | result (`completed`/`cancelled`/`network`/`checksum`/`disk`/`other`), kind (`curated`/`custom`), duration bucket, ramUnder16 (Bool) |
| `Segue.AI.assistantUsed` | context (`builder`/`library`/`stage`), chips by lexicon bucket, suggested chips shown / accepted buckets, provider, rebuilt (Bool), `artistChips` and `albumChips` (Bools: the request held an artist or a Movie / Album chip, P8-8) |
| `Segue.AI.smartFilterUsed` | action (`created`/`applied`/`assistantInput`), conditions bucket |

Never song text, titles, artists, tags, queries or model names typed by the user. `duringShow` is not a fallback value: paste is disabled during a show (R95). The privacy policy's example list is updated in P3-9. Exact names and buckets are fixed in P3-4 with the allowlist test.

## 12. Release impact (owned by P3-A and P3-9)

- **App Review 2.5.2 / 4.2.3(ii):** model weights are data, not code; the download is user-initiated with size shown first (`docs/release/research/03-review-risk.md`). Custom models raise risk, hence Personal-only (R62). Review notes get an AI paragraph (P3-9).
- **MLX in the sandbox + hardened runtime: VERIFIED by P3-A** (section 4.3): kernels compile, the model loads from the group container, no exception needed.
- **Tuist and static linking:** the metallib lands in `Contents/Resources/mlx-swift_Cmlx.bundle` (all MLX code static); `.pkg` +8.5 MB, `.app` +21 MB, archive about 2x slower; `verify-archive` green with the new allowed set.
- **Model storage** in the app group (R67, R100), `verify-common.sh` `app_entitlements`; App Store Connect acceptance pending at the first real `make validate`.
- **Privacy:** R54 header stripping on downloads; the privacy policy gets a model-download section and a Hugging Face vendor row; the support FAQ ("goes online only for...") gains model downloads; the privacy manifest is diffed for required-reason APIs pulled in by the new dependencies (and Segue's own disk-space check before download). App Privacy label impact of the HF download is part of the WS5-stage research ticket (section 16.2).
- **Third-party notices:** MLX / mlx-swift-lm (MIT), swift-transformers (Apache-2.0), XGrammar (Apache-2.0), every transitive pin `make docs-check` finds, and the curated model's licence (Apache-2.0, Qwen) shown in Settings > AI, in the bundled `THIRD_PARTY_NOTICES.md` and on the web `/acknowledgements` page (the in-app Acknowledgements window was removed 2026-10-18).
- **Memory:** about 3 GB per paste or request while MLX is loaded, released right after (R94); the live view must never block; no model during a show.
- **Store copy:** review notes are at 3,557 / 4,000 bytes; keywords 97 / 100 bytes; 8 screenshots. WS5 lines that say "no AI in 0.5", "Works offline" and NETWORK USE are superseded and rewritten in P3-9 (open items in section 16.2).
- **Accessibility:** every new surface (review sheet, AI pane, assistant chips, smart filters, song card, slash menu, section band, Pick/Arrange and break rows, the unknown-time list, section notes, metronome overlay, the live repeat message) gets its own VoiceOver / Voice Control walk before any accessibility label is claimed (R79).
- **About panel** (R103): variant A; dark-mode legibility of the link row is verified by its implementer (P3-15).

## 13. Code placement and file map

| Where | What | Workstream |
|---|---|---|
| `Packages/SegueCore/Sources/Ingest/` (landed, 55d8701) | Normalizer, FormatDetector, stop list, Segmenter + hints, Converter, Validator, MetadataExtractor, LyricGuard, KeyInference, `.crd` reader, `IngestPipeline` (deterministic result + refinement merge) | P3-1 (R101 follow-ups and the refinement merge: P3-2) |
| `Packages/SegueCore/Sources/ModelPort/` (new) | `LanguageModelProvider`, tasks and outputs, `ProviderError`, `Router`, `CallMetrics`, `ScriptedProvider` | P3-2 |
| `Packages/SegueCore/Sources/Library/` | `SmartFilter`, `SmartFilterStore`; `SongFileTypes` (+crd, P3-4) | P3-6, P3-4 |
| `Packages/SegueUI/Sources/SegueUI/SongCard/` (new) | the song card, its fields and essentials dots (P3-10) | P3-10 |
| `Packages/SegueUI/Sources/SegueUI/Editor/` | `{` completion fixes, slash menu, vertical `CompletionPopup` (P3-10); section band in `VisualEditorController+*` (P3-11) | P3-10, P3-11 |
| `Packages/SegueCore/Sources/Editing/` + `ChordPro` diagnostics | section operations (wrap, relabel, resize, unwrap, split, merge) (P3-11); `{key}`/`{time}` value validation with fixes (P3-10) | P3-11, P3-10 |
| `Packages/SegueCore/Sources/Setlists/` + `SegueUI/Setlists/` + `Components/SelectableList.swift` | break entries, changeover, per-part timing, unknown-time list; Pick/Arrange, multi-select | P3-12 |
| `Library/Sidecar.swift` cues + `{comment}` handling, notes sheet, `LiveLayout` | section notes (R87) | P3-13 |
| `Packages/SegueUI/Sources/SegueUI/Live/` metronome overlay, `LiveCommand`/`InputBindings` | visual metronome (R90) | P3-14 |
| `Shows/ShowController.swift` add paths, `App/AboutPanel.swift` | no repeats in a show (R102), About variant A (R103) | P3-15 |
| `Packages/SegueCore/Sources/SetAssistant/` (new) | `SetRequest`, `SetRequestLexicon`, `Scorer` (+breakdown), `Packer`, `SetBuilder` | P3-7 |
| `Packages/SegueCore/Sources/Services/AnalyticsEvent.swift` + `Packages/SegueVendorServices/.../IngestBody.swift` | new rows and allowlist | P3-4 |
| `Packages/SegueAI/` (new package, both flavours) | `FoundationModelsAdapter`, `MLXAdapter`, `GenerableTasks` (wire types, schema export), `ModelStore` (manifest, downloader, app-group paths, lock), `segue-eval` executable | P3-2 (FM), P3-3 (MLX, store, eval) |
| `Packages/SeguePersonalModules/` | Advanced custom models (R97) | P3-3 |
| `Packages/SegueUI/Sources/SegueUI/Paste/` (new) | review sheet (input state for New Song, batch list for several files), empty-state button, Welcome card / TipKit tip | P3-4 |
| `Packages/SegueUI/Sources/SegueUI/Settings/AISettingsView.swift` + `SegueSettingsView.swift` | sixth pane | P3-3 |
| `Packages/SegueUI/Sources/SegueUI/Assistant/` (new) | chips, request field, breakdown popover | P3-7 |
| `Packages/SegueUI/Sources/SegueUI/SmartFilters/` (new), `Library/MainSidebar.swift` | sidebar section, editor | P3-6 |
| `Project.swift`, `Tuist/Package.swift`, `App/*.entitlements`, `scripts/lib/verify-common.sh`, `App/PrivacyInfo.xcprivacy`, `Makefile` | SegueAI dependency, app group, allowed entitlements, DiskSpace reason, `make eval-ai`, Metal Toolchain in `make bootstrap` | P3-2, P3-3 (proven in P3-A) |
| `research/phase3-eval/` | Ryan's pastes (gitignored), local gold and results (gitignored) | P3-A |

## 14. Test strategy and budget

Integration-first: real parser, real file store on a fresh temp library, real GRDB index, real set builder. The only substitute is `ScriptedProvider` replaying recorded real model outputs. Unit tests only for tricky pure logic (chord-line classification, column alignment, packer swap scoring, lexicon).

- **Paste pipeline golden fixtures** (`Tests/Fixtures/paste/`): **30+** original pastes (no copyrighted lyrics), **8+ romanized Hindi**, including the 20 spike fixtures and permanent regression cases E07 (no title block) and H07 (Hindi-dominant), plus `.crd` samples. Each goes raw text -> pipeline (no provider; and ScriptedProvider for FM and MLX recordings) -> Accept -> `.cho` + sidecar in a temp library -> reloaded via the real store and index; asserts byte equality with the expected `.cho`, zero chord loss, zero lyric change. A scripted output that would change a lyric is rejected by the guard.
- **Times:** songs without a time stay `--:--`; totals with changeover, break parts and unknowns match the phase 2 notation; the unknown-time list names exactly the unknown songs.
- **Song card and text helpers:** every card field writes exactly its directive or sidecar field (and removes it when cleared) through the real `DocumentEditor`, reloaded via the real parser; slash-menu wrap and `{` completions produce valid ChordPro; `{key: Hm}` yields a diagnostic with a fix.
- **Section band:** each section operation on real documents round-trips through the parser with zero lyric or chord change and one undo step per gesture.
- **Set assistant:** seeded 300-song fixture library -> lexicon + scripted chips -> real scorer and packer -> draft setlist written and reloaded. Property checks over many seeds: set time within tolerance, filters respected, Learning excluded by default, **no song twice**, locks and break rows kept, same seed same output, breakdown sums to total.
- **Eval target** (`make eval-ai`, manual, never in `make check`): real FM and MLX over the fixtures and Ryan's local pastes, scored with the spike metrics (labels split headed/unheaded, title/artist/key, failure kinds, latency p50/p90, tokens), stored baseline for regression; `RECORD=1` refreshes `ScriptedProvider` recordings. **Real FM/MLX calls never run in `make check` or `make gate`.**
- **E2E (XCUITest)**, fresh library each run: paste -> sheet -> Accept -> song with correct sections, Cancel changes nothing; New Song -> paste flow and Start blank; three files -> one sheet with three ticked rows, untick one -> two imported; `.crd` import; song card fields; slash menu wraps a selection; section band V on selected lines; Pick mode Space/⌘A then Arrange ⌥↑; Library ⌘-click multi-select -> Add to Setlist; break row + per-part totals; unknown-time button; metronome toggle on stage; Insert Next of an already-played song refused; assistant request -> chips -> set within tolerance, breakdown reachable; Settings > AI with no model: size and licence shown, nothing downloads without a click (download stubbed).

**Test budget (R58, written into every workstream):** per step, only the targeted `swift test --filter <Suite>` suites for what changed; per workstream, `make quick` + `make gate` once at the end; `make check` only at the phase gate (P3-9). Never re-run the slow suite after small fixes.

### 14.1 Acceptance criteria

- Every golden fixture yields valid ChordPro with zero chord loss and zero lyric change (English and romanized Hindi); a model response that would change a lyric is always rejected.
- **Quality bar (R64):** with the curated MLX model, section labels and title correct on >= 90% of the golden fixtures AND of Ryan's 10-20 real pastes (eval target). The FM path is measured and reported, with no bar (spike: about 88%).
- AI off, unavailable or failing: paste and import still work, nothing crashes, blocks or waits on a spinner; the deterministic result shows instantly.
- No FM call exceeds its runtime budget; long sheets succeed via MLX or chunking.
- No model downloads without a click; size, licence and RAM need shown first; SHA256 verified; no `Accept-Language` or device User-Agent sent (asserted against a local test server).
- Both flavours read one model store (proven by P3-A, R100), excluded from backup, never in the library or its archive.
- Every paste and conversion import goes through the review sheet; nothing reaches the library without Accept.
- A slot's time comes only from its tempo and played bars (R172); unknown times show `--:--`, totals say `+ N unknown`, and "N unknown" lists exactly those songs.
- Every song card field and slash-menu item writes valid ChordPro or sidecar data with no typing of directive syntax; Text mode shows the result.
- A 20-song set can be built in Pick mode with the keyboard alone (filter, ↓/Space or ⌘A, then ⌥↑/⌥↓ in Arrange), never adding a song twice.
- During a show: no model loads, paste is disabled, no song is added twice, the metronome never makes a sound.
- The set assistant builds a set within tolerance in < 2 s for 300 songs, never repeats a song, and every pick shows its breakdown. Lexicon chips appear in < 100 ms; model chips are async and optional.
- No model is loaded while a show is running; the live view never stalls.
- MLX footprint stays bounded (`Memory.cacheLimit`; peak about 3 GB on Qwen3-4B) and the model unloads right after each paste or request (R94).
- The archived Release-AppStore build passes `verify-archive` (updated check 4) with MLX inside, and `make check` is green at the phase gate.

## 15. Workstreams and waves

| Id | Workstream | Depends on | Wave | Status (2026-10-19) |
|---|---|---|---|---|
| P3-A | MLX in the shipped app: spike + re-run scorer on Ryan's pastes (R64 lock gate) | Ryan's pastes for Part 2 | 1 | Part 1 done (`docs/research/phase3-mlx-in-app.md`, branch `spike/p3a-mlx-in-app`); Part 2 waits on the pastes |
| P3-1 | Deterministic pipeline in Core + golden fixtures | - | 1 | done (55d8701, 33 fixtures); R101 follow-ups go to P3-2 step 0 |
| P3-2 | Converter follow-ups (R101) + provider port + FM adapter + tasks + routing + SegueAI package | P3-1 | 2 | |
| P3-10 | Song card + `{` completion fixes + slash menu (R80, R81) | - | 2 | new |
| P3-11 | Visual-editor section band + section operations (R82) | - | 2 | new |
| P3-12 | Set builder Pick/Arrange, Library multi-select, break rows, changeover (R84-R86) | - | 2 | new |
| P3-6 | Tags + smart filters | P3-10 step 1 (only the tag field step) | 2 | |
| P3-3 | MLX adapter + model manager + AI Settings pane + eval target | P3-A, P3-2 | 3 | |
| P3-4 | Paste/import UI, New Song via paste, batch sheet, menus, Welcome card, analytics | P3-1, P3-2, P3-10 (song card) | 3 | |
| P3-7 | Set assistant | P3-2, P3-6, P3-12 | 3 | |
| P3-13 | Section notes: `{comment}` + cues merged (R87) | P3-10, P3-11 | 3 | new |
| P3-14 | Visual metronome (R90) | P3-12 (live-side break rows) | 3 | new |
| P3-15 | No repeats in a show (R102) + About panel A (R103) | P3-12 (live-side break rows) | 3 | new |
| P3-16 | Per-slot arrangements: skip, repeat and reorder sections for one gig (R122) | P3-12, P3-13 (anchoring) | 3 | new |
| P3-9 | Release fold-in + accessibility re-walk + phase gate `make check` | all | 4 | |

(P3-8, the stats screen, was dropped by R74.) Shell files (`AppModel`, `SegueRootView`, commands, `SegueApp.swift`, `Project.swift`, the Settings host, `MenuShortcuts.swift`) are owned per workstream as listed in each spec:

- **Wave 2:** only P3-2 edits `Project.swift`, `Tuist/Package.swift`, the `Makefile` and the `AppModel` property; only P3-12 edits `MenuShortcuts.swift`, `SetlistCommands.swift` and a Settings pane (General); P3-10 owns `SongMetadataViews.swift`/`SongDetailPane.swift` and the source-editor files; P3-11 owns the visual-editor files and the new `EditOperation` cases.
- **Wave 3:** only P3-3 edits `Project.swift` and the Settings host; only P3-4 edits `MenuShortcuts.swift` and `FileCommands.swift` (P3-14 and P3-15 ask P3-4 for any menu item); P3-14 owns `LiveCommand`/`InputBindings` defaults; P3-15 owns `ShowController` add paths; P3-7 owns `QuickSearchModel`'s lexicon hook.

Sibling workstreams share a working tree: expect unrelated diffs and stage only your own files. Questions 21-29 (section 16.1) are resolved by R104-R112.

**Release order after phase 3 (R79):** phase 3 lands -> Ryan's R56 walkthrough -> WS5 screenshots, preview and metadata -> TestFlight -> real gig -> submit.

## 16. Metadata entry, fast set building and open questions

### 16.0 Metadata entry and fast set building (R80-R90)

**Problem (Ryan's R56 walkthrough):** "The song markers and metadata need to be thought out well, it is hard to type in and remember everything and insert everything correctly, it should be very easy and quick to build a setlist." A read-only audit (2026-10-18) found: key, tempo and time are editable only by typing directives in Text mode; the inspector shows key and tempo as read-only subtitle text; the visual editor can relabel but not create a section; the `{` completion is a flat list of raw names where `{cho` offers only the chorus-*repeat* directive, `{verse` matches nothing, short and labelled forms are never offered and values get no help; `{key}` is never validated (`{key: Hm}` gets in silently); building a 20-song set takes about 110-130 actions and 6 context switches, with no multi-select, no keyboard path from search to add, drag-only reordering.

**Ruling:** direction B (song card + checklist) with A's text helpers (R80-R87); a visual metronome (R90). Every control writes standard ChordPro or the sidecar through the existing edit path (`EditOperation.setDirective` / `.setMeta` in `DocumentEditor`), so Text mode stays the escape hatch and files stay portable. Autosave (R17) and undo apply as everywhere else.

#### 16.0.1 Song card (R80, P3-10)

Shown in the library detail pane (replacing the read-only subtitle "Segue Originals · Am, 84" and holding the proficiency, tags and notes controls), in the editor's inspector, and, in draft mode, as the paste review sheet's metadata block (P3-4; edits the pending result, not a file). A compact read state expands on focus so the inspector does not grow by default.

| Field | Control | Writes |
|---|---|---|
| Title | text field | `{title}` |
| Artist | text field, completion from artists in the library | `{artist}` |
| Key ● | picker of major and minor keys; a detected key (`KeyDetector`) is offered as a suggestion ("Am - from chords") and written only when picked | `{key}` (with a capo: the shapes key, R101) |
| Tempo ● | number field (BPM); Tap per open question 28 | `{tempo}` |
| Capo | stepper 0-11 (the same binding as the editor top bar's stepper) | `{capo}` |
| Time | segmented 4/4, 3/4, 6/8 + Other... | `{time}` |
| Proficiency | the existing Learning / Ready / Pro chips | sidecar |
| Tags | the existing tag field (P3-6 adds completion and starter suggestions) | sidecar |

- ● = **set essential** (R80): key and tempo show a dot when missing; nothing blocks. Whether the marker also appears outside the card is open question 27.
- Clearing a field removes its directive. Each committed field is one undoable edit. An invalid value never reaches the file (the field shows why).
- Accessibility identifiers `segue.songCard.*`; every field reachable by keyboard and VoiceOver.

#### 16.0.2 Text mode helpers (R81, P3-10)

- **Slash menu:** `/` typed at the start of a line (only whitespace before it) opens a vertical, filterable menu with plain names: Verse, Chorus, Bridge, Intro, Outro, Tab, Chorus (repeat), Note, Key..., Tempo..., Capo..., Time.... Matching is fuzzy over words and aliases (`cho`, `ch`, `c`, `soc` -> Chorus; `v`, `sov` -> Verse). A section item **wraps the selected lines** in `{start_of_<kind>: <Label>}` ... `{end_of_<kind>}`, or inserts the pair with the caret inside when nothing is selected, and proposes the next number ("Verse 2" when "Verse 1" exists). Value items open the same pickers as the song card and write the directive at the top of the file (replacing an existing one). Esc closes the menu and leaves the `/` as typed; `/` mid-line is plain text. "Note" inserts a section note (R87, P3-13 decides its storage).
- **`{` completion fixes** (bugs from the audit): items show a plain name beside the directive; typing a section word (`{cho`, `{verse`, `{bri`) offers `start_of_<kind>` and its labelled form first and labels the `chorus` directive "Chorus (repeat)"; short forms (`soc`, `eoc`, `sov`, `eov`, `sob`, `eob`, `c`) are offered as aliases; after `key:`, `tempo:`, `time:` and `capo:` the value pickers appear; inside an open section its `end_of_` stays first (existing).
- **Value validation:** `valueProblem` gains `{key}` (must parse as a key in MusicTheory) and `{time}`; the diagnostic offers a one-click fix where one is clear (`Hm` -> `Bm`, `G major` -> `G`, `A minor` -> `Am`).
- `CompletionPopup` gains a vertical list variant with descriptions, shared by both menus.

#### 16.0.3 Section band (R82, P3-11)

- The visual editor gets a left gutter band per section (colour per kind, label at the top). Lines outside any section show an empty slot.
- Select lines (drag in the gutter, or a text selection), then press **V / C / B / I** (Verse, Chorus, Bridge, Intro) or click a chip in a small floating bar (also Outro, Tab, Custom...) to **create** a section around them, or to **relabel** when the selection is exactly one section. Numbers follow the slash-menu rule.
- **Drag** a band's top or bottom edge to resize it, snapping to line boundaries and clamped at the neighbouring section.
- Context menu: Rename, Change Kind, Unwrap (keeps the lines), Split Here, Merge with Next.
- New `EditOperation` cases in SegueCore `Editing`: wrap lines in a section, set kind/label, move an edge, unwrap, split, merge. Each gesture is one undo step and produces standard ChordPro; the slash menu's wrap (16.0.2) uses the same operation.
- The letter keys act only while the visual editor has a line selection, never in Text mode.

#### 16.0.4 New song (R83, P3-4)

New Song (`⌘N`, the sidebar and empty-state buttons) opens the paste flow (section 6.1) with a **"Start blank"** link: a blank song in the editor with the song card focused on Title. With paste disabled during a show (R95), New Song goes straight to Start blank (open question 26).

#### 16.0.5 Set building (R84-R86, P3-12)

- **Pick | Arrange** segmented control in the builder header.
- **Pick:** the builder's library column becomes a checklist. Click or **Space** ticks the focused row; ↑/↓ move focus; Return in the filter field moves focus to the first result; **⌘A ticks every row the current filter shows**. **Tick order = set order** (each tick appends); unticking removes that song's entry. A ticked row simply is in the set, which is the at-most-once rule made visible. A live total bar shows target, total and the "N unknown" button.
- **Arrange:** the set alone, full width: **⌥↑ / ⌥↓** move the selected rows, drag still works, the per-row popover (`SetEntryEditor`) stays, plus Insert Break.
- **Library multi-select:** the main Library list (`SelectableList`) gains real multi-selection: ⌘-click toggles, ⇧-click selects a range, ⇧↑/⇧↓ extend. **Add to Setlist** (menu, context menu, existing shortcut) adds every selected song in list order, skipping songs already in that setlist, and reports it ("Added 7 songs, 2 were already in the set"). With several songs selected the detail pane shows "N songs selected" and Add to Setlist.
- **Break rows (R85):** a new setlist entry kind with a label ("Set 2", numbered automatically, editable). The rows between breaks form a **part**; each part shows its own total (song times + changeovers + its unknown count) on its break row or header, and the setlist header shows the whole. The setlist schema version bumps; a newer file opens read-only in older builds (the `VersionedJSON` rule). Break-row behaviour on stage and break lengths: open questions 21 and 22.
- **Changeover (R86):** `Setlist` gains an optional changeover in seconds (nil = the global default in Settings > General, default 0 s). It is added after every song but the last of each part (`SetlistTiming` already takes a `changeover` argument); the totals' help text says "incl. 30 s changeovers".
- **Unknown-time list (P8-8):** every "N unknown" in a total (setlist header, part totals) is a button. Its popover lists exactly the songs with no time, in set order, each with an inline Tempo field (type or tap; writes `{tempo}`) and Open Song.

#### 16.0.6 Section notes (R87, P3-13)

One concept replaces `{comment}` vs live cues: a **section note** attached to a section (label + optional occurrence, as `SongCue` anchors today) with a **"Show on stage only"** toggle. Chart notes print and show in every view; stage-only notes appear only in live mode. Storage is open question 23 (recommendation: chart notes stay `{comment}` lines in the `.cho`, stage-only notes stay sidecar cues, and the toggle moves a note between them in one undoable edit). Existing `{comment}` lines and existing cues both appear as section notes; the "Add Notes & Cues..." sheet becomes "Section Notes..."; the section band (16.0.3) shows a note badge per section; the slash menu's Note item creates one.

#### 16.0.7 Visual metronome (R90, P3-14)

- A small overlay in a stage corner (clear of the stage chrome, footer and sidebar) pulsing on every beat at the current song's `{tempo}`, with beat 1 accented per `{time}` (4/4 when absent). The phase restarts when the song changes. With Reduce Motion it shows a stepping beat counter instead of a pulse.
- **Toggle per show** (in the start-show / pre-show checklist) **and by a key** (new `LiveCommand.toggleMetronome`, default key `M`, free in `InputBindings.defaults` today; rebindable; listed in the `?` overlay).
- **Sound only in rehearsal mode** (`session.kind == .rehearsal`): a click on each beat, behind its own toggle. In a gig the audio path does not exist at all (no audio engine is created), so it cannot sound by mistake.
- Driven by an injectable clock (deterministic tests); never on the main thread's critical path; songs without a tempo per open question 25.

#### 16.0.8 Not in 0.5

"Detect sections and key" on existing songs; metronome sound during a show (R90).

### 16.1 Open questions

Questions 1-16 were ruled on 2026-10-18/19 (R92-R100):

3. Tempo in the set assistant: **(b) an explicit filter only** (R92).
4. Opener/closer shaping: **(a) only when asked, via tags** (R92).
7. Personal-only custom-model code: **(a) `SeguePersonalModules`** (R97).
8. Fallback if the shared store fails: **moot**; P3-A proved the store (R100). App Store Connect validation is still pending at the first real `make validate`.
9. AI preferences: **(b) one toggle, "Use AI to refine pastes and set requests", default on** (R93).
10. Offering the download outside Settings: **(b) a quiet link in Settings > AI, the Welcome card and the review sheet footer; no popups** (R93).
11. Model residency: **(b) load per paste or request, unload right after** (R94; P3-A measured a 0.8-1.2 s load).
12. Paste during a show: **(c) paste is disabled** (R95); scope in question 26.
13. Importing many conversion files: **one review sheet listing every converted file, per-file preview and checkbox, import the ticked ones together** (R96, a new option).
14. Model for the set assistant's async pass: **(a) curated MLX if installed, else FM**; output stays suggested chips (R92).
15. "Romanized Hindi detected" flag: **(a) include** (R98).
16. Deleting a downloaded model: **(b) directly after a confirmation** (R99).

New questions raised by R80-R103. Each blocks only the step named; nothing here is decided.

21. **[Resolved: R104] Break rows on stage** (blocks P3-12's live step). (a) A break is a stage interstitial ("Break - Set 2 starts with <song>"); Next continues; the show clock keeps running and the gig log records the break; (b) breaks are builder-only grouping and the stage skips them silently; (c) as (a), but the show pauses (elapsed time stops) until Next. **Recommend a.**
22. **[Resolved: R105] Break length** (blocks P3-12's timing step). (a) A break row may carry an optional length (an intermission), counted in the whole-setlist total but not in either part; (b) no length: breaks only separate parts. **Recommend a.**
23. **[Resolved: R106] Section-note storage** (blocks P3-13). (a) Chart notes stay `{comment}` in the `.cho` (portable, printed), stage-only notes stay sidecar cues; the toggle moves a note between them; (b) every note in the sidecar with a flag (existing `{comment}` lines stay in the file and are shown as read-only chart notes); (c) every note in the `.cho`, stage-only ones as a Segue-specific directive (`{x_stage_note: ...}`, non-standard ChordPro that other apps ignore). **Recommend a.**
25. **[Resolved: R108] Metronome details** (blocks P3-14 step 1). (a) A song without `{tempo}` hides the overlay; the per-show toggle remembers the last choice as the next show's default; rehearsal sound is off by default; (b) as (a), but the per-show toggle always starts off; (c) as (a), but a song without a tempo shows a dimmed "no tempo" overlay. **Recommend a.**
26. **[Resolved: R109] What "paste disabled during a show" covers** (blocks P3-4's show-state step). (a) Every route into the review sheet: New Song from Clipboard, `⌘V` on the list, the empty-state button, `.txt`/`.crd` conversion imports and New Song's paste flow (which goes straight to Start blank); already-ChordPro imports stay allowed; (b) only clipboard paste; file conversions still open the sheet without AI; (c) all imports and new songs are disabled during a show. **Recommend a.**
27. **[Resolved: R110 (c)] Set-essentials marker outside the card** (blocks P3-10's essentials step). (a) Only the card's dots; (b) also a quiet dot on library rows and the builder's library column for songs missing an essential; (c) (b) plus a built-in "Missing essentials" filter chip. **Recommend b.**
28. **[Resolved: R111] Tap tempo on the song card** (blocks P3-10's tempo step). (a) A Tap button next to Tempo (average of the last four taps, rounded); (b) no tap, type the number. **Recommend a.**

29. **[Resolved: R112] What "already played" means for R102** (blocks P3-15 Part 1's classification). (a) Only songs actually played are refused, in gigs and rehearsals alike; a skipped song may be added back; (b) skipped songs count as played too; (c) as (a), but the rule applies to gigs only and rehearsals allow repeats. **Recommend a.**

### 16.2 Deferred to the P3-9 / WS5-stage fold-in (Ryan rules then)

17. **Screenshots:** (a) add a 9th (paste review sheet); (b) replace one of the 8 (e.g. `minsize`); (c) none. **Recommend a.**
18. **Keywords (97/100 bytes):** (a) swap one term for `ai` or `paste`; (b) keep R37 unchanged. **Recommend a** (swap `cover`, recount bytes).
19. **Age-rating AI questionnaire, content-rights answer and App Privacy label with a downloadable model:** (a) a quick research ticket before WS5 (Apple's current questionnaire and guidelines, read at source); (b) answer by best reading in WS5. **Recommend a.**
20. **"Apple Intelligence" in marketing and in-app copy:** (a) use the term per Apple's trademark guidelines (read at source in the research ticket); (b) say "on-device AI" only. **Recommend a, pending the research ticket.**

## 17. Resolved decisions

`docs/release/decisions.md` R61-R79 (2026-10-18) and R80-R103 (2026-10-18/19) and, still valid, `docs/decisions.md` Phase 3: review sheet always shown; no polished batch import (R96's one-sheet batch with checkboxes is not automatic acceptance); recently-played penalty global, not venue-aware; free-form tags with starter suggestions; minimum OS stays macOS 26. Superseded there: FM-first Hindi routing (by R63), any mlx-community model in both flavours (narrowed by R62). The phase 2 rule that an unknown time is never made up stands. A song appears at most once per setlist (walkthrough rule, enforced in code, 1d027df) and at most once per show (R102).

