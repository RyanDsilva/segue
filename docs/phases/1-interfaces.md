# Phase 1 - Frozen interfaces

Cross-unit contract for the parallel phase 1 build (spec: `1-editor-and-music-theory.md`). Every type and signature below exists as a compiling skeleton. Bodies that are still `fatalError("unimplemented: unit X")` are that unit's work. Change a frozen signature only by agreement with the units that consume it. Adding new members is fine.

## Module graph (SegueCore)

```
Support      ChordPro (Tonic)      MusicTheory (Tonic)        <- unit A
                 |                    |
                 |                 Diagrams (MusicTheory, Support)   <- unit B (core)
                 |                    |
                 +------ Editing (ChordPro, MusicTheory, Diagrams, Tonic)   <- unit C
                              |
             Library (ChordPro, Diagrams, Editing, MusicTheory, Support, GRDB)
```

All new targets are in the `SegueCore` product and in the Tuist `targetSettings` strict list. SegueUI reaches them through the `SegueCore` product. The test target `SegueCoreTests` depends on every core module plus Tonic.

## Conventions

- **Text offsets.** `TextEdit.range`, every `SourceSnapshot` range and `SourceChange.selectionAfter` use UTF-16 offsets (NSString, NSRange and TextKit units).
- **Lyric offsets.** `LyricPosition.offset`, `RenderChord.offset` and `EditOperation.editLyrics` ranges count `Character`s per text run between chords (the lyric text with the chords removed, counted run by run). A chord can split a grapheme cluster (`प[G]्यार`), so the joined text's own `Character`s differ: convert through `RenderLine.characterStarts`.
- **Addresses** (`BlockPath`, `ChordRef`, `LyricPosition`) are only valid for the snapshot they came from. After every edit, re-read them from the new `RenderModel`.
- **Source of truth.** The text in the text view is the undoable store. `SourceSnapshot(text:)` re-parses it after each change. A tree operation becomes a `SourceChange`, and the editor applies it to the text storage as one undo group. Both modes therefore share one undo stack and never serialize a whole tree.
- **Pitch.** `PitchClass` is 0...11. Concrete pitches are MIDI `Int` (60 = C4). Spelled notes are Tonic `NoteClass`. Use `NoteClass.pitchClass` and never Tonic's `intValue`, which is a spelling index.

## Unit A - MusicTheory (`Packages/SegueCore/Sources/MusicTheory/`)

