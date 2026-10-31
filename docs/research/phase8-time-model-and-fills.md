# Phase 8 research - a time model over chord sheets, and a bass fill / riff creator

Status: research, 2026-10-30. Not yet a workstream. Asked by Ryan: select a run of chords (possibly across a key change), generate 3-5 bass fills, hear them, edit them on a fretboard + rhythm grid or a piano roll (toggle), save them per song, and show them on stage as note names or a mini tab. The open problem is **time**: "design a full musical system or adapt to one" that works with existing lyric-first ChordPro charts. Inputs read: `docs/research/phase8-bass-patterns.md` ([BP]), `docs/research/phase8-audio-engine.md` ([AE]), `docs/phases/8-workstreams/P8-4-bass.md` ([P84], sections 8.5, 8.10, 8.11), `P8-6-audio.md` ([P86], section 7), decisions R147-R165. **V** = verified at the cited source or in this repo's code today; **U** = unverified.

**Short answer: adapt, don't adopt or invent a notation.** Keep the `.cho` as the canonical chart and treat time as a *layered projection* over it (one `SongTimeline`), with the user's corrections, taps and fills in the sidecar. Borrow iReal Pro's bar/cell grid as the internal shape, ChordPro's own `{time}` / `{tempo}` / `{key}` / bar lines / grids as the only things ever written to the `.cho`, and MIDI / MusicXML / iReal Pro only as exports. Fills are an instrument-neutral `Part` of note events in musical time, anchored to chords the same way walk-up picks already are.

## 0. What exists in the repo today (V)

- `ChordBeats.estimate` (`Packages/SegueCore/Sources/Library/ChordBeats.swift`): per chord, beats from bar lines / beat marks / `{time}` + one chord on a line, else `unknown` [P84 8.5].
- `ChordTiming { rule: TimingRule?, chords: [ChordBeatsOverride] }`, `TimingRule` (`each` halfBar/bar/twoBars, `beats n`, `line n`), `ChordAnchor` (section anchor + `fp` + chord ordinal + written bass), all in `Library/BassPrefs.swift`, decoded leniently in sidecar schema 5 (`bass.timing`) and filled by P8-6b.
- `WalkUp.candidates(from:to:context:)` (`MusicTheory/WalkUp.swift:202`): 0-4 ranked candidates per change with kinds, offsets from the target bass, chromatic flags, degrees and a score breakdown; `WalkUpContext.beats` comes from the estimate.
- `PlayedPass { index, mode, position }` (`Library/ArrangementResolver.swift:11`): P8-2's played order over `RenderModel.sections`.
- **Gaps that matter here:** (1) `{key}` is read once (`ChordPro/SongDocument+Derived.swift:136`, `key = key ?? value`), so a mid-song key change is invisible to every bass feature; (2) grid sections are verbatim and carry no chords (`ChordPro/DirectiveLine.swift:70-75`); (3) the P8-6 `Playback` module does not exist yet (`Packages/SegueCore/Sources/` has no `Playback`), so P8-6b's `PlayAlongTimeline` can still be reshaped before it is built; (4) `ChordBeatsOverride.beats` is whole beats 1...32: no sub-beat, no push.

## Part A - time models

### A1. Survey

