# P8-7 - Time model and bass fills: one `SongTimeline`, timing UI and tap capture, parts, the fill generator, the fill editor, fills on stage

Phase 8 workstream (new, 2026-10-30). Rulings: `docs/release/decisions.md` **R167** (the time model and fill creator rulings, closing `docs/research/phase8-time-model-and-fills.md` section E; cited as R167 Q1 ... Q16), **R166** (the fill creator exists, bass first, instrument-neutral model; select a run with click then shift-click, "Create Bass Fill...", 3-5 fills to audition and A/B, a fretboard plus rhythm grid or a piano roll as a toggle, saved per song in the sidecar, note names or a mini tab on stage; built after P8-6a; the mini neck shows the whole chord). Earlier rulings this builds on: R113 (test budget), R118 (compound meters count dotted quarters), R146 ("Shows on" pop-up), R147-R149 (expanded passes, loop, show modes), R155 (Phase 8 before v0.5), R161 and R162 (walk-ups, audio, stage silence, play-along rules), R165 (the clash rule). Research: `docs/research/phase8-time-model-and-fills.md` ("the research", cited as [A2], [C3] etc.; the design basis), `docs/research/phase8-bass-patterns.md` ([BP]), `docs/research/phase8-audio-engine.md` ([AE]), and the fill corpus research `docs/research/phase8-fill-corpus.md` plus its `fill-corpus.json` fixture (being written by a sibling at the time of this spec; R167 Q16; section 11.4). Sibling specs: `P8-4-bass.md` (P8-4b walk-ups, `ChordBeats`, `ChordAnchors`, sidecar schema 5; amended by this spec in its section 8.14), `P8-6-audio.md` (the engine, audition, play-along; amended in its section 7), `P8-2-stage-map-and-passes.md` (played passes, `StagePasses`).

Ryan plays bass. He wants every bass feature to agree on how long each chord lasts, to fix that timing quickly (a click on a chord's length, or tapping along), to have key changes in the middle of a song count, and to write his own fills: pick a run of chords (possibly into the last chorus a step up), get four fills that differ in rhythm, hear them against the chords, tweak one on a fretboard or a piano roll, save it, and read it on stage as note names or a mini tab. None of it may make a sound during a show.

The work is six build sessions in this one doc (section 17): **P8-7a** time core (lands **before P8-6b**), **P8-7b** timing UI and tap capture, **P8-7c** parts and the generator (after the fill corpus), **P8-7d** the fill editor (after P8-6a), **P8-7e** stage and the PDF hook, **P8-7f** the closing E2E test, guide pages and Ryan's by-ear check.

## Session rules (apply to every session)

- `cat` and `ls` are aliased to eza and can hang: use `command cat` / `command ls` or the Read/Grep/Glob tools, and pass this warning to any subagent. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-". Ignore `.build/`.
- Sibling workstreams (P8-6, the fill corpus research, others) edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, and stage only your own hunks. Keep the tree compiling between steps.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget (R113): per step only targeted in-process suites (`swift test --filter <Suite>`); new UI behaviour gets in-process SegueUI tests (`Packages/SegueUI/Tests/SegueThemeTests`). Exactly **one** new XCUITest for this whole workstream, in P8-7f (section 16.4). At the end of each session ONE `make quick`, and ONE `make e2e-one` only for an existing UI test class the session changed. No `make gate`, no `make check`, no E2E retry loops, no scratch-worktree builds. Every build or test runs under `lockf -k .build/make.lock`. Write this budget into any subagent's prompt.
- Before using any Apple API not already in the codebase (a new `Canvas` gesture, `NSEvent` key handling in a sheet, an SF Symbol such as `waveform.path` or `music.note.list`), run the `apple-api-check` skill.
- Manual steps for Ryan (the by-ear fill check in P8-7f, any corpus question): prepare everything, hand the orchestrator the exact action, and wait.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency, including any answer to section 21 that is still open when a session reaches it.

## 1. Goal

**One timing system.** Every chord in a song gets a length from one pure model, `SongTimeline`, layered over the `.cho`: the song's rule (one bar per chord by default), then the chart's own marks (bar lines, beat marks, `{time}` with one chord on a line, and, new, ChordPro grids), then the user's corrections (whole beats as today, plus sub-beat lengths and pushes), with tap capture as one more way to write corrections. Mid-song `{key}`, `{time}` and `{tempo}` count from where they are written (today only the first `{key}` is read: a bug, fixed here). Walk-ups (P8-4b), play-along (P8-6b) and fills all read lengths, keys and meters from it; nothing else computes a chord's length (R167 Q1).

**Timing that is quick to fix.** The play-along bar's chord-length lane (P8-6b) gains pushes and sub-beat lengths; "Tap Timing" records chord changes while you tap, with Segue's click at `{tempo}` or with no click (the tempo derived from the taps), and shows the result for review before anything is saved (R167 Q6). The editor can insert a standard `{key}`, `{time}` or `{tempo}` at a section or line, one directive per action (R167 Q2), and shows a quiet "Looks like a key change to A" chip on a section whose chords fit another key, applied only on a click (R167 Q3).

**Bass fills.** Click a chord in the chart, shift-click a later one (the span may cross a section or a key change), choose "Create Bass Fill...": a sheet offers four fills A-D (and "More" for a fifth), one per rhythm family, ranked deterministically with a score breakdown; each plays on the P8-6a engine with loop and A/B; the chosen one is edited on a fretboard plus step grid (typed fret entry) or on a piano roll (one toggle, remembered), with one shared selection and undo, and a mini tab preview; saving stores an instrument-neutral `Part` in the sidecar (schema 6). A fill plays on every pass of its section unless "Shows on" narrows it, and wins over a walk-up pick on the same change while the pick is kept (R167 Q7, Q8). On stage a fill shows as note names after the chords it sounds over, or as a mini tab per fill, and `t` flips every fill to tab; the mini neck numbers the fill's notes. Fills never sound on the Live stage.

**In scope:** `SongTimeline` and its maps (meter, tempo, key) from positional directives; the `{key}` fix and its consumers; the grid parser; `ticks` and `push` on corrections; the chord-length lane's push and sub-beat editing; tap capture with review; the key-change chip; directive inserts; the `Part` model and sidecar schema 6; span anchoring; `Fill.candidates` with rhythm templates driven by the corpus; the fill editor (selection, candidates, audition, two views, mini tab, accessibility); fills in previews, on stage, on the mini neck and in play-along; the bass chart PDF hook; analytics; guide pages.

**Not in scope:** instruments other than bass in the UI (R167 Q10); any sound in a Live show; lyric-syllable timing, LRC or a recording; randomised fills; AI-generated fills; a per-song or named fill library shared across songs.

## 2. Prior art (summary; the full survey is the research's A1 and Part B)

- **ChordPro 6** positional `{time}` / `{tempo}` / `{key}` ("each specification is assumed to apply from where it was specified") and grids: **adopted** as the only time data in a `.cho` [A1].
- **iReal Pro / Band-in-a-Box**: chord-per-bar cells and pattern length chosen by the time available: **build informed by** (our default rule and template fitting) [A1, B].
- **Nashville Number System / JotChord**: only exceptions are marked (split, push, hold): **build informed by** (push as a per-chord flag) [A1].
- **Soundslice** tap-to-sync with implied points between taps: **build informed by** (tap capture, section 7) [A1, B].
- **Impro-Visor** note functions, **Captain Deep / Hookpad** rhythm bank separate from pitch shape, **Scaler** chord-relative phrases, **Logic Session Player** fill dials: **build informed by** (templates of function slots, chord-relative `deg`) [B].
- **Guitar Pro** keypad entry (digits = fret): **build informed by** (typed fret entry, section 12.4) [B].
- **MusicXML, Guitar Pro, ABC, LRC as storage**: **not adopted** (they demand rhythm or a melody the charts do not have) [A8].
- **Magenta MusicVAE / GrooVAE**: **not used** (not chord-conditioned, nondeterministic) [B].

## 3. Terms

- **Tick**: the timeline's unit, `Ticks.perQuarter = 480` ticks per quarter note (section 21 Q1; the research proposed 24). A whole note is 1920; an eighth 240; a sixteenth 120; an eighth triplet 160.
- **Pulse** (beat): `Metadata.pulses(ofTime:)` (`Packages/SegueCore/Sources/ChordPro/SongDocument+Derived.swift:210`), R118: 6/8 has two dotted-quarter pulses (720 ticks each). Every "beats" value in the sidecar is pulses.
- **Layer / source**: where a chord's length came from: `.rule`, `.chart` (bar lines, beat marks, `meterLine`), `.grid`, `.user`, `.tap`. A chord whose source is `.rule` is **estimated**.
- **Span**: a run of consecutive chords in played order, from a **start** chord to a **landing** chord (the last selected chord). The chords before the landing are the **departing** chords.
- **Part**: an instrument-neutral list of note events over a span (section 9). A **fill** is a bass `Part`.
- **Rhythm family**: one of a closed set (`walk`, `pickup`, `run`, `triplet`, `octave`, `push`) grouping rhythm templates (section 11).
- **Key in effect**: the `{key}` that applies at a chord: the last `{key}` written before it in source order (section 5.3).

## 4. Current code (with file:line)

- **The `{key}` bug:** `Metadata.apply` keeps the first value of `key`, `tempo` and `time` (`ChordPro/SongDocument+Derived.swift:136, 139, 140`: `key = key ?? value`). `Metadata(blocks:)` walks top-level and section directives (`:110-129`), so a second `{key}` is parsed and dropped. Consumers of the first key: `KeyContext.declared` (`Editing/DisplayOptions.swift:96`), the library index (`Library/SongFiles.swift:103-104`), `SongEssentials` (`Library/SongEssentials.swift:26-28`), ingest (`Ingest/MetadataAssembly.swift:79-81`, `Ingest/IngestPipeline.swift:75`), the metronome (`Shows/Metronome.swift:91-92`), `RenderModel` header tempo and time (`Editing/RenderModel.swift:85-86`).
- **Directives in the tree:** `Block.directive` keeps every directive verbatim in place (`ChordPro/SongDocument.swift:83-97`); `BlockPath` orders blocks and section items in source order (`Editing/Addressing.swift:8-30`); `RenderLine.path` and `RenderItem.verbatim(text:path:)` carry paths (`Editing/RenderModel.swift:232-247`). `EditOperation.setDirective(name:value:)` sets only the **first** directive of a name (`Editing/DocumentEditor.swift:36-39`); there is no positional insert.
- **Grids:** `{start_of_grid}` / `{sog}` (`ChordPro/DirectiveSyntax.swift:47-48`) are verbatim sections (`ChordPro/DirectiveLine.swift:70-77`), rendered as `.verbatim` items; `ChordBeatsTests` pins "a grid section contributes nothing".
- **Beats today:** `ChordBeats.estimate(_:time:)` per line, song-wide `{time}` (`Library/ChordBeats.swift:45-82`); sources `barLines`, `beatMarks`, `meterLine`, `unknown` (`:10-15`). `BassLine`'s walk reads it once over the sections it annotates (`Library/BassLine.swift:187`), with `BassLineContext.time` and `.tempo` from the header (`Library/BassLine+Song.swift:10-30`).
- **Timing storage (schema 5, built):** `ChordTiming { rule, chords }`, `TimingRule` (`each`, `beats 1...16`, `line 1|2|4`), `ChordBeatsOverride { anchor, beats 1...32 }`, lenient decode one by one (`Library/BassPrefs.swift:179-299`). `ChordAnchor { section, fp, chord, from }` (`:73-125`). `ChordAnchors.resolve` for picks and overrides, `ChordAnchors.anchor(at:units:sections:)` to save one (`Library/ChordAnchor.swift:27-84`), over a private `WrittenChords` of render chords only (`:95`). `ChordPosition { section, chord }` (`Editing/ChordPosition.swift:6-22`). Schema 5 is current (`Library/Sidecar.swift:22`); migrator step `4: { _ in }` (`Library/SidecarCodec.swift:48`); `PartialSidecar` (`:141`).
- **Walk-ups (built):** `WalkUp.candidates(from:to:context:)` (`MusicTheory/WalkUp.swift:202`), `WalkUpContext` (`:63`), `WalkUpWeights.standard`; `BassLine.changes` / `annotate` (`Library/BassLine.swift:75-100`), `ChordChange.shown` (`:64`); the stage hook in `SongPreparation` (`LiveLayout/SongPreparation.swift:25-31`); the approach run as a `TextRole.approach` run of the chord unit (`LiveLayout/LayoutRequest.swift:29`, `LiveLayout/SongMeasurement.swift:35-49`).
- **Passes:** `PlayedPass { index, mode, position }` (`Library/ArrangementResolver.swift:11-19`), `ArrangementResolver.fullSong(_:)` (`:94`).
- **Audio (P8-6a, in progress by a sibling as this spec is written):** the `Playback` module (`Packages/SegueCore/Sources/Playback/`: `SoundOutput.swift`, `PhraseBuilder.swift`, `PhraseCursor.swift`, `Voicing.swift`), target at `Packages/SegueCore/Package.swift:137-141` (deps `Diagrams`, `Editing`, `Library`, `MusicTheory`, `Shows`, `Support`). `BeatNote` (a note on a pulse grid, "what a generated part (a walk-up, a fill, a pattern) is written as", `SoundOutput.swift:61`) and `Phrase(beats:tempo:lengthBeats:)` (`:93`); the port `SoundOutput` (`:113`). `PhraseBuilder.audition(_:candidate:tempo:meter:voices:)` (`PhraseBuilder.swift:62`). SegueUI: `SoundPlayer.play / loop / swapAtNextWrap / stop` (`Audio/SoundPlayer.swift:52-71`), `SoundSession` (`Audio/SoundSession.swift`), the injected `ChordHearing` and `ChordUnitPlayback` (a plain click on a preview chord unit plays it; `Audio/ChordHearing.swift:11-21, 130-157`), `WalkUpAudition` (`Audio/WalkUpAudition.swift:11-23`, untracked, step 6 in progress). `PlayAlongTimeline`, `PhraseBuilder.playAlong`, the play-along bar and its timeline strip are **not built** (P8-6b).
- **Fretboard and neck:** `BassFretboard.positions / suggested / tones / walkPath` (`Diagrams/BassFretboard.swift`, P8-4 section 7.1), `BassFretboardView` (`SegueUI/Diagrams/BassFretboardView.swift`), `StageBassNeck` (`SegueUI/Live/StageBassNeck.swift`).
- **Bass view:** `BassView { notes, chordBeside, tuning, neck, fretboard, walkUps, ... }` (`Editing/InstrumentProfile.swift:129-141`).
- **Stage keys:** the default table (`Shows/InputBindings.swift:253-297`). Taken: arrows, Space, Page Up/Down, Home, `a`, `[`, `]`, `⌘K`, `/`, `r`, `q`, `x`, `s`, `c`, `⌘=`, `⌘+`, `⌘-`, `⌘0`, `⌘.`, `?`, `m`, `k`, `1`-`9`, `l`, `b`; P8-6b claims `p`. **`t` is free** and is this spec's "Fills as Tab" key.
- **Analytics:** `FeatureKey` (`Services/FeatureKey.swift:5-66`, the P8-6 keys at `:60-65`), `FeatureContext` (`Services/AnalyticsEvent.swift:216-222`), event rows up to 25 (`Segue.Bass.walkUpPicked`, `docs/release/specs/WS3-services.md:312`), `SmallBucket` (`Services/Buckets.swift:33`).
- **Ids:** `ULID` (used by `SongID`, `Library/SongRecord.swift:5-14`).
- **Key detection:** `KeyDetector.detect(_:) -> KeyDetection` with a 24-key ranking and `ambiguityMargin` (`MusicTheory/KeyDetector.swift:16-60`).
- **PDF:** the "Bass chart" option moved into the phase 4 export build (`docs/phases/4-export.md:19`); phase 4 is not built.
- **Guide:** `guide/src/content/docs/play-bass.mdx` (Shot/Steps components), `keyboard.mdx`, `edit-a-song.mdx`, `rehearse.mdx`.

## 5. The time core: `SongTimeline` (P8-7a; SegueCore `Library`, pure)

### 5.1 Where it lives (a deviation from the research)

The research proposed a new `Timing` module [C1]. It lives in **`Library`** instead (`Packages/SegueCore/Sources/Library/Timing/` as files of the `Library` target): it needs `ChordAnchors` and `BassPrefs` (Library), and `BassLine` (Library) must read it, so a `Timing` module above Library would make a cycle. Meter arithmetic uses `Metadata.pulses` and `Metadata.parseTime` (ChordPro), never `MetronomeMeter` (Shows, which Library may not import). `Playback` already depends on `Library`.

### 5.2 Types

```swift
public enum Ticks { public static let perQuarter = 480 }

public struct Meter: Sendable, Hashable {
    public var beats: Int, noteValue: Int          // from {time}; 4/4 when absent
    public var pulses: Int                         // Metadata.pulses (R118)
    public var ticksPerPulse: Int                  // compound: 3 x (1920 / noteValue), else 1920 / noteValue
    public var ticksPerBar: Int                    // pulses x ticksPerPulse
}

/// A value that applies from a chord onward (source order), with the initial value first.
public struct PositionalMap<Value: Sendable & Hashable>: Sendable, Hashable {
    public var initial: Value
    public var changes: [(from: ChordPosition, value: Value)]   // sorted by position
    public func value(at position: ChordPosition) -> Value
}
public typealias MeterMap = PositionalMap<Meter>
public typealias TempoMap = PositionalMap<Double?>        // BPM in pulses per minute; nil = no {tempo}
public typealias KeyMap = PositionalMap<SongKey?>         // written keys (shape key under a capo)

public enum TimingSource: String, Sendable, Hashable { case rule, chart, grid, user, tap }
public enum Push: String, Sendable, Hashable, Codable { case eighth = "8", sixteenth = "16" }

public struct TimedChord: Sendable, Hashable {
    public var position: ChordPosition   // written section + ordinal (grid chords included, 5.5)
    public var pass: Int                 // index into the played order (0 for written order)
    public var occurrence: Int           // 1-based: which play of this section index this is
    public var token: String             // the chord as written ("G/B", "N.C.")
    public var onset: Int                // ticks from the timeline start (after any push)
    public var length: Int               // ticks
    public var push: Push?
    public var source: TimingSource
    public var meter: Meter, tempo: Double?, key: SongKey?   // in effect here
    public var isSilent: Bool            // N.C.
}

public struct SongTimeline: Sendable, Hashable {
    public var meters: MeterMap, tempos: TempoMap, keys: KeyMap
    public var chords: [TimedChord]      // in played order
    public var totalTicks: Int
    public var unmatched: [ChordBeatsOverride]          // corrections that no longer match

    public static func build(document: SongDocument, sections: [RenderSection],
                             units: [SongSectionUnit], timing: ChordTiming,
                             order: [PlayedPass]?) -> SongTimeline
    public func length(of position: ChordPosition) -> (ticks: Int, source: TimingSource)?
    public func barBeat(at tick: Int) -> BarBeat              // bar 1-based, beat 1-based, sub-beat ticks
    public func chord(atTick tick: Int) -> Int?              // index into `chords`
    public func lineOnset(_ line: BlockPath, pass: Int) -> Int?   // the line's first chord onset
    public func slice(passes: Range<Int>) -> SongTimeline    // what play-along plays (5.7)
}
```

`sections` is the song's own `RenderModel.sections` (written order) and `units` is `SongSections.units(of:)` (default options, as anchors already use). `order == nil` is the written song with `{chorus}` stubs written out (the editor and library); on the Rehearsal stage it is P8-2's played passes (a Skip pass is absent; Chords-only and First-line-only passes play their full chords, P8-6 section 7.2).

### 5.3 Positional directives and the `{key}` fix

- `PositionalDirectives.scan(_ document: SongDocument, sections:) -> (meters, tempos, keys)`: every `{time}`, `{tempo}` and `{key}` directive in source order (top-level and inside sections), each applying from the **first chord whose line path is after the directive's path** (a directive between two sections applies to the next section's first chord; one inside a section before a line, to that line's first chord). The initial value is the first directive of each name that comes before any chord, else the first one in the song (so a song that writes `{key}` after an intro keeps today's behaviour); a value that does not parse is skipped (the existing `valueProblem` diagnostics already flag it).
- **The fix:** `Metadata.key`, `.tempo` and `.time` keep meaning "the song's key / tempo / time" (the first one): the library index, filters, essentials, ingest and the header keep working unchanged. Every **musical** consumer reads the map instead:
  - walk-up context (`BassLine`: `WalkUpContext.key`, the passing scale and spelling use the key in effect at chord A, transposed to concert pitch);
  - fills (generator, spelling, the editor's tinted rows);
  - the stage scale line and the sounding key in the stage header follow the current pass's key (P8-2's `currentPass`, its first chord);
  - Nashville numbers re-key from a key change on (the NNS convention: numbers restart in the new key);
  - transposed chord spelling uses the key in effect (`KeySpelling` per line instead of per song);
  - play-along tempo and bar lengths, and P8-6b's click.
  These consumer choices are section 21 Q2; the stage metronome without play-along is Q3.
