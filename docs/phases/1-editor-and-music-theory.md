# Phase 1 - Editor & Music Theory

> Canonical context: `docs/00-vision.md` (decisions), `docs/research.md` (verified facts) and `docs/decisions.md` (closed answers). This doc is standalone for one build session; it depends on phase 0 (walking skeleton: Core package, ChordPro parser v0, library folder, basic live view).

## Goal

Make a song chart fast to write and correct, and make one chart serve keys, guitar and voice: transpose, capo toggle, Nashville view, and chord diagrams for guitar (standard, alternate tunings, custom shapes) and piano.

## Scope

- `MusicTheory` module in `SegueCore`, built on **Tonic** (AudioKit, MIT, pinned in phase 0): chord model, parsing chord symbols, transposition, capo, Nashville numbers, key detection, voicing lookup.
- ChordPro parser/serializer upgraded to a lossless syntax tree (round-trip fidelity).
- Song editor with two toggleable modes: **Text** (ChordPro source) and **Visual** (lyrics with chords placed on syllables).
- Chord autocomplete, live preview.
- Chord diagram components: guitar (any tuning, capo-aware, custom shapes) and piano.
- Per-song display toggles: transpose, capo shapes vs concert pitch, Nashville, diagrams on/off (**off by default**). Stored in the song sidecar.

## Non-goals

AI cleanup and paste conversion (phase 3), setlist/live-mode features (phase 2), PDF (phase 4), tab/grid editing beyond pass-through (blocks are preserved, not edited visually), audio (P8-6).

## Data model

### Chord representation

Tonic supplies the pitch/note/key/chord-type vocabulary (`Note`, `NoteClass`, `Key`, `Chord`, `ChordType`). Segue wraps it rather than re-implementing it:

```
ChartChord { tonic: Tonic.Chord?          // pitch content: root + type, used for transposition, diagrams, key scoring
             symbol: ChordSymbol           // what the author wrote, parsed: root spelling, quality text,
                                           // extensions, alterations, bass: Tonic.NoteClass?
             original: String }            // verbatim token for round trips
```

- Our own `ChordSymbol` parser handles real-world chart spelling (`C7(#9)`, `Dsus4`, `G/B`, `N.C.`, `maj9`, `-7`) and maps it onto a Tonic `ChordType`; where Tonic has no matching type, `tonic` is nil but the chord still transposes by root/bass and renders verbatim suffix.
- Spelling decisions (below) are ours; Tonic's key/note-spelling helpers are used where their output matches the rules, and the property tests pin the behaviour so a Tonic upgrade cannot silently change it.

- Parse symbols like `C`, `F#m7b5`, `Bbmaj9`, `Dsus4`, `G/B`, `C7(#9)`, `N.C.`. Unparseable tokens are kept as `UnknownChord(original)`: displayed verbatim, never transposed, flagged in the editor.
- `original` preserves the author's spelling for round trips; rendering uses a canonical formatter only when the chord has been transformed.

### Transposition and enharmonic spelling

