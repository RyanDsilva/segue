# P3-10 - Song card, `{` completion fixes and the slash menu

Wave 2 (new, 2026-10-19). Parent spec: `docs/phases/3-ai-entry-and-assistant.md` (read sections 16.0, 16.0.1, 16.0.2, 14, and 16.1 questions 27-28). Rulings: `docs/release/decisions.md` R80 (song card, set essentials = key + tempo), R81 (slash menu + `{` completion fixes + key validation), R83 (Start blank opens the card), R101 (with a capo, `{key}` is the shapes key; detected keys are suggestions), R17 (autosave), R39 (design directions), R79 (accessibility walk before claims). Background: the 2026-10-18 brainstorm audit summarised in spec 16.0 (its mockup `mock-b` is not in the repo; the orchestrator can supply it).

## Session rules (apply to every P3 workstream)

- `cat` is aliased to eza and can hang: use `command cat` or the Read tool. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-".
- Sibling workstreams edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, and stage only your own files.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget (R113): per step only targeted in-process suites (`swift test --filter <Suite>`); new UI behaviour gets in-process SegueUI tests, and a new XCUITest only for a flow that cannot be tested in-process. At the end of the workstream ONE `make quick` plus ONE `make e2e-one` per UI test class you added or changed. NO `make gate` per workstream (the orchestrator runs one per wave), no `make check` (phase gate only, P3-9), no E2E retry loops (a failure is investigated, not re-run), no duplicate builds in scratch worktrees. Real FM/MLX calls never run inside `make check` or `make gate`.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency.

## Goal

Nobody has to remember a directive name or a value format. Song metadata is set with controls that write standard ChordPro and the sidecar; Text mode gains a `/` menu and a `{` completion that lead to the right directive and help with its value.

## Existing code

- `Library/SongDetailPane.swift` (read-only subtitle "artist · key, tempo", lines ~122-128), `Library/SongMetadataViews.swift` (proficiency chips, tag field ~159-232, "Add Notes & Cues..." ~119-126), `Library/LibraryViewModel+Metadata.swift`, `Library/LibraryViewModel+Editing.swift` (new-song path ~230-251).
- `Editor/EditorTopBar.swift` (capo stepper ~74-90), `Editor/SongEditorViewModel+Options.swift` (`setDirective` ~71), `SegueCore/Editing/DocumentEditor.swift` (`EditOperation.setDirective` / `.setMeta` ~37-39).
- `Editor/EditorSuggestions.swift` (flat list of 22 names ~113-144, short forms recognised ~157-175, `end_of_` promoted ~137-141), `Editor/CompletionPopup.swift` (horizontal chips), `Editor/SourceEditorController+Completion.swift`.
- `SegueCore/ChordPro/SongDocument+Derived.swift` (`valueProblem` ~178-190 covers capo and tempo; not key or time), `MusicTheory` key parsing, `KeyDetector`.

## Steps