- `ChordBeats.estimate` reads the meter per line from the map (`estimate(_ sections:, meters: MeterMap)`; the old `time:` overload stays as a wrapper for tests until P8-7a removes it).

### 5.4 Layers (R167 Q1; highest wins, each fills only what it knows)

1. **Rule** (`bass.timing.rule`, absent = one bar per chord): exactly P8-6 section 7.1 layer 3, measured in the meter in effect.
2. **Chart marks**: `ChordBeats` (bar lines, beat marks, `meterLine`) and grid chords (5.5). `meterLine` reads the meter in effect at that line.
3. **User corrections** (`bass.timing.chords`, resolved by `ChordAnchors.resolve`): `beats` (exists) or the new `ticks` (sub-beat length), plus the new optional `push`. A correction with `source: "tap"` is drawn differently in the lane but resolves the same.
4. **Tap capture** is not a store: it writes layer 3 (section 7).

Then (P8-6 section 7.1 rules, unchanged): a chordless lyric line extends the chord before it (one bar under `each`/`beats`, `n` bars under `line n`, R162 Q2); `N.C.` is a timed silence; unknown chords get no length and are skipped; every chord is at least a sixteenth and at most 32 pulses; onsets are cumulative. **Push:** the chord's onset moves earlier by an eighth or sixteenth and the chord before it loses that much (the bar grid does not move); a push on the first chord of the timeline is ignored.

### 5.5 Grids (R167 Q4)

`GridParser.parse(_ section: RenderSection, header: String?, meter: Meter) -> GridChart` (pure, `Library/Timing/GridParser.swift`), for a verbatim section whose kind is `grid` (`DirectiveLine.isVerbatimSection`). From the ChordPro grid spec [A1]: the optional `shape` (`"L+MxB+R"`: margin cells, measures x cells per measure, margin; the legacy `{start_of_grid: 1+4x2+4}` form too) gives cells per bar, else each bar's cells are its tokens; bars `|` `||` `|.` `|:` `:|` `:|:`; `.` an empty cell (the chord before continues), `/` a cell where the chord is struck again, `~` several chords sharing one cell evenly, `%` / `%%` repeat one / two measures, voltas `|1` `:|2`; margin text and strum lines (`|S`) are ignored; chord names are bare tokens parsed with `ChordToken(parsing:)` (an unparsed token is text). Repeats and voltas expand into bars **before** layering. Each grid chord's `ChordPosition` is (the grid section's index, its ordinal among the grid's chords in written, unexpanded order), so corrections and fill anchors address grid chords exactly like lyric chords. `WrittenChords` (`Library/ChordAnchor.swift:95`) includes grid chords so `ChordAnchors.resolve` and `anchor(at:)` cover them. A grid section's fingerprint is `SongSections.fingerprint` as today (check that verbatim lines count; if not, stop and ask).

Grid chords are timed, play in play-along and can be part of a fill span; no walk-up run is drawn inside a grid (its text is verbatim), and `BassLine`'s chain passes through a grid as it does today.

### 5.6 Storage: optional fields, still schema 5

`ChordBeatsOverride` gains `ticks: Int?` (1 ... 32 pulses' worth of ticks; when present it wins over `beats`, and `beats` is written as the rounded value so a reader that only knows `beats` still gets a sensible length), `push: Push?` and `source: String?` (`"tap"` or absent). `ChordTiming` gains `dismissedKeys: [KeyChangeDismissal]` (section 6.2). All lenient (a bad `ticks` or `push` drops that field, not the override). **No schema bump:** no build that reads schema 5 has shipped, and P8-7a lands before P8-6b, so no build writes `bass.timing` without these fields (the research's A2/Q5 reasoning). On disk:

```json
"timing": {
  "rule": {"each": "bar"},
  "chords": [
    {"section": "Chorus", "occurrence": 1, "fp": "9f8e7d6c", "chord": 0, "from": "C", "beats": 2},
    {"section": "Verse", "occurrence": 1, "fp": "1a2b3c4d", "chord": 2, "from": "D",
     "beats": 3, "ticks": 1200, "push": "8", "source": "tap"}
  ],
  "dismissedKeys": [{"section": "Chorus", "occurrence": 3, "fp": "5e6f7a8b", "key": "A"}]
}
```

### 5.7 What consumes it

| Consumer | Before | After (P8-7a unless noted) |
|---|---|---|
| P8-4b walk-ups | `ChordBeats.estimate` in `BassLine.Walk` (`BassLine.swift:187`) | `BassLineContext.timeline: SongTimeline`; `beats` = the chord's length in pulses when its source is not `.rule`, else unknown (so the two-note cap on estimated chords is unchanged, R161); `key` = the key in effect at chord A |
| P8-6b play-along | `PlayAlongTimeline.build(sections:origins:range:estimates:timing:meter:changes:)` (P8-6 7.5, unbuilt) | `PlayAlongTimeline` is `SongTimeline.slice(passes:)` plus voices (P8-6 section 7, amended); its tempo and bar lengths follow the maps |
| P8-6b lane | edits `beats` | same lane; P8-7b adds push, ticks and tap |
| Fills (P8-7c) | n/a | event ticks are relative to `TimedChord.onset`; seconds via the tempo map |
| Stage | walk-up text | fill names / tab at their span, bar and beat from the timeline (P8-7e) |

**Rule for every spec and session:** no feature computes a chord's length, key or meter except through `SongTimeline` (R167 Q1). `ChordBeats` becomes layer 2's implementation detail.

### 5.8 Performance

`SongTimeline.build` runs on every preview render where a bass feature or play-along is on: one pass over the chords, no allocation per tick. Budget: under 2 ms for the longest corpus song (`live-very-long.cho`) in a `@Test` that measures 100 builds (not in `SLOW_TESTS`); the stage builds it once per song preparation, never per frame.

