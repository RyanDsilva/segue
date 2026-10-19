# Phase 3 - AI entry & set assistant

**Status (2026-10-18):** canonical spec, rewritten after the phase 3 spikes and Ryan's rulings R61-R79 (`docs/release/decisions.md`). Phase 3 now ships **in v0.5, in both flavours, before the App Store upload** (R61). Where this doc and an earlier phase 3 ruling in `docs/decisions.md` disagree, R61-R79 win; the superseded entries carry pointer lines. Where this doc and `docs/00-vision.md` disagree on phase 3, R61-R79 win (the vision's AI and library rows carry pointers).

Depends on: phase 0 (Core package, ChordPro parser, library + index), phase 1 (MusicTheory, `KeyDetector`), phase 2 (setlists, shows, rehearsal timings, tags/proficiency basics), and the release build-out (WS1-WS5, `docs/release/`). Inputs: `docs/research/phase3-ai.md` (sources), `docs/research/phase3-spikes.md` (measured results, harness in `research/phase3-spikes/`).

Workstream specs, one per implementation session: `docs/phases/3-workstreams/P3-*.md` (section 15).

---

## 1. Goal

Make adding a song take under a minute from any messy source, and make building a set a one-line request. On-device, free, and working offline once a model is present. AI is an enhancement, never a requirement: with no model at all, every feature still works.

## 2. Scope per flavour

| Feature | App Store flavour | Personal flavour | Ruling |
|---|---|---|---|
| Paste cleanup: deterministic converter + always-on review sheet | yes | yes | R63 |
| File import incl. `.crd` through the converter and review sheet | yes | yes | R76 |
| Apple Foundation Models (FM) refinement | yes | yes | R62 |
| ONE curated MLX model, downloaded on user request | yes | yes | R62, R64 |
| Any `mlx-community` model (Settings > AI > Advanced) + "Check this model" | **no** | yes | R62 |
| Set assistant (lexicon + async model chips) and NL picks | yes | yes | R65 |
| Learned durations, per-song timer, flagged estimates | yes | yes | R70 |
| Tags (starter suggestions) + smart filters | yes | yes | R71, R72 |
| Settings > AI pane (sixth pane) | yes (no Advanced) | yes (with Advanced) | R73 |
| AI analytics events (opt-in, closed vocabulary) | yes | yes | R74 |
| URL import, LRCLIB, audio | no | phase 5 | R61 |

Out of scope for 0.5: energy rating (deferred, R71), AI energy or AI tag guesses at import (R71), a local AI stats screen or metrics database (R74), PDF/photo import (phase 4), macOS 27 `LanguageModel` / `MLXFoundationModels` (revisited in 0.6, R77), Private Cloud Compute.

## 3. Design principle: deterministic first, model last

Code handles everything code can handle. Models only refine: section labels for blocks without a header, title/artist when code found none, and lines code could not classify (R63). The model **never outputs lyric text**: every output refers to blocks or lines by index, so lyrics cannot be respelled by construction (spike section 1). The lyric guard stays as a backstop.

