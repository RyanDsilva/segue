# P3-16 - Per-slot arrangements: which sections a setlist slot plays

Wave 3 (new, 2026-10-19). Parent spec: `docs/phases/3-ai-entry-and-assistant.md` (sections 14-16). Ruling: `docs/release/decisions.md` **R122**. Related rulings: R16 (builder undo), R17 (autosave), R79 (accessibility walk), R84-R88 (builder, breaks, changeover, missing-lengths list), R91 (manual length plus Time it; unknown stays unknown), R102/R112 (no repeats in a show), R107 (packer leaves out songs with no length), R114-R115 (assistant, locked slots), R118 (metronome). Phase 2 interfaces `docs/phases/2-interfaces.md` (cue anchoring, repeat collapsing).

Ryan's request: "what if I want my setlist to have only specific sections of a song or specific repeats for a particular gig?"

## Session rules (apply to every P3 workstream)

- `cat` is aliased to eza and can hang: use `command cat` or the Read tool. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-".
- Sibling workstreams edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, and stage only your own hunks. Keep the tree compiling between steps.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget (R113): per step only targeted in-process suites (`swift test --filter <Suite>`); new UI behaviour gets in-process SegueUI tests, and a new XCUITest only for a flow that cannot be tested in-process. At the end of the workstream ONE `make quick` plus ONE `make e2e-one` per UI test class added or changed. No `make gate`, no `make check`, no E2E retry loops, no scratch-worktree builds. Every build or test runs under `lockf -k .build/make.lock`.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency.

## 1. Goal

For one gig, a setlist slot can say "play Intro, Verse 1, Chorus, Verse 2, then the last Chorus twice, skip the Bridge", without touching the song. The `.cho` stays the master; "Reset to Full Song" removes the override. The stage, the set totals and the gig log all follow the slot's arrangement, and every place that cannot honour it says so instead of guessing.

**In scope:** skip sections, per-section play counts, reorder, play a section again at another point; a slot length for an arranged slot; out-of-date detection; stage rendering; timing; gig log; undo; accessibility.

**Not in scope (R122):** named song-level arrangements ("Acoustic version" saved on the song), stage-time section jumping, any change to the `.cho`, the song PDF export or the library preview (they always show the full song).

## 2. Terms