## 6. Key changes in the chart (P8-7a core, P8-7b UI)

### 6.1 Explicit directive insert (R167 Q2)

- New `EditOperation.insertDirective(name: String, value: String, before: BlockPath)` (`Editing/DocumentEditor.swift`), accepting only `key`, `time`, `tempo`: inserts one canonical line (`{key: A}`) as its own line immediately before the block at `before` (a section header: top-level, before it; a lyric line inside a section: as a section item before it). Nothing else in the file changes (byte-minimal, like the other operations); undo is the editor's existing undo. The value is validated with `Metadata.valueProblem` before insert.
- **Editor UI** (text mode and visual mode; the editor only, never the library or stage): the section band's context menu and the line context menu in the preview gain **"Insert Key Change Here..."**, **"Insert Time Change Here..."**, **"Insert Tempo Change Here..."**: a small popover with a key picker (the 24 keys, defaulting to the chip's suggestion or the key in effect), a time field (`3/4`, validated) or a BPM field. One action inserts one directive. Song > Insert gains the same three items for the line at the cursor (text mode) or the selected band (visual mode). The written key is the **shape key** under a capo, as `{key}` always is (`DisplayOptions.swift:52-55`); the popover says "Written key (capo 2: sounds B)" when a capo is set.
- A setlist slot key override applies to the whole song as today: a mid-song `{key}` moves with it (concert = written + capo + transpose).

### 6.2 The "Looks like a key change" chip (R167 Q3)

- `KeyChangeDetector.suggestions(timeline:sections:units:dismissed:) -> [KeyChangeSuggestion]` (pure, `Library/Timing/KeyChangeDetector.swift`): for each written section with at least 4 chord occurrences, run `KeyDetector.detect` on that section's chords alone. Suggest key K' for the section when all hold: K' is not the key in effect K and not its relative major/minor; the detection is not ambiguous; K' scores at least 25% higher than K on the section's chords (`KeyChangeDetector.margin = 0.25`, tuned in the tests against the fixtures below); the previous section's detection is not K' (the change happens here, not earlier); no `{key}` is written at this section; no dismissal matches (anchor + `fp` + K').
- **Where:** the editor only (text-mode preview and visual canvas section band), for anyone (key changes matter to every chart, not only bass). A quiet capsule at the right of the section's header: "Looks like a key change to A" with two buttons: **"Insert {key: A}"** (writes 6.1's directive before the section header; undoable) and **"x"** (dismisses: writes `timing.dismissedKeys` through `LibraryStore.updateBassPrefs`, sidecar only; undoable in the editor). Never applied without a click.
- Fixtures (`KeyChangeDetectorTests`): a G song whose last chorus is A B C#m D (lift to A) suggests A on that chorus only; a half-step lift G -> Ab; a Bollywood song in Am with a C major bridge (relative: no chip); a 3-chord section (no chip); a chorus that borrows one bVII (no chip); a section with `{key}` already written (no chip); a dismissed suggestion (no chip); the change suggested only at the first section of the new key.

## 7. Tap capture (P8-7b; R167 Q6)

**Where:** the P8-6b play-along bar in the editor and library (never the stage): a **"Tap Timing"** button (`segue.playAlong.tap`) beside the lane, for the bar's current range.

**Modes** (a segmented control in the tap panel, remembered in `AudioSettings`):
- **With the click** (default): one bar of count-in, then Segue's click at the song's `{tempo}` in effect (or the session tempo; 90 with the existing hint when none), chords and bass muted by default (toggles stay available). Each tap is quantised to the nearest pulse of the click grid (to the nearest eighth while ⌥ is held at the tap, or with "Half beats" ticked in the panel).
- **No click**: no sound; the first tap starts the first chord. The tempo is derived when tapping stops (`TapQuantiser.tempo(intervals:hint:)`): a deterministic search over 40 ... 240 BPM in 0.5 steps minimising the summed error of every inter-tap interval to a whole number of pulses (half pulses with "Half beats"), preferring, within 2% error, the song's `{tempo}`, then lengths that sum to whole bars; ties go to the slower tempo. The review shows it ("Tempo from your taps: 96 BPM", with -/+ that re-quantises).