0. **Design directions (R39 style):** 2-3 renders of the song card within direction B (compact read state and expanded edit state, the essentials dots, light and dark), and of its placement while the editor is open (the library detail pane hosts the editor today; e.g. a collapsible inspector column vs the card above the editor). Ryan picks before step 2.
1. **Card shell + tag field move:** new folder `Packages/SegueUI/Sources/SegueUI/SongCard/`; move the existing proficiency chips and tag field out of `SongMetadataViews.swift` into `SongCard/` files with no behaviour change (P3-6 owns the tag field file's contents after this commit: tell the orchestrator when it lands). Commit alone.
2. **Fields** (spec 16.0.1 table): Title, Artist (completion from artists in the library), Key (picker; detected key offered as "Am - from chords", written only when picked), Tempo (Tap per question 28: blocked until Ryan rules), Capo (the same binding as the top-bar stepper, so both stay in sync), Time (4/4, 3/4, 6/8, Other...), Proficiency, Tags. Each commit is one `EditOperation.setDirective`/`.setMeta` (one undo step, autosaved); clearing removes the directive; invalid values never reach the file. The subtitle in `SongDetailPane` is replaced by the card. Compact read state, expands on focus. Draft mode: the same view edits an in-memory document for P3-4's review sheet (expose a binding-based initialiser; no file I/O in draft mode).
3. **Set essentials (R80):** key and tempo show a dot when missing, with a help tag "Set essential: used to time a set and plan its flow". Markers outside the card are question 27 (blocked until Ryan rules; recommendation b: a quiet dot on library rows and the builder's library column).
4. **Focus seams** for siblings: `focus(.title)` (P3-4's Start blank), plus a notification/route that selects a song and focuses a field.
5. **Value validation (R81):** `valueProblem` gains `{key}` (must parse as a MusicTheory key) and `{time}` (`n/d` with sane values); the diagnostic carries a fix where one is clear (`Hm` -> `Bm`, `H` -> `B`, `G major` -> `G`, `A minor` -> `Am`); the editor's diagnostics UI offers it as a one-click fix.
6. **`{` completion fixes (R81):** items show a plain name beside the directive; a section word (`{cho`, `{verse`, `{bri`, `{int`, `{out`) offers `start_of_<kind>` and the labelled form `{start_of_<kind>: <Kind N>}` first and shows `chorus` as "Chorus (repeat)"; short forms (`soc`, `eoc`, `sov`, `eov`, `sob`, `eob`, `c`) offered as aliases; after `key:`, `tempo:`, `time:`, `capo:` the value pickers (shared with the card) open; `end_of_` promotion kept. `CompletionPopup` gains a vertical list variant with descriptions.
7. **Slash menu (R81):** `/` at line start (only whitespace before it) opens the vertical menu (spec 16.0.2): sections wrap the selected lines (or insert the pair with the caret inside) with automatic numbering; value items write the directive at the top (replacing an existing one); Note inserts `{comment: }` for now (P3-13 later routes it to section notes); fuzzy matching on words and aliases; Esc leaves the `/` typed; `/` mid-line is text. Wrapping uses P3-11's section `EditOperation` if it has landed, else a text edit you replace with it later (tell the orchestrator).

## Coordination

- P3-6 edits the tag field file's contents after step 1. P3-4 embeds the card in draft mode (wave 3). P3-11 owns the visual editor and the new section operations; P3-13 owns notes. Do not touch `NotesEditorSheet.swift` or the "Add Notes & Cues..." entry beyond moving it intact if the card layout requires.
- Accessibility identifiers `segue.songCard.*`, `segue.editor.slashMenu.*`; every control reachable by keyboard and VoiceOver.

## Tests

In-process SegueUI integration tests with a temp library and the real parser/editor: each card field writes exactly its directive or sidecar field and clearing removes it; capo stepper and card stay in sync; draft mode writes nothing to disk; `{key: Hm}` yields a diagnostic whose fix produces `{key: Bm}`; completion lists for `{cho`, `{verse`, `{soc` and after `key: `; slash-menu wrap of a 4-line selection gives valid ChordPro with zero lyric change and one undo step. Suites: `SongCardTests`, `EditorCompletionTests`, `SlashMenuTests`, `DirectiveValidationTests`. E2E `SegueSongCardE2ETests` (fresh library): set key and tempo on a Welcome song from the card, then Text mode shows the directives; type `/cho` + Return on a selection and see a Chorus section.

## Files owned

`Packages/SegueUI/Sources/SegueUI/SongCard/**` (except the tag field's contents after step 1), `Library/SongDetailPane.swift`, `Library/SongMetadataViews.swift`, `Editor/EditorSuggestions.swift`, `Editor/CompletionPopup.swift`, `Editor/SourceEditorController+Completion.swift`, `Editor/EditorTopBar.swift` (capo sync only), `SegueCore/Sources/ChordPro/SongDocument+Derived.swift` (validation additions), the editor diagnostics fix action, `UITests/SegueSongCardE2ETests.swift`, the tests above.

## Acceptance

Every field and slash/completion item writes valid ChordPro or sidecar data without typing directive syntax; the brainstorm's three completion traps and the unvalidated `{key}` are gone; the card works in draft mode for P3-4; `make quick` green; the wave gate green.