```
raw text (paste, .txt, .crd)
 -> Normalizer        (code)  HTML residue, tabs->spaces, CRLF, smart quotes in non-lyric lines, ads,
                               "Tabbed by"/rating/nav junk, chord-site headers (Singer: | Music: | Lyrics:)
 -> FormatDetector    (code)  ChordPro | chords-over-lyrics | bare lyrics | mixed; per line:
                               chordLine / lyricLine / headerLine ([Verse], Chorus:, V1, Mukhda:) /
                               directive / tab / blank / unknown
 -> Segmenter + hints (code)  blocks on blank lines, lone header merged into the next block; per-block
                               hints: header label, "same lyrics as block N", chords only, tab, no chords
 -> Converter         (code)  chords-over-lyrics -> ChordPro by column alignment; headers -> sections;
                               unlabelled blocks -> {start_of_verse} placeholders
 -> Validator         (code)  every chord parses (MusicTheory, strict: "Do" is never a chord);
                               collect unknown lines and unparseable tokens
 -> Metadata          (code)  {title}/{artist}/{key}/{capo}/{tempo} directives, "Title - Artist" header
                               lines, "Key: G", "Capo 2", "Scale: Am"
 == review sheet opens HERE with the deterministic result (instant, never behind a spinner) ==
 -> AI refinement     (model, async)  only: labels for unheaded blocks, title/artist when code found
                               none, unknown-line classes; results stream into the open sheet
 -> Lyric guard       (code)  the lyric token sequence of the assembled result must equal the
                               converter's; any difference rejects the AI result for that block
 -> Key inference     (code)  stated key wins; else KeyDetector; a model key is used only when
                               KeyDetector.isAmbiguous and the model's key is in the top two
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
- **MLX adapter**: `mlx-swift-lm` with `MLXGuidedGeneration` (`GrammarConstraint(jsonSchema:)` + `GuidedGenerationLoop`, greedy). A no-free-whitespace grammar (compact JSON or EBNF), bounded ints and fixed counts; one retry with a whitespace bias on `incompleteOutput`. `Memory.cacheLimit` set (512 MB start; without it the footprint reached 11.6 GB). Residency per open question 11.
- **`ScriptedProvider`** replays **recorded real outputs** keyed by task + input hash (`Tests/Fixtures/paste/recorded/<provider>/`), recorded by the manual eval target (`make eval-ai RECORD=1`). All automated tests use it; a missing recording is a test failure, never a silent pass.

### 4.1 Routing (R63, supersedes the FM-first rule)

Per paste: **curated MLX if installed -> else FM if available -> else deterministic converter alone.** A provider failure on a call falls through to the next provider in the same order for that call (FM: `unsupportedLanguage`, `guardrail`, `refusal`, `decodingFailure`, `contextOverflow`; `rateLimited`/`busy` after one spaced retry). The review sheet is always shown, whichever path produced the result.

- Hinglish needs no special route: on MLX it scored 100% on the songs it completed; on FM the language rejection is deterministic and costs about 3 ms (spike 2.2), so FM -> deterministic is cheap.
- **No model is loaded during a show** (R65). A paste while a show is running gets the deterministic result; behaviour per open question 12.
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

## 5. Curated model, download and store

### 5.1 Curated model (R64)

**Candidate:** `mlx-community/Qwen3-4B-Instruct-2507-4bit` (upstream `Qwen/Qwen3-4B-Instruct-2507`, Apache-2.0, not gated, 2.28 GB download, about 3 GB peak RAM, about 6.5 s per song on an M1 Pro). **Not locked.** It is locked only after the spike scorer is re-run (P3-A) on **10-20 of Ryan's own real pastes** (UG and other sites, some Hinglish) and reaches the **>= 90%** bar (section labels and title/artist, as in section 14.1). The pastes live in the gitignored `research/phase3-eval/pastes/` (format in its README); they contain copyrighted lyrics and are never committed, quoted in docs or sent anywhere. If Qwen3-4B misses the bar, P3-A reports per-failure kinds and the next candidates (Gemma 4 E2B, Qwen3.5-4B) to Ryan; nothing is swapped without his ruling.

### 5.2 Download (R66)

- Never automatic. Settings > AI shows name, licence (upstream), download size, RAM need, free disk; the user clicks **Download**; progress, cancel, resume; **Delete**.
- Direct from `huggingface.co` (`/resolve/<pinned revision>/<file>`), no mirror, nothing bundled. The app carries a **manifest** per curated model: repo, pinned commit revision, and per file its size and SHA256 (from the Hub's LFS metadata). A file is accepted only when its SHA256 matches; a mismatch deletes it and fails the download.
- **R54 header stripping applies**: no `Accept-Language`, no device `User-Agent` (a fixed `Segue/<version>` one), on every hop including the CDN redirect. Uses the vendor HTTP client pattern from WS3.
- Low RAM (R68): show the memory need; on Macs under 16 GB, a warning ("Needs about 3 GB of memory while it works. On this Mac other apps may slow down."). Never blocked.

### 5.3 Store (R67)

- **Shared between the two flavours** through an **app-group container** (new `com.apple.security.application-groups` entitlement in both flavours, team `V6BM673U35`), at `<group container>/Library/Application Support/Models/<repo>/<revision>/`. `scripts/verify-archive.sh` check 4 (exact entitlements) and the entitlements comments change in the same commit. **Needs proof in P3-A**: Mac App Store app-group rules for a manually signed MAS build plus an automatically signed Personal build, the provisioning-profile capability, and both flavours reading one store. Fallback if the proof fails: open question 8.
- Excluded from backup (`isExcludedFromBackup`), never inside the library folder, never in `LibraryArchive`. Reset All Settings resets AI prefs but **keeps downloaded models** (R73).
- A download in progress is held by a file lock in the group container, so the two flavours never download at once.

## 6. Paste and import UX

### 6.1 Entry points (R75)

- **File > New Song from Clipboard** (`⌥⌘V`). P3-4 verifies it is free: no clash in `MenuShortcuts.all` (the clash test), and no clash with the text system's Paste Style (`⌥⌘V` maps to `pasteFont:` only through a Format menu, which Segue does not have; P3-4 confirms in the editor).
- A **"Paste a Song"** button in the empty-library state.
- **`⌘V` while the song list has focus** (never when a text field or the editor has focus).
- **File > Import Songs...** and drag and drop (existing, WS2a): `.cho/.chopro/.chordpro/.pro` that are already ChordPro import directly (A29); `.txt` and **`.crd`** (R76) that need conversion go through the converter and the review sheet. Multiple conversion files queue one review sheet at a time, with "Skip Remaining" (open question 13). `SongFileTypes.importExtensions` gains `crd`.

### 6.2 Review sheet

- Opens with the deterministic result immediately; AI decisions stream in as they arrive (MLX warm: about 4.4 s labels + 1.8 s metadata; FM: 5-30 s) with a quiet "Refining with <provider>..." line, never a blocking spinner. The user can edit or Accept before refinement finishes (refinement then stops).
- Side by side (layout "a"): original left, result right; AI-decided labels and metadata marked apart from rule-based conversion; unknown lines and unparseable tokens flagged.
- Metadata fields (title, artist, key, capo, tempo, tags with starter suggestions) are editable in the sheet. No energy field (R71), no AI tag guesses (R71).
- Accept writes `.cho` + sidecar through `LibraryStore.commitImport` (the `prepareImport`/`commitImport` split already exists). Cancel leaves the library untouched.
- The footer names what produced the result ("Labels by Qwen3-4B", "Labels by Apple Intelligence", "Converted without AI") and shows the R69 note when relevant.

## 7. Set assistant (R65)

Request -> instant code lexicon -> chips -> deterministic builder; an async model pass adds **suggested** chips.

1. **Lexicon (code, instant):** numbers and durations ("45 min", "10 songs"), keys ("in G", "no Bb"), BPM, proficiency phrases ("know well" -> Ready+, "know cold" -> Pro), tag names as written in the library (fold-insensitive, romanization-tolerant via `RomanNormalizer`), slot phrases ("open strong", "finish big", per open question 4), smart filter names ("from Wedding set"). Fills the chips immediately.
2. **Async model pass:** only when words remain unmapped, after the user stops typing (0.8 s) or presses Return. It maps the leftover words onto the library's **actual** tags and the fixed chip vocabulary; results appear as dashed "suggested" chips the user accepts or ignores. Provider per open question 14. Never blocks; cancelled when the request changes.
3. **Chips** are editable; with no AI, chips are filled by hand. "Songs I know well" maps to proficiency >= Ready; Learning is excluded by default.
4. **Score (code):** weighted signals - proficiency, tag match, recently-played penalty (global across gigs, decaying with days since last played, not venue-aware), slot fit from tags (open question 4), key flow. Weights in config. Every candidate carries a **score breakdown** (signal -> weighted contribution, summing to the total), shown in a popover (hover and keyboard/VoiceOver reachable).
5. **Pack (code):** greedy fill to the target duration (tolerance +/- 3 min default), then a local-swap pass for flow: penalise the same key back to back and adjacent capo/tuning changes, small bonus for closely related keys. **A song appears at most once per setlist** (a hard invariant enforced in the setlist model, from Ryan's walkthrough): the packer never proposes a duplicate and treats it as an invariant, not a score term. Lengths per section 8 (learned > `{duration}` > estimate); estimated lengths are flagged in the result and its total.
6. **Result** opens as a draft setlist in the phase 2 builder; the user drags, locks songs, and hits **Rebuild** to re-pack around the locked ones.
7. **Deterministic:** the builder takes an injectable seed; same library + request + seed gives the same set.

**NL picks.** In the library search field: lexicon chips instantly, model suggestions async as above. **On stage** (quick search during a show): lexicon + text search only; **no model is loaded during a show**. Request queueing on stage follows the same at-most-once rule: a song already in the show cannot be queued again as a new entry.

Energy is deferred (R71): no energy field, signal or chip. Tempo's role is open question 3.

## 8. Durations (R70, supersedes the phase 2 "never made up" ruling)

Learned lengths from real plays, and where nothing is known, **visibly flagged estimates**.

- **Sources:** finished shows (`shows/<ulid>.show.json`, `ShowRecord.playedSongs`), rehearse-setlist runs (`timings/<ulid>.rehearsal.json`), and a new **per-song Start/Stop timer** in the song view writing `timings/<ulid>.timer.json` (`DurationSample.Source.timer`, already reserved). **No duplicate store**: no sidecar `timings` block; learned values are derived from these canonical files into the rebuildable index (storage choice listed for Ryan's confirmation, open question 1).
- **Filtering:** show samples under 40% or over 200% of the current learned value are outliers; samples under 30 s are discarded; requests and "Play now" songs count.
- **Learned value:** median of the last 10 retained samples once there are at least 2.
- **Precedence:** learned -> `{duration}` directive -> **estimate** -> unknown. `SongLengthSource` gains `.estimated`.
- **Estimate:** from `{tempo}` and the lyric line count (formula and calibration, open question 6). Songs with neither a learned length, a directive nor a tempo **stay unknown** (`--:--`, as phase 2).
- **Display:** an estimate always carries a `~` ("~3:40"); totals say what they include ("~41:20, incl. 3 estimated"; with unknowns as well: "≥38:20 + 2 unknown, incl. 3 estimated"). Estimates are never shown without the mark, in the builder, the stage footer, the inspector, smart filters or the assistant.
- **Inspector:** learned length, sample count, source mix; clearing samples per open question 2.
- **Welcome songs** carry `{duration}` lengths (R78). The four shipped Welcome songs already have them (Ferry Lights 4:40, Kettle On 3:05, Kitaabon Wali Gali 4:05, Soundcheck at Seven 3:20); P3-5 adds a test that pins this and adds `{duration}` to WS5's screenshot-only songs when they land.

## 9. Tags and smart filters (R71, R72)

- Tags stay free-form in the sidecar (existing field); autocomplete from tags in use; rename/merge across the library.
- **Starter tags:** an empty tag vocabulary suggests `upbeat`, `ballad`, `crowd pleaser`, `singalong`, `original`, `cover` in the tag picker (manual pick only; nothing pre-applied; they disappear once the user has their own tags; the seed tag "Welcome" does not count as the user's own).
- **Smart filter** = a saved predicate over tags (all/any/none), proficiency, key, tempo range, length range (open question 5 for estimates), last played before/after, never played. Stored as library files **`filters/<slug>.filter.json`** (versioned JSON, `schemaVersion: 1`, ULID id). `LibraryRoot` gains `filtersDirectory`; `LibraryArchive.includedFolders` gains `filters`. Deleting a filter moves it to the Trash (R15). Evaluated against the index.
- Sidebar section **Smart Filters**; a filter is usable as a set-assistant input chip. `SongFilter` (phase 2 simple filtering) stays the in-memory matcher the smart filter compiles to.

## 10. Settings > AI (R73)

A **sixth pane**, "AI", after Live (General, Appearance, Live, AI, Privacy, Data):

- Apple Intelligence status with the R69 note and Open System Settings.
- The curated model card: name, licence with link, download size, RAM need, free disk, Download / progress / Cancel / Delete, low-RAM warning (R68), "candidate" wording until R64 locks it.
- AI preferences (open question 9).
- **Advanced** (Personal flavour only, R62): enter an `mlx-community/...` repo id; the app fetches the model card, shows size and the **upstream** licence (`base_model` card, not only the mlx-community card), downloads only on click; "Check this model" runs the bundled original fixtures through it and shows its score next to the curated model's (not blocked if lower). One active MLX model at a time. Code placement per open question 7.
- Reset All Settings resets AI prefs, keeps models (R73).

## 11. Analytics (R74, analytics only)

No local stats screen and no local metrics database. Opt-in (existing consent), closed vocabulary, non-personal TelemetryDeck events, extending `AnalyticsEvent` and the `IngestBody` allowlist under their existing rules (no `String` payloads; values match `^[A-Za-z0-9+<>._-]{1,24}$`):

| Signal | Parameters (all enums/buckets/Bool) |
|---|---|
| `Segue.AI.pasteFinished` | source (`clipboard`/`emptyState`/`listPaste`/`fileTxt`/`fileCrd`), provider (`mlx`/`fm`/`none`), fallback (`none`/`notInstalled`/`fmOff`/`fmNotReady`/`fmIneligible`/`unsupportedLang`/`guardrail`/`decoding`/`overBudget`/`busy`/`timeout`/`duringShow`/`other`), latency bucket, outcome (`accepted`/`cancelled`), correction bucket (`none`/`small`/`medium`/`large`: edit distance of AI-touched labels and metadata between proposal and Accept) |
| `Segue.AI.modelDownload` | result (`completed`/`cancelled`/`network`/`checksum`/`disk`/`other`), kind (`curated`/`custom`), duration bucket, ramUnder16 (Bool) |
| `Segue.AI.assistantUsed` | context (`builder`/`library`/`stage`), chips by lexicon bucket, suggested chips shown / accepted buckets, provider, rebuilt (Bool) |
| `Segue.AI.smartFilterUsed` | action (`created`/`applied`/`assistantInput`), conditions bucket |

Never song text, titles, artists, tags, queries or model names typed by the user. `featureUsed` gains `runThroughTimer`. The privacy policy's example list is updated in P3-9. Exact names and buckets are fixed in P3-4 with the allowlist test.

## 12. Release impact (owned by P3-A and P3-9)

- **App Review 2.5.2 / 4.2.3(ii):** model weights are data, not code; the download is user-initiated with size shown first (`docs/release/research/03-review-risk.md`). Custom models raise risk, hence Personal-only (R62). Review notes get an AI paragraph (P3-9).
- **MLX in the sandbox + hardened runtime: UNVERIFIED.** P3-A proves Metal kernel compile, model load from the group container and inference in a sandboxed, hardened, archived Release-AppStore build.
- **Tuist and static linking:** the MLX metallib must land in `Contents/Resources` (SwiftPM on the CLI does not build it; the spike used xcodebuild). P3-A measures app size and build-time deltas and keeps `verify-archive` green.
- **Model storage** in the app group (R67), verify-archive check 4.
- **Privacy:** R54 header stripping on downloads; the privacy policy gets a model-download section and a Hugging Face vendor row; the support FAQ ("goes online only for...") gains model downloads; the privacy manifest is diffed for required-reason APIs pulled in by the new dependencies (and Segue's own disk-space check before download). App Privacy label impact of the HF download is part of the WS5-stage research ticket (section 16.2).
- **Third-party notices:** MLX / mlx-swift-lm (MIT), swift-transformers (Apache-2.0), XGrammar (Apache-2.0), every transitive pin `make docs-check` finds, and the curated model's licence (Apache-2.0, Qwen) shown in Settings > AI, in the bundled `THIRD_PARTY_NOTICES.md` and on the web `/acknowledgements` page (the in-app Acknowledgements window was removed 2026-10-18).
- **Memory:** about 3 GB per paste while MLX is active; the live view must never block; no model during a show.
- **Store copy:** review notes are at 3,557 / 4,000 bytes; keywords 97 / 100 bytes; 8 screenshots. WS5 lines that say "no AI in 0.5", "Works offline" and NETWORK USE are superseded and rewritten in P3-9 (open items in section 16.2).
- **Accessibility:** every new surface (review sheet, AI pane, assistant chips, smart filters, timer) gets its own VoiceOver / Voice Control walk before any accessibility label is claimed (R79).

## 13. Code placement and file map

| Where | What | Workstream |
|---|---|---|
| `Packages/SegueCore/Sources/Ingest/` (new module) | Normalizer, FormatDetector, stop list, Segmenter + hints, Converter, Validator, MetadataExtractor, LyricGuard, KeyInference, `.crd` reader, `IngestPipeline` (deterministic result + refinement merge) | P3-1 (refinement merge P3-2) |
| `Packages/SegueCore/Sources/ModelPort/` (new) | `LanguageModelProvider`, tasks and outputs, `ProviderError`, `Router`, `CallMetrics`, `ScriptedProvider` | P3-2 |
| `Packages/SegueCore/Sources/Durations/` (new) | learned-length derivation, `TimerTimingStore`, `LengthEstimator`, effective-length resolver | P3-5 |
| `Packages/SegueCore/Sources/Library/` | `SmartFilter`, `SmartFilterStore`; `SongFileTypes` (+crd, P3-4); index columns for lengths (P3-5) | P3-6, P3-5, P3-4 |
| `Packages/SegueCore/Sources/SetAssistant/` (new) | `SetRequest`, `SetRequestLexicon`, `Scorer` (+breakdown), `Packer`, `SetBuilder` | P3-7 |
| `Packages/SegueCore/Sources/Services/AnalyticsEvent.swift` + `Packages/SegueVendorServices/.../IngestBody.swift` | new rows and allowlist | P3-4 |
| `Packages/SegueAI/` (new package, both flavours) | `FoundationModelsAdapter`, `MLXAdapter`, `GenerableTasks` (wire types, schema export), `ModelStore` (manifest, downloader, app-group paths, lock), `segue-eval` executable | P3-2 (FM), P3-3 (MLX, store, eval) |
| `Packages/SegueUI/Sources/SegueUI/Paste/` (new) | review sheet, import queue, empty-state button, Welcome card / TipKit tip | P3-4 |
| `Packages/SegueUI/Sources/SegueUI/Settings/AISettingsView.swift` + `SegueSettingsView.swift` | sixth pane | P3-3 |
| `Packages/SegueUI/Sources/SegueUI/Assistant/` (new) | chips, request field, breakdown popover | P3-7 |
| `Packages/SegueUI/Sources/SegueUI/SmartFilters/` (new), `Library/MainSidebar.swift` | sidebar section, editor | P3-6 |
| `Project.swift`, `App/*.entitlements`, `scripts/verify-archive.sh`, `Makefile` | SegueAI dependency, app group, check 4, `make eval-ai` | P3-2, P3-3 (proven in P3-A) |
| `research/phase3-eval/` | Ryan's pastes (gitignored), local gold and results (gitignored) | P3-A |

## 14. Test strategy and budget

Integration-first: real parser, real file store on a fresh temp library, real GRDB index, real set builder. The only substitute is `ScriptedProvider` replaying recorded real model outputs. Unit tests only for tricky pure logic (chord-line classification, column alignment, packer swap scoring, lexicon).

- **Paste pipeline golden fixtures** (`Tests/Fixtures/paste/`): **30+** original pastes (no copyrighted lyrics), **8+ romanized Hindi**, including the 20 spike fixtures and permanent regression cases E07 (no title block) and H07 (Hindi-dominant), plus `.crd` samples. Each goes raw text -> pipeline (no provider; and ScriptedProvider for FM and MLX recordings) -> Accept -> `.cho` + sidecar in a temp library -> reloaded via the real store and index; asserts byte equality with the expected `.cho`, zero chord loss, zero lyric change. A scripted output that would change a lyric is rejected by the guard.
- **Durations:** recorded show, rehearsal and timer files (with outliers) -> real store -> learned medians, estimates flagged, the builder uses learned over `{duration}` over estimate.
- **Set assistant:** seeded 300-song fixture library -> lexicon + scripted chips -> real scorer and packer -> draft setlist written and reloaded. Property checks over many seeds: duration within tolerance, filters respected, Learning excluded by default, **no song twice**, locks kept, same seed same output, breakdown sums to total.
- **Eval target** (`make eval-ai`, manual, never in `make check`): real FM and MLX over the fixtures and Ryan's local pastes, scored with the spike metrics (labels split headed/unheaded, title/artist/key, failure kinds, latency p50/p90, tokens), stored baseline for regression; `RECORD=1` refreshes `ScriptedProvider` recordings. **Real FM/MLX calls never run in `make check` or `make gate`.**
- **E2E (XCUITest)**, fresh library each run: paste -> sheet -> Accept -> song with correct sections, Cancel changes nothing; three files -> three sheets; `.crd` import; assistant request -> chips -> set within tolerance, breakdown reachable; timer twice -> learned length; Settings > AI with no model: size and licence shown, nothing downloads without a click (download stubbed).

**Test budget (R58, written into every workstream):** per step, only the targeted `swift test --filter <Suite>` suites for what changed; per workstream, `make quick` + `make gate` once at the end; `make check` only at the phase gate (P3-9). Never re-run the slow suite after small fixes.

### 14.1 Acceptance criteria

- Every golden fixture yields valid ChordPro with zero chord loss and zero lyric change (English and romanized Hindi); a model response that would change a lyric is always rejected.
- **Quality bar (R64):** with the curated MLX model, section labels and title/artist correct on >= 90% of the golden fixtures AND of Ryan's 10-20 real pastes (eval target). The FM path is measured and reported, with no bar (spike: about 88%).
- AI off, unavailable or failing: paste and import still work, nothing crashes, blocks or waits on a spinner; the deterministic result shows instantly.
- No FM call exceeds its runtime budget; long sheets succeed via MLX or chunking.
- No model downloads without a click; size, licence and RAM need shown first; SHA256 verified; no `Accept-Language` or device User-Agent sent (asserted against a local test server).
- Both flavours read one model store (or the open question 8 fallback), excluded from backup, never in the library or its archive.
- Every paste and conversion import goes through the review sheet; nothing reaches the library without Accept.
- After two timed plays, a song's set length comes from its learned value; songs with only a tempo show a `~` estimate and every total says how many are estimated; songs with neither stay unknown.
- The set assistant builds a set within tolerance in < 2 s for 300 songs, never repeats a song, and every pick shows its breakdown. Lexicon chips appear in < 100 ms; model chips are async and optional.
- No model is loaded while a show is running; the live view never stalls.
- MLX footprint stays bounded (`Memory.cacheLimit`; peak about 3 GB on Qwen3-4B) and the model unloads per open question 11.
- The archived Release-AppStore build passes `verify-archive` (updated check 4) with MLX inside, and `make check` is green at the phase gate.

## 15. Workstreams and waves

| Id | Workstream | Depends on | Wave |
|---|---|---|---|
| P3-A | MLX in the shipped app: spike (Tuist, sandboxed Release-AppStore archive, app-group store proof, metallib, size/build deltas, verify-archive green) + re-run scorer on Ryan's pastes (R64 lock gate) | Ryan's pastes for part 2 | 1 |
| P3-1 | Deterministic pipeline in Core + 30+ golden fixtures | - | 1 |
| P3-5 | Durations: learned + timer + flagged estimates + Welcome lengths | - | 1 |
| P3-2 | Provider port + FM adapter + tasks + routing + SegueAI package | P3-1 | 2 |
| P3-6 | Tags + smart filters | P3-5 (length predicate) | 2 |
| P3-3 | MLX adapter + model manager + AI Settings pane + eval target | P3-A, P3-2 | 3 |
| P3-4 | Paste/import UI, menus, Welcome card/tip, analytics events | P3-1, P3-2 | 3 |
| P3-7 | Set assistant | P3-2, P3-5, P3-6 | 3 |
| P3-9 | Release fold-in + accessibility re-walk + phase gate `make check` | all | 4 |

(P3-8, the stats screen, was dropped by R74.) Shell files (`AppModel`, `SegueRootView`, commands, `SegueApp.swift`, `Project.swift`, the Settings host) are owned per workstream as listed in each spec; within wave 3 only P3-3 edits `Project.swift`, only P3-4 edits the commands, only P3-3 edits the Settings host. Sibling workstreams share a working tree: expect unrelated diffs and stage only your own files.

**Release order after phase 3 (R79):** phase 3 lands -> Ryan's R56 walkthrough (with phase 3 items) -> WS5 screenshots, preview and metadata -> TestFlight -> real gig -> submit.

## 16. Placeholders and open questions

### 16.0 Metadata entry and fast set building (pending brainstorm)

**Placeholder - do not design or build yet.** A separate brainstorm (from Ryan's walkthrough) is exploring how to make song markers/metadata entry and setlist building much faster and easier. Its outcome will be folded into phase 3 as a ruling plus edits to this section and to P3-4 / P3-6 / P3-7. Until then those workstreams build what this spec says and keep their UI seams simple (no speculative fast-entry UI).

### 16.1 Open questions for Ryan

Each has a recommendation; nothing here is decided. Workstreams build to the recommendation only where their spec says so, and flag it in the hand-off.

1. **Learned-length storage (confirm R70's default).** (a) Derive from `shows/` + `timings/` (`.rehearsal.json`, new `.timer.json` per timer run), computed into the rebuildable index; (b) a sidecar `timings` block (duplicates shows/timings, needs schema v4); (c) derived, plus a per-song cache file under `.segue/`. **Recommend a.**
2. **Clearing a song's learned samples** (derived storage cannot delete show files). (a) A sidecar `lengthSamplesSince` date; samples before it are ignored (sidecar schema v4; older builds open read-only); (b) no clearing in 0.5, outlier filtering only; (c) a per-sample exclusion list in the sidecar. **Recommend a.**
3. **Tempo in the set assistant** (R71 names tags, length, key flow, repeat avoidance). (a) Not used; (b) as an explicit filter only ("under 100 bpm" via the lexicon and smart filters); (c) filter plus a flow penalty for big tempo jumps. **Recommend b.**
4. **Opener/closer shaping without energy.** (a) Only when asked: slot phrases map to tag preferences (open with `upbeat`, close with `crowd pleaser`/`singalong`) when those tags exist; (b) those tag preferences by default whenever the tags exist; (c) no slot shaping; locks only. **Recommend a.**
5. **Estimated lengths in smart filters and the assistant.** (a) Count everywhere, always shown with `~`; (b) the packer uses them, length filters ignore them; (c) only learned/directive lengths count anywhere. **Recommend a.**
6. **Estimate formula.** (a) Fixed rule: 2 bars per lyric line at the song's `{time}` (4/4 default), repeats counted, clamped 1:30-8:00; (b) (a) plus a per-library calibration of bars-per-line from songs that have both a learned length and a tempo (once 5+ exist). **Recommend a for 0.5**, with the Welcome songs (directive + tempo) as a test oracle; b in 0.6.
7. **Where the Personal-only custom-model code lives.** (a) `SeguePersonalModules` (mechanically excluded; `verify-appstore` symbol check extended); (b) `SegueAI` behind a runtime flavour flag. **Recommend a.**
8. **Fallback if P3-A cannot prove the shared app-group store.** (a) Per-flavour stores in each container (a Personal user downloads twice, 4.6 GB total); (b) the Personal flavour opens the App Store flavour's store through a user-granted folder bookmark; (c) ship the App Store flavour only with MLX and the Personal flavour FM-only until fixed. **Recommend a.**
9. **AI preferences in Settings > AI.** (a) None (AI used whenever available); (b) one toggle "Use AI to refine pastes and set requests", default on; (c) per-provider toggles (Apple Intelligence / downloaded model). **Recommend b.**
10. **Offering the curated download outside Settings** (R69 bans nag prompts). (a) Only Settings > AI and the Welcome card's link to it; (b) also a quiet one-line link in the review sheet footer when the result came from FM or code; (c) also a one-time TipKit tip after the third paste. **Recommend b.**
11. **MLX model residency.** (a) Load when the paste sheet or assistant opens, unload 2 min after last use and immediately when a show starts; (b) load per request, unload right after (adds about 2.3 s cold per paste); (c) keep loaded while Segue is frontmost. **Recommend a.**
12. **Paste while a show is running.** (a) Deterministic result, with "AI cleanup is paused during a show" and a Refine button that works after the show ends; (b) deterministic only, no refine later; (c) refuse paste during a show. **Recommend a.**
13. **Importing many files that need conversion.** (a) One review sheet per file with "Skip Remaining" (skipped files listed in the import summary); (b) also "Accept All Remaining (converted without AI)"; (c) cap conversions per import (e.g. 20). **Recommend a.**
14. **Model for the set assistant's async pass.** (a) Curated MLX if installed, else FM (FM scored 65% of fields, inventing values); (b) curated MLX only, no FM for set requests; (c) lexicon only in 0.5. **Recommend b.**
15. **A "romanized Hindi detected" flag in `pasteFinished`.** (a) Include (useful for routing quality); (b) exclude (content language can be a proxy for origin). **Recommend b.**
16. **Deleting a downloaded model** (R15 sends every delete to the Trash). (a) Move it to the Trash like any delete (2.3 GB lands there); (b) remove it directly after a confirmation, since it is re-downloadable app data, not a user document. **Recommend b.**

### 16.2 Deferred to the P3-9 / WS5-stage fold-in (Ryan rules then)

17. **Screenshots:** (a) add a 9th (paste review sheet); (b) replace one of the 8 (e.g. `minsize`); (c) none. **Recommend a.**
18. **Keywords (97/100 bytes):** (a) swap one term for `ai` or `paste`; (b) keep R37 unchanged. **Recommend a** (swap `cover`, recount bytes).
19. **Age-rating AI questionnaire, content-rights answer and App Privacy label with a downloadable model:** (a) a quick research ticket before WS5 (Apple's current questionnaire and guidelines, read at source); (b) answer by best reading in WS5. **Recommend a.**
20. **"Apple Intelligence" in marketing and in-app copy:** (a) use the term per Apple's trademark guidelines (read at source in the research ticket); (b) say "on-device AI" only. **Recommend a, pending the research ticket.**

## 17. Resolved decisions

`docs/release/decisions.md` R61-R79 (2026-10-18) and, still valid, `docs/decisions.md` Phase 3: review sheet always shown; no polished batch import; recently-played penalty global, not venue-aware; free-form tags with starter suggestions; rehearsal timing from both rehearse-setlist runs and a per-song timer; minimum OS stays macOS 26. Superseded there: FM-first Hindi routing (by R63), energy 1-5 and AI energy at import (by R71), any mlx-community model in both flavours (narrowed by R62), and the phase 2 "unknown length never made up" rule (by R70). A song appears at most once per setlist (walkthrough rule, enforced in code).