- **Section**: one `RenderSection` of the song rendered with default options (the same list `SectionNotes` and the section band use): a labelled section, a `{chorus}` repeat, or a run of loose lines outside any section.
- **Anchor**: how an arrangement names a section: its display label (`SectionNotes.label(of:)`: own label, else the kind's name), compared case-insensitively after trimming, plus the 1-based occurrence of that label in the song (`Anchors` in `SectionNotes.swift`). A `{chorus}` repeat counts as an occurrence of its label, exactly as for cues. Loose lines have no label: each maximal run of them is anchored to the labelled section before it (`loose(after:)`), or is the lead-in (R123).
- **Step**: one row of an arrangement: an anchor plus a play count. Play count 0 = skipped.
- **Arranged slot**: a song slot whose `SetlistEntry.arrangement` is non-nil.
- **Slot length**: the length entered (or timed) for an arranged slot. The song's `{duration}` is untouched and keeps the full song's length.

## 3. Data model (SegueCore `Setlists/`)

```swift
/// Which section of the song a step plays: the section notes anchoring rule.
public enum SectionAnchor: Sendable, Hashable, Codable {
    /// The labelled section (or `{chorus}` repeat) with this label and 1-based occurrence.
    case section(label: String, occurrence: Int)
    /// The loose lines before the first labelled section (the "Lead-in" row).
    case leadIn
    /// The block of loose lines right after this labelled section (R123).
    case loose(afterLabel: String, occurrence: Int)
}

public struct ArrangementStep: Sendable, Hashable, Codable {
    public var anchor: SectionAnchor
    /// A short content fingerprint of the section when the step was saved (R123);
    /// nil when not recorded.
    public var fingerprint: String?
    /// 0 = skipped, 1 = once (default), up to `SlotArrangement.maxPlays` (9).
    public var plays: Int
}

/// A setlist slot's arrangement for this gig only (R122).
public struct SlotArrangement: Sendable, Hashable, Codable {
    public static let maxPlays = 9
    /// Every section of the song, in played order: skipped sections stay in the list (plays 0)
    /// so a section added to the song later is recognisable as new.
    public var steps: [ArrangementStep]
    /// The slot's length in seconds (manual or timed); nil = unknown, flagged in totals.
    public var length: TimeInterval?
}
```

- `SetlistEntry` gains `arrangement: SlotArrangement?` (song slots only; always nil for a break). It is a separate field from `SetlistOverrides` on purpose: "Use Song's Key and Capo" resets `overrides` and must not wipe an arrangement, and "Reset to Full Song" must not touch key or capo.
- JSON (inside an entry), absent when nil:
  ```json
  "arrangement": {
    "steps": [
      {"section": "Intro", "occurrence": 1, "fp": "4f1a9c02", "plays": 1},
      {"section": "Verse", "occurrence": 1, "fp": "b7e0d3aa", "plays": 1},
      {"section": "Bridge", "occurrence": 1, "fp": "0c55e9f1", "plays": 0},
      {"section": "Chorus", "occurrence": 3, "fp": "9d2be417", "plays": 2}
    ],
    "length": 215
  }
  ```
  The lead-in is `{"leadIn": true, "fp": "...", "plays": 1}`; a loose block is `{"after": "Verse 2", "occurrence": 1, "fp": "...", "plays": 1}`. `length` is omitted when nil. Unknown keys are ignored on read, as everywhere else.
- **Invariants** (enforced by the editor and checked on decode; a file that breaks them loads with the arrangement marked out of date, never rejected): at least one step plays; plays in 0...9; an anchor appears at most once with plays 0 (a skipped row); "Play Again Later" rows repeat an anchor with plays >= 1.
- **"Is it worth saving?"** An arrangement identical to the full song (every section once, song order) is still saved if the user made it (they may want the slot length); the slot shows it as arranged. Only "Reset to Full Song" removes it.

### 3.1 Schema bump to 5

- `Setlist.currentSchemaVersion` 4 -> 5. History line: "5 = per-slot arrangements (R122)".
- Migration 4 -> 5 is the identity (no field changes); add the step to `SetlistStore.migrator` so a v4 file reads as current and is written at v5 on its next save (the existing rule).
- An older build (schema 4) opening a v5 file gets `readOnly = .newerSchema(found: 5, supported: 4)` and never rewrites it (existing `VersionedJSON` behaviour; the builder shows its read-only banner). This is what protects an arrangement from being silently dropped by an older build that ignores the unknown key.
- **`ShowRecord`** 2 -> 3: `ShowItem` gains `arrangement: SlotArrangement?` and `arrangementState` (section 6). Identity migration 2 -> 3. `planned: [SetlistEntry]` carries arrangements through the entry codec.
- Question 6 asks whether every saved setlist moves to v5 or only ones that hold an arrangement.

## 4. Resolution (pure, SegueCore)

`ArrangementResolver.resolve(_ arrangement: SlotArrangement, sections: [RenderSection]) -> ArrangementResolution`:

```swift
public enum ArrangementResolution: Sendable, Equatable {
    /// Every step resolved: the sections to play, in order, each with its play count.
    case applied(order: [PlayedSection], newSections: [SectionAnchor])
    /// Some step no longer resolves (label gone, occurrence gone, or fingerprint mismatch).
    case outOfDate(missing: [ArrangementStep])
}
public struct PlayedSection: Sendable, Equatable {
    /// Indices into the song's `RenderModel.sections` (one labelled section, or a run of
    /// consecutive loose sections).
    public var sections: [Int]
    public var plays: Int
    public var anchor: SectionAnchor
}
```

- Anchoring reuses `Anchors` from `SectionNotes.swift` (make it `public` or add a public `SectionNotes.anchor(of:in:)`; P3-13 owns that file, so this is a small additive hunk agreed with P3-13).
- `newSections`: anchors of the current song that the arrangement does not list (a section added since). They do not make it out of date; see section 16 (4) for how they show.
- The resolver runs on the song rendered with **default** options (like `SectionNotes`), so a transposition or capo override never changes which section an anchor names.
- Fingerprint (R123): `RepeatCollapser.normalize` of the section's lyric text (chords and comments excluded, so re-voicing chords or editing a note never invalidates), first two lyric lines, stable 32-bit FNV-1a in hex. A `{chorus}` repeat's fingerprint is `"repeat"` (its content is its target's). Loose lines hash the same way.

## 5. Stage behaviour (LiveLayout + Live)

- **Seam:** `LayoutRequest` gains `arrangement: [PlayedSection]?` (nil = full song). `SongPreparation.measure()` applies it **after** pinning cues and resolving `{chorus}` repeats against the song's own section order, then emits the measured sections in played order. This keeps three things song-relative: cue anchors (a cue on "Chorus 2" stays on that chorus wherever it is played), `{chorus}` repeat targets (a `{chorus}` line whose written chorus was skipped still renders that chorus's body), and the gutter labels (Verse 2 stays "Verse 2" even when Verse 1 is skipped).
- Skipped sections are gone from the stage with their cues. A cue pinned only to skipped sections is not "unmatched" and does not move to the notes block (it is simply not played).
- `MeasuredSection.id` must stay unique: a section played twice gets a derived id (`id * 16 + playIndex`, or a new composite id type; decide in step 3 with the layout tests).
- **Play counts** show per R123 (1 = b): consecutive plays are laid out as consecutive sections and the existing repeat collapsing turns the second into the "Repeat chorus" line, honouring the song's "collapse repeats" live preference.
- Cues on a section played N times show on its first rendering only.
- **Out of date:** the stage renders the full song (R122). See section 16 (5) for what the stage and the pre-show checklist say about it.
- **Header:** the stage chrome's key line gains a quiet "Arranged" tag on an arranged slot ("D, capo 2 · Arranged"); the up-next preview and the Page Down / auto-scroll layout use the arranged plan.
- **Auto-scroll speed:** `ScrollSpeedInput.duration` for an arranged slot is the slot length; with no slot length it is nil (the model's tempo and line-count path), never the full song's `{duration}` (R122 "never derived").
- **Rehearsal** behaves exactly like a show.
- **Metronome** (R118) is unaffected (tempo and meter are song-level).
- `LiveSession.renderModel(_:overrides:)` stays as is; `relayout()` resolves the arrangement once per item and passes it in the request. Resolution is cached per item id (cheap anyway: linear in sections).

## 6. Gig log and show records

- At show start `ShowController` copies `entry.arrangement` into `ShowItem.arrangement` (next to `overrides`, `ShowController.swift` ~99). Requests and inserted songs have none.
- When an item first becomes current, the stage records what it actually used in `ShowItem.arrangementState`: `.applied` or `.outOfDate` (full song played). Recorded once per item; it never changes afterwards, so the log is truthful even if the song is edited after the gig.
- The gig detail's Played list (`GigLog/GigDetailView.swift`, `GigPlayedList`) shows a second line on such rows: "Custom arrangement: Intro, V1, C1, V2, C3 x2" (skipped sections omitted; label short forms from `SectionLabels`), or "Full song (arrangement out of date)". The actual played time stays what the show measured.
- **Edits during a show:** editing an arrangement in the builder while a show of that setlist runs changes the setlist only; the running show keeps its start snapshot, as overrides do today (verify in step 1 and say so in the editor footer if true).
- **Save to setlist** (`ReorderDiff`): performed entries are taken from the current setlist (arrangement included), so nothing is lost; inserted rows get no arrangement.

## 7. Timing rules

- `SetlistTiming` takes the length per entry: an arranged slot uses `arrangement.length` (new `SongLengthSource.slot`), whatever the song's `{duration}` says; nil = unknown, counted in `unknownItemIds` and the "N unknown" button (R88, R91). A non-arranged slot is unchanged.
- The builder row's length cell shows the slot length; the timeline strip (design C) and part totals follow automatically.
- **Missing-lengths list** (`MissingLengthsList.swift`): an arranged slot's row reads "<title> · Custom arrangement"; its `LengthField` writes the slot length (builder undo, not the song's editor); its secondary action is "Edit Arrangement..." instead of "Open Song".
- **Time it for a slot:** `TimeItModel` is keyed by song id today; it gains a target enum (`.song(SongID)` / `.slot(SetlistID, SetlistItemID)`), additive, so the arrangement editor's length row and the missing-lengths row can time the arranged version. One run at a time across the app stays true.
- **Out of date** while computing totals: they keep the slot length (R123).
- **Set assistant (P3-7):** Rebuild keeps a locked slot's whole `SetlistEntry` (arrangement and slot length included) and counts its slot length in `fixedLength`; an unlocked song that Rebuild picks again reuses its entry (existing `reusable` path) and so keeps its arrangement; the packer counts that slot's length, and an arranged slot with no slot length is a song with no length for R107 (left out and listed). The packer never reads `{duration}` for an arranged slot.

## 8. Builder UI (Arrange mode)

Direction B, the sheet (R123):

- **Entry points:** the slot popover (`SetEntryEditor`) gets an "Arrangement" row ("Full song" / "Custom: 6 of 8 sections" with Edit...); the slot context menu gets "Arrange Sections..."; a menu item Setlist > Arrange Sections... with a shortcut in `MenuShortcuts.all` (the clash test decides). The sheet holds the section list (left) and a live miniature stage (right, the real stage layout engine at a small size); footer: length, Time it, Reset to Full Song, Done. Pick mode does not show the editor.
- **Section list:** one row per step in played order: drag handle, play checkbox, the section's kind colour cap (P3-11 band colours: verse blue, chorus amber, bridge violet, intro/outro green, other grey), label ("Verse 2"; a label that occurs more than once gets a muted ordinal, "Chorus 3rd", since `{chorus}` repeats and unlabelled choruses all read "Chorus"), a muted first lyric line, and a play-count stepper ("x1" ... "x9", shown only when it is above 1 or on hover/focus). Skipped rows stay in place, dimmed with the label struck through, so they can be ticked back.
- **Reorder:** drag, ⌥↑ / ⌥↓ on the focused row (the builder's own keys), VoiceOver Move Up / Move Down actions.
- **Footer:** "Length for this gig" `LengthField` with Time it, the song's own length shown beside it as a hint ("Song: 4:40") and never copied; "Reset to Full Song" (destructive-styled secondary, removes the arrangement and its slot length after no confirmation since undo covers it).
- **Slot mark:** an arranged row shows a small "Custom arrangement" line under the title ("Custom · 6 of 8 sections", or the summary "V1 C1 V2 C3 x2"); the slot note, if any, shares that line ("start soft · Custom"). Out of date: the line turns cue-coloured, "Arrangement out of date - full song on stage", and clicking it opens the editor.
- **Out-of-date editor:** opening it shows the current song's sections with every step that still resolves kept as it was, the missing steps listed above the list ("No longer in the song: Verse 3"), and an "Update" button that re-anchors and clears the flag.
- **New sections** (R123): listed at the end, unticked, under "New in the song".
- **Read-only setlist** (newer schema, or a show running if the builder is read-only then): the editor opens read-only.
- Songs with fewer than two sections: "Arrange Sections..." is disabled with the help text "This song has only one section".

## 9. Undo

Builder undo (R16, `SetlistsViewModel+Undo.registerSnapshotUndo`) covers every change as one step each, with action names: "Skip Section" / "Play Section", "Change Play Count", "Move Section", "Set Slot Length", "Reset to Full Song", "Update Arrangement". The first change on a full-song slot creates the arrangement in the same step, so undoing it returns the slot to "Full song". Stepper presses coalesce into one undo step while the stepper keeps focus (as the transpose stepper should; if it does not today, match whatever it does and note it).

## 10. Accessibility

- Each section row is one accessibility element: "Chorus 3, playing twice, 5 of 8" / "Bridge, skipped, 3 of 8"; Space toggles play/skip; the play count is an adjustable element (VoiceOver increment/decrement); custom actions Move Up / Move Down.
- The slot mark and the out-of-date mark are text, never colour or glyph alone; the out-of-date line is announced as "Arrangement out of date. The full song will be shown on stage."
- Kind colour caps are decorative (the label names the section), as on the section band.
- Contrast: the cue-coloured out-of-date text uses `cueText` (already AA on both grounds).
- Identifiers: `segue.setlist.arrangement.{open,row.<n>,play.<n>,count.<n>,length,timeIt,reset,update,mark}`.
- New UI joins the R79 accessibility walk before any label is claimed.

## 11. Tests (R113 budget)

- Core (`SlotArrangementTests`, new): codec round trip and absent-when-nil; invariants on decode; v4 -> v5 migration reads unchanged; a v6 file opens read-only; `ShowRecord` v2 -> v3. `ArrangementResolverTests`: skip, reorder, plays, `{chorus}` repeat target kept when its chorus is skipped, cues stay on their song-relative section, label renamed -> out of date, occurrence gone -> out of date, fingerprint mismatch after inserting a verse earlier -> out of date, new section detected, loose lines rule (R123).
- LiveLayout (`SongPreparationArrangementTests` in the existing layout suite): played order, unique ids for a section played twice, the repeat display per R123 with collapse on and off, auto-scroll duration from the slot length / nil.
- `SetlistTimingTests` (extend): an arranged slot uses its slot length, nil is unknown even when the song has `{duration}`, out-of-date per R123.
- Assistant (`PackerTests`, extend): Rebuild keeps a locked arranged slot whole; a re-picked unlocked arranged song keeps its arrangement; an arranged slot with no slot length is left out per R107.
- SegueUI in-process (`ArrangementEditorTests`, new): toggle, count, move, reset, each one undo step with its name; missing-lengths row writes the slot length; the slot mark text; out-of-date editor shows the missing steps.
- E2E (one new class, `SegueArrangementE2ETests`, because the stage result cannot be checked in-process end to end): fresh library -> Welcome set -> the Soundcheck at Seven slot -> Arrange Sections -> skip the Bridge, last Chorus x2 -> length 2:40 -> total shows 2:40 for that row -> Rehearse -> the stage shows no Bridge and the Chorus repeat -> end -> the gig log row reads "Custom arrangement". Then rename a played section in the song's section band -> the slot reads "out of date".

## 12. Design directions (step 0)

Renders in the session scratchpad `p3-16/` (light and dark):

- **A - Popover** (`a-popover-*.png`): the existing slot popover grows a "Sections" area: compact list, checkbox, colour cap, label, xN stepper; length row and Reset in the footer. Smallest change, stays in place next to the row; tight for songs with 10+ sections.
- **B - Sheet with stage preview** (`b-sheet-*.png`): "Arrange Sections..." opens a sheet: the section list on the left, a miniature stage preview of the arranged song on the right that updates live. Most room and the only one that shows what the stage will show; a modal step away from the set.
- **C - Inline strip** (`c-inline-*.png`): the selected slot row expands in place into a Logic-style arrange strip: one block per section, width proportional to line count, kind-coloured, xN badge on the block, skipped blocks hatched; drag blocks to reorder, click to skip, ⌥-click or stepper to set plays. Matches the Timeline design C of the builder; densest, and the hardest to make fully keyboard and VoiceOver friendly.
- `stage-repeats-*.png`: the three options of question 1 side by side on the stage.

## 13. Steps

0. Spec (this file) and the renders. Done; answers in R123.
1. Core model, codec, schema 5 / show record 3, migrations, `ArrangementResolver`, fingerprint, `SectionNotes` anchor hook. Suites: `SlotArrangementTests`, `ArrangementResolverTests`.
2. Timing: `SetlistTiming` slot lengths, `SongLengthSource.slot`, missing-lengths rows, packer rules, `TimeItModel` target. Suites: `SetlistTimingTests`, `PackerTests`, `LengthEntryTests`.
3. Stage: `LayoutRequest.arrangement`, `SongPreparation`, unique ids, repeat display, header tag, auto-scroll duration, show item copy and `arrangementState`, pre-show row (R123). Suites: the layout suite, `ShowControllerTests`.
4. Builder UI in the picked direction: editor, entry points, slot mark, out-of-date editor, undo, accessibility. Suite: `ArrangementEditorTests`.
5. Gig log line. E2E `SegueArrangementE2ETests`; one `make quick`; one `make e2e-one` for the new class (and for `SegueSetBuilderE2ETests` only if its rows changed).

## 14. Files owned

- New: `SegueCore/Sources/Setlists/SlotArrangement.swift`, `ArrangementResolver.swift`; `SegueUI/Sources/SegueUI/Setlists/ArrangementEditor*.swift`, `AccessibilityID+Arrangement.swift`; the tests above; `UITests/SegueArrangementE2ETests.swift`.
- Additive hunks: `Setlists/Setlist.swift` (field, codec, version), `SetlistStore.swift` (migration step), `SetlistTiming.swift`, `Shows/ShowRecord.swift` (field, version), `ShowController.swift` (the copy line only; P3-15 owns the add paths), `LiveLayout/LayoutRequest.swift`, `SongPreparation.swift`, `Library/SectionNotes.swift` (public anchor hook; P3-13 owns the file), `SetAssistant/Packer.swift` (length per entry; P3-7 owns it), `SongCard/TimeItModel.swift` (target enum), `Setlists/SetEntryEditor.swift`, `SetEntriesList.swift` (slot mark, context menu), `MissingLengthsList.swift`, `Live/LiveSession+Viewport.swift`, `Live/StageChrome.swift` (tag), `GigLog/GigDetailView.swift` (second line), and the menu item through the `MenuShortcuts` owner.

## 15. Acceptance

A slot can skip, repeat and reorder sections for one gig; the `.cho` is byte-identical before and after; "Reset to Full Song" restores the plain slot; the stage plays the arrangement (or the full song, visibly, when it is out of date); the set total uses the slot length or counts the slot as unknown; the gig log says what was played; every change is one undo step; an older build opens a v5 setlist read-only; `make quick` green; the new E2E green.

## 16. Resolved questions (Ryan, 2026-10-19: R123)

1. Play counts on stage: **b**. An extra play is laid out as one more consecutive section and follows the song's "collapse repeats" live setting (collapsed: one more "Repeat chorus" line; expanded: printed again in full). No new stage badge.
2. Playing a section again elsewhere: **b**. "Play Again Later" duplicates a row, which can then be dragged anywhere.
3. Lines outside any section: **each block of loose lines is its own row** (tickable, skippable, movable, with a play count, like a section). It is anchored to the labelled section before it ("After Verse 2"); lines before the first section are the "Lead-in" row.
4. Song edits that shift sections: **b**. Label + occurrence plus a fingerprint of the first two lyric lines; a mismatch marks the arrangement out of date. New sections appear unticked under "New in the song" and do not mark it out of date.
5. Out of date: **a**. Builder mark, a pre-show checklist row with Edit, totals keep the slot length, a quiet "Full song" note in the stage header.
6. Schema: **a**. Every setlist saved by this build is written at version 5.
7. Editor: **B, the sheet** ("Arrange Sections"), opened from the slot popover's Arrangement row, the slot's context menu and a Setlist menu item (shortcut added to `MenuShortcuts.swift`, clash test green).

Also ruled: a running show copies arrangements exactly as it copies key and capo when the setlist is edited mid-show.
