# P8-4 - Bass: instrument profile, bass-note view, Nashville roots, mini neck, bass chart PDF, fretboard and walk-ups

Phase 8 (2026-10-30 review round). Rulings: `docs/release/decisions.md` **R152** (bass support, all four levels; supersedes R137 / N7 for bass only, other extra instruments stay declined), **R155** (build order), **R158** (this spec's open questions closed, section 15), **R160** (walk-ups and hearing chords went to research first), **R161** (walk-up and audio rulings closing that research; P8-4b unblocked, audio is sibling P8-6), **R162** (P8-4b's open questions closed, section 16; no owner-review CSV gate). Research: `docs/research/phase8-bass-patterns.md` (the walk-up rules, section 8) and `docs/research/phase8-audio-engine.md` (audio, built in `P8-6-audio.md`). Related rulings: R113 (test budget), R122/R123 (slot arrangements), R147 (stage shows every section expanded; sibling spec P8-2 removes repeat collapsing from the stage), R149 (per-pass show modes), phase 1 spec `docs/phases/1-editor-and-music-theory.md` (capo semantics, Nashville rules, spelling rules, tunings), phase 1 interfaces `docs/phases/1-interfaces.md` (`DisplayOptions`, `DisplayTransform`, `RenderModel`).

Ryan's situation: he plays bass in a band. Charts are usually written by or for the guitarist, often with `{capo}` and shapes. Today Segue's instrument is a per-song diagram choice (guitar or piano), and nothing tells a bassist which note to play at sounding pitch.

The work is two build sessions in this one doc:

