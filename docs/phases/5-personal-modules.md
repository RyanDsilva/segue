# Phase 5 - Personal modules (restricted package)

> Canonical context: `docs/00-vision.md` (decisions) and `docs/research.md` (verified facts). This doc is standalone for the phase 5 build session. If it disagrees with the vision doc, the vision doc wins.

## 1. Goal

Ship a separate local Swift package, `SeguePersonalModules`, living as a **folder in this repo at `Packages/SeguePersonalModules`**, that adds three licence-sensitive capabilities to the **Personal** build only:

1. **Audio-to-chart** - record or drop an audio file, get a draft ChordPro chart (lyrics, chords, tempo, sections) to correct.
2. **LRCLIB lyrics search** - type a title/artist, get plain lyrics as a starting point.
3. **URL import** - paste a chord-site URL (or Share from Safari), extract the chart.

The **App Store** scheme must not reference this package at all: absent from the source tree it builds, from the build graph, and from the binary. Core (`SegueCore`) never imports it; it only exposes protocols the package implements.

Why restricted: chord models are GPL or non-commercial (Chordino GPL, BTC weights CC-BY-NC-SA, aubio GPLv3, Essentia AGPL, libKeyFinder GPLv3, madmom models CC-BY-NC-SA); LRCLIB's content licence is unclear; scraping chord sites breaches their ToS (Ultimate Guitar). The licence-clean audio parts (WhisperKit MIT, Demucs MIT, All-In-One MIT) also stay here for now, by decision.

## 2. Plugin contract in core

Core owns the protocols and a registry; it ships with zero implementations of them (App Store build simply shows no audio/URL/LRCLIB entry points).

```swift
// SegueCore/Plugins
public protocol SongImporter: Sendable {
    static var id: PluginID { get }
    var displayName: String { get }
    func canImport(_ input: ImportInput) -> Bool        // .url(URL), .file(URL), .text(String)
    func importSong(_ input: ImportInput, progress: ProgressSink) async throws -> DraftSong
}

public protocol AudioAnalyzer: Sendable {
    static var id: PluginID { get }
    var capabilities: Set<AudioCapability> { get }      // .lyrics, .tempo, .beats, .sections, .chords, .key
    func analyze(_ audio: AudioSource, options: AnalysisOptions,
                 progress: ProgressSink) async throws -> AudioAnalysis
}

public protocol LyricsSource: Sendable {
    static var id: PluginID { get }
    func search(title: String, artist: String?) async throws -> [LyricsCandidate]
    func fetch(_ candidate: LyricsCandidate) async throws -> LyricsResult
}

public final class PluginRegistry {          // built once at launch, immutable after
    public func register(_ importer: any SongImporter)
    public func register(_ analyzer: any AudioAnalyzer)
    public func register(_ source: any LyricsSource)
}
```

- `DraftSong` is core's existing "unsaved song" value (ChordPro AST + metadata + provenance). Every plugin result lands in the same review/correct flow used by paste cleanup (phase 3); nothing is saved without user confirmation.
- `AudioAnalysis` is a typed, timestamped result: `words: [TimedWord]`, `chords: [TimedChord]`, `beats`, `tempo`, `sections: [TimedSection]`, `key`, each with a confidence. Alignment into ChordPro is **core code** (deterministic, testable), not plugin code, so any analyzer benefits.
- UI asks the registry what is available; it never checks build flags.

**Registration.** The Personal scheme's app target links `SeguePersonalModules` and contains one file, `PersonalPlugins.swift`, that calls `SeguePersonalModules.registerAll(into: registry)` at launch. That file belongs only to the Personal target's membership. The App Store target has no such file and no package dependency. No `#if PERSONAL` in shared code.

## 3. Enforcing absence from the App Store build

Mechanical checks, run in CI and as a pre-archive script, fail the build on any hit:

