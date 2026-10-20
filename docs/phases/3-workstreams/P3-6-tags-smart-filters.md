# P3-6 - Tags and smart filters

Wave 2 (the tag-field step waits for P3-10's song-card step 1; everything else starts at once). Parent spec: `docs/phases/3-ai-entry-and-assistant.md` (read sections 8, 9, 11, 16.0.1). Rulings: `docs/release/decisions.md` R71 (no energy, starter tags manual only, no AI tag guesses), R72 (filters as library files), R74 (analytics), R15 (deletes to Trash), R80 (the song card hosts the tag field), R91 (lengths are `{duration}` only, no estimates). Existing code: `Library/SongFilter.swift` (phase 2 simple filters: tags, proficiency, key, typed tokens), `Library/LibraryArchive.swift` (`includedFolders`), `Support/LibraryRoot.swift`, `Library/SongIndex+Plays.swift` (`lastPlayed`), `SegueUI/Library/MainSidebar.swift`, `SongFilterState.swift`.

## Session rules (apply to every P3 workstream)

- `cat` is aliased to eza and can hang: use `command cat` or the Read tool. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-".
- Sibling workstreams edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, and stage only your own files.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget (R113): per step only targeted in-process suites (`swift test --filter <Suite>`); new UI behaviour gets in-process SegueUI tests, and a new XCUITest only for a flow that cannot be tested in-process. At the end of the workstream ONE `make quick` plus ONE `make e2e-one` per UI test class you added or changed. NO `make gate` per workstream (the orchestrator runs one per wave), no `make check` (phase gate only, P3-9), no E2E retry loops (a failure is investigated, not re-run), no duplicate builds in scratch worktrees. Real FM/MLX calls never run inside `make check` or `make gate`.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency.

## Goal

Tags become easy to apply and manage, and saved smart filters live as plain library files that show up in the sidebar, travel with the library archive and feed the set assistant.

## Deliverables

1. **Tags** (the tag field lives inside P3-10's song card: P3-10 step 1 moves it into its own file under `SongCard/`; you own that file's contents from then on, P3-10 owns the card layout): autocomplete from tags in use; rename and merge across the library (rewrites sidecars atomically, one undoable action); **starter suggestions** `upbeat`, `ballad`, `crowd pleaser`, `singalong`, `original`, `cover` when the user has no tags of their own (the Welcome seed tag does not count); manual pick only, nothing pre-applied.
2. **SmartFilter model** (`Library/SmartFilter.swift`): name, ULID id, conditions - tags all / any / none, proficiency set, keys, tempo range, length range (on the song's `{duration}`; a song with no length never matches a length condition; no estimates, R91), last played before / after, never played. No energy. Compiles to the in-memory matcher (extend `SongFilter` or a sibling; keep phase 2 behaviour intact).
3. **Storage (R72):** `filters/<slug>.filter.json`, versioned JSON (`schemaVersion: 1`, `VersionedJSON` migrator, newer-version files read-only with a warning like sidecars); `LibraryRoot.filtersDirectory` + `filterSuffix` (shared file with P3-5: additive edits); `LibraryArchive.includedFolders` gains `filters` (update its doc comment and the archive test); delete moves to the Trash; slug collisions as setlists do.
4. **Index evaluation:** fast evaluation for a 300-song library (< 50 ms); file changes picked up by the existing rescan.
5. **UI:** sidebar section **Smart Filters** (list, new, rename, edit, delete to Trash); a filter editor (rows of conditions; accessible by keyboard and VoiceOver); applying a filter shows its songs in the list. A filter can be picked as a set-assistant input (P3-7 consumes `SmartFilterStore`). Emit `Segue.AI.smartFilterUsed` (vocabulary defined by P3-4; if P3-4 has not landed, leave a single call site TODO for it and tell the orchestrator).
6. A smart filter is usable in the set builder's Pick mode filter (P3-12) the same way as the phase 2 filter chips; expose it through `SmartFilterStore` and let P3-12 wire it.

## Tests

Integration in a temp library: create/edit/delete filters as files, reload, archive contains `filters/`, rename/merge tags across sidecars, starter suggestions appear only with no own tags, each condition kind including last-played and length (songs without a length excluded). In-process UI test for the sidebar section. Suites: `SmartFilterTests`, `TagManagementTests`.

## Files owned

`Library/SmartFilter*.swift`, `Library/SongFilter.swift` (compatible extension), `Library/LibraryArchive.swift`, `LibraryRoot.swift` (shared, additive), tag rename/merge in `LibraryStore` (new file `LibraryStore+Tags.swift`), `SegueUI/Sources/SegueUI/SmartFilters/**`, `Library/MainSidebar.swift`, the tag field file under `SongCard/` (contents only, after P3-10 step 1 creates it).

## Acceptance

Filters persist as `filters/*.filter.json`, are archived, evaluate correctly and appear in the sidebar; no energy anywhere; `make quick` green; the wave gate green.