- **P8-4a - profile, bass-note view, numbers, mini neck, bass chart PDF** (levels 1, 2, 3 and the stage part of 4; R160): the user-level instrument profile, the bass-note chord view at sounding pitch (anyone can turn it on, R158 Q7), Nashville number plus note (following each song's Nashville toggle, R158 Q2), the key's scale in the stage header, the fretboard core and a **mini neck on stage** for the chord at the scroll position (R158 Q6), and a **"Bass chart" PDF export option** (R158 Q8). Not blocked, except its bass chart PDF step, which needs the phase 4 PDF export built first (R161, section 7.4).
- **P8-4b - editor fretboard strip + walk-ups** (the rest of level 4): bass fretboard cells in the editor's diagram strip (kept here by R161), and walk-up suggestions built from the research's rule set as amended by R161 (section 8): passing notes from the departing chord, a per-song feel (genre) defaulting from the profile, a ranked `candidates(from:to:context:)` API, a pick saved per song in the sidecar (schema 5) and shown on stage, alternates only in the editor and library, beats from bar lines or `{time}`, and an evaluation plan with a golden corpus and property tests (walk-ups are then judged by ear in P8-6a, R162 Q5). Depends on P8-4a having landed. It is silent: hearing chords and auditioning candidates is sibling **P8-6** (`P8-6-audio.md`), built after P8-4b on its candidates API and pick storage.

**Build order (R155):** all of Phase 8 ships before the v0.5 submission. P8-1 first; then P8-2, then P8-3; **P8-4a runs in parallel** with P8-2 / P8-3 and P8-5 (its stage-layout step 2 waits for P8-2's layout step, section 12); **P8-4b** follows P8-4a (and P8-2's played passes, for its stage hook), then **P8-6** builds on it (R161). P8-4a's "Bass chart" PDF step needs the phase 4 PDF export built first (R161, section 7.4). Index: `README.md` in this folder.

## Session rules (apply to both sessions)

- `cat` and `ls` are aliased to eza and can hang: use `command cat` / `command ls` or the Read/Grep/Glob tools. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-". Ignore `.build/`.
- Sibling workstreams (P8-2, P8-3, P8-5) edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, and stage only your own hunks. Keep the tree compiling between steps.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget (R113): per step only targeted in-process suites (`swift test --filter <Suite>`); new UI behaviour gets in-process SegueUI tests (`Packages/SegueUI/Tests/SegueThemeTests`). At most ONE new XCUITest for this whole workstream (section 11.4), plus the phase 4 export's own E2E if the bass chart option changes what it covers. At the end of each session ONE `make quick` plus ONE `make e2e-one` for the UI test class added or changed. No `make gate`, no `make check`, no E2E retry loops, no scratch-worktree builds. Every build or test runs under `lockf -k .build/make.lock`.
- Before using any Apple API not already in the codebase (for example the `guitars` SF Symbol, a new `Picker` style), run the `apple-api-check` skill.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency.

## 1. Goal

A bassist turns on "I play bass" once in Settings, picks 4 or 5 strings and a tuning, and from then on every song and the stage can show **the note to play** - the slash bass, else the root - at **sounding (concert) pitch**, whatever capo the guitarist's chart uses and whatever key or capo a setlist slot overrides. Anyone else (a keyboard player covering bass) can turn the same bass-note view on without the profile (R158 Q7). The note carries its Nashville number ("5 · D") when the song's own Nashville toggle is on (R158 Q2), optionally the full chord small beside it; the stage shows the key's scale in the header and, quietly, a mini neck with where to play the chord at the scroll position (R158 Q6); a "Bass chart" PDF prints the same view (R158 Q8). P8-4b adds fretboard positions in the editor's strip and one walk-up into the next chord on charts and stage, with ranked alternates and a saved pick per change in the editor and library.

**In scope:** the profile and its Settings pane, the bass-note view in the editor preview, library preview and stage, the editor top bar and stage toggles, Nashville number plus note, the scale line, bass tunings (4 and 5 strings), the fretboard core, the stage mini neck, the "Bass chart" PDF option, analytics events, accessibility (P8-4a); the editor's fretboard cells, walk-up suggestions, the per-song feel, saved picks in the sidecar, the shared beat estimate, and the walk-up evaluation (P8-4b).

**Not in scope:** any change to the `.cho` source or `{meta: tuning}` (a song's tuning stays the guitar's), print or Singer view variants beyond the "Bass chart" PDF option (the normal chart and Singer view always print chords), ukulele or other instruments (R137 stands), bass tab, rhythm or groove notation, rhythm hints on walk-ups (ChordPro has no chord durations; beats are only estimated, section 8.5), randomised or varied walk-ups (deterministic only), and any sound: hearing chords, auditioning walk-ups and play-along are P8-6 (R161).

## 2. Prior art

- **OnSong** has a "Bass Only" chord style that shows only the bass of split (slash) chords, and 4- and 5-string bass chord diagrams (https://4.onsongapp.com/docs/interface/menubar/style-preferences-menu/chords, https://onsongapp.com/docs/4-string-bass). It shows a slash chord's bass but has no sounding-pitch guarantee under capo, no Nashville-plus-note, and no walk-ups. Its bass "diagrams" are chord boxes, which is a guitar idea; a bassist needs the root's positions, not a chord shape. Verdict: build informed by it (take "bass only" as a view, drop chord boxes for bass).
- **ChordPro** has no bass concept; instruments live in the application's configuration, not in the song (https://chordpro.org/chordpro/chordpro-configuration-instrument). This confirms the profile belongs in app settings, never in the `.cho` or the per-song sidecar.
- **Forum advice for bassists reading guitar charts** is consistent: play roots first, then add fifths (and octaves), then walk-ups between chords. That ordering shapes the defaults here: the bass-note view is the main feature, root-fifth-octave lives on the fretboard cell, walk-ups are opt-in and sparse.
- No app found does pop-style walk-up suggestions; backing-track generators (iReal Pro, Band-in-a-Box, Strum Machine, Impro-Visor, MMA) walk every bar and randomise. Section 8 follows the research's survey (`docs/research/phase8-bass-patterns.md` section 4): sparse, end-of-chord approaches only, deterministic, ranked, with slash chords as the user's way to write their own line. Verdict for all: build informed by them (Impro-Visor's note-function vocabulary is the idea behind our candidate kinds).

## 3. Terms

- **Bass note**: for a parsed chord, `ChordSymbol.bass ?? ChordSymbol.root` (`MusicTheory/ChordSymbol.swift:17-19`); as a pitch class, `ChordTones.lowest` (`MusicTheory/ChordFormula.swift:47-50`). `C6/9` has no slash bass (its `/9` is suffix), so its bass note is C. `N.C.` and unknown chords have none.
- **Sounding (concert) pitch**: written chord + capo + transpose. `DisplayTransform.concertSemitones` (`Editing/DisplayOptions.swift:106-110`) is exactly this, whatever the capo mode. With a setlist slot override, `SetlistOverrides.applied(to:songCapo:)` (`Setlists/Setlist.swift:95-107`) rewrites transpose to `t + c - c2` and the capo to `c2`, so `concertSemitones` stays `written + c + t`: the slot's key and capo flow into the bass view for free, as long as the bass view reads `concertSemitones` and never `semitones`.
- **Concert key**: `key.writtenKey?.transposed(by: concertSemitones)`. `{key}` names the key of the chords as written (shape key under a capo; `DisplayOptions.swift:52-55`).
- **Bass view** (the bass-note view): the chord row shows bass notes instead of chord names. Available to anyone (R158 Q7); the profile ("I play bass") adds tuning-aware extras.
- **Chord unit**: what sits at one chord position in the chord row: the main text plus optional small detail (the full chord) and an optional approach run (walk-up).

## 4. Current behaviour (with file:line)

- **Instrument is per song.** `enum Instrument { guitar, piano }` (`Packages/SegueCore/Sources/Diagrams/PianoVoicing.swift:28-32`) is stored per song in `DisplayPrefs.instrument` with `tuning` (`Packages/SegueCore/Sources/Library/Sidecar.swift:238-309`, lenient per-field decode at 296-308). `DisplayOptions` mirrors it (`Editing/DisplayOptions.swift:9-38`). The editor's instrument menu writes it per song (`SegueUI/Editor/EditorTopBar.swift:124-158`, `SongEditorViewModel+Options.swift:44-64`; `setTuning` also writes `{meta: tuning}` into the source).
- **The stage ignores the instrument** and forces diagrams off: `LiveSession.renderModel(_:overrides:)` sets `options.showDiagrams = false` (`SegueUI/Live/LiveSession+Viewport.swift:34-42`).
- **Chord text** is produced once per chord by `RenderSectionBuilder.renderLine` calling `transform.display(token)` (`Editing/RenderSectionBuilder.swift:127-153`, the call at 142). `display` returns Nashville or `displayed(token)`, which uses `semitones` (capo-mode dependent; `DisplayOptions.swift:100-104, 117-132`). `concert(_:)` exists for piano diagrams (`DisplayOptions.swift:134-137`).
- **Header key** is the displayed key (`RenderModel.swift:69-71`); the stage header shows `SongSummary.performanceLine(model)` (`SegueUI/Live/StageChrome.swift:25-31`, `Rendering/SongSummary.swift:70-88`), which adds "capo N" only in Shapes mode.
- **Nashville** numbers a chord relative to the (relative major of the) key: `Nashville.number(for:in:)`; the degree names table is private (`MusicTheory/Nashville.swift:16-30, 137-155`).
- **Diagram strip** shows guitar or piano cells for unique displayed chords (`Editing/RenderModel.swift:97-133`, `SegueUI/Diagrams/DiagramStrip.swift:9-113`); shown in the editor when the per-song `showDiagrams` is on (`Editor/SongEditorView.swift:117-123, 155-171`).
- **Tunings** allow 3 ... 12 strings when parsed (`Diagrams/Tuning.swift:57-58`); presets are guitar only (`Tuning.swift:18-24`); `ScientificPitch` parses and names MIDI pitches (`Tuning.swift:71-122`).
- **Scale membership** exists: `SongKey.scaleContains` (major, natural minor plus leading tone; `MusicTheory/SongKey.swift:115-124`); spelling by key signature is `KeySpelling.spell` (`SongKey.swift:141-167`).
- **Stage repeats:** sibling P8-2 writes every pass out in full on stage (R147) and lands its layout step before this spec's stage-layout step (section 12), so the bass view only ever meets expanded passes. `{chorus}` repeat targets resolve with `SongSections.repeatTarget(of:in:)` (`Library/SlotArrangement.swift:361`), which P8-2 keeps.
- **PDF export** (phase 4, `docs/phases/4-export.md`) is specified but not built yet; it ships in v0.5 too (R138). Its viewer has display toggles and renders through a shared `ChartLayout` from `DisplayOptions` (4-export.md, Scope 4 and "Rendering approach"), which is where the "Bass chart" option plugs in (section 7.4).
- **Settings** has panes General, Appearance, Live, AI, Privacy, Data (`SegueUI/Settings/SegueSettingsView.swift:15-63`); stores are `@Observable` classes over UserDefaults (`Settings/LiveSettingsStore.swift`, `Settings/AppearanceStore.swift`); Reset All Settings is `AppModel.resetAllSettings()` (`Settings/AppModel+Settings.swift:62-73`).
- **Stage keys** are the default binding table (`Shows/InputBindings.swift:240-268`); `b` is free today.
- **Sidecar** (`Library/Sidecar.swift`): schema 4 (`currentSchemaVersion`, `:21`); per-field lenient decode through `PartialSidecar` (`Library/SidecarCodec.swift:139-190`), cues decoded one by one (`:222-232`), forward migrator steps 0-3 (`:14-48`); an older build opens a newer file read-only and never rewrites it (`:81-84`). Sidecar-only writes go through `SongFiles.writingDisplayPrefs` (`Library/LibraryStore+DisplayPrefs.swift:11-24`) behind `LibraryStore.updateDisplayPrefs(id:_:)` (`Library/LibraryStore.swift:216-220`). Siblings P8-2 and P8-5 do not bump the sidecar schema (P8-2 only drops `LivePrefs.collapseRepeats` leniently).
- **Anchors that survive edits** exist twice: slot arrangement rows store a `SectionAnchor` (label + 1-based occurrence, or a loose block after a labelled section; `Library/SlotArrangement.swift:10-52`) plus the section's content fingerprint `fp` (first two content lines, comments excluded, FNV-1a; `SongSections.fingerprint`, `:286-323`), coded as `section`/`occurrence` or `loose`/`after`/`afterOccurrence` keys (`:73-121`) and checked by `ArrangementResolver.unit(for:in:)` (`Library/ArrangementResolver.swift:66-81`). Placed section notes store label, occurrence and `fp` and re-anchor to the one same-label section with that `fp`, else are flagged unsure (`Library/SectionNotes+Anchors.swift:48-70`). `SongSections.units(of:)` renders with default options, so transposition and capo never change which part an anchor names (`SlotArrangement.swift:219-272`).
- **Bar lines and beat marks** survive import only on chord-only lines: `ColumnAligner.chordsOnly` keeps `|`, `||`, `|:`, `:|`, `/`, `.`, `%` as text (`Ingest/Converter.swift:211-226`, the decoration set at `Ingest/ChordLines.swift:176-178`), while a chord line merged onto lyrics drops them (`Converter.swift:166-190`). A `[|]` typed by hand parses as an unknown chord. `{time}` is parsed by `Metadata.parseTime` (`ChordPro/SongDocument+Derived.swift:195-204`); `MetronomeMeter.pulses` (`Shows/Metronome.swift:39`) counts compound meters in dotted quarters (R118). Grid sections are verbatim (`ChordPro/DirectiveLine.swift:70-75`) and carry no chords.

## 5. Decisions

1. **The profile is user-level, never per song (R152).** It lives in UserDefaults (`instrument.profile`), not in the sidecar and not in the `.cho` (ChordPro prior art agrees). It is carried to renderers as a new, **non-persisted** field `DisplayOptions.bass: BassView?`. `DisplayPrefs(_ options:)` has no such field, so the editor's existing `persistOptions()` can never write it into a sidecar: the precedence is enforced by the type, not by remembering.
2. **Anyone can turn on the bass-note view (R158 Q7).** The Bass segment in the editor and `b` on stage are always there, with or without "I play bass"; they flip the user-level `profile.bassNotes`. Without the profile the view uses the default 4-string EADG tuning for the mini neck. "I play bass" is the bassist's profile on top: turning it on also turns the bass-note view on (once; it can be turned off again), sets strings and tuning, and in P8-4b makes the editor's diagram strip a bass fretboard. With the bass-note view off the app is unchanged.
3. **Sounding pitch always.** The bass view reads `concertSemitones`, never `semitones`, so Shapes/Concert never changes the bass note and setlist slot overrides flow in (section 3). The small full chord beside the note is also at concert pitch (R158 Q11).
4. **Precedence:**

   | Thing | Bass-note view off (today) | Bass-note view on (anyone) | Plus "I play bass" |
   |---|---|---|---|
   | Chord row text | song: transpose, capo mode, Nashville | bass note at sounding pitch | same |
   | Transpose, capo, slot overrides | song / slot | same, they feed the sounding pitch | same |
   | Shapes / Concert segment | song | disabled (help: "Bass notes always show sounding pitch") | same |
   | Nashville numbers | song toggle | song toggle: on gives "5 · D", off gives "D" (R158 Q2) | same |
   | Diagram strip content | song instrument + tuning (`{meta: tuning}` wins) | unchanged | P8-4b: bass fretboard cells in the profile's tuning; song instrument and tuning ignored, never changed |
   | Diagram strip shown | song `showDiagrams` | unchanged | P8-4b: profile `fretboard` (the editor button reads "Fretboard") |
   | Stage diagrams | off | off; the mini neck when `stageNeck` is on (section 7.3) | same, in the profile's tuning |
   | Header key | displayed key (+ capo in Shapes) | sounding key, no capo; plus the scale line on stage | same |
   | PDF export | chords | chords unless the export's "Bass chart" option is on (section 7.4) | same |

5. **The visual editor canvas keeps chart chords** (R158 Q1). Chord pills are editable objects; showing a derived note there risks the chord popover prefilling "B" for `G/B` and rewriting the chord. The bass view applies to the text-mode preview, the library preview, the stage and the bass chart PDF; in visual mode the top bar shows a quiet note "Bass notes show in the preview and on stage" while bass view is on.
6. **Toggles:** the editor top bar gets a "Bass" segment next to Nashville; the stage gets `b` (new `LiveCommand.toggleBassNotes`, R158 Q3). Both flip the user-level `profile.bassNotes`, so they agree everywhere. The Nashville segment **stays the per-song Nashville toggle** in bass view too (R158 Q2); there is no separate "numbers with the note" setting.
7. **Nashville plus note:** with the song's Nashville toggle on, "5 · D" = the Nashville degree of the **bass note** (relative major in minor keys, phase 1 rule) + " · " (U+00B7 with spaces) + the note. `G/B` in G reads "3 · B". No key: the note alone.
8. **Scale line:** the stage header gains a muted "Sounding A major: A B C# D E F# G#" (minor: natural minor, "F#m: F# G# A B C# D E"), spelled with `KeySpelling` so its letters match the chart's (R158 Q10). It is the first thing to drop when the header is narrow.
9. **Mini neck (P8-4a, R158 Q6):** an optional, quiet mini neck at the left end of the stage's status band showing where to play the chord at the current scroll position (section 7.3). It replaces the positions strip this spec first proposed.
10. **Bass chart PDF (P8-4a, R158 Q8):** a "Bass chart" option in the phase 4 export viewer prints the bass-note view (section 7.4).
11. **Fretboard strip (P8-4b):** one editor strip cell per unique concert chord (same uniqueness as today's strip), titled with the bass note, the chord small under it; a horizontal neck, frets 0-12, every position of the bass note drawn hollow, one **suggested** position filled, and for non-slash chords the fifth and octave around it (section 7.2). Uses the fretboard core that P8-4a builds for the mini neck.
12. **Walk-ups (P8-4b, R161):** off by default; "Into sections" or "Every change" in Settings > Instrument; drawn only in the bass-note view, small and muted after the chord they leave; one walk-up per change on charts and stage (the saved pick, else the top candidate); the 2-4 ranked alternates and "Nothing here" only in the editor and library (section 8).
13. **Bass tunings** are a separate preset list (`Tuning.bassPresets`), never added to `Tuning.presets` (which `{meta: tuning}` parsing searches; adding "Standard" twice would make it ambiguous).
14. **Passing notes come from the departing chord (R161).** The scale a walk-up steps through is the key's scale with chord A's own tones overriding it, so E to Am walks F# G# (pop, rock, worship) or F G# (Bollywood feel), and A7 to Dm in C walks B C# (section 8.3).
15. **Feel is per song (R161).** A song's feel (pop, rock, worship, country / gospel, Bollywood) is a sidecar field; unset means the profile's default feel (Pop). It only reorders candidates; it never invents notes outside the candidate kinds.
16. **Picks live in the sidecar, never the `.cho` (R161).** A pick is stored per chord change with an anchor that survives edits (section 8.11); the stage shows it; a change whose pick no longer matches falls back to the rules.
17. **Beats are estimated, never required (R161).** Bar lines, beat marks and `{time}` give a chord's beats when the chart has them; otherwise a walk-up is at most two notes (section 8.5). The same estimate feeds P8-6's play-along timing.
18. **bVI-bVII-i and other written stepwise lines (R161):** both a "nothing" candidate and a passing-note candidate are offered, and the user chooses; "nothing" ranks first in every feel (section 8.3, R162 Q1).

## 6. P8-4a - profile, bass-note view, Nashville plus note, scale

### 6.1 Core types (SegueCore)

New `Editing/InstrumentProfile.swift`:

```swift
/// The user's instrument (Settings > Instrument, R152). App-level: never in a sidecar or
/// a `.cho`. Decoded leniently per field, like `LiveSettings`.
public struct InstrumentProfile: Sendable, Hashable, Codable {
    public var playsBass: Bool            // the bassist profile; default false
    public var strings: Int               // 4 or 5; default 4
    public var tuning: Tuning             // count == strings; default .bassStandard4
    public var bassNotes: Bool            // bass-note view, for anyone (R158 Q7); default false
    public var chordBeside: Bool          // full chord small beside the note; default false
    public var stageNeck: Bool            // mini neck on stage while bass view is on; default true
    public var fretboard: Bool            // editor strip (P8-4b, needs playsBass); default true

    /// What renderers get: nil unless `bassNotes` (or, for P8-4b's strip, `playsBass`).
    public var bassView: BassView? { ... }
}

/// The render-time slice of the profile (`DisplayOptions.bass`). Not persisted.
/// Nashville numbers come from the song's own `DisplayOptions.nashville` (R158 Q2).
public struct BassView: Sendable, Hashable {
    public var notes: Bool                // = bassNotes
    public var chordBeside: Bool
    public var tuning: Tuning             // the profile's, else .bassStandard4
    public var neck: Bool                 // = bassNotes && stageNeck
    public var fretboard: Bool            // = playsBass && fretboard (P8-4b)
}
```

- Invariant enforced on decode and on every Settings write: `tuning.strings.count == strings` and `strings` in {4, 5}; a mismatch falls back to that count's standard tuning.
- Turning `playsBass` on sets `bassNotes = true` in the same write (the store does it, not the view); turning it off leaves `bassNotes` as it is.
- Walk-up settings are not added in P8-4a; P8-4b adds `walkUps: WalkUpDensity` and `genre: BassGenre` to the profile (section 8.7).
- `DisplayOptions` gains `public var bass: BassView? = nil` (init parameter with default; `DisplayOptions` is not encoded anywhere persistent today - verify with a grep in step 1; if it is, exclude `bass` from its coding keys). `DisplayPrefs` is unchanged.

`Diagrams/Tuning.swift` additions:

```swift
public static let bassStandard4 = Self(name: "EADG", strings: [28, 33, 38, 43])        // E1 A1 D2 G2
public static let bassDropD     = Self(name: "DADG", strings: [26, 33, 38, 43])        // D1 A1 D2 G2
public static let bassHalfDown4 = Self(name: "Eb Ab Db Gb", strings: [27, 32, 37, 42])
public static let bassStandard5 = Self(name: "BEADG", strings: [23, 28, 33, 38, 43])   // B0 E1 A1 D2 G2
public static let bassHighC5    = Self(name: "EADGC", strings: [28, 33, 38, 43, 48])
public static let bassPresets: [Self] = [...]  // menu order: 4-string, then 5-string

/// Letters low to high, octaves implied ("BEADG", "DADG", "Eb Ab Db Gb"): the lowest
/// string is the note in B0 ... A#1 (MIDI 23 ... 34), each next string the nearest
/// occurrence strictly above the previous. Also accepts scientific pitches. nil unless
/// 4 or 5 strings.
public init?(bassLetters: String)
```

`MusicTheory` additions:

- `DisplayTransform` (Editing): `concertKey: SongKey?`; `bassText(_ token: ChordToken) -> BassChordText?` (nil when `options.bass?.notes != true`):
  ```swift
  public struct BassChordText: Sendable, Equatable {
      public var note: String      // "B", or "3 · B" when the song's Nashville toggle is on
      public var chord: String?    // concert chord ("G/B" -> "A/C#" under capo 2) when chordBeside
  }
  ```
  For `.chord`: `let concert = concert(token)`; note = `concert.symbol.bass ?? concert.symbol.root` spelled as the transposer spelled it (so slash basses follow the phase 1 "spelled in the same key context" rule), prefixed with the degree and " · " when the song's `options.nashville` is on and a key is known. `.noChord` and `.unknown`: note = `token.original`, chord nil (verbatim, as today).
- `Nashville.degree(of: PitchClass, in: SongKey) -> String` (public wrapper over the private table, relative major in minor keys).
- `SongKey.scaleNotes: [NoteClass]` - major or natural minor, seven notes from the tonic, each `KeySpelling.spell(_:in: self)`.

### 6.2 Render model

- `RenderChord` (`Editing/RenderModel.swift:289-314`) gains `detail: String?` (the small chord). `text` stays "what to draw big", so every existing consumer (measurement, accessibility, the stage passes) keeps working. P8-4b adds `approach` (section 8.8).
- `RenderSectionBuilder.renderLine` (`RenderSectionBuilder.swift:142`): when `transform.bassText(token)` is non-nil, `text = bass.note`, `detail = bass.chord`; else unchanged.
- Header (`RenderModel.swift:69-71`): in bass view the header key is `transform.concertKey` (with `Nashville.header` when the song's Nashville toggle is on), and `RenderHeader` gains `scale: String?` = "A major: A B C# D E F# G#" / "F#m: F# G# A B C# D E" (nil without a key or outside bass view).
- `SongSummary.performanceLine(_ model:)` (`Rendering/SongSummary.swift:70-88`): no "capo N" in bass view (the notes are not shapes), exactly as in Concert mode.

### 6.3 Where the profile enters

One helper, `DisplayOptions.withBass(_ profile: InstrumentProfile) -> DisplayOptions`, used at the three render sites (and by the bass chart PDF, section 7.4, as `withBass(profile, forcingNotes: true)`):

1. Editor: `SongEditorViewModel.scheduleRender` (`Editor/SongEditorViewModel.swift:340-358`) renders with `options.withBass(profile)`; `refreshCanvas` (`:318-337`) and the canvas copy in `scheduleRender` (`:363-366`) must use a model rendered **without** bass (decision 5): render the canvas model from `options` (bass nil) and compare against that, or keep a second render in visual mode only. Pick whichever keeps one background render in text mode; note the choice in the commit.
2. Library preview: `SongSummary.renderModel` (`Rendering/SongSummary.swift:46-54`) takes the profile.
3. Stage: `LiveSession.renderModel(_:overrides:)` (`Live/LiveSession+Viewport.swift:34-42`) gains `bass: BassView?`, applied **before** `overrides.applied(to:songCapo:)` so the slot's capo and transpose still feed `concertSemitones`. `relayout()` (`:64-108`) passes `context.instrument.profile.bassView` for the current and up-next models.

`InstrumentProfileStore` (new, `SegueUI/Settings/InstrumentProfileStore.swift`): `@MainActor @Observable`, key `instrument.profile`, saves on every change, records analytics (6.6), `resetToDefaults()`. Owned by `AppModel` next to `liveSettings`, passed to the editor view model and into `LiveDependencies` / `LiveSession.Context` (`Live/LiveSession.swift:27-41`). The editor and the stage observe it, so flipping it anywhere re-renders the open editor preview and calls `relayout()` on stage.

### 6.4 Settings > Instrument

New tab between Appearance and Live: `Tab("Instrument", systemImage: "guitars", value: Pane.instrument)` (check the symbol with `apple-api-check`; fall back to `music.note`). `Form` with `.formStyle(.grouped)` like the other panes:

- **Bass notes** group (anyone, R158 Q7): "Show bass notes instead of chords" (`bassNotes`) with `SettingsNote` "Shows the note to play at sounding pitch in every song and on stage, even when the chart is written for a capo. Nashville numbers follow each song's Nashville setting."; "Show the full chord beside the note" (`chordBeside`); "Mini neck on stage" (`stageNeck`, note: "Shows where to play the current chord, bottom left on stage"). The last two are disabled while `bassNotes` is off.
- **Toggle "I play bass"** (`playsBass`) - `SettingsNote`: "Turns on bass notes and uses your strings and tuning for the neck."
- **Strings**: segmented 4 / 5. Switching resets the tuning to that count's standard unless the current tuning already has that count. Always enabled (the mini neck uses it for anyone).
- **Tuning**: pop-up of `Tuning.bassPresets` for the string count, plus "Custom..." revealing a text field ("BEADG" or "B0 E1 A1 D2 G2") parsed by `Tuning(bassLetters:)`, with an inline error "Enter 4 notes, low to high" / "5 notes"; the field has autocorrect and text substitutions off (no lyric text is involved, but no field should rewrite note names). Always enabled.
- **P8-4b controls** (absent in P8-4a, not disabled): "Fretboard in the editor" (needs "I play bass"), "Walk-ups on charts" and "Default feel" (section 8.7). Audio settings are P8-6's own Settings > Audio pane.
- Reset All Settings (`AppModel+Settings.swift:62-73`) also resets the profile; update the doc comment listing what it resets.
- Identifiers: `segue.settings.instrument.{bassNotes,chordBeside,stageNeck,playsBass,strings,tuning,customTuning}` (P8-4b adds `fretboard` and its own); pane id via `AccessibilityID.settingsPane("instrument")`.

### 6.5 Editor and stage toggles

- `EditorTopBar.displayGroup` (`Editor/EditorTopBar.swift:99-122`): always (R158 Q7) a third `SegmentedGroup` with `SegmentButton(title: "Bass", isOn: profile.bassNotes)`, id `segue.editor.bass`, help "Show the note to play at sounding pitch (all songs)". While it is on: the Shapes/Concert group is disabled with help "Bass notes always show sounding pitch". The Nashville button is unchanged: it stays the **per-song** Nashville toggle (R158 Q2), and in bass view its help reads "Show the Nashville number with the bass note (this song)".
- `EditorTopBar.diagramGroup` (`:124-158`) is unchanged in P8-4a (the per-song Diagrams button and instrument menu). P8-4b changes it when `playsBass` (the "Fretboard" button, the "Bass, BEADG" label with "Instrument Settings..."); the per-song guitar/piano value is never touched.
- Stage: `LiveCommand.toggleBassNotes` (`Shows/LiveCommand.swift`), scope `.viewport`, `repeatsWhenHeld` false (P8-1), title "Bass Notes", bound to `b` in the default table (`Shows/InputBindings.swift:240-268`; R158 Q3; the key-clash test must stay green; P8-2 binds 1-9 and `l`). Dispatch flips `profile.bassNotes`, `relayout()`, and flashes "Bass notes" / "Chords", for anyone (no profile needed). It appears in the `?` key help (`KeyHelp`).
- Stage header (`Live/StageChrome.swift:25-31`): after the performance line, the scale text (muted, 16pt medium, `lineLimit(1)`, lowest layout priority, inside a `ViewThatFits` that drops it before the title truncates). Accessibility label "Sounding key A major, scale A, B, C sharp, ...".

### 6.6 Analytics (non-PII, WS3 spec 5 row 8)

`FeatureKey` (`Services/AnalyticsEvent.swift:205`) gains `bassProfile` (Settings: "I play bass" turned on), `bassNotes` (editor or stage toggle), `bassNeck` (mini neck shown in a stage session, once per session), `bassChart` (a PDF exported with the "Bass chart" option); P8-4b adds its own (section 8.12). Update the vocabulary test (`ServicesVocabularyTests`) and `docs/release/specs/WS3-services.md` (the catalogue row).

### 6.7 Drawing the chord unit

- **Editor preview / library preview**: `SongSheetView` builds segments from `chord.text` (`Rendering/SongSheetView.swift:334-344`); the segment gains the detail, drawn after the note at 0.6 x the chord size in `muted`, baseline-aligned, one space-width gap. The editor line layout (`Rendering/LyricLineLayout.swift`) measures the unit as a whole so lyrics never run under it.
- **Stage**: `TextRole` (`LiveLayout/LayoutRequest.swift:19-40`) gains `.chordDetail` (medium, 0.6 x `chordSize`, muted). `Measurer.line` (`LiveLayout/SongMeasurement.swift:132-139`) measures a chord unit as `width(text) + gap + width(detail)`, built so P8-4b can append a further run, and `MeasuredChord` / `PlacedText` carry the extra runs so `LineLayout`'s existing `chordEnd` push keeps units from overlapping. `StageSongBody` draws the extra runs by role. `LayoutAudit` must pass on the corpus with bass view on. P8-2's Chords-only rows (`LayoutRow.Kind.chordRow`) show bass notes like any chord row.
- Accessibility of a unit: "B, bass of G slash B" (with chord beside) or "3, B"; never colour alone.

## 7. Fretboard core, mini neck and bass chart PDF (P8-4a); editor fretboard strip (P8-4b)

### 7.1 Fretboard core (P8-4a; `Diagrams/BassFretboard.swift`, pure)

Built in P8-4a because the mini neck (7.3) needs it; P8-4b's editor strip reuses it unchanged.

```swift
public struct FretPosition: Sendable, Hashable { public var string: Int; public var fret: Int } // string 0 = lowest
public enum BassFretboard {
    public static let maxFret = 12
    /// Every position of `pitchClass` on frets 0 ... maxFret, low string first, then by fret.
    public static func positions(of pitchClass: PitchClass, tuning: Tuning) -> [FretPosition]
    /// The hand position for a song: the fret of the concert key's tonic on the lowest string
    /// where it falls on frets 0 ... 7 (no key: the song's first bass note).
    public static func homeFret(tonic: PitchClass, tuning: Tuning) -> Int
    /// The suggested position for a note within the box around `home`.
    public static func suggested(_ pitchClass: PitchClass, home: Int, tuning: Tuning) -> FretPosition?
    /// Fifth (above and below) and octave positions around `root`, inside the box.
    public static func shape(around root: FretPosition, fifth: Int?, home: Int, tuning: Tuning)
        -> [FretPosition]
}
```

Rules (pinned by the tables in 11.1; R158 Q12: fixed box, lowest pitch wins):

- **Box**: frets `max(0, home - 1) ... home + 3`; open strings (fret 0) are always candidates.
- **Suggested**: among candidates, the lowest sounding pitch (`tuning.strings[s] + fret`); ties go to the lower string. If none (a non-fourths tuning), the position nearest `home` by fret distance, then lowest pitch.
- **Shape** (root-fifth-octave, the forum's second step): exact pitches `root + fifth`, `root + fifth - 12`, `root + 12` inside the box. `fifth` comes from the chord formula: 7 if present, else 6 (b5) or 8 (#5), else none. **Slash chords** get the octave only (a fifth above the slash bass is usually not a chord tone).
- With standard fourths tunings every pitch class has a box candidate, because three strings x five frets cover 15 consecutive semitones.

### 7.2 Editor fretboard strip (P8-4b)

The editor strip stays in P8-4b with the walk-ups (R161).

- `RenderDiagram` (`Editing/RenderModel.swift:316-347`) gains `bass: BassDiagram?`: `note`, `chordName` (concert), `positions`, `suggested`, `shape`. `RenderModel.diagrams` (`:97-133`) fills it instead of guitar/piano when `options.bass?.fretboard == true`, using the concert chord, `options.bass.tuning`, and one `home` per song from `transform.concertKey`. Diagrams are built when `showDiagrams || bass.fretboard`; the editor's strip condition (`Editor/SongEditorView.swift:119`) uses the same rule.
- `DiagramStrip` (`SegueUI/Diagrams/DiagramStrip.swift`) gains a `.bass` case drawing `BassFretboardView` (new `SegueUI/Diagrams/BassFretboardView.swift`, SwiftUI `Canvas`): strings horizontal, lowest at the bottom (tab orientation), fret 0 as a nut line, single dots at 3, 5, 7, 9 and a double dot at 12 on the edge, note positions as hollow rings, the suggested position filled `cue`, shape positions as small filled `muted` dots; title = bass note big, concert chord small under it; fret number under the suggested dot. `.compact` and `.regular` sizes; snapshot-tested light and dark. No customise action for bass cells (there is no bass shape to customise).
- Accessibility: "B, play on the A string, fret 2; also E string fret 7, G string fret 4; fifth F sharp on the D string fret 4".

### 7.3 Mini neck on stage (P8-4a, R158 Q6)

An optional, quiet neck that shows where to play the chord at the current scroll position. It replaces the "positions strip" this spec first proposed.

- **When it shows:** bass view on and `stageNeck` on (`BassView.neck`), a song with at least one chord, not in a break interstitial, not past the end, not while a song is unavailable. Hidden (no placeholder) otherwise. Live and Rehearsal alike.
- **Placement:** the **left end of the status band** above the footer (`LiveView.statusBandHeight`, the 30 pt line inside it), 40 pt from the left edge (`LiveView.horizontalPadding`). P8-2 keeps the metronome pips at the right end of the same band (R158 P8-2 Q1). The neck takes no height from the lyrics: the band is already reserved, so the viewport does not change. While the neck shows, the transient status line (`StageStatusLine`, `LiveView.swift:297-308`) starts after it (leading inset = neck width + 16 pt) so the two never overlap. Hidden while the request panel covers the bottom of the stage, like the metronome.
- **Size and drawing** (new `SegueUI/Live/StageBassNeck.swift`, SwiftUI `Canvas`, drawn from the stage theme tokens):
  - Overall 30 pt high. On the left a label: the bass note (bold 18, `ink`) and under-right of it the position "A2" (string letter from the tuning's open note, then the fret; semibold 11, `muted`), 8 pt gap to the neck.
  - The neck: a **5-fret window** = the box `max(0, home - 1) ... home + 3` (section 7.1), shifted to include the suggested position if needed; 22 pt per fret, so about 110 pt wide plus the label (about 160 pt in all). Strings horizontal, lowest at the bottom (tab orientation): 4 strings 7 pt apart, 5 strings 5.5 pt apart; 1 pt lines in `indicatorOff`; fret wires 1 pt `line`; a 2 pt nut line when fret 0 is in the window; the window's first fret number in semibold 9 `muted` under the neck.
  - Positions: the **suggested** position a filled `cue` dot (7 pt); the other positions of the same note inside the window hollow 6 pt rings in `muted`; no fifth or octave dots on stage (that is the editor strip's teaching detail, too busy here).
- **Which chord:** the chord at the reading line. P8-2's `StagePasses.readLine(offset:plan:)` (P8-2 section 9) gives the y; the neck shows the last placed chord whose line top is at or above it within the current pass (P8-2's `currentPass`), else the current pass's first chord. When the song fits or is in 2-3 columns (no scroll), it is the first chord of the current pass (pass 1 unless a jump pinned another, R158 P8-2 Q2). Pure function in LiveLayout (`StagePasses.chord(at:plan:pinned:) -> PlacedChordRef?`) so it is tested without a window; the plan's placed chords already carry their concert `RenderChord` and y.
- **Behaviour:** read inside the stage's existing `TimelineView` (no new timer); it changes only when the chord changes (the value is compared, so the `Canvas` redraws only then). No animation: the dot moves instantly (quiet), with or without Reduce Motion. Never takes clicks or focus. `N.C.` or an unknown chord: the neck keeps the last real chord dimmed to 40% until the next one.
- **Tuning:** the profile's when "I play bass" is on, else `.bassStandard4` (EADG). `home` is computed once per song from the sounding key (`transform.concertKey`), as in 7.1.
- **Accessibility:** one element, label "Bass neck", value "B, A string fret 2" (updated when the chord changes, never announced), identifier `segue.live.bassNeck`. Hidden from VoiceOver when not shown.

### 7.4 "Bass chart" PDF export option (P8-4a, R158 Q8)

Plugs into the phase 4 export (`docs/phases/4-export.md`), which renders single chart and songbook PDFs through a shared `ChartLayout` from `DisplayOptions` and shows them in an embedded viewer with toolbar options (4-export.md Scope 4: "paper size, display toggles, include diagrams, include notes").

- **Option:** a toolbar toggle **"Bass chart"** in the export viewer, for single chart and songbook PDFs alike; default = the user's current bass-note setting (`profile.bassNotes`), so the export matches what the performer sees (4-export.md Goal). Available to anyone (R158 Q7). Changing it re-renders the preview like the other display toggles.
- **What it prints:** each song rendered with `DisplayOptions.withBass(profile, forcingNotes: true)`: bass notes at sounding pitch, the full chord beside when `chordBeside` is on, Nashville "5 · D" when that song's Nashville toggle is on, setlist slot key and capo overrides applied (songbook), the page header's key the sounding key with no capo, and under the header line a muted scale line ("Sounding A major: A B C# D E F# G#"). Chord detail runs print in a dark grey that stays readable on a mono printer (the print theme's rule, 4-export.md "Print theme").
- **Diagrams:** none. "Include diagrams" is disabled while "Bass chart" is on (help "Bass charts print no chord diagrams"); guitar or piano diagrams would contradict the notes. P8-4b may later print fretboard cells; not now.
- **Repeats:** independent of this option; the export's own repeats option applies (R158 P8-2 Q9, 4-export.md rule 6).
- **Naming and metadata:** the suggested file name gains " (Bass)" ("Harbour Lights (Bass).pdf", "Friday Set (Bass).pdf"); the PDF keywords gain "bass chart".
- **Seam:** P8-4a provides everything below the toggle: `withBass(_:forcingNotes:)`, `RenderChord.detail`, `RenderHeader.scale`, and the chord unit measurement (6.7). The export's `ChartLayout` consumes those like the stage does. **Phase 4's export is not built yet, and R161 makes it a prerequisite of this step.** If it exists when P8-4a reaches step 3c (section 12), P8-4a adds the toggle, the file name rule and the tests in 11.5. If it does not, stop and ask the orchestrator: the toggle then moves into the phase 4 build, and `docs/phases/4-export.md` needs a line for it.

## 8. P8-4b - walk-ups (research rule set, R161)

Built from `docs/research/phase8-bass-patterns.md` ("the research"; its section numbers are given as [R3.4] etc.) as amended by **R161**. The research's own open questions are closed in section 15 (Q13-Q18). Where this section and the research disagree, this section wins.

### 8.1 What the user gets

- **On charts and stage, one walk-up per change.** With "Walk-ups on charts" set to Into sections or Every change (Settings > Instrument, default Off) and the bass-note view on, the departing chord's unit gains a small muted run of approach notes: the user's **saved pick** for that change, else the **top-ranked candidate** (R161). The same run shows in the editor preview, the library preview, the stage and the bass chart PDF (7.4). The stage never offers alternates and never makes a sound.
- **In the editor and library only, alternates and picking.** Clicking a walk-up run (or any change in the song's Walk-ups list, 8.9) shows the 2-4 ranked candidates plus "Nothing here"; choosing one saves it to the song's sidecar (R161). P8-6 adds play buttons and A/B audition to the same popover; P8-4b's popover is complete without sound.
- **A feel per song** (R161): Pop, Rock, Worship, Country / gospel, Bollywood, or "Default" (the profile's default feel, Pop unless changed). It reorders candidates only.
- **Passing notes agree with the departing chord** (R161): E to Am walks F# G# (pop, rock, worship) or F G# (Bollywood); A7 to Dm in C walks B C#.
- **Beats** come from bar lines, beat marks or `{time}` when present, else a walk-up is at most two notes (R161).

### 8.2 Core API (`MusicTheory/WalkUp.swift`, pure)

```swift
/// A song's feel for walk-ups (R161). Stored per song in the sidecar; the profile holds the default.
public enum BassGenre: String, Sendable, Hashable, Codable, CaseIterable {
    case pop, rock, worship
    case country            // "Country / gospel"
    case bollywood          // "Bollywood" (Hindi film and raga-flavoured songs)
}

/// What a candidate is, from a closed vocabulary [R3.3] plus `hold`.
public enum WalkUpKind: String, Sendable, Hashable, Codable, CaseIterable {
    case hold               // "Nothing here": the written roots already walk (R161, bVI-bVII-i)
    case scaleWalk, scaleChrom, diatonicNeighbour, chromBelow, chromAbove, fifth
    case doubleChromAbove, octavePickup
}

public struct WalkUpContext: Sendable, Hashable {
    public var key: SongKey?            // concert key; nil = unknown
    public var departing: ChordSymbol   // chord A at concert pitch (its tones override the scale)
    public var arriving: ChordSymbol    // chord B at concert pitch
    public var genre: BassGenre?        // nil = the research's "unknown" column (legacy rule, tests)
    public var beats: Int?              // chord A's estimated beats (8.5); nil = unknown
    public var tempo: Double?           // `{tempo}`; nil = assume mid
    public var intoSection: Bool        // A ends its section and B starts the next one with chords
    public var energyUp: Bool?          // B's section is a chorus or bridge (true), a verse (false), else nil
    public var writtenLine: Bool        // A -> B sits in a written stepwise bass line (rule S2)

    /// The pre-research rule's context: unknown genre, unknown beats, no section facts.
    public static func legacy(key: SongKey?, from: ChordSymbol, to: ChordSymbol) -> Self
}

public struct WalkUpCandidate: Sendable, Hashable {
    public enum Direction: String, Sendable, Hashable { case up, down, none }
    public var kind: WalkUpKind
    public var notes: [NoteClass]       // spelled, concert pitch, played order (target last); [] for hold
    public var offsets: [Int]           // semitones from the target bass, played order, e.g. [-3, -1]
    public var direction: Direction
    public var chromatic: [Bool]        // per note: outside the passing scale
    public var degrees: [String]        // per note, relative to the key ("2", "#4", "b7"); [] without a key
    public var score: Double
    public var breakdown: [WalkUpTerm: Double]   // every weighted term; the values sum to `score`
}

public enum WalkUpTerm: String, Sendable, Hashable, CaseIterable {
    case genrePrior, clash, resolution, direction, length, minorTonic, intoSection, writtenLine
}

public enum WalkUp {
    /// 0 ... 4 ranked candidates for the move from bass `from` to bass `to` (concert pitch classes).
    public static func candidates(from: PitchClass, to: PitchClass, context: WalkUpContext)
        -> [WalkUpCandidate]
    /// The legacy single answer: `candidates(from:to:context: .legacy(...)).first?.notes ?? []`.
    public static func notes(from: PitchClass, to: PitchClass, key: SongKey?) -> [NoteClass]
}

/// The ranking weights [R3.4], one static value so tuning after the by-ear check in P8-6a (8.13)
/// changes numbers only, never code.
public struct WalkUpWeights: Sendable, Hashable { public static let standard: Self ... }
```

The score breakdown is kept on every candidate (the house rule for deterministic rankers): tests assert on it, and the editor shows it on hover for tuning (8.9).

### 8.3 Rules

Derived values [R3.1]: `a`, `b` (bass pitch classes at concert pitch: slash bass, else root); `d`, the signed shortest distance from `a` to `b` in -5 ... +6 (a tritone counts as up); `maxNotes` (8.5: known beats `n` gives `min(3, n - 1)`, unknown gives 2).

**Passing scale (R161: from the departing chord).** The key's scale (major, or natural minor) with every letter that chord A alters replaced by A's chord tone (its third, fifth and seventh as spelled at concert pitch). Consequences:
- Minor, A is V, V7 or vii°: the raised 7 (A contains it; E major's G#, never G over it).
- Minor, walking **up** to i from V: the raised 6 as well (melodic), so E -> Am walks `F# G#`. With feel Bollywood the harmonic form `F G#` is generated too and gets the minor-tonic bonus (term 6), so it ranks first.
- Major, secondary dominants: in C, A7 -> Dm walks `B C#` (A7's C#).
- No key: the passing scale is A's chord tones only, so only `chromBelow`, `chromAbove` (descending) and `fifth` can appear.

**Suppression** (no candidates at all) [R3.2]:
- **S1.** `a == b`, or `|d| == 1` (already a step).
- **S2. Written stepwise line (changed by R161).** The bass notes of (previous, A, B) or (A, B, next) each move 1-2 semitones in one direction (`C - C/B - Am - Am/G`; the rock `F G Am`, bVI-bVII-i). Then `|d| == 1` is S1, and `|d| == 2` gives exactly two candidates: `hold` first and the note between second (`diatonicNeighbour` when it is in the passing scale, else `chromBelow` going up or `chromAbove` going down). Nothing else is generated. This is R161's "the user chooses in the app": both are offered, and the chart shows "nothing" until the user picks the passing note (R162 Q1).
- **S3.** A or B is `N.C.` or unknown, or A is the last chord in the played order.
- **S4.** Known `n == 1`; or tempo above 160 with `n <= 2`.
- **S5.** Density (8.6): "Into sections" and A does not end its section.
- **S6.** Feel Worship, or tempo below 70: not into a section and only chromatic candidates survive.
- **Tritone** (`|d| == 6`): not suppressed, but only `chromBelow` is generated ("no idiomatic walk", research section 2).

**Candidates** [R3.3], each with the spelling rule below; a candidate equal to another's notes is dropped (the higher-ranked kind keeps it):

| Kind | Notes (target `b`) | Generated when |
|---|---|---|
| `scaleWalk` | the passing-scale notes strictly between `a` and `b` in the chosen direction, the ones nearest `b`, at most `maxNotes` | the interval in that direction is 2 ... 7; tried up and down |
| `scaleChrom` | `scaleWalk` with its last note replaced by `b - 1` (up) or `b + 1` (down) when that differs | going up, the last scale step into `b` is a whole step (3-#4-5: `A B C#` into D) |
| `diatonicNeighbour` | the one passing-scale note next to `b` on the approach side | a key is known |
| `chromBelow` | `b - 1` | always (the no-key fallback) |
| `chromAbove` | `b + 1` | `a` is above `b` (descending), or feel Rock or Country |
| `fifth` | the fifth of B (`b + 7`) | B's bass is its root (not a slash chord) |
| `doubleChromAbove` | `b + 2`, `b + 1` | feel Rock or Country, `maxNotes >= 2` |
| `octavePickup` | A's octave (drawn as a fill) | A ends its section; always lowest priority |
| `hold` | none | only under S2 |

**Ranking** [R3.4]: score = the sum of weighted terms, every term recorded in `breakdown`:

1. **Genre prior** (0-3), `WalkUpWeights.standard.prior[kind][genre]`, the research table verbatim ([R3.4] item 1; column "unknown" for `genre == nil`).
2. **Clash with chord A** (-5): a note a half step from A's third, fifth or seventh that is not the target-side chromatic approach note (this rejects `F G` over E into Am).
3. **Resolution**: last note a half step from `b` +2, a whole step +1, the fifth +1.
4. **Direction**: +1 for up when `energyUp == true`, down when `false`; +1 more in Country for the walk up a fourth (I-IV, V-I).
5. **Length**: -2 per note beyond `maxNotes` (dropped beyond `maxNotes + 1`); +0.5 for exactly filling the slots when `n >= 4`.
6. **Minor tonic** (+2): minor key, B is i, the candidate ends on the raised 7; plus +1 for `F G#` (harmonic) with Bollywood, +1 for `F# G#` (melodic) otherwise.
7. **Into section** (+1) for `scaleWalk` and `scaleChrom`.

Under S2 the order is fixed (`hold`, then the passing note) and the breakdown holds one `writtenLine` term. Otherwise the result is the top 4 with score >= 3 (`WalkUpWeights.standard.floor`), ties broken by `WalkUpKind` declaration order, then lower first-note pitch.

**Legacy property.** With `WalkUpContext.legacy` the top-1 equals the old spec rule (|d| = 2 the note between; 3-5 the two nearest scale notes; a tritone a half step below), except the documented changes, each a named row in `WalkUpTests`: minor V-i (`E -> Am` is `F# G#`, not `F G`), chord-A overrides (`A7 -> Dm` in C is `B C#`), and written lines (`hold` first).

**Spelling**: notes in the key's scale via `KeySpelling.spell(_:in:)`; a note that chord A supplies keeps A's spelling (`G#` over E); any other chromatic note is a sharp ascending and a flat descending (white keys stay naturals, the chart rule).

**Worked examples** (feel Pop unless stated, unknown beats; first = what the chart shows):

| A -> B (key) | Ranked candidates |
|---|---|
| G -> C (G) | `A B`, `B`, `G` (fifth of C) |
| G -> D (G) | `F# E` (down), `B C#` (scaleChrom up), `A` (fifth of D) |
| G -> Em (G) | `F#` |
| C -> D (G) | `C#` |
| E -> Am (Am) | `F# G#`, `G#`; Bollywood: `F G#`, `F# G#`, `G#`; `F G` never |
| G -> Am (Am) | `G#` |
| F -> G, then G -> Am (Am), any feel | F -> G: `hold`, `F#` (S2); G -> Am: `hold`, `G#` |
| A7 -> Dm (C) | `B C#`, `C#`, `E` |
| C -> C/B -> Am -> Am/G (C) | C -> C/B none (S1); C/B -> Am: `hold`, `Bb`; Am -> Am/G: `hold`, `Ab` |
| G -> C# (C), tritone | `C` |

### 8.4 Section facts

`intoSection`: A is the last `.chord` of its section in the order being annotated and B is the first `.chord` of a later section. `energyUp`: B's section kind `.chorus` or `.bridge` (or a custom label starting "Pre-Chorus" or "Chorus") is true; `.verse` (or a custom "Outro") is false; anything else nil. Labels are read through `SectionNotes.label(of:)`.

### 8.5 Beats (`Library/ChordBeats.swift`, pure; shared with P8-6)

```swift
public enum ChordBeats {
    public struct Estimate: Sendable, Hashable {
        public enum Source: String, Sendable, Hashable { case barLines, beatMarks, meterLine, unknown }
        public var beats: Int?          // nil when unknown
        public var source: Source
    }
    /// One estimate per `.chord`-kind chord of `sections`, in written order, keyed by
    /// (section index, chord ordinal within the section).
    public static func estimate(_ sections: [RenderSection], time: String?)
        -> [ChordPosition: Estimate]
}
```

`beatsPerBar` = `Metadata.pulses(ofTime:)`, a new function next to `Metadata.parseTime` (`ChordPro/SongDocument+Derived.swift:195`) that holds the R118 rule (4/4 = 4, 3/4 = 3, 6/8 = 2, 12/8 = 4); `MetronomeMeter.pulses` (`Shows/Metronome.swift:39`) calls it so the rule exists once. No `{time}`: 4.

Rules, per lyric line, first match wins:
1. **Bar lines** (`barLines`): the line's text has bar tokens (`|`, `||`, `|:`, `:|`, whitespace-separated, as `ChordLines`' decoration set) or `[|]`-style unknown chords whose text is one of them. A chord's bar is the span between the bar tokens around it; it gets `beatsPerBar / (chords in that bar)` (integer division, at least 1), plus `beatsPerBar` for each following bar on the line that holds no chord or only `%` (a repeat bar).
2. **Beat marks** (`beatMarks`): `/` or `.` tokens after a chord, before the next chord or bar token: the chord gets 1 + their count (`[G] / / / [C] / / /` is 4 and 4).
3. **Meter, one chord on the line** (`meterLine`): the song has `{time}` and the line holds exactly one chord: that chord gets `beatsPerBar` (at least a bar).
4. Otherwise `unknown`.

A chord's estimate never reads past its own line. Walk-ups use `beats` for `maxNotes` (8.3); P8-6 uses the same estimates as the first layer of its play-along timing (P8-6 section 6).

### 8.6 Applying it to a song (`Library/BassLine.swift`, pure)

```swift
public struct BassLineContext: Sendable {
    public var key: SongKey?                 // concert key
    public var genre: BassGenre              // the song's feel, else the profile's default
    public var density: WalkUpDensity        // .off, .sections, .everyChange
    public var tempo: Double?
    public var time: String?
    public var picks: ResolvedPicks          // 8.11
}

public enum BassLine {
    /// Every chord change of `sections` in the order given, with its candidates and pick.
    public static func changes(_ sections: [RenderSection], origins: [Int], context: BassLineContext)
        -> [ChordChange]
    /// `sections` with `RenderChord.approach` set on each departing chord that shows a walk-up.
    public static func annotate(_ sections: [RenderSection], origins: [Int], context: BassLineContext)
        -> [RenderSection]
}

public struct ChordChange: Sendable, Hashable, Identifiable {
    public var id: ChangeID                  // the departing chord's position + the target bass
    public var from: RenderChord, to: RenderChord
    public var candidates: [WalkUpCandidate] // [] when suppressed
    public var suppressed: Suppression?      // which rule (S1 ... S6), for the Walk-ups list
    public var pick: WalkUpPick?             // the user's, when it applies here (8.11)
    public var shown: WalkUpCandidate?       // pick, else candidates.first; nil for hold / none
}
```

- `origins[i]` is the index into the song's own `RenderModel.sections` that `sections[i]` came from (identity for the editor and library; P8-2's played passes carry their section index on stage), so picks and beat estimates resolve against the written song whatever order is played.
- The next chord is the next `.chord`-kind `RenderChord` in the order given, across lines and sections. `N.C.`, an unknown chord, or a section with lyrics and no chords between two chords breaks the chain (S3).
- A `{chorus}` stub (editor and library previews only; on stage P8-2 has written it out, R147) resolves to its target's first chord through `SongSections.repeatTarget(of:in:)` (`Library/SlotArrangement.swift:361`).
- **Density:** Off: nothing anywhere (the editor's Walk-ups list still works, with a note that walk-ups are off on charts). Into sections: only section-final changes show. Every change: every change not suppressed. **A pick always shows while density is not Off**, even on a change the density would skip (R162 Q2).
- Bass notes are read from each chord's concert pitch (the same `concert(_:)` as the bass view), so walk-ups agree with the notes drawn.
- **Where it runs:** the editor preview and library preview call `annotate` on `RenderModel.sections` (written order) after building the model, when `options.bass?.walkUps != .off` and the bass-note view is on. The stage calls it in `SongPreparation` on P8-2's final played list of passes, so each pass gets the approach into what actually follows it (one additive call; coordinate the hunk with P8-2). The bass chart PDF uses the editor path.

### 8.7 Settings and the song's feel

- `InstrumentProfile` gains `walkUps: WalkUpDensity` (default `.off`) and `genre: BassGenre` (the default feel, default `.pop`); `BassView` gains the same two plus `fretboard` (already there). Lenient decode as for the other fields.
- Settings > Instrument, a **Walk-ups** group (enabled while "Show bass notes" is on): "Walk-ups on charts" pop-up Off / Into sections / Every change, note "A short run of notes into the next chord, after the chord it leaves. Change one in the editor or library."; "Default feel" pop-up (Pop, Rock, Worship, Country / gospel, Bollywood), note "Songs use this unless you set their own feel." Identifiers `segue.settings.instrument.walkUps`, `segue.settings.instrument.genre`, plus `segue.settings.instrument.fretboard`.
- A **song's feel** is set in the Walk-ups list header (8.9): "Feel: Default (Pop) / Pop / Rock / Worship / Country / gospel / Bollywood". Choosing "Default" removes the song's own value. Stored in the sidecar (8.10).

### 8.8 Display

- `RenderChord` gains `approach: ApproachRun?`:
  ```swift
  public struct ApproachRun: Sendable, Equatable {
      public var change: ChangeID          // opens the popover (editor, library)
      public var notes: [String]           // "A", "B" (or degrees "2", "3" with the song's Nashville on)
      public var chromatic: [Bool]         // drawn with a trailing small "°" [R5]
      public var isPick: Bool
      public var accessibility: String     // "walk up A, B into C"
  }
  ```
- Drawn after the chord unit (after `detail` when the chord is beside), separated by one space width: notes separated by spaces, then "›" (U+203A; verify the stage face has the glyph, else ">"): `G  A B ›` then `C`. Chromatic notes carry a small "°" (`A B C#° ›`). Nashville on: degrees, sharps and flats relative to the key (`2 3 ›`, `3 #4 ›`). A `hold` shows nothing. No rhythm hint and no direction glyph (letters show direction).
- Stage: new `TextRole.approach` (medium, 0.6 x `chordSize`, `muted`), measured and placed as a further run of the chord unit (6.7 built the run list for this), so `LineLayout`'s `chordEnd` push keeps units apart and `LayoutAudit` stays clean with walk-ups on.
- Editor text-mode preview and library preview: the same run in `SongSheetView`'s segment (`Rendering/SongSheetView.swift:334-344`), and it is a **button** (plain style, pointing-hand cursor, underline on hover) that opens the popover (8.9). A picked run is drawn in `ink` at 70% instead of `muted`, so a pick reads as "yours". The visual canvas shows no walk-ups (decision 5).
- Bass chart PDF: runs print as in the preview (dark grey, mono-safe), never as buttons.

### 8.9 Picking: the popover and the Walk-ups list (editor and library only)

**Popover** (anchored to the run, or to a row of the list), identifier `segue.walkUp.popover`:
- Title "G → C", subtitle the section ("Verse 1") and the feel ("Pop").
- One row per candidate, labelled A-D in rank order: notes ("A B ›"), degrees muted ("2 3"), a plain description from the kind ("Scale walk up", "Scale walk with a half step", "Step into the chord", "Half step below", "Half step above", "Fifth of C", "Two half steps from above", "Octave pickup", "Nothing - the chords already walk" for `hold`), a "Suggested" tag on the rule's top-1, and a checkmark on the one shown. Then a last row **"Nothing here"** (always offered; it saves a `hold` pick).
- Footer: "Reset to suggestion" when a pick exists. Hovering a row with ⌥ held shows its score breakdown (for tuning; not otherwise visible).
- Keys: ↑/↓ move, Return chooses, Esc closes. Choosing saves at once and closes. P8-6 adds a play button per row, Space to play, and A/B (P8-6 section 5).
- A change with no candidates (S1 or S3-S6) shows "No walk-up here" with the reason in muted text ("Already a half step", "The chord before is N.C.") and the "Nothing here" row only.

**Walk-ups list** (a sheet), opened from the editor top bar's diagram group ("Walk-ups...", shown while the bass-note view is on; identifier `segue.editor.walkUps`) and from a library song's context menu ("Walk-ups...", `segue.library.song.walkUps`):
- Header: the song's feel picker (8.7) and, when density is Off, the note "Walk-ups are off on charts. Turn them on in Settings > Instrument."
- Body: every change in written order, **grouped under its section** ("Verse 1", "Chorus"), each row "G → C", the shown run or "Nothing", and "Your pick" / "Suggested"; clicking a row opens the popover beside it.
- Footer, only when some picks no longer match (8.11): "2 saved walk-ups no longer match this song", each listed with its section and chords as saved ("Verse 1: G → C, A B") and a Remove button, plus "Remove all".

**Undo:** in the editor every pick, reset and feel change registers an undo on the window's undo manager (the inverse `BassPrefs` write). The library's sheet has no undo; "Reset to suggestion" is the way back.

**Writes:** `LibraryStore.updateBassPrefs(id:_:)` (new, beside `updateDisplayPrefs`, `Library/LibraryStore.swift:216-220`) over `SongFiles.writingBassPrefs` (new, `Library/LibraryStore+Bass.swift`, the same shape as `writingDisplayPrefs`, `LibraryStore+DisplayPrefs.swift:11-24`): sidecar only, `.cho` bytes, mtime and index projection untouched, written at the current schema. A read-only song (a sidecar from a newer Segue, `ReadOnlyReason.newerSchema`) disables picking with the help "This song was saved by a newer Segue".

### 8.10 Sidecar schema 5 (`bass`)

`Sidecar.currentSchemaVersion` 4 -> **5**; history line "5 = P8-4b (`bass`: per-song walk-up feel and picks, play-along timing for P8-6; R161)". New field `public var bass: BassPrefs` (default empty), always encoded. On disk:

```json
"bass": {
  "genre": "rock",
  "walkUps": [
    {"section": "Verse", "occurrence": 1, "fp": "1a2b3c4d", "chord": 3,
     "from": "G", "to": "C", "pick": "scaleWalk", "offsets": [-3, -1]},
    {"loose": 1, "after": "Chorus", "afterOccurrence": 2, "fp": "0f0e0d0c", "chord": 0,
     "from": "F", "to": "G", "pick": "hold", "offsets": []}
  ],
  "timing": {
    "rule": {"each": "bar"},
    "chords": [{"section": "Chorus", "occurrence": 1, "fp": "9f8e7d6c", "chord": 0, "from": "C", "beats": 2}]
  }
}
```

```swift
public struct BassPrefs: Sendable, Hashable, Codable {
    public var genre: BassGenre?             // nil = the profile's default feel
    public var walkUps: [WalkUpPick]
    public var timing: ChordTiming           // filled by P8-6 (P8-6 section 6); P8-4b only preserves it
}
public struct ChordAnchor: Sendable, Hashable {       // 8.11
    public var section: SectionAnchor        // the `ArrangementStep` keys
    public var fingerprint: String           // "fp"
    public var chord: Int                    // 0-based among the section's `.chord`-kind chords
    public var from: String                  // the chord's bass as written ("B" for G/B)
}
public struct WalkUpPick: Sendable, Hashable, Codable {
    public var anchor: ChordAnchor           // flattened into the object
    public var to: String                    // the target's bass as written
    public var kind: WalkUpKind              // "pick"
    public var offsets: [Int]                // semitones from the target bass, played order; [] for hold
}
public struct ChordTiming: Sendable, Hashable, Codable {
    public var rule: TimingRule?             // P8-6 section 6
    public var chords: [ChordBeatsOverride]  // anchor + "beats" (1 ... 32)
}
```

- `from` and `to` hold the **bass as written** (slash bass, else root, before any transpose or capo), so the anchor never depends on display options; a pick's notes are rebuilt from `offsets` at concert pitch and spelled by 8.3's rule, so transposing, capo changes and setlist key overrides keep the pick correct.
- **Coding:** the anchor keys are exactly `ArrangementStep`'s (`section`/`occurrence`, or `loose`/`after`/`afterOccurrence`, then `fp`; `Library/SlotArrangement.swift:73-121`). Factor that coding into `SectionAnchor` helpers (`decode(from: KeyedDecodingContainer)` / `encode(to:)`) used by both; P8-2 edits the same file for passes, so coordinate the hunk and keep its `migrateV5` untouched.
- **Lenient decode**, as everywhere in the sidecar: `PartialSidecar` (`Library/SidecarCodec.swift:139-190`) gains `bass`, decoded on its own; inside it `genre`, `walkUps` and `timing` decode per field, and picks and overrides **one by one** (like `lenientCues`, `:222-232`): a pick with an unknown `pick` kind, a missing anchor, more than 4 offsets or an offset outside -11 ... 11, or an override outside 1 ... 32 beats is dropped, and the rest survive. A missing `bass` decodes as empty.
- **Migration:** step `4: { _ in }` (an absent `bass` decodes as empty); a v4 file is written at 5 on its next save (the existing rule). An older build opens a v5 sidecar read-only and never rewrites it (`SidecarCodec.swift:81-84`), so picks are never silently dropped by an old build; the cost is that an older build cannot edit a song this build has saved. Dev builds only, since none of this has shipped.
- `DisplayPrefs` and the `.cho` are untouched; no bass action ever writes the `.cho` (section 14).

### 8.11 Anchoring a pick so it survives edits

The anchor reuses the slot-arrangement and section-note approach (`SectionAnchor` + content fingerprint, section 4), narrowed to one chord:

- **Saving:** `section` = the `SongSectionUnit.anchor` of the section holding chord A, from `SongSections.units(of:)` (default render options, so transposition never changes it); `fp` = that unit's `fingerprint`; `chord` = A's 0-based ordinal among that section's `.chord`-kind chords in written order; `from` = A's written bass; `to` = the target's written bass. At most one pick per (anchor, `to`): saving replaces any other pick with the same anchor and `to`. A section-final chord can therefore hold one pick per possible target (an arrangement that plays the bridge next instead of the chorus finds its own pick, or none).
- **Resolving** (`ChordAnchors.resolve(_:units:sections:) -> ResolvedPicks`, pure, in `Library/ChordAnchor.swift`; used for picks and for P8-6's timing overrides):
  1. Find the unit whose anchor matches (`SectionAnchor.matches`) and whose `fingerprint` (or `legacyFingerprint`) equals `fp`. If the anchor's unit has another fingerprint, re-anchor as section notes do: exactly one unit with the same label (or, for loose lines, the same `after` label) and this `fp` takes it (`SectionNotes+Anchors.swift:48-70`); none or several: **unmatched**.
  2. In that section, the `.chord` at ordinal `chord` whose written bass equals `from` (pitch-class equality) is A. If it is not, re-anchor within the section: exactly one `.chord` there whose written bass is `from` **and** whose next chord's written bass is `to`; none or several: **unmatched**.
  3. The pick **applies** to a change when its departing chord is A and the change's target bass (as written, in the order being annotated) is `to`. In any other order (a slot arrangement), the change falls back to the rules.
- **When the chord change disappears** (unmatched: the section, the chord or the target is gone or ambiguous): the pick is **not applied anywhere**; the chart shows the rules' top candidate for whatever change is there now; the pick **stays in the sidecar** (so undoing the edit, or retyping the chord, brings it back) and the Walk-ups list footer lists it with Remove (8.9). It is never deleted on load or by the background save. Saving a new pick on the same anchor and target replaces it. Re-anchored positions (steps 1-2) are written back only with the next bass write for that song, never as a side effect of opening it.
- Edits that keep the first two content lines keep `fp`; edits that change them are found by step 1's re-anchoring when the label is unique; a chord changed to another chord with the same bass (G to G7) keeps its pick.

### 8.12 Analytics and accessibility

- `FeatureKey` gains `walkUps` (Settings: density turned on, context `.settings`), `walkUpPick` (a pick or "Nothing here" saved; `.editor` or `.library`), `songFeel` (a song's feel set; `.editor` or `.library`).
- New event row 24 `walkUpPicked(WalkUpPickSummary)`: `kind: WalkUpKind`, `rank: WalkUpRank` (`top`, `alternate`, `nothing`, `reset`), `genre: BassGenre`; daily per (kind, rank, genre) in `AnalyticsEvent+Throttle.swift` like `notesEdited` (`:45-48`). It answers the research's "which kinds musicians reject" [R7.5] with a closed vocabulary and no song data. Update `ServicesVocabularyTests` and `docs/release/specs/WS3-services.md` (row 8 list and a row 24).
- Accessibility: a chord unit with a walk-up reads "G, walk up A, B into C" (chromatic notes add "outside the key"); on stage it is part of the unit's label, never separate. In previews the run is a button, label "Walk-up into C: A, B", hint "Shows other walk-ups". Popover rows: "Option A, A, B, scale walk up, suggested, selected"; "Nothing here". List rows: "Verse 1, G to C, A B, your pick". All state is text, never colour alone.

### 8.13 Evaluation plan (research section 7)

1. **Golden corpus** `Packages/SegueCore/Tests/Fixtures/walkups/WalkUpCorpus.json`, read by `WalkUpTests` (loaded the way the existing fixture suites load theirs): about **60** cases of `{A, B, key, mode, genre, beats?, tempo?, intoSection, energyUp?, prev?, next?}` -> `expectTop1`, `expectContains`, `expectNone`, `mustNotContain`. Coverage: every diatonic move in G major and A minor; I-IV, V-I, IV-V, I-vi, vi-IV; descending slash lines (`C - C/B - Am - Am/G - F`, `G - D/F# - Em - C`) -> `hold` first; V-i in minor for each feel; secondary dominants (`A7 -> Dm`, `E7 -> Am` in C); the rock bVI-bVII-i (`hold` and `F#` both present); tritone and half-step moves; `N.C.` and the last chord; flat keys (Bb, Eb) and sharp keys (E, F#) for spelling; known beats 1, 2, 4, 8 and unknown. `mustNotContain` pins regressions (`F G` for `E -> Am`). Each worked example in 8.3 is a corpus row.
2. **Property tests** (`WalkUpPropertyTests`, all 12 x 12 bass pairs x 2 modes x 5 feels and nil x beats {nil, 1, 2, 4, 8}; fast, pure, not in `SLOW_TESTS`): deterministic (same input, same output); at most 4 candidates; no candidate longer than `maxNotes + 1`; every last note within 2 semitones of `b` or the fifth; no candidate contains `a` or `b`; no note clashes with A's third; each breakdown sums to its score; `hold` only under S2; legacy top-1 equals the old rule except the documented rows.
3. **By-ear check** (after P8-6a lands, a manual step for Ryan; R162 Q5): there is no owner-review CSV and no acceptance-rate gate. Once P8-6a's audition exists, Ryan plays the walk-ups in his own songs through the popover and the Walk-ups list; any change he judges wrong (or that should be silent) becomes a golden case, and tuning changes only `WalkUpWeights.standard`. Recorded as a manual step and in the done criteria of P8-6a (P8-6 sections 10.2 and 16), not P8-4b's.
4. **Analytics** (8.12) after release: kind shown, alternate picked, nothing picked, per feel.

## 9. Interaction with sibling specs

- **P8-2 (stage passes, R147):** P8-4a's stage-layout step (step 2) starts after P8-2's layout step has landed, so it measures chord units inside P8-2's expanded passes and its new chord rows; `SongPreparation`, `SongMeasurement` and `LineLayout` edits are coordinated by hunk. The mini neck reads P8-2's `StagePasses` (reading line, current pass); if P8-2's names differ when P8-4a gets there, stop and ask. P8-4b's walk-up hook runs on P8-2's played passes, and needs each pass to carry its source section index (8.6); P8-2 edits `SlotArrangement.swift` too, where P8-4b factors the `SectionAnchor` coding (8.10).
- **P8-2 stage chrome:** the metronome pips sit at the right end of the status band (R158 P8-2 Q1); the mini neck takes the left end (7.3). The scale line goes in the header after "Arranged", before the spacer (P8-2 section 12).
- **P8-2 section jump keys 1-9 and `l`**, P8-1's `repeatsWhenHeld`, and any new stage keys from siblings: `b` must stay free; the binding clash test catches a collision.
- **Slot arrangements and show modes (R122, R149):** the bass view needs nothing from them; a "Chords only" pass shows bass notes in bass view like any chord row, and the mini neck follows the current pass.
- **Phase 4 export:** the "Bass chart" option (7.4); P8-4b's walk-up runs print in it like the preview (8.8).
- **P8-6 (audio, R161):** builds on P8-4b's `WalkUp.candidates`, `BassLine.changes`, the pick storage and the popover (it adds play buttons and A/B there), `ChordBeats` and `ChordAnchors` (its play-along timing overrides use the same anchors and the `bass.timing` field P8-4b already decodes). P8-4b must not add any sound, audio dependency or engine code.

## 10. Romanized Hindi and text

No lyric text is read, written or transformed: bass notes come only from bracketed chord tokens already parsed by `ChordToken(parsing:)`, so lyric words such as "Am", "Dm", "Bas" are never treated as chords (phase 1 rule stands). `RomanNormalizer` is not involved. The custom tuning field has autocorrect and substitutions off.

## 11. Tests (R113 budget)

Music theory here is tricky pure logic: table-driven Swift Testing suites (`@Test(arguments:)`) in `Packages/SegueCore/Tests/SegueCoreTests`, each row a one-line case. P8-4b's walk-up suites follow the evaluation plan (8.13).

### 11.1 Core (in-process)

- **`BassNoteTests`** (P8-4a): `DisplayTransform.bassText` through a real `RenderModel` built from a tiny `.cho` per row. Columns: written chord, `{key}`, `{capo}`, capo mode, transpose, slot override, the song's Nashville toggle, `chordBeside` -> note, detail.

  | chord | key | capo | mode | transpose | override | song Nashville | -> note | detail (if beside) |
  |---|---|---|---|---|---|---|---|---|
  | G | G | - | shapes | 0 | - | no | G | G |
  | G/B | G | - | shapes | 0 | - | no | B | G/B |
  | Cmaj7 | G | - | shapes | 0 | - | no | C | Cmaj7 |
  | F#m7b5 | G | - | shapes | 0 | - | no | F# | F#m7b5 |
  | C6/9 | C | - | shapes | 0 | - | no | C | C6/9 |
  | G | G | 2 | shapes | 0 | - | no | A | A |
  | G/B | G | 2 | shapes | 0 | - | no | C# | A/C# |
  | Em | G | 2 | concert | 0 | - | no | F# | F#m |
  | C | C | 3 | shapes | 0 | - | no | Eb | Eb |
  | Bb | F | 1 | shapes | 0 | - | no | B | B |
  | G | G | 2 | shapes | 0 | capo 0 | no | A | A |
  | G | G | 2 | shapes | 0 | capo 4 | no | A | A |
  | G | G | 2 | shapes | 0 | transpose +2 | no | B | B |
  | D | G | - | shapes | 0 | - | yes | 5 · D | D |
  | G/B | G | - | shapes | 0 | - | yes | 3 · B | G/B |
  | Am | Am | - | shapes | 0 | - | yes | 6 · A | Am |
  | E7 | Am | - | shapes | 0 | - | yes | 3 · E | E7 |
  | Bb | C | - | shapes | 0 | - | yes | b7 · Bb | Bb |
  | N.C. | G | - | shapes | 0 | - | yes | N.C. | none |
  | Xyz | G | - | shapes | 0 | - | no | Xyz | none |

  Plus: no key (`KeyContext(declared: nil, detection: nil)`) with the song's Nashville on -> note only; two songs open in turn, one with Nashville on and one off, give "5 · D" and "D" with the same profile (per-song numbers, R158 Q2); bass view off -> `RenderChord.text` byte-identical to today's goldens (`EditingPipelineGoldens`); `bassNotes` on with `playsBass` off still gives bass notes (R158 Q7); `DisplayPrefs(options)` of options with `bass` set equals the same without it (the precedence guard).
- **`ScaleTests`** (P8-4a): `SongKey.scaleNotes` for G, F, Bb, Eb, E, D, Am, Em, Dm, Bm, F#m, Cm, and the pinned edge rows F# (`F# G# A# B C# D# F`, white-key rule) and Gb; header text for major and minor; nil header without a key.
- **`BassNeckChordTests`** (P8-4a, LiveLayout, pure): `StagePasses.chord(at:plan:pinned:)` on a laid-out corpus song: the chord at the reading line at offset 0, mid and overflow; across a pass boundary it follows P8-2's current pass; a fitting song and a two-column plan give the current pass's first chord (pass 1, or the pinned pass after a jump); a line of `N.C.` keeps the previous chord flagged dimmed; the neck window for EADG home 3 is frets 2-6 and shifts to include a suggested position outside it.
- **`TuningBassTests`** (P8-4a): `Tuning(bassLetters:)` rows "EADG" -> 28 33 38 43, "BEADG" -> 23 28 33 38 43, "DADG" -> 26 33 38 43, "EADGC" -> 28 33 38 43 48, "Eb Ab Db Gb" -> 27 32 37 42, "B0 E1 A1 D2 G2" -> 23 ..., "EAD" -> nil, "XYZ" -> nil, 6 letters -> nil; `InstrumentProfile` lenient decode (missing fields default, a 5-note tuning with `strings: 4` falls back to `bassStandard4`).
- **`BassFretboardTests`** (P8-4a, the core the mini neck and P8-4b's strip share): `positions` (EADG, G -> E3, A10, D5, G0, G12); `homeFret` rows (EADG: G -> 3, D -> 5 on A, E -> 0; BEADG: G -> 3 on E, D -> 3 on B); `suggested` rows, EADG home 3 (key G): G -> E3, C -> A3, D -> A5, Em -> E0, Am -> E5 (tie with open A goes to the lower string), B -> A2, F# -> E2; EADG home 5 (key D): A -> E5, Bm -> E7, G -> D5; BEADG home 3 (key D): D -> B3, G -> E3, B -> B0; DADG home 0 (key D): D -> string 0 fret 0, A -> A0, G -> G0; `shape` rows: G at E3 in key G -> fifth D at A5, fifth below none (no lower string), octave G at D5 and the open G string; Bdim -> b5; G/B -> octave only.
- **`WalkUpTests`** (P8-4b): the golden corpus (8.13 item 1), plus the legacy rows as named cases (from, to, key -> top-1): G->C in G "A B"; C->G in G "B A"; G->D in G "F# E"; G->Em in G "F#"; C->D in G "C#"; D->C in G "Db"; G->G7 none; G->A in G "G#"; E->F in C none; C->F# in C "F"; Bb->Eb in C "C D"; Bb->C in C "B"; G->C with no key "B"; and the documented changes: E->Am in Am "F# G#" (was "F G"), Bollywood "F G#"; A7->Dm in C "B C#"; F->G before Am in Am `hold` then "F#". Breakdown rows: G->C in G at Pop lists `genrePrior` 3, `resolution` 2 for `A B`, summing to its score.
- **`WalkUpPropertyTests`** (P8-4b): the invariants in 8.13 item 2.
- **`ChordBeatsTests`** (P8-4b): rows of one line and `{time}` -> beats and source: `| [G] . . . | [C] . . . |` -> 4, 4 (barLines); `| [G] [D] | [C] |` -> 2, 2, 4; `| [G] | % | [C] |` -> 8, 4; `[G] / / / [C] / /` -> 4, 3 (beatMarks); `[|] [G] [|] [C] [|]` -> 4, 4; 3/4 with `| [G] | [C] |` -> 3, 3; 6/8 -> pulses 2; `{time: 4/4}` and a lyric line with one chord -> 4 (meterLine); two chords on a lyric line without marks -> unknown, unknown; no `{time}` and no marks -> unknown; a grid section contributes nothing. `Metadata.pulses(ofTime:)` and `MetronomeMeter.pulses` agree for 2/4, 3/4, 4/4, 6/8, 9/8, 12/8, 5/4.
- **`BassLineTests`** (P8-4b): `.sections` annotates only section-final changes; `.everyChange` every unsuppressed change; `.off` changes nothing; a pick shows at `.sections` on a mid-section change; into a `{chorus}` stub uses its target's first chord; `N.C.` and a chord-less section break the chain; the last chord gets none; an arranged order (R122) with `origins` changes the target, and a pick whose `to` differs from the played target falls back to the rules; the song's feel overrides the profile's; Nashville on gives degrees; a `hold` pick shows nothing.
- **`ChordAnchorTests`** (P8-4b, pure, through real `RenderModel`s from small `.cho` texts): a pick resolves on an unchanged song; survives a transpose, a capo, a setlist key override, and an edit below the section's first two lines; re-anchors when a same-label section is inserted before it (occurrence shifts, `fp` unique); re-anchors within the section when a chord is inserted before A; G changed to G7 keeps it; is **unmatched** when A's chord is deleted, when the target bass changes, when the section is deleted, and when two same-label sections share the `fp` (ambiguous); an unmatched pick is still in the encoded sidecar; a loose-lines anchor resolves; timing overrides resolve by the same rules.
- **`BassPrefsSidecarTests`** (P8-4b, extend `LibrarySidecarLenienceTests` style): a v4 sidecar migrates to 5 with empty `bass` and is written at 5 on save; `bass` round-trips; one bad pick (unknown kind, 6 offsets, offset 12, no anchor) is dropped and the others kept; a bad `genre` reads nil; a malformed `timing` reads empty while `walkUps` survive; a v6 file opens read-only; `updateBassPrefs` leaves the `.cho` bytes, its mtime and the index projection unchanged.
### 11.2 LiveLayout (in-process, extend `LiveLayoutEngineTests`)

A corpus song laid out with bass view and `chordBeside` on, in full-song and arranged plans with a Chords-only pass (P8-2): `LayoutAudit` clean (no overlapping runs, nothing clipped); a chord unit's width equals the sum of its runs plus gaps; the plan with bass view off is unchanged. P8-4b adds: with walk-ups at Every change, approach runs are placed as part of each chord unit (`LayoutAudit` clean, no run overlaps the next chord), and the stage hook on P8-2's passes gives each pass the approach into the pass that follows it.

### 11.3 SegueUI (in-process, `Packages/SegueUI/Tests/SegueThemeTests`)

`InstrumentProfileStoreTests`: load, save, reset, Reset All Settings includes it, string-count switch resets the tuning, turning "I play bass" on also turns bass notes on. `BassToggleTests`: the editor's Bass segment is present with the profile off, flips the store and re-renders the preview with notes while the visual canvas keeps chart chords and the sidecar prefs are unchanged; the Nashville button still flips only the song's own setting in bass view; `LiveSession.dispatch(.toggleBassNotes)` flips the store, relayouts and flashes with or without the profile; the stage header's scale text. `StageBassNeckTests`: the neck shows only with bass view and `stageNeck` on, sits at the left of the status band with the metronome at the right, follows a scripted scroll offset chord by chord, uses EADG without the profile and the profile's 5-string tuning with it, hides in a break and past the end, and its accessibility value. P8-4b: `BassFretboardView` snapshots (compact, light and dark) in the existing diagram snapshot style; `WalkUpPickerTests`: clicking a run in the editor preview opens the popover with the ranked rows and "Nothing here", choosing B writes the sidecar through `updateBassPrefs` (not the `.cho`) and redraws the run as a pick, ⌘Z restores the suggestion, "Reset to suggestion" removes the pick, the library sheet groups changes by section and lists an unmatched pick with Remove, the feel picker writes `genre` and "Default" removes it, a read-only song disables picking, and the stage draws the pick with no button; analytics records `walkUpPick` and one `walkUpPicked` per tuple per day.

### 11.4 The one UI test

`SegueBassE2ETests.testBassProfileShowsSoundingRoots` (new file `UITests/SegueBassE2ETests.swift`, added to `UITests/e2e-map.tsv`): fresh library -> create a song in text mode with `{key: G}`, `{capo: 2}` and `[G]Hello [G/B]there [C]friend` -> Settings > Instrument -> I play bass, 5 strings, BEADG -> back to the editor: the preview's chord row reads "A", "C#", "D" -> Rehearse that song (R150) -> the stage chord row reads the same, the header shows "Sounding A major" -> the mini neck (`segue.live.bassNeck`) reads "A, ..." -> press `b` -> the stage reads "G", "G/B", "C" and the neck is gone -> End. Written in P8-4a. P8-4b does not extend it: its behaviour is covered in-process (11.1-11.3).

### 11.5 Bass chart PDF (P8-4a step 3c, inside the phase 4 export's test suites)

Integration, through the real export (4-export.md "Test strategy"): export the 11.4 song as a single chart with "Bass chart" on: PDFKit text extraction contains "A", "C#", "D" in the chord rows, not "G/B"; the header reads the sounding key with no capo and the scale line; "Include diagrams" is disabled and no diagram is drawn; the suggested file name ends " (Bass).pdf". A two-song songbook with a slot key override prints the overridden sounding notes. With "Bass chart" off the PDF is byte-for-byte what it was before this change (the export's own snapshot references).

## 12. Steps

**P8-4a** (not blocked; in parallel with P8-2 / P8-3 and P8-5, R155)

1. Core: `InstrumentProfile`, `BassView`, `DisplayOptions.bass` and `withBass(_:forcingNotes:)`, bass tunings and `Tuning(bassLetters:)`, `DisplayTransform.concertKey` / `bassText` (numbers from the song's Nashville toggle), `Nashville.degree`, `SongKey.scaleNotes`, `RenderChord.detail`, `RenderHeader.scale`, header key rule, and the fretboard core `BassFretboard` (7.1). Suites: `BassNoteTests`, `ScaleTests`, `TuningBassTests`, `BassFretboardTests`, the existing editing goldens.
2. Stage layout (**starts after P8-2's step 2 has landed**): `TextRole.chordDetail`, chord unit measurement and placement, audit; `StagePasses.chord(at:plan:pinned:)` for the neck. Suites: `LiveLayoutEngineTests`, `BassNeckChordTests`.
3. UI: `InstrumentProfileStore`, Settings > Instrument, Reset All Settings, analytics keys, editor Bass segment (always present) and the canvas rule, preview drawing, library preview, stage render path, `LiveCommand.toggleBassNotes` + `b`, key help, header scale line. Suites: `InstrumentProfileStoreTests`, `BassToggleTests`, `ServicesVocabularyTests`, `KeyHelpTests`.
   3b. Mini neck: `StageBassNeck`, its place in the status band, the status line inset. Suite: `StageBassNeckTests`.
   3c. Bass chart PDF: the export toggle, rendering, file name and metadata (7.4), only if the phase 4 export exists; else stop and ask. Suites: 11.5.
4. `SegueBassE2ETests`; one `make quick`; one `make e2e-one TEST=SegueBassE2ETests` (plus the phase 4 export's E2E class once, if 3c changed it).

**P8-4b** (after P8-4a and P8-2's layout step; P8-6 follows it, R161)

5. **Walk-up core:** `BassGenre`, `WalkUpKind`, `WalkUpContext`, passing scale, suppression S1-S6, candidates, `WalkUpWeights.standard`, ranking with breakdown, spelling, legacy `notes`; `Metadata.pulses(ofTime:)` and `ChordBeats`. Write `WalkUpCorpus.json` first (8.13 item 1) and drive the rules to it. Suites: `WalkUpTests`, `WalkUpPropertyTests`, `ChordBeatsTests`.
6. **Song level:** `BassPrefs`, `ChordAnchor` + `ChordAnchors.resolve`, the `SectionAnchor` coding helpers (coordinate with P8-2), sidecar schema 5 (migrator step, `PartialSidecar`, lenient picks), `LibraryStore.updateBassPrefs` / `SongFiles.writingBassPrefs`, `BassLine.changes` / `annotate`, `RenderChord.approach`, `RenderDiagram.bass` and the diagrams rule (7.2). Suites: `BassLineTests`, `ChordAnchorTests`, `BassPrefsSidecarTests`, `DiagramModelTests`, the editing goldens (unchanged with walk-ups off).
7. **Layout:** `TextRole.approach`, the run in chord unit measurement, the stage hook in `SongPreparation` on P8-2's passes (with section origins). Suite: `LiveLayoutEngineTests`.
8. **UI:** profile fields and the Walk-ups and Fretboard controls in Settings > Instrument; `BassFretboardView`, the strip's `.bass` case, the "Fretboard" button and "Bass, BEADG" label (6.5); run drawing and the run button in the previews; the popover; the Walk-ups list (editor and library); feel picker; undo; analytics. Suites: `BassFretboardView` snapshots, `WalkUpPickerTests`, `BassToggleTests`, `ServicesVocabularyTests`.
9. One `make quick`. No `make e2e-one` (no UI test class changes).

## 13. Files owned

- New (P8-4a): `SegueCore/Sources/Editing/InstrumentProfile.swift`, `SegueCore/Sources/Diagrams/BassFretboard.swift`, `SegueUI/Sources/SegueUI/Settings/InstrumentProfileStore.swift`, `Settings/InstrumentSettingsView.swift`, `Live/StageBassNeck.swift`, `AccessibilityID+Bass.swift`, the P8-4a test suites above, `UITests/SegueBassE2ETests.swift`; the export toggle's files in whatever folder phase 4 creates (step 3c).
- New (P8-4b): `SegueCore/Sources/MusicTheory/WalkUp.swift` (+ `WalkUpWeights.swift`), `SegueCore/Sources/Library/ChordBeats.swift`, `Library/BassLine.swift`, `Library/BassPrefs.swift`, `Library/ChordAnchor.swift`, `Library/LibraryStore+Bass.swift`, `Packages/SegueCore/Tests/Fixtures/walkups/WalkUpCorpus.json`, the P8-4b suites above; `SegueUI/Sources/SegueUI/Diagrams/BassFretboardView.swift`, `Editor/WalkUpPopover.swift`, `Editor/WalkUpsSheet.swift` (shared by the library).
- Changed (P8-4b): `Library/Sidecar.swift` (schema 5, `bass`), `Library/SidecarCodec.swift` (migrator step 4, `PartialSidecar`), `Library/SlotArrangement.swift` (the `SectionAnchor` coding helpers only; P8-2 owns the rest of the file's changes), `Library/LibraryStore.swift` (`updateBassPrefs`), `ChordPro/SongDocument+Derived.swift` (`Metadata.pulses`), `Shows/Metronome.swift` (`pulses` delegates), `Editing/InstrumentProfile.swift`, `Editing/RenderModel.swift` (`approach`), `Services/AnalyticsEvent.swift` and `AnalyticsEvent+Throttle.swift` (row 24), `Library/SongDetailPane.swift` and `Library/LibraryViews.swift` (context menu), `Settings/InstrumentSettingsView.swift`.
- Additive hunks: `Editing/DisplayOptions.swift`, `Editing/RenderModel.swift`, `Editing/RenderSectionBuilder.swift`, `Diagrams/Tuning.swift`, `MusicTheory/Nashville.swift`, `MusicTheory/SongKey.swift`, `LiveLayout/LayoutRequest.swift` (roles), `LiveLayout/SongMeasurement.swift`, `LiveLayout/LineLayout.swift` / `LayoutPlan.swift` (extra runs), `LiveLayout/StagePasses.swift` (P8-2's file: the neck's chord lookup, coordinate by hunk), `LiveLayout/SongPreparation.swift` (P8-4b walk-up hook only; coordinate with P8-2), `Shows/LiveCommand.swift`, `Shows/InputBindings.swift`, `Shows/KeyHelp.swift`, `Services/AnalyticsEvent.swift`, `SegueUI/Settings/SegueSettingsView.swift`, `Settings/AppModel+Settings.swift`, `App/AppModel.swift`, `Live/LiveDependencies.swift`, `Live/LiveSession.swift` (context), `Live/LiveSession+Viewport.swift`, `Live/LiveSession+Commands.swift`, `Live/StageChrome.swift`, `Live/StageSongBody.swift`, `Live/LiveView.swift` (mini neck in the status band, status line inset; P8-2 edits the same file for the map and metronome, coordinate by hunk), `docs/release/specs/WS3-services.md` (catalogue), `Editor/EditorTopBar.swift`, `Editor/SongEditorView.swift`, `Editor/SongEditorViewModel.swift`, `Editor/SongEditorViewModel+Options.swift`, `Rendering/SongSummary.swift`, `Rendering/SongSheetView.swift`, `Rendering/LyricLineLayout.swift`, `Diagrams/DiagramStrip.swift`, `UITests/e2e-map.tsv`.
- Docs: the user guide's editor and stage pages gain a short "Playing bass" section with captures in the next store media pass (R140), not in this workstream.

## 14. Done criteria

**P8-4a done when:** with the bass-note view off the app is byte-for-byte unchanged (editing goldens, layout corpus, export references); with it on (with or without "I play bass"), every song's preview, the library preview and the stage show bass notes at sounding pitch for every capo, capo mode, transpose and slot override row in 11.1; "5 · D" follows each song's own Nashville toggle and the chord beside works; the header shows the sounding key and scale; the editor Bass segment and stage `b` flip the same user-level setting for anyone; the mini neck shows the chord at the scroll position bottom left, quietly, and only when switched on; the "Bass chart" PDF option prints the same view (or step 3c was handed back because phase 4 was not built); no sidecar or `.cho` byte changes from any bass action; the visual canvas still edits chart chords; Settings > Instrument persists and resets; analytics events fire; the new suites, `make quick` and `SegueBassE2ETests` are green.

**P8-4b done when:** the editor strip shows bass fretboard cells in the profile's 4- or 5-string tuning with the suggested position, fifth and octave per the tables; with walk-ups on, the preview, library preview, stage (on P8-2's played passes) and bass chart PDF show one walk-up per change, the pick else the top candidate, ranked by section 8.3 with passing notes from the departing chord and the song's feel; written stepwise lines (bVI-bVII-i) offer "nothing" and the passing note; beats come from bar lines, beat marks or `{time}` else cap at two notes; picks and feel are saved in sidecar schema 5 (never the `.cho`), survive the edits in `ChordAnchorTests`, and an unmatched pick is kept and listed, never applied; alternates exist only in the editor and library; the golden corpus (about 60 cases) and property tests pass (the by-ear check of the walk-ups is P8-6a's, R162 Q5); nothing in P8-4b makes a sound; everything is off by default except the fretboard cells for a bassist; suites and `make quick` green.

## 15. Closed questions

Closed by Ryan on 2026-10-30 (**R158**; Q4 and Q5 went to research under **R160** and were closed by **R161**; letters refer to the options as they were offered). The body above already reflects each answer.

1. **Visual editor canvas in bass view.** (a) Chart chords stay on the canvas; bass notes show in the preview, on stage and in the bass chart PDF, with the quiet hint (R158 Q1; decision 5).
2. **Nashville button in bass view.** (b) It stays the per-song Nashville toggle, and "5 · D" follows each song's setting; there is no profile `numbers` field (R158 Q2; decisions 6-7). This differs from the recommendation.
3. **Stage key.** `b` for Bass Notes (R158 Q3; section 6.5).
4. **Walk-ups: density and placement.** Went to research (R160), closed by R161: Off / Into sections / Every change, off by default; one walk-up per change on charts and stage, small and muted after the departing chord; alternates in the editor and library only (sections 8.1, 8.6, 8.8, 8.9).
5. **Minor-key walk-ups.** Went to research (R160), closed by R161: passing notes come from the departing chord, so V-i walks the raised 7 (`F# G#` in pop, rock, worship; `F G#` with a Bollywood feel) (section 8.3).
6. **Something compact on stage for positions.** (c) A mini neck on stage for the chord at the current scroll position, optional and quiet, built in P8-4a (R158 Q6; section 7.3). This differs from the recommendation; the positions strip is dropped.
7. **Bass view without the profile.** (b) Anyone can turn on the bass-note view, not only with "I play bass" (R158 Q7; decision 2, sections 6.4-6.5). This differs from the recommendation.
8. **PDF, print and Singer view.** (b) A "Bass chart" PDF export option, built in P8-4a on the phase 4 export (R158 Q8; section 7.4). Print of the normal chart and Singer view are unchanged. This differs from the recommendation.
9. **Per-song escape hatch.** (a) None (R158 Q9).
10. **Scale spelling in sharp-heavy keys.** (a) The chart rule, white keys natural: F# major reads "F# G# A# B C# D# F" (R158 Q10; decision 8).
11. **The chord beside the note.** (a) The concert chord ("A/C#" under capo 2) (R158 Q11; decision 3).
12. **Suggested fret position heuristic.** (a) The fixed box around the key's tonic, lowest pitch wins (R158 Q12; section 7.1); used by the mini neck now and the editor strip later.

Closed by Ryan on 2026-10-30 (**R161**), the open questions of `docs/research/phase8-bass-patterns.md` section 8 (numbered on from the list above):

13. **Minor V-i** (research Q1). (a) The chord-A override rule: melodic `F# G#` first for pop, rock and worship, harmonic `F G#` for a Bollywood feel; the old `E->Am "F G"` row changes (section 8.3).
14. **Genre source** (research Q2). (a) A per-song field defaulting from the profile (sections 8.7, 8.10).
15. **Rock bVI-bVII-i and other whole-step root moves** (research Q3). Neither (a) nor (b): the user chooses in the app; a "nothing" candidate and a passing-note candidate are both offered (rule S2, section 8.3; "nothing" ranks first, R162 Q1, section 16).
16. **Candidates surface** (research Q4). (a) The stage shows one walk-up (the pick, else the top candidate) and stays silent; alternates and audition live in the editor and library only (sections 8.1, 8.9).
17. **Pinned choices** (research Q5). (a) Stored per chord change in the song's sidecar, never the `.cho` (sections 8.10, 8.11).
18. **Durations** (research Q6). (b) Beats estimated from bar lines or `{time}` when present, otherwise at most two notes (section 8.5).
19. **Editor fretboard strip.** Stays in P8-4b with the walk-ups (R161; section 7.2).
20. **Audio.** Not in P8-4b: a new workstream P8-6 (`P8-6-audio.md`) after P8-4b (R161).

## 16. Closed questions (P8-4b)

Closed by Ryan on 2026-10-30 (**R162**; letters refer to the options as they were offered). The body above already reflects each answer.

1. **Which candidate shows first in a written stepwise line (bVI-bVII-i, `C - C/B - Am`)?** (a) "Nothing" first in every feel, the passing note as the alternate (R162 Q1; rule S2, section 8.3).
2. **Does a saved pick show where the density would skip that change?** (a) Yes: while walk-ups are not Off, a pick always shows; with Off, nothing shows (R162 Q2; section 8.6).
3. **Chromatic marker.** (a) Keep the small "°" after chromatic notes on charts and stage (R162 Q3; section 8.8).
4. **Walk-ups without the bass-note view.** (a) Walk-ups show only in the bass-note view; the guitar chart stays unchanged (R162 Q4; section 8.6).
5. **Owner review gate.** Replaced (R162 Q5): there is no owner-review CSV gate. P8-4b ships on the golden corpus and property tests; walk-ups are judged by ear in P8-6a once audio lands, as a manual step for Ryan (section 8.13 item 3; P8-6 sections 10.2 and 16). This differs from the recommendation: the env-gated CSV export test and the 85% / 5% acceptance gate are removed.
6. **Sidecar version for both workstreams.** (a) One bump, 4 -> 5, in P8-4b, with `bass.timing` decoded and preserved now and filled by P8-6 (R162 Q6; section 8.10).