1. **Graph check** - `xcodebuild -scheme AppStore -showBuildSettings` plus resolved package graph (`Package.resolved` / `xcodebuild -resolvePackageDependencies -scheme AppStore`) must not list `SeguePersonalModules`, WhisperKit, or any restricted dependency.
2. **Source check** - script greps sources compiled by the AppStore target (from the target's file list) for `SeguePersonalModules`, `import WhisperKit`, `LRCLIB`, and module type names.
3. **Binary check** - on the archived `.app`: `nm`/`otool -L`/`strings` scan for restricted symbols, frameworks, bundled model files (`*.mlmodelc` from the package), and the LRCLIB host. Zero matches required.
4. **Export check** - if a source tree is ever exported for App Store builds, the exporter copies only paths in an allowlist; the restricted package directory is not on it.

Decided: the package stays an in-repo folder (`Packages/SeguePersonalModules`); these checks, not repo separation, are the enforcement. They run in `make verify-appstore` (phase 0) and must pass before any App Store archive.

## 4. Model packaging and runtime

- **No Python at runtime.** All conversion (PyTorch -> Core ML or MLX) happens offline via scripts in `SeguePersonalModules/Tools/convert/` (Python via `uv`), producing versioned artifacts with a manifest (name, version, source commit, licence, sha256, size).
- **Download on demand, not bundled.** First use of a capability prompts "Download speech model (~X MB)?" Artifacts go to the app's Application Support container, verified by sha256. Keeps the app small and lets models update independently. Stage use never triggers a download.
- Rough sizes to confirm in spikes: WhisperKit models from ~40 MB (tiny) to ~1.5 GB (large-v3); HTDemucs ~80-300 MB; All-In-One and BTC small (tens of MB). Default picks: smallest model meeting the eval targets.
- Analysis runs off the main thread with progress and cancel; target <= 1x song length on an M-series MacBook for a 4-minute song.

## 5. Pipeline (audio-to-chart)

1. **Input** - drop file (m4a/mp3/wav/aiff) or **record in-app (in 5a)** via AVAudioEngine: level meter, start/stop, re-take; mic usage description + `com.apple.security.device.audio-input` entitlement in the Personal scheme only. The recording is a temp file used for analysis and **discarded after drafting** (not stored with the song by default).
2. **Separation** - HTDemucs -> vocals stem + accompaniment stem (skippable for solo voice+guitar takes; measure both).
3. **Lyrics** - WhisperKit and Apple SpeechAnalyzer both implemented behind one internal `LyricsTranscriber` interface with word timestamps. **The default engine is chosen by the eval on the user's own recordings** (lower WER wins; tie-break documented in the eval report); the other stays selectable in settings.
4. **Beats, tempo, sections** - All-In-One converted to Core ML/MLX; output BPM, downbeats, labelled segments (verse/chorus/bridge/intro/outro).
5. **Chords** - BTC (NC weights) or Chordino (GPL, C++ via VAMP host or direct port) on accompaniment stem; snap chord changes to beats.
6. **Key** - derive from chord sequence in core MusicTheory (avoids GPL key detectors); restricted detector only if eval demands.
7. **Alignment (core)** - assign each chord change to the word whose start is nearest at or after the change within a tolerance; chords in instrumental gaps become instrumental lines; sections from step 4 become ChordPro section directives; repeated sections deduplicated.
8. **Romanization (core)** - ASR engines usually return Hindi in Devanagari (or translate it). Hindi output is converted deterministically to casual Bollywood romanization (no diacritics: "tum hi ho", "pyaar", "dil", "hai") by a `HindiRomanizer` in core: a rule table (consonants, matras, inherent-vowel deletion at word end and in common medial positions, nasalization as "n", nukta forms) plus an override dictionary for frequent words where the casual spelling differs from the rules. No language model in the loop, so output is reproducible. English words in mixed lines pass through unchanged. If an engine translates instead of transcribing, that engine is flagged for Hindi in the eval and not used for Hindi takes.
9. **Draft** - ChordPro + metadata (`tempo`, `key`, `duration`) opened in the review UI with per-word/per-chord confidence highlighting and audio scrub.

## 6. Sub-milestones

- **5a - Lyrics, tempo, sections.** Package scaffold, registry wiring, absence checks (section 3), model download manager, in-app recording, Demucs + WhisperKit + SpeechAnalyzer (ASR eval picks the default) + All-In-One, draft with lyrics and sections only.
- **5b - Chords.** Chord model integration, beat snapping, key from chords.
- **5c - Alignment and review UI.** Core alignment, confidence highlighting, play-from-here scrubbing, accept/fix flow into the editor.
- **5d - LRCLIB.** `LyricsSource` implementation (search, fetch plain lyrics; synced LRC kept as optional timing hint), result feeds paste-cleanup AI to add structure. Attribution shown. Results returned in Devanagari go through `HindiRomanizer` first; search queries in romanized Hindi also try the normalized form from phase 0.
- **5e - URL import.** `SongImporter` for URLs: fetch the page the user chose and extract the chart. Site-specific extractors for **Ultimate Guitar, E-Chords and Chordie**, plus **generic page extraction** for any other site (readable-text extraction, then the phase 3 chords-over-lyrics converter + AI cleanup). Share extension in Personal build only.

Each sub-milestone ends with a green test suite, passing absence checks, and an E2E run of both schemes.

## 7. Evaluation set

`SeguePersonalModules/Eval/` (audio not committed if copyrighted; manifest + local paths):

- 10 self-recorded takes (voice + guitar, voice + keys) with hand-made ground-truth ChordPro, plus 10 commercial tracks with reference charts. **At least 4 self-recorded and 4 commercial items are Hindi songs**, with ground truth in casual romanization.
  - Hindi lyrics WER is computed after mapping both sides through phase 0's `RomanNormalizer`, so spelling variants of the same word are not counted as errors; reported separately from English.
- Metrics and v1 targets. **Decided: the accuracy targets are a hard gate.** 5b (chords) and 5c (alignment/review) do not ship as enabled features until the lyrics WER and chord accuracy targets pass on the self-recording set; below target they stay behind an "experimental" toggle while the spike continues. The time-saved measure is tracked and reported but does not gate.
  - Lyrics WER: <= 25% on self-recordings, <= 35% on commercial mixes (benchmarks: ~20-36% for Whisper on sung vocals).
  - Chord accuracy (WCSR, majmin) >= 70% self-recordings, >= 60% commercial.
  - Tempo within +-2 BPM (or octave-equivalent) on >= 90%.
  - Section boundary hit within 3 s on >= 70%.
  - End-to-end (tracked, not gating): time to a corrected, gig-usable chart is at least 40% faster than paste + manual chord entry (timed by the user on 5 songs).
- Eval runs as a CLI target, outputs a per-song breakdown and a summary table; results recorded with model versions.

## 8. Test strategy

Integration-first; unit tests only for tricky pure logic.

- **Pipeline integration tests (primary):** short committed fixture clips (self-recorded, licence-free) run through the real pipeline with real downloaded models (cached in CI/dev): assert a draft is produced with lyrics, tempo within tolerance, sections, chords, and that it opens in the real editor. Slow suite, run on demand and before each sub-milestone closes.
- **Registry integration:** launch Personal and AppStore builds, assert which entry points exist (XCUITest).
- **Absence checks** (section 3) run as tests against real AppStore archives.
- **LRCLIB / URL import:** integration tests against recorded HTTP fixtures of real pages (UG, E-Chords, Chordie, a generic blog) through the real extractors and converter; one opt-in live-network smoke test.
- **Unit tests (narrow):** chord-to-word alignment edge cases, beat snapping, and a `HindiRomanizer` table (Devanagari word -> expected casual romanization) of a few hundred common lyric words.
- **Eval** (section 7) is separate from tests; it gates shipping, not CI.

## 9. Acceptance criteria

- Personal build: drop or record a 4-minute take, get a draft with lyrics, sections, tempo, chords and key in under ~4 minutes, editable in the normal editor.
- LRCLIB search and URL import produce drafts that go through the same review flow.
- App Store build: archive succeeds, all four absence checks pass, no UI entry points for these features, no mic entitlement.
- Nothing in this package runs or downloads during live mode; app works fully offline with models already downloaded.
- All model artifacts listed with licence in an in-app "Personal modules" licences screen.
- Hindi takes produce lyrics in casual Latin-script romanization, never Devanagari or an English translation.
- 5b/5c enabled only once eval targets pass (otherwise behind the experimental toggle).

## 10. Research spikes (before or at start of phase)

1. All-In-One -> Core ML/MLX conversion feasibility and speed.
2. Chord model choice: BTC conversion vs Chordino C++ embedding; accuracy on own recordings.
3. WhisperKit vs SpeechAnalyzer on sung vocals, with and without Demucs.
4. HTDemucs Core ML (`schism-audio/htdemucs-coreml`) vs MLX port speed/memory.
5. Train our own licence-clean chord model (permissive data and architecture) - runs if the chord accuracy gate is missed, and is also the App Store path; chord detection stays behind the experimental toggle meanwhile.
6. LRCLIB API terms and rate limits re-check; synced-lyrics usefulness for alignment.
7. Page structures of UG, E-Chords and Chordie (UG embeds chart JSON in page data - verify), and Share extension behaviour on macOS 26.
8. **Hindi ASR:** WhisperKit vs SpeechAnalyzer on Hindi singing - documented Hindi support, whether output is Devanagari, romanized or translated, and WER on the Hindi eval items. Decides the per-language engine default.
9. **Licence-clean transliteration:** survey Devanagari -> casual romanization approaches and their licences (rule-based libraries, Apple's `StringTransform`/ICU transliteration and how far its output is from casual style, permissively licensed word lists for the override dictionary) and pick the base for `HindiRomanizer`.

## Resolved decisions

See `docs/decisions.md`.

1. **Package location: folder in this repo** (`Packages/SeguePersonalModules`) - absence is enforced by the section 3 checks, not by repo separation.
2. **Default lyrics engine: picked by eval** on the user's recordings - both engines implemented behind one interface.
3. **In-app recording ships in 5a** - mic entitlement in the Personal scheme only.
4. **URL import sites: Ultimate Guitar, E-Chords/Chordie, plus generic page extraction.**
5. **Accuracy targets gate** 5b/5c (WER <= 25%, chords >= 70% on self-recordings); time saved is tracked only.
6. **Source audio is not retained** after drafting.
7. **Chord model below the 70% target:** chord detection stays usable behind the experimental toggle, and a research spike (spike 5) evaluates training our own licence-clean chord model. Implication: 5b ships as experimental rather than being dropped.

## Open questions

None open.
