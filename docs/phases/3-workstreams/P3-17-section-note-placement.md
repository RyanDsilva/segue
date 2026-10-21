# P3-17 - Section note placement: per-instance targeting and stable note IDs

Follow-up to P3-13 (new, 2026-10-20), from the Featurebase bug "Section Notes Exact Placement". In v0.5 scope as a phase 3 fix. Parent spec: `docs/phases/3-ai-entry-and-assistant.md` section 16.0.6 (read only; a sibling owns that file). Rulings: `docs/release/decisions.md` **R144** (this work), R87 (one section note concept with "Show on stage only"), R106 (chart notes stay `{comment}` in the `.cho`, stage-only notes stay sidecar cues), R122/R123 (per-slot arrangements anchor by label + occurrence + a first-two-lyric-lines fingerprint), R113 (test budget), R74 (closed analytics vocabulary); phase 2 interfaces `docs/phases/2-interfaces.md` (cue anchoring). Sibling spec: `P3-13-section-notes.md` (what exists today), `P3-16-slot-arrangements.md` (anchors and fingerprint).

**Do not start step 2 until Ryan has closed the Open Questions at the end.** Step 1 (stage note IDs) does not depend on them.

## Session rules

- `cat` and `ls` are aliased to eza and can hang: use `command cat` / `command ls` or the Read tool. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-".
- Sibling agents edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, stage only your own files by explicit path.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact and tell the orchestrator. Never push.
- Test budget (R113): per step only targeted in-process suites (`swift test --filter <Suite>`). New UI behaviour is covered by in-process SegueUI tests. At the end of the workstream ONE `make quick` plus ONE `make e2e-one` for `SegueSectionNotesE2ETests` (the only UI test class this spec changes). No `make gate` (the orchestrator runs one per wave), no `make check`, no E2E retry loops, no duplicate builds in scratch worktrees.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency.

## 1. The problem

Ryan reported two things under "Section Notes Exact Placement":

1. **A crash** when adding notes to several sections at once. Fixed in commit dce53bc (pending addition rows keyed by a UUID instead of position) with `testNotesOnSeveralSectionsAtOnce`. Not part of this spec, except that the same class of bug (rows and edits keyed by a position that shifts) still exists for saved notes (section 3).
2. **No way to say which instance a note is on.** A song with Chorus, Verse 2, Chorus, `{chorus}` has one "Chorus" group in the sheet with one "Add Note" button. A new chart note always lands in the first written-out chorus; a new stage note always pins to every chorus. Only after saving can a stage note be re-pinned with the "Every time / Only #n" picker; a chart note cannot be moved to another instance at all (its row shows a static "In #n"). And a second note on the same section is inserted **above** the first, because `SectionNotes+Edits.swift:104` calls `insertComment(text, at: header)`, which inserts the line directly after the section header.

