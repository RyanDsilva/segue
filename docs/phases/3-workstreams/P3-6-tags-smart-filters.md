# P3-6 - Tags and smart filters

Wave 2 (after P3-5's effective-length resolver lands). Parent spec: `docs/phases/3-ai-entry-and-assistant.md` (read sections 9, 11, 16.0, 16.1 question 5). Rulings: `docs/release/decisions.md` R71 (no energy, starter tags manual only, no AI tag guesses), R72 (filters as library files), R74 (analytics), R15 (deletes to Trash). Existing code: `Library/SongFilter.swift` (phase 2 simple filters: tags, proficiency, key, typed tokens), `Library/LibraryArchive.swift` (`includedFolders`), `Support/LibraryRoot.swift`, `Library/SongIndex+Plays.swift` (`lastPlayed`), `SegueUI/Library/MainSidebar.swift`, `SongFilterState.swift`.

## Session rules (apply to every P3 workstream)

- `cat` is aliased to eza and can hang: use `command cat` or the Read tool. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-".
- Sibling workstreams edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, and stage only your own files.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget: per step only targeted `swift test --filter <Suite>`; `make quick` + `make gate` once at the end of the workstream; never `make check` (phase gate only, P3-9). Real FM/MLX calls never run inside `make check` or `make gate`.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency.

## Goal

Tags become easy to apply and manage, and saved smart filters live as plain library files that show up in the sidebar, travel with the library archive and feed the set assistant.

## Deliverables

1. **Tags:** autocomplete from tags in use; rename and merge across the library (rewrites sidecars atomically, one undoable action); **starter suggestions** `upbeat`, `ballad`, `crowd pleaser`, `singalong`, `original`, `cover` when the user has no tags of their own (the Welcome seed tag does not count); manual pick only, nothing pre-applied.
2. **SmartFilter model** (`Library/SmartFilter.swift`): name, ULID id, conditions - tags all / any / none, proficiency set, keys, tempo range, length range (uses P3-5's `EffectiveLength`; estimates count per recommendation 5a and are marked `~` in results until Ryan rules), last played before / after, never played. No energy. Compiles to the in-memory matcher (extend `SongFilter` or a sibling; keep phase 2 behaviour intact).
3. **Storage (R72):** `filters/<slug>.filter.json`, versioned JSON (`schemaVersion: 1`, `VersionedJSON` migrator, newer-version files read-only with a warning like sidecars); `LibraryRoot.filtersDirectory` + `filterSuffix` (shared file with P3-5: additive edits); `LibraryArchive.includedFolders` gains `filters` (update its doc comment and the archive test); delete moves to the Trash; slug collisions as setlists do.
4. **Index evaluation:** fast evaluation for a 300-song library (< 50 ms); file changes picked up by the existing rescan.
5. **UI:** sidebar section **Smart Filters** (list, new, rename, edit, delete to Trash); a filter editor (rows of conditions; accessible by keyboard and VoiceOver); applying a filter shows its songs in the list. A filter can be picked as a set-assistant input (P3-7 consumes `SmartFilterStore`). Emit `Segue.AI.smartFilterUsed` (vocabulary defined by P3-4; if P3-4 has not landed, leave a single call site TODO for it and tell the orchestrator).
6. Leave fast-entry ideas alone: "Metadata entry and fast set building" is pending a brainstorm (spec 16.0).

## Tests

Integration in a temp library: create/edit/delete filters as files, reload, archive contains `filters/`, rename/merge tags across sidecars, starter suggestions appear only with no own tags, each condition kind including last-played and length with estimates. In-process UI test for the sidebar section. Suites: `SmartFilterTests`, `TagManagementTests`.

## Files owned

`Library/SmartFilter*.swift`, `Library/SongFilter.swift` (compatible extension), `Library/LibraryArchive.swift`, `LibraryRoot.swift` (shared, additive), tag rename/merge in `LibraryStore` (new file `LibraryStore+Tags.swift`), `SegueUI/Sources/SegueUI/SmartFilters/**`, `Library/MainSidebar.swift`, tag picker views.

## Acceptance

Filters persist as `filters/*.filter.json`, are archived, evaluate correctly and appear in the sidebar; no energy anywhere; `make quick` + `make gate` green.
