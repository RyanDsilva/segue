# P8-6 - Audio: hear chords, audition walk-ups, play along

Phase 8 workstream (new, 2026-10-30). Rulings: `docs/release/decisions.md` **R161** (audio is a new workstream P8-6, shipped before v0.5 per R155, after P8-4b; the play-along loop is in; the sound bank is picked by a listening A/B in the build session, GeneralUser GS vs FluidR3, SF2 only, 12 MB cap; chord voice piano or clean guitar in Settings; a Settings output picker, default system output, plus a quiet hint for a USB interface; audio never plays in a Live show), **R162** (this spec's open questions closed, section 19; the USB hint is a Settings note only), **R160** (the research request), **R155** (Phase 8 ships before v0.5). Earlier rulings this builds on: R90 / R108 / R118 / R142 (rehearsal-only metronome click, no sound during a show, compound meters), R113 (test budget), R148 (rehearsal loop with a one-bar count-in, built by P8-2), R150 (single-song Rehearse / Live), R152 and R158 (bass profile and views, P8-4a). Research: `docs/research/phase8-audio-engine.md` ("the research", cited as [A3] etc.) and `docs/research/phase8-bass-patterns.md` (walk-ups, built by P8-4b). Sibling specs: `P8-4-bass.md` (P8-4a profile, fretboard core; P8-4b walk-up candidates, picks, `ChordBeats`, `ChordAnchors`, sidecar schema 5), `P8-2-stage-map-and-passes.md` (played passes, `StagePasses`, rehearsal loop).

Ryan plays bass. He wants to hear a chord and its bass note at the pitch the band will sound, hear the 2-4 walk-up options for a change side by side and keep the one he likes, and practise a section or the whole song against bass, chords and click at tempo, at home or at rehearsal, through his laptop speakers or his Hotone Ampero II Stomp. None of it may ever make a sound during a gig.

The work is three build sessions in this one doc (section 16): **P8-6a** engine, sound bank, hear a chord, audition and pick; **P8-6b** play-along; **P8-6c** output device routing and polish. **P8-6a starts only after P8-4b has landed** (it needs `WalkUp.candidates`, the pick storage and the walk-up popover).

## Session rules (apply to every session)

- `cat` and `ls` are aliased to eza and can hang: use `command cat` / `command ls` or the Read/Grep/Glob tools. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-". Ignore `.build/` (except the sound bank folder this spec names inside it).
- Sibling workstreams may edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, and stage only your own hunks. Keep the tree compiling between steps.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget (R113): per step only targeted in-process suites (`swift test --filter <Suite>`); new UI behaviour gets in-process SegueUI tests (`Packages/SegueUI/Tests/SegueThemeTests`). **No new XCUITest in this workstream** (section 15). Exactly one offline-render smoke test touches real audio. At the end of each session ONE `make quick`, and ONE `make e2e-one` only for an existing UI test class the session changed (none expected). No `make gate`, no `make check`, no E2E retry loops, no scratch-worktree builds. Every build or test runs under `lockf -k .build/make.lock`.
- Before using any Apple API not already in the codebase (`AVAudioUnitSampler`, `scheduleMIDIEventListBlock`, `kAudioUnitSubType_PeakLimiter`, `enableManualRenderingMode`, CoreAudio device properties, the `speaker.wave.2` SF Symbol), run the `apple-api-check` skill.
- Manual steps for Ryan (the listening A/B in P8-6a step 1, the by-ear walk-up check in P8-6a, the Ampero check and low-spec measurement in P8-6c): prepare everything, hand the orchestrator the exact folder or action, and wait. Never pick a sound bank by reputation.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency.

## 1. Goal

In the editor and the library, clicking a chord plays it (piano or clean guitar, strummed or block) with its bass note underneath, at **sounding pitch** (capo, transpose and the song's display options already applied). In the walk-up popover (P8-4b), each candidate has a play button; Ryan can loop the change and switch between options (A/B) while it plays, then pick one, which saves P8-4b's pick. A **play-along** bar plays bass line, chords and click at tempo for a section (looping) or the whole song, in the editor, the library and the Rehearsal stage, never Live. Chords in ChordPro have no durations, so play-along estimates them from bar lines and `{time}`, falls back to a per-song rule ("one bar per chord" by default), and lets Ryan correct any chord's length on a timeline strip. Settings > Audio picks the output (the system output by default), quietly notes when it is a USB interface such as the Ampero, and sets the chord sound and volume.

**In scope:** a pure `Playback` core in SegueCore (note events, voicings, phrase building, the play-along timeline, the lookahead cursor) behind a SegueCore `SoundOutput` port; one shared `AVAudioEngine` with bass and chord samplers next to the existing rehearsal click, as an AVFoundation adapter in SegueUI; a bundled SF2 subset chosen by a listening A/B; the gig guard and its test; hear a chord; walk-up audition with A/B and pick; play-along in editor, library and Rehearsal; timing estimation and correction; Settings > Audio (output device, USB hint, chord voice, chord style, volume, test); accessibility; analytics; licence notices.

**Not in scope:** any sound in a Live show or on the Live stage (R161); click-to-hear on any stage (Rehearsal included; Rehearsal gets play-along only); loading the user's own SoundFont; AUv3 instrument hosting; more instruments (drums, strings); swing or groove feels; recording, input or the microphone (R132 stays); MIDI output to external gear (roadmap, separate research); any `.cho` change (timing and picks live in the sidecar); setting a song's `{tempo}` from the play-along tempo control.

## 2. Prior art

- **iReal Pro, Band-in-a-Box, Strum Machine** (research [P8 bass 4]): backing tracks from chord charts, with chord durations always explicit in their grid formats; Strum Machine and iReal randomise walks. Our charts are lyric-first ChordPro without durations, so play-along must estimate timing and let the user correct it (section 7). Verdict: build informed by them (their one-chord-per-bar grid is our default rule).
- **Logic Pro Session Player** (research): knobs over a generated part. We expose only voice toggles, tempo and timing; verdict: not adopted.
- **AudioKit 5** (MIT): `AppleSampler` wraps the same `AVAudioUnitSampler`; DunneAudioKit's SFZ sampler is the escape hatch if `AVAudioUnitSampler` ever proves inadequate [A1]. Verdict: build informed by it, no dependency.
- **The existing rehearsal click** (`AudioEngineClickOutput`, `RehearsalClick`): a proven lookahead pump on an injectable clock, behind a small port, structurally absent in a gig. This spec generalises it rather than adding a second subsystem [A0].

## 3. Terms

- **Sounding pitch**: written chord + capo + transpose, `DisplayTransform.concertSemitones` (`Packages/SegueCore/Sources/Editing/DisplayOptions.swift:106-110`), as P8-4 section 3 defines it; setlist slot overrides flow in the same way on the Rehearsal stage.
- **Voice**: `.bass`, `.chord`, `.click`. **Chord sound**: piano or clean guitar (Settings, R161). **Chord style**: strum (20-30 ms low to high) or block.
- **Change**: P8-4b's `ChordChange` (departing chord A, target B, candidates, pick).
- **Phrase**: a list of note events with onsets relative to its start, and a length.
- **Timeline**: the play-along's chords with onsets and lengths in beats, built by section 7.
- **Gig**: a Live show, `ShowKind.gig` (`Packages/SegueCore/Sources/Shows/ShowRecord.swift:62-68`), including a single-song Live session (R150).

## 4. Current code (with file:line)

- **Click port and pump**: `MetronomeClickOutput` (`schedule(_:beat:in:)`, `stop()`), `Packages/SegueUI/Sources/SegueUI/Live/MetronomeClick.swift:9-14`. `RehearsalClick` (`:21-96`): `init?(kind:clock:makeOutput:)` returns nil unless `.rehearsal` (`:38-46`); 300 ms lookahead, 100 ms pump task (`:23-26, 53-65, 77-95`); output made on the first click only (`:85-86`).
- **Click adapter**: `AudioEngineClickOutput` (`MetronomeClick.swift:102-179`): one `AVAudioEngine`, one `AVAudioPlayerNode`, two synthesized 40 ms sine ticks at 1760 / 1320 Hz (`:153-156, 161-178`), host-time scheduling on a private serial queue (`:111-118`), built lazily (`:128-159`), restarted when a device change stopped the engine (`:133-139`), follows the system default output.
- **Who makes the click**: `StageMetronome.init` builds `RehearsalClick(kind:clock:makeOutput:)` (`Live/StageMetronome.swift:41-51`); the factory is `LiveDependencies.makeClickOutput` (`Live/LiveDependencies.swift:20-24`), copied into `LiveSession.Context.makeClickOutput` (`Live/LiveSession.swift:37-40`) when the stage is presented (`App/AppModel+Shows.swift:331-356`, the call at `:350`).
- **Show state in the app**: `AppModel.live` (`App/AppModel.swift:164-170`); its `didSet` already gates other subsystems during a show (`dependencies.ai.gate.isShowRunning = live != nil`, the R65 pattern). The run ends in `finishRun` (`App/AppModel+Shows.swift:382-401`).
- **The gig test pattern**: `` `a gig never constructs the audio path, whatever the settings say` `` (`Packages/SegueUI/Tests/SegueThemeTests/StageMetronomeTests.swift:107-123`) starts a gig with the `MetronomeRun` harness and asserts the recording output factory was never called (`RecordingClickOutput` and `ClickOutputs`, `:254-305`).
- **Beat grid**: `MetronomeMeter` (`init(time:)`, `isCompound`, `pulses`; `Packages/SegueCore/Sources/Shows/Metronome.swift:9-43`), `MetronomeAccent` (`:45-50`), `MetronomeTrack` (bpm 20-400, `interval`, `time(ofBeat:)`, `nextBeat(atOrAfter:)`; `:70-130`). `Clock` (`Packages/SegueCore/Sources/Support/Clock.swift:9-12`). P8-2 adds `MetronomeTrack.barDuration` and `StageMetronome.countIn(at:)` (P8-2 section 11).
- **Previews with chords**: `SongSheetView` builds one text segment per chord (`Packages/SegueUI/Sources/SegueUI/Rendering/SongSheetView.swift:36-51, 320-344`); no chord has a click action today. Used by `SongPageView` (`Rendering/SongPageView.swift:39`) for the editor preview (`Editor/SongEditorView.swift:194`) and by the library's song pane (`Library/SongDetailPane.swift:231`). The diagram strip (`Diagrams/DiagramStrip.swift:9-113`); guitar and piano cells already use a tap for "customise" (`Diagrams/GuitarDiagramView.swift:88`, `PianoDiagramView.swift:67`).
- **Settings**: panes General, Appearance, Live, AI, Privacy, Data (`Settings/SegueSettingsView.swift:15-63`; P8-4a adds Instrument after Appearance); stores are `@Observable` classes over one UserDefaults JSON value (`Settings/LiveSettingsStore.swift:7-80`); Reset All Settings is `AppModel.resetAllSettings()` (`Settings/AppModel+Settings.swift:62-73`).
- **Stage keys**: the default table (`Packages/SegueCore/Sources/Shows/InputBindings.swift:236-266`). After P8-1/2/4a: `1`-`9`, `l` (loop), `b` (bass notes) are taken and `o` is freed; `p` is free.
- **Analytics**: `FeatureKey` (`Packages/SegueCore/Sources/Services/AnalyticsEvent.swift:205-234`), recorded as `.featureUsed(key, context)` daily per (feature, context); the catalogue is `docs/release/specs/WS3-services.md` row 8 (`:299, 314`); `ServicesVocabularyTests` pins the vocabulary.
- **Resources and notices**: SegueUI resources (`Packages/SegueUI/Package.swift:28-40`; licence texts under `App/Licenses/`, `.copy`); `THIRD_PARTY_NOTICES.md` (table + one section per component; `make docs-check` and `make site-check` enforce it against pins and `content/site.json` credits).
- **Entitlements**: `App/SegueAppStore.entitlements` has no audio input; output needs no entitlement [A0].
- **SegueCore modules**: one target per folder (`Packages/SegueCore/Package.swift:34-133`); `Shows` depends on `Library`, `Library` does not depend on `Shows`.
- **From P8-4 (must have landed)**: `InstrumentProfile` and `BassFretboard.suggested(_:home:tuning:)` (P8-4 sections 6.1, 7.1); `WalkUp.candidates`, `BassLine.changes`, `ChordChange`, `WalkUpPick`, `ChordAnchor` / `ChordAnchors.resolve`, `ChordBeats`, `BassPrefs.timing` in sidecar schema 5, `LibraryStore.updateBassPrefs`, the walk-up popover and Walk-ups list (P8-4 sections 8.2-8.11).

## 5. Decisions

1. **One engine, one clock.** A single `AVAudioEngine` per process (`AudioEngineHost`) owns the click player and two `AVAudioUnitSampler`s (bass, chords), so click, bass and chords share one host clock and one output device [A4, A6].
2. **A SegueCore port.** `SoundOutput` lives in the new pure SegueCore module `Playback`; the AVFoundation adapter (`AudioEngineSoundOutput`) and the engine host live in SegueUI next to `MetronomeClick.swift`. The port has one production adapter and a recording test double, the same justification the click port already has. `MetronomeClickOutput` stays as it is; its production adapter becomes a client of the shared host.
3. **All musical decisions are pure core code** (voicings, phrases, timeline, cursor), tested by asserting note events. The adapter only plays events.
4. **No sound in a gig, by construction (R161).** The only object that may hold a `SoundOutput` cannot be created while a gig runs, starting a gig tears the engine down, and the stage has no chord click targets (section 9).
5. **Sounding pitch only.** Every pitch is computed from concert chords (`DisplayTransform.concert`), so capo, transpose, capo mode and slot overrides never change what is heard.
6. **Editor and library for hearing and auditioning; Rehearsal adds play-along; Live gets nothing (R161).**
7. **The sound bank is chosen by ear** in P8-6a step 1 (section 12), SF2 only, at most 12 MB, licence notices shipped, per-voice gain measured (R161).
8. **Timing is estimated, then corrected by the user, and stored in the sidecar** (`bass.timing`, schema 5 from P8-4b), never in the `.cho` (section 7).
9. **Play-along plays what the chart shows**: the same walk-up (pick else top candidate) the bass view draws, so hearing and reading agree.

## 6. Core: the `Playback` module (SegueCore, pure)

New target `Playback` in `Packages/SegueCore/Package.swift` (dependencies: `MusicTheory`, `Diagrams`, `Editing`, `Library`, `Shows`, `Support`; added to the `SegueCore` product). Files under `Packages/SegueCore/Sources/Playback/`.

### 6.1 Events and the port (`SoundOutput.swift`)

```swift
public enum ChordSound: String, Sendable, Hashable, Codable, CaseIterable { case piano, cleanGuitar }
public enum ChordStyle: String, Sendable, Hashable, Codable, CaseIterable { case strum, block }

public enum Voice: Sendable, Hashable {
    case bass
    case chord
    case click(MetronomeAccent)
}

public struct NoteEvent: Sendable, Hashable {
    public var voice: Voice
    public var note: UInt8          // MIDI note, sounding pitch (ignored for .click)
    public var velocity: UInt8      // 1 ... 127
    public var onset: TimeInterval  // seconds from the phrase start
    public var duration: TimeInterval
}

public struct Phrase: Sendable, Hashable {
    public var events: [NoteEvent]  // sorted by onset
    public var length: TimeInterval // where a loop wraps
    init(beats: [BeatNote], tempo: Double, lengthBeats: Double?) // beat-placed notes
}

/// A note on the beat grid (voice, pitch, start beat, beats, velocity): how a generated
/// part such as a P8-7 fill is written before it meets a tempo (R166).
public struct BeatNote: Sendable, Hashable { ... }

public enum BassSound: String, Sendable, Hashable, Codable, CaseIterable { case finger, pick }

/// Where notes go: the audio engine in the app, a recorder in tests. Only a `SoundPlayer`
/// (SegueUI) ever holds one, and none exists while a gig runs (section 9).
public protocol SoundOutput: AnyObject, Sendable {
    /// Loads what the voices need (the sound bank) off the main thread. Makes no sound.
    func prepare(chord: ChordSound, bass: BassSound)
    /// Plays `events`, their onsets counted from `delay` seconds after now.
    func schedule(_ events: [NoteEvent], in delay: TimeInterval)
    /// Silences everything at once: pending events dropped, sounding notes released.
    func stopAll()
}
```

### 6.2 Voicings (`Voicing.swift`)

- `Voicing.chord(_ chord: ChordSymbol, sound: ChordSound, tuning: Tuning = .standard) -> [UInt8]` for a **concert** chord:
  - Piano: the chord's tones (`ChordFormula` / `ChordTones`) in close position, the root (not the slash bass; the bass voice plays that) placed at its lowest occurrence at or above C3 (MIDI 48), the other tones stacked upward, all inside C3 ... C5 (48 ... 72); extensions above the 7th dropped beyond four notes (keep root, third, seventh, then the colour tone).
  - Clean guitar: the first resolved standard-tuning shape for the concert chord from the Diagrams lookup (the same one the strip shows for capo 0), pitches = `tuning.strings[i] + fret` for every played string; no shape: the piano voicing an octave lower, clamped to E2 ... E5.
- `Voicing.bass(_ pitchClass: PitchClass, home: Int, tuning: Tuning) -> UInt8`: `BassFretboard.suggested(_:home:tuning:)` (P8-4 section 7.1) gives the position; MIDI = `tuning.strings[string] + fret` (E1 = 28 on EADG, B0 = 23 on BEADG). `home` comes from the concert key's tonic as on the mini neck; no key: the song's first bass note. Tuning: the Settings > Instrument strings and tuning for anyone, with or without "I play bass", as the mini neck uses them (R163); EADG only without a profile.
- Pinned rows: section 15.1.

### 6.3 Phrases (`PhraseBuilder.swift`)

- `PhraseBuilder.chord(_ chord:, sound:, style:, bass:) -> Phrase`: chord notes at onset 0 (block) or 25 ms apart low to high (strum), velocity 80, duration 1.6 s; the bass note at onset 0, velocity 96, duration 1.6 s; length 1.6 s.
- `PhraseBuilder.bassNote(_:)`: the bass note alone, 1.2 s.
- `PhraseBuilder.audition(_ change: ChordChange, candidate: WalkUpCandidate?, tempo: Double?, meter: MetronomeMeter, voices: PlaybackVoices) -> Phrase` [A3] (`PlaybackVoices` = chord sound, style and `BassPlacement`): two bars. Bar 1: chord A struck on beat 1; bass A's note on beat 1 (and on the bar's middle strong beat in 4/4, unless a walk note takes that beat); the candidate's notes one per beat on the **last** beats of bar 1 (eighths on the last beat when there are more notes than free beats). Bar 2: chord B and bass B on beat 1, held to the bar's end. `candidate == nil` (or `hold`) plays the change with no walk-up. Tempo: the song's `{tempo}`, else 90. No click. Pitches of the walk-up notes: `b + offsets`, each placed in the octave nearest the previous bass note (a walk is stepwise), and after a walk bass B lands a step from the last walk note (so it may sit an octave from `Voicing.bass`); with no walk-up bass B is `Voicing.bass`.
- `PhraseBuilder.playAlong(_ timeline: PlayAlongTimeline, voices: Set<VoiceToggle>, sound:, style:, countIn: Bool) -> Phrase` (section 7.5).

All builders use `MetronomeTrack`'s beat arithmetic (`interval`, compound meters in dotted quarters, R118) so notes and the click share one beat model.

### 6.4 The cursor (`PhraseCursor.swift`)

The pure half of `RehearsalClick.pump`, generalised to phrases: `PhraseCursor(phrase:start:loop:)` with `mutating func due(at now: Date, lookahead: TimeInterval) -> [(NoteEvent, delay: TimeInterval)]` returns every event (across loop wraps) whose time falls within `lookahead` and was not handed out yet, with its delay from `now`; `swap(to:)` replaces the phrase at the next wrap not yet handed out (for A/B and for timing edits during play-along). Tested with a scripted clock; the UI pump task only calls it (section 8.4).

## 7. The play-along timing model

ChordPro has no chord durations (P8-4 section 1). Play-along needs one for every chord, so each chord's length in beats comes from the first layer that has an answer:

### 7.1 Layers

1. **The user's correction** for this chord: an override in the song's sidecar (`bass.timing.chords`, 7.3), anchored like a walk-up pick (P8-4 section 8.11).
2. **The chart's own marks**: P8-4b's `ChordBeats.estimate` with source `barLines` or `beatMarks` (bar lines `|`, `[|]`, `%` bars, and `/` or `.` beat marks on the chord's line; P8-4 section 8.5). Beats per bar from `{time}` (`Metadata.pulses(ofTime:)`), else 4.
3. **The song's timing rule** (`bass.timing.rule`, default **one bar per chord**):
   - `{"each": "halfBar" | "bar" | "twoBars"}`: every chord lasts that long.
   - `{"beats": n}` (1 ... 16): every chord lasts `n` beats.
   - `{"line": n}` (1, 2 or 4 bars): each lyric line lasts `n` bars, shared evenly by its chords: line beats `L = n x beatsPerBar`; with `k` chords, each gets `L / k` rounded down to whole beats and the remainder goes one beat at a time to the first chords. "Even distribution per lyric line."
   P8-4b's `meterLine` estimate (one chord on a line with `{time}` = one bar) is the "each bar" rule and is not a separate layer here.

Then, whatever the layers gave:
- **A lyric line with no chords** inside the range extends the chord before it, by one bar under an "each" or "beats" rule and by `n` bars under a "line" rule (the previous chord keeps ringing under those words).
- **`N.C.`** is a chord with no notes (silence for its length; the click continues). Unknown chords are skipped with no length (the timeline strip shows them greyed).
- **The range is rounded up to whole bars** by lengthening its last chord, so a loop wraps on a downbeat.
- Every chord gets at least 1 beat; at most 32.

### 7.2 Which chords, in which order

- **Editor and library:** the song as written (`RenderModel.sections`), `{chorus}` stubs written out with their target's chords (as on stage, R147). The range is the whole song, one section (`SongSectionUnit`, P8-4 section 4), or "from this section to the end".
- **Rehearsal stage:** P8-2's played passes (the slot's arrangement and show modes; a Skip pass contributes nothing; Chords-only and First-line-only passes still play their full chords, since the band plays them), with the slot's key and capo.
- Overrides and estimates always resolve against the song's own sections through each pass's origin index, so one correction applies to every pass of that section.

### 7.3 Storage (sidecar `bass.timing`, schema 5 from P8-4b)

P8-4b defines and preserves the field (P8-4 section 8.10); P8-6b fills it:

```json
"timing": {
  "rule": {"line": 2},
  "chords": [
    {"section": "Chorus", "occurrence": 1, "fp": "9f8e7d6c", "chord": 0, "from": "C", "beats": 2}
  ]
}
```

- `rule` absent = one bar per chord. `TimingRule` decodes leniently: an unknown shape reads as absent.
- `chords`: one override per chord anchor (`ChordAnchor`: section anchor, `fp`, ordinal among the section's `.chord` chords, written bass), resolved by `ChordAnchors.resolve` exactly as picks (P8-4 section 8.11): re-anchored when unambiguous, otherwise **unmatched**, then ignored (the layers below apply), kept in the sidecar, and listed in the timeline strip's menu ("1 timing change no longer matches" with Remove).
- Writes go through `LibraryStore.updateBassPrefs` (sidecar only), debounced 0.5 s while dragging, one undo step per gesture in the editor.

### 7.4 How the user corrects timing

The play-along bar (section 10.3) has a **timeline strip** for the chosen range:
- One block per chord, width proportional to its beats, labelled with what the chart row shows (the chord, or the bass note in the bass-note view), thin bar ticks behind, and a playhead while playing. The block's edge style shows where its length came from: solid (chart marks), dashed (the song's rule), a small filled dot (your correction).
- **Change one chord**: click a block to select it, then the "Beats" stepper (- / +), or type a digit 1-9 for that many beats, or drag its right edge (snaps to beats; the following chords move, the total grows or shrinks). Delete (or "Use the song's rule") removes the correction.
- **Change the rule**: the "Timing" menu: "One chord per half bar / per bar / per two bars", "Each line lasts 1 / 2 / 4 bars", "Every chord lasts N beats...", and "Reset corrections in this section / in the song".
- Changes during playback apply from the next bar (the cursor swaps the phrase, 6.4); the highlighted chord in the preview follows the playhead, so a wrong length is visible as well as audible.
- No lyric-length heuristic (placing chords by syllable position): the research rated it fragile [A7 Q4], and the user correction covers what the rules miss.

### 7.5 What plays

`PlayAlongTimeline.build(sections:origins:range:estimates:timing:meter:changes:) -> PlayAlongTimeline` (pure) gives `[TimedChord { position, onsetBeat, beats, chord (concert), bass, approach: [UInt8] }]` and `totalBeats`. `PhraseBuilder.playAlong` turns it into events:
- **Bass** (toggle): the chord's bass note on its first beat and again on each strong beat it covers (4/4: beats 1 and 3; 3/4: beat 1; compound: each dotted-quarter pulse; 2/4: beat 1), each held to the next strong beat; the walk-up into the next chord on the last beats (one note per beat, eighths when squeezed), taken from P8-4b's `ChordChange.shown` (the pick, else the top candidate) when walk-ups are on, so play-along sounds like the chart reads (decision 9). The bar's "Walk-ups" toggle defaults to the charts' setting.
- **Chords** (toggle): struck at the chord's onset in the chosen sound and style, re-struck on each later downbeat it covers, held.
- **Click** (toggle): every beat, beat 1 accented, through the existing tick sounds.
- **Count-in**: one bar of click before the first chord (always, even with the click toggle off).
- **Loop**: a section loops seamlessly in the editor and library (count-in only at the start); on the Rehearsal stage each wrap gets R148's one-bar count-in (10.4).
- **Tempo**: the song's `{tempo}`, else 90 with the hint "No tempo in this song: playing at 90". A session tempo control (40 ... 240) with 50% / 75% / 100% buttons for practice; never saved, never written to `{tempo}`.

## 8. Engine and adapter (SegueUI, macOS)

New folder `Packages/SegueUI/Sources/SegueUI/Audio/`.

### 8.1 `AudioEngineHost`

- One per process, owned by `AppDependencies` (`App/AppModel.swift:14`), injected wherever an output is made. Everything runs on one private serial queue, as the click does today (`MetronomeClick.swift:103-107`).
- Built lazily on the first sound: `AVAudioEngine`; the click `AVAudioPlayerNode` with the existing tick buffers (moved here unchanged from `MetronomeClick.swift:146-178`); a bass `AVAudioUnitSampler` and a chord `AVAudioUnitSampler`, each connected with `format: nil` so the mixer converts any device rate [A5]; per-voice gain (`SoundBank.gain`, 12.4); the main mixer; a peak limiter (`AVAudioUnitEffect` with `kAudioUnitSubType_PeakLimiter`; check with `apple-api-check`) before the output; `mainMixerNode.outputVolume` = the Settings volume.
- Loads the bundled `SegueSounds.sf2` with `loadSoundBankInstrument(at:program:bankMSB:bankLSB:)` off the main thread (bass program from the A/B, chord program for the current chord sound; reloaded on change). Fallback order when the load fails: the system `gs_instruments.dls` loaded in place (never bundled) [A1], then the sampler's built-in sine voice; each fallback records `errorOccurred(.soundBankLoad)` once per launch. `.sf3` is never loaded (it crashed the probe [A1]).
- Output device: before `start()`, sets `kAudioOutputUnitProperty_CurrentDevice` on `engine.outputNode.audioUnit` to the chosen device (section 11), else leaves the system default.
- Device and configuration changes: on `AVAudioEngineConfigurationChange`, anything playing **stops and says so** ("Stopped: the audio output changed") and the engine is rebuilt lazily on the next sound; a loop never resumes by itself [A5].
- `block()` / `unblock()`: while blocked (a gig, section 9) `build()` refuses and every schedule is dropped; `block()` also stops and releases the engine and its nodes.

### 8.2 Adapters over the host

- `AudioEngineSoundOutput: SoundOutput`: `.bass` and `.chord` events become MIDI note-on / note-off on the samplers, `.click` events schedule the tick buffers on the player at host time (as today).
- `AudioEngineClickOutput: MetronomeClickOutput` keeps its public API and behaviour but schedules on the shared host's player, so a rehearsal's click and a play-along are on one clock and one device. `LiveDependencies.makeClickOutput` (`Live/LiveDependencies.swift:22-24`) passes the host.

### 8.3 Scheduling notes at sample accuracy (probe first)

The research recommends `auAudioUnit.scheduleMIDIEventListBlock` with sample-time stamps fed by the lookahead pump [A1 "Scheduling"]. **P8-6a step 2 probes** whether `AVAudioUnitSampler` honours future absolute sample times 50-300 ms ahead (render offline, measure onsets). If it does: convert each event's host-time onset to the engine's sample time (via `outputNode.lastRenderTime` and the device's sample rate) and stamp it. If it does not: a tighter pump (25 ms tick, 60 ms lookahead) sending events stamped `AUEventSampleTimeImmediate` plus a frame offset within the next render cycle. **Outcome (P8-6a step 2):** the sampler honours future absolute sample times (under 0.5 ms error at 50-300 ms ahead) when they are stamped in the sampler's own rate (44.1 kHz with `format: nil`), but events handed to it ahead of time cannot be withdrawn (`reset`, the AU's reset and all-notes-off all leave them sounding). So the adapter keeps a per-sampler queue that a pre-render observer (`token(byAddingRenderObserver:)`) drains in the render cycle each event falls in, stamping its frame offset: sample-accurate and cancellable (`stopAll` empties the queue and sends all-notes-off). Either way the tolerance is one output buffer (about 11 ms at 512 frames, 48 kHz [A1 "Latency"]), checked by the smoke test (15.3). Record the outcome in the step's commit message.

### 8.4 `SoundPlayer` (the only holder of an output)

`@MainActor final class SoundPlayer` (`Audio/SoundPlayer.swift`): `init?(gate: SoundGate, makeOutput: @escaping @MainActor () -> any SoundOutput, clock: any Clock, settings: AudioSettingsStore)`. It owns the output (made on the first sound), a `PhraseCursor` and the 100 ms pump task (the `RehearsalClick` loop shape, `MetronomeClick.swift:53-95`), and exposes `play(_ phrase:)`, `loop(_ phrase:)`, `swapAtNextWrap(_:)`, `stop()`, `isPlaying`, `position` (for the playhead). Playing anything stops what was playing (one sound at a time).

## 9. Stage safety: no sound in a gig

Removing the capability, not stating a policy:

1. `SoundGate` (`Audio/SoundGate.swift`, `@MainActor @Observable`, `gigRunning: Bool`). `AppModel.live`'s `didSet` (`App/AppModel.swift:164-170`) sets `soundGate.gigRunning = (live?.kind == .gig)`, next to the existing `ai.gate.isShowRunning` line.
2. `SoundPlayer.init?` returns nil while `gate.gigRunning`. `AppModel.soundPlayer` is a lazily made optional; when the gate turns on, `AppModel` calls `soundPlayer?.stop()`, drops it, and calls `AudioEngineHost.block()`, **before** the stage window is presented (`presentStage`, `App/AppModel+Shows.swift:331-356`). When the gig ends (`finishRun`, `:382-401`) the host is unblocked; nothing restarts by itself.
3. The stage's play-along owner `StagePlayAlong` (`Live/StagePlayAlong.swift`) has `init?(kind: ShowKind, ...)` that returns nil unless `.rehearsal` (the `RehearsalClick` pattern, `MetronomeClick.swift:38-46`), so a gig `LiveSession` has `playAlong == nil` and no code path to a `SoundPlayer`.
4. The stage has **no** chord click targets at all, in Live or Rehearsal (research risk 2). `p` in a gig changes nothing and flashes "Play-along works in rehearsals" (like P8-2's `L`).
5. Every sound control outside the stage (preview chord clicks, popover play buttons, the play-along bar, Settings "Test") is disabled while the gate is on, with the help "Sound is off during a show", so nothing looks clickable and silently fails.
6. A rehearsal may play along; starting any stage session stops editor or library sound first.

**The test that proves it** (`SoundSafetyTests`, in-process, `SegueThemeTests`, built on `StageMetronomeTests`' `MetronomeRun` harness with a `RecordingSoundOutput` factory that counts creations):

- `SoundPlayer(gate:)` is nil exactly when `gigRunning`, and `StagePlayAlong(kind:)` is nil exactly for `.gig`, via an exhaustive `switch` over `ShowKind` in the test so a new kind must decide.
- Start a gig (setlist and single-song Live): drive a library preview chord click, the walk-up popover's play, the editor's Play along, Settings "Test", and `p` on the stage: the factory count stays 0, no events are recorded, the host stays blocked, `p` only flashes.
- With an editor play-along running, start a gig: `stopAll` is recorded before the stage is presented, the `SoundPlayer` and output are released (weak references nil), and the host is blocked.
- End the gig: one chord click plays again (factory called once).
- The existing `a gig never constructs the audio path` test (`StageMetronomeTests.swift:107-123`) also asserts `live.playAlong == nil`.

## 10. Features

### 10.1 Hear a chord (P8-6a)

- **Editor text-mode preview and library preview:** clicking a chord unit plays `PhraseBuilder.chord` for that chord at sounding pitch with its bass note (the slash bass, else the root), in the Settings chord sound and style. Pointer cursor and a subtle hover tint on chord units; no other visual change. A new click stops the previous chord. Built in `SongSheetView`'s chord segment (`Rendering/SongSheetView.swift:334-344`) through an `onChord` action the preview owner passes in (nil on stage, so the stage cannot get one).
- **Visual canvas:** a plain click keeps editing the chord pill as today; **⌥-click** plays it.
- **Bass fretboard strip** (P8-4b cells): a click plays the cell's bass note at the suggested position's pitch, ⌥-click the chord with it. Guitar and piano cells keep their customise tap; ⌥-click plays.
- With the bass-note view on, the bass note is drawn in the chord row; the sound is the same (chord plus bass), since a bassist wants to hear the harmony over the note.

### 10.2 Audition walk-ups, A/B and pick (P8-6a)

In P8-4b's walk-up popover (P8-4 section 8.9), which is unchanged otherwise:
- Each candidate row and the "Nothing here" row gain a **play button** (▶, `segue.walkUp.play.<letter>`). Playing a row plays `PhraseBuilder.audition` for that candidate once (two bars).
- **Loop** switch in the popover header (default off): the selected row's phrase repeats. **A/B**: while looping, moving the selection (↑/↓, a click, or the letter keys A-D) switches the candidate **at the next phrase start** (`swapAtNextWrap`), so the comparison is seamless. Space plays or stops the selected row.
- **Pick**: Return, or the row's "Use this" button, saves P8-4b's pick (`LibraryStore.updateBassPrefs`), stops the sound and closes the popover. Playing never saves by itself.
- Playing B while A sounds stops A at once (`stopAll`, then B).
- The Walk-ups list (P8-4 section 8.9) gets a ▶ per change row that plays the shown walk-up.
- **By-ear walk-up check** (manual step for Ryan, R162 Q5): P8-4b has no owner-review CSV gate, so walk-ups are first judged here. Once P8-6a lands, Ryan opens his own songs with walk-ups at Every change, plays the changes through the popover and the Walk-ups list, and notes any walk-up that sounds wrong or should be silent; each becomes a P8-4b golden case and any tuning changes only `WalkUpWeights.standard` (P8-4 section 8.13 item 3). The session prepares the check (which songs, how to open them) and hands it to the orchestrator for Ryan; it does not judge walk-ups itself.

### 10.3 Play along in the editor and library (P8-6b)

A collapsible **Play along** bar under the preview (editor text mode and visual mode; library song pane), closed by default, opened by a toolbar button "Play Along" (`segue.playAlong.toggle`) or Song > Play Along (⇧⌘P; check the clash table):
- Transport: Play / Stop (Space while the bar has focus; ⌥Space from anywhere in the window), the range menu (Whole song, each section by name, "From <section> to the end"), Loop (on by default for a section, off for the whole song).
- Voices: Bass, Chords, Click, Walk-ups toggles (remembered in `AudioSettings`; Walk-ups defaults to the charts' setting).
- Tempo: the value, -/+ and 50% / 75% / 100%.
- The timeline strip and Timing menu (7.4).
- The preview highlights the chord unit at the playhead (a `cue` underline), and scrolls to keep it in view; with Reduce Motion the scroll is instant.
- Closing the bar, switching song, entering a show, or quitting stops playback.

### 10.4 Play along in Rehearsal (P8-6b)

- New `LiveCommand.togglePlayAlong`, default key `p`, scope `.viewport`, `repeatsWhenHeld` false, title "Play Along (Rehearsal)", in the "Sections" help group P8-2 adds; `KeyHelp.statusHints` gains "P play along" in a rehearsal. Works in setlist and single-song rehearsals (R150, R156).
- `p` starts the current song's played passes **from the current pass**, with the slot's key and capo, voices from `AudioSettings`. With P8-2's loop on (`L`), it plays the looped pass and loops it.
- **The audio is the clock while playing:** auto-scroll pauses, and the stage scrolls so the line holding the chord at the playhead sits at P8-2's reading line (`StagePasses.readLine`); an 0.25 s ease, instant with Reduce Motion. P8-2's loop wrap is then scheduled from the audio timeline (the phrase end) instead of `AutoScroller.instant(reaching:)`, with R148's one-bar count-in (pips shown, click sounding).
- A jump (map chip or 1-9) while playing restarts play-along at the start of that pass on the next downbeat. Song change, break, End, `p` again, or `L` off (when it was looping) stop it; auto-scroll returns to its state before.
- The metronome pips follow the play-along's beat grid while it plays (one grid, decision 1); the rehearsal click (`K`) is muted while play-along's own click toggle is on, so there is never a double click.
- The header shows a "♪ Playing along" pill (`segue.live.playAlong`) before P8-2's loop pill.

## 11. Settings > Audio (P8-6a for sound, style and volume; P8-6c for the output)

New tab after Instrument: `Tab("Audio", systemImage: "speaker.wave.2", value: Pane.audio)` (check the symbol), a grouped `Form` like the other panes, pane id `AccessibilityID.settingsPane("audio")`. Store: `AudioSettingsStore` (`Settings/AudioSettingsStore.swift`, `@MainActor @Observable`, one JSON value at UserDefaults key `audio.settings`, lenient per-field decode, `resetToDefaults()`), owned by `AppModel` beside `liveSettings`; Reset All Settings includes it (`Settings/AppModel+Settings.swift:62-73`, update its doc comment).

- **Play through** (P8-6c): a pop-up "System output (<current default's name>)" (default) followed by every output device by name; stored by device UID. A stored device that is not connected shows "<name> (not connected)" and sound uses the system output until it returns. Identifier `segue.settings.audio.output`.
- **USB hint** (P8-6c): when the device sound will actually use has a USB transport, a quiet `SettingsNote` under the picker: "<Name> is a USB audio interface. Sound goes wherever it is connected, such as an amp or PA." This note is the only USB hint (R162 Q10): no status line or dialog when sound plays. Nothing is shown for built-in, Bluetooth or HDMI outputs.
- **Chord sound**: segmented Piano / Clean guitar (R161; default Piano). `segue.settings.audio.chordSound`.
- **Chords play as**: segmented Strum / Block (default Strum). `segue.settings.audio.chordStyle`.
- **Bass**: segmented Finger / Pick (default Finger; R166, the owner's A/B). `segue.settings.audio.bassSound`.
- **Volume**: slider 0-100% (default 70%) with speaker glyphs, applied to `outputVolume`. `segue.settings.audio.volume`.
- **Test**: plays a G chord with its bass through the chosen output (disabled during a gig).
- Pane note: "Sound plays in the editor, the library and rehearsals. It never plays during a show."

Device listing is a small SegueUI port, `AudioDeviceDirectory` (`outputs()`, `defaultOutput()`, `transport(of:)`, change notifications), with a CoreAudio adapter (`kAudioHardwarePropertyDevices`, output stream check, `kAudioDevicePropertyDeviceUID`, `kAudioObjectPropertyName`, `kAudioDevicePropertyTransportType`, a `kAudioHardwarePropertyDefaultOutputDevice` listener; check each with `apple-api-check`) and a fake in tests. Device names are never sent anywhere (analytics records only that a non-default output was chosen).

## 12. The sound bank (P8-6a step 1, a listening A/B)

1. **Download** (never committed) into `.build/soundbank/`: GeneralUser GS 2.0.3 (https://github.com/mrbumpy409/GeneralUser-GS) and FluidR3_GM (Debian `fluid-soundfont` 3.1, https://sources.debian.org/data/main/f/fluid-soundfont/3.1-5.3/). Record each file's URL and SHA-256 in `scripts/soundbank/sources.txt`.
2. **Render the A/B**: `scripts/soundbank/render-ab.swift` (the research's offline-render probe made reproducible; run with the toolchain under mise) renders the same material from each bank to `.build/soundbank/ab/`: **bass** (finger 33 and pick 34) playing a G - C - D - G line with two walk-ups at 96 BPM; **piano** (0) the progression G, C/G, D/F#, Em, Am7, D7, G; **clean guitar** (27) the same progression strummed; and a **mix** (bass + piano + click). Files are blind-labelled X and Y per voice (`bass-X.m4a`, `bass-Y.m4a`, ...), loudness-matched per voice so level does not bias the choice, with the key in `key.txt`.
3. **Ryan listens and chooses per voice** (manual step: hand over the folder and wait): finger and/or pick bass, piano, clean guitar, each from either bank. The bundle must stay at or under **12 MB** (the research measured about 3 MB for an all-GeneralUser set and 6-11 MB with Fluid's bass or piano).
4. **Extract** the chosen presets (with their instruments and samples) into one SF2, `Packages/SegueUI/Sources/SegueUI/Audio/Sounds/SegueSounds.sf2`, with `scripts/soundbank/extract.py` (stdlib-only Python under `uv run`; a minimal RIFF/SF2 reader and writer) so the file is reproducible from the recorded downloads; programs kept (0 piano, 27 guitar, 33/34 bass, bank 0), the INFO chunk credits the source banks. Add `.copy("Audio/Sounds")` to SegueUI's resources (`Packages/SegueUI/Package.swift:28-40`).
5. **Licences**: the chosen banks' texts as `App/Licenses/GeneralUserGS.txt` (the License v2.0 text verbatim) and/or `App/Licenses/FluidR3.txt` (MIT, its COPYING); rows and sections in `THIRD_PARTY_NOTICES.md` (a "Sounds" row group with version and source); the `credits` in `content/site.json` so the website acknowledgements carry them (`make site-check`). Never in the About window (house rule).
**Outcome (2026-10-30, R166).** Ryan's blind A/B picked FluidR3_GM for piano, clean guitar and pick bass, and GeneralUser GS for finger bass on its own but FluidR3 in the full mix; he then chose FluidR3's finger bass too, so **every voice is FluidR3_GM** (programs 0, 27, 33, 34; 11.6 MB) and GeneralUser GS is not shipped. The bass voice defaults to finger bass (33); pick bass (34) is selectable in Settings > Audio ("Bass", Finger / Pick). The A/B was rendered from extracted subsets with `render-ab.swift` into the session scratchpad rather than `.build/soundbank/ab/`.

6. **Per-voice gain** (`Audio/SoundBank.swift`): render each chosen voice offline, a velocity-100 four-note chord for the chord voices and single notes for bass, and set `SoundBank.gain` (dB per voice) so each voice peaks at or below -6 dBFS and all three together at or below -1 dBFS; record the measured peaks in a comment. The research measured GeneralUser's piano peaking at 2.90 (clipping) uncorrected [A1]. The limiter is a safety net, not the gain stage.
7. `SoundBankBundleTests` (cheap, no rendering): the file is at most 12 MB, is SF2 (RIFF `sfbk`, `ifil` major version 2, so never SF3), and holds every program `SoundBank` names.

## 13. Accessibility

- Chord units in the previews: each gets an accessibility action "Play chord" (and is still read as before: "G", "B, bass of G slash B"); VoiceOver users trigger it with the actions rotor. Hover tint is decoration only.
- Popover: the play buttons are labelled "Play option A, A, B into C"; the Loop switch "Loop this change"; selection changes while looping announce "Now playing option B" (one announcement, not per bar); "Use this" picks.
- Play-along bar: every control labelled; the transport has the value "Playing Chorus 2, bar 3 of 8" (read on focus, never auto-announced); timeline blocks are adjustable elements ("G, 4 beats, from the chart"; increment / decrement change beats; "your change" when overridden); the range and Timing menus are standard menus.
- Rehearsal: the "Playing along" pill is text; the follow scroll is instant with Reduce Motion; nothing relies on sound alone (the playhead and pips are visible).
- Settings: standard controls; the USB note is plain text under the picker, read with it.
- Keyboard: everything above works without a pointer (Space, ⌥Space, ↑/↓, A-D, Return, digits on the strip, Delete).

## 14. Analytics (non-PII, closed vocabulary)

`FeatureKey` (`Services/AnalyticsEvent.swift:205-234`) gains, recorded with the existing `.featureUsed(key, context)` at view-model entry points (never in views), daily per (feature, context):
- `hearChord` (`.editor`, `.library`): a chord played.
- `walkUpAudition` (`.editor`, `.library`): a candidate played in the popover.
- `playAlong` (`.editor`, `.library`, `.stage`): play-along started (`.stage` only ever from a rehearsal).
- `playAlongTiming` (`.editor`, `.library`): a timing rule or chord correction changed.
- `audioOutput` (`.settings`): a non-default output chosen (never its name).
- `chordSoundGuitar` (`.settings`): the chord sound set to clean guitar.

Plus `ErrorCode.soundBankLoad` on the existing `errorOccurred` row when the bundled bank fails and a fallback is used. Update `ServicesVocabularyTests` and `docs/release/specs/WS3-services.md` (row 8's list; the error codes list) in the same change.

## 15. Tests (R113 budget)

### 15.1 Core (in-process, `Packages/SegueCore/Tests/SegueCoreTests`, table-driven)

- **`VoicingTests`**: chord + key + capo + transpose + sound -> MIDI notes. Piano: `[G]`, no capo -> 55 59 62 (G3 B3 D4); `[G]` capo 2 -> 57 61 64 (sounds A); `[Cmaj7]` -> 48 52 55 59; `[F#m7b5]` -> 54 57 60 64; `[G/B]` -> 55 59 62 (no B in the chord voice). Guitar: `[G]` standard -> 43 47 50 55 59 67; `[C]` -> 48 52 55 60 64. Bass (EADG): key G, `[G]` -> 31 (E string fret 3); `[G/B]` -> 35 (A string fret 2); key G capo 2, `[G]` -> 33 (sounds A, E string fret 5); BEADG key D, `[D]` -> 26 (B string fret 3); no key -> home from the first bass note.
- **`PhraseBuilderTests`**: `chord` block onsets all 0, strum onsets 0, 0.025, 0.05 ...; bass at 0; `audition` G -> C in G at 90 BPM 4/4 with `A B`: G chord and bass G at 0.0, walk notes A at 1.333 (beat 3, replacing the beat-3 root) and B at 2.0 (beat 4), C chord and bass C at 2.667, length 5.333; with no walk-up the bass plays G at 0.0 and 1.333; three notes in 4/4 -> beats 2, 3, 4; in 3/4 two notes -> beats 2 and 3; 6/8 (two pulses) two notes -> eighths on the last pulse; `hold` -> no walk notes; walk-up octave placement stays stepwise across E1.
- **`PlayAlongTimelineTests`**: layer order (a correction beats chart marks beats the rule); each rule (`each` half bar / bar / two bars, `beats` 3, `line` 2 with 1, 2, 3 and 5 chords); a chord-less lyric line extends the previous chord; `N.C.` is silent with length; unknown chords are skipped; rounding to whole bars; a `{chorus}` stub written out; played passes with a Skip pass and a Chords-only pass; one correction applies to every pass of its section; an unmatched correction is ignored; walk-up notes come from `ChordChange.shown` and sit on the last beats; total beats and loop length.
- **`PhraseCursorTests`** (scripted clock): hands out each event once within the lookahead, in order, across a loop wrap; `swap(to:at:)` takes effect exactly at the next wrap; nothing is due after the phrase ends without a loop; count-in events precede the first chord by one bar.

### 15.2 SegueUI (in-process, `Packages/SegueUI/Tests/SegueThemeTests`, with `RecordingSoundOutput`)

- **`SoundSafetyTests`**: section 9.
- **`HearChordTests`**: a click on a preview chord schedules chord and bass events at sounding pitch (the 15.1 rows through a real editor view model); a second click stops the first; the visual canvas plain click schedules nothing and ⌥-click plays; a bass strip cell plays its bass note; the library preview plays the song's own options; analytics `hearChord`.
- **`WalkUpAuditionTests`**: ▶ on row B schedules B's phrase; playing A then B records `stopAll` between; looping and moving the selection swaps at the next phrase start (scripted clock); Return writes the pick through `updateBassPrefs` (sidecar only, `.cho` unchanged) and stops; Space toggles; analytics `walkUpAudition`.
- **`PlayAlongTests`**: Play schedules count-in then events; voice toggles filter events; a section loops seamlessly, the whole song stops at the end; a strip edit writes `bass.timing` and the next bar uses it; the rule menu; undo restores a correction; tempo buttons scale onsets; switching song stops; the preview highlight follows the playhead.
- **`StagePlayAlongTests`**: `p` in a rehearsal plays the played passes from the current pass with the slot's key; with `L` it loops the pass and each wrap has the one-bar count-in from the audio timeline; auto-scroll pauses and the follow scroll puts the playhead's line at the reading line; a jump restarts at that pass; song change and End stop; `K` is muted while play-along clicks; key help and status hints list `p`; `p` in a gig only flashes (with 9).
- **`AudioSettingsStoreTests`**: defaults, persist, lenient decode, Reset All Settings; with a fake `AudioDeviceDirectory`: a stored UID that is gone reads "(not connected)" and the host uses the default; the USB note shows only for a USB transport.

### 15.3 The one audio smoke test

**`SoundRenderSmokeTests`** (SegueThemeTests, one test): the real `AudioEngineHost` in offline manual rendering (`enableManualRenderingMode(.offline, ...)`, `renderOffline`) with the bundled bank renders a phrase "bass G1 at 0.10 s, chord C at 0.50 s, click at 0.90 s"; asserts silence (peak below -60 dBFS) before 0.10 s, non-silence in each onset's 0-150 ms window, an onset error within one buffer, and no sample at or above 1.0. Under 2 s. Never compares waveforms. Plus `SoundBankBundleTests` (12.7), which reads the file and renders nothing.

### 15.4 No new UI test

All behaviour above is proven in-process. No new XCUITest class (R113: in-process first; the house rule against blanket E2E). At each session's end: one `make quick`; `make e2e-one` only for an existing class the session changed (none is expected; if P8-6b's `p` key changes what `SegueStageMapE2ETests` sees, run that one class once).

## 16. Sessions and steps

**P8-6a - engine, sound bank, hear a chord, audition and pick** (after **P8-4b** has landed)

1. Sound bank A/B (section 12, steps 1-3): download, render, hand `.build/soundbank/ab/` to the orchestrator for Ryan, wait for his choice. Meanwhile do step 2.
2. `Playback` core: the module, `SoundOutput`, `NoteEvent`, `Voicing`, `PhraseBuilder.chord` / `bassNote` / `audition`, `PhraseCursor`. Plus the 8.3 scheduling probe (scratch, not committed; outcome in the commit message). Suites: `VoicingTests`, `PhraseBuilderTests`, `PhraseCursorTests`.
3. Engine: `AudioEngineHost`, `AudioEngineSoundOutput`, `AudioEngineClickOutput` over the host (the rehearsal click behaves exactly as before: `StageMetronomeTests` green), extraction (12.4), licences and notices (12.5), gain (12.6), fallbacks. Suites: `SoundBankBundleTests`, `SoundRenderSmokeTests`, `StageMetronomeTests`.
4. Safety: `SoundGate`, `SoundPlayer`, the `AppModel.live` hook, host block/unblock, disabled affordances. Suite: `SoundSafetyTests`.
5. Hear a chord (10.1). Suite: `HearChordTests`.
6. Audition, A/B and pick in P8-4b's popover and list (10.2). Suite: `WalkUpAuditionTests`.
7. Settings > Audio without the output picker (chord sound, style, volume, Test, note), Reset All Settings, analytics keys. Suites: `AudioSettingsStoreTests`, `ServicesVocabularyTests`.
8. One `make quick`. Hand Ryan the by-ear walk-up check (10.2, last bullet; R162 Q5): a manual step for Ryan, say so explicitly in the hand-off.

**P8-6b - play-along** (after P8-6a, and after P8-2 has landed its passes and loop)

9. Timing core: `TimingRule`, override resolution through `ChordAnchors`, `PlayAlongTimeline`, `PhraseBuilder.playAlong`. Suites: `PlayAlongTimelineTests`, `PhraseBuilderTests`.
10. Editor and library play-along bar, timeline strip and corrections, sidecar writes, undo, highlight and follow (10.3). Suite: `PlayAlongTests`.
11. Rehearsal: `StagePlayAlong`, `LiveCommand.togglePlayAlong` and `p`, key help, audio-driven follow scroll, loop wrap from the audio timeline with the count-in, jump and stop rules, the pill, analytics (10.4). Suites: `StagePlayAlongTests`, `KeyHelpTests`, `SoundSafetyTests`.
12. One `make quick` (and `make e2e-one` for a changed existing class only).

**P8-6c - output routing and polish** (after P8-6a; may run in parallel with P8-6b)

13. `AudioDeviceDirectory` and its CoreAudio adapter, the Play through picker, stored UID, not-connected fallback, the USB note, configuration-change stop and rebuild (8.1, 11). Suite: `AudioSettingsStoreTests`.
14. Manual checks for Ryan, prepared and handed over: play through the Ampero II Stomp (the hint shows, sound comes out of it, unplugging it stops playback cleanly and the next sound uses the speakers); and a play-along CPU and memory reading on the lowest-spec Mac available (Activity Monitor during a looping section; the 8 GB target, `segue-ai-low-power-target`), recorded in the commit. If no low-spec Mac is available, record the M1 Pro figures and flag it.
15. One `make quick`.

Dependencies: **P8-4b -> P8-6a -> P8-6b**; **P8-6a -> P8-6c**; P8-6b also needs P8-2's passes, `StagePasses` and loop. All before v0.5 (R155, R161).

## 17. Files owned

- New (SegueCore): `Sources/Playback/` (`SoundOutput.swift`, `Voicing.swift`, `PhraseBuilder.swift`, `PhraseCursor.swift`, `PlayAlongTimeline.swift`, `TimingRule.swift`); the target in `Packages/SegueCore/Package.swift`; tests `VoicingTests`, `PhraseBuilderTests`, `PlayAlongTimelineTests`, `PhraseCursorTests`.
- New (SegueUI): `Sources/SegueUI/Audio/` (`AudioEngineHost.swift`, `AudioEngineSoundOutput.swift`, `SoundPlayer.swift`, `SoundGate.swift`, `SoundBank.swift`, `AudioDeviceDirectory.swift`, `CoreAudioDeviceDirectory.swift`, `Sounds/SegueSounds.sf2`), `Settings/AudioSettingsStore.swift`, `Settings/AudioSettingsView.swift`, `Editor/PlayAlongBar.swift`, `Editor/TimelineStrip.swift`, `Live/StagePlayAlong.swift`, `App/Licenses/GeneralUserGS.txt` and/or `FluidR3.txt`, `AccessibilityID+Audio.swift`; tests `SoundSafetyTests`, `HearChordTests`, `WalkUpAuditionTests`, `PlayAlongTests`, `StagePlayAlongTests`, `AudioSettingsStoreTests`, `SoundRenderSmokeTests`, `SoundBankBundleTests`.
- New (repo): `scripts/soundbank/` (`sources.txt`, `render-ab.swift`, `extract.py`).
- Changed: `Live/MetronomeClick.swift` (click output over the host; `RehearsalClick` unchanged), `Live/LiveDependencies.swift`, `Live/LiveSession.swift` (context, `playAlong`), `Live/LiveSession+Commands.swift`, `Live/LiveSession+Viewport.swift` (follow scroll; P8-2 owns the loop code, coordinate by hunk), `Live/StageChrome.swift` (pill), `Shows/LiveCommand.swift`, `Shows/InputBindings.swift`, `Shows/KeyHelp.swift`, `App/AppModel.swift` (`live` didSet, `soundPlayer`, dependencies), `App/AppModel+Shows.swift` (block before present, unblock in `finishRun`), `Settings/SegueSettingsView.swift`, `Settings/AppModel+Settings.swift`, `Rendering/SongSheetView.swift` and `Rendering/SongPageView.swift` (`onChord`, highlight), `Editor/SongEditorView.swift`, `Editor/WalkUpPopover.swift` and `Editor/WalkUpsSheet.swift` (P8-4b's files: play buttons, loop, A/B), `Diagrams/DiagramStrip.swift` and the bass cell (⌥-click), `Library/SongDetailPane.swift`, `Services/AnalyticsEvent.swift`, `Packages/SegueUI/Package.swift` (resources), `THIRD_PARTY_NOTICES.md`, `content/site.json` (credits), `docs/release/specs/WS3-services.md`.
- Docs: the user guide gains "Hear chords and walk-ups" and "Play along" sections (editor and rehearse pages) with captures in the next store media pass (R140), not in this workstream.

## 18. Done criteria

**P8-6a done when:** the bundled bank is the one Ryan chose by ear, at most 12 MB, SF2, credited in `THIRD_PARTY_NOTICES.md`, the licence folder and the website credits; clicking a chord in the editor and library previews (and ⌥-click on the canvas, a click on a bass strip cell) plays it with its bass at sounding pitch in the chosen sound and style; the walk-up popover plays each candidate, loops, switches seamlessly on A/B, and Return saves P8-4b's pick; the rehearsal click works exactly as before on the shared engine; no sound control works or looks enabled during a gig and `SoundSafetyTests` proves it; Settings > Audio sets the chord sound, style and volume; analytics keys fire; `VoicingTests`, `PhraseBuilderTests`, `PhraseCursorTests`, the UI suites, the smoke test and `make quick` are green; Ryan has done the by-ear walk-up check (10.2; the only walk-up review, R162 Q5).

**P8-6b done when:** play-along plays bass, chords and click at tempo for a section (looping) or the whole song in the editor and library, and in a rehearsal from the current pass (looping with `L`), never in a gig; chord lengths follow corrections, then chart marks, then the song's rule (one bar per chord by default); the timeline strip corrects any chord and the rule menu changes the rule, saved in `bass.timing` (never the `.cho`) and surviving the edits `ChordAnchorTests` covers; on stage the audio drives the scroll and the loop wrap with the count-in; suites and `make quick` green.

**P8-6c done when:** Settings > Audio lists outputs with the system output as default, remembers a device, falls back cleanly when it is gone, shows the quiet USB note in Settings for a USB interface, and stops (never auto-resumes) on a device change; Ryan has checked the Ampero routing; the low-spec reading is recorded or flagged; suites and `make quick` green.

## 19. Closed questions

Closed by Ryan on 2026-10-30 (**R162**; letters refer to the options as they were offered). The body above already reflects each answer.

1. **Default timing rule when the chart has no marks.** (a) One bar per chord, with the rule menu one click away (R162 Q1; section 7).
2. **A lyric line with no chords.** (a) It extends the previous chord (R162 Q2; section 7).
3. **Where timing corrections live.** (a) Per song in the sidecar, per chord, anchored like picks (R162 Q3; sections 7.3-7.4).
4. **Rehearsal play-along and the scroll.** (a) The audio drives: auto-scroll pauses, the stage follows the playhead, and the loop wraps on the audio's phrase end with R148's count-in (R162 Q4; section 10.4).
5. **Count-in on each wrap in the editor and library.** (a) One count-in at the start, then a seamless loop; the stage keeps R148 (R162 Q5; section 10.3).
6. **Walk-ups in play-along.** (a) Play what the chart shows: the pick, else the top candidate, with a Walk-ups toggle defaulting to the charts' setting (R162 Q6; decision 9).
7. **Bass pattern in play-along.** (a) The bass note on each strong beat (1 and 3 in 4/4), held, plus the shown walk-up (R162 Q7; section 7.5).
8. **Defaults for hearing a chord.** (a) Piano, strummed (R162 Q8; section 11).
9. **A/B interaction.** (a) Loop the change and switch candidates at the next phrase start (R162 Q9; section 10.2).
10. **The USB hint.** (b) A quiet note in Settings only, with no "first sound" status line (R162 Q10; section 11). This differs from the recommendation: the once-per-launch status line and its tests are removed.
11. **Bank fallback.** (a) Bundled SF2, then the macOS built-in bank (`gs_instruments.dls`, loaded in place), then a sine (R162 Q11; section 8.1).
12. **One sidecar version bump for P8-4b and P8-6.** (a) P8-4b's schema 5 already carries `bass.timing` (R162 Q12; P8-4 section 16 Q6).