| Format / product | How it models time | Lyrics | Verdict for Segue | Technique worth taking |
|---|---|---|---|---|
| **ChordPro 6 `{time}` / `{tempo}` / `{key}`** | `{time}` "specifies a time signature"; "Multiple signatures are possible, each specification is assumed to apply from where it was specified" ([time](https://www.chordpro.org/chordpro/directives-time/)). `{tempo}` is BPM, also positional ([tempo](https://www.chordpro.org/chordpro/directives-tempo/)). `{key}`: "Multiple key specifications are possible, each ... from where it was specified" ([key](https://www.chordpro.org/chordpro/directives-key/)) | n/a | **Adopt** as the only time data written into a `.cho`. Fix the positional reading: today Segue keeps only the first `{key}` and treats `{time}`/`{tempo}` as song-wide | Positional directives = a free, standard **meter/tempo/key map** |
| **ChordPro grids** `{start_of_grid shape="1+4x2+4" label="Intro"}` | Cells; `.` empty cell, `/` "a chord must be played in that cell", `~` several chords in one cell; bars `\|` `\|\|` `\|.` `\|:` `:\|` `:\|:`; voltas `\|1` `:\|2`; `%` / `%%` repeat 1 / 2 measures; margins hold text; optional strum lines (`\|S` with `up`/`dn`/`x`) ([grid](https://www.chordpro.org/chordpro/directives-env_grid/)). The reference implementation prints a ruled grid, labels in the left margin, styled by the PDF config "grid lines" | **No lyrics in a grid** (same page) | **Adopt as an input layer** (parse grids into timed chords; today they are dead text). Never use grids to store timing of lyric sections: grids cannot hold lyrics | Cell model: N cells per bar, `.`/`/`/`~`, `%` repeats |
| **ChordPro `{meta}` / `x_` directives** | `{meta: name value}`, "names can be chosen freely" ([meta](https://www.chordpro.org/chordpro/directives-meta/)); directives starting `x_` "should be completely ignored by applications that do not handle this directive", app tag recommended, e.g. `x_mspro_pedal_setting` ([directives](https://www.chordpro.org/chordpro/chordpro-directives/)) | n/a | **Don't use** for timing or fills: Segue already has a sidecar with anchors, lenient decode and schema versioning; an `x_segue_*` copy in the `.cho` would be a second store that has to agree | Selectors (`{comment-bass: ...}`) could carry bass-only notes for other apps; not needed |
| **iReal Pro** chart format | `irealbook://Title=Composer=Style=Key=n=Progression`; 16 cells per line, typically 4 cells per bar; bars `\|` `[ ]` `{ }` `Z`; `T44`/`T34`/`T68`; marks `*A` `*V` `*i` `S` `Q`; endings `N1 N2 N3`; `x` repeat 1 bar, `r` repeat 2 bars; `,` packs chords into one cell; `<8x>` repeat count; `n` = N.C. ([format](https://www.irealpro.com/ireal-pro-file-format)) | none | **Build informed by it + export target.** Its cell grid is exactly the shape our timeline needs; exporting a Segue song to an `irealbook://` URL is cheap once every chord has beats | Chord duration = cell count; repeats/endings as structure, not copies |
| **Nashville Number System** rhythm marks | Split bar = underline (or parentheses/slash), even split assumed; tick marks for uneven splits; **diamond** = hold whole bar; marcato = choke; **push** `<` early / `>` late ([airgigs crash course](https://blog.airgigs.com/2015/03/number-charts-crash-course-by-lydia-salnikova/), [No Treble](https://www.notreble.com/?p=25458)). JotChord's ChordText makes it typeable: `1_6-` split, `<1>` diamond, `<5` push an 8th early, `<<` a 16th, `1{4d,8}` beat values, `X` rest, `%`, `\|\|: :\|\|{4}`, inline `[3/8]` ([JotChord reference](https://www.jotchord.com/reference-guide)) | Number charts usually sit beside lyrics, not inside them | **Build informed by it.** It is the closest thing to how a working bassist annotates time on a lyric chart: almost nothing is written, and only exceptions (split, push, hold) are marked | The exceptions-only philosophy; **push** and **hold** as per-chord flags in our overrides |
| **ABC notation** | Notes with lengths; chords as quoted strings `"Am"`; `w:` lines align syllables to notes (space/hyphen advance, `_` hold, `*` skip, `\|` re-sync) ([Chambers, words](https://trillian.mit.edu/~jc/doc/abc/ABCtut_Words.html), [ABC FAQ](https://trillian.mit.edu/~jc/doc/abc/ABC-FAQ.html)) | syllable-to-note | **Neither storage nor export.** It needs a melody to hang lyrics on, which we don't have | None beyond confirming lyrics-to-time needs notes |
| **MusicXML** | Full notation; `<harmony>` = `(root \| function), kind, inversion?, bass?, degree*` ([harmony](https://usermanuals.musicxml.com/MusicXML/Content/EL-MusicXML-harmony.htm)); lyrics hang off notes | per note | **Export only** (bass staff + TAB staff + harmony). Gets the bass part into MuseScore / Guitar Pro / Sibelius / Dorico | `<harmony>` per chord onset; a bass part as notes with `<technical><string><fret>` |
| **Standard MIDI File** | Ticks per quarter; `FF 05` lyric "Generally, each syllable will be a separate lyric event"; `FF 06` marker = "Name of start of section" ([SMF meta](https://www.lim.di.unimi.it/IEEE/MIDI/META.HTM)); `.kar` = SMF with lyric events | per syllable | **Export first** (type 1: bass, chords, markers, a lyric event per chord's lyric fragment); DAW-ready, trivial from note events | 24-PPQN-compatible tick grid; markers for sections |
| **Guitar Pro / Songsterr / alphaTab** | Every bar fully notated; "a bar is valid only when the durations of its notes and rests exactly match the time signature" ([GP8 note input](https://www.guitar-pro.com/docs/gp8/score/note/note-input)). alphaTab (MPL-2.0) renders GP3-7, MusicXML and its alphaTex ([GitHub](https://github.com/coderline/alphatab)) | lyrics per beat | **Not as a model** (forces complete rhythm everywhere, which a lyric chart doesn't have). alphaTab is web/.NET, wrong stack: build informed by its tab layout | GP's keypad entry (digits = fret, `+`/`-` = duration, `R` rest) for the editor |
| **Band-in-a-Box** | Chords per bar/beat in a grid; a style "is a set of rules that determine how BiaB creates music using your chords" ([manual ch.2](https://ftp.pgmusic.com/manuals/bbm2021full/chapter2.htm)); RealCharts saved to a MIDI track ([ch.7](https://www.pgmusic.com/manuals/bbw2024full/chapter7.htm)) | lyrics per bar (U) | **Build informed by it** | Chord-per-bar default = our `TimingRule.each(.bar)` |
| **LRC / Enhanced LRC (A2)** | `[mm:ss.xx]` per line; A2 extension adds `<mm:ss.xx>` per word ([Wikipedia](https://en.wikipedia.org/wiki/LRC_(file_format))) | per line / word | **Not adopted.** Absolute seconds against a recording; Segue has no recording (R132) and tempo is variable live | Line onset = first chord's onset is all we need |
| **Tap-along capture** | Soundslice: "tap T on your keyboard for each downbeat while you listen"; gaps get **implied syncpoints** that move proportionally ([adding syncpoints](https://soundslice.com/help/en/creating/syncing/171/adding-syncpoints)). LivePrompter scrolls ChordPro by bar-number timing that follows tempo (U, [Cantabile forum](https://community.cantabilesoftware.com/t/new-liveprompter-release/8859)). Casio Chordana Tap records taps against a track ([Casio](https://web.casio.com/app/en/tap/usage.html)) | n/a | **Build informed by Soundslice** | Tap on chord changes (not every beat), quantise to the song's beat grid, fill unknowns by interpolation |
| **OnSong** | Pipes on a chord line make it a bar line ("Bar and Chords" / "Bar Only" detection) ([OnSong chords settings](https://mobile.onsongapp.com/docs/interface/menubar/utilities-menu/settings/display-settings/song-formatting/chords)) | inline | Same as our `ChordBeats` bar-line rule | Confirms bar lines on chord-only lines are the de facto convention |
| **Planning Center / MultiTracks ChartBuilder** | ChordPro-style `[G]Amazing Grace`; timing comes from the RehearsalMix audio and section markers ("song sections must be created FIRST"), auto-scroll and section loop follow audio ([MultiTracks help](https://helpcenter.multitracks.com/en/articles/7436863-how-to-create-cloud-song-charts), [song map](https://helpcenter.multitracks.com/en/articles/9005435-editing-the-song-map-in-chartbuilder-new)) | inline | Build informed by it | Time is **section-level**, owned by a separate layer, never by the chart text |
| **Moises** | Detected chords shown "in time" on a beat/bar grid; no chord-timeline export found ([App Store](https://apps.apple.com/us/app/1515796612)) | n/a | Not adopted (audio in, R132) | A horizontal chord-block timeline is the familiar UI for chord timing |

**Pattern across every lyric-first product:** none puts rhythm into the lyric text. Time lives in a separate layer (audio markers, section maps, bar-number scroll), and the chart only carries optional bar lines on chord-only lines. Notation formats (GP, MusicXML, ABC) require complete rhythm and a melody, which Segue's charts don't have. That settles "adopt a full system": no.

### A2. Proposed model: one `SongTimeline`, four layers

A pure SegueCore value (new module `Timing`, depending on `ChordPro`, `Editing`, `Library`; P8-6's `Playback` and P8-4b's `BassLine` depend on it):

```swift
public struct SongTimeline: Sendable, Hashable {
    public var meter: MeterMap          // {time} positions, R118 pulses
    public var tempo: TempoMap          // {tempo} positions (play-along override is session-only)
    public var keys: KeyMap             // {key} positions, concert
    public var chords: [TimedChord]     // in played order (passes), onsets in ticks
    public var totalTicks: Int
}
public struct TimedChord: Sendable, Hashable {
    public var position: ChordPosition  // (section index, chord ordinal) in the song
    public var pass: Int?               // PlayedPass position; nil = as written
    public var onset: Int               // ticks from the timeline start
    public var length: Int              // ticks
    public var push: Push?              // .eighth / .sixteenth early (NNS "<")
    public var source: TimingSource     // .rule, .chartMarks, .grid, .user, .tap
    public var key: SongKey?            // in effect at this chord
}
```

- **Unit:** ticks, **24 per quarter note** (MIDI clock resolution; holds 16ths = 6, 8th triplets = 8, 16th triplets = 4). Beats per bar and the beat unit come from the meter (R118: 6/8 counts two dotted-quarter pulses; a 6/8 bar = 72 ticks). Existing `ChordBeatsOverride.beats` (whole beats) maps 1:1.
- **Layers, highest wins, each only fills what it knows:**
  1. **Inferred rule** (`bass.timing.rule`, default one bar per chord; `line n` for even distribution per lyric line) [P86 7.1].
  2. **Chart marks**: `ChordBeats` (bar lines, beat marks, `meterLine`) **plus parsed `{start_of_grid}` sections** (new: cells, `.`, `/`, `~`, `%`, `%%`, voltas). Positional `{time}`/`{tempo}`/`{key}`.
  3. **User corrections** (`bass.timing.chords`): per chord anchor, `beats` (exists) plus two new optional fields, `ticks` (sub-beat length, e.g. a 2.5-beat chord) and `push` (`"8"` / `"16"`).
  4. **Tap capture** is an **input method that writes layer 3**, not a fourth store: taps are quantised to the beat grid and saved as ordinary corrections with `source: "tap"` (kept only as provenance for the strip's edge style). One storage, one resolver, one undo path.
- **Unknown stays visible:** `source == .rule` chords are "estimated". P8-4b keeps capping walk-ups at two notes on estimated chords (its R161 rule) but uses real lengths when the source is chart marks, grid, user or tap. The timeline strip draws estimated edges dashed (P8-6 7.4 already specifies this).

### A3. Where it is stored

| Data | Where | Why |
|---|---|---|
| Meter, tempo, key and their changes | `.cho`: standard `{time}`, `{tempo}`, `{key}` at the position they apply | Standard ChordPro, portable, already the user's habit. Writing one is an explicit user action ("Key change here" / "Time change here" in the editor) that inserts one directive line, never a silent rewrite |
| Bar lines on chord-only lines, grids for instrumentals | `.cho`, as the user typed them | Already read by `ChordBeats`; grids become read too |
| Timing rule, per-chord corrections, pushes, taps | sidecar `bass.timing` (schema 5, exists) | Anchored, lenient, never touches `.cho` bytes |
| Fills / riffs | sidecar, new top-level `parts` (schema 6), instrument-neutral | See A6 |

`{start_of_grid}` in the `.cho` is **not** a place to store timing for lyric sections (grids cannot hold lyrics). Offer one optional, explicit export: "Write this intro as a ChordPro grid", for an instrumental section only.

### A4. Chords to bars and beats; lyrics hang off it

1. Walk the played order (P8-2 passes, R147: every pass written out). For each section, take its `.chord`-kind chords in written order.
2. Length per chord = the highest layer that has one (A2). A chordless lyric line extends the chord before it (P86 7.1, R162 Q2). `N.C.` is a timed silence.
3. Onsets are cumulative; with `push`, the chord's onset moves earlier by an 8th/16th and the previous chord loses that much (the bar grid does not move).
4. **Lyrics hang off chords, not the other way round.** Each chord already sits at a character offset in its lyric line. The lyric fragment from chord *i* up to chord *i+1* is "sung during" chord *i*. A line's onset is its first chord's onset (or the previous chord's tail for a line that starts mid-chord). No syllable timing, no LRC: nothing in Segue needs it, and the stage highlight moves chord by chord.
5. Bar numbers are derived (`onset / barTicks` within the meter map), so a fill or a stage cue can say "bar 3, beat 4&" for display, while storage stays anchored to chords (A6).

### A5. Key changes and repeats

- **Key map:** `{key}` read positionally (fix `SongDocument+Derived.swift:136`). Each `TimedChord.key` is the key in effect. Without a second `{key}`, offer a non-writing **inferred key change**: when a section's chords fit another key much better than the song key (a deterministic diatonic-fit score), the bass view shows a quiet "Key change? A" chip that the user can confirm (writes `{key: A}` at the section start) or dismiss (stored in the sidecar). This matters for Bollywood/worship last-chorus lifts.
- **Repeats (P8-2 passes):** timing corrections resolve against the song's own sections through `PlayedPass.index`, so one correction applies to every pass of that section [P86 7.2]. Grid repeats (`\|: :\|`, `%`, voltas) expand into bars before layering. A `{chorus}` stub plays its target's chords and timing.
- **Fills across passes:** a fill anchors to written chords, so by default it plays in **every** pass of that section; an optional `passes` filter (`[2]`, "last") mirrors the section-note "Shows on" pop-up (R144/R146), e.g. a fill only into the final chorus.

### A6. Fills attached to a position

A fill is a `Part` over a **chord span**: start chord anchor, end (landing) chord anchor, plus events positioned **relative to the chord they sound over**:

```json
"parts": [
  {"id": "01JD...", "instrument": "bass", "name": "Into last chorus",
   "start": {"section": "Bridge", "occurrence": 1, "fp": "9f8e7d6c", "chord": 3, "from": "E"},
   "end":   {"section": "Chorus", "occurrence": 3, "fp": "1a2b3c4d", "chord": 0, "from": "A"},
   "spanBass": ["E", "F#", "A"], "passes": null, "show": "names",
   "events": [
     {"chord": 0, "at": 48, "len": 12, "deg": 7,  "oct": 0},
     {"chord": 1, "at": 0,  "len": 24, "deg": 0,  "oct": 0, "str": 3},
     {"chord": 1, "at": 36, "len": 12, "deg": 11, "oct": -1, "art": ["slide"]}
   ]}
]
```

- `chord` = index into the span; `at` / `len` = ticks from that chord's onset. A timing correction that lengthens a chord moves later chords' events with them; an event whose `at` falls past its chord's new length is drawn with a warning mark and skipped in playback (never silently moved).
- Pitch is stored as **semitones from that chord's written bass** (`deg`) plus an octave register (`oct`, relative to the profile's home position), like walk-up picks' `offsets` (P84 8.10). So transpose, capo and slot key overrides keep the fill correct, and spelling uses the chord's local key from the key map (R161 rule: notes over chord A agree with chord A). `str` optionally pins a string (tab editor); absent = `BassFretboard.suggested`.
- **Anchoring reuses `ChordAnchors.resolve`** (P84 8.11) for `start` and `end`, plus a span check: the written basses between them must still equal `spanBass` (pitch class). If not, the fill is **unmatched**: kept in the sidecar, listed with Remove, never applied (same rules as unmatched picks).
- A single-change fill (span of two chords) is a superset of a walk-up pick. Keep picks as they are (shipped, simple, shown by default); a saved fill on the same change wins over the pick on stage and in play-along.

### A7. One model for P8-4b, P8-6b and fills

| Consumer | Today / as specced | With `SongTimeline` |
|---|---|---|
| P8-4b walk-ups | `ChordBeats.estimate` -> `WalkUpContext.beats` | `timeline.length(of:)` with `source`; estimated -> cap 2 notes (unchanged behaviour) |
| P8-6b play-along | `PlayAlongTimeline.build(sections:origins:range:estimates:timing:meter:changes:)` [P86 7.5] | `PlayAlongTimeline` **is** a range slice of `SongTimeline` plus voices; build it this way from the start (the module isn't written yet) |
| P8-6 timeline strip | edits `bass.timing.chords` | same strip, same storage; adds push and tap |
| Fills | n/a | events resolve to absolute ticks via `TimedChord.onset`; to seconds via the tempo map, then P8-6's `NoteEvent` |
| Stage | walk-up text after a chord | fill names/tab drawn at the span, bar/beat from the timeline |
| Exports | n/a | MIDI / MusicXML / iReal read only the timeline + parts |

Rule to write into the specs: **no feature may compute a chord's length except through `SongTimeline`.** `ChordBeats` becomes layer 2's implementation detail.

### A8. Recommendation: adapt

- **Adopt**: ChordPro's positional `{time}`/`{tempo}`/`{key}`, bar lines and grids as the only chart-side time data.
- **Adapt**: iReal/BiaB chord-per-bar default, NNS split/push/hold as per-chord flags, Soundslice tap capture with interpolation.
- **Design our own** only the overlay: `SongTimeline` (derived, never stored) + `bass.timing` (exists) + `parts` (new). It is small because it never has to represent melody or full notation.
- **Don't** adopt MusicXML, Guitar Pro, ABC or LRC as storage: each demands rhythm or melody the charts don't have, or absolute time against audio Segue doesn't record.

**Tap capture design.** In the play-along bar (editor/library): "Tap timing" mode. Choose a range, press play, and either (a) tap Space on each **chord change** while listening to the song elsewhere or playing along, with Segue's click as a count-in at `{tempo}`, or (b) tap with no click and let Segue derive the tempo from the taps (median inter-tap interval over the shortest-chord assumption, shown for confirmation). Quantise each change to the nearest beat (8th with a modifier), write corrections, show changed blocks before saving (Review: Keep / Discard). A missed tap leaves that chord at its lower-layer length (Soundslice's implied points). A MIDI footswitch or the existing input bindings can tap (R141 `bindings.json`). No microphone (R132).

**Import / export path (priority order).**
1. **MIDI export** of the bass part (and optionally chords + click), SMF type 1, 480 PPQ, `FF 06` section markers, `FF 51` tempo, `FF 58` meter, a `FF 05` lyric event per chord's lyric fragment. Drag into Logic, GarageBand, Guitar Pro.
2. **MusicXML export**: one bass staff + linked TAB staff, `<harmony>` at chord onsets, the fill notes and held roots, `<technical><string/><fret/>`. Opens in MuseScore (free) and Guitar Pro. Prior art: [ireal-musicxml](https://github.com/infojunkie/ireal-musicxml) (licence not verified, U) converts iReal charts to MusicXML 3.1.
3. **iReal Pro export** (chords only, `irealbook://` URL, cell = beat, 4 cells per 4/4 bar): only when every chord's length is a whole number of beats; otherwise round and say so.
4. **iReal Pro import** as a new chord-only song (bars as ChordPro bar lines on chord-only lines): later, if wanted.

## Part B - prior art for fill and riff creation

| Tool | What it does | Verdict | Technique worth taking |
|---|---|---|---|
| **Band-in-a-Box** RealTracks / StyleMaker | Rules per style; bass patterns 1/2/4/8 notes chosen by chord duration ([SOS](https://www.soundonsound.com/node/4924292)); RealTracks are recorded phrases, optional notation to MIDI ([ch.7](https://www.pgmusic.com/manuals/bbw2024full/chapter7.htm)); "fill gaps between fills" option | build informed by it | Pattern length chosen from available duration = our template fit by span ticks |
| **Logic Pro Session Player - Bass** | Knobs: complexity, intensity, octaves, slides, lowest note, Align Root; **Fill Amount / Fill Complexity** with a lock ([Logic guide](https://support.apple.com/it-ch/guide/logicpro/lgcp74b34026/mac)) | build informed by it | Two orthogonal dials (how many notes, how busy the rhythm) instead of a style menu; "lock" a fill while browsing |
| **Guitar Pro 8 + RSE** | Full tab editor; keypad: digits = fret, `+`/`-` duration, `R` rest, `Tab` switch notation; virtual fretboard/keyboard input ([note input](https://www.guitar-pro.com/docs/gp8/score/note/note-input)) | build informed by it | Keyboard-first entry and the fretboard as an input device |
| **Songsterr** | Tab player with bass tracks, synced playback (editor community-driven) | build informed by it | Clean bass-tab rendering with rhythm as spacing |
| **alphaTab** (MPL-2.0) | Renders GP/MusicXML/alphaTex tab ([GitHub](https://github.com/coderline/alphatab)) | build informed by it (web/.NET, wrong stack) | Tab layout rules for the mini tab |
| **TuxGuitar** (LGPL) / **MuseScore** (GPL) | Open-source tab/notation editors ([AlternativeTo](https://www.alternativeto.net/software/tuxguitar/)) | export targets, not dependencies | MusicXML is the bridge |
| **iReal Pro** | 50+ styles decide the bass, regenerated with variation each play ([styles](https://www.irealpro.com/learn/accompaniment-styles)) | build informed by it | Slash chords as the user's override [BP] |
| **Hookpad / Hooktheory** | Bass from presets only ("you don't write the patterns yourself"); default "Piano Bass Dotted" = dotted quarter + 8th; custom patterns limited to triad tones ([forum](https://forum.hooktheory.com/t/what-are-the-length-of-notes-in-hookpad-chords/160), [pattern builder](https://forum.hooktheory.com/t/rhythm-pattern-builder/9753)) | build informed by it | Rhythm templates as named presets, independent of pitch; its triad-only limit is what users complain about, so allow scale/chromatic tones |
| **Captain Deep** (Mixed In Key) | Bass follows Captain Chords live; "Shape" (follow chords vs hold key root), genre rhythm banks ([SOS](https://www.soundonsound.com/reviews/mixed-key-captain-plug-ins)) | build informed by it | Separate **rhythm bank** x **pitch shape**; regenerating one keeps the other |
| **Scaler 3** | Bass Follow Track from chord roots; "Motions" (phrases, basslines) mood-tagged and bound to the chord's notes ([Attack](https://www.attackmagazine.com/technique/tutorials/scaler-3-chart-ready-chords-and-compositions-for-any-skill-level/), [product](https://scalermusic.com/products/scaler-3/)) | build informed by it | Phrases stored as **chord-relative degrees**, re-bound to any chord: our `deg` encoding |
| **Cthulhu** (Xfer) | Chord memory + arp, up to 12 patterns A-L per preset, "fingered bottom" puts the chord's bass on every 2nd step ([MusicRadar](https://www.musicradar.com/reviews/tech/xfer-records-cthulhu-574652)) | build informed by it | Step patterns that reference "bass / chord tone n" rather than pitches |
| **Impro-Visor** (GPL) | Per-beat note functions B/S/C/A (bass, scale, chord, approach), weighted ([style editor](https://www.cs.hmc.edu/~keller/jazz/improvisor/StyleEditorTutorial.pdf)) [BP] | build informed by it | Fill templates as **function slots** resolved to pitches; the core of the generator below |
| **MMA** (GPL) | Text grooves with bass tracks ([home](https://www.mellowood.ca/mma/)) | build informed by it | Groove files = data, not code |
| **Magenta MusicVAE / GrooVAE** (Apache-2.0 code) | MusicVAE trio = "melody, bass, and drums over 16-bar sections" ([MusicVAE](https://magenta.tensorflow.org/music-vae)), no chord conditioning in the post; GrooVAE is drums ([HF mirror](https://huggingface.co/AEmotionStudio/drumstudio-groovae-models)) | build from scratch (don't use) | None: not chord-conditioned, TF stack, nondeterministic, and the house rule wants deterministic, inspectable ranking |
| **music-bassline-generator** (Python), **MIDI-Bassline-Walk** (Perl, Artistic-2.0), **NeuralAcid** rule sequencer | Randomised chord-scale lines; authors warn of clashing notes ([PyPI](https://pypi.org/project/music-bassline-generator/), [GitHub](https://github.com/ology/MIDI-Bassline-Walk), [dataset](https://huggingface.co/datasets/intrect/neuralacid-basslines)) | build informed by them | NeuralAcid's explicit rules ("every bar begins with a note", root on most downbeats) as hard constraints |
| **Signal** (MIT-ish web piano roll), **wavy** ([Signal](https://signalmidi.app/), [wavy](https://github.com/chanyatfu/wavy)) | Browser piano rolls; no fretboard toggle found | build from scratch (SwiftUI), informed by them | Keep the roll minimal: bass range only, chord-tone rows tinted |
| **Soundslice** | Tap-to-sync, implied syncpoints, live fretboard highlight during playback ([help](https://soundslice.com/help/en/creating/syncing/171/adding-syncpoints)) | build informed by it | Tap capture (A8) and fretboard that lights up during playback |

**Fill pedagogy for multi-chord spans and key changes** (combines [BP] catalogue with modulation theory; no single bass source covers fills across modulations, flagged as thin):
- **Notes over a chord agree with that chord** (R161 passScale), so a span is planned chord by chord, with the final 1-2 notes as the approach into the landing chord.
- **Chromatic approach into the new key's target** on a weak beat: half step below (or above) the new root ([TalkingBass chromatic fills](https://www.talkingbass.net/create-killer-chromatic-bass-fills-like-pro/)).
- **Dominant of the new key**: play the new key's 5 just before its 1 (the implied V-I, StudyBass fifth approach [BP P7]); for a half-step lift (G to Ab) the 5 of Ab (Eb) is the strongest single-note cue.
- **Pivot / common tone**: hold or repeat a note shared by both keys, then step into the new root; common-chord modulation favours chords that are predominants in the new key ([Milne OER](https://milnepublishing.geneseo.edu/fundamentals-function-form/?p=12025)).
- **Octave run / root-5-8 pickup** of the departing chord: no clash risk, works for any modulation [BP P9].
- **Scale run in the new key** over the last beats when the departing chord is the new key's V (it usually is in a prepared modulation); in a direct (truck-driver) modulation, a chromatic run into the new root is idiomatic.
- **Rhythmic pickups**: 8ths on "3 & 4 &", 16th quadruplet on beat 4, triplet on 4, an anticipation (push) of the new root on "4&". Density by tempo and feel as in [BP section 2].

**Editor UX findings.** Guitar Pro: one score, fretboard/keyboard as input panels, keypad entry. Soundslice: notation + fretboard that lights up. Hookpad/Scaler/Captain: pitch and rhythm chosen separately. Piano rolls: time horizontal, pitch vertical, snap grid. Nobody found toggles fretboard+grid vs piano roll over **one shared selection**; that is ours to design.

## C. Recommended architecture

**C1. Time core** (`Timing` module, pure): `SongTimeline.build(render:passes:sidecar:)`, `MeterMap`/`TempoMap`/`KeyMap` from positional directives, `GridParser` for `{start_of_grid}`, layered lengths (A2), `ChordPosition` <-> ticks <-> bar:beat, tap quantiser. Replaces the planned `PlayAlongTimeline.build` internals.

**C2. Note/event model** (`Parts`, pure, instrument-neutral):
- `Part { id (ULID), instrument: InstrumentRef, span: SpanAnchor, passes, show, events: [PartEvent] }`
- `PartEvent { chord: Int, at: Int, len: Int, deg: Int, oct: Int, velocity: UInt8?, art: Set<Articulation>, pin: FretPin? }`, `Articulation` = slide, hammer, pull, ghost (dead), staccato, accent (closed vocabulary).
- `InstrumentRef` = `.bass(tuning)` now; `.guitar`, `.keys` later. Rendering to positions is per instrument (`BassFretboard` today); the event model never stores frets except an optional pin.
- `Part.resolve(timeline:) -> [AbsoluteNote(tick, len, midi)]` -> P8-6 `NoteEvent` via tempo map. So hearing, stage, PDF and export all read one resolver.

**C3. Fill generator** (`MusicTheory/Fill.swift`, deterministic, extends `WalkUp`):
`Fill.candidates(span: [TimedChord] + landing, context: FillContext) -> [FillCandidate]` (3-5, each with kind, events, score breakdown summing to the score).
1. **Rhythm templates** (data file, closed vocabulary, ~15): `pickup8` (3& 4 4&), `quarterWalk` (one per beat), `sixteenRun` (4e&a), `tripletRun`, `octavePops`, `rootFiveOctave`, `anticipation` (land on 4&), `dottedPush`, `rest+pickup`, `halfTimeHold`. Each slot is a **function** (Impro-Visor style): `R` root, `C` chord tone, `S` passing-scale tone, `A` approach to next, `O` octave, `P` pivot/common tone, `D` dominant of the next. Templates are fitted to the last N ticks of the span (BiaB-style length choice) and filtered by tempo/feel.
2. **Pitch resolution** per slot: strong beats take R/C of the chord sounding; `S` uses `passScale(chord, localKey)` (R161); the final `A` slots reuse `WalkUp.candidates(from: lastChordBass, to: landingBass, context:)` so single-change knowledge is not duplicated; across a key change, add `D` (5 of the new key/landing chord), `P` (common tone of the two keys nearest the current pitch), chromatic-below/above of the new root, and new-key scale run when the departing chord is the new key's V. Voice-lead in the octave nearest the previous note within the tuning's range (B0 on a 5-string).
3. **Rank** with the existing additive terms (clash = same-letter cross-relation, R165; resolution; direction by section energy) plus rhythm terms: approach notes on weak sub-beats, chord tone on every strong beat, density fit to tempo and feel, "every bar begins with a note". **Diversity:** pick the top candidate per template family so the 3-5 shown differ in rhythm and contour, not just one note.
4. Golden corpus extends `WalkUpCorpus` (spans of 2-4 chords; I-IV-V-I turnaround; G->Ab lift; E-Am in A minor; Bollywood harmonic minor; written stepwise lines -> a "hold" candidate first, per R162 Q1) plus property tests (deterministic, in range, no strong-beat chromatic, last note within 2 semitones of the landing bass or its fifth).

**C4. Editor** (sheet `segue.fill.editor`, editor and library only; never stage):
- **Entry:** shift-click (or drag) a run of chords in the preview, then "Create Fill..." (also from the Walk-ups list). Pre-loads the 3-5 candidates (A-E) in a left column, each with play (P8-6 audition, loop + A/B switching while playing).
- **Top lane:** the span's chord blocks from the timeline (same component as P8-6's timing strip; lengths editable here too), bar/beat ruler, key-change marker.
- **View toggle (segmented, `⌘1`/`⌘2`):** (a) **Fretboard + rhythm grid**: a step grid (8th/16th/triplet snap) under a horizontal neck in the profile's tuning; select a step, click a fret (or type a fret digit, Guitar Pro style) to set its pitch; drag a note's right edge for length. (b) **Piano roll**: bass range only, rows tinted per chord column (chord tones strong, scale tones light, others plain). Both views edit the same `[PartEvent]` and share selection, undo and snap.
- **Pitch snap:** chord tones / scale / chromatic (default scale, Option overrides). **Rhythm snap:** 8th / 16th / triplet.
- **Mini tab preview** at the bottom, exactly what the stage will draw.
- Save writes the sidecar `parts` (debounced, one undo step); "Revert to candidate", "Delete fill".

**C5. Stage and PDF:** the fill shows at its span in the bass-note view: **note names** by default (`E | F# G# › A`, chromatic "°" as for walk-ups, R162 Q3), or a **mini tab** (4 or 5 lines, fret numbers, rhythm as proportional spacing with a beat tick, no stems), toggled per fill (`show`) and globally (a stage key). Silent on stage (R161). Bass chart PDF prints the same.

## D. Proposed build sessions

1. **Spec session (planning only):** a P8-7 spec from this doc; amend P8-6 section 7 so `PlayAlongTimeline` is a slice of `SongTimeline`, and P8-4b so beats come from the timeline. Close the open questions below.
2. **Time core:** positional `{time}`/`{tempo}`/`{key}` (fix `key ?? value`), `GridParser`, `SongTimeline` with layers, `push`/`ticks` on overrides (lenient decode, still schema 5 since the fields are optional), in-process tests. Can land before or with P8-6b.
3. **Timing UI + tap capture:** the timeline strip (shared with P8-6b), push toggle, tap mode with review, "Key change here" / inferred key-change chip.
4. **Parts model + generator:** `Part`/`PartEvent`, sidecar schema 6 `parts`, `SpanAnchor` resolve (reusing `ChordAnchors`), `Fill.candidates` with templates, corpus and property tests. Silent.
5. **Fill editor:** span selection, candidates with audition (needs P8-6a engine), fretboard+grid / piano roll toggle, mini tab preview, save.
6. **Stage + PDF:** names and mini tab rendering, stage toggle key, bass chart PDF, analytics (`fillCreated`, `fillCandidatePicked`, `fillEdited`, view toggle use).
7. **Exports:** MIDI first, MusicXML second, iReal URL third.

Dependencies: 2 before 3/4; 4 before 5; P8-6a (engine) before 5's audition; 5 before 6.

## E. Open questions for Ryan (each with a recommendation)

1. **Adopt vs adapt.** (a) Adapt: layered overlay on ChordPro (this doc) / (b) adopt MusicXML or Guitar Pro as the per-song store / (c) research ticket. **Recommend (a).**
2. **Writing to the `.cho`.** Allow explicit, user-initiated inserts of standard `{key}`, `{time}`, `{tempo}` at a position? (a) yes, one directive per action / (b) never write the `.cho`, keep key changes in the sidecar. **Recommend (a)**: they are standard and portable, and the stage header then shows the right key.
3. **Inferred key changes.** (a) Show a confirm/dismiss chip when a section fits another key / (b) only honour written `{key}`. **Recommend (a)**, deterministic fit score, never applied without a click.
4. **Grids.** Parse `{start_of_grid}` into timed chords (play-along, fills, walk-ups)? **Recommend yes**; today grids are dead text.
5. **Sub-beat timing.** Add `ticks` and `push` to chord corrections (NNS pushes), or whole beats only? **Recommend add both** (optional fields, no schema bump).
6. **Tap capture source.** (a) Taps on chord changes with Segue's click at `{tempo}` / (b) also tempo-free tapping that derives BPM / (c) defer. **Recommend (a)+(b)**, quantise to beats, review before save.
7. **Fill scope across passes.** Default a fill to every pass of its section, with a "Shows on" filter like section notes? **Recommend yes.**
8. **Fill vs walk-up pick on the same change.** (a) Fill wins on stage and play-along, pick kept / (b) saving a fill deletes the pick. **Recommend (a).**
9. **Pitch storage.** Chord-relative degrees + octave register (survive transpose/capo, like picks) vs absolute MIDI. **Recommend chord-relative**, with an optional string pin.
10. **Instrument neutrality now.** Build `Part` with an instrument field but ship bass only, or bass-specific types? **Recommend neutral model, bass-only UI** (R137 keeps other instruments declined; this only keeps the door open).
11. **Candidate count and diversity.** 3-5 candidates, at most one per rhythm family? **Recommend 4 by default**, "More" shows the 5th.
12. **Stage display default.** (a) note names, tab per fill / (b) tab by default / (c) global setting only. **Recommend (a)** plus a stage key to flip all fills to tab.
13. **Editor default view.** Fretboard + grid or piano roll first? **Recommend fretboard + grid** (bassist), remembered per user.
14. **Exports in v0.5?** **Recommend no**: MIDI export in the first release after the editor; MusicXML and iReal later.
15. **Workstream and release.** Is the fill creator a P8 workstream before v0.5 (R155 pattern) or post-v0.5? **Recommend post-v0.5 for the editor (sessions 4-7)**, but land the time core (sessions 2-3) with P8-6b so there is one timing system from day one.
16. **Thin evidence on Bollywood fills and fills across modulations.** (a) Accept and tune by ear in the editor / (b) research ticket to grow a corpus from transcriptions. **Recommend (a)**, with a corpus-growth task in session 4.
