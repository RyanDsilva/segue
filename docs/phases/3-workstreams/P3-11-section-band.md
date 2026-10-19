# P3-11 - Section band in the visual editor and section operations

Wave 2 (new, 2026-10-19). Parent spec: `docs/phases/3-ai-entry-and-assistant.md` (read sections 16.0, 16.0.3, 14). Rulings: `docs/release/decisions.md` R82 (Logic-style section band: select lines, V / C / B / I keys or chips, drag marker edges), R81 (the slash menu's wrap reuses your operation), R17 (autosave), R39 (design directions), R79 (accessibility walk); `docs/decisions.md` Language section (lyrics never altered).

## Session rules (apply to every P3 workstream)

- `cat` is aliased to eza and can hang: use `command cat` or the Read tool. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-".
- Sibling workstreams edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, and stage only your own files.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget: per step only targeted `swift test --filter <Suite>`; `make quick` + `make gate` once at the end of the workstream; never `make check` (phase gate only, P3-9). Real FM/MLX calls never run inside `make check` or `make gate`.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency.

## Goal

Sections become visual objects: in the visual editor every section is a band in the left gutter that can be created around selected lines with one key, relabelled, resized by dragging its edge, split, merged or removed, always producing standard ChordPro with no lyric or chord change.

## Existing code

`SegueCore/Sources/Editing/` (`DocumentEditor.swift` with `EditOperation` incl. `.setSectionLabel`, `EditPlanner.swift`, `SourceMap.swift`, `RenderSectionBuilder.swift`, `TextEdit.swift`), `SegueUI/Editor/VisualEditorController.swift` (`.setSectionLabel` use ~357), `VisualEditorController+Gestures.swift`, `+Painting.swift`, `+Geometry.swift`, `SongEditorViewModel+Edits.swift`, `CanvasViews.swift`. The visual editor can relabel a section today but cannot create one.

## Steps

0. **Design directions (R39 style):** 2-3 renders of the band (gutter width, colour per kind in light and dark, label placement, the selection + chip bar, the drag handle, a note badge slot for P3-13). Ryan picks before step 2.
1. **Section operations in Core (land first; P3-10's slash menu reuses wrap):** new `EditOperation` cases planned by `EditPlanner`: `wrapSection(lines:kind:label:)` (inserts `{start_of_<kind>: <label>}` / `{end_of_<kind>}`; refuses to cross an existing section boundary with a typed error), `setSectionKind(section:kind:label:)`, `moveSectionEdge(section:edge:toLine:)` (clamped at neighbours), `unwrapSection(section:)` (keeps the lines), `splitSection(section:atLine:)`, `mergeSections(first:second:)` (same kind only, else asks for the kind). Labels number automatically ("Verse 2" when "Verse 1" exists) through one shared helper P3-10 also uses. Every operation is one undo step, preserves the source text outside the directive lines byte for byte, and round-trips through the parser.
2. **Band painting:** a gutter band per section (colour per kind, label at its top), an empty slot for lines outside any section; hit-testing in `+Geometry`.
3. **Create and relabel:** select lines (drag in the gutter, or a text selection mapped to whole lines), then **V / C / B / I** (Verse, Chorus, Bridge, Intro) or a click on the floating chip bar (also Outro, Tab, Custom...) creates a section, or relabels when the selection is exactly one section. Keys act only while the visual editor has a line selection, never in Text mode and never while typing in a lyric.
4. **Resize:** drag a band's top or bottom edge; snaps to line boundaries, clamped at the neighbouring section; live preview, one undo step on release.
5. **Context menu:** Rename, Change Kind, Unwrap, Split Here, Merge with Next. Keyboard and VoiceOver: each band is an accessibility element with actions for these (no drag needed); identifiers `segue.editor.sectionBand.*`.
6. **Note badge slot:** leave a badge position on each band that P3-13 fills (no notes logic here).

## Tests

Core integration over real documents (Welcome songs and paste fixtures): each operation round-trips through the parser with zero lyric and chord change, refuses overlapping wraps, numbers labels, and undoes in one step. Unit tests only for edge clamping. In-process UI test for selection -> key -> section. Suites: `SectionOperationTests`, `SectionBandTests`. E2E `SegueSectionBandE2ETests` (fresh library): select four lines of a Welcome song in the visual editor, press C, Text mode shows a chorus section around exactly those lines; drag its bottom edge down one line.

## Files owned

New `EditOperation` cases and their planner code in `SegueCore/Sources/Editing/` (additive; `DocumentEditor.swift` and `EditPlanner.swift` edits limited to the new cases), `SegueUI/Editor/VisualEditorController*.swift`, `SongEditorViewModel+Edits.swift` (new cases only), `UITests/SegueSectionBandE2ETests.swift`, the tests above.

## Acceptance

A section can be created, relabelled, resized, split, merged and removed in the visual editor without typing a directive; every result is valid ChordPro with zero lyric or chord change and one undo step per gesture; `make quick` + `make gate` green.