- Transpose by semitones relative to the song key. **In-key** chords follow the **target key signature**: sharp keys (G, D, A, E, B, F#) spell with sharps, flat keys (F, Bb, Eb, Ab, Db, Gb) with flats; C/Am uses sharps for raised degrees except bVII and bIII, which use flats (Bb, Eb). **Out-of-key** chords keep the author's accidental family (`Ab` in C becomes `Bb` in D, never `A#`; a natural when it lands on a white key; an out-of-key natural takes its degree's usual family: b2 b3 #4 b6 b7).
- Slash bass notes are spelled in the same key context.
- **Key detection** (deterministic, in Core): if the song has no `{key}`, score every major/minor Tonic `Key` against the chord set (diatonic fit, weighted by first/last chord and frequency), and show the winner as "inferred" until confirmed. When the top two scores are within a margin, mark the result **ambiguous**; phase 3's AI cleanup may resolve only ambiguous cases.
- Transposition is a **view transform**, not an edit, unless the user picks **"Apply transposition to source"**: it rewrites every chord token and `{key}` (and **adds a `{key}`**, the detected key transposed, when the song had none), **keeps `{capo}` unchanged**, and any custom `{define}` shape whose chord name no longer appears (or no longer matches the rewritten chord) is **flagged for review** in the editor rather than silently deleted or auto-shifted. The rewrite is one undoable edit.

### Capo semantics

- `{capo: N}` in the source states that chords as written are **shapes**. Concert pitch = shapes + N semitones.
- Toggle per song: **Shapes** (guitar view, as written) vs **Concert** (keys/voice view, transposed up N). Diagrams in Shapes mode show capo position; piano diagrams always use concert pitch.
- A "suggest capo" helper lists capo positions that turn the concert key into open-friendly shape keys (C, G, D, A, E, Am, Em).

### Nashville rendering

- Degree relative to the displayed key: `1 4 5 6m`, accidentals as `b7`, `#4`; quality suffix kept (`2m7`, `57/7`); slash bass as a degree (`1/3`).
- Minor keys: numbered relative to the **relative major** (standard Nashville practice): in A minor, `Am F G E7` reads `6m 4 5 3(7)`. No setting in this phase.

### Tunings and custom shapes

```
Tuning { name, strings: [Pitch] }   // low to high, e.g. Standard E2 A2 D3 G3 B3 E4; Drop D; DADGAD; Open G
GuitarShape { frets: [Int?] (nil = muted), fingers: [Int?], baseFret: Int, barres: [Barre] }
PianoVoicing { notes: [Pitch] }    // concrete pitches, left hand optional
```

- Song tuning stored in the sidecar (and emitted as a `{meta: tuning ...}` for portability).
- Custom shapes use ChordPro `{define: Gadd9 base-fret 1 frets 3 2 0 2 0 3 fingers 2 1 0 3 0 4}` so they live in the song file. `{define}` with `keys` (ChordPro 6 piano defines) is supported for custom piano voicings.
- Shape lookup order: song `{define}` -> user shape library (app support JSON) -> **curated overrides** (a small hand-checked set of common open/barre shapes in standard tuning, authored by us, so no licence question) -> **algorithmic generator** for the current tuning.
- Generator: for the chord's pitch classes (from Tonic), enumerate fingerings within a 4-fret span per position across the tuning's strings, require root (or slash bass) as lowest sounding note and all essential tones (3rd, 7th when present) covered, then rank by playability (fewest fingers, open strings, barre detection, span, position). Works identically for Drop D, DADGAD, Open G and any custom tuning.

### Lossless syntax tree

Parser produces a concrete syntax tree that keeps whitespace, comments, unknown directives and directive spelling. `serialize(parse(x)) == x` byte-for-byte for every fixture. All editor mutations operate on the tree and emit minimal text edits.

## Editor UX

### Text mode

- Native text view (TextKit 2) with syntax colors for chords, directives, section markers and comments.
- **Chord autocomplete** on `[`: suggests chords already in the song first, then diatonic chords of the key, then common extensions; typing filters; Return inserts `[Chord]`.
- **Text input settings for lyrics:** automatic spelling correction, continuous spell-checking, grammar checking, text replacement, smart quotes, smart dashes and automatic capitalization are all off in both editor modes (lyrics are often romanized Hindi, and macOS would "correct" them into English). Set on the TextKit 2 view, not left to system defaults, and asserted in an E2E test.
- **Chord autocomplete triggers only on `[`** (and the visual-mode chord popover), never on plain word typing, so Hindi words that happen to look like chord names ("Am", "Dm", "Bas") are never suggested or converted.
- Directive completion on `{` (title, artist, key, capo, tempo, time, sections, define).
- Inline diagnostics: unknown chord, unclosed section, malformed directive.

### Visual mode

- Lyrics rendered with chords above syllables (same renderer as the live preview).
- Click a syllable to add a chord (popover with autocomplete); adding where a chord already sits **replaces** it (no stacking); drag a chord left/right to snap to another character; delete with Backspace; Option-drag duplicates.
- In Nashville view chords can be entered as **numbers** (`1`, `4`, `6m`, `b7`, `5/7`, `3(7)`) in the popover and in text-mode `[` completion, resolved against the display key and written to the source as letters; letter names are accepted too.
- Section headers editable (Verse, Chorus, Bridge, custom labels); lyrics editable inline.
- Tab/grid blocks shown read-only with "Edit in text mode".

### Sync between modes

- Single source of truth: the syntax tree. Both modes are views; switching never re-parses lossy output.
- Visual edits map to tree operations (insert chord at character offset, move chord, edit lyric run) and then to text edits, so undo/redo is one shared stack.
- Cursor/selection position is mapped across a mode switch (same line + character offset).

### Live preview

Split pane in text mode: rendered chart updating as you type (debounced ~100 ms, incremental re-render of the changed section). Preview honours the current transpose/capo/Nashville toggles and shows a diagram strip of all chords in the song.

## Diagram components

- **GuitarDiagramView**: SwiftUI `Canvas`, n strings from the tuning, base fret label, barres, muted/open markers, capo bar in Shapes mode. Scales crisply for stage use; dark and light themes.
- **PianoDiagramView** (no existing library): **compact one-octave** keyboard (stage-readable at small sizes) with highlighted chord tones and the root marked distinctly; the bass note (slash bass or root) is shown as a separate marker/label under the keyboard rather than a second octave. Voicings that span more than an octave fold into the octave for display. Default voicing generator: root position close voicing within C3-C5, inversion chosen to minimise movement from the previous chord in the song (smooth voice leading), slash bass in left hand. Users can tap keys to save a custom voicing as a `{define ... keys ...}`.
- **Diagram strip**: all unique chords of the song in order of first appearance, togglable per instrument.

## Test strategy

Integration-first: tests drive real components (parser, syntax tree, editor model, file store, GRDB index, rendering) on real temp-dir libraries. Unit-level tests only for the genuinely tricky pure logic.

- **Song pipeline integration suite:** for each fixture song in the corpus, load it through the real `LibraryStore`, apply view transforms (transpose -12...12, capo Shapes/Concert, Nashville) through the same render model the preview and live view use, and assert rendered chord text against golden expectations. Then "Apply transposition to source", save, re-open from disk and assert the file bytes, `{key}`, unchanged `{capo}`, flagged `{define}` shapes, and that the index reflects the new key.
- **Round-trip corpus:** every fixture `.cho` round-trips byte-for-byte through parse -> tree edits (scripted operation fixtures) -> serialize -> disk -> reload; edits change only the touched text.
- **Pure-logic tests (kept deliberately small):** transposition property test (for every parseable chord and n, transpose there and back restores the original spelling; spelling follows key-signature rules; Nashville is transposition-invariant, including relative-major numbering in minor keys); key-detection table over the fixture corpus (expected key or "ambiguous"); guitar generator yields a playable shape for every corpus chord in Standard, Drop D, DADGAD and Open G, and curated overrides win where defined.
- **Romanized Hindi corpus:** fixture songs with Hindi lyrics in Latin script (original fixture text) round-trip byte-for-byte; words like "Am", "Dm", "Bas" inside lyrics are never parsed or rendered as chords.
- **Snapshot tests** for guitar and piano diagram views (light/dark) - these double as integration checks of generator + renderer.
- **UI E2E (XCUITest, clean temp library per run):** create song in text mode with chord autocomplete; switch to visual, click a syllable to add a chord, drag another, undo, switch back and assert the exact source and cursor position; toggle capo/transpose/Nashville and assert rendered chords; add a custom shape and confirm `{define}` written to the file on disk; apply transposition to source and confirm the flagged-shape warning appears.

## Acceptance criteria

1. Every golden fixture round-trips byte-for-byte; editing in either mode changes only the touched text.
2. Transposing a song by any interval and back yields the original source spelling for in-key chords and common borrowed chords (bII, bIII, #IV, bVI, bVII); rarer spellings return in the standard spelling (see decisions.md).
3. Capo toggle shows guitar shapes vs concert chords correctly; piano diagrams always concert.
4. Nashville view renders correctly for major and minor keys (minor keys numbered from the relative major), including borrowed chords and slash chords.
5. Guitar diagrams render for standard, Drop D, DADGAD and Open G; custom `{define}` shapes override the built-ins.
6. Compact one-octave piano diagrams render every chord in the fixture corpus with root and bass clearly marked.
7. Songs without `{key}` show an inferred key (or "ambiguous") matching the key-detection table; "Apply transposition to source" keeps capo and flags mismatched custom shapes.
8. Mode switching keeps cursor position and shares one undo stack.
9. Editor stays responsive (< 16 ms per keystroke) on a 200-line song.
10. Typing romanized Hindi lyrics in either mode is never autocorrected, spell-flagged or quote-substituted, and no lyric word is ever turned into a chord.

## Resolved decisions

See `docs/decisions.md` for the audit trail.

1. **Theory engine: Tonic as a dependency.** Our `ChartChord`/`ChordSymbol` wrap Tonic types; spelling rules are pinned by tests so Tonic upgrades cannot drift them.
2. **Visual editor: TextKit 2 in AppKit** via `NSViewRepresentable`; shares the text engine with text mode.
3. **Guitar shapes: algorithmic generator per tuning + our own curated overrides.** No third-party chord database, so no licence risk.
4. **Nashville in minor keys: relative major** (Am in A minor = 6m). No user setting this phase.
5. **Apply transposition to source: rewrite chords and `{key}` (adding the inferred key when there is none), keep `{capo}`, flag custom shapes** that no longer match.
6. **Key detection: deterministic scorer** in Core; AI (phase 3) only resolves results marked ambiguous.
7. **Piano diagram: compact one octave**, bass marked separately.
8. **Chords Tonic cannot model** (e.g. `7(#9)`, `6/9`, `add9`, `13sus4`): our own small interval table in `MusicTheory` maps them to pitch content, so they transpose and get generated diagrams like any other chord. Verified against the fixture corpus in the first build session.
9. **Nashville header in minor keys** shows both, e.g. "Am (rel. C)", so the relative-major numbering is obvious.

## Open questions

None open.
