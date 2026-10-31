# P8-3 - Arrangement sequence strip: the Arrange Sections sheet rebuilt as B1

Wave 8 (2026-10-30). Rulings: `docs/release/decisions.md` **R149** (per-pass show modes, sequence strip), with R122 (per-slot arrangements), R123 (P3-16 details: sheet, live preview, anchoring, out of date, new sections), R147 (every pass written out on stage, section map, collapse-repeats removed), R148 (section jump, rehearsal loop) and R150 (single-song sessions from the library play the full song), **R156** ("Rehearse this" plays the slot's arrangement in the slot's key and capo, not logged; extends R150), **R155** (build order), **R158** (this spec's open questions closed, section 14). Related: R16 (builder undo), R79 (accessibility walk), R113 (test budget), R154 (serialized setlist undo snapshots). Predecessor spec: `docs/phases/3-workstreams/P3-16-slot-arrangements.md` (the current row-list sheet).

**Consumes P8-2's pass model.** Sibling spec `docs/phases/8-workstreams/P8-2-stage-map-and-passes.md` owns the pass model (one entry per pass, each with a show mode), the setlist schema v6 bump and its migration from v5 `plays`, the resolver, and stage rendering (map strip, pass badges, mode rendering). This spec owns only the editor: the draft logic, the sheet, the typed roadmap, the preview wiring, "Rehearse this", and the builder's arrangement text. Section 4 lists exactly what it needs from P8-2.

**Build order (R155):** all of Phase 8 ships before the v0.5 submission. P8-1 first, then P8-2, **then this spec (P8-3)**, which starts only once P8-2's model (step 1) and shared stage request (step 2) have landed; P8-4a and P8-5 run in parallel; P8-4b is blocked on research (R160). Index: `README.md` in this folder.

Ryan's brief: direction **B1, sequence strip**, plus "think about making this arrangement part easier to use".

## Session rules

- `cat` and `ls` are aliased to eza and can hang: use `command cat` / `command ls` or the Read/Grep/Glob tools; pass this on to any subagent. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-". Ignore `.build/`.
- Sibling workstreams (P8-4a, P8-5; P8-2 only if it is still finishing) may edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, stage only your own hunks. Keep the tree compiling between steps.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget (R113): per step only targeted in-process suites (`swift test --filter <Suite>`). At the end ONE `make quick`, ONE `make e2e-one` for `SegueArrangementE2ETests`, and ONE `make e2e-one` for `AccessibilityAuditE2ETests` (it opens this sheet). No `make gate`, no `make check`, no E2E retry loops. Every build or test runs under `lockf -k .build/make.lock`.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency, and before starting if P8-2's API (section 4) differs from what this spec assumes.

## 1. Goal

Arranging a slot becomes "build the sequence you will play": the song's parts in a palette, the slot's passes as a lane of chips in played order, each chip with a show mode (Full, Chords only, First line, Skip), an optional typed roadmap that mirrors the lane both ways, and a live stage preview that is exactly what the stage will draw. The common edits are one gesture each: play a chorus again, skip a verse, extend the outro, reset to the full song. A "Rehearse this" button plays the slot as arranged.

**In scope:** the sheet (layout, chips, palette, inspector, roadmap, preview, footer, banner), keyboard, drag and drop, accessibility, undo names, the pure draft and roadmap logic, the preview fix (section 3.4), "Rehearse this", the slot popover's and the slot mark's arrangement text, the guide page, analytics events, the editor half of the E2E.

**Not in scope:** the pass model, schema v6 and its migration, the resolver, stage and map rendering, section jump and loop (P8-2 / R148), single-song sessions from the library (R150 sibling), any change to the `.cho`.

## 2. Terms

- **Part**: one `SongSectionUnit` of the song (`SongSections.units(of:)`, `SlotArrangement.swift:222`): a labelled section, a `{chorus}` repeat, or a block of loose lines ("Lead-in", "After Verse 2"). Parts are anchored by label + occurrence + fingerprint (R123); this does not change.
- **Label group**: the parts that share a display label ("Chorus" written out three times = one group of three occurrences).
- **Pass**: one chip in the lane: a part plus a show mode. A part played twice is two passes. P8-2's model type; called `ArrangementPass` below.
- **Mode**: `full` (default), `chordsOnly`, `firstLine`, `skip` (R149). A skipped pass stays in the lane (dashed) but never reaches the stage or the map.
- **Pass number**: "2 of 3" for the second playing pass of a label group, the same numbering the stage map and gutter badges use (R147). Skipped passes are not numbered and do not count.
- **Roadmap**: the lane written as text, for example `I:ch V1 C V2 C B C O:1`.

## 3. Current behaviour (read before changing anything)

### 3.1 Sheet (`Packages/SegueUI/Sources/SegueUI/Setlists/ArrangementEditorSheet.swift`)

- `ArrangementEditorSheet` (:14-58) resolves the slot, song record and units, builds an `ArrangementDraft` from the saved `entry.arrangement` on every render, and saves each edit through `model.setArrangement` in a fire-and-forget `Task` (:35-44).
- `ArrangementEditorContent` (:60-278): 920 x 640 sheet (:88); header "Arrange Sections" plus "<title> · this gig only, the song is not changed" and "N of M sections play" (:94-116); out-of-date banner with Update (:118-142); a `List` of rows, 470 wide (:146-181) with a "New in the song" section, `onMove`, and keys Space, ⌥↑/⌥↓, +/=/-, ⌘D (:171, :205-232); footer with guide help, "Length for this gig" `LengthField` (slot target), "Song: 4:40" hint, Reset to Full Song, Done (:244-272).
- `edit(_:_:)` (:235-240) copies the draft, applies the change, saves. Because the draft is re-derived from the saved model, two quick edits before the first save lands both start from the same stale draft and the first is lost. This spec fixes that (section 6.6).
- `ArrangementRowView` (:282-427): checkbox, kind colour cap (`SectionBandStyle.dynamicColor(for:)`), title + ordinal + "again", first line, x1-x9 stepper, context menu and VoiceOver actions.
- `ArrangementPreview` (:431-499): a 1024 x 640 stage scaled into the right pane. **Bug:** its `LayoutRequest` (:487-498) hard-codes `minLyricSize: 22`, passes `columns: prefs.columns` (the song's own choice only) instead of `settings.columns(for: prefs)` (`Packages/SegueCore/Sources/Shows/LiveSettings.swift:61`, song choice else the Settings > Live default, clamped), and omits `zoom: prefs.zoom` and the header `notes` that the real stage passes (`Packages/SegueUI/Sources/SegueUI/Live/LiveSession+Viewport.swift:90-104`, minimum lyric size from `LiveSession.minLyricSize` at `LiveSession.swift:148`). So the preview can disagree with the stage on size, columns and line breaks. It also passes `collapseRepeats`, which R147 removes.

### 3.2 Draft (`Packages/SegueUI/Sources/SegueUI/Setlists/ArrangementDraft.swift`)

- Rows are steps (part + `plays` 0...9) with `isNew` and `isAgain` flags (:8-22). `init(arrangement:units:)` (:31-67) resolves each step with `ArrangementResolver.unit(for:in:)`, collects missing steps, appends unlisted parts as new rows with plays 0.
- Ops: `toggle`, `setPlays`, `move(fromOffsets:toOffset:)`, `move(_:by:)`, `playAgainLater` (:102-172); at least one row must play (`canToggleOff`, :102-105).
- `markText` (:188-195) builds the builder mark "Custom · 8 of 10 sections · Chorus 3rd x2"; `missingNames` (:198-208) the banner list.

### 3.3 View model (`Packages/SegueUI/Sources/SegueUI/Setlists/SetlistsViewModel+Arrangement.swift`)

- `openArrangement` (:19-22), `editArrangement` (pre-show checklist Edit, :25-28), `arrangeSelectedSlot` (menu, :39-42), `setArrangement(_:of:in:actionName:)` (:46-60): one builder undo step per save (R16), no-op when unchanged, records `.featureUsed(.setlistEdit, .builder)`.
- The sheet is presented from `SetlistBuilderView.swift:116-121` with `model` and `library` only (no Live settings).

### 3.4 Model (`Packages/SegueCore/Sources/Library/`)

- `SlotArrangement.swift`: `SectionRef`, `SectionAnchor` (:10-52), `ArrangementStep` with `plays` (:55-122), `SlotArrangement { steps, length }` (:126-186), `SongSectionUnit` (:192-216), `SongSections.units/ordinal/fingerprint/repeatTarget` (:219-401). P8-2 replaces steps-with-plays by passes-with-modes.
- `ArrangementResolver.swift`: `PlayedSection { index, plays }`, `ArrangementResolution.applied/outOfDate`, `resolve(_:units:)`, `unit(for:in:)` (:10-82), `ArrangedSections.build` (:98-128). P8-2 changes these to passes.

### 3.5 Other readers of the editor's text

- Slot popover row "Sections" (`SetEntryEditor.swift:42-55`, text at :93-102: "Full song…", "Custom: 6 of 8 sections…", "Out of date: full song…").
- Slot mark (`SlotArrangementMark.swift:38`, via `ArrangementDraft.markText`).
- Menu item Setlist > Arrange Sections… ⇧⌘A (`MenuShortcuts.swift:118-123`); Setlist > Rehearse is ⌥⌘↩ (:113).
- Identifiers: `AccessibilityID+Arrangement.swift` (row/play/count IDs go away, section 8.5); mirrored in `UITests/SegueArrangementE2ETests.swift:206+`.
- Guide page `guide/src/content/docs/arrange-sections.mdx` (linked from the sheet's help button, `SegueLinks.swift:64`).

## 4. Needs from P8-2

This spec is written against these names. If P8-2 names them differently, use P8-2's names; if a capability is missing, stop and ask.

1. **Pass type.** `ArrangementPass { anchor: SectionAnchor, fingerprint: String?, mode: PassMode }` and `PassMode: CaseIterable { full, chordsOnly, firstLine, skip }` with stable coded values. `SlotArrangement { passes: [ArrangementPass], length: TimeInterval? }` with a memberwise init and `static func fullSong(_ units:)` (every part once, Full, song order).
2. **Limits and invariants** as public constants and one validator the editor calls: `SlotArrangement.maxPasses` (recommend 48), "at least one pass is not Skip". The editor refuses edits that break them; decode behaviour is P8-2's.
3. **New-section detection without one chip per part.** B1 lets a pass be removed, so "every part is listed" (P3-16 section 3) no longer holds by construction. The editor needs P8-2 to record which parts the arrangement knew when saved (recommended: a `knownParts: [anchor + fingerprint]` list written on every save, replacing "skipped rows stay"), so a part added to the song later shows as **New** (R123). P8-2 records `knownParts` (its section 5 item 3), so Remove really removes (R158 P8-3 Q3).
4. **Resolver per pass.** `ArrangementResolver.unit(for: ArrangementPass, in:)` (anchor + fingerprint match, legacy fingerprint accepted, as today) and `resolve(_:units:) -> .applied(order: [PlayedPass], newSections:) | .outOfDate(missing: [ArrangementPass])`, where `PlayedPass` carries the part index, the mode and the pass's position in `passes` (the preview scrolls to it, section 6.4).
5. **Pass numbering.** One public function, for example `PassNumbering.numbers(_ passes: [ArrangementPass]) -> [PassNumber?]` (`n`, `total`; nil for skip and for groups played once), used by the stage map, the gutter badges and the editor chips, so "2 of 3" means the same everywhere. Numbering groups by display label (`SectionNotes.key`), not by occurrence.
6. **Stage layout input.** `LayoutRequest` takes the played passes with their modes (`arrangement: [PlayedPass]?`), `collapseRepeats` gone (R147). `LayoutPlan` exposes each pass's vertical extent keyed by pass position (for "scroll the preview to the selected pass").
7. **Map strip and badges for the preview.** The stage's section map strip as a SwiftUI view with a compact, non-interactive style (no number-key hints, no jump, no progress bar; mockup: 40 pt high row, chip labels 11.5 pt), and `StagePlanView` drawing the gutter pass badges and mode tags, so the preview needs no drawing code of its own.
8. **Migration** of v5 `steps/plays` to passes (P8-2's). The draft only ever sees passes.
9. **Summaries.** The gig log line (`playedSummary`, today `SlotArrangement.swift:155`) moves to passes in P8-2. This spec owns only the editor-side texts (section 6.8).
10. **Stage accessibility identifiers** for the map chips and pass badges, mirrored in the UITests target, for the E2E's stage assertions (section 10.4).
11. **Shared stage request.** Either P8-2 provides one function that builds the stage's `LayoutRequest` for (song, slot entry, Live settings, viewport), called by `LiveSession+Viewport.swift` and by the preview, or this workstream adds it (section 6.4) and P8-2 switches its call site. Agree which before step 4.

**Needs from the R150 single-song session workstream** (sibling P8 spec that adds Rehearse/Live from the library): an entry point that starts a one-song rehearsal for a song **with an optional slot entry** (key/capo overrides and arrangement), not logged to the Gig Log (R150), and that tells the caller when the session ends (section 6.7).

## 5. Decisions

1. **Layout is mockup B1** (R149): palette on top, lane, inspector for the selected chip, roadmap field, keyboard hint line; live stage preview on the right; footer with the slot length. The sheet keeps the name **"Arrange Sections"** and every entry point (popover row, slot context menu, Setlist > Arrange Sections… ⇧⌘A, pre-show checklist Edit) (R123).
2. **One chip per pass.** No play-count stepper and no `x2` badge anywhere in the editor; repeats are visible as chips with "2 of 3". "Play Again Later" (R123 question 2) becomes Duplicate plus drag, and "Play Again at End".
3. **Every edit saves at once as one builder undo step** (as today, R16), except the roadmap field, which previews live and commits once (decision 7).
4. **Edits apply to the newest draft, saves are serialized.** The sheet keeps a local draft that is authoritative while saves are in flight, and each save is awaited in order (no fire-and-forget `Task` per edit). Re-derive from the model only when no save is pending (external change, undo, redo). Matches R154's serialized undo snapshots.
5. **The draft is pure and owns all logic.** One `apply(_ edit:)` entry point returns the new arrangement, the new selection and the undo name, or a refusal reason. The views only map gestures and keys to edits. This is what the in-process tests drive.
6. **Selection is the keyboard cursor.** The lane always has exactly one selected chip (the first on open); it is index-based, survives saves, and is clamped after undo or removal.
7. **Roadmap commits on Return or focus loss**, as one undo step "Edit Roadmap". While typing, each valid parse updates the lane and the preview (draft-only, not saved); an invalid parse keeps the last valid lane, turns the field border cue-red and shows the error. Esc in the field reverts the text to the saved roadmap. Return in the field must commit and keep the sheet open: if the default-action Done fires instead, drop Done's `.defaultAction` shortcut while the field has focus.
8. **The roadmap is optional and never required** (Ryan's "syntax-heavy entry is a UX bug" rule): every edit is possible without it, autocorrect and spell-check are off in it (romanized Hindi labels), and the field's help line lists this song's tokens.
9. **Palette click inserts after the selected chip** and selects the new chip, so successive clicks build a sequence in order; drag places exactly. (The mockup appends at the end; R158 P8-3 Q2 confirmed insert-after.)
10. **Occurrences are picked automatically.** A palette button stands for a label group. Adding it picks the occurrence after the nearest earlier chip of that group in the lane (capped at the last occurrence; none earlier = the first). So adding a Chorus between Verse 2 and the Bridge gives "Chorus 2nd", and adding one after the last chorus gives the last chorus again (an extended ending). A palette button for a group with more than one occurrence has a menu (right-click, or the ▾ on hover) listing each occurrence with its first line, to pick one explicitly.
11. **The preview uses the stage's real request** (fixes section 3.1's bug): `settings.minLyricSize`, `settings.columns(for: prefs)`, `prefs.zoom`, the song's and slot's notes, the slot's key/capo overrides, at a 1024 x 640 stage. One shared builder function for stage and preview so they cannot drift again.
12. **"Rehearse this"** starts a one-song rehearsal of this slot as arranged (key, capo and arrangement), not logged; when it ends, the builder reopens this sheet. This is **R156**, which extends R150 (the library entry point keeps the full song).
13. **Kind colours** are the app's section band colours (`SectionBandStyle.dynamicColor(for:)`, P3-11), the same ones P8-2's map uses. The mockup's monochrome kind bars were illustrative.
14. **Arrange is available for every song**, including one-section songs (a single part can now usefully be played twice or as chords only).

## 6. Exact behaviour

### 6.1 Sheet layout (mockup B1 at 1200 x 760)

Sheet: **1200 x 760** pt, background `Theme.color.ground` for the preview pane and `surfaceAlt`-tinted chrome as below. Top to bottom:

- **Header bar**, 52 pt high, 18 pt side padding, 12 pt gaps, 1 pt `line` rule below:
  - Title "Arrange Sections", Schibsted Grotesk extraBold 17, `ink`, header trait, identifier `arrangementSheet` (on the title, as today).
  - Subtitle, medium 13, `muted`, one line, tail-truncated: "<song title> · <setlist name> · slot <N>".
  - Spacer, then three buttons (13 pt semibold, 7 pt radius, 6 x 13 padding, 1 pt `controlBorder`): **"Rehearse this"** with a leading play glyph and a muted "⌥⌘↩" key hint; **"Reset to Full Song"** (disabled when the slot has no arrangement or is read-only); **"Done"** primary (filled `ink`, dark text), `.defaultAction`.
- **Out-of-date banner** (only when out of date): as today (`cueText` triangle, "Out of date: no longer in the song: Verse 3. The stage shows the full song until you update.", Update button), `cue` at 8% behind.
- **Body**, two panes side by side:
  - **Left pane, 640 pt wide**, 18 pt top/bottom and 20 pt side padding, 18 pt vertical gap between blocks, scrolls vertically:
    1. Eyebrow "SONG PARTS - CLICK OR DRAG INTO THE SEQUENCE" (11 pt bold, 0.08 em tracking, uppercase, `muted`, 8 pt below), then the **palette** (6.2).
    2. Eyebrow "SEQUENCE", then the **lane** (6.3).
    3. The **inspector** for the selected chip (6.3).
    4. The **roadmap** block (6.5).
    5. **Hint line**, medium 12, `muted`: "← → select · ⌥← ⌥→ move · F C 1 S mode · ⌫ remove · ⌘D duplicate".
  - **Right pane**, the rest of the width, the **stage preview** (6.4), 1 pt `line` rule on its left.
- **Footer**, 52 pt high, 18 pt side padding, 10 pt gaps, 1 pt `line` rule above, 13 pt `muted`: guide help button (`GuideHelpButton(.arrangeSections)`), "Length for this gig", the slot `LengthField` with Time it (unchanged behaviour), "Song: 4:05" hint (unchanged), spacer, then "<n> passes play · <m> skipped · this gig only, the song is not changed" (the "· <m> skipped" part only when m > 0; "1 pass plays" singular).

### 6.2 Palette

- One button per **label group**, in order of first appearance in the song (Lead-in first when present). Button: 13 pt semibold `ink`, 1 pt `controlBorder`, 7 pt radius, padding 5 / 10 / 5 / 7, 7 pt gap between a 3 x 14 pt kind bar (radius 2) and the name. Hover: `surfaceAlt` fill. Buttons wrap with 6 pt gaps (`Components/FlowLayout.swift`, spacing 6, lineSpacing 6).
- Name: the group's label ("Verse 1", "Chorus", "After Verse 2"). Tooltip: "Add <name> after the selected pass (<token> in the roadmap)".
- **New** parts (section 4, need 3): the button carries a small "New" text tag (11 pt bold `cueText`) after the name; it disappears once the arrangement is saved again.
- A group with several occurrences shows a ▾ on hover; right-click or ▾ opens a menu: "Chorus 1st - Harbour lights, call me back", "Chorus 2nd - …", "Chorus 3rd - …" (first line from `SongSectionUnit.firstLine`). Picking one inserts that occurrence after the selected chip.
- Click (or Space/Return on a focused palette button) inserts per decisions 9 and 10. Drag a palette button into the lane to insert at the drop point (6.3).
- Read-only: buttons disabled.

### 6.3 Lane, chips and inspector

**Lane:** a wrapping row of chips (`FlowLayout`, spacing 8, lineSpacing 8) inside a 12 pt padded box with a 1 pt dashed `lineStrong` border, 10 pt radius, minimum height 96 pt. At 640 pt pane width that is 5 chips per row. The lane is one focusable element; it takes focus when the sheet opens.

**Chip** (one per pass, in played order), 108 x 74 pt, 9 pt radius, 1 pt `controlBorder`, `surfaceAlt` fill, padding 7 / 9 / 7 / 12 (top, right, bottom, left):

- Kind bar: 3 pt wide on the left edge, inset 9 pt top and bottom, right corners radius 2, band colour.
- Line 1: the pass's position in the lane, "1", "2", … (10 pt bold, `indicatorOff`).
- Line 2: the part's title, 14 pt bold `ink`, one line, tail-truncated. Shows the occurrence ordinal as a muted suffix ("Chorus ·3rd") only when the label group's written occurrences differ in content (some fingerprints differ after mapping a `{chorus}` repeat to its target); otherwise the plain title (R158 P8-3 Q4).
- Line 3: the pass number "2 of 3" (11 pt semibold `muted`), blank when the group plays once or the chip is skipped.
- Bottom: the mode tag, 10 pt bold, 0.06 em tracking, uppercase, `muted`: "FULL", "CHORDS", "1ST LINE", "SKIPPED". (Mockup 9.5 pt; raised to 10 for legibility, check in the R79 walk.)
- **Selected:** a 2 pt `ink` ring outside the border.
- **Skip mode:** no fill, dashed border, 55% opacity, title struck through. Still selectable, draggable and numbered in line 1.
- **Hover:** two 18 pt borderless buttons in the top-right corner, `muted`, 14 pt glyphs: "+" (Duplicate: a copy right after) and "×" (Remove). Hidden when read-only.
- **Dragging:** the source chip at 30% opacity.
- Tooltip: full name and first line.

**Pointer gestures on a chip:**

| Gesture | Effect | Undo name |
|---|---|---|
| Click | Select | (none) |
| ⌥-click | Toggle Skip / Full | "Skip Pass" / "Play Pass" |
| Hover "+" | Duplicate right after, select the copy | "Duplicate Pass" |
| Hover "×" | Remove (refused for the last pass that plays) | "Remove Pass" |
| Drag within the lane | Move to the drop point | "Move Pass" |
| ⌥-drag within the lane | Copy to the drop point | "Duplicate Pass" |
| Drag a palette part in | Insert at the drop point | "Add Pass" |
| Right-click | Context menu (below) | per item |

**Context menu:** Full / Chords Only / First Line Only / Skip (checkmark on the current mode; "Play" instead of Skip when skipped), divider, Duplicate (⌘D), Play Again at End, divider, Move Earlier, Move Later, Move to Start, Move to End, divider, Remove (⌫).

**Drop point:** while dragging over the lane, the drop index is the first chip whose bottom is below the pointer and that the pointer is above or left of the horizontal middle of; otherwise the end. An insertion mark shows there: 3 pt wide, 2 pt radius, `cue`, the chip's height, 6 pt left of the target chip (or 3 pt right of the last chip). It hides when the drag leaves the lane. Dropping outside the lane does nothing (no remove-by-drag-out). Implement with a location-aware `DropDelegate` on the lane and chip frames in the lane's coordinate space; drag payloads are strings ("pass:<position>", "part:<unit index>"), like `SetEntriesList.swift:232-235`.

**Refusals** (no save, a short `NSSound.beep()`, and the help text on the control): removing or skipping the last pass that plays ("At least one pass plays"); adding beyond `maxPasses` ("A slot can have up to 48 passes").

**Inspector** (below the lane): 1 pt `line` border, 10 pt radius, 12 x 14 padding, 10 pt gaps:

- Title row: part name 15 pt bold `ink`, then 13 pt medium `muted` "pass 2 of 3" (when numbered) and "· <first line>" (chords and bar lines stripped, as the mockup), one line, tail-truncated.
- **Mode picker**: a four-segment control, 1 pt `controlBorder`, 7 pt radius, segments 13 pt semibold `muted`, 6 x 12 padding, 1 pt dividers; the selected segment filled `ink` with dark text. Each segment shows its key hint after the name (11 pt medium, 60% opacity): "Full F", "Chords only C", "First line 1", "Skip S". Built as buttons with an `accessibilityRepresentation` of a `Picker` (section 8).
- Two small buttons (12 pt, 3 x 8 padding, 6 pt radius): "Duplicate ⌘D", "Remove ⌫".

### 6.4 Stage preview

- Header row, 14 / 16 / 8 padding: eyebrow "STAGE PREVIEW" (`muted`) left, eyebrow "AS THE STAGE WILL DRAW IT" (`indicatorOff`) right.
- The map strip row from P8-2 in its compact preview style (need 7), 40 pt high, 16 pt side padding, 8 pt below; skipped passes are absent from it (R147).
- The stage body: the real layout engine and `StagePlanView` at a 1024 x 640 stage scaled to the pane width (as today, `ArrangementEditorSheet.swift:443-473`), scrolls vertically, 8 / 16 / 20 padding.
- **Request:** built by one shared function, for example `StageLayoutRequest.make(song:entry:passes:settings:viewport:)` in `SegueUI/Live/`, returning exactly what `LiveSession+Viewport.swift:94-104` builds today: `minLyricSize: settings.minLyricSize`, `zoom: prefs.zoom`, `columns: settings.columns(for: prefs)`, cues, the song's and the slot's notes, the model with the slot's overrides, and the arrangement passes (need 11). The sheet receives the `LiveSettingsStore` from the builder (`AppModel.liveSettings`, `AppModel.swift:407`) through the sheet's initializer or an environment value; changing Settings > Live while the sheet is open updates the preview.
- **Follows the selection:** selecting a playing chip scrolls the preview so that pass's top is visible (animated unless Reduce Motion), using the plan's per-pass extents (need 6). Selecting a skipped chip does not scroll.
- Out of date: the preview shows what the stage will show (the full song) until Update.
- Accessibility: one element, "Stage preview, <n> passes", as today, identifier `arrangementPreview`.

### 6.5 Roadmap field

- Eyebrow "ROADMAP (OPTIONAL)", then a single-line field: monospaced 15 pt semibold (`.monospaced()` system font), `ink` on `ground`, 1 pt `controlBorder` (focused: `muted`; invalid: `cue`), 7 pt radius, 9 x 11 padding, 0.02 em tracking. Autocorrection, spell-check and text completion off.
- Help line (12 pt `muted`, codes in monospaced 12 pt semibold `ink`): "`:ch` chords only · `:1` first line · `-V2` skip · `x2` twice · parts `I V1 C V2 B O`", with this song's tokens.
- Error line (12 pt semibold `cueText`, reserved 15 pt height so nothing jumps), announced to VoiceOver when it appears.
- Sync: lane edits rewrite the field (unless the field has focus and holds an uncommitted edit); field edits follow decision 7.

**Grammar** (pure, SegueCore `Library/ArrangementRoadmap.swift`, `format(_ passes:, units:) -> String` and `parse(_ text:, units:) -> Result<[ArrangementPass], RoadmapError>`):

- Tokens separated by spaces or commas; case-insensitive; output upper-case, single spaces.
- `pass := ["-"] part ["#" occurrence] [":" mode] [("x" | "×") count]`. `-` = Skip; `:ch` = Chords only; `:1` = First line; `:f` = Full (accepted, never written); `x2` repeats the pass that many times (2...9, accepted, never written: the formatter writes each pass).
- **Part tokens** are derived per song, in order of first appearance: the initials of the label's words (split on spaces and hyphens), upper-cased, with a trailing number kept ("Verse 1" V1, "Chorus" C, "Chorus 2" C2, "Pre-Chorus" PC, "Intro" I, "Outro" O, "Bridge" B). On a clash with an earlier label, the later one extends its first word's prefix until unique ("Instrumental" after "Intro" becomes IN). Lead-in is `L` (same clash rule). A loose block after a part is that part's token plus `+` (`V2+`; a second block `V2+2`). Non-Latin labels use their first characters the same way.
- **Occurrences:** a bare token resolves by the counting rule of decision 10 applied left to right (the k-th bare `C` is Chorus occurrence min(k, count)), so the as-written song formats with bare tokens: `I V1 C V2 C B C O`. `C#3` pins occurrence 3. The formatter writes `#n` only where the counting rule would pick a different occurrence.
- Round trip: `parse(format(p)) == p` for every valid pass list (property test, section 10.1).
- Errors (first one wins, shown verbatim): `"Q" is not a part. Parts: I V1 C V2 B O.` · `C#4: the song has 3 Choruses.` · `At least one part plays.` · `A slot can have up to 48 passes.` · `"C:x" - modes are :ch and :1.`
- Empty field on commit = no change (it does not reset; Reset to Full Song is the button).

### 6.6 Keyboard (lane focused)

| Key | Effect | Undo name |
|---|---|---|
| ← / → | Select previous / next chip | - |
| Home / End (or ⌘← / ⌘→) | Select first / last chip | - |
| ⌥← / ⌥→ (also ⌥↑ / ⌥↓, the builder's move keys) | Move the selected pass one place | "Move Pass" |
| F / C / 1 | Set mode Full / Chords only / First line | "Show Full" / "Show Chords Only" / "Show First Line" |
| S | Toggle Skip / Full | "Skip Pass" / "Play Pass" |
| ⌘D | Duplicate right after, select the copy | "Duplicate Pass" |
| ⇧⌘D | Play Again at End (a copy as the last pass) | "Play Again at End" |
| ⌫ / ⌦ | Remove the selected pass | "Remove Pass" |
| Return | Done (default action) | - |
| ⌘Z / ⇧⌘Z | Builder undo / redo (R16) | - |
| Tab / ⇧Tab | Move focus: lane, inspector, roadmap, footer, header buttons, palette | - |
| ⌥⌘↩ | Rehearse this | - |

- Mode keys ignore Command and Control (⌘C copies nothing here and must not set Chords only). They act only when the lane has focus, never while typing in the roadmap or length fields.
- ⌥⌘↩ is the Setlist > Rehearse shortcut; while the sheet is open the menu item is disabled so the sheet's button wins. Verify with the shortcut clash test (`MenuAndAboutTests`).
- Esc closes the sheet (as Done); in the roadmap field Esc first reverts the field.

### 6.7 "Rehearse this"

- Disabled when the slot's song is missing, a show or rehearsal is running, or the arrangement is out of date (help: "Update the arrangement first" - the stage would show the full song).
- Action: commit a pending roadmap edit, wait for pending saves, dismiss the sheet, start a one-song rehearsal of this slot's entry (song, key/capo overrides, arrangement) through the R150 entry point (section 4). Not logged (R150, R156). The pre-show checklist is skipped, as for library single-song sessions.
- When that session ends, the builder reopens this sheet for the same slot (`model.arranging` set again), so rehearse-tweak-rehearse is a loop.
- Analytics: `featureUsed(.arrangementRehearse, .builder)`.

### 6.8 Builder texts

- Popover row (`SetEntryEditor.swift:93-102`): "Full song…", "Custom: 9 passes, 1 skipped…", "Out of date: full song…".
- Slot mark (`ArrangementDraft.markText`, used by `SlotArrangementMark.swift:38`): "Custom · " + the roadmap (tail-truncated by the row), for example "Custom · I:CH V1 C V2 C B C O:1"; VoiceOver reads "Custom arrangement, 9 passes, 1 skipped". Out-of-date mark unchanged.
- Banner missing names (`missingNames`) unchanged, per pass.

### 6.9 Common edits, one gesture each

| Edit | Gesture |
|---|---|
| Play a chorus again (right after) | Hover the chorus chip, click "+" (or ⌘D) |
| Play a chorus again later | ⌥-drag the chorus chip to the spot, or drag "Chorus" from the palette |
| Extend the ending with a chorus | Right-click the chorus chip > Play Again at End (or ⇧⌘D) |
| Skip a verse | ⌥-click the verse chip (or select + S) |
| Extend the outro | Hover the outro chip, click "+" |
| Chords only for the intro | Select + C (or right-click > Chords Only) |
| Reset to the full song | "Reset to Full Song" in the header (undoable, no confirmation) |
| Type a whole arrangement | Roadmap field, Return |

The guide page lists this table.

### 6.10 Read-only and edge cases

- Read-only setlist (newer schema, or the builder's read-only state during a show): palette, chip buttons, mode picker, roadmap and footer controls disabled; selection and the preview still work.
- Out of date: the lane shows the passes that still resolve, the banner lists the rest, Update saves the lane as shown (undo "Update Arrangement").
- The slot or song disappears while the sheet is open: today's fallback view (`ArrangementEditorSheet.swift:47-56`).
- A full-song slot: the lane shows `fullSong(units)`; the first edit creates the arrangement in the same undo step (P3-16 section 9).
- An arrangement identical to the full song is still saved if the user made it (P3-16 section 3).

## 7. Draft API (SegueUI, pure)

`ArrangementDraft` is rewritten around passes:

```swift
struct ArrangementDraft: Equatable {
    struct Chip: Equatable, Identifiable {
        var id: Int            // position in the lane
        var unit: SongSectionUnit
        var mode: PassMode
        var number: PassNumber?  // from P8-2's numbering
    }
    enum Edit: Equatable {
        case insert(unit: Int, at: Int)          // palette click (after selection) or drop
        case insertGroup(label: String, after: Int)  // occurrence by decision 10
        case duplicate(Int)
        case playAgainAtEnd(Int)
        case remove(Int)
        case move(from: Int, to: Int)
        case setMode(Int, PassMode)
        case toggleSkip(Int)
        case replace([ArrangementPass])          // roadmap commit
        case update                              // out-of-date Update
    }
    enum Refusal: Equatable { case lastPlayingPass, tooManyPasses, nothingChanged }
    struct Result: Equatable { var arrangement: SlotArrangement; var selection: Int; var actionName: String }

    init(arrangement: SlotArrangement?, units: [SongSectionUnit])
    private(set) var chips: [Chip]
    private(set) var missing: [ArrangementPass]
    private(set) var newParts: [SongSectionUnit]
    var length: TimeInterval?
    let isCustom: Bool
    func apply(_ edit: Edit, selection: Int) -> Swift.Result<Result, Refusal>
    var roadmap: String
    func parseRoadmap(_ text: String) -> Swift.Result<[ArrangementPass], RoadmapError>
    var playingCount: Int; var skippedCount: Int
    static func markText(_: SlotArrangement, units: [SongSectionUnit]) -> String
    var missingNames: String
}
```

`apply` never mutates the receiver; the sheet holds the result as its local draft (decision 4) and enqueues the save.

## 8. Accessibility

1. **Chip**: one element, button trait, `isSelected` when selected. Label "Chorus, pass 2 of 3" (or "Chorus 3rd" when the ordinal shows); value "Chords only, 5 of 9" / "Skipped, 3 of 9". Custom actions: Full, Chords Only, First Line Only, Skip (Play when skipped), Duplicate, Play Again at End, Move Earlier, Move Later, Remove. VoiceOver can do every edit without dragging.
2. **Lane**: container labelled "Sequence, 9 passes, 1 skipped"; ←/→ also work with VoiceOver's own navigation.
3. **Palette button**: "Add Chorus", hint "Adds a pass after the selected one"; the occurrence menu is a custom action "Choose which Chorus".
4. **Mode picker**: `accessibilityRepresentation { Picker("Show mode for Chorus, pass 2", selection:) { … } }` so it reads as a picker with four values.
5. **Roadmap**: label "Roadmap", hint = the help line; errors posted as an announcement; the invalid state is the error text, never the red border alone.
6. **Selection and Skip are never colour-only**: the ring is a shape, Skip has the dashed border, strike-through and the "SKIPPED" tag.
7. **Reduce Motion**: no animated chip reflow or preview scrolling.
8. **Identifiers** (`AccessibilityID+Arrangement.swift`, mirrored in the UITests target): keep `arrangementOpen`, `arrangementMark`, `arrangementSheet`, `arrangementReset`, `arrangementUpdate`, `arrangementDone`, `arrangementMissing`, `arrangementPreview`, `liveArrangement`, `checklistArrangements`. Remove `arrangementRow/Play/Count/CountUp/CountDown`. Add `segue.setlist.arrangement.lane`, `.chip.<n>`, `.chip.<n>.duplicate`, `.chip.<n>.remove`, `.palette.<n>` (group index), `.mode.<full|chords|first|skip>`, `.duplicate`, `.remove`, `.roadmap`, `.roadmapError`, `.rehearse`.
9. The new sheet joins the R79 accessibility walk (the audit test's `p3-arrange-sections` step keeps working through the kept IDs) before any label is claimed.

## 9. Analytics

Non-PII events through the existing `services.record(.featureUsed(_, .builder))`, adding `FeatureKey` cases (`Packages/SegueCore/Sources/Services/AnalyticsEvent.swift:205+`): `arrangementMode` (a mode set, with no song data), `arrangementRoadmap` (a roadmap commit), `arrangementRehearse`. Keep `setlistEdit` on every save as today.

## 10. Test plan (R113)

Fast in-process tests carry the logic; one XCUITest covers the core edit flow.

### 10.1 SegueCore `ArrangementRoadmapTests` (new, pure)

- Token derivation: V1/V2/C/B/I/O; "Chorus 2" C2; "Pre-Chorus" PC; Intro + Instrumental clash -> I, IN; Lead-in L; loose blocks `V2+`, `V2+2`; a non-Latin label.
- Format: as-written song -> `I V1 C V2 C B C O` (bare tokens by the counting rule); a pinned out-of-order occurrence gets `#n`; modes `:CH`, `:1`, `-`.
- Parse: case-insensitivity, commas, `x2` / `×3` expansion, `:f`, each error message verbatim, maxPasses, "at least one plays".
- Property: `parse(format(p)) == p` over generated pass lists for three fixture songs (one with three differing choruses, one with a `{chorus}` repeat, one with loose lines).

### 10.2 SegueUI `ArrangementDraftTests` (new, pure, no fixture app)

- `init` from nil = `fullSong`; from passes; out-of-date passes go to `missing`; unknown parts go to `newParts`.
- Every `Edit`: resulting passes, selection and undo name; refusals (last playing pass via remove, skip and ⌥-click; maxPasses via insert, duplicate, ⌥-drag, roadmap).
- Decision 10 occurrence picking: between V2 and B -> 2nd; after the last chorus -> last; no earlier chorus -> 1st.
- Move semantics for drop indexes (before itself, after itself, to end) match the mockup's splice rule.
- Pass numbers on chips equal P8-2's numbering for the same passes.
- `markText`, popover text, footer counts.

### 10.3 SegueUI `ArrangementEditorTests` (rewrite the existing suite, `Packages/SegueUI/Tests/SegueThemeTests/ArrangementEditorTests.swift`)

- Through the real view model and store: each edit is one undo step with its name; undo restores the lane and clamps the selection; the `.cho` is byte-identical; Reset removes the arrangement.
- **Rapid edits** (decision 4): F then C then ⌘D issued without awaiting each save end with all three applied, three undo steps, in order.
- Roadmap commit is one undo step; an invalid roadmap saves nothing.
- Preview request: the shared builder given Settings min lyric size 30 and default columns 2 with a song without its own columns returns `minLyricSize 30`, `columns 2`, the song's zoom and notes (the section 3.1 bug).
- Keep the existing timing, gig log line and Time-it tests, updated to passes.

### 10.4 E2E: rewrite `UITests/SegueArrangementE2ETests.swift` (the one XCUITest)

Fresh library, seeded set (as today): open the slot popover > Sections > the sheet shows 6 chips -> select the Bridge chip, press S -> the file has the Bridge pass as skip -> hover the last Chorus chip, click "+" -> 7 passes on disk -> type `I V1 C V2 C -B C O:1` in the roadmap, Return -> the sheet is still open and the file matches -> length 2:40 -> Done -> the row shows the mark and 2:40 -> Rehearse this from the sheet (reopen it) -> the stage map shows no Bridge and a "2 of 2" Chorus (P8-2 identifiers) -> end -> the sheet is open again -> Done. Keep the out-of-date half (rename a section -> "out of date"). The gig log assertion moves to whichever test still starts a full show (keep `playTheShow` with P8-2's new texts).

The stage half of this class depends on P8-2's identifiers and texts: land it after P8-2 (R158 P8-3 Q6: P8-3 owns the whole class).

### 10.5 End of workstream

One `make quick`; one `make e2e-one` for `SegueArrangementE2ETests`; one `make e2e-one` for `AccessibilityAuditE2ETests`.

## 11. Steps

0. Read P8-2's spec and code as landed; confirm every item in section 4 exists or agree the gaps with the orchestrator. Agree who adds the shared stage request (need 11).
1. `ArrangementRoadmap` (SegueCore Library) with `ArrangementRoadmapTests`.
2. `ArrangementDraft` rewrite with `ArrangementDraftTests`; `markText`, popover text.
3. Serialized saves and the local draft in the sheet; `setArrangement` awaited in order; `ArrangementEditorTests` rapid-edit test.
4. Shared stage `LayoutRequest` builder and the preview fix; Live settings into the sheet; preview follows the selection.
5. The B1 sheet: header, palette, lane, chips, drag and drop, inspector, roadmap, footer, keyboard, context menus, accessibility, identifiers; analytics.
6. "Rehearse this" through the R150 entry point; reopen on end; menu disable while open (clash test).
7. Guide page `guide/src/content/docs/arrange-sections.mdx` rewritten for the strip (with the 6.9 table and a fresh light and dark screenshot); E2E rewrite; end-of-workstream runs.

## 12. Files owned

- Rewrite: `SegueUI/Sources/SegueUI/Setlists/ArrangementEditorSheet.swift` (may split into `ArrangementLane.swift`, `ArrangementChip.swift`, `ArrangementPalette.swift`, `ArrangementInspector.swift`, `ArrangementRoadmapField.swift`, `ArrangementPreview.swift` in the same folder), `ArrangementDraft.swift`, `SetlistsViewModel+Arrangement.swift`, `AccessibilityID+Arrangement.swift`, `Tests/SegueThemeTests/ArrangementEditorTests.swift`, `UITests/SegueArrangementE2ETests.swift`, `guide/src/content/docs/arrange-sections.mdx`.
- New: `SegueCore/Sources/Library/ArrangementRoadmap.swift` and its test; `Tests/SegueThemeTests/ArrangementDraftTests.swift`; the shared stage request file if need 11 lands here.
- Additive hunks: `Setlists/SetEntryEditor.swift` (row text), `Setlists/SlotArrangementMark.swift` (mark text), `Setlists/SetlistBuilderView.swift` (pass Live settings, reopen after rehearse), `App/Commands/SetlistCommands.swift` (disable Rehearse while the sheet is open), `Services/AnalyticsEvent.swift` (three keys), `UITests/AccessibilityAuditE2ETests+Phase3.swift` only if a kept identifier moves.
- Not owned (P8-2): `SlotArrangement.swift`, `ArrangementResolver.swift`, `Setlist.swift`, `SetlistStore.swift`, `LiveLayout/*`, `Live/*` (except the one call-site switch agreed in step 0).

## 13. Done criteria

- The sheet matches section 6 in light and dark (screenshots in the E2E), at 1200 x 760, with every gesture in 6.3, every key in 6.6 and every edit in 6.9 working and each one undo step.
- The roadmap and the lane stay in sync both ways; `parse(format(p)) == p` holds; invalid input never saves.
- The preview equals the stage for the same slot (same min lyric size, columns, zoom, notes, passes and modes); the hard-coded 22 is gone.
- Rapid edits are never lost.
- "Rehearse this" plays the slot as arranged, is not logged, and returns to the sheet.
- VoiceOver can perform every edit; the R79 walk passes; no colour-only state.
- The `.cho` is byte-identical before and after any arrangement edit.
- Targeted suites green; one `make quick` green; `SegueArrangementE2ETests` and `AccessibilityAuditE2ETests` green once each.
- The guide page describes the strip.

## 14. Closed questions

Closed by Ryan on 2026-10-30 (**R158**: "P8-3: Q1 per R156, Q2-Q7 all a"; a = the recommendation). The body above already reflects each answer.

1. **"Rehearse this" plays the arrangement or the full song?** The slot's arrangement in the slot's key and capo, not logged (**R156**, extending R150: library = full song, arrangement editor = that slot; section 6.7).
2. **Palette click.** Inserts after the selected chip (R158 Q2; decision 9).
3. **Remove versus Skip.** P8-2 records `knownParts`; Remove really removes and Skip is a visible "we cut this" reminder (R158 Q3; section 4 need 3).
4. **Repeated labels.** One palette button per label group with automatic occurrence, and the ordinal on a chip only when the occurrences differ in content (R158 Q4; decision 10, section 6.3).
5. **Roadmap extras.** `x2` and `:f` are accepted on input though never written (R158 Q5; section 6.5).
6. **Owner of the stage half of `SegueArrangementE2ETests`.** P8-3 owns the whole class and lands its rewrite after P8-2, using P8-2's stage identifiers (R158 Q6; section 10.4).
7. **Sheet name.** Keep "Arrange Sections" (R158 Q7; decision 1).
