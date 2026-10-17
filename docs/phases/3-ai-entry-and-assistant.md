# Phase 3 - AI entry & set assistant

Depends on: phase 0 (Core package, ChordPro parser, library + index), phase 2 (setlists, tags/proficiency basics). Canonical context: `docs/00-vision.md`, `docs/research.md`. If this doc and the vision disagree, the vision wins.

## Goal

Make adding a song take under a minute from any messy source, and make building a set a one-line request. All on-device, offline, free.

## Scope

1. **Paste + AI cleanup** - paste anything (chords-over-lyrics, ChordPro, bare lyrics, mixed junk from a web page) and get a clean ChordPro song with metadata and labelled sections.
2. **File import** - `.cho/.chopro/.crd/.pro`, `.txt` (chords-over-lyrics or bare lyrics), drag-and-drop or Open panel. Multiple files are accepted but simply queue through the review sheet one at a time; no batch-import dashboard (the library starts empty, so it isn't worth polishing).
3. **AI provider port** - one interface, two adapters: Apple Foundation Models (default) and MLX-Swift (fallback).
4. **Set assistant** - build a set to a target length; natural-language song picks ("something upbeat in G I know well").
5. **Tags + smart filters** - saved filters over tags, proficiency, energy, key, tempo, duration, last played.
6. **Learned durations + energy** - real song durations measured from shows and rehearsal run-throughs; a per-song energy rating (1-5) for set flow.

Out of scope: URL import, LRCLIB, audio (phase 5, restricted module); PDF (phase 4).

## Design principle: deterministic first, model last

The LLM never touches text that code can handle. Pipeline for a paste:

```
raw text
 -> Normalizer        (code)  strip HTML residue, tabs->spaces, smart quotes, trailing junk, ads/"Tabbed by" lines
 -> FormatDetector    (code)  ChordPro | chords-over-lyrics | bare lyrics | mixed; per-line classification:
                               chordLine / lyricLine / headerLine ([Verse], Chorus:) / directive / tab / blank / unknown
 -> Converter         (code)  chords-over-lyrics -> ChordPro by column alignment (chord at col N inserted before
                               the lyric char at col N; chords past line end appended); header lines -> sections
 -> Validator         (code)  every chord token parses via MusicTheory; collect `unknown` lines + unparseable tokens
 -> AI enrichment     (LLM)   only: metadata (title/artist/key guess), section labels for unlabelled blocks,
                               resolving `unknown` lines (chord line? lyric? note?)
 -> Lyric guard       (code)  lyric token sequence of the AI result must equal the converter's; any change to a
                               lyric word (respelling, translation, casing fix, added/removed word) rejects the AI
                               result for that chunk and the deterministic result is used instead
 -> Key inference     (code)  key from chord set (MusicTheory) cross-checked with the LLM guess; code wins on conflict
 -> Review sheet      (UI)    ALWAYS shown: side-by-side original vs result, diffs and every AI decision
                               highlighted, accept/edit/cancel. Nothing is saved to the library until Accept.
```

**Romanized Hindi.** Lyrics may be Hindi written in Latin script with no fixed spelling. The pipeline never transliterates, translates or respells lyrics: the Normalizer touches only whitespace, HTML residue and quote characters, and the lyric guard enforces that the model cannot change a lyric word. Every prompt states that lyrics may be romanized Hindi or English and must be copied verbatim, never translated or corrected, and asks only for labels and metadata. Chord-line detection must not mistake Hindi lyric lines for chord lines (words like "Am", "Dm", "Bas", "Main" in a lyric line): a line is a chord line only if most of its tokens parse as chords and none is a common romanized Hindi or English word from a small stop list (fixtures cover this).

Port ChordSheetJS (MIT) heuristics for chord-line detection and alignment as reference only. If no AI provider is available, the pipeline still produces a usable song (unlabelled blocks become `{start_of_verse}` placeholders; metadata left blank). AI is an enhancement, never a requirement.

## AI provider port

```swift
protocol LanguageModelProvider: Sendable {
    var id: ProviderID { get }                  // .foundationModels, .mlx(modelID)
    var capabilities: ProviderCapabilities { get } // contextTokens, structuredOutput, available
    func availability() async -> ProviderAvailability
    func generate<T: GenerableTask>(_ task: T) async throws -> ModelResult<T.Output>
}
struct ModelResult<O> { let output: O; let metrics: CallMetrics }
```

- Tasks are typed (`SectionLabelTask`, `MetadataTask`, `AmbiguousLineTask`, `SetRequestParseTask`), each with a fixed small prompt, a `@Generable` output struct (FM) and a JSON schema (MLX).
- **FM adapter**: `SystemLanguageModel.default`, check availability (Apple Intelligence enabled, device eligible, model ready), `@Generable` guided generation. Budget per call from `contextSize`/`tokenCount()` (26.4+); chunk per section so no single call exceeds ~2,500 input tokens, leaving room for instructions + output.
- **MLX adapter**: `mlx-swift-lm`. Structured output via JSON schema + parse-and-retry (max 2) if no constrained decoding is available.
  - **Curated model:** one recommended model offered as a one-click download, chosen by an eval spike (task 6a) over 2-4 candidates (e.g. Qwen3 ~4B 4-bit, Gemma, Phi-4-mini) on the paste eval set and set-request parsing, weighing quality, latency, RAM and download size. Licence verified at source before it is offered.
  - **Any mlx-community model (advanced):** Settings > AI > Advanced accepts a Hugging Face `mlx-community/...` repo id. The app fetches the model card, shows size and declared licence, and downloads only on click. A custom model runs the paste eval set on demand ("Check this model") and shows its score next to the curated model's; it is not blocked if it scores lower. Only one active MLX model at a time.
- **Routing (config-driven, per task)**:
  1. FM available and input fits budget after chunking -> FM.
  2. FM unavailable, input cannot be chunked (task needs whole-song view), or FM fails structured output twice -> MLX if installed.
  3. Neither -> deterministic-only result, UI says "AI unavailable" with reason.
- **MLX model download UX**: never automatic. Settings > AI shows model name, licence, download size, disk space; user clicks Download; progress, cancel, resume; stored in the app container's Application Support (not the library folder). Delete button. Unavailable while downloading falls back per routing. Same flow for curated and custom models.
- **Fake provider** (`ScriptedProvider`) returns canned outputs keyed by task + input hash - used by all unit/UI tests.

## Set assistant

Natural-language request -> constraints -> deterministic builder.

1. **Parse (LLM)**: `SetRequestParseTask` turns text into a `SetRequest` struct: `targetDuration`, `filters` (tags include/exclude, minimum proficiency as one of Learning / Ready / Pro, energy range, keys, tempo range), `shape` (e.g. opener energy high, closer crowd pleaser), `count?`. "Songs I know well" maps to proficiency >= Ready; "know cold" to Pro. Shown to the user as editable chips before building, so a misparse is visible and fixable. Without AI, the same chips are filled by hand.
2. **Score (code)**: each candidate gets weighted signals - proficiency (Learning / Ready / Pro mapped to configurable values, Learning excluded by default), tag match, recently played penalty (global across all gigs, decaying with days since last played; not venue-aware), energy fit for its slot (from the explicit energy rating; tempo used only when energy is unset), tempo fit. Weights in config. Each song carries a **score breakdown** (signal -> weighted contribution, summing to total), visible on hover.
3. **Pack (code)**: greedy fill to target duration (tolerance +/- 3 min default), then local-swap pass to improve flow: penalise big energy and tempo jumps, adjacent capo/tuning changes, and repeated keys back-to-back. Duration per song, in priority order: learned duration, then `{duration}` directive, then estimate from tempo + line count. Estimated durations are flagged in the UI.
4. **Result** opens as a draft setlist (phase 2 setlist editor); user drags, locks songs, hits Rebuild to re-pack around locked ones.

**Natural-language picks** (mid-gig or library): same parse step -> filter struct -> ranked results from the index. Must return in under 1 s on FM; if the model is busy/unavailable, fall back to plain text search instantly. Never blocks the live view.

Deterministic seed: builder takes an injectable RNG/seed so the same library + request gives the same set in tests.

## Learned durations + energy

**Sidecar schema additions** (requires a sidecar schema version bump under phase 0's versioning rules; older apps open these songs read-only):
- `energy: 1...5` - optional, set in the song inspector and in the review sheet on import, where it is prefilled with an AI suggestion (from tempo and lyrics) that the user can change or clear before Accept. When blank, the scorer falls back to tempo.
- `timings: { samples: [{ at, seconds, source: "show" | "rehearsal" }], learned: seconds? }` - capped at the last 10 samples.

**Sources of samples:**
- **Shows:** derived from phase 2 show events (song start to next advance). Samples under 40% or over 200% of the current learned value are dropped as outliers (skipped early, left on screen during a break). Requests and "Play now" songs count too.
- **Rehearsal (both paths):** (a) a rehearse-setlist run - the live view driven through a setlist in rehearsal mode (phase 2), timing every song without creating a show or gig-log entry; (b) a Start/Stop run-through timer in the song view, one tap to start, one to stop. Samples under 30 s are discarded.

**Learned value:** median of retained samples once there are at least 2; until then the `{duration}` directive or estimate is used. The song inspector shows learned duration, sample count and lets the user clear samples.

## Tags + smart filters

- Tags stored in the song JSON sidecar; free-form, autocomplete from existing tags, rename/merge across library.
- **Starter tags:** an empty library suggests a small starter set in the tag picker - `upbeat`, `ballad`, `crowd pleaser`, `singalong` (plus `original`, `cover`). Suggestions only; nothing is pre-applied, and they disappear from suggestions once the user has their own tags in use.
- Smart filter = saved predicate (tags, proficiency level, energy range, key, tempo range, duration range, last played before/after, never played) stored as JSON in the library folder; evaluated against the SQLite index.
- Sidebar section "Smart Filters"; filters usable as set-assistant inputs.
- Optional AI tag suggestions on import (mood/tempo feel) - shown as suggestions, never applied silently.

## Observability (local, no cost)

Every model call logs a `CallMetrics` record to a local SQLite table (rebuildable data does not apply here - this is operational state): task, provider, model id, input/output tokens (FM `tokenCount`, MLX tokenizer), latency, success/structured-output retries, fallback reason.

Settings > AI > Stats shows:
- avg latency and tokens per task, per provider
- fallback rate (FM -> MLX -> deterministic) and reasons
- **correction rate**: per imported song, how much the user changed the AI-touched parts before/after accept (edit distance on sections/metadata, chord changes) - the real quality signal
- set assistant: songs swapped/removed after build
- key-inference agreement rate (code vs LLM)

## Tasks

1. **Re-verify at source** the unverified WWDC26 Foundation Models claims in `research.md` (bigger context, PCC access for third-party apps, MLX backend behind the FM protocol, image input). Update `research.md` and adjust the port if MLX can sit behind FM's own protocol.
2. Normalizer + FormatDetector + Converter + Validator + lyric guard with golden fixtures (including romanized Hindi pastes).
   - 2a. **Verify Foundation Models behaviour on romanized Hindi** at source and in a spike: documented language support, and whether section labelling/metadata extraction stays accurate when lyrics are Hinglish. Record in `research.md`; if quality is poor, route Hindi-heavy songs to MLX or deterministic-only.
3. Provider port, FM adapter, fake provider, metrics store.
4. Enrichment tasks + chunking + key inference.
5. Paste/import UI: paste sheet, drag-and-drop (multi-file queues through the review sheet), always-on review sheet.
6. MLX adapter + download manager + routing config.
   - 6a. Eval spike to choose the curated model; record results in `research.md`.
   - 6b. Advanced custom mlx-community model entry + "Check this model" eval run.
7. Sidecar additions (`energy`, `timings`) with schema bump; learned-duration derivation from show events; rehearsal timer.
8. Tags (starter suggestions) + smart filters (index queries, sidebar, editor).
9. Set assistant: parser task, scorer with breakdown, packer, chips UI, rebuild-with-locks.
10. Stats view.

## Test strategy

Integration-first: tests run the whole pipeline end to end through real components (real parser, real file store on a fresh temp library, real GRDB index, real set builder). The only substitute is the `ScriptedProvider` standing in for the model, so AI paths stay deterministic and offline. No mock-heavy unit tests of individual pipeline stages.

- **Paste pipeline integration (golden fixtures,** `Tests/Fixtures/paste/`): 30+ real-world-shaped messy pastes (UG-style, chords inline, tabs mixed in, `[Chorus]` headers, `x2` repeats, Windows line endings, capo notes, ads, trailing comments), each with expected `.cho`. Each fixture goes raw text -> full pipeline (fake provider, and again with no provider) -> Accept -> `.cho` + sidecar written to the temp library -> reloaded through the real store and found via the index. Assert the reloaded file equals the expected `.cho` and that chords are untouched.
- **Romanized Hindi pastes:** at least 8 of the paste fixtures are Hindi songs in Latin script (original fixture text), in UG style and plain style, including lines with chord-like words ("Main", "Am", "Bas"). Expected output keeps every lyric character identical. A scripted-provider fixture that returns respelled or translated lyrics must be rejected by the lyric guard, with the deterministic result shown in the review sheet.
- **Learned durations integration:** replay recorded show JSON files (from phase 2's format, including outliers) and rehearsal timer runs through the real store; assert `timings` in the sidecar, the learned median, and that the set builder then uses it over `{duration}`.
- **Set assistant integration:** seeded fixture library (300 songs with tags, proficiency, energy, timings, gig history) -> fake-parsed request -> real scorer + packer -> draft setlist file written and reloaded. Property checks over many seeds: duration within tolerance, filters respected, Learning excluded by default, locked songs stay put, same seed -> same output, breakdown sums to the total.
- **Unit tests (pure logic only):** chord-line classification and column alignment edge cases in the converter, and the packer's local-swap scoring - only where a failing integration fixture can't pinpoint the cause.
- **Eval set** (separate target, run manually or nightly, not in CI): same fixtures through real FM and MLX (curated model, and any custom model via "Check this model"), scored on section-label accuracy, metadata accuracy, chord preservation (must be 100% - the model may never alter a chord), with a stored baseline to detect regressions when prompts or models change.
- **E2E (XCUITest)** on a freshly reset library each run:
  1. Paste fixture -> review sheet appears -> accept -> song in library with correct sections; cancel leaves the library unchanged.
  2. Drop three files -> three review sheets in sequence -> three songs in library.
  3. "30 min set, songs I know well" with fake provider -> chips show proficiency >= Ready -> setlist within tolerance, score breakdown visible on hover.
  4. Rehearsal timer start/stop twice on one song -> inspector shows a learned duration.
  5. Settings > AI with no model installed: download button shows size and licence; nothing downloads without a click (download itself stubbed).

## Acceptance criteria

- Pasting any golden fixture yields valid ChordPro with zero chord loss; with AI on, section labels and title/artist correct on >= 90% of fixtures (eval set).
- AI off / unavailable: paste and import still work, nothing crashes or blocks.
- Zero lyric words altered across all fixtures, English and romanized Hindi alike; a model response that changes a lyric word is always rejected by the lyric guard.
- No single FM call exceeds its context budget; long songs succeed via chunking or MLX.
- MLX model never downloads without an explicit click; size and licence shown first, for curated and custom models alike.
- Every paste and import goes through the review sheet; nothing reaches the library without Accept.
- After two timed plays, a song's set-builder duration comes from its learned value, not the estimate.
- Set assistant produces a set within tolerance in < 2 s for a 300-song library; every pick shows its score breakdown.
- NL pick returns in < 1 s or falls back to text search; live view never stalls.
- Stats view shows latency, tokens, fallback rate and correction rate from real use.

## Resolved decisions

See `docs/decisions.md` (Phase 3).

1. **MLX model:** curated one-click model chosen by an eval spike, plus an advanced setting for any mlx-community model. Implication: task 6a/6b, custom models scored but not blocked.
2. **Durations:** learned from real plays (shows and rehearsal timer). Implication: new `timings` sidecar field; learned > `{duration}` > estimate.
3. **Energy:** explicit per-song 1-5 rating. Implication: new `energy` sidecar field (schema bump), used in scoring and flow.
4. **Review sheet:** always shown. Implication: nothing auto-accepts.
5. **Batch import:** not polished; multi-file drops queue through the review sheet.
6. **Recently-played penalty:** global across gigs, not venue-aware.
7. **Tags:** free-form plus a few suggested starter tags.
8. **Rehearsal timing: both** a rehearse-setlist run (live view without a show record, defined in phase 2) and a per-song Start/Stop timer in the song view. Both feed `timings`.
9. **Energy at import:** optional field in the review sheet, prefilled with an AI suggestion (from tempo and lyrics); blank is allowed and the scorer falls back to tempo.

## Open questions

None open.