| Type / function | Contract |
|---|---|
| `PitchClass`, `NoteClass.pitchClass` | Implemented. |
| `ChordFormula { intervals, essential }`, `.parse(suffix:) -> ChordFormula?` | Our own interval table. Intervals above 11 are allowed (9 = 14). |
| `ChordTones { root, bass?, formula }` (+ `lowest`, `pitchClasses`, `essentialPitchClasses`) | Implemented. **This is the A-to-B contract.** |
| `ChordSymbol { root: NoteClass, suffix, formula, bass: NoteClass? }`, `.text`, `.tones` | `text` is the canonical form, used only after a transform. `tones` is implemented. |
| `ChartChord { tonic: Tonic.Chord?, symbol, original }`, `UnknownChord { original }` | As in the spec. |
| `ChordToken` = `.chord(ChartChord)` / `.noChord(original:)` / `.unknown(UnknownChord)`; `init(parsing:)`, `.original`, `.chord` | The parser never fails. |
| `KeyMode`, `SongKey { tonic, mode }` | `init?(parsing:)`, `name`, `relativeMajor`, `tonicKey`, `transposed(by:)`, `diatonicChordSymbols` (feeds autocomplete). |
| `KeySpelling.spell(_:in:) -> NoteClass` | Key-signature spelling rules. |
| `Transposer(semitones:sourceKey:)`, `Transposer(from:to:)` | `.transpose(_: ChordToken)` and `.transpose(_: ChartChord)`. Identity keeps `original`. N.C. and unknown tokens pass through. Spelling (decisions.md, out-of-key chord spelling): notes of the source key's scale follow the target signature; out-of-key notes keep the author's accidental family (a natural on a white key; an out-of-key natural takes its degree's usual family, `KeySpelling.preferred`); an out-of-key slash bass is spelled as its interval above the root. |
| `CapoMode` (`.shapes` / `.concert`), `Capo.displayOffset(capo:mode:)`, `Capo.suggestions(concertKey:) -> [CapoSuggestion]` | `displayOffset` is implemented. |
| `Nashville.number(for:in:)`, `Nashville.header(for:)`, `Nashville.chord(parsing:in:)`, `Nashville.looksLikeNumber(_:)` | Minor keys number from the relative major. The header reads `"Am (rel. C)"`. `chord(parsing:in:)` is number entry: `1`, `6m`, `b7`, `5/7`, `3(7)` back to a letter chord. |
| `KeyDetector.detect(_: [ChartChord]) -> KeyDetection?`, `KeyDetector.ambiguityMargin` | `KeyDetection { key, isAmbiguous, ranking: [ScoredKey] }`. The margin is a placeholder for A to tune. |

## Unit B - Diagrams

**Core** (`Packages/SegueCore/Sources/Diagrams/`):

| Type / function | Contract |
|---|---|
| `Tuning { name, strings: [Int] }` | Presets are implemented (`.standard .dropD .dadgad .openG`, `presets`). `init?(metaValue:)` and `metaValue` are left for B. |
| `GuitarShape { frets: [Int?], fingers: [Int?], baseFret, barres: [Barre] }` | Frets are relative to `baseFret` as in ChordPro: `nil` = muted, 0 = open. `absoluteFrets` and `pitches(in:)` are implemented. |
| `Barre { fret, strings: ClosedRange<Int>, finger? }` | Value type. |
| `ShapeSource` | `.songDefine` / `.userLibrary` / `.curated` / `.generated`. |
| `ResolvedGuitarShape { shape, source }` | Value type. |
| `PianoVoicing { notes: [Int], bass: Int?, root: PitchClass }` | `foldedPitchClasses` is implemented. |
| `Instrument` | `.guitar` / `.piano`. |
| `ChordDefinition { name, shape: .guitar(GuitarShape) / .piano(keys:) }` | `init?(directiveValue:)` and `directiveValue` handle the `{define}` value. |
| `GuitarShapeGenerator.shapes(for: ChordTones, tuning:limit:)` | Ranked shapes, best first. |
| `CuratedShapes.shape(for:tuning:)` | Curated shapes exist for standard tuning only. |
| `PianoVoicingGenerator.voicing(for:after:)`, `.voicings(for:)` | `voicings` voice-leads across the sequence. |
| `UserShapeLibrary { entries }` | `shape(named:tuning:)`, `load(from:fileSystem:)`, `save(to:fileSystem:)`. The app loads it from `Application Support/<bundle id>/shape-library.json` when a library opens (`AppDependencies.shapeLibraryURL`; test runs only read `-SegueShapeLibraryPath`) and passes it to every `RenderModel` that draws diagrams. |
| `ShapeResolver(defines:userLibrary:tuning:)` | `.guitarShape(for: ChartChord)` and `.pianoVoicings(for: [ChartChord])`. Lookup order: define, user library, curated, generated. |

B builds its tests on hand-made `ChordTones`, so it does not wait for A's parser. The corpus-wide generator test lands once A is in.

**UI** (`Packages/SegueUI/Sources/SegueUI/Diagrams/`, internal `Canvas` views):

- `DiagramSize`: `.compact` / `.regular` / `.stage`.
- `GuitarDiagramView(name:shape:tuning:capoFret:size:)`
- `PianoDiagramView(name:voicing:size:onToggleKey:)`
- `DiagramStrip(diagrams: [RenderDiagram], instrument:tuning:size:onCustomize:)`
- `ShapeEditorView(chordName:instrument:tuning:initialGuitar:initialPiano:onSave: (ChordDefinition) -> Void, onCancel:)`

The accessibility IDs `diagramStrip`, `guitarDiagram`, `pianoDiagram`, `shapeEditor` and `shapeEditorSave` are already in `AccessibilityID`.

## Unit C - Editing engine (`Packages/SegueCore/Sources/Editing/`, plus `Library/`, `ChordPro/`)

| Type / function | Contract |
|---|---|
| `BlockPath { block, item? }`, `LyricPosition { line, offset }`, `ChordRef { line, index }` | Implemented. |
| `TextEdit { range, replacement }`, `SourceChange { edits, actionName, selectionAfter }`, `String.applying(_:)` | Implemented. Edits are ascending, non-overlapping and relative to the pre-edit text. |
| `SourceSnapshot(text:)`: `text`, `document`, `parseDiagnostics` | Implemented. |
| `SourceSnapshot` mapping | `sourceRange(of: BlockPath)`, `sourceRange(of: ChordRef)`, `path(atSourceOffset:)`, `lyricPosition(atSourceOffset:)`, `sourceOffset(of:)`. The last two do the cursor mapping between modes. |
| `SourceSnapshot` derived content | `chords: [ChordOccurrence]`, `chordDefinitions`, `highlights(in:) -> [SyntaxHighlight]`, `diagnostics -> [EditorDiagnostic]`. |
| `EditOperation` | `insertChord`, `replaceChord`, `moveChord`, `duplicateChord`, `deleteChord`, `editLyrics`, `splitLine`, `joinWithPrevious`, `setSectionLabel`, `setDirective`, `setMeta`, `setDefine`, `removeDefine`. |
| `DocumentEditor.change(for:in:) throws(EditError) -> SourceChange` | Produces minimal edits. Bytes outside the touched lines never change. `insertChord` where a chord already sits replaces it (no stacking). `editLyrics` / `splitLine` throw `notLyricText` when the line would become a `#` comment, a directive or gain a typed `[chord]`. |
| `TranspositionRewrite.plan(semitones:in:)` | Returns `{ change, newKey, flaggedDefines: [DefineFlag] }`. It keeps `{capo}`. When the song has no `{key}` line, it adds the detected key, transposed, after the leading metadata directives. |
| `DisplayOptions { transpose, capoMode, nashville, showDiagrams, instrument, tuning }` | Implemented. `showDiagrams` defaults to off. |
| `KeyContext { declared, detection }` | `init(document:)`, `writtenKey`, `status: KeyStatus`. |
| `DisplayTransform(options:key:capo:)` | `semitones`, `concertSemitones`, `displayKey`, `display(_:)`, `concert(_:)`, `sourceChord(fromDisplayed:)`. In Nashville view `sourceChord` also accepts numbers, resolved against `displayKey` (letters are accepted in every view). |
| `RenderModel(document:options:userShapes:)` | Yields `header: RenderHeader`, `sections: [RenderSection]` (items `.lyrics(RenderLine)` / `.comment` / `.stanzaBreak` / `.verbatim`), `diagrams: [RenderDiagram]`, `transform` and `tuning`. `{meta: tuning}` wins over `options.tuning`. `RenderLine.characterStarts` maps lyric offsets to UTF-16 offsets in the joined `lyrics` (use `utf16Offset(ofLyricOffset:)` / `lyricOffset(atUTF16:)`, never `lyrics.count`). |
| `DisplayPrefs` (in `Library/Sidecar.swift`) | Fields mirror `DisplayOptions`. Decoding is lenient; a sidecar without `showDiagrams` reads as off. `init(_ options:)` and `displayOptions` convert between the two. |
| `LibraryStore.updateDisplayPrefs(id:_:) -> SongRecord` | Writes the sidecar only. |

Remaining sidecar work for C:
- Bump `Sidecar.currentSchemaVersion` to 2 and add the 1-to-2 migration.
- Make `PartialSidecar` carry `displayPrefs`. Today the migrated and newer-schema paths drop it.
- Update the sidecar golden in `TestLibrary.swift`. It already includes the default prefs.

## Unit D - Editor UI (`Packages/SegueUI/Sources/SegueUI/Editor/`, `Rendering/`, `Live/`, `Library/`)

D consumes the APIs above and exposes nothing that other units depend on. The flow:

1. The text view holds the text. After each change, D builds a `SourceSnapshot` and then a `RenderModel(document:options:userShapes:)`. The preview, the visual canvas and the live view all draw from that `RenderModel`.
2. A visual gesture becomes an `EditOperation`. Chord input goes through `DisplayTransform.sourceChord(fromDisplayed:)` first (numbers in Nashville view, letters everywhere); committing a chord unchanged is a no-op. `DocumentEditor.change` then returns a `SourceChange`, which D applies to the `NSTextStorage` through `shouldChangeText(inRanges:replacementStrings:)` as one undo group named `actionName`.
3. Mode switching maps the cursor with `lyricPosition(atSourceOffset:)` and `sourceOffset(of:)`.
4. Syntax colours come from `highlights(in:)` and inline diagnostics from `diagnostics`.
5. `[` autocomplete combines song chords from `snapshot.chords`, `KeyContext.writtenKey?.diatonicChordSymbols`, and a common-extensions list that D owns. In Nashville view the chips are numbers and accepting one inserts the source letters.
6. Top-bar toggles write `DisplayPrefs` through `LibraryStore.updateDisplayPrefs`.
7. "Apply transposition to source" uses `TranspositionRewrite` (adding a `{key}` when the song had none). D then resets `transpose` to 0 and shows `flaggedDefines`.
8. Custom shapes go through `ShapeEditorView`, then `EditOperation.setDefine`.

## File ownership

| Unit | Owns |
|---|---|
| A | `SegueCore/Sources/MusicTheory/**`; tests `Tests/SegueCoreTests/MusicTheory*.swift` |
| B | `SegueCore/Sources/Diagrams/**`; `SegueUI/Sources/SegueUI/Diagrams/**`; tests `Tests/SegueCoreTests/Diagram*.swift` and `SegueUI/Tests/SegueThemeTests/Diagram*.swift` (snapshots) |
| C | `SegueCore/Sources/Editing/**`, `ChordPro/**`, `Library/**`; tests `Tests/SegueCoreTests/Editing*.swift`, `SongPipeline*.swift`, existing Library/ChordPro tests incl. `TestLibrary.swift` |
| D | `SegueUI/Sources/SegueUI/{Editor,Rendering,Live,Library,App}/**`, `AccessibilityID.swift`, `UITests/**` |

Shared rules:
- New fixtures go in `Tests/Fixtures/` under new file names. Never edit an existing fixture. A fixture another unit needs is added by whoever needs it first.
- `Package.swift`, `Tuist/Package.swift`, `Project.swift` and the `Makefile` are frozen for this stage. A unit that needs a manifest change asks the orchestrator.
- Every unit runs `make lint build test` before handing back.

## Open questions (closed)

All six were ruled on 2026-10-17 (docs/decisions.md, "Phase 1 build rulings"):

1. **`{key}` with `{capo}`:** `{key}` names the shapes key; concert = key + capo.
2. **Apply transposition when the song has no `{key}`:** the detected key, transposed, is added as a `{key}`.
3. **Chord input in Nashville view:** numbers (`1`, `4`, `6m`, `b7`, `5/7`, `3(7)`) as well as letter names; numbers resolve against the display key.
4. **`showDiagrams` default:** off (sidecars without the field read as off).
5. **Tuning source of truth:** `{meta: tuning}` in the song wins, the sidecar is the fallback, and the editor writes both.
6. **Inserting a chord where one already sits:** it replaces the chord there (no stacking).