R144 rules: per-instance targeting when adding (Chorus #1, #2, Every time), defaulting to the instance whose band context menu opened the sheet; stable note IDs; `{chorus}` repeats are shown as targets but explained (only a stage note can go there); a second note appends after existing notes.

## 2. Current state (read before changing anything)

Core (`Packages/SegueCore/Sources/Library/`):

- `Sidecar.swift`: `Sidecar.currentSchemaVersion = 3` (3 = phase 2 `cues` and `live`). `SongCue { section: String, occurrence: Int?, text: String }`: label matched case-insensitively after trimming, `occurrence` 1-based, nil = every occurrence. No identity.
- `SidecarCodec.swift`: `SchemaMigrator` with forward steps `0 -> 1 -> 2 -> 3`; an older file is migrated in memory and written back at the current version on the next save; a newer file opens read-only (`ReadOnlyReason.newerSchema`) and is never rewritten.
- `SectionNotes.swift`: `SectionNote { source: .chart(BlockPath) | .stage(Int), text, occurrence }`, and `id == source`. So a stage note's identity is its **index in `Sidecar.cues`** and a chart note's is the **`BlockPath` of its `{comment}` line**; both shift when anything before them is added or removed. `SectionNoteGroup` is one group per label (`"section:<key>"`), per loose run (`"loose:<i>"`) or per orphaned label. `Anchors` computes the label key and 1-based occurrence of every `RenderSection`; a `{chorus}` repeat counts as an occurrence of its label. `SectionNotes.pin(_:to:)` is the phase 2 interface live layout uses.
- `SectionNotes+Edits.swift`: `SectionNotePlanner` turns a `SectionNoteEdit` into a `SectionNoteChange` (one `SourceChange` for the `.cho` plus the full new cue list). `add` appends a cue with `occurrence: nil`, or inserts a `{comment}` at `group.chartTarget` (the header of the first written-out section with that label). `setStageOnly(false)` inserts at the first section the cue pins to (a repeat sends it to the chorus it repeats).
- `Editing/EditPlanner+Comments.swift`: `insertComment(_:at:)` inserts after the header line when `path` is a section header, else before the line at `path`.
- `LiveLayout/SongPreparation.swift:15-27`: cues pin to the song's own sections (song-relative label + occurrence) before an arrangement reorders them; a cue shows on its section's first play only; a cue on a skipped section is not played; unmatched cues go to the notes block.
- `SlotArrangement.swift:284-308`: `SlotArrangement.fingerprint(of:)` hashes the first two normalised lyric lines (chords and **comments excluded**), FNV-1a 32-bit hex; a `{chorus}` repeat's fingerprint is `"repeat"`.

UI (`Packages/SegueUI/Sources/SegueUI/`):

- `Library/SectionNotesSheet.swift`: the "Section Notes" sheet (560 x 540). Groups in song order; per group one "Add Note" button; per note a text field, the "Show on stage only" checkbox, a placement control (`Menu "Move to"` for orphaned cues, `Picker "Every time / Only #n"` for stage notes on a repeated label, static "In #n" for chart notes) and delete. `drafts` are keyed by `SectionNote.Source`. Edits are queued through `run(_:)`, each awaiting the previous, but **the edit value is captured when the user acts**, so a queued `.delete(.stage(2))` planned after a queued delete of `.stage(0)` hits the wrong cue (the stale-position bug class).
- `Editor/SongEditorViewModel+SectionNotes.swift`: `SectionNotesRequest { group }`; `showSectionNotes(forSectionAt:)` maps a header path to its group. Callers: the band badge (`VisualEditorController+SectionActions.swift:37`), the band context menu "Section Notes..." (`:271`) and the VoiceOver action (`VisualEditorController+SectionNotes.swift:40`). All three know the exact band (header path), so they know the instance; today that is thrown away.
- `LibraryViewModel.editSectionNotes(id:_:)`: the library host (no band, no instance context).

Tests: `SegueCoreTests/SectionNoteTests.swift`, `SegueThemeTests/SectionNotesUITests.swift`, `UITests/SegueSectionNotesE2ETests.swift` (`testStageNoteShowsOnStageThenBecomesAChartNote`, `testNotesOnSeveralSectionsAtOnce`).

## 3. Stable IDs for stage notes (step 1, no open questions)

### 3.1 Schema

Sidecar schema **3 -> 4**. `SongCue` gains:

```swift
public struct SongCue: Sendable, Hashable, Codable {
    /// Stable identity (R144), unique within the song. Never reused, never shown.
    public var id: CueID          // ULID, encoded as its 26-char string
    public var section: String
    public var occurrence: Int?
    public var text: String
}
```

On disk: `{"id": "01JB...", "section": "Chorus", "occurrence": 2, "text": "Watch Ravi"}`. Open question 5 adds an optional `fp` (section fingerprint) field; if Ryan takes it, it lands in the same schema bump, never a second one.

### 3.2 Migration (`SidecarCodec` step `3:`)

- Each cue without an `id` gets a **deterministic** ID: a ULID whose 48-bit time part is the sidecar's `createdAt` (else the Unix epoch) and whose 80-bit random part is the first 80 bits of a stable hash of `(song id, cue index, section, occurrence, text)`. Deterministic so that (a) re-reading an unsaved migrated sidecar yields the same IDs (the store reloads on file events, and a fresh UUID per read would make every reload look like new notes to the sheet), and (b) two devices migrating the same file (phase 7 iOS reads the same folder, R134) agree on the IDs without coordination.
- New cues created after migration get a fresh `ULID()` (`Support/ULID.swift`).
- Decode repairs hand-edited files deterministically: a missing or unparseable `id` gets the derived ID above; a duplicate `id` keeps the first and re-derives the later ones. A repaired sidecar is written back on the next save like any migration.
- An older build (schema 3) opening a v4 sidecar gets `.newerSchema(found: 4, supported: 3)` and opens the song read-only, so it can never silently drop the IDs. This is the same trade as setlist schema 5 (R123 question 6 = a). Every sidecar this build saves is written at 4.
- Coordinate the bump with any other v0.5 workstream that touches `Sidecar` (N1 Singer view, N4 Medleys): one bump per release if they land together; whoever lands second rebases onto 4 and adds 5 only if the shape changes again. Ask the orchestrator.

### 3.3 Note identity in the model

- `SectionNote.id` becomes `SectionNoteID`: `.stage(CueID)` or `.chart(ChartNoteID)` (section 5 defines `ChartNoteID`; under the recommended option it is derived, not stored). `SectionNote.Source` stays as an internal resolution detail.
- Every `SectionNoteEdit` case takes a `SectionNoteID`, never a `BlockPath` or an index. `SectionNotePlanner` resolves the ID against the snapshot and cues it is given **at plan time**; an ID that no longer resolves throws `.notFound` (the sheet then reloads and shows "That note is no longer in the song.", as today). This fixes the stale-position bug class for queued edits.
- `SectionNoteChange` gains `resultID: SectionNoteID?`: the note's ID after the edit (a new note's ID; a toggled note's new ID; a chart note whose text changed, when its ID is derived from text). The sheet re-keys its draft and focus from `resultID`, so typing focus never jumps to another row.
- `SongPreparation` and `SectionNotes.pin` keep matching cues by label + occurrence; the ID is not used on stage.

## 4. Per-instance targeting (step 2)

### 4.1 Placement

A **placement** names where a note shows:

```swift
public enum NotePlacement: Sendable, Hashable {
    case everyTime                 // every occurrence of the label
    case instance(Int)             // one occurrence, 1-based, repeats included
}
```

Instances are numbered as `Anchors` numbers them today: written-out sections and `{chorus}` repeats share one 1-based sequence per label. So "Chorus #3" can be a `{chorus}` line.

What each kind of note can do with each placement:

| Placement | Stage note | Chart note |
|---|---|---|
| Every time | cue with `occurrence: nil` (today's default) | open question 2 |
| #n, written out | cue with `occurrence: n` | `{comment}` line inside that section's block, appended (4.4) |
| #n, a `{chorus}` repeat | cue with `occurrence: n` | not possible: explained, offered stage-only (4.3) |

A label that occurs once shows no picker (placement is implicit).

### 4.2 Sheet changes

- The group stays one per label (the user still thinks "notes on the chorus"), titled as today with the caption "3 times". Inside it, notes are ordered by placement: Every time first, then #1, #2, ..., and within one placement in their order in the file (chart) then sidecar order (stage).
- Every note row of a repeated label gets **one placement picker**, for chart and stage notes alike, replacing today's stage-only `Picker` and the static "In #n". Items: "Every time", then one per instance: "Chorus #1", "Chorus #2", "Chorus #3 (repeat)". Picking moves the note (new edit `.place(SectionNoteID, NotePlacement)`, one undo step, action name "Move Note"); for a chart note that means removing its line and appending it in the target section (4.4).
- The pending addition row (the "Add Note" row) gets the same picker next to the "Show on stage only" checkbox.
- **Default placement for a new note:**
  - Opened from the section band (badge, context menu, VoiceOver action): the instance of that band. `SectionNotesRequest` gains `placement: NotePlacement?`; `showSectionNotes(forSectionAt:)` computes it from the header path via `Anchors`. For a band of a label that occurs once, no placement.
  - Opened from the library or the song card (no band): open question 3.
- **Band context menu:** keep "Section Notes..." and add **"Add Note to Chorus #2..."** (title uses the band's label and, when the label repeats, its instance), which opens the sheet scrolled to the group with a new addition row already open, focused, and preset to that instance. Open question 4 asks whether this extra item is wanted.
- Identifiers: `segue.sectionNotes.note.placement` (picker on a saved note), `segue.sectionNotes.addition.placement` (picker on a new note), `segue.sectionNotes.repeatHint` (4.3). Pickers carry accessibility labels "Shows on".

### 4.3 `{chorus}` repeats

R144: repeats are offered as targets, and picking one for a chart note explains why it cannot be a chart note.

- In the picker a repeat reads "Chorus #3 (repeat)".
- New note, "Show on stage only" off, placement set to a repeat: the checkbox turns on and disables, and an inline hint appears under the row (`segue.sectionNotes.repeatHint`, callout, muted): "Chorus #3 is a `{chorus}` repeat, so it has no lines of its own. A note here shows on stage only. To have it in the chart on every chorus, put it in Chorus #1." The last sentence is a button that switches the placement to the written-out chorus the repeat repeats (`repeatRoot`, as `chartTarget(for:)` already computes) and turns the checkbox back off.
- Existing chart note moved to a repeat with the picker: the same hint, and the move converts it to a stage note on that instance in one undo step ("Move Note").
- Existing stage note on a repeat, "Show on stage only" turned off: today it silently becomes a chart note in the chorus the repeat repeats (so it then shows on every play of that chorus). Keep that behaviour but show the same hint first as a confirmation: "Chorus #3 is a repeat. In the chart this note goes in Chorus #1 and shows every time Chorus #1 is played or repeated." with Move / Cancel. The move changes its placement to #1 (or Every time, per open question 2).
- Stage rendering is unchanged: a cue on a repeat pins to that repeat's render section, whether repeats are collapsed into a reference line or expanded (add a test to prove the collapsed case still shows the callout).

### 4.4 Append order

- A new chart note goes **after the existing notes of that section**: after the last line of the run of `{comment}` lines (and blank lines between them) that directly follows the section header. If there is no such run, directly after the header (today's behaviour). A `{comment}` further down inside the section, between lyric lines, is a positional note on that spot and does not move the insertion point.
- Implementation: `EditPlanner.insertComment` keeps its contract; the planner computes the target path itself (the path of the last comment in the leading run, inserting after it) via a new `EditOperation.insertCommentAfter(String, BlockPath)` or an `insertComment(_:at:position:)` parameter. Do not change what `insertComment` at a header means for other callers (the slash menu's Note item uses it; check the call sites and ask if any expects "first").
- The same rule applies to "Show on stage only" turned off (stage -> chart) and to a chart note moved between instances.
- A new stage note is appended to the end of `Sidecar.cues` (already true); with 4.2's ordering it lists after the notes already on that placement.

## 5. Chart notes: does a `{comment}` line get a stable identity?

This is the hard part and Ryan's call (open question 1). Constraints:

- **Files stay valid, portable ChordPro** (vision, R106). Other apps must open the `.cho` and print the notes exactly as the user wrote them.
- **The user may edit the `.cho` anywhere**: Segue's Text mode, another editor, another ChordPro app, a phone (phase 7 reads the same folder). Any identity scheme must survive that or degrade honestly.
- **What needs a chart note ID?** Today: only the sheet (rows, drafts, focus, queued edits) and the planner (resolve the target of an edit). No stored artifact refers to a chart note: arrangements reference sections, the gig log references songs, analytics carries no IDs. A persistent chart note ID would only pay off for a future feature that refers to a specific chart note from outside the `.cho` (none is planned).

### Option I - Derived IDs (chart notes stay positional; only stage notes are persisted with IDs)

`ChartNoteID` is computed on every read, never stored: `(label key, occurrence of the owning section, ordinal among notes with the same text in that section, text hash)`, or `(loose run index, ordinal, text hash)` for loose lines.

- Stable across any edit that does not touch the note's own section label, occurrence or text: adding notes or lines elsewhere, adding notes before it in the same section (ordinal is among same-text notes only), retiming, chord edits, transposition.
- Changes when its own text changes, its section is relabelled, or a section of the same label is inserted earlier (occurrence shifts). The planner returns the new ID in `resultID`, so the sheet's own edits never lose the row; an outside edit just reads as "a different note", which is honest.
- The `.cho` is untouched: zero interop risk, nothing to reconcile, nothing to migrate, no extra file noise.
- Cost: chart notes have no identity across sessions or devices (nothing needs one today), and two identical notes in one section are distinguished only by order.

### Option II - Sidecar map keyed by fingerprint

The sidecar gains `chartNotes: [{id, section, occurrence, fp, textHash, ordinal}]`: Segue's record of which `{comment}` line is which note. On read, each `{comment}` line is matched to an entry cheapest-first: exact (section, occurrence, text hash, ordinal), then same text in a section with the same fingerprint (`SlotArrangement.fingerprint`, survives an earlier section being inserted), else a new entry. Every planner change rewrites the map in the same `SectionNoteChange`.

- Persistent identity across sessions and devices, and across occurrence shifts when the section's lyrics match.
- The `.cho` stays clean and portable.
- Cost: two stores that must agree. Every outside edit (Text mode, another app, another device) creates drift that must be reconciled on read; entries whose line is gone need garbage collection; the sheet and planner need a reconcile step before every edit; the sidecar schema grows a field that must be maintained forever; more tests. All to provide identity nothing yet consumes.

### Option III - An ID written into the `.cho`

Three spellings, all with the same core trade (identity travels with the line, but the file carries Segue-specific text):

- **IIIa. Attribute on the comment directive**, e.g. `{comment id="n7": Bring it down}` or `{comment: id="n7" Bring it down}`. ChordPro 6 defines `key="value"` attributes for some directives (`{image: src=... scale=...}`, `{start_of_verse label="Verse 1"}`) but defines **none for `comment`**: a comment's value is its text (chordpro.org, ChordPro Directives). Other ChordPro apps would print `id="n7"` as part of the note or fail to recognise the directive. Breaks portability; **not recommended under any answer**.
- **IIIb. A ChordPro file comment on the line above**: `# segue-note 01JB...` then `{comment: Bring it down}`. The ChordPro spec says lines starting with `#` are ignored by processors, so other apps print nothing extra, and Segue's parser already keeps `#` lines as `FileComment` blocks with their trivia (round-trips). Costs: one marker line per chart note visible in Text mode and in other editors; other editors that re-save may drop or reorder `#` lines; a user moving the `{comment}` in Text mode separates it from its marker, so Segue still needs Option II-style reconciliation as a fallback.
- **IIIc. A custom directive**: `{x_segue_note: 01JB...}` before the comment. The spec says `x_` directives must be ignored without warnings, so it is portable in compliant apps; noisier than IIIb, same separation and reconcile problems, and not every non-reference app honours the `x_` rule.

### Comparison

| | I Derived | II Sidecar map | IIIb `#` marker |
|---|---|---|---|
| `.cho` unchanged | yes | yes | no (one line per note) |
| Other ChordPro apps print the same | yes | yes | yes (if they honour `#`) |
| Identity across sessions and devices | no | yes (best effort) | yes until a line is moved |
| Survives outside edits | re-derives, honest | reconcile, can mismatch | marker can detach |
| New schema / migration | none | sidecar field | none, but every existing note needs a marker |
| Fixes the stale-position bugs | yes | yes | yes |
| Size of work | small | large | medium |

**Recommendation: Option I.** Stage notes get persisted IDs (section 3); chart notes keep positional identity with derived IDs resolved at plan time. It fixes every bug the report exposed, keeps files exactly as portable as today, and needs no reconciliation. Option II is the upgrade path if a later feature (for example notes referenced from a setlist or shared to a partner device) ever needs persistent chart note identity; nothing in Option I blocks it.

## 6. Arrangements (R122/R123)

- Arrangements reference sections by label + occurrence + fingerprint; notes reference sections by label + occurrence. Per-instance placement uses the **same** `Anchors` numbering, so "Chorus #2" in the notes sheet and "Chorus 2" in Arrange Sections are always the same section. Add one shared test that asserts both resolve the same render section for a song with written-out choruses and a `{chorus}` repeat.
- Adding, moving or deleting a chart note never marks an arrangement out of date: the fingerprint excludes comments (assert it in a test). Relabelling a section is the only note-adjacent edit that does, as today.
- On stage with an arrangement (`SongPreparation`): a note on instance #n shows on that section's first play only and not at all if the slot skips it; "Every time" notes show on the first play of every occurrence. Unchanged behaviour, now user-reachable per instance; cover with one `ArrangementResolverTests`-style case.
- If Ryan takes open question 5 (stage notes store the section fingerprint), re-anchoring uses `SlotArrangement.fingerprint(of:)` exactly as R123 defines it, so the two features can never disagree about whether a section "moved".

## 7. Analytics (non-PII, R74 closed vocabulary)

New row in `AnalyticsEvent` and in `docs/release/specs/WS3-services.md` section 5 (plus the consent sheet's "What's sent" list, which reads the same table):

- **`Segue.Notes.edited`** (daily per action, kind and placement), parameters:
  - `segue.action`: `add` | `move` | `toggle` | `delete`
  - `segue.kind`: `chart` | `stage` (after the edit)
  - `segue.placement`: `single` (label occurs once) | `every` | `instance` | `repeat` (an instance that is a `{chorus}` repeat)
  - `segue.entry`: `bandMenu` | `badge` | `sheet` | `slash` | `library`
  - `segue.repeatHint`: Bool (the 4.3 hint was shown for this edit)
- `ErrorCode` gains `sectionNoteGone` for a `.notFound` surfaced to the user (counts stale-edit failures after the ID change; should be near zero).
- `Sidecar` migration: no event (one-off, silent).

All values are enums or Bools; no note text, labels, song titles or IDs are expressible. Questions these answer: do people use per-instance notes at all; how often the repeat limitation bites (`repeat` + `repeatHint`); which entry point is used (whether the band menu item earns its place).

## 8. Steps

1. **Stage note IDs** (section 3): `SongCue.id`, schema 4, migration and repair, `SectionNoteID`, edits by ID resolved at plan time, `resultID`, sheet keyed by ID. Suites: `SectionNoteTests`, `SidecarCodecTests` (or the existing sidecar suite).
2. **Chart note identity** per open question 1 (Option I: `ChartNoteID` derivation). Suite: `SectionNoteTests`.
3. **Placement model and planner**: `NotePlacement`, `.add` with placement, `.place`, append order (4.4), repeat rules (4.3). Suite: `SectionNoteTests`.
4. **Sheet and band**: pickers, defaults, `SectionNotesRequest.placement`, the "Add Note to ..." menu item (if kept), repeat hint, ordering. Suite: `SectionNotesUITests`.
5. **Analytics**: the new row and error code, WS3 table entry. Suite: the analytics vocabulary tests.
6. **E2E and wrap-up**: extend `SegueSectionNotesE2ETests` (section 9), one `make quick`, one `make e2e-one`.

## 9. Test plan

In-process first (Core integration on temp-library songs through the real `LibraryStore`, as `SectionNoteTests` does):

- Migration: a v3 sidecar with three cues reads with three distinct IDs; reading it twice before saving yields the same IDs; saving writes v4 with those IDs; a v5 sidecar opens read-only; duplicate and missing IDs are repaired deterministically.
- IDs: queue delete of the first cue and delete of the third in one run: the right two are deleted (the stale-position regression). Edit text of a chart note while a note is added above it in the same section: the right line changes. `resultID` after add, toggle and text edit points at the note.
- Placement on a song with Chorus (#1), Verse, Chorus (#2), `{chorus}` (#3): add chart note to #2 lands inside the second chorus block; add stage note to #3 pins `occurrence: 3`; Every time stage note pins nil; chart note on #3 is refused by the planner with `.noAnchor` (the UI never sends it); moving a chart note #1 -> #2 moves its line and keeps lyrics byte-identical; one undo step each.
- Append order: two adds to the same section read back in add order; an add to a section with a mid-section `{comment}` lands after the leading run, not after the mid-section line; stage -> chart toggle appends.
- Arrangements: notes and Arrange Sections resolve "Chorus #2" to the same render section; adding a chart note leaves every arrangement fingerprint unchanged; a note on a skipped instance is not played.
- Live layout: a cue on a `{chorus}` repeat shows its callout with collapse repeats on and off.
- UI (`SectionNotesUITests`, in-process): picker items and default from a band request; the repeat hint appears and its button switches placement; group ordering by placement; drafts survive a reload keyed by ID.
- Interop: a song whose notes were all added by Segue, re-parsed by the ChordPro parser, contains only standard `{comment}` lines (no attributes, no markers) under Option I.

E2E (at most one new flow, in the existing class `SegueSectionNotesE2ETests`): open a Welcome song with a repeated chorus in the visual editor, use the band context menu of the second chorus to add a note, confirm the picker defaults to "Chorus #2", save, add a second note to the same chorus, and assert in Text mode that both `{comment}` lines sit inside the second chorus in add order. No E2E for repeats, migration or analytics (in-process covers them).

## 10. Files owned

`SegueCore/Sources/Library/Sidecar.swift` (`SongCue`, schema version), `SidecarCodec.swift` (step 3), `SectionNotes.swift`, `SectionNotes+Edits.swift`, `Editing/EditPlanner+Comments.swift` and `DocumentEditor.swift` (only the append operation), `Services/AnalyticsEvent.swift` (the new row), `SegueUI/Library/SectionNotesSheet.swift`, `Editor/SongEditorViewModel+SectionNotes.swift`, `Editor/VisualEditorController+SectionActions.swift` (the menu item only), `Editor/VisualEditorController+SectionNotes.swift`, `LibraryViewModel` section notes entry, `AccessibilityID+SectionNotes.swift`, the tests above, `docs/release/specs/WS3-services.md` section 5 (one row). Ask before touching `SongPreparation.swift` (it should not need changes).

## 11. Acceptance

- A note can be added to Chorus #1, #2, a repeat (stage only, explained) or every chorus, from the band menu with the right default; existing notes can be moved between instances.
- A second note on a section reads back after the first, in the file and in the sheet.
- No edit ever lands on the wrong note, including queued edits.
- Songs saved by this build stay standard ChordPro; existing sidecars migrate with stable IDs; older builds open v4 sidecars read-only.
- Arrangements are never marked out of date by note edits.
- `make quick` green; `make e2e-one` for `SegueSectionNotesE2ETests` green; the wave gate green.

## 12. Open Questions (for Ryan; recommendations only, not decided)

1. **Chart note identity.** (I) Derived IDs: chart notes stay positional `{comment}` lines, only stage notes get persisted IDs; (II) a sidecar map keyed by section fingerprint and text, giving chart notes persistent IDs Segue reconciles on read; (III) an ID in the `.cho`, as a `# segue-note <id>` file comment above the note (IIIb) or an `{x_segue_note}` directive (IIIc); attributes on `{comment}` (IIIa) are ruled out because ChordPro defines none and other apps would print them. **Recommend I**: it fixes every reported bug, leaves files untouched, and nothing yet needs a chart note to be identifiable from outside the file; II stays the upgrade path.
2. **"Every time" for a chart note** on a label with several written-out sections. (a) Write one `{comment}` copy into each written-out instance, shown in the sheet as one note "in #1, #2" (linked by identical text and position; editing the row edits all copies; a copy edited elsewhere just becomes its own note); (b) "Every time" is a stage-only placement: picking it for a chart note turns on "Show on stage only", with a hint; (c) "Every time" for a chart note means the first written-out instance (today's behaviour; repeats of it show it, other written-out copies do not). **Recommend a**: it is the only answer where "Every time" means what it says in the chart, PDFs and other apps, and it needs no identity beyond Option I.
3. **Default placement with no band context** (sheet opened from the library or song card, or "Add Note" on a group). (a) "Every time"; (b) #1; (c) no default: the picker starts empty and Add asks for a choice. **Recommend a** for stage notes (matches today's cue default) and, if question 2 is a, for chart notes too; if question 2 is b or c, #1 for chart notes.
4. **Band context menu item.** (a) Add "Add Note to Chorus #2..." next to "Section Notes..." (opens the sheet with a new note row preset to that instance and focused); (b) keep only "Section Notes...", which scrolls to the group and presets the next Add to that instance. **Recommend a**: one step instead of two for the most common action, and it makes the instance default visible in the menu title.
5. **Stage notes and section shifts.** When a verse or chorus is inserted earlier in the song, "Chorus #2" silently becomes a different chorus for an existing stage note (today and after this spec). (a) Store the section fingerprint (`fp`) on each placed cue in the same schema 4 bump; on read, if label + occurrence no longer matches the fingerprint and exactly one same-label instance does, re-anchor to it; otherwise keep the occurrence and show a quiet "Check placement" mark on the note in the sheet; (b) leave as is (label + occurrence only). **Recommend a**: it reuses R123's fingerprint so notes and arrangements agree, and it is cheap only if done in the same schema bump.
6. **Sheet grouping.** (a) One group per label with notes ordered by placement and a placement picker per note (this spec); (b) one sub-group per instance nested under the label ("Chorus" > "#1", "#2", "#3 (repeat)", "Every time"), each with its own Add. **Recommend a** for v0.5 (smaller change to a shipped sheet, and most songs have few notes); revisit b if analytics shows heavy per-instance use.