**Keys while tapping:** Space or Page Down (a pedal) = "the next chord starts now"; Tab = "skip": the next chord keeps its lower-layer length (Soundslice's implied points); Esc = stop. The panel shows the chord being waited for ("Next: C, chord 3 of 12") and a running tap count. VoiceOver: the same text as the value of the panel, read on focus, plus an announcement per tap only when "Announce taps" is on (off by default).

**Review before save:** stopping (Esc, the end of the range, or the Stop button) never writes anything. The lane switches to review: each changed block shows its new length with the old one ghosted under it ("C 4 -> 3 beats"), unchanged blocks plain, skipped blocks marked. Buttons: **Keep** (writes every changed chord as a correction with `source: "tap"`, in one `updateBassPrefs` write and one undo step), **Discard**, and, in no-click mode when the song has no `{tempo}` or a different one, **"Set song tempo to 96"** (an explicit `setDirective(name: "tempo")` write, R167 Q2; never automatic; P8-6's "never written from the play-along tempo control" stays true for that control). Lengths are clamped to a sixteenth ... 32 pulses; a tap that would give a chord zero length is dropped and that chord is marked skipped.

`TapQuantiser` (pure, `Library/Timing/TapQuantiser.swift`) takes tap times from the injected `Clock`, the range's timeline and the mode, and returns proposed corrections plus the tempo; tested with scripted clocks.

## 8. The chord-length lane (P8-6b builds it, P8-7b extends it)

P8-6b builds the lane exactly as P8-6 section 7.4 says (one block per chord, width by length, edge style by source, select, Beats stepper, digits, drag the right edge, Delete, the Timing menu), reading `SongTimeline`. P8-7b adds, in the same component (`Editor/TimelineStrip.swift`, renamed in the UI to the "chord-length lane"):

- **Sub-beat lengths:** ⌥-drag snaps the right edge to eighths (sixteenths with ⌥⇧); typing "2.5" or "2½" in the Beats field sets 2.5 pulses. Stored as `ticks`.
- **Push:** with a block selected, `<` cycles none / eighth / sixteenth early (and a "Push" menu item); drawn as a small notch on the block's left edge with the block starting that much early; accessibility value "pushed an eighth early".
- **Edge styles:** solid (chart or grid), dashed (the song's rule: estimated), a small filled dot (your correction), a small filled dot with a tick (tapped).
- **Markers:** a key-change marker ("Key: A") and a time or tempo change marker ("3/4", "♩ 120") above the block where each map changes.
- **Selection for fills:** shift-click in the lane extends a span selection (section 12.1), so grid chords and `{chorus}` stub chords (which have no clickable unit in the preview) can start or end a fill.
- The same component, read-only for the rule menu, is the fill editor's top lane (12.2), where lengths stay editable.

## 9. Parts (P8-7c; SegueCore `Library`, pure; R167 Q7-Q10)

### 9.1 Types

```swift
public struct PartID: Sendable, Hashable, Codable { public var ulid: ULID }

public enum InstrumentRef: String, Sendable, Hashable, Codable { case bass }   // .guitar, .keys later (R167 Q10)

public struct SpanAnchor: Sendable, Hashable {
    public var start: ChordAnchor            // the first departing chord
    public var end: ChordAnchor              // the landing chord
    public var spanBass: [String]            // written bass of every chord start ... landing, in order
}

public enum PassFilter: Sendable, Hashable { case all, only(Set<Int>), last }   // "Shows on" (R146)
public enum PartShow: String, Sendable, Hashable, Codable { case names, tab }
public enum Articulation: String, Sendable, Hashable, Codable, CaseIterable {
    case slide, hammer, pull, ghost, staccato, accent                           // closed vocabulary
}

public struct PartEvent: Sendable, Hashable {
    public var chord: Int                    // index into the span, 0 ... count-1 (the landing allowed)
    public var at: Int, len: Int             // ticks from that chord's onset; len >= 1
    public var deg: Int                      // 0 ... 11 semitones above that chord's written bass
    public var oct: Int                      // -2 ... 2 octaves from the chord's placed bass note
    public var velocity: UInt8?              // nil = 96
    public var articulations: Set<Articulation>
    public var string: String?               // optional pin: the open string's pitch, "A1"
}

public struct PartOrigin: Sendable, Hashable, Codable {   // provenance, for analytics and "Revert"
    public var family: FillFamily, template: String, rank: CandidateRank, edited: Bool
}

public struct Part: Sendable, Hashable, Identifiable {
    public var id: PartID
    public var instrument: InstrumentRef
    public var name: String?
    public var span: SpanAnchor
    public var passes: PassFilter
    public var show: PartShow
    public var origin: PartOrigin?           // nil = written from scratch
    public var events: [PartEvent]
}
```

### 9.2 Pitch: chord-relative with an optional string pin (R167 Q9)

- An event's pitch is `Voicing.bassNote(of: concertChord, placement:) + deg + 12 x oct`: relative to the bass note the play-along bass voice plays for that chord (`Playback/Voicing.swift:96`), so a fill agrees with the roots around it, and transpose, capo, capo mode and slot key overrides keep it correct (the same reason walk-up picks store `offsets`, P8-4 8.10). The canonical form (`deg` 0 ... 11) makes every pitch have exactly one encoding.
- **Range:** a resolved pitch outside the tuning's range (lowest open string ... highest open string + 20 frets) is folded by octaves into it, and the editor marks that note "moved an octave".
- **Spelling:** in the key in effect at that chord, with chord tones taking the chord's spelling (R161's passing-scale rule, `passScale(chord, localKey)`), else sharp ascending / flat descending from the previous note (the walk-up rule, P8-4 8.3).
- **Pin:** `string` names an open string by pitch ("A1"); with the current tuning, if a string has that open pitch and the note sits on frets 0 ... 24 there, the tab and the neck use it; otherwise (a 4-string profile and a pin on B0, or a fret out of range) the pin is ignored and `BassFretboard.suggested` decides. Pins never change pitch.

### 9.3 Anchoring and when a fill applies

- `PartAnchors.resolve(_ parts:, timeline:, units:, sections:) -> ResolvedParts { applied: [AppliedPart], unmatched: [Part] }` (pure, `Library/PartAnchor.swift`) reuses `ChordAnchors` for `start` and `end` (re-anchoring rules of P8-4 8.11), then checks the span: in written order, the chords from start to end must be consecutive (across sections, through `{chorus}` stubs written out and grid chords) and their written basses must equal `spanBass` by pitch class. Otherwise the part is **unmatched**: kept in the sidecar, listed with Remove (the Walk-ups list footer gains a "Fills" group, and the fill editor's open menu), never applied, never deleted on load. Re-anchored positions are written back only with the next parts write.
- **In a played order** (a slot arrangement, the Rehearsal stage), the fill applies in a pass when that pass plays the start chord and the landing chord follows in the next played chords exactly as written (an arrangement that plays the bridge next instead of the chorus does not get a fill written into the chorus), and the pass passes the filter: `.all` every pass of the start chord's section index; `.only(n)` the n-th play of that section index (1-based, P8-2's "Chorus 2/3" numbering); `.last` the final play of that section in the whole song: play-along counts plays over the timeline its range is cut from, so looping the first chorus alone never makes it the "last" chorus (R170; `ResolvedParts.plays(in:song:)`). The editor and library (written order) treat each `{chorus}` stub as another play of the chorus.
- **No overlap:** two parts may not cover the same chord change. Saving a fill whose span overlaps an existing one asks "Replace 'Into last chorus'?" (Replace / Cancel).
- **Fill wins over pick (R167 Q8):** on every change inside an applied fill's span (each departing chord into the next, including the change into the landing), `BassLine` shows no walk-up (`ChordChange.shown = nil`, `coveredBy: PartID`) in that pass, on charts, on stage, on the neck and in play-along. The pick stays in the sidecar and applies again wherever the fill does not (another pass, or after the fill is deleted). The walk-up popover on a covered change shows "A fill covers this change" with "Edit Fill..." and still lets you pick (the pick then shows on the passes the fill skips).
- **Timing edits move notes with their chord:** `at` is relative to the chord's onset, so lengthening chord 0 moves chord 1's events with it. An event whose `at + len` passes its chord's new length is clipped at the chord's end in playback; one whose `at` is past it is drawn with a warning mark ("outside its chord") in the editor and skipped in playback and on stage, never silently moved.

### 9.4 Resolving to notes

`Part.resolve(timeline:pass:transform:placement:) -> [ResolvedNote]` with `ResolvedNote { tick, len, midi, name, position: FretPosition?, articulations, velocity }` (absolute ticks from the timeline start, MIDI at sounding pitch, the spelled name, the fret position by pin or suggestion). Hearing, the stage, the neck and the mini tab all read this one resolver. `PhraseBuilder.fill(...)` (section 12.3) and `PhraseBuilder.playAlong` turn resolved notes into `BeatNote`s / `NoteEvent`s through the tempo map (ghost: velocity 40 and half length; staccato: half length; accent: +20 velocity; slide, hammer, pull: velocity -15, no other change).

### 9.5 Sidecar schema 6 (`parts`)

`Sidecar.currentSchemaVersion` 5 -> **6**; history line "6 = P8-7c (`parts`: per-song instrument-neutral parts, bass fills; R167)". New field `public var parts: [Part]` (default empty), always encoded. On disk:

```json
"parts": [
  {"id": "01JD7Q3W5N8K2M4R6T0V9X1Y3Z", "instrument": "bass", "name": "Into last chorus",
   "start": {"section": "Bridge", "occurrence": 1, "fp": "9f8e7d6c", "chord": 3, "from": "E"},
   "end":   {"section": "Chorus", "occurrence": 3, "fp": "1a2b3c4d", "chord": 0, "from": "A"},
   "span": ["E", "A"], "passes": "all", "show": "names",
   "origin": {"family": "pickup", "template": "pickup8", "rank": "b", "edited": true},
   "events": [
     {"chord": 0, "at": 960,  "len": 240, "deg": 0,  "oct": 0},
     {"chord": 0, "at": 1200, "len": 240, "deg": 2,  "oct": 0, "string": "A1"},
     {"chord": 0, "at": 1440, "len": 240, "deg": 4,  "oct": 0, "art": ["slide"]},
     {"chord": 1, "at": 0,    "len": 480, "deg": 0,  "oct": 0, "vel": 110}
   ]}
]
```

- `passes`: `"all"`, `"last"` or an array of 1-based plays (`[3]`). Anchor keys are exactly `ChordAnchor`'s (the `SectionAnchor` helpers).
- **Lenient decode:** `PartialSidecar` gains `parts`, decoded one part at a time; inside a part, events one by one (an event with `deg` outside 0 ... 11, `oct` outside -2 ... 2, `len < 1`, `at < 0`, `chord` outside the span, an unknown articulation or an unparsable `string` is dropped); a part with an unknown `instrument`, a bad anchor, a `span` shorter than 2 or longer than 9, or no valid events is dropped; the rest survive.
- **Migration:** step `5: { _ in }`. An older build opens a v6 sidecar read-only and never rewrites it (`SidecarCodec.swift:81-84`), as for schema 5. Dev builds only.
- Writes: `LibraryStore.updateParts(id:_:)` over `SongFiles.writingParts` (new, `Library/LibraryStore+Parts.swift`, the shape of `writingBassPrefs`): sidecar only; `.cho` bytes, mtime and index projection untouched.

### 9.6 Instrument neutrality (R167 Q10)

Nothing in `Part`, `PartEvent`, `SpanAnchor` or the resolver is bass-specific except `InstrumentRef.bass` and the placement passed in; fret positions are derived, never stored (the pin is an open-string pitch, meaningful for any fretted instrument). The UI, the generator and the sidecar accept only `.bass` in this workstream (other instruments come later).

## 10. Selection to fill: what the span may be

- 2 ... 9 chords (up to 8 departing chords plus the landing; R166 "a run of chords"). A span may cross a section boundary and a key change. It may not include `N.C.` or an unknown chord ("A fill can't cross N.C.").
- Its departing length (start onset to landing onset) is at most 8 bars ("A fill covers at most 8 bars").
- A span whose chord lengths are estimated (source `.rule`) is allowed; the generator and editor show "Chord lengths are estimated - set them in the lane above" (the lane is right there, 12.2).

## 11. The generator: `Fill.candidates` (P8-7c; `MusicTheory/Fill.swift` + `Library/FillSpan.swift`, pure)

### 11.1 API

```swift
public enum FillFamily: String, Sendable, Hashable, Codable, CaseIterable {
    case walk, pickup, run, triplet, octave, push            // closed (section 11.3)
}
public enum CandidateRank: String, Sendable, Hashable, Codable { case a, b, c, d, more, scratch }
public enum FillTerm: String, Sendable, Hashable, CaseIterable {
    case templatePrior, strongBeatTone, clash, resolution, density, contour, range,
         keyChange, downbeat, walkUpAgreement
}

public struct FillSpanChord: Sendable, Hashable {
    public var chord: ChordSymbol            // concert
    public var bass: PitchClass              // concert slash bass, else root
    public var length: Int                   // ticks
    public var source: TimingSource
    public var key: SongKey?                 // concert key in effect
    public var meter: Meter
}
public struct FillContext: Sendable, Hashable {
    public var span: [FillSpanChord]         // departing chords then the landing
    public var genre: BassGenre?             // the song's feel, else the profile's (R161)
    public var tempo: Double?
    public var tuning: Tuning, home: Int     // range and placement
    public var intoSection: Bool, energyUp: Bool?   // P8-4 8.4 facts for the landing
    public var mode: FillMode?               // the song's scale (11.7, R170)
}
public struct FillCandidate: Sendable, Hashable {
    public var family: FillFamily
    public var template: String              // a FillTemplates id
    public var events: [PartEvent]
    public var score: Double
    public var breakdown: [FillTerm: Double] // sums to `score`
    public var corpus: [String]              // the corpus pattern ids the template came from
}
public enum Fill {
    /// Up to 5 candidates, one per corpus pattern family (R170), best first; `[]` when nothing fits.
    public static func candidates(_ context: FillContext) -> [FillCandidate]
}
public struct FillWeights: Sendable, Hashable { public static let standard: Self ... }
public struct FillTemplates: Sendable, Hashable { public static let standard: Self ... }
```

`FillSpan.context(for span:, timeline:, transform:, prefs:, profile:)` (Library) builds `FillContext` from the timeline, so the generator never reads the `.cho`.

### 11.2 How it extends `WalkUp.candidates` (R166)

- A **template** is a rhythm (onsets and lengths in ticks, measured back from the landing onset, e.g. `pickup8` = eighths on "3& 4 4&" of the last departing bar) whose slots carry **functions** (Impro-Visor style [C3]): `R` root of the chord sounding, `C` a chord tone, `S` passing-scale tone (`passScale(chord, localKey)`, R161), `A` approach into the next chord, `O` octave, `P` pivot (a tone common to the two keys nearest the previous note), `D` dominant of the next chord's key. Templates are fitted to the time available (the last 1, 2, 4 or 8 pulses of the departing chords, never more than the departing length; a `walk` template may cover every departing chord, one note per pulse).
- **The final approach slots reuse `WalkUp.candidates(from: lastBass, to: landingBass, context:)`** with `context.beats` = the slots left, so single-change knowledge is not duplicated: the `A` slots of every template are filled from the walk-up candidates in their rank order (the first that fits the slot count and does not clash). A span of two chords with a `walk` template is therefore a walk-up written as a fill.
- **Across a key change** (the landing's key differs from the last departing chord's key): the generator also tries, per template, `D` (the 5 of the new key or landing chord just before it), `P` (a common tone, then a step into the new root), a chromatic approach from a half step below or above the new root, and, when the departing chord is the new key's V, a run in the new key's scale. These are the research's key-change moves [Part B, fill pedagogy]; the `keyChange` term rewards them only when the key actually changes.
- Pitch placement: each note in the octave nearest the previous one within the tuning's range (B0 on 5 strings), starting from the departing chord's placed bass note; then encoded as `deg` / `oct` (9.2).

### 11.3 Families, templates and the corpus

- **Families** (closed; widening it is a spec change, asked of the orchestrator): `walk` (one note per pulse, a walking line), `pickup` (eighth pickups into the landing), `run` (sixteenth runs), `triplet` (eighth or quarter triplets), `octave` (root, fifth and octave pops), `push` (anticipations: the landing note pushed to "4&", dotted pushes, rest-then-approach).
- **Templates** live in Swift as `FillTemplates.standard` (`MusicTheory/FillTemplates.swift`; compiled data, no runtime resource), about 15, each `{ id, family, pulses needed, slots: [(at, len, function)], feels it suits, corpus: [pattern id] }`. The provisional set from the research (`pickup8`, `quarterWalk`, `sixteenRun`, `tripletRun`, `octavePops`, `rootFiveOctave`, `anticipation`, `dottedPush`, `restPickup`, `halfTimeHold`) is **replaced by what the corpus supports** in P8-7c step 2 (R167 Q16): every template must cite at least one corpus pattern; a template the corpus does not support is dropped; a frequent corpus pattern with no template gets one. The `templatePrior` term per (template, feel) is the corpus frequency of that template's patterns for that feel (smoothed: `log(1 + count)` scaled to 0 ... 3, the walk-up prior's range), recorded in a comment with the corpus revision it came from.
- **Hard constraints** (a candidate breaking one is never generated): monophonic; every note inside the departing span (no note crosses the landing onset, except a `push` landing note on "4&" that sustains into it and replaces the landing's first root); in range; no chromatic note on a strong beat (beat 1 and the bar's middle pulse in 4/4; each pulse in compound meters) except the final approach note; no note cross-relating with the sounding chord's third (the P8-4 8.3 rule); every bar of the fill region that starts inside it begins with a note unless the template is `restPickup`.
- **Ranking:** score = the sum of weighted terms, every term in `breakdown`: `templatePrior` (corpus, per feel), `strongBeatTone` (+1 per strong beat on R/C), `clash` (-5 per R165 cross-relation with the sounding chord), `resolution` (last note a half step from the landing bass +2, a whole step +1, its fifth +1), `density` (fit of notes per pulse to tempo and feel: fewer above 140 BPM and for Worship, more for Rock; table in `FillWeights`), `contour` (-0.5 per leap over a fifth), `range` (-1 per note folded by an octave), `keyChange` (+2 for a D or chromatic-into-new-root ending when the key changes), `downbeat` (the NeuralAcid rule: -1 per fill bar without a note on its first pulse), `walkUpAgreement` (+1 when the approach equals the walk-up candidate the chart would show for that change).
- **Situation** (R170): one more term, `situation`, from each template's **traits** (`FillTrait`: `approach`, `chordScale`, `arpeggio`, `accent`, `cadence`) and the span: over a repeated chord (a vamp) chord-scale material +2 and accents +1, an approach shape -2; an arpeggio over a dominant seventh +3; into a new section an accent +1.5 (same key only: into a new key the key is the event) and a tihai's cadence +4; the mode's colour +2 (both notes of the augmented second of harmonic minor b6-7 or Bhairav b2-3, or a run of three or more pentatonic notes under a pentatonic scale); per fill note above two, -1 in Worship or a slow song and -1 into a new key not prepared by V'; the walk through a pivot (the last departing chord already in the new key) +2. `templatePrior` is smoothed toward all feels (`priorSmoothing` 0.5: a feel's count plus half the family's all-feel count over the five feels) and scaled to 0 ... 4. Tuned against the corpus (11.4) by changing numbers only: `resolution` half step +1, whole step +0.5, fifth +1; `walkUpAgreement` +2; `contour` -0.25; the rest as above. The hold candidate keeps its `restraint` term.
- **Diversity** (R170): the best candidate of each **corpus pattern family** (a template's `corpusFamily`, about 20), not each rhythm family, plus the hold candidate; ordered by score; ties by hold first, then `FillFamily` declaration order, then template order, then lower first-note pitch. A-D are the first four; **"More" shows the fifth** (R167 Q11); a sixth pattern's best is not shown. Templates sharing a corpus family compete for its place (the pentatonic bar figure and the sixteenth pentatonic run; the stop with a pickup and the break-stop). Fewer than four fit a short span: show what fits. `FillFamily` stays as the part's provenance (`PartOrigin.family`) and the editor's row name.
- **Templates as built** (R170, each citing its corpus rows): `quarterWalk` (the walk-up as a walk) and, on a prepared lift, `dominantArpeggio` (5 then 3 of V'); `pickup8` (two eighths arriving from a half step below: the walk-up that ends on T-1, else the octave then T-1; every corpus row ends on T-1); `chromaticLine` (the departing root, then half steps into the landing: from a root within a major third it covers the distance, B C into C#, else the root and the last three, A B C C# into D); `approachNote` (T-1 on the last pulse, the root re-struck on the last bar line of a chord longer than a bar); `slideInto` (a slide from the departing root when it sits within a whole step of the landing, its octave on a repeated chord, else from the approach note); `dominantApproach` (the landing's fifth); `dominantPedal` (repeated V', prepared lifts); `scaleRun` (four eighths of the passing scale, the shorter way into the landing); `sixteenRun` and its seven-note off-beat form; `pentatonicBar` (a bar up the pentatonic to the octave and back, overhanging onto the root) and `pentatonicRun` (octave then three sixteenths down; over a minor chord in Rock or Pop the blues scale, with b5); `tihai` (Bollywood only); `tripletRun`; `rootFiveOctave`; `octavePops`; `chordArpeggio` (R 3 5 7 9 7 5 3, topped with the ninth); `machineGun`; `anticipation` (only over a change: over a repeated chord it anticipates nothing); `restPickup`; `stopTime` (a hit on 1, rests, one pickup; same key only) and **`breakStop`** (R170: the band hits 1 and stops, the silence holds, the landing comes with no pickup; the only stop into a new key). A walk down from a low root starts an octave up (the register that folds the fewest notes).
- **Deterministic:** same input, same output; no randomness, no clock.

### 11.4 How the corpus plugs in (R167 Q16; consumed by P8-7c)

**Pass rates (R170):** with diversity per corpus family and the situation rules, the goldens pass section 33/41 (80%, was 39%), key change 18/22 (81%, was 31%) and Bollywood 13/17 (76%, was 47%); `FillCandidateTests.floors` records them. R170 asks for 80% per category; Bollywood stops short because the four rows it misses need what the context does not carry, and hard-coding them would be overfitting: `bw-rock-n-roll-soniye` (a boogie R 3 5 6 walk where the walk plays the walk-up), `bw-chaal-pickup` (the same single staccato pickup as `bw-koi-kahe-staccato` but from the landing's fifth, not T-1; only the shuffle feel tells them apart), `bw-ballad-fifth` (a slow ballad approaching from the fifth, ranked 8th behind the T-1 approaches the chart's walk-up agrees with) and `bw-disco-octaves` (octave pops over a moving change at a fast tempo, ranked 10th). Three are `theory` rows, so a by-ear verdict in P8-7f may settle them. The section and key-change misses: `sec-tb-slide-double-stop` (a double stop: the generator is monophonic), `sec-bonedo-octave` versus `sec-baby-love-octaves` (one octave pop or R 8 R 8 in the same context; one template per family), `sec-bluegrass-walk-down` (walking down where the named G -> C row walks up the top walk-up), `sec-lead-me-to-the-cross` (a descent into a bridge where the shorter way is up), `sec-bonedo-rnb-blues` (eight notes in a slow song), `sec-livin-prayer-anticipation`, `sec-pop-octave-pickup` and `sec-rock-stop-pickup` (three of six different patterns into a rock or pop chorus, five places); `kc-i-will-always-love-you` (the break-stop ranks below the fills), `kc-street-life` (the anticipation at a +1 lift), `kc-aug6-route` and `kc-half-step-sharp5-pedal` (V' played out loses to its arpeggio and the approaches).

The corpus research (`docs/research/phase8-fill-corpus.md`, sibling, in progress) abstracts real fills (Bollywood/Hindi film songs and fills across key changes among them) into patterns of chord functions, degrees and rhythm, never copied tabs. Its machine-readable form is the fixture **`Packages/SegueCore/Tests/Fixtures/fills/fill-corpus.json`** (if the sibling writes it elsewhere, P8-7c step 1 moves it there with `git mv`). This spec expects, per pattern: `id`, `source` (a citation, no transcription), `feel`, `meter`, `tempo` band, `span` (chord functions relative to the key, e.g. `["V", "I"]` or `["V/new", "I/new"]` with the key change interval), `rhythm` (onsets and lengths in ticks at 480 PPQ, or in sixteenths), `functions` (R/C/S/A/O/P/D per note), optional `degrees`, and `family`. **The corpus document is canonical:** if its schema differs, P8-7c adapts the loader (`FillCorpus.load`, test-only) and records the mapping in a comment, never the corpus.

It plugs in three ways:
1. **Template tuning** (P8-7c step 2): `FillTemplates.standard` and the `templatePrior` table are derived from it as 11.3 says. This step **consumes** the corpus and cannot start until the corpus doc and fixture have landed (the dependency in section 17).
2. **Grounding test** `FillTemplateCorpusTests`: every template cites existing corpus ids; every corpus pattern marked as a template source maps to a template; families and functions in the corpus are inside the closed vocabularies (an unknown family or function fails the test with the pattern id, so a vocabulary change is a deliberate spec change).
3. **Golden test** `FillCandidateTests`: each corpus pattern that carries a concrete example (a key, chords and a feel) becomes a case: realised in that key, the generator's candidates must include the pattern's family and a candidate whose functions match the pattern's on its strong beats (`expectFamily`, `expectFunctions`); plus named rows (11.5). A failing golden is a tuning signal for `FillWeights` and the templates, never a reason to edit the corpus.

### 11.5 Named rows (in `FillCandidateTests`, beside the corpus goldens)

- G -> C (G, Pop, one bar each, 96 BPM): A-D are four different corpus pattern families (R170); the `walk` candidate's last two notes equal the top walk-up (`A B`); every breakdown sums to its score.
- E -> A (A): the break-stop hits E on 1 (staccato), then nothing until the landing; into a new key (E -> B with `{key: B}`) it is offered and the stop with a pickup is not (R170).
- D -> G -> Em -> C (a four-chord span, G, Pop): a `walk` candidate covers all departing chords; `pickup` sits in the last bar only.
- E -> Am (Am, Bollywood): the approach uses `F G#` first (R161 harmonic minor), never `F G`.
- Bridge E -> Chorus A with `{key: A}` before the chorus (G -> A lift): a candidate ends `E` (D) or `G#` (chromatic below) into A, with `keyChange` in its breakdown; with no key change in the same chords the term is 0.
- G -> Ab (half-step lift, truck-driver): a chromatic run into Ab ranks in the top two.
- 180 BPM, Rock: no `run` candidate (density); Worship at 66 BPM: at most 4 notes per candidate.
- 6/8 (two pulses per bar): templates align to dotted-quarter pulses; `triplet` is not offered (compound meters already triple).
- A one-pulse departing span: only families that fit; never an empty A.
- 5-string BEADG, key of D: notes may go below E1; on EADG the same fill folds up an octave and is flagged.

### 11.6 Property tests (`FillPropertyTests`, fast, pure, not in `SLOW_TESTS`)

Over generated spans (2-4 chords from all 12 roots x major and minor keys x 5 feels and nil x lengths {1, 2, 4, 8 pulses, mixed} x meters {4/4, 3/4, 6/8} x with and without a key change): deterministic; at most 5 candidates; at most one per corpus pattern family (R170); each breakdown sums to its score; every event inside the span and monophonic; in range after placement; no strong-beat chromatic except the last note; the last note within 2 semitones of the landing bass or its fifth (or the landing note itself for `push`; a break-stop's last note is the hit before the silence); no note cross-relates with the sounding chord's third (a note inside a chromatic run into the landing, or the last note before a chord a half step from its bass inside a walk, is exempt); every candidate round-trips through `Part` JSON unchanged.

### 11.7 The song's scale (R170)

- `BassPrefs.mode: FillMode?` in the sidecar's `bass` object (still schema 6, lenient: an unknown value reads as nil): `major`, `minor` (natural), `harmonicMinor`, `melodicMinor`, `bhairav`, `majorPentatonic`, `minorPentatonic`. Nil = the default from the feel and key, `FillMode.standard(genre:key:)`: harmonic minor for a Bollywood feel in a minor key (R161, R168), else the key's own (major, natural minor).
- It is the passing scale for walk-ups (`WalkUpContext.mode`, through `BassLineContext.mode`) and fills (`FillContext.mode`, through `FillSpan.context`), applied to keys of its quality (a minor scale does nothing in a section in a major key).
- The Walk-ups list header shows **"Scale: Default (Major)"** after the feel (`segue.walkUps.scale`), offering "Default (...)" and the scales of the song's key quality only (major: Major, Bhairav, Major pentatonic; minor: Natural, Harmonic and Melodic minor, Minor pentatonic); disabled without a key ("Set the song's key to choose its scale"). One undo step ("Change Scale") in the editor, a sidecar write with no undo in the library; `FeatureKey.songScale`.

## 12. The fill editor (P8-7d; SegueUI; editor and library only, never the stage)

### 12.1 Selecting a span (R166: click, then shift-click)

- **Surfaces:** the editor's text-mode preview and the library song pane preview (chord units, `SongSheetView`), the visual canvas, and the chord-length lane (8).
- **Preview:** a plain click on a chord unit keeps P8-6a's behaviour (it plays the chord) and also records it, invisibly, as the selection anchor. A **shift-click** on another chord unit selects the span from the anchor to it, in written order (either direction; the later chord is the landing): every chord unit in the span gets a `cue` tint and a thin connecting underline, and shift-click makes no sound. Shift-click again moves the landing. Esc, a click on empty space, or an edit clears it. With no anchor, shift-click alone anchors.
- **Visual canvas:** a plain click still opens the chord pill's editor and ⌥-click still plays; a **shift-click** on a pill selects the span from the last pill clicked or played.
- **Lane:** click a block, shift-click another (the only way to include grid chords and `{chorus}` stub chords).
- **Acting on it:** a small capsule button **"Create Bass Fill..."** floats under the span's last unit (`segue.fill.create`); the same item is in the span's context menu and in Song > Create Bass Fill... (⌥⌘F; check the menu clash table first). When the span equals an existing fill's span the button reads "Edit Bass Fill..."; when it overlaps one, choosing it asks to replace (9.3). An invalid span (10) shows the reason in the capsule instead of the button ("A fill can't cross N.C.").
- Fills can be made with or without the bass-note view on; saving one with the view off shows a one-time note: "Fills show in the bass-note view. Turn it on with B or the Bass button." Each saved fill is also listed in the Walk-ups list under a "Fills" group (P8-4 8.9; open, rename, delete).
- A read-only song (newer sidecar) disables the button with the existing help.

### 12.2 The sheet (`segue.fill.editor`)

A resizable sheet (default 1040 x 700, minimum 860 x 600), dark and light per the theme, layout top to bottom:

1. **Header:** "Bass Fill", the span ("Bridge: E -> Chorus 3: A"), the key(s) ("G -> A"), the tempo ("96 BPM"; with the session tempo control 50 / 75 / 100% from P8-6b), the song's feel.
2. **Chord lane** (8): the span's chords, plus one bar of context before and the landing bar, a bar and beat ruler, key-change and meter markers, the playhead; lengths and pushes editable here (writes `bass.timing` like the play-along bar, its own undo step).
3. **Body**, two columns:
   - **Candidates** (left, 220 pt): rows A-D, each with the family name ("Pickup", "Walk", "Sixteenth run", "Triplets", "Octaves", "Push"), a tiny contour sparkline, the note names, and a ▶ button; then a "More" disclosure that reveals E; then "Start from scratch" (an empty part). The selected row is the part being edited; editing it marks the row "Edited" and keeps the original under "Revert to A". With ⌥ held, a row's hover shows its score breakdown (the P8-4b popover convention).
   - **Editor** (right): a segmented toggle **Fretboard | Piano Roll** (`segue.fill.view`; ⌘1 / ⌘2 while the sheet is key, check the clash table), opening on Fretboard + grid the first time and then on the last used view, remembered per user (`FillEditorSettings.view`, UserDefaults `fill.editor`, never per song; R167 Q13). Snap controls: Rhythm (8th / 16th / Triplet, default 8th) and Pitch (Chord tones / Scale / Chromatic, default Scale; ⌥ while placing bypasses it).
4. **Mini tab preview** (12.5), exactly what the stage draws.
5. **Footer:** Name field (optional, default "Fill into <landing section>"), **Shows on** pop-up (Every time / Only #1 ... #n / Last time; R146 style, R167 Q7), **Show as** (Names / Tab), Delete Fill (when editing a saved one), Cancel, **Save** (Return).

### 12.3 Audition and A/B on the P8-6a engine

- `PhraseBuilder.fill(span: SongTimeline, notes: [ResolvedNote], voices: PlaybackVoices, from: Int, through: Int) -> Phrase` (Playback, pure): from one bar before the fill's first note (not before the span start) through the landing chord's first bar; chords voice as play-along plays them; bass voice plays play-along's roots until the fill starts, then the fill's notes, then the landing root; no click unless the sheet's Click toggle is on; tempo from the tempo map times the session factor.
- ▶ on a row plays that candidate once; **Loop** (header switch, default on in the sheet) repeats it; while looping, selecting another row (click, ↑/↓, or the letters A-D, E) switches **at the next phrase start** (`SoundPlayer.swapAtNextWrap`), so A/B is seamless; Space plays or stops the selected row; editing a note while it loops swaps the edited phrase in at the next wrap. Playing never saves.
- Built on P8-6a's `SoundSession` / `SoundPlayer` exactly like `WalkUpAudition`: a `FillAudition` value injected by the sheet's owner (`isEnabled` false during a gig, every sound control disabled with "Sound is off during a show"; P8-6 section 9). The sheet itself is closed when a gig starts (the stage presentation already stops editor sound; the sheet is dismissed with its draft kept for the next open of the same span, never saved).

### 12.4 Fretboard + step grid (the default view)

- **Neck** (top half): horizontal, the profile's tuning (Settings > Instrument for anyone, R163), frets 0 ... 15, strings low at the bottom (tab orientation), the `BassFretboardView` drawing style at an editor size (strings 18 pt apart, frets 34 pt). Tinted by the chord under the selected step: chord tones as in the strip (degree labels), scale tones faint, the selected note filled `cue`.
- **Step grid** (below): one column per snap step across the fill region (the span's departing chords plus the landing bar), grouped by beat and bar, chord names above their columns; each note is a block from its start step to its length, labelled with its fret and string ("7 A") or name (a small "Names / Frets" switch); rests are empty steps.
- **Entry (keyboard first, Guitar Pro style):** ←/→ move the step cursor; ↑/↓ move the cursor string; a digit types a fret on the cursor string (a second digit within 0.6 s makes 10-15; the pitch snap does not apply to typed frets); `+` / `-` lengthen or shorten by one step; `R` or Delete makes the step a rest; ⇧←/⇧→ extend the selection; a click on the neck sets the selected note's pitch at that position (and pins it to that string); a click on an empty grid cell adds a note there (the suggested position for the chord's root, then edit); drag a block's right edge to change its length; drag a block to move it in time. Articulation buttons under the grid (Slide, Hammer, Pull, Ghost, Staccato, Accent) toggle on the selection (keys `⌥S`, `⌥H`, `⌥P`, `⌥G`, `⌥.`, `⌥>`; check clashes).
- Monophonic: a new or longer note truncates the one it overlaps (the model allows chords for other instruments later, 9.6).

### 12.5 Piano roll (the other view)

- Time horizontal (same columns, ruler and chord names as the grid), pitch vertical over the bass range of the tuning (B0 or E1 to G3), one row per semitone with note names on the left. Rows are tinted **per chord column**: that chord's tones strong (`cue` 15%), its passing scale light (`ink` 5%), others plain; key-change columns change the tint with the key.
- Click an empty cell to add a note (pitch snap applies; ⌥ bypasses it), drag a note to move (time snaps, pitch snaps), drag its right edge to resize, ⌥-drag to copy, Delete removes, ⌘A selects all, ↑/↓ transpose the selection by the snap step (⇧ for an octave). Notes outside the instrument range cannot be placed (the rows end there).
- **Shared with the grid:** the same `[PartEvent]` draft (`FillDraft`, `@MainActor @Observable`, SegueUI), the same selection (a set of event ids, kept across the toggle), the same snap settings and one **sheet-local undo stack** (every gesture one step, ⌘Z / ⇧⌘Z, across both views); the sheet's Cancel discards the whole draft; Save is one undo step on the editor window's undo manager (the library has none, as for picks).

### 12.6 Mini tab preview (`Diagrams/TabLayout.swift` pure + `SegueUI/Diagrams/MiniTabView.swift`)

`TabLayout.layout(notes: [ResolvedNote], chords: [(tick, name)], ticksRange:, strings: Tuning, width:) -> TabLayout` (pure): 4 or 5 lines labelled with the open strings (G D A E, plus B), fret numbers placed proportionally to their tick (rhythm as spacing, no stems), a short beat tick under each pulse, a bar line at each bar, chord names above at their onsets, articulations as `s` / `h` / `p` before the fret, `x` for ghost, `>` above for accent, `.` for staccato; the landing bar shows the landing root. Measured widths come from the caller's text measurer (so the stage can lay it out in LiveLayout, 14.2). The sheet shows it full width; the stage uses the same layout (14).

### 12.7 Save and edit

Save writes the part through `LibraryStore.updateParts` (sidecar only; the `.cho` is never touched by a fill), with `origin` (family, template, rank, edited), closes the sheet, and the preview redraws with the fill (in the bass-note view). Editing a saved fill reopens the sheet on it with its candidates regenerated beside it (its own row is "Saved", the candidates below for comparison). Delete Fill asks once and removes it (undoable in the editor).

### 12.8 Accessibility

- Span selection: chord units in a span read "In fill span, 2 of 3"; the capsule is a button "Create bass fill from E to A"; VoiceOver users select a span with the chord unit's actions "Start fill here" and "End fill here" (the actions rotor), so shift-click is not required.
- Candidates: "Option B, pickup, F sharp, G sharp, A, into A, suggested" plus "Play" and "Edited"; the score breakdown is an accessibility custom content item, not hover-only.
- Grid: the step grid is one adjustable container with one element per step: "Bar 2 beat 4 and, over E, F sharp, A string fret 9, eighth note, slide" or "rest"; increment/decrement change the fret; custom actions Lengthen, Shorten, Rest, string up/down. The neck is decorative for VoiceOver (positions are spoken by the grid). Piano roll notes are elements "F sharp 2, bar 2 beat 4 and, an eighth"; the roll offers the same actions.
- The mini tab has a text equivalent: "Tab: A string 7, 9, D string 7, then A" (its accessibility label).
- Selection changes while looping announce "Now playing option C" once (P8-6 13); nothing relies on colour alone (chord-tone tints are also shown by degree labels on the neck); everything works from the keyboard (12.4-12.5 keys, Tab between regions, Space, Return, Esc).

## 13. Play-along with fills (P8-7c amends P8-6b's builder)

`PhraseBuilder.playAlong` (P8-6b) plays each applied fill's resolved notes in place of the bass voice's roots and walk-up over the fill region, in every pass the fill applies to (R167 Q8: the fill wins, the pick is kept). If P8-6b has landed before P8-7c, P8-7c adds this as one hunk in `PhraseBuilder.playAlong` with its tests; if not, P8-6b builds it from this section. The Rehearsal stage's play-along (`p`, P8-6 10.4) therefore plays fills: that is the existing rehearsal sound path, never a Live show (section 21 Q4).

**Wiring (R170):** every place walk-ups are worked out gets the sidecar's `parts` (`BassLineContext.apply(_:parts:units:sections:)`): the editor preview (`BassRender.parts`), the library preview (`SongSummary.renderModel`), the Walk-ups list and popover, the stage layout (`StageRequest.walkUps`) and both play-along timelines (`PlayAlongSource.make`, `LiveSession.playAlongTimeline`), so a covered change shows and plays no walk-up in that pass. The editor's and library's `PlayAlong.fillProvider` plays `PlayAlongSource.fills` (`PlayAlongFills`: the resolved parts and the timeline the range is cut from); the stage's `StagePlayAlong.fillProvider`, set when sound is attached, resolves the current song's parts for its played passes (`LiveSession.playAlongFills`).

## 14. Stage, mini neck and PDF (P8-7e)

### 14.1 Note names (default; R167 Q12)

- In the bass-note view (as walk-ups, R162 Q4), each chord in an applied fill's span gets `RenderChord.fill: FillRun?` (new, beside `approach`, `Editing/RenderModel.swift`): `{ part: PartID, notes: [String], chromatic: [Bool], isLast: Bool, accessibility }`, the notes sounding over that chord, spelled (9.2), Nashville degrees when the song's Nashville is on. It is drawn after the chord unit like the approach run (one space, notes separated by spaces, the last departing chord's run ending in "›", chromatic "°"): `E  E F# G# ›` then `A`. A run is drawn in `ink` at 70% like a pick (it is yours), in the measured `TextRole.approach` style; a chord with a fill run never draws an approach run. A chord in the span with no notes over it draws nothing.
- Fills show in the bass-note view whatever the walk-up density (they are the user's own; section 21 Q7).
- Built by `BassLine.annotate` (it already owns the runs and the passes): it receives `ResolvedParts` and the timeline, sets `fill` runs on the chords of each applied part per pass, and clears `approach` on covered changes (9.3).

### 14.2 Tab per fill, and `t` flips all fills to tab

- A fill whose `show` is `tab` (or every fill while "Fills as tab" is on) draws, instead of its runs, a **mini tab block** under the lyric line holding the span's first chord (section 21 Q5): a new `RenderItem.fillTab(FillTabBlock)` inserted after that line in the pass's items (`FillTabBlock { part, layout input, accessibility }`), measured and placed by LiveLayout as a block (its height = strings x 8 pt + chord names + ruler at the stage scale; full column width, rhythm proportional). Every exhaustive switch over `RenderItem` gains the case (`LiveLayout/SectionLayout.swift`, `LiveLayout/SongPreparation.swift:178`, `Library/SlotArrangement.swift`, `Library/SectionNotes+Anchors.swift`, `SegueUI` `SongSheetView`, `StageSongBody`, `StageTypography`, `CanvasTypesetting`, `CanvasProjection`): the canvas and anchors ignore it; the previews and stage draw `MiniTabView`. A span that starts in a grid draws its tab (or a names line) after the grid.
- **Stage key `t`** (free in the default table, section 4): new `LiveCommand.toggleFillTab`, title "Fills as Tab", scope `.viewport`, `repeatsWhenHeld` false, in the help group with `b` ("Bass"); works in Live and Rehearsal (display only, no sound); flips the user-level `InstrumentProfile.fillsAsTab` (new, persisted, default off; lenient decode), relayouts and flashes "Fills as tab" / "Fills as names". The editor top bar's Bass menu gets the same "Fills as Tab" item, and Settings > Instrument a "Show fills as: Each fill's choice / Always tab" row, all the same setting. `t` in a song with no fills flashes "No fills in this song". The binding clash test and `KeyHelpTests` cover it; `KeyHelp.statusHints` gains "T fills as tab" when the song has a fill.

### 14.3 Silent on stage

Fills add no sound path on any stage: the stage has no fill audition and no click targets (P8-6 section 9 holds); the only sound a fill makes on a stage is through the Rehearsal play-along's existing path (13). `SoundSafetyTests` gains: a gig with fills on the chart records no events, and `t` in a gig changes only the display.

### 14.4 Mini neck: the fill path

While the chord at the reading line is inside an applied fill's span in the current pass, `StageBassNeck` draws that chord's fill notes as numbered dashed rings (the R166 walk-up path style), numbered in played order across the whole fill (so the bassist sees "3, 4, 5" over the second chord), positioned by the pin else `BassFretboard.walkPath` from the suggested position; notes outside the 5-fret window are left out, as for walk-ups. A covered change never also draws its walk-up path. Accessibility value adds "fill: 5 notes". `StagePasses.chord(at:plan:pinned:)` already returns the placed chord; it gains the chord's `FillRun` reference.

### 14.5 PDF: the hook only

The bass chart PDF is built in the phase 4 export (`docs/phases/4-export.md:19`), not here. P8-7e provides the seam and nothing else: with bass notes forced on (`DisplayOptions.withBass(_:forcingNotes:)`), the render model already carries `RenderChord.fill` runs and `RenderItem.fillTab` blocks for the song's applied fills in written order (every pass where a fill applies), and `TabLayout` lays out a tab for any width. The phase 4 export's `ChartLayout` prints runs as dark-grey text like walk-up runs (skipping a run whose `inTab` is set: its fill prints as the block) and tab blocks with `FillTabBlock.layout(width:metrics:measure:)` in the print theme. The orchestrator adds one line to `docs/phases/4-export.md`'s Bass chart note pointing at this section (this spec does not edit that file); if the export exists when P8-7e runs, stop and ask before touching it.

### 14.6 As built (P8-7e)

- `FillRun` and `FillTabBlock` live in `Editing/RenderModel+Bass.swift` and carry the part's id as its string (`Editing` cannot see `Library`'s `PartID`). `FillRun` also carries the neck's input: `pitches`, `pins` (a pinned note's position), `firstNumber` (its first note's number in the whole fill) and `total`.
- A fill shown as a tab keeps its `FillRun`s with `inTab` set: they are not drawn (the block is) but the stage neck still shows the fill's path over the chord.
- Fills follow the walk-up density (R168 Q7, overruling 14.1's second bullet): `BassLine.annotate` draws nothing while walk-ups are Off, and a fill shows on any change while they are on, as a saved pick does (R162 Q2).
- On stage, `BassLine.context(for:document:prefs:parts:order:)` builds `BassLineContext.played`, the timeline in the played passes' order, only when a fill applies; fills are resolved and laid out once per plan in `SongPreparation`, and a tab row keeps with the line above it when a section splits between columns.
- A span starting in a grid always draws as a tab after the grid (no names line).
- The editor's "Bass menu" is the bassist's "Bass, BEADG" menu in the top bar; Settings > Instrument's row sits in the Walk-ups section.

## 15. Analytics (non-PII, closed vocabulary)

`FeatureKey` (`Services/FeatureKey.swift`) gains, recorded with `.featureUsed(key, context)` at view-model entry points, daily per (feature, context):
- `timingTap` (`.editor`, `.library`): a tap capture kept.
- `chartDirective` (`.editor`): a `{key}`, `{time}` or `{tempo}` inserted by 6.1 or the tap review.
- `keyChangeChip` (`.editor`): a chip confirmed.
- `fillEditor` (`.editor`, `.library`): the fill sheet opened from a span.
- `fillAudition` (`.editor`, `.library`): a candidate or draft played.
- `fillPianoRoll` (`.editor`, `.library`): the piano roll view used in a session.
- `fillTab` (`.stage`, `.editor`, `.settings`): "Fills as tab" turned on (stage `t`, the editor menu, Settings).
- Pushes and sub-beat lengths are corrections: they record the existing `playAlongTiming`.

New event rows (WS3 spec 5 catalogue; Services mirrors the vocabularies, since it does not import MusicTheory or Library):
- **Row 26 `Segue.Bass.fillSaved`** (`FillSavedSummary`): `segue.family` (`walk`, `pickup`, `run`, `triplet`, `octave`, `push`, `scratch`), `segue.rank` (`a`, `b`, `c`, `d`, `more`, `scratch`), `segue.edited` (Bool), `segue.view` (`fretboard`, `pianoRoll`, `both`, `none`: where it was edited), `segue.chords` (SmallBucket: span length), `segue.keyChange` (Bool), `segue.genre` (the feel), `segue.shows` (`all`, `only`, `last`). Daily per (family, rank, edited). Answers: do people keep the generated fills, which families win per feel, is the piano roll used, do key-change fills matter.
- **Row 27 `Segue.Timing.tapCaptured`**: `segue.mode` (`click`, `free`), `segue.outcome` (`kept`, `discarded`), `segue.chords` (SmallBucket), `segue.skipped` (SmallBucket), `segue.tempoSet` (Bool). Per occurrence (rare).
- **Row 28 `Segue.Timing.keyChange`**: `segue.action` (`confirmed`, `dismissed`, `inserted`), `segue.interval` (`halfUp`, `wholeUp`, `other`). Daily per tuple. Answers whether the chip's threshold is right (a dismissal-heavy rate means it fires too often).

Proposed beyond the ask (cheap, same rows): the rank of the candidate kept vs its family, so `FillWeights` tuning sees whether A is usually right; and `segue.estimated` (Bool) on row 26 (a fill saved over estimated lengths), which shows whether the lane is being used before fills. Update `ServicesVocabularyTests` and `docs/release/specs/WS3-services.md` (row 8's list, rows 26-28) in the same change as each key.

## 16. Tests (R113 budget)

Music theory and timing are tricky pure logic: table-driven Swift Testing suites in `Packages/SegueCore/Tests/SegueCoreTests`, one-line rows, real `RenderModel`s from small `.cho` texts (no mocks). UI behaviour in-process in `SegueThemeTests`. One XCUITest for the whole workstream.

### 16.1 Core

- **`SongTimelineTests`** (7a): layer order (correction > chart > rule); `ticks` beats `beats`; push moves the onset and shortens the chord before, bar grid unchanged, ignored on the first chord; each rule in 4/4, 3/4, 6/8 (720-tick pulses); a chordless lyric line extends the previous chord; `N.C.` silent with length; unknown skipped; a `{chorus}` stub written out; played passes with a Skip pass; one correction applies to every pass of its section; an unmatched correction is listed in `unmatched` and ignored; `barBeat` and `chord(atTick:)` round-trip; `lineOnset`; `slice`; the 2 ms budget.
- **`PositionalDirectiveTests`** (7a): mid-song `{key: A}` before the last chorus: chords before it in G, after it in A; `Metadata.key` still "G" (index, header unchanged); `{time: 3/4}` before the bridge changes bar length there and `ChordBeats` per line; `{tempo: 120}` mid-song in the tempo map; a directive between sections applies to the next section; one inside a section before a line; an unparsable second `{key}` is skipped; a `{key}` after an intro with no earlier one is the initial key; capo and a slot override transpose every entry.
- **`GridParserTests`** (7a): shape `1+4x2+4` with `| G . | C . |` -> G 2 cells, C 2 cells at one bar each; `.`, `/`, `~`, `%`, `%%`; `|: ... :|` and voltas `|1` `:|2` expand; margin text ignored; strum lines ignored; legacy `{start_of_grid: 1+4x2+4}`; an unknown token is text; `ChordBeatsTests`' "a grid contributes nothing" row changes to "a grid's chords are timed by the grid".
- **`ChordAnchorTests`** (extend, 7a): grid chord anchors save and resolve; a `ticks` / `push` override round-trips and resolves.
- **`BassPrefsSidecarTests`** (extend, 7a): `ticks`, `push`, `source`, `dismissedKeys` round-trip; a bad `push` drops only that field; an old-shape override still reads; the song's scale `mode` round-trips, an unknown one reads as the default, none is not written (R170).
- **`BassLineTests`** (extend, 7a): a 4-beat user correction raises `maxNotes` from 2 to 3 where the chart had no marks; a rule-estimated chord still caps at 2; after `{key: A}` the walk-up into the last chorus is spelled and scaled in A; Nashville degrees re-key after the change; the song's scale sets the passing notes (C -> F walks D E in major, Db E in Bhairav) and defaults to harmonic minor for a Bollywood feel in a minor key (R170).
- **`TapQuantiserTests`** (7b): click mode quantises to pulses, ⌥/half beats to eighths; free mode derives 96 BPM from noisy taps (scripted intervals with +-30 ms jitter), prefers the song's `{tempo}` within 2%, ties go slower; skip keeps the lower-layer length; a zero-length chord is dropped and marked skipped; clamping.
- **`KeyChangeDetectorTests`** (7a core; fixtures in 6.2).
- **`DirectiveInsertTests`** (7a): `insertDirective` before a section header and before a line inside a section; byte-minimal; rejects other names and bad values; undo restores bytes.
- **`PartModelTests`** (7c): resolve `deg`/`oct` to MIDI under transpose, capo (both modes), a slot key override and a 5-string profile; spelling in the key in effect; a pin honoured, ignored on a missing string; octave folding flagged; an event past its chord's length flagged and skipped; articulation velocities and lengths.
- **`PartAnchorTests`** (7c): resolves unchanged; survives transpose and an edit below the first two lines; re-anchors as picks do; unmatched when a span bass changes, a chord is inserted inside the span, or the landing is deleted; `.only(3)` / `.last` / `.all` on played passes; an arrangement that does not play the landing next does not apply it; overlap is rejected; fill wins over pick (`shown == nil`, `coveredBy`), the pick applies again on a skipped pass and after the part is removed.
- **`PartsSidecarTests`** (7c): v5 migrates to 6 with empty `parts`; round-trip of the 9.5 example; lenient drops (bad event, bad part, unknown instrument); a v7 file opens read-only; `updateParts` leaves the `.cho` bytes, mtime and index projection unchanged.
- **`FillCandidateTests`** (7c): the corpus goldens (11.4, per-category floors at the rates achieved) and named rows (11.5). **`FillPropertyTests`** (11.6). **`FillTemplateCorpusTests`** (11.4 item 2).
- **`PhraseBuilderTests`** (extend): `fill` audition phrase bounds and voices (7d); play-along plays a fill instead of the pick in the passes it applies to (7c, with P8-6b's suite); **`PlayAlongFillTests`**: "Last time" plays on the song's last chorus, never on a looped first chorus (R170).
- **`TabLayoutTests`** (7d): columns proportional to ticks, bar lines, chord names, articulations, 4 and 5 strings, a pin.

### 16.2 LiveLayout (7e)

**`StageFillLayoutTests`**: a corpus song with two fills laid out with bass view on: names runs placed as chord-unit runs (`LayoutAudit` clean, no overlap with the next chord), covered changes have no approach run; a tab fill inserts a measured block after the right line; flipping "fills as tab" relayouts with every fill as a block; the passes filter on P8-2's played passes (only the last chorus gets the fill); a grid-start fill's block after the grid. **`BassNeckChordTests`** (extend): the fill path numbering across two chords; the walk-up path not drawn on a covered change.

### 16.3 SegueUI (in-process)

- **`TimingLaneTests`** (7b): ⌥-drag to eighths, typed "2.5", `<` push cycle, edge styles per source, markers, one undo step per gesture, shift-click span in the lane.
- **`TapCaptureTests`** (7b, scripted clock, `RecordingSoundOutput`): click mode plays the count-in and click, taps become proposed lengths, nothing is written before Keep, Keep writes one `updateBassPrefs` with `source: "tap"` and one undo step, Discard writes nothing, Tab skips, Esc stops, free mode shows the derived tempo and "Set song tempo" writes `{tempo}` only when pressed; disabled during a gig.
- **`KeyChangeUITests`** (7b): the chip shows on the fixture's last chorus in both editor modes; Insert writes `{key: A}` before the section (undoable); dismiss writes `dismissedKeys` (sidecar only) and hides it; the Insert ... Change Here menu items and the popover validation.
- **`ChordSpanSelectionTests`** (7d): click plays and anchors; shift-click selects across a section boundary silently; either direction; Esc clears; N.C. and 9+ chords and 8+ bars refused with the reason; the canvas shift-click; the VoiceOver start/end actions; "Edit Bass Fill..." on an existing span; library preview.
- **`FillEditorTests`** (7d): four candidates A-D and More with distinct families; ▶ schedules the phrase (`RecordingSoundOutput`); looping and A/B swap at the next wrap; the view toggle keeps the selection and remembers the view across sheets; typed fret entry (single and two digits), `+`/`-`, `R`; neck click pins a string; piano roll add/move/resize with snaps and ⌥; one undo stack across both views; mini tab text equals `TabLayout`; Save writes `parts` only (the `.cho` unchanged) with `origin`; Revert; Delete; overlap replace prompt; gig gate disables sound and dismisses the sheet; analytics `fillEditor`, `fillAudition`, `fillPianoRoll`, row 26.
- **`FillEditorSnapshotTests`** (7d): the sheet at default size, light and dark, Fretboard and Piano Roll; `MiniTabView` snapshots (4 and 5 strings).
- **`StageFillTests`** (7e): names by default, a tab fill as a block, `t` flips all and persists, works in Live with no sound (`SoundSafetyTests` extended), the neck's fill path, key help and status hints list `t`.
- **`WalkUpPickerTests`** (extend, R170): the Walk-ups list's scale in the editor (the key quality's scales, default Major, one undo step) and the library (sidecar write).
- **`PlayAlongTests`** (extend, R170): a saved fill plays in the editor's and library's play-along and covers its walk-up; the stage resolves the saved fill for its played passes.
- **`ServicesVocabularyTests`**: every new key and rows 26-28.

### 16.4 The one UI test (P8-7f)

`SegueFillE2ETests.testCreateFillAndReadItOnStage` (`UITests/SegueFillE2ETests.swift`, in `UITests/e2e-map.tsv`), as built in P8-7f: a library seeded with a song in `{key: G}` whose verse `[G]Hello` / `[C]there` ends on C and whose chorus `[D]friend` / `[G]home` starts on D (one chord per line, so the test clicks each chord at its line's start) -> Edit, text mode, the bass-note view on (`B` segment) -> in the preview click `C`, shift-click `D` (the capsule reads "from C to D", across the section boundary) -> Option-Cmd-F -> the sheet shows options A-D -> audition B (Play, then Stop) and choose it -> click the grid's first steps and type `9` (the mini tab changes) -> Piano Roll and back (the choice and the edit survive) -> Save -> the `.cho` is byte-identical, the sidecar holds one part, and the preview shows a fill run over `C` -> quit and relaunch on the same library without resetting state -> the library preview shows the same run -> Rehearse that song (R150) -> the stage shows the run -> press `t` -> a tab block appears (`segue.live.fillTab`) and the names go -> End. One `make e2e-one TEST=SegueFillE2ETests`. No audio is asserted in UI tests (P8-6 15.4).

## 17. Sessions and steps

Every session ends with one `make quick` (and `make e2e-one` only for an existing class it changed).

**P8-7a - time core** (after P8-4b, landed; **before P8-6b step 9**; may run beside P8-6a)
1. `Meter`, `PositionalMap`, `PositionalDirectives.scan`; the `{key}` fix in every musical consumer (5.3). Suites: `PositionalDirectiveTests`, the editing goldens (unchanged for songs with one `{key}`).
2. `GridParser`; grid chords in `WrittenChords`. Suites: `GridParserTests`, `ChordBeatsTests`, `ChordAnchorTests`.
3. `SongTimeline` with layers, push and ticks; `ChordBeatsOverride` and `ChordTiming` new fields (lenient). Suites: `SongTimelineTests`, `BassPrefsSidecarTests`.
4. `BassLine` reads the timeline (beats and key in effect); `SongPreparation`'s hook passes it. Suites: `BassLineTests`, `StageWalkUpLayoutTests`, `WalkUpTests` (unchanged).
5. `KeyChangeDetector` and `EditOperation.insertDirective`. Suites: `KeyChangeDetectorTests`, `DirectiveInsertTests`.
6. Hand the orchestrator a note for P8-6b: `SongTimeline.slice` is ready, and P8-6 section 7 (amended) is the contract.

**P8-7b - timing UI and tap capture** (after P8-7a and **P8-6b** (the play-along bar and its lane exist))
7. Lane extensions: sub-beat, push, edge styles, markers, shift-click spans (8). Suite: `TimingLaneTests`.
8. Tap capture with review, `TapQuantiser` (7). Suites: `TapQuantiserTests`, `TapCaptureTests`.
9. Directive insert UI and the key-change chip (6). Suite: `KeyChangeUITests`.
10. Analytics `timingTap`, `chartDirective`, `keyChangeChip`, rows 27-28. Suite: `ServicesVocabularyTests`.

**P8-7c - parts and generator** (after P8-7a and **after the fill corpus research has landed**: `docs/research/phase8-fill-corpus.md` and `fill-corpus.json`; silent)
11. Corpus fixture in place and its loader (11.4); `Part` types, `PartAnchors`, `Part.resolve`, sidecar schema 6, `updateParts`. Suites: `PartModelTests`, `PartAnchorTests`, `PartsSidecarTests`.
12. **Template tuning, consuming the corpus:** `FillTemplates.standard` and the prior table derived from it; `Fill.candidates` with `FillWeights.standard`; `FillSpan.context`. Write the goldens first and drive the rules to them. Suites: `FillCandidateTests`, `FillPropertyTests`, `FillTemplateCorpusTests`.
13. Fill wins over pick in `BassLine` (`coveredBy`); fills in `PhraseBuilder.playAlong` (section 13) if P8-6b has landed, else hand it to P8-6b. Suites: `BassLineTests`, `PhraseBuilderTests`.

**P8-7d - the fill editor** (after P8-7c, **P8-6a** (engine, `SoundPlayer`, the audition pattern) and P8-7b (the lane component))
14. Span selection in previews, canvas and lane; the capsule, menu and context menu (12.1). Suite: `ChordSpanSelectionTests`.
15. The sheet: header, lane, candidates with audition and A/B (`PhraseBuilder.fill`, `FillAudition`), footer, save, revert, delete (12.2, 12.3, 12.7). Suites: `FillEditorTests`, `PhraseBuilderTests`.
16. Fretboard + step grid with typed entry; piano roll; shared `FillDraft`, selection and undo; `TabLayout` and `MiniTabView` (12.4-12.6). Suites: `FillEditorTests`, `TabLayoutTests`, `FillEditorSnapshotTests`.
17. Accessibility (12.8) and analytics `fillEditor`, `fillAudition`, `fillPianoRoll`, row 26. Suites: `FillEditorTests`, `ServicesVocabularyTests`.

**P8-7e - stage and the PDF hook** (after P8-7d; its layout step may start after P8-7c)
18. `RenderChord.fill`, `RenderItem.fillTab` and every switch over it; `BassLine.annotate` sets runs per pass. Suites: `StageFillLayoutTests`, the editing goldens, `LiveLayoutEngineTests`.
19. `LiveCommand.toggleFillTab` and `t`, `InstrumentProfile.fillsAsTab`, the editor menu item and Settings row, key help; the mini neck's fill path; `SoundSafetyTests` additions; analytics `fillTab` (14). Suites: `StageFillTests`, `BassNeckChordTests`, `KeyHelpTests`, `SoundSafetyTests`.
20. The PDF seam check (14.5): with bass forced on, a render model carries the runs and blocks; note to the orchestrator for `4-export.md`.

**P8-7f - closing** (after P8-7e)
21. `SegueFillE2ETests` (16.4) and its one `make e2e-one`.
22. Guide: `play-bass.mdx` gains "Fills" (select, create, audition, edit, Shows on, names and tab, `t`) and a new page `chord-timing.mdx` (the chord-length lane, pushes, Tap Timing with and without the click, key changes and the chip, inserting `{key}` / `{time}` / `{tempo}`), with real screenshots through the guide's `Shot` component as `play-bass.mdx` does; `keyboard.mdx` lists `t` and the fill editor keys; the site's sidebar (`guide/astro.config.mjs`) and any in-app help link table updated together.
23. Hand Ryan the **by-ear fill check** (a manual step for Ryan, say so explicitly): on his own songs (one Bollywood, one with a last-chorus lift), create fills across a key change and a section boundary, audition A-D and More, and note any candidate that sounds wrong; each becomes a golden case and any tuning changes only `FillWeights.standard` or `FillTemplates.standard` (never the corpus). One `make quick`. The checklist is below.

**By-ear fill check (MANUAL STEP FOR RYAN; agents never do it).** On a Personal or App Store build, with Settings > Instrument > I play bass on, the bass-note view on and headphones or the usual monitor output:

1. **Pick two of your own songs:** (a) a Bollywood / Hindi film song (set the Walk-ups list's Feel to Bollywood if the song has none), (b) a song whose last chorus lifts key (a `{key}` before it; insert one with Insert Key Change Here if needed). Give both a `{tempo}` and fix any estimated chord lengths in the play-along lane first, so the fills play at the real feel.
2. **Fill across a section boundary** in each song: click the last chord of a verse, shift-click the first chord of the chorus, Option-Cmd-F.
3. **Fill across the key change** in song (b): from the last chord before the lift to the first chord of the lifted chorus. Check the notes are spelled in the new key (R169).
4. **Audition every option** for each span: A, B, C, D, then More (E), with Loop on, switching between them while they play. Also try Tempo 75% and the click off once.
5. **For each option, note one verdict:** fine, wrong note (which one), wrong rhythm or feel, too busy for the tempo, lands badly on the target chord, or a missing pattern you would have played instead (describe it as chord functions, degrees and rhythm, not a copied tab).
6. **Check the ranking:** is the option you would actually play in A-D? Is "hold" (or nothing) ranked where it should be for a slow worship song and for bVI-bVII-i?
7. **Save one fill per song**, play it back in Rehearsal play-along (`p`), and confirm it plays only on the passes its Shows on says, then press `t` on stage to read it as tab.
8. **Hand the notes back** as a short list: song, span (e.g. "E -> Am into chorus"), feel, tempo, option letter, pattern name, verdict. The orchestrator turns each wrong candidate into a `FillCandidateTests` golden case; tuning touches only `FillWeights.standard` or `FillTemplates.standard`, never `fill-corpus.json`. A check with no wrong candidates is recorded as "none" (19, P8-7f done criteria). The four Bollywood misses and three `theory` rows named in 11.3 (`bw-chaal-pickup`, `bw-ballad-fifth`, `bw-disco-octaves`, `bw-rock-n-roll-soniye`) are worth a listen in passing.

Dependencies (also in `README.md`):

```
P8-4b ─> P8-7a ─┬─> P8-6b ─> P8-7b ──┐
                │                   ├─> P8-7d ─> P8-7e ─> P8-7f
fill corpus ────┴─> P8-7c ──────────┤
P8-6a ──────────────────────────────┘
```

All before v0.5 (R167 Q15).

## 18. Files owned

- New (SegueCore `Library`): `Library/Timing/` (`SongTimeline.swift`, `Meter.swift`, `PositionalMap.swift`, `PositionalDirectives.swift`, `GridParser.swift`, `TapQuantiser.swift`, `KeyChangeDetector.swift`), `Library/Part.swift`, `Library/PartAnchor.swift`, `Library/FillSpan.swift`, `Library/LibraryStore+Parts.swift`.
- New (SegueCore other): `MusicTheory/Fill.swift`, `MusicTheory/FillTemplates.swift`, `MusicTheory/FillWeights.swift`, `Diagrams/TabLayout.swift`; `Playback/PhraseBuilder+Fill.swift`; tests in 16.1; `Packages/SegueCore/Tests/Fixtures/fills/fill-corpus.json` (moved in, owned by the corpus research).
- New (SegueUI): `Editor/Fill/` (`FillEditorSheet.swift`, `FillDraft.swift`, `FillCandidatesColumn.swift`, `FillFretboardGrid.swift`, `FillPianoRoll.swift`, `FillAudition.swift`, `ChordSpanSelection.swift`), `Diagrams/MiniTabView.swift`, `Editor/TapCapturePanel.swift`, `Editor/KeyChangeChip.swift`, `Editor/DirectiveInsertPopover.swift`, `Settings/FillEditorSettings.swift`, `AccessibilityID+Fill.swift`; tests in 16.3; `UITests/SegueFillE2ETests.swift`.
- Changed: `ChordPro/SongDocument+Derived.swift` (doc comments only: the first-value meaning), `Editing/DocumentEditor.swift` (`insertDirective`), `Editing/DisplayOptions.swift` and `Editing/RenderSectionBuilder.swift` (spelling and Nashville by the key in effect), `Editing/RenderModel.swift` (`fill`, `fillTab`), `Editing/InstrumentProfile.swift` (`fillsAsTab`), `Library/BassPrefs.swift` (override and timing fields), `Library/ChordBeats.swift` (per-line meter), `Library/ChordAnchor.swift` (grid chords), `Library/BassLine.swift`, `Library/BassLine+Song.swift`, `Library/Sidecar.swift`, `Library/SidecarCodec.swift` (schema 6), `Library/LibraryStore.swift`, every `RenderItem` switch (14.2), `LiveLayout/SongPreparation.swift`, `LiveLayout/SongMeasurement.swift`, `LiveLayout/StagePasses.swift` (P8-2's file, by hunk), `Playback/PhraseBuilder.swift` (play-along fills, by hunk with P8-6b), `Shows/LiveCommand.swift`, `Shows/InputBindings.swift`, `Shows/KeyHelp.swift`, `Services/FeatureKey.swift`, `Services/AnalyticsEvent.swift` (+ `Throttle`), `Editor/TimelineStrip.swift` and `Editor/PlayAlongBar.swift` (P8-6b's files, by hunk), `Editor/WalkUpPopover.swift` and `Editor/WalkUpsSheet.swift` (covered-change note, Fills group), `Rendering/SongSheetView.swift` (span selection, runs, tab blocks), `Editor/SongEditorView.swift`, `Editor/EditorTopBar.swift`, visual canvas gesture file (shift-click), `Library/SongDetailPane.swift`, `Live/StageBassNeck.swift`, `Live/StageSongBody.swift`, `Settings/InstrumentSettingsView.swift`, `docs/release/specs/WS3-services.md`, `guide/` pages (step 22).

## 19. Done criteria

- **P8-7a:** a second `{key}`, `{time}` or `{tempo}` counts from where it is written for walk-ups, Nashville, spelling, the stage scale line and (once built) play-along, while library, filters and header keep the first; grids are timed; `SongTimeline` is the only length source for walk-ups and the contract for P8-6b; `ticks`, `push` and dismissals round-trip in schema 5; walk-ups are unchanged on every existing golden; suites and `make quick` green.
- **P8-7b:** the lane edits sub-beat lengths and pushes; Tap Timing works with the click and tempo-free, reviews before save, writes one undoable correction set, and never writes `{tempo}` unless asked; the chip suggests the fixture key changes only, inserts on a click and dismisses into the sidecar; directive inserts are one line each and undoable; analytics fire; suites green.
- **P8-7c:** fills are `Part`s in sidecar schema 6 (never the `.cho`), anchored to start and landing chords, unmatched ones kept and listed; "Shows on" filters passes; a fill wins over the pick, which is kept; `Fill.candidates` gives up to five deterministic candidates, one per corpus pattern family (R170), with breakdowns, its templates grounded in the corpus; corpus goldens, named rows and properties pass; play-along plays fills; nothing in P8-7c makes a new sound path; suites green.
- **P8-7d:** click then shift-click (and the lane, canvas and VoiceOver actions) selects a span; the sheet offers A-D plus More, auditions with loop and seamless A/B, edits on fretboard + grid (typed frets) or piano roll with one selection and undo, remembers the view, previews the mini tab, saves only the sidecar; nothing sounds or opens during a gig; accessible by keyboard and VoiceOver; snapshots and suites green.
- **P8-7e:** fills read as note names on charts and stage, tab per fill, `t` flips all to tab in Live and Rehearsal with no sound, the neck shows the fill path, layouts audit clean, the PDF seam carries runs and blocks; suites green.
- **P8-7f:** `SegueFillE2ETests` green once; the guide pages are live in the build with real screenshots and the key table; Ryan has done the by-ear fill check, and its findings are goldens or recorded as none.

## 20. Where the research was overruled or changed

By **R167** (Ryan):
- **Q15 (release).** The research recommended the fill editor (its sessions 4-6) **after** v0.5, with only the time core landing with P8-6b. R167 ships **everything before v0.5** (time core, timing UI, tap capture, parts and generator, editor, stage, PDF) as P8-7, and puts P8-6b on the same `SongTimeline`. Sections 1 and 17 follow R167; the time core must land **before** P8-6b, not "before or with" it (research D, session 2).
- **Q16 (thin evidence).** The research recommended accepting thin evidence and tuning by ear, with a corpus-growth task inside the generator session. R167 makes the corpus **a research ticket first**; the generator's templates are derived from it (11.3-11.4), and P8-7c is blocked on it (17). The by-ear check stays, as a final pass (step 23), not as the tuning method.
- **PDF.** The research had P8-7 print fills in the bass chart PDF (C5, D6); R161 had already moved the bass chart into the phase 4 export, so P8-7 specifies the seam only (14.5).
- Every other research recommendation was accepted as offered.

By this spec (each also an open question below where it is a real choice):
- The time model lives in `Library`, not a new `Timing` module (5.1; a dependency cycle otherwise).
- Ticks are 480 per quarter, not 24 (Q1).
- The key-change chip is in the editor for anyone, not only in the bass view (6.2), because accepting it edits the `.cho` and a key change matters to every chart.

## 21. Open questions

1. **Tick resolution.** (a) 480 per quarter (a standard MIDI resolution, holds 64th-note meters, triplets and quintuplets exactly) / (b) 24 per quarter (the research's MIDI-clock choice; a `{time}` in /64 would not divide). **Recommend (a)**; it only changes the numbers stored in `ticks` and `at`/`len`.
2. **Which consumers follow a mid-song `{key}`.** (a) Walk-ups, fills, Nashville numbers (re-keyed from the change, NNS practice), transposed chord spelling and the stage's sounding key and scale line follow the key in effect; library, filters, essentials and the song header keep the first `{key}` / (b) only walk-ups and fills follow it, everything visible stays on the first key / (c) (a) but Nashville keeps numbering in the song key. **Recommend (a).**
3. **The stage metronome and a mid-song `{tempo}` / `{time}`** (outside play-along, which follows the maps). (a) The pips and rehearsal click switch at pass boundaries to the value in effect at the pass's first chord / (b) keep the first `{tempo}` and `{time}` for the whole song in v0.5. **Recommend (a)**: it honours R167's "mid-song directives are honoured" without tying the metronome to scroll position inside a pass.
4. **Fills in the Rehearsal play-along.** (a) `p` in a rehearsal plays fills as it plays walk-ups (the existing rehearsal sound path; Live stays silent by construction) / (b) fills never sound on any stage, rehearsal play-along plays the pick or top walk-up instead. **Recommend (a)** (R162 Q6: play what the chart shows; R167 Q8: the fill wins in play-along).
5. **Where a tab fill sits on stage.** (a) A block under the lyric line holding the span's first chord / (b) a block just above the line holding the landing chord / (c) in the gutter beside the span. **Recommend (a)**: the bassist reads it as the fill starts; (c) has no room at stage sizes.
6. **Plain click in the preview.** (a) Keeps playing the chord (P8-6a) and also sets the invisible selection anchor; shift-click selects silently / (b) a plain click only plays, and spans need ⌘-click then ⇧-click / (c) a "Select Chords" mode in the top bar. **Recommend (a)**: it is R166's "click, then shift-click" with no new mode.
7. **Fills and the walk-up density.** (a) Fills show in the bass-note view whatever the walk-up density (they are the user's own) / (b) fills follow the density (hidden when walk-ups are Off). Either way they show only in the bass-note view (as R162 Q4 for walk-ups). **Recommend (a).**
8. **`t` scope.** (a) A persisted user-level setting ("Fills as tab", like `b` for bass notes), mirrored in the editor menu and Settings / (b) a stage-session-only flip that resets per show. **Recommend (a)**, consistent with `b`.
10. **If the corpus schema or family set differs from section 11.4 / 11.3.** (a) The corpus is canonical: P8-7c adapts the loader, and a new family the corpus finds (for example a Bollywood slide/meend family) comes back to the orchestrator as a one-line spec change before tuning / (b) P8-7c maps it onto the six families without asking. **Recommend (a)**, per the house rule to stop and ask at a spec-vs-research inconsistency.
11. **Span limits.** (a) 2-9 chords and at most 8 bars of departing time / (b) no chord limit, 4 bars / (c) no limits. **Recommend (a)**: long enough for a turnaround across a section, short enough for the generator's templates and the stage display.
