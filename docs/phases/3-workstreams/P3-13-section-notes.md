# P3-13 - Section notes: `{comment}` and live cues merged

Wave 3 (new, 2026-10-19; after P3-10 and P3-11). Parent spec: `docs/phases/3-ai-entry-and-assistant.md` (read sections 16.0.6, 14, and 16.1 question 23). Rulings: `docs/release/decisions.md` R87 (merge `{comment}` and live cues into one section note with a "Show on stage only" toggle), R80/R81/R82 (song card, slash menu Note item, section band badge), R17 (autosave), R39, R79; phase 2 interfaces `docs/phases/2-interfaces.md` (cue anchoring: section label, case-insensitive, optional 1-based occurrence; a cue whose label no longer exists shows in the notes block).

## Session rules (apply to every P3 workstream)

- `cat` is aliased to eza and can hang: use `command cat` or the Read tool. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-".
- Sibling workstreams edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, and stage only your own files.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget: per step only targeted `swift test --filter <Suite>`; `make quick` + `make gate` once at the end of the workstream; never `make check` (phase gate only, P3-9). Real FM/MLX calls never run inside `make check` or `make gate`.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency.

## Before you start

**Question 23 (storage) blocks step 1** until Ryan rules. Recommendation a: chart notes stay `{comment}` lines in the `.cho` (portable, printed, shown everywhere), stage-only notes stay sidecar `cues` (`SongCue`), and the toggle moves a note between them in one undoable edit. The steps below assume a; if Ryan rules otherwise, ask the orchestrator to revise them.

## Goal

The user thinks in one concept, "a note on this section", and decides only whether it shows on stage only. Existing `{comment}` lines and existing cues both appear as section notes with no data loss.

## Existing code

`SegueCore/Library/Sidecar.swift` (`cues: [SongCue]`, `SongCue` ~61-75), `SidecarCodec.swift`, `LibraryStore+Phase2.swift`, `ChordPro` parser (`{comment}`, `{c}`), `Editing/` (`RenderSectionBuilder`, `SourceMap`), `LiveLayout/` (`LayoutPlan`, `SectionLayout`, cue callouts), `SegueUI/Library/NotesEditorSheet.swift` ("Add Notes & Cues..."), `Library/SongMetadataViews.swift` / `SongCard/` (P3-10), `Library/LibraryViewModel+Metadata.swift`, `Live/StageSongBody.swift`, `Live/LiveSession+Viewport.swift`, the section band badge slot (P3-11), the slash menu's Note item (P3-10).

## Steps

1. **Model:** a `SectionNote` view model in Core that reads both sources for a song: `{comment}` lines attributed to the section they sit in (or "before the first section"), and sidecar cues by label + occurrence; each note has text, anchor, and `stageOnly` (true for cues). Writes: edit text in place; toggle `stageOnly` moves the note (remove the `{comment}` line and add a cue, or the reverse, inserting the `{comment}` as the first line inside the section) as one undoable edit; delete; add. Orphaned cues (label no longer exists) stay visible in the notes list, as phase 2 does.
2. **UI:** "Add Notes & Cues..." becomes **"Section Notes..."**: one list grouped by section, each note with its text and a "Show on stage only" toggle; add per section. The section band (P3-11) shows a badge with the count on each band and opens the sheet on that section. The slash menu's Note item (P3-10) creates a chart note in the current section. Identifiers `segue.sectionNotes.*`.
3. **Rendering:** chart notes render where `{comment}` renders today (editor preview, export, stage); stage-only notes render only in live mode as today's cue callouts. Nothing changes on stage visually except that both come from one model.
4. **Converter interplay:** the paste converter writes unknown lines as `{comment}` (R101); they appear as chart notes with no special handling.

## Tests

Core integration on temp-library songs with both `{comment}` lines and cues: the merged list is complete and ordered; toggling moves the note between `.cho` and sidecar and back with byte-identical lyrics and one undo step; orphaned cues listed; reload via the real store. In-process UI test for the sheet. Suites: `SectionNoteTests`. E2E `SegueSectionNotesE2ETests`: add a stage-only note on a Welcome song's chorus, start a rehearsal, see the callout; toggle it off "stage only", Text mode shows `{comment}`.

## Files owned

New `SectionNote` files in `SegueCore/Sources/Library/` (and `Editing/` if anchoring needs it), `Library/NotesEditorSheet.swift` (renamed or replaced), the notes entry in the song card (ask P3-10's owner if the card file is still in flight), the badge contents in the section band (P3-11's slot), `LiveLayout` cue sourcing, `UITests/SegueSectionNotesE2ETests.swift`, the tests above.

## Acceptance

One "Section Notes" surface covers both former mechanisms; the stage-only toggle works both ways with no data loss; existing songs show all their comments and cues as notes; `make quick` + `make gate` green.
