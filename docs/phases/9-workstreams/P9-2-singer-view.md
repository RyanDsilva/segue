# P9-2 - Singer view: lyrics only, chords hidden

Phase 9 workstream (new, 2026-10-31). Rulings: `docs/release/decisions.md` **R176** (the first App Store release is v1.0 and builds Singer view before submission, specced with its open questions closed first), **R178** (this spec's questions closed, section 20), **R138** / **R140** (Singer view is in the release; the one store media pass comes after it), and `docs/00-vision.md:90` ("Singer view - lyrics only, chords hidden"). Built on Phase 8: **R147** (every pass written out, the section map), **R148** (jump and loop), **R149** (pass show modes), **R150** (single-song sessions), **R152** / **R158** P8-4 Q3 / **R161** (the bass-note view, user-level, `B`), **R166** / **R168** Q8 / **R175** (fills, `T`, saved fills always show in the bass view), **R144** / **R145** (section notes and stage cues), **R113** (test budget), **R39** (design directions before new UI), **R79** (accessibility walk), and the owner's romanized Hindi rule (no step may "correct" romanized Hindi words; spell-check and autocorrect off in lyric fields). Reference specs for the code this extends: `docs/phases/8-workstreams/P8-2-stage-map-and-passes.md` (pass model, map, `StageRequest`), `P8-3-arrangement-sequence-strip.md` (show modes in the editor), `P8-4-bass.md` and `P8-7-time-model-and-fills.md` (what the stage draws over chords).

**Sibling specs in this folder, written in parallel:** **P9-1** (`P9-1-pdf-export.md`: single chart, songbook, print, preview, Bass chart and fills) prints singer view as its "Lyrics" part through this spec's layout switch (section 8 here answers P9-1 section 8); **P9-3** (medleys) lays several songs into one stage plan, and singer view applies to each member the same way (section 6.12).

**Build order:** after Phase 8 has landed (it edits `SongPreparation`, `StageRequest`, `LiveSession`, the editor top bar and the library pane, all Phase 8 files). P9-2a (core and stage) may run beside P9-1's core; P9-2b (previews, guide, E2E) follows P9-2a; P9-2c (the second-display Singer Screen, in v1.0 per R178) follows P9-2a. All before the R140 store media pass.

## Session rules (apply to every session)

- `cat` and `ls` are aliased to eza and can hang: use `command cat` / `command ls` or the Read / Grep / Glob tools, and pass this warning to any subagent. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-". Ignore `.build/`.
- Sibling workstreams (P9-1, P9-3, others) edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, stage only your own hunks, keep the tree compiling between steps.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget (R113): per step only targeted in-process suites (`swift test --filter <Suite>`). The transform is tricky pure logic and gets table-driven tests; the layout engine is pure and proves stage behaviour in-process. Exactly **one** new XCUITest class for the workstream (section 16.4). At the end of each session ONE `make quick`, plus ONE `make e2e-one` per UI test class added or changed. No `make gate`, no `make check`, no E2E retry loops (a failure is investigated, not re-run), no scratch-worktree builds. Every build or test runs under `lockf -k .build/make.lock`. Write this budget into any subagent's prompt.
- Before using any Apple API not already in the codebase, run the `apple-api-check` skill.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency, including any case section 20's closed questions do not cover.

## 1. Goal

A singer reads the set from a Segue screen with no chord in the way: big lyrics, the section names and the map so they know where the band is, the chart notes and stage cues placed in the song, and nothing a player needs (chords, walk-ups, fills, tab, the bass neck, capo shapes, the song and slot notes). The owner can flip his own stage to singer view with one key and hand the screen over, put a Singer Screen on a second display facing the singer while he keeps his chords, preview a song as the singer will see it from the library or the editor, and print lyric sheets through P9-1.

**In scope:** one pure singer transform used by every surface; the stage toggle (`V`) in Live and Rehearsal, remembered; how each Phase 8 feature behaves under it (pass modes, section map, jump and loop, cues and notes, walk-ups, fills, the bass view and mini neck, play-along, transposition, metronome, auto-scroll); bigger lyrics; the Singer Screen on a second display (section 6.13); the library and editor previews; the print interface for P9-1; romanized Hindi kept byte for byte; analytics; accessibility; guide pages; one E2E.

**Not in scope:** editing lyrics in singer view (the editor's Text and Visual modes stay the editing surfaces); a per-singer part model (harmonies, who sings which line); lyric translation or transliteration; any change to `.cho` files, sidecars or setlists. The PDF option's toolbar control, pagination and file naming are P9-1's.

## 2. Terms

- **Singer view**: a way of drawing a song with every chord removed. It is a view, never an edit: the song, its sidecar and its setlist slots are unchanged.
- **Chart view**: today's drawing (chords over lyrics). The opposite of singer view.
- **Singer transform**: the pure function in section 5 that turns render sections into singer sections.
- **Instrumental part**: a part (P8-2 term: one `RenderSection`) with no lyric words left once chords, tab and grids are gone (an intro, a solo, a turnaround). Singer view keeps it as one placeholder row so the map, the gutter and jumps still name it.
- **Lyric words**: text with at least one Unicode letter (`Character.isLetter`) once a bare repeat mark ("x2", "(x3)") is set aside. "|", "/ / /", "- - -" and "x2" alone have none; 5.2 rule 2 defines it exactly.

## 3. Current code (verified 2026-10-31)

Render model and options:

- `RenderModel { header, sections, diagrams, transform, tuning }`: `Packages/SegueCore/Sources/Editing/RenderModel.swift:11-19`. `RenderItem` cases `lyrics(RenderLine)`, `comment(text:style:path:)`, `stanzaBreak(path:)`, `verbatim(text:path:)` (tab and grid blocks), `fillTab(FillTabBlock)`: `:238-247`. `RenderLine { path, lyrics (private(set)), chords, characterStarts }`, `init(path:lyrics:chords:)`: `:253-268`. `RenderSection { id, path, kind, label, isRepeat, isEditable, items }`: `:206-215`.
- `DisplayOptions { transpose, capoMode, nashville, showDiagrams, instrument, tuning, bass }`: `Packages/SegueCore/Sources/Editing/DisplayOptions.swift:11-25`. No chord-hiding option exists anywhere (`git grep -i "lyricsOnly\|hideChords\|singer"` finds only test seeds and credit parsing).
- `CommentStyle` `plain`, `italic`, `box`, `highlight`: `Packages/SegueCore/Sources/ChordPro/SongDocument.swift:169-177`.

Stage:

- `StageRequest.make(song:slot:prefs:settings:minLyricSize:viewport:bass:)` builds the one stage `LayoutRequest` (stage and the Arrange Sections preview): `Packages/SegueUI/Sources/SegueUI/Live/StageRequest.swift:45-79`; `walkUps(_:song:passes:)` (walk-ups and fills only in the bass-note view): `:82-100`; `renderModel(_:overrides:bass:)` (sidecar view options, diagrams off, overrides applied): `:104-117`.
- `LayoutRequest { model, viewport, minLyricSize, zoom, columns, cues, notes, passes, style, walkUps }`: `Packages/SegueCore/Sources/LiveLayout/LayoutRequest.swift:340-364`. `LayoutStyle` defaults (`maxLyricSize: 44`, `comfortableLyricSize: 28`, `lineHeight: 1.25`, `chordRatio: 0.82`): `:253-293`; `LayoutStyle.stage`: `:334`.
- `SongPreparation.measure()` pins cues, builds the passes (`ArrangedSections.build`), annotates walk-ups when `request.walkUps` is set, names passes and measures each: `Packages/SegueCore/Sources/LiveLayout/SongPreparation.swift:14-58`; show modes in `items(_:mode:)`: `:98-104`; `chordsOnly`: `:108-132`; `firstLine` (comments before, the first line, "+ N more lines (first line only)"): `:135-160`; `lineCount` (performed lyric lines, the scroll estimate): `:56`.
- The bass-note view on stage, `B` and `T`: `Packages/SegueUI/Sources/SegueUI/Live/LiveSession+Bass.swift:18-37`; the mini neck gate `showsBassNeck`: `:44-51`.
- `LiveSession.relayout()` (up-next model, `StageRequest.make`, the timeline, the plan): `Packages/SegueUI/Sources/SegueUI/Live/LiveSession+Viewport.swift:44-109`.
- Header and footer: `StageHeader` `Live/StageChrome.swift:9`, `StageFooter` `:213`, `keyLine` ("D, capo 2" / "D, no capo") `:304-308`, `firstLine` (the up-next lyric) `:311-323`.
- Keys: `InputBindingTable.defaults` `Packages/SegueCore/Sources/Shows/InputBindings.swift:252-301`. Bound plain letters: `a r q x s c m k l p b t` plus `/` and `?`; **`v` is free** (and `o`, freed by R147). `LiveCommand` cases `:13-67` in `Shows/LiveCommand.swift`, scopes from `:72`, titles from `:139`.
- `LiveSettings { minLyricSize, startShortcut, endShortcut, hiddenChecklistItems, defaultColumns }` (app-level, Settings > Live): `Packages/SegueCore/Sources/Shows/LiveSettings.swift:19-60`; `ChecklistItem`: `:7`.

Previews:

- Library detail pane: `SongDetailPane.chart(_:)` draws `SongSheetView(sections: render.sections, style: .preview)` with the play-along toggle above it: `Packages/SegueUI/Sources/SegueUI/Library/SongDetailPane.swift:255-289`; the render model: `:20-25`.
- Editor: Text mode's live preview `EditorPreview` draws `SongPageView(model:selectable:onCustomize:keyChanges:)`: `Packages/SegueUI/Sources/SegueUI/Editor/SongEditorView.swift:214-240`; Visual mode is the editable canvas (`VisualEditorController`). The display group (Shapes / Concert, Nashville, Bass): `Editor/EditorTopBar.swift:104-137`.
- `SongPageView` wraps `SongSheetView` (`Rendering/SongPageView.swift:42`); `SongSheetView.rows` and `LyricLineView` lay out chords over lyrics: `Rendering/SongSheetView.swift:55-128, 220-302`.

Print: not built (`docs/phases/4-export.md`, now P9-1).

## 4. Decisions

1. **One transform, every surface.** A pure `SingerView` in SegueCore Editing turns `[RenderSection]` into singer sections. The stage (LiveLayout), the library and editor previews (`SongSheetView`) and P9-1's PDF all call it, so a song reads the same everywhere. No surface strips chords on its own.
2. **A view, not a song setting.** Nothing is written to the `.cho`, the sidecar or a setlist. Two remembered settings only: the stage's (Settings-level, `LiveSettings.singerView`) and the previews' (`PreviewPrefs.singer`, section 11).
3. **Stage: a toggle in Live and Rehearsal, `V`.** Not a separate mode or a separate start command: the owner flips it mid-set when he hands the screen over, and the same session (keys, map, pedal, requests) keeps working. It is remembered across shows like `B`, and the pre-show checklist warns when it is on (6.10).
4. **Chords only passes become First line** in singer view, keeping the CHORDS tag (section 6.3, R178).
5. **Bigger lyrics** come from two things: chord rows are gone (the fit search gets the space back on its own), and singer view lays out with `LayoutStyle.singer` (a higher maximum and comfortable size, section 6.5).
6. **Everything a player reads goes; everything a performer reads stays.** Goes: chords, chord rows, Nashville, capo shapes, walk-ups, fills, tab and grid blocks, chord diagrams, the bass mini neck. Song and slot notes go too (R178: they are often player reminders). Stays: section names, the map, pass badges and mode tags, `{comment}` lines, stage cues, the metronome, the up-next line (6.7).
7. **Transposition only reaches the key line.** Lyrics never change with transpose or capo; the header shows the sounding (concert) key after the slot's overrides, never a capo or shape key (6.8).
8. **Romanized Hindi is untouched.** The transform copies lyric text byte for byte, joins words a chord split ("Tu[G]jh" reads "Tujh"), never changes case, spelling, punctuation or spacing inside a word, never hyphenates (section 10).

## 5. The singer transform (SegueCore `Editing/SingerView.swift`, pure)

```swift
public enum SingerView {
    /// The text of an instrumental part's placeholder row.
    public static let instrumentalText = "Instrumental"
    /// Singer sections for `sections`, one per input section, same ids, paths, kinds, labels
    /// and order (pass naming, cues and the map key on these), items rewritten by 5.2.
    public static func sections(_ sections: [RenderSection]) -> [RenderSection]
    /// One section (the stage calls it per pass, after its show mode is mapped).
    public static func section(_ section: RenderSection) -> RenderSection
    /// A model for previews and print: `sections` transformed, `diagrams` emptied, the
    /// header's capo cleared and its key replaced by the concert key (6.8).
    public static func model(_ model: RenderModel) -> RenderModel
    /// The show mode a pass takes in singer view (6.3): chordsOnly -> firstLine, others kept.
    public static func mode(_ mode: PassMode) -> PassMode   // in Library (PassMode lives there)
    /// Whether a part has lyric words left (5.2 rule 2).
    public static func isInstrumental(_ section: RenderSection) -> Bool
}
```

`mode(_:)` lives beside `PassMode` in Library (`SlotArrangement.swift`) as `PassMode.singer`, since Editing does not import Library; the rest is in Editing.

### 5.1 Lines

A `.lyrics(line)` item becomes `.lyrics(RenderLine(path: line.path, lyrics: line.lyrics, chords: []))`: the same text and path, no chords. Because `line.lyrics` is the joined text of the chord runs, a word a chord sat inside comes out whole ("Tu[G]jh mein [D]rab" -> "Tujh mein rab"), and the layout engines lay it out as a chordless line (one run, no chord row), which both `LineLayout` and `LyricLineView` already do for lines without chords. Trailing whitespace a chord-only run left at the end of a line is trimmed; leading and inner whitespace is kept exactly.

### 5.2 Items

Applied in order to each section's items:

1. `lyrics` with lyric words: kept (5.1).
2. `lyrics` without lyric words: dropped. A line has lyric words when its text, after removing a trailing or standalone repeat mark (`x2`, `X3`, `(x2)`, `×2`, any count 2-9), still contains a letter and is not a chord line typed as text (rule 3's test: every token a chord symbol, "N.C." or a bar mark). So "[G] [D] [Em]" (empty text), "| G . . | D . . |" (its letters are chord names) and "x2" alone are dropped; "Oh oh oh", "(Hum hum)" and "Tujh mein rab x2" are kept, the last one with its "x2" (only a line that is nothing but the mark is dropped).
3. `comment`: kept as is (a `{comment}` is a direction to the performer: "Softly", "All together", "Key change"). Exception: a comment whose text, trimmed, parses entirely as chords (every space-separated token with a letter is a `ChordToken(parsing:)` chord or "N.C.", at least one a chord, for example `{c: G D Em C}`) is dropped, because it is a chord line written as a comment (a common paste habit). (There is no `ChordParser` type; `ChordToken` is the parser.)
4. `verbatim` (tab, grids): dropped.
5. `fillTab`: dropped (the bass view's fill tab, P8-7).
6. `stanzaBreak`: kept, then consecutive breaks collapse to one and leading or trailing breaks are removed (the rule `chordsOnly` already applies, `SongPreparation.swift:108-132`).
7. **Instrumental part**: if no `lyrics` item survives, the section's items become the comments that survived (rule 3) followed by one `.comment(text: SingerView.instrumentalText, style: .italic, path: section.path ?? first item path)`. A labelled part keeps its label ("Intro" / "Solo"), so the gutter reads "Intro" and the body reads "Instrumental". An unlabelled loose block with no words is left out of `SingerView.sections` (previews and print: it has no name to show and nothing to sing) unless a comment survives in it, which is then kept without the placeholder; a song whose only content it is shows "Instrumental". On stage, `SingerView.section` keeps it as its pass ("Lead-in", "After Verse 1" on the map) with "Instrumental", so the map keeps the chart's chips (6.4).

`{chorus}` repeats are already written out by the stage before the transform (`ArrangedSections.build`, R147); in previews a `{chorus}` stub is handled by `SongSheetView` as today, then its target's items are transformed like any other.

### 5.3 What the transform never does

It never reorders, merges or renames sections, never edits a label, never changes a lyric character (case, diacritics, apostrophes, spacing inside a line), never inserts hyphens, never touches `header.title`, `artists` or `album`, and never reads the network or the model port. Section ids are stable, so `SectionNotes.pin`, `PassNaming` and cue placement see exactly the sections the chart view sees.

## 6. The stage

### 6.1 The toggle

- New `LiveCommand.toggleSingerView`, default key `v` (no modifiers), scope `.viewport` like `toggleBassNotes` (which is `.viewport` in code), `repeatsWhenHeld` false (P8-1). Title "Singer View"; help group "View".
- `V` flips `LiveSettings.singerView` through the Live settings store, re-lays out at once and flashes "Singer view" / "Chords" in the mode indicator. Works in Live and Rehearsal, in setlist and single-song sessions (R150), and keeps the scroll position on the current pass: after the re-layout the scroller seeks to the same pass at the same progress (`StagePasses.progress`, P8-2 section 9), never back to the top.
- Also in the Live menu ("Singer View", ⌥⌘V per R188, a checkmark when on). ⌥⌘V is also File > New Song from Clipboard (R75), which is disabled during a show, so Live > Singer View is enabled only during one and the two share the chord (`MenuShortcuts.sharedChords`, like Rehearse Song / Rehearse) and in Settings > Live ("Show lyrics only on stage (Singer view)"), so it is reachable without the keyboard.
- The stage header shows a quiet "Singer" chip (the "Rehearsal" chip's style) while it is on, identifier `segue.live.singer`, so the owner can see at a glance why there are no chords.

### 6.2 Layout input

`LayoutRequest` gains `view: StageView` (`.chart` default, `.singer`). `StageRequest.make` gains `singer: Bool` and, when set:

- builds the render model as today (overrides applied, so the concert key is right), with `bass: nil` (the bass view never applies, 6.6);
- passes `walkUps: nil` (no walk-ups, no fills, whatever `B` and the density say);
- passes `style: .singer` (6.5);
- passes `notes: []` (song and slot notes are hidden in singer view, R178) and keeps `cues` and `passes` unchanged.

`SongPreparation.measure()` with `view == .singer`: after `ArrangedSections.build`, each pass's mode is mapped through `PassMode.singer` and its section through `SingerView.section`, then measured with the existing `items(_:mode:)` (Full or First line; Chords only never reaches it). `firstLine` on a singer section picks the first lyric line with words (its existing rule) and counts "+ N more lines" over the singer items. An instrumental part in First line mode shows its "Instrumental" row and no "+ N" line.

### 6.3 Pass modes (R149)

| Pass mode | Chart view | Singer view |
| --- | --- | --- |
| Full | chords over lyrics | the lyrics, every line |
| Chords only | `\| C \| G \|` chord rows | **First line**: the first lyric line, then "+ N more lines (first line only)"; the gutter mode tag still reads "CHORDS" and the map chip's mode line "CHORDS", so the singer sees the leader marked it as a chords pass |
| First line | the first line with chords, "+ N more lines" | the first line without chords, "+ N more lines" |
| Skip | absent | absent |

Rationale (R178): a Chords only pass is played, so the singer must see that it happens and which part it is, but the leader chose not to read its words; the first line names it without asserting a full vocal.

### 6.4 Section map, badges, jump and loop (R147, R148)

Unchanged: singer view keeps the same shown passes in the same order, so the map has the same chips ("Chorus 2/3"), the gutter keeps the "2 of 3" badges and the mode tags, 1-9 and chip clicks jump, and `L` loops in a rehearsal with the same count-in. `plan.passes` comes from the singer plan, so a chip's width follows the singer layout's heights. The current-pass dot and the loop bracket draw as today.

### 6.5 Font sizing: bigger lyrics

- `LayoutStyle.singer` = `.stage` with `maxLyricSize` **60** (stage 44), `comfortableLyricSize` **36** (28) with `comfortableMinimumFactor` **1** (1.25), `lineHeight` 1.25 (as the stage), `sectionSpacing` **0.7** (0.6), `columnGap` **32** (48), `gutterGap` 18 (as the stage: the loop bracket sits in it, R163), `wrapPenalty` **0.15** (stage nil), `wrapTolerance` 0.15 (as the stage); `chordRatio` and the chord fields unused. R178 fixes the 60 pt maximum and the 28 pt floor; the rest are step 0's tuning (R187 picked direction A).
- Step 0 tuning (2026-11-01). The starting numbers (36, 1.3, 0.8) reached 29 pt for the R187 fixture at 1440 x 900 with Verse 1 wrapped, and no comfortable size or `wrapTolerance` changes that: `comfortableMinimumFactor` 1.25 x the 28 pt floor already set the comfortable size to 35, and the wrap is width-bound (a 46-character romanized line does not fit a 2-column measure above about 28 pt), not a column choice. So singer view gains `wrapPenalty` (a `LayoutStyle` field, nil for every other style): below the comfortable size an unwrapped layout wins unless wrapping makes lyrics more than 15% larger. With the narrower column gap that gives the fixture 28 pt with no line wrapped (a phrase is never broken), the Hindi fixtures 45 pt (stage 31), basic-verse-chorus 35.5 pt (wrapping wins there: 27% larger than unwrapped 28) and 1920 x 1080 39.5 pt (stage 26.5). The trade is deliberate: "larger" and "unwrapped" pull against each other on a 2-column 1440 x 900 stage, and an unbroken phrase wins up to 15%.
- The minimum lyric size in singer view is `max(settings.minLyricSize, 28)`: the fit never shrinks a singer's lyrics below 28 pt; a long song scrolls or takes columns instead (the existing fit rules).
- R188: when every layout that fits would wrap a lyric line, singer view lays out one column at the largest size that wraps none, up to the 36 pt comfortable size (larger only adds scrolling), and scrolls it (`LayoutStyle.scrollsRatherThanWrap`, singer style only; `LayoutFit.scrollsUnwrapped`). Forced columns (`C`) skip it.
- Zoom: ⌘+ / ⌘- / ⌘0 in singer view change a separate `LiveSettings.singerZoom` (default 1.0, range `LiveSession.zoomRange`), not the song's `LivePrefs.zoom`, so a singer's zoom never changes the owner's chart zoom for that song and applies to every song while singer view is on. Columns (`C`) stay per song as today.
- The 58 pt map band and the header and footer heights are unchanged.

### 6.6 Bass view, walk-ups, fills, the mini neck (P8-4, P8-7)

- Walk-ups, approach notes, fill names and fill tabs never draw in singer view (`walkUps: nil`, rule 5.2.5), and the mini neck is hidden (`showsBassNeck` gains `&& !singer`).
- `B` and `T` in singer view do not change any setting; they flash "Singer view hides chords (V shows them)". The bass-note setting itself is untouched, so turning singer view off returns the owner's bass view exactly as it was.
- R175 ("saved fills always show in the bass view") does not apply: singer view is not the bass view.

### 6.7 Cues, notes, comments, header, footer

- **Stage cues** (sidecar cues, P3-17) draw as callouts on their part's first shown pass, as today. **Song notes and the slot note** are hidden: singer view lays out no notes block (R178). Chart notes (`{comment}` lines) stay, per 5.2 rule 3.
- **Header**: title, then the key line `SingerKeyLine`: "Key A" (the concert key after the slot's overrides, `model.transform.concertKey`), no capo, no "Shapes"; the tempo stays ("Key A, 96"). Arranged / Full song, the Singer chip, the Rehearsal chip, the loop pill, progress dots and elapsed time as today.
- **Footer up-next**: the next song's title and the same singer key line; its lyric line is `StageFooter.firstLine` of the next song's **singer** model (the first line with words), so an up-next never shows a chord-only line.
- **Metronome**: unchanged (pips, BPM, `M`, count-ins); a singer often wants the pulse.

### 6.8 Transposition and capo

Lyrics do not depend on transpose or capo. Overrides still apply to the model, so the header's key is the sounding key a singer pitches to. Capo is never shown in singer view. Nashville is ignored (no chords to number).

### 6.9 Play-along, auto-scroll and timing

- Rehearsal play-along (`P`, P8-6b) works in singer view and sounds exactly as in chart view (bass, chords, click from the timeline): it is the singer's practice track. Audio-driven scroll follows the singer plan by pass and progress (the existing `PlayAlongFollow` maps timeline position to `plan.passes`, which singer view keeps).
- Auto-scroll speed is the slot's time from `SongTimeline` (P8-8 5.6), which singer view does not change, spread over the singer plan's overflow. The time and every set total are the same in both views.

### 6.10 Pre-show checklist

`ChecklistItem.singerView`: when singer view is on at show or rehearsal start, the checklist shows "Singer view is on: the stage shows lyrics only" with a "Show Chords" button (turns it off) and "Don't show again". Not shown for single-song sessions (they skip the checklist, R158 P8-2 Q8).

### 6.11 What does not change

Paging, pedals and P8-1's guards, requests, search, the drawer, Gig Mode, the gig log (singer view is not recorded in the show record), single-song sessions, Rehearse this (P8-3) and every key other than `V`, `B` and `T`.

### 6.12 Medleys (P9-3)

P9-3 lays a medley's members into one plan as segments; `view` applies to every segment and the transition blocks keep their text. The member header in singer view shows the member's title and its singer key line. P9-3 owns that header; this spec only requires that it reads `StageView` the same way.

### 6.13 Singer Screen on a second display (P9-2c, R178)

- **What:** a second stage window, always in singer view, on another display facing the singer, while the owner's main stage keeps whatever view he has (usually chords). It has no keys of its own, no audio, no pedals and no chrome beyond the stage header (title, singer key line) and the map strip.
- **Open:** Window > "Singer Screen" (identifier `segue.menu.singerScreen`, no default shortcut), enabled while a Live or Rehearsal session is up and more than one display is connected; help when disabled: "Connect a second display to show a Singer Screen". It opens borderless and full screen on the first display other than the main stage's; when there are three or more, a submenu lists them by `NSScreen.localizedName`. The chosen display is remembered per machine (`LiveSettings.singerScreenDisplay`, the display's name, lenient like the 11 fields) and re-used when it is connected. The pre-show checklist gains no row; per R188 it shows a "Singer Screen: no second display" warning when a Singer Screen display is remembered on this Mac (`singerScreenDisplay`) and fewer than two displays are connected.
- **Follow model (`SingerScreenFollow`, SegueCore `LiveLayout`, pure; `Shows` does not depend on `LiveLayout`, so it lives beside `StagePasses`, and `V` keeps the position with it too):** the screen lays out its own singer plan for the current song (`StageRequest.make(..., singer: true)` at the second display's viewport and `LayoutStyle.singer`, notes hidden) and maps the performer's position onto it pass by pass: input is the main plan's current pass index and progress (`StagePasses.progress`), output is the scroll offset of the same pass at the same progress in the singer plan. Song changes, jumps (1-9, chip clicks), loops and requests follow at once; continuous scroll follows with the stage's existing smoothing. Medleys follow member by member (6.12).
- **Between songs and at show end:** the changeover shows the next song's title and singer key line; ending the show closes the window. Unplugging its display closes it quietly (no error); reconnecting does not reopen it.
- **Singer view on the main stage too:** if the owner presses `V` as well, both show lyrics; the Singer Screen ignores `V`, `B`, `T` and zoom on the main stage (its size is the fit at its own display, with `LiveSettings.singerZoom`).
- **Accessibility:** the window is not key and takes no focus; VoiceOver users drive the main stage.

## 7. Editor and library preview

- **Library detail pane**: a "Chords / Singer" segmented control (native, R187 A) at the right of the row that holds the Play Along toggle (`SongDetailPane.chart`, `:255-265`), identifier `segue.library.singerPreview`, help "Preview lyrics only, as a singer sees them". On: the pane draws `SongSheetView(sections: SingerView.sections(render.sections), style: .preview)`, the song notes are hidden as on stage, the diagrams strip is hidden, and the chord interactions (walk-up picking, hearing a chord, the fill span) are absent because there are no chords. The song card above the chart (the editable metadata, notes included) is unchanged: it is the library's editing surface, not part of the chart preview. Play-along still works (it reads the timeline, not the drawing) and its cue highlight follows lines by path, which the transform keeps.
- **Editor**: the same "Chords / Singer" segmented control in the display group after "Bass" (`EditorTopBar.displayGroup`, `:104-137`), identifier `segue.editor.display.singer`. In **Text mode** the live preview (`EditorPreview`) draws `SingerView.model(renderModel)`; the source pane stays editable, so lyric edits show in singer view as you type. In **Visual mode** the canvas is replaced by a read-only singer page with a slim bar above it: "Singer preview: chords are hidden. Turn off Singer to edit chords." with a "Turn Off" button; typing is not possible in it. Switching Visual / Text keeps the toggle.
- Both previews share one remembered setting, `PreviewPrefs.singer` (R178: the preview has its own singer toggle), separate from the stage's: previewing a song for a singer never turns the owner's stage into singer view.
- Song menu: "Singer Preview" with ⇧⌘Y (free today: check `MenuAndAboutTests` at build time; if taken, pick a free chord and record it), enabled when a song is shown in the library or open in the editor.

## 8. Print: interface for P9-1

P9-1 owns the export UI, pagination and files; it prints singer view as its **Lyrics** part (P9-1 sections 6 and 8, through the same `StageRequest` path as the stage). This spec provides, and P9-1 consumes:

1. The layout-request switch P9-1 section 8 item 1 asks for: `StageRequest.make(..., singer: true)` -> `LayoutRequest.view = .singer` (section 6.2), so `SongPreparation` produces no chord rows, chord runs, walk-up or fill runs and no fill tabs; print never strips chords itself. For anything drawn outside the layout engine (headers, the set list page), `SingerView.model(_ model: RenderModel) -> RenderModel` (section 5): diagrams empty, the header's capo nil and its key the concert key.
2. `PassMode.singer` for P9-1's repeats and arrangement handling, if the songbook honours slot arrangements (P9-1's decision): a Chords only pass prints as First line, as on stage.
3. `SingerView.instrumentalText` and the placeholder rule, so a printed instrumental part reads "Intro / Instrumental" like the stage.
4. The answers P9-1 section 8 item 2 leaves to this spec: Chords only passes print as First line with the "CHORDS" tag, First line passes as their first line without chords, tab and grid blocks are dropped, `{comment}` lines are kept (5.2), instrumental parts print "Instrumental", song and slot notes never print in the Lyrics part (R178; P9-1's "Stage notes and cues" option prints cues only), and the header and the set list page's key column show the sounding key and no capo ("Key A", R178). P9-1's own choices (the Chart picker value "Lyrics", its Large default text size, the " (Lyrics)" file name, diagrams and fill tab disabled) stand; a lyric line is the unit print never splits; romanized Hindi prints byte for byte (section 10).
5. Analytics: P9-1's export signal carries the part (`lyrics`); this spec adds nothing to the export row.

If P9-1 needs anything else from the transform (for example, a per-line marker for "+ N more lines"), it is added here, in `SingerView`, never re-implemented in the paginator.

## 9. Phase 8 interactions (summary)

| Phase 8 feature | In singer view |
| --- | --- |
| Every pass written out, map strip, badges (R147) | unchanged; same passes, same chips |
| Jump 1-9, chip click, loop with count-in (R148) | unchanged |
| Show modes (R149) | Full: lyrics; Chords only: First line, tag "CHORDS"; First line: first line without chords; Skip: absent |
| Single-song sessions (R150), Rehearse this (R156) | follow the stage setting |
| Metronome pips (R151) | unchanged |
| Bass-note view, Nashville, mini neck, scale line (R152) | hidden; `B` flashes; the setting is kept |
| Walk-ups (P8-4b), fills and fill tab (P8-7, R175) | hidden; `T` flashes |
| Play-along (P8-6b) | sounds as in chart view, follows the singer plan |
| Mid-song `{key}` (R168 Q2) | the header key line follows the key at the reading line, concert pitch |
| Chart notes and stage cues (R144, R145) | shown |
| Song notes and slot notes | hidden (R178) |
| Slot time and totals (R172) | unchanged |
| Movie / Album (R173) | not shown on stage, as in chart view |

## 10. Romanized Hindi

- The transform copies `line.lyrics` as is; the only edits are dropping whole items (5.2) and trimming trailing whitespace a chord-only run left (5.1). Proved by a property test: for every kept line, `singer.lyrics == original.lyrics.trimmingTrailingWhitespace()`.
- Layout wraps at whitespace only and never hyphenates (the stage and `SongSheetView` already do; singer view adds no text system feature). No case transform (no small caps, no uppercasing of lyric text).
- No AI step, no spell-check, no autocorrect: singer view has no text input at all.
- Fixtures include real romanized Hindi with chords inside words ("Tu[G]jh mein [D]rab dikh[Em]ta hai", "Ke[A]sari[E]ya te[F#m]ra") and a Devanagari line, so the word-join rule is proved on the owner's actual material.

## 11. Data and settings (lenient)

- `LiveSettings` gains `singerView: Bool` (default false) and `singerZoom: Double` (default 1.0, clamped to `LiveSession.zoomRange` on read). Today `LiveSettings` uses synthesized `Codable` (no `init(from:)`, `Shows/LiveSettings.swift:19`) and the store decodes it with `try? SegueJSON.decode` (`Settings/LiveSettingsStore.swift:77`), so a missing non-optional key would silently reset **every** Live setting to defaults. This change therefore adds a hand-written lenient `init(from:)` (`decodeIfPresent` with the defaults for every field, old and new) and a test that a pre-P9-2 settings file keeps its minimum lyric size, Shortcuts, hidden checklist rows and columns. An older build reading a newer file ignores the extra keys (synthesized decoding skips unknown keys).
- `ChecklistItem.singerView` (new case). `hiddenChecklistItems` is a `Set<ChecklistItem>` decoded strictly: an older build meeting `"singerView"` in it would fail the whole decode and fall back to defaults. The new lenient decoder decodes it as `[String]` and drops unknown raw values. The settings value carries no schema version, so for older builds the encoder writes only the rows every build knows (focus, charger, brightness) under `hiddenChecklistItems` and every hidden row under a new `hiddenChecklistRows` key, which older builds ignore; the decoder reads the union. An older build therefore keeps every Live setting.
- `PreviewPrefs` (new, SegueUI, `UserDefaults` key `segue.preview.singer`, Bool, default false): a per-machine convenience, read in a `do`/`catch`-free way (`bool(forKey:)`), never synced, never in the library folder.
- `InputBindingTable`: the new command is only written to `bindings.json` if the user rebinds it. An older build decodes a current-version file strictly (an unknown command throws), so the bindings schema is now **2** (same shape as 1; versions 0 and 1 migrate unchanged), and an older build reads a version-2 file best effort, skipping `toggleSingerView`.
- No `.cho`, sidecar, setlist or show record change. No index rebuild.

## 12. Accessibility

- `V` and the menu item announce "Singer view on" / "Chords shown" (the existing indicator announcement). The Singer chip reads "Singer view, lyrics only".
- The instrumental row reads "Intro, instrumental". A Chords only pass in singer view reads "Chorus, 2 of 3, chords pass, first line only".
- The library and editor toggles are buttons with a selected state; the Visual-mode bar's text is the read-only explanation; "Turn Off" is a button.
- New UI joins the R79 accessibility walk.

## 13. Analytics (non-PII, closed vocabulary, WS3)

- `FeatureKey.singerView` (WS3 row 8): recorded with `featureUsed` when singer view is switched **on**, context `stage` (the `V` key, the menu or Settings), `screen` (the Singer Screen opened, P9-2c), `library` or `editor` (the preview toggles). Once per show for `stage`; daily for the previews (existing throttle rules).
- The show-ended signal gains `segue.singer` (Bool: singer view was on at any time during the run), so it is visible whether singer view is used at gigs or only in rehearsals. Update `AnalyticsEvent` params, the throttle case if needed, `ServicesVocabularyTests`, and the WS3 table in the same change.
- Never lyric text, titles or ids.

## 14. Guide pages

- New `guide/src/content/docs/singer-view.mdx`: what it hides and keeps, `V` on stage, the checklist warning, Chords only passes as first lines, the previews in the library and the editor, printing lyric sheets (link to P9-1's page), a screenshot of the stage in singer view (`make docs-shots ONLY=singer-view` once the UI lands; the full re-capture is R140's pass).
- `go-on-stage.mdx`: one paragraph and the `V` key. `rehearse.mdx`: play-along works in singer view. `keyboard.mdx` from the regenerated `keyboard.json` (`make guide-keys`, never hand-edited). `index.mdx`: a tile only if the page set has room (keep it short, per the owner's rule).
- `SegueLinks` gains `singerView` -> `/guide/singer-view`; verify against the local build and the live site once deployed.

## 15. Design directions (step 0, R39)

Three directions, rendered in the session scratchpad `p9-2/` with real material (the Welcome song "Kettle On, Lights Low" and a romanized Hindi song with chords inside words, one arranged with a Chords only pass and an instrumental intro), on the stage theme at 1440 x 900 and at a 13" laptop size, for Ryan to pick before step 4:

- **A - Chart without chords:** today's stage layout (gutter labels, badges, tints, map strip) with chord rows gone and `LayoutStyle.singer` sizes. Most consistent with the chart view; the gutter keeps orientation.
- **B - Lyric sheet:** no gutter; each part's name as a small heading above its stanza, the map strip kept, lyrics larger again (the gutter width goes to the text), wider stanza spacing.
- **C - Prompter:** one column always, very large lyrics (up to 72 pt), the line at the reading line drawn in `ink` and the others in `muted`, the map strip kept; auto-scroll and pedals as today.

Also rendered for each: the instrumental row, a Chords only pass as First line, the header with the Singer chip and "Key A", and the library pane's Singer toggle. Recommendation: **A** (the map, badges and jump already teach the singer where the band is, and nothing about the stage behaves differently, so the owner can flip back and forth mid-song without relearning the screen).

**Picked (R187, 2026-11-01):** the stage as the chart without chords (A); a segmented "Chords / Singer" control in the library and editor preview (A); the Singer Screen mirrors the stage's header and map (A). Mockups in `.build/design-p9/` (not committed). The final `LayoutStyle.singer` numbers are in 6.5.

## 16. Test plan (R113)

### 16.1 SegueCore, pure (`SingerViewTests`, new, Swift Testing, table-driven)

- Chords removed, text kept; "Tu[G]jh mein [D]rab" -> "Tujh mein rab"; trailing whitespace from a final chord run trimmed; leading and inner spaces kept.
- Lines without lyric words dropped: empty, bar lines, "x2" alone; kept: "Oh oh", "(Hum hum)", "Tujh mein rab x2".
- Comments kept; a chord-only comment (`{c: G D Em C}`) dropped; "Key change" kept.
- `verbatim` and `fillTab` dropped; stanza breaks collapsed and trimmed.
- Instrumental part: labelled -> comments plus "Instrumental"; unlabelled wordless loose block dropped; a song of only an instrumental -> one "Instrumental" section.
- Ids, paths, kinds, labels and order unchanged (a property over the fixture corpus, `LiveLayoutCorpusTests` fixtures).
- Byte identity of kept lyrics over the corpus plus the romanized Hindi and Devanagari fixtures.
- `SingerView.model`: diagrams empty, capo nil, header key = concert key for transposed and capo'd inputs.
- `PassMode.singer`: chordsOnly -> firstLine, others unchanged.

### 16.2 LiveLayout, pure (`LiveLayoutSingerTests`, new)

- A singer plan has no `.chord`, `.chordSeparator`, `.approach` or fill text anywhere; the chart plan of the same request has them.
- Same `plan.passes` count, order, names, badges and mode tags as the chart plan, for a full song and an arranged slot with Chords only, First line and Skip passes; a Chords only pass lays out as First line with tag "CHORDS".
- For a fixed viewport, the singer plan's lyric size is >= the chart plan's and >= 28; `LayoutStyle.singer` caps at 60.
- Cues on the first shown pass; no notes block (song and slot notes passed in are not laid out); walk-ups ignored even when `walkUps` is passed (defensive).
- `lineCount` and therefore auto-scroll speed inputs unchanged between views for the same song.

### 16.3 SegueUI, in-process (`StageSingerViewTests`, `SingerPreviewTests`, new; extend `KeyHelpTests`, `LiveModeTests`, `PreShowChecklistTests`, `MenuAndAboutTests`)

- `V` flips `LiveSettings.singerView`, re-lays out, flashes, keeps the current pass and progress; remembered for the next session; the Singer chip shows.
- `B` and `T` under singer view flash and change nothing; the mini neck is hidden; turning singer view off restores the bass view as it was.
- Header key line "Key A" for a song in G with a slot transpose of +2 and capo 2; up-next lyric is the next song's first line with words.
- Singer zoom separate from the song's zoom; minimum 28.
- Checklist row appears when on, its button turns it off; absent for single-song sessions.
- Library pane and editor Text preview draw singer sections; Visual mode shows the read-only bar; the two previews share `PreviewPrefs.singer`; the stage setting is untouched by them.
- Key help: `V` in "View", every command once; Song menu shortcut unique.

### 16.4 XCUITest (one new class)

**`SegueSingerViewE2ETests.testSingerViewOnStage`**: fresh library; seed one song with a tempo, an instrumental intro, a chorus with chords inside romanized Hindi words, and a slot arrangement with a Chords only pass (as `SegueArrangementE2ETests` seeds); select it -> Rehearse (⌥⌘↩) -> chords visible -> press `v` -> no chord text is found in the stage (the chord accessibility labels are gone), "Tujh mein rab" is, the Intro reads "Instrumental", the Singer chip shows, the map still lists the same chips -> press `b` -> the "Singer view hides chords" flash -> `v` -> chords back -> `⌘.` and Return. Screenshots for the review. One `make e2e-one` for it.

### 16.5 Singer Screen (P9-2c, in-process)

- `SingerScreenFollowTests` (pure, table-driven): the same pass at the same progress across plans of different heights; a pass that is First line in both plans; jumps and loops; medley members; the last pass at progress 1.
- `SingerScreenTests` (SegueUI, in-process with a fake screen list): the menu item's enabled state by display count and session; the remembered display chosen when connected, else the first other display; the window closes when its display disappears and when the show ends; notes hidden and no chord text in its plan.

## 17. Build sessions and steps

**P9-2a - core and stage** (after Phase 8 has landed):

0. Design directions (section 15) rendered and picked by Ryan; record the pick and the final `LayoutStyle.singer` numbers in this spec before step 4.
1. `SingerView` and `PassMode.singer`, suites 16.1.
2. `LayoutRequest.view`, `LayoutStyle.singer`, `SongPreparation` singer path, suites 16.2.
3. Settings and command: `LiveSettings.singerView` / `singerZoom`, `ChecklistItem.singerView`, `LiveCommand.toggleSingerView`, `v` default, bindings versioning check, key help, `make guide-keys`; suites `KeyHelpTests` and the settings and bindings tests.
4. Stage UI: `StageRequest` singer path, toggle with position kept, chip, header and footer key lines, `B`/`T` flashes, mini neck gate, zoom, checklist row, Live menu and Settings > Live control; `StageSingerViewTests`, `PreShowChecklistTests`. One `make quick`.

**P9-2b - previews, docs and E2E** (after P9-2a):

5. Library pane toggle, editor button (Text preview, Visual read-only bar), `PreviewPrefs`, Song menu item; `SingerPreviewTests`, `MenuAndAboutTests`.
6. Analytics (`FeatureKey.singerView`, `segue.singer` on show ended, WS3 table, vocabulary test).
7. Guide pages and `SegueLinks`; the E2E (16.4); one `make quick`; one `make e2e-one SegueSingerViewE2ETests`; the screenshot command for Ryan if the session cannot run it.

**P9-2c - Singer Screen on a second display** (in v1.0, R178; after P9-2a): section 6.13.

8. `SingerScreenFollow` (pure) and its tests (16.5).
9. `SingerScreenController`, the window, Window menu item, display choice and remembered screen, the checklist line, analytics context `screen`, the guide paragraph; `SingerScreenTests`. One `make quick`; no new XCUITest class (the second display cannot be driven in the E2E VM).

## 18. Files

- **New**: `SegueCore/Sources/Editing/SingerView.swift`; `SegueCore/Sources/Shows/SingerScreenFollow.swift`, `SegueUI/Sources/SegueUI/Live/SingerScreenController.swift`, `SingerScreenView.swift` (P9-2c); `SegueUI/Sources/SegueUI/Live/StageSingerChip.swift` (if the chip is not a one-line addition to `StageChrome`), `SegueUI/Sources/SegueUI/Rendering/PreviewPrefs.swift`, `AccessibilityID+Singer.swift`; tests in section 16; `UITests/SegueSingerViewE2ETests.swift`; `guide/src/content/docs/singer-view.mdx`.
- **Changed**: `Library/SlotArrangement.swift` (`PassMode.singer`); `LiveLayout/LayoutRequest.swift`, `SongPreparation.swift`; `Shows/LiveCommand.swift`, `InputBindings.swift`, `KeyHelp.swift`, `LiveSettings.swift`; `Services/FeatureKey.swift`, `AnalyticsEvent.swift`; `SegueUI/Live/StageRequest.swift`, `LiveSession+Viewport.swift`, `LiveSession+Bass.swift`, `LiveSession+Commands.swift`, `StageChrome.swift`, `PreShowChecklist.swift`, `PreShowChecklistView.swift`; `Settings/LiveSettingsView.swift`, `LiveSettingsStore.swift`; `App/Commands/LiveCommands.swift`, `SongCommands.swift`, `App/MenuShortcuts.swift`, `App/SegueLinks.swift`; `Library/SongDetailPane.swift`; `Editor/EditorTopBar.swift`, `SongEditorView.swift`; `docs/release/specs/WS3-services.md`; `UITests/e2e-map.tsv` (route `Editing/SingerView.swift` and the stage files to the new class); guide pages in section 14.

## 19. Done criteria

- `V` on stage hides every chord, chord row, walk-up, fill, tab and grid, and the mini neck, in Live and Rehearsal, keeping the current pass; it is remembered and the checklist warns when it is on.
- Chords only passes show as First line with the "CHORDS" tag; the map, badges, jump and loop are the same as in chart view.
- Instrumental parts show their name and "Instrumental"; a word split by a chord reads whole; romanized Hindi lyrics are byte-identical to the chart's.
- Singer lyrics are larger than chart lyrics for the same song and window, never below 28 pt, with their own zoom.
- The header shows the sounding key and no capo; `B` and `T` explain themselves and change nothing.
- The library pane and the editor preview a song in singer view through the same transform; editing stays in the editor's normal modes.
- P9-1 has `LayoutRequest.view = .singer` (through `StageRequest`), `SingerView.model` and `PassMode.singer` to print its Lyrics part.
- The Singer Screen opens on a second display, follows the performer's song, pass and progress in singer view, and closes cleanly when its display goes away (6.13).
- Analytics, accessibility labels, guide pages and `keyboard.json` updated; targeted suites green per step; one `make quick` per session; `make e2e-one` green for `SegueSingerViewE2ETests`.

## 20. Closed questions (R178, 2026-11-01)

1. **What a Chords only pass becomes in singer view:** First line, with the CHORDS tag (R178; 6.3).
2. **One preview setting or two:** the library and editor preview has its own singer toggle, separate from the stage's (R178; section 7).
3. **Song notes and slot notes in singer view:** hidden (R178, differing from the spec's recommendation; decision 6, 6.2, 6.7). Chart notes (`{comment}`) and stage cues still show.
4. **Stage key:** `V` (R178; 6.1).
5. **Singer lyric sizes:** up to 60 pt with a 28 pt floor (R178; 6.5).
6. **A Singer Screen on a second display:** ships in v1.0 as P9-2c (R178; 6.13).
7. **Print: the header key:** printed lyric sheets show the sounding key and no capo (R178; section 8 item 4).
