# P8-1 - Fix round: pedal safety, crash class, robustness, near-duplicate import warning, custom section names

Phase 8 workstream (new, 2026-10-30), from the read-only review of 2026-10-30. Rulings: `docs/release/decisions.md` **R154** (this work), **R158** (its open questions closed, section 11), **R159** (custom section names offered again, section 7a). Related rulings: R45 (page turners send Page Down/Up and cross song boundaries), R102/R112 (no repeats in a show), R104 (breaks), R113 (test budget), R74 (closed analytics vocabulary), R144 (the section notes crash fixed in dce53bc, the pattern reused here), R147 (collapse repeats removed on stage; sibling P8-2 owns that), R153 (the set composer reuses `RomanNormalizer`, as this spec does). Sibling specs in this folder (P8-2..P8-5) touch none of this spec's files except where section 9 says so.

**Build order (R155):** all of Phase 8 ships before the v0.5 submission. **P8-1 is built first**; then P8-2, then P8-3 (it consumes P8-2's pass model), with P8-4a and P8-5 in parallel with them; P8-4b is blocked on research (R160). Index: `README.md` in this folder.

Every item below was checked against the code at `ca077c9` (2026-10-30). File:line references are from that tree; re-check them before editing, since siblings edit the same files.

## Session rules

- `cat` and `ls` are aliased to eza and can hang: use `command cat` / `command ls` or the Read tool. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-". Ignore `.build/`.
- Sibling agents edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, stage only your own hunks by explicit path. Keep the tree compiling between steps.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact and tell the orchestrator; never commit unsigned. Never push.
- Test budget (R113): per step only targeted in-process suites (`swift test --filter <Suite>`), every build or test under `lockf -k .build/make.lock`. New UI behaviour is covered by in-process SegueUI tests. At the end of the workstream ONE `make quick` plus ONE `make e2e-one` per UI test class whose covered UI changed (section 8). No `make gate` (the orchestrator runs one per wave), no `make check`, no E2E retry loops, no scratch-worktree builds.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency.

## 1. Goal

A stage that a held, bouncing or stuck pedal cannot derail; two crash paths closed; four robustness gaps closed; a gentle warning when an import or paste looks like a song already in the library; and the custom section names a song already uses offered again in the editor. No new features beyond the warning and the section chips; nothing here changes a file format.

**In scope (R154, R159):** key auto-repeat limited to scroll and zoom; page-forward and page-back ignored while a song change is in flight; page-forward at the bottom of the last song stays put with a hint; the Smart Filter editor's positional row bindings; the reorder review's double submit; serialized setlist undo snapshots; a failed End Show re-offered at once; import folder depth and symlink guard; UTF-16 text files with a BOM; the near-duplicate warning (a similarity score over title, artist and content); verifying and resolving Sentry SEGUE-MACOS-2; custom section names as extra chips and menu items, and library suggestions in the Custom... field (R159).

**Not in scope (R154 declined):** Duplicate Song, a count-in before auto-scroll, a quicker first run. Also not here: the collapse-repeats toggle (P8-2 removes it, R147).

## 2. Review findings checked against the code

| # | Finding | Verdict |
|---|---|---|
| 1a | Key auto-repeat passes for every `.viewport` command, which includes page-forward/back, auto-scroll, columns and collapse repeats | Confirmed |
| 1b | Page-forward decides from stale state while a `.next` is in flight | Confirmed; page-back has the same shape and is guarded too (R158 Q1) |
| 1c | Page-forward at the bottom of the last song ends the chart | Confirmed; the fix belongs in the stage session, not in `ShowRecord+Transitions.swift` (explicit Next keeps ending the chart) |
| 2a | Smart Filter `ForEach($draft.rows)` positional bindings | Confirmed; the only `ForEach($...)` in the codebase |
| 2b | Reorder review double submit | Confirmed, and worse than a duplicate save: the second call's `removeFirst()` drops the next unanswered review from the UI, or traps on an empty array when it was the only one (a crash) |
| 3a | `SetlistsViewModel.mutate` undo snapshot race | Confirmed; undo and redo writes can also interleave with an edit in flight |
| 3b | `finishRun` leaves an unended show without `pendingResume` | Confirmed; `endPendingShow` has the same gap |
| 3c | Import expand has no depth or symlink guard | Confirmed (unbounded recursion on a symlink loop) |
| 3d | UTF-16 files rejected for their NUL bytes | Confirmed; `SongFiles.decodeText` already decodes UTF-16 with a BOM, the NUL check in import runs first |
| 4 | No near-duplicate warning | Confirmed; only byte-identical files are caught (`prepareImport`), and only for file imports; already-ChordPro files skip the review sheet entirely, so a lookalike among them is now routed through the sheet (R158 Q4, section 6.3) |
| 5 | SEGUE-MACOS-2 looks fixed by dce53bc | Plausible from the code (pending rows keyed by UUID); no release tag contains dce53bc yet (the repo has no tags; `Config/Version.xcconfig` is 0.5 build 1), so verification needs a build that includes it |

Wrong or imprecise in the review: the transitions file is not the place to fix 1c (section 3.3); 1b also applies to page-back; 2b is a crash, not only a double save; 3d's decoder already supports UTF-16, so the fix is one guard, not a new decoder.

## 3. Pedal safety (step 1)

### 3.1 Current state

- `Packages/SegueUI/Sources/SegueUI/Live/LiveKeyInput.swift:39-55`: `handle` drops a repeat only when `command.scope != .viewport` (`:50-52`). The doc comment at `:37-38` already promises "a repeat never advances songs, toggles panels", which the code does not keep.
- `Packages/SegueCore/Sources/Shows/LiveCommand.swift:61-73`: `.viewport` holds `cycleColumns, pageBack, pageForward, resetZoom, restartScroll, scrollFaster, scrollPageDown, scrollPageUp, scrollSlower, toggleAutoScroll, toggleCollapseRepeats, zoomIn, zoomOut`.
- `Packages/SegueCore/Sources/Shows/InputBindings.swift:242-244`: Page Down = `.pageForward`, Page Up = `.pageBack` (what page turners send).
- `Packages/SegueUI/Sources/SegueUI/Live/LiveSession+Viewport.swift:239-250` `pageForward()`: pages down, or at the bottom (or when the song fits) calls `perform(.next)`. `:254-262` `pageBack()` mirrors it with `.previous`.
- `Packages/SegueUI/Sources/SegueUI/Live/LiveSession.swift:197-215` `perform(_:)` enqueues the action behind any in flight (`enqueue`, `:237-244`); `plan` and `state` only change in `apply` (`:247-256`) after the engine answers. So a second Page Down before the first `.next` lands still sees the old song at its bottom and enqueues a second `.next`: one double tap skips a song. A held Page Down does the same at key-repeat rate.
- `Packages/SegueCore/Sources/Shows/ShowRecord+Transitions.swift:292-313` `advance(marking:at:)`: with no pending item after current (`nextPendingIndex`, `:225-228`, internal), `.next` marks the song played and leaves nothing current. The stage then shows "End of N" (`LiveSession.swift:295`) and the footer "End of set" (`StageChrome.swift:194-196`). Correct for an explicit Next; wrong for a page turn.
- Existing test: `LiveHardeningTests` "key repeats scroll but never advance songs or toggle panels" (`Packages/SegueUI/Tests/SegueThemeTests/LiveHardeningTests.swift:193-214`) covers Right arrow and `s` only, which is why the page-turner gap was missed.

### 3.2 Repeats: an explicit allowlist in Core

- Add to `LiveCommand` (Core, so phase 6 pedal and MIDI sources reuse the same rule):

```swift
/// Whether a held key (auto-repeat) may repeat this command: only continuous scroll and
/// zoom. A repeat never changes songs, toggles, cycles, confirms or plays (R154).
public var repeatsWhenHeld: Bool {
    switch self {
    case .scrollPageDown, .scrollPageUp, .scrollFaster, .scrollSlower, .zoomIn, .zoomOut:
        true
    default:
        false
    }
}
```

- `LiveKeyInput.handle`: replace `if isRepeat, command.scope != .viewport` with `if isRepeat, !command.repeatsWhenHeld` (still returns true, swallowing the repeat). Keep the doc comment, now true.
- `restartScroll` and `resetZoom` are idempotent but excluded anyway, so the rule reads "only continuous changes repeat" (R158 Q2).
- P8-2 (built after this spec, R155) deletes `.toggleCollapseRepeats`; it is excluded here by the `default`, so P8-2's deletion needs no change to this property.

### 3.3 Page turns while a song change is in flight

- `LiveSession` gains `@ObservationIgnored private(set) var songChangesInFlight = 0`. `perform(_:)` increments it before enqueueing a navigation action that can change the current song (`.next`, `.previous`, `.skipCurrent`, `.jump`, `.playNow`, `.playNextRequest`) and decrements it at the end of that action's queued closure (success and failure paths, via `defer`).
- `pageForward()` and `pageBack()`: `guard songChangesInFlight == 0 else { return }` as their first line (page-back too, R158 Q1: a double Page Up never goes back two songs). Scrolling inside a song is unaffected, and explicit Next / Previous (arrows, Space) keep applying in order as `perform` documents ("fast pedal taps apply in order").
- A dropped page turn is silent: the song change it would have repeated is already happening.

### 3.4 Page-forward at the bottom of the last song

- Core: expose `public var hasNextItem: Bool { nextPendingIndex != nil }` on `ShowRecord` (`ShowRecord+Transitions.swift`, next to `nextPendingIndex`). Do not use `ShowState.upNext`: it shows a queued request first, but `.next` never plays a request, so `upNext != nil` does not mean Next has somewhere to go.
- `pageForward()`: where it would call `perform(.next)`, first check `state.record.breakId == nil && !state.record.hasNextItem` (`breakId` is already public, `ShowRecord.swift:317`; a break showing still ends on `.next`, R104). When true, do not perform; call `flash("Last song")` (the 1.5 s mode indicator, `LiveSession+Viewport.swift:366-374`). The hint is plain "Last song" always, also when requests are queued; there is no request variant (R158 Q3).
- Explicit Next (Right arrow, Space) at the last song still ends the chart, and `Cmd-.` still ends the show: only the page turner is made safe.
- Single-song sessions (R150, a sibling spec) get this for free: page-forward at the bottom of the only song stays put.

## 4. Crash class (step 2)

### 4.1 Smart Filter editor rows

- Current: `Packages/SegueUI/Sources/SegueUI/SmartFilters/SmartFilterEditorSheet.swift:57-68` `ForEach($draft.rows) { $row in ... onRemove: { draft.removeRow(row.id) } }`. The row view's text fields bind through `$row` (`:269` From, `:277` To, plus the popups and key chips). `SmartFilterDraft.removeRow` (`SmartFilterDraft.swift:187-191`) and `addRow(after:)` (`:180-184`) change the array under SwiftUI's positional `Binding` subscripts. This is the same shape as SEGUE-MACOS-2 (index out of range in a `TextField` binding while rows are removed): a focused From/To field in a removed row, or the last row after a removal, writes through a stale index.
- Fix, copying `SectionNotesSheet+Additions.swift:106-119` (`additionBinding`):
  - Iterate values: `ForEach(draft.rows) { row in ... }` (rows are `Identifiable`).
  - Pass `SmartFilterConditionRow` a `Binding<SmartFilterDraft.Row>` built by id: `get` returns `draft.rows.first { $0.id == row.id } ?? row` (the captured value as fallback for a row that outlives its entry by one render pass); `set` writes only when `firstIndex(where:)` finds the id, else ignores the write.
  - Put the helper on the sheet as `private func rowBinding(_ id: SmartFilterDraft.Row.ID, fallback: SmartFilterDraft.Row) -> Binding<SmartFilterDraft.Row>`; the row view keeps `@Binding var row` and its `$row.lower` / `$row.upper` projections unchanged.
- Sweep result (`ForEach($`, `.indices`, `enumerated()`, index-captured `Binding`): `SmartFilterEditorSheet.swift:57` is the **only** `ForEach` over a binding collection. The other index-based lists are read-only (`ReorderDiffSheet.swift:160,169`, `GigDetailView.swift:250`, `ImportSummaryBar.swift:66`, `QuickSearchOverlay.swift:143`, `StageSongBody.swift`, `KeyboardShortcutsView.swift:105`) or mutate through bounds-checked index methods (`ArrangementDraft.swift:102-170`, every method guards `rows.indices.contains`; `ArrangementEditorSheet.swift:207-225` re-checks `draft.rows.indices.contains(index)`). Nothing else to change. Note that sibling work on the Arrange Sections sheet (R149) must keep id-keyed or bounds-checked access.

### 4.2 Reorder review double submit

- Current: `Packages/SegueUI/Sources/SegueUI/Live/LivePresentations.swift:59-79` wraps each button in `Task { await app.resolveReorderReview(...) }`. `ReorderDiffSheet.swift:235-248` never disables its buttons. `AppModel+Shows.swift:209-247` `resolveReorderReview` reads `pendingReorderReviews.first`, awaits the store (`:214`, `:216`, `:233`), then calls `pendingReorderReviews.removeFirst()` (`:243`). A double click runs two calls on the same review: two `saveShowOrder` writes (two undo steps "Save Show Order"), two `resolveReview` writes, then two `removeFirst()`. The second removes the **next** review unanswered (it reappears only on the next `reloadPendingReviews`), or traps if the array is empty.
- Fix:
  - `AppModel` gains `public internal(set) var isResolvingReview = false`. `resolveReorderReview` returns at once when it is true; otherwise sets it and clears it in a `defer`.
  - Capture the diff's identity at entry and remove that diff, not the first: `pendingReorderReviews.removeAll { $0.showId == diff.showId && $0.setlistId == diff.setlistId }` (`ReorderDiff` is `Hashable`, not `Identifiable`; `showId` is optional, so match on both). Never `removeFirst()`.
  - `ReorderDiffSheet` gains `isBusy: Bool` (from `app.isResolvingReview`) that disables Save and Discard while an answer is being written; `LivePresentations.reviewHost` passes it.

## 5. Robustness (step 3)

### 5.1 Setlist undo snapshots are serialized

- Current: `Packages/SegueUI/Sources/SegueUI/Setlists/SetlistsViewModel.swift:227-256` `mutate` reads `before` from the store, awaits the operation, reloads, then registers `before -> updated`. Two edits in flight on the same setlist (a drag and a quick Delete, the assistant applying while the user edits) both read the same `before`; the later one's undo then also reverts the earlier edit, and the registration order on the undo stack follows await resumption, not the order the user acted. Undo and redo writes run through a separate chain (`SetlistsViewModel+Undo.swift:117-124`, `undoWork`) that does not wait for an edit in flight, so Undo pressed during an edit can restore a snapshot the edit then overwrites.
- Fix: one serial queue for every setlist write in the view model.
  - Rename `undoWork` to `writeWork` (`SetlistsViewModel.swift:47`) and make `mutate` run its whole body (read `before`, operation, reload, `then`, register undo) inside the chain, awaiting the queued task's result so callers keep their `async -> Setlist?` contract.
  - Undo and redo keep using the same chain (`chain(_:)`), so an Undo pressed during an edit runs after it, against the snapshot the edit registered.
  - Do not move the snapshot into the store actor instead: per-call before/after pairs would still register on the undo stack out of order.
- Callers to re-check (13 `mutate(` call sites): `SetlistsViewModel.swift`, `SetlistsViewModel+Builder.swift`, `SetlistsViewModel+Arrangement.swift`, `Assistant/SetlistsViewModel+Assistant.swift`. None may call `mutate` from inside a `mutate` operation (it would deadlock the chain); assert this by reading each call site.

### 5.2 A failed End Show is re-offered at once

- Current: `AppModel+Shows.swift:382-406` `finishRun`: when `controller.end()` throws, it shows "It will be offered again at next launch." and relinquishes the claim; `pendingResume` stays nil, so the run sits unended and invisible until relaunch (and the user may start another show meanwhile). `endPendingShow` (`:177-202`) clears `pendingResume` before trying, so its failure has the same gap. Note `ShowController.end()` (`ShowController.swift:268-285`) has already marked its in-memory record finished when the write fails, so the in-memory record must not be offered.
- Fix:
  - After the failed `end()` and `relinquish()`, reload the record from disk: `let record = await session.stores.shows.reloaded(showId)`. If it exists, is not finished and is not read-only, set `pendingResume = record`; the existing resume prompt (`LivePresentations.swift:29-31`, Resume / End Show) appears as soon as the stage closes (`isPerforming` is false once `self.live = nil`). Message: "The show could not be closed (<reason>). It is still open: Resume it, or try End Show again."
  - If the reload finds nothing usable, keep today's message.
  - `endPendingShow`: on failure, do the same reload and restore `pendingResume`, so End Show in the prompt can be retried.
  - When the user was quitting (`quitsAfterEnding`), keep quitting; the launch check offers the show at next launch (R158 Q5).

### 5.3 Import folder depth and symlink guard

- Current: `Packages/SegueCore/Sources/Library/LibraryStore+Import.swift:177-191` `expand(_:)` recurses into every directory `directoryExists` reports, and `LiveFileSystem.directoryExists` (`Support/FileSystem.swift:97-104`) follows symlinks. A symlink to an ancestor folder recurses until the stack overflows; a dropped home folder walks everything before the 500-file limit applies (`SongImport.maxFiles`, applied later in `prepareImport`).
- Fix (stat-only, like `isPackage` at `:195-197`):
  - Carry `depth` and a `visited: Set<String>` of resolved directory paths (`url.resolvingSymlinksInPath().path(percentEncoded: false)`). Skip a directory already visited (loops and diamonds) and stop descending past `SongImport.maxFolderDepth = 16`.
  - Follow a symlinked directory only through the visited check (a deliberate link to a song folder still imports; R158 Q6).
  - Stop expanding once the walk has collected `SongImport.maxFiles + 1` importable files, so a huge folder is not enumerated in full. The overflow is reported as ONE skip line, "Import limit of 500 files reached; the rest of <folder> was not read" (`<folder>` = the dropped item's name); unread files are never counted (R158 Q7).
  - Directories skipped for depth add one `ImportSkip(fileName: <folder name>, reason: "Folder nested too deeply")`; loops are skipped silently.

### 5.4 UTF-16 text files

- Current: `decodeForImport` (`LibraryStore+Import.swift:200-228`) rejects any file containing a NUL byte as "Not a text file" (`:211-213`) before decoding. Every UTF-16 file has NUL bytes for ASCII characters, so Windows Notepad exports never reach `SongFiles.decodeText` (`SongFiles.swift:305-319`), which already decodes UTF-16 with a BOM and reports `.notUTF8(encoding: "UTF-16")`.
- Fix: sniff the BOM first. If the data starts with `FF FE` or `FE FF`, skip the NUL check and pass the bytes (BOM included) to `decodeText`. Everything else keeps the NUL check. The imported song is written as UTF-8 by `createSong`, and the summary says "converted from UTF-16" through the existing `convertedFrom` path.
- Make sure the decoded text has no leading U+FEFF (strip it if Foundation leaves it), so `{title}` detection on line one still works.
- Out of scope: UTF-16 without a BOM and UTF-32 (R154 says "by BOM"); they stay "Not a text file".

## 6. Near-duplicate warning on import and paste (step 4)

### 6.1 Rule: a basic similarity score (R158 Q8)

The title-plus-artist rule is replaced by one deterministic score over **title, artist and content together**. It is cheap: the score is computed only against library songs whose titles look similar (6.2 blocking), never against the whole library per file, and it uses only string work already in `RomanNormalizer` (`Packages/SegueCore/Sources/Library/RomanNormalizer.swift`). Original text is never changed; normalization only decides the warning.

For an incoming song `s` (title, artists and `plainLyrics` from its current text) and a candidate library song `c`:

- **Title similarity `T`** (0...1). `a = RomanNormalizer.loose(s.title)`, `b = RomanNormalizer.loose(c.title)` (`loose` at `:88`; so `Deewana` / `Diwana` / `dewaana`, `Pyaar` / `Pyar` are equal). `T = max(charSim, wordSim)`:
  - `charSim = 1 - d / max(a.count, b.count)` with `d = RomanNormalizer.editDistance(a, b, limit: 3)` (`:182`, internal to the Library module, which is where this code lives); `charSim = 0` when `d > 3` or either side is empty.
  - `wordSim` = Jaccard of the two sets of loose title words (`|A ∩ B| / |A ∪ B|`), so "Tum Hi Ho" vs "Tum Hi Ho (Unplugged)" scores 0.75.
- **Artist similarity `A`**: 1 when both sides have an artist and any `RomanNormalizer.normalize` form of `s.artists` equals one of `c.artists`; **0.5 when either side has no artist** (unknown: pastes from chat often have no artist line); 0 when both have artists and none match.
- **Content similarity `C`**: word 3-shingles over the loose lyric words (`RomanNormalizer.words` of `plainLyrics`, each through `normalizeWord` then `looseWord`, first 400 words only; chords, directives and comments are not in `plainLyrics`). `C` = Jaccard of the two shingle sets. Shingles rather than lines, so a paste re-wrapped at different line breaks still matches. When either side has fewer than 3 shingles (a chords-only chart, an empty paste) `C = 0.5` (unknown).
- **Score** `S = 0.5 T + 0.2 A + 0.3 C`. The song **looks like** `c` when `S >= 0.72` and the content hashes differ (byte-identical files are already skipped by `prepareImport`, `LibraryStore+Import.swift:120-127`; byte-identical pastes get their own callout, 6.3).

Worked values (each pinned by a test row in section 8):

| Case | T | A | C | S | Warns |
|---|---|---|---|---|---|
| `Diwana` vs `Deewana`, same artist, same lyrics re-wrapped | 1 | 1 | 0.9 | 0.97 | yes |
| same title, no artist on the paste, same lyrics | 1 | 0.5 | 0.9 | 0.87 | yes |
| same title, same artist, chords-only paste (no lyrics) | 1 | 1 | 0.5 | 0.85 | yes |
| `Tum Hi Ho` vs `Tum Hi Ho (Unplugged)`, same artist, same lyrics | 0.75 | 1 | 0.9 | 0.85 | yes |
| same title, different artist, same lyrics (a cover) | 1 | 0 | 0.9 | 0.77 | yes |
| same title, same artist, entirely different lyrics | 1 | 1 | 0 | 0.70 | no |
| same title, different artist, different lyrics (another song) | 1 | 0 | 0.02 | 0.51 | no |
| `Pen` vs `Pin`, same artist, different lyrics | 0.67 | 1 | 0 | 0.53 | no (and never a candidate, 6.2) |

When several candidates pass, the highest `S` wins; ties go to the shorter title, then `localizedStandardCompare` of the title, then the song ID, so the result is stable across runs.

### 6.2 Core

New `Packages/SegueCore/Sources/Library/NearDuplicates.swift`: a value type built once from the library's songs, so the sheet can re-check on every edit without a store call.

```swift
public struct NearDuplicateIndex: Sendable {
    public struct Breakdown: Sendable, Hashable {
        public let title: Double      // T
        public let artist: Double     // A
        public let content: Double    // C
        public var score: Double { 0.5 * title + 0.2 * artist + 0.3 * content }
    }
    public struct Match: Sendable, Hashable {
        public let songId: SongID
        public let title: String
        public let artist: String?
        public let breakdown: Breakdown   // why it matched (tests and debugging)
    }
    public static let threshold = 0.72
    public init(_ songs: some Sequence<SongRecord>)
    /// The library song this one looks most like (6.1), or nil.
    public func match(title: String?, artists: [String], lyrics: String,
                      contentHash: String) -> Match?
    /// A library song with exactly this content hash (6.3, byte-identical pastes), or nil.
    public func identical(contentHash: String) -> Match?
}
```

- **Built once** (per review sheet or import batch): for each song, its loose title, loose title words, normalized artists, content hash and a reference to its `plainLyrics` (shingles are not precomputed for the whole library).
- **Blocking (the "similar titles only" rule):** a dictionary from blocking key to songs. Keys of a title = the first 3 letters of each loose title word of 3 or more letters; a title with no such word (e.g. "Ho") uses its whole loose form as its only key. A query's candidates are the songs sharing at least one key ("kesariya" / "kesriya" share `kes`; "pen" / "pin" share none).
- **Scoring:** compute `T` for each candidate and keep those with `T >= 0.5`; only those get `A` and `C` (shingling the candidate's lyrics on demand). Typical cost: a handful of candidates per file.
- `LibraryStore` gains `func nearDuplicateIndex() throws -> NearDuplicateIndex` (from `openLibrary().songs`).
- Within one batch, two incoming files that look like each other are not warned about (only library matches count).
- R157 widens `RomanNormalizer`'s short-word rules (built in P8-5). This index calls the normalizer at run time and stores nothing, so it picks the new rules up with no change and no migration.

### 6.3 UI

- **Review sheet** (pastes and non-ChordPro file imports, plus ChordPro lookalikes, below): `PasteReviewModel` holds the index (built when the review opens, `LibraryViewModel+Paste.swift:102-154` and the paste entry); `PasteReviewItem` gains `nearDuplicate: NearDuplicateIndex.Match?`, recomputed when its current `text` changes from the text's title and artists (from `SourceSnapshot(text:)`, as `canSwapTitleAndArtist` already reads them at `PasteReviewItem.swift:121-126`), its `plainLyrics` and `SongFiles.hash` of the text.
- **Where it shows:** under the song card in `PasteItemColumns.card` (`PasteItemColumns.swift:133-160`), a callout row with an `exclamationmark.circle` symbol in the muted cue colour: "Looks like “<title>” by <artist> in your library." (without "by <artist>" when blank). Identifier `segue.paste.nearDuplicate`. Text only, no "Show" link (R158 Q10). It does not block Accept and does not untick the item; the user decides.
- **Byte-identical pastes** (R158 Q9): a paste whose hash equals a library song's (`identical(contentHash:)`) shows the same non-blocking callout reading "Already in your library as “<title>”." instead.
- **Batch list** (`PasteBatchList.row`, `PasteItemColumns.swift:377-416`): a small dot on rows with a match, so a 30-file import shows which ones to look at; accessibility label suffix ", looks like a song in your library".
- **Already-ChordPro lookalikes go through the review sheet** (R158 Q4; an exception to R96's "ChordPro files import at once", for lookalikes only). In `importWithReview` (`LibraryViewModel+Paste.swift:102-154`), after `prepareImport`, the index is built once and each already-ChordPro candidate is checked: a candidate with a match becomes a review item (new `PasteSource.fileCho`, `Services/AnalyticsEvent+AI.swift:41-52`), with its text kept exactly as read: no AI or parser conversion runs, and Accept writes it byte-identical through the existing `writeReviewed` path. ChordPro files without a match still import directly, together with the reviewed items at Accept (one undo step, as today's mixed batches). During a show (no review sheet, R95) a ChordPro lookalike imports directly as today, without the warning. If the review sheet cannot show an item without a conversion step, stop and ask the orchestrator.
- There is no `ImportSummary.lookalikes` list: every warning sits beside its song in the sheet.

### 6.4 Analytics (non-PII, R74)

- Row 6 `songImported` (`Packages/SegueCore/Sources/Services/AnalyticsEvent.swift:30-35`, parameters at `:414-420`) gains `nearDuplicate: Bool` (`segue.nearDuplicate`: at least one imported song carried the warning). `PasteSource` gains `fileCho` (the vocabulary test and the WS3 row that lists paste sources update with it). Update `docs/release/specs/WS3-services.md` section 5 row 6 and the consent sheet list that reads it.
- The paste path: if pasted songs are recorded through `songCreated(.paste)` rather than row 6, ask the orchestrator before adding a parameter there.
- No titles, artists, IDs or scores are expressible.

## 7. Sentry SEGUE-MACOS-2 (step 5, Ryan)

The crash (index out of range in a `TextField` binding while adding notes to several sections) matches the code dce53bc replaced: pending addition rows indexed by position, now keyed by UUID with `additionBinding` (`SectionNotesSheet+Additions.swift:106-119`), with `testNotesOnSeveralSectionsAtOnce` in `UITests/SegueSectionNotesE2ETests.swift`.

1. The building agent checks that the build under test contains dce53bc (`git merge-base --is-ancestor dce53bc HEAD`) and notes the build number in the step's commit message.
2. **Ryan**, in Terminal.app (the agent shell cannot use `op`): `make sentry-pull`, then the agent reads `.build/sentry/issues.json` and `.build/sentry/events/` and reports whether SEGUE-MACOS-2 has any event from a release containing dce53bc (compare each event's `release` with the version and build that first included it).
3. If none: **Ryan** resolves it in the Sentry web UI with "Resolved in next release" (so a regression on a later build reopens it). `scripts/sentry-pull.sh` uses a read-only token and cannot resolve issues; do not add a write token for this.
4. If there are events from a build that contains dce53bc, the fix is incomplete: stop and report the stack to the orchestrator before resolving anything.

## 7a. Custom section names offered again (step 6, R159)

### 7a.1 Current behaviour (checked at `ca077c9`)

- **Chip bar.** `Packages/SegueUI/Sources/SegueUI/Editor/SectionChipBar.swift:61-96` `SectionChipBar` draws "N lines", the four quick chips `SectionChip.quick` (`:33-38`: Verse, Chorus, Bridge, Intro with keys V C B I), a divider, the fixed `SectionChip.outro` chip (`:41`), then "Custom..." (`:77-79`). `SectionChip.all = quick + [outro]` (`:42`). Nothing reads the song: a "Hook" section made with Custom... is never offered again, so the second Hook means typing the name again. `SectionChipBarHost.show(lines:at:in:)` (`:165-190`) builds the bar with `apply` and `custom` closures only.
- **Custom... field.** `VisualEditorController.applyCustomSection()` and `askSectionName()` (`VisualEditorController+SectionActions.swift:188-208`): an `NSAlert` with a plain `NSTextField` (placeholder "Section name", id `AccessibilityID.sectionBandCustomField`), no suggestions; `SectionChip.kind(named:)` (`SectionChipBar.swift:46-57`) turns the name into `.custom(<spelled>)`.
- **Section menu.** `bandMenu(for:)` (`VisualEditorController+SectionActions.swift:212-232`): on lines outside a section (`.slot`) a menu "Make <chip>" for each of `SectionChip.all` (`:223-227`), with no Custom... item; on a section, `sectionMenu` (`:236-284`) whose "Change Kind" submenu `kindMenu` (`:286-298`) lists `SectionChip.all` plus Tab, then "Custom..." (`:293-296`).
- **VoiceOver.** The same fixed list drives the band's custom actions: "Make <chip>" on a slot (`VisualEditorController+SectionAccessibility.swift:48-54`) and "Change to <chip>" on a section (`:75-79`).
- A custom kind's display name is `SectionLabels.displayName(.custom(name))` (`Packages/SegueCore/Sources/Editing/SectionLabels.swift:29-37`: underscores to spaces, capitalised, so `start_of_hook` reads "Hook" and `start_of_pre-chorus` "Pre-Chorus"). Kinds compare with `DirectiveLine.sameSectionKind` (`ChordPro/DirectiveLine.swift:66-68`, case-insensitive on the directive name).
- The editor has no library access today: `SongEditorViewModel` is built in `LibraryViewModel+Editing.swift:205-218` (edit) and `:235-247` (new song) without the catalog; the catalog is `LibraryViewModel.catalog: [SongRecord]` (`Library/LibraryViewModel.swift:25`), each record carrying its parsed `document`.

### 7a.2 Which names count

- **A custom section name** is a section kind `.custom(name)` that is not one of the fixed offers: not `intro`, `outro` (already chips), not `grid` (a verbatim block, `DirectiveLine.isVerbatimSection`), and not a built-in kind (`verse`, `chorus`, `bridge`, `tab`). Labels (`{start_of_verse: Hook}`) are not kinds and are not offered: a chip applies a kind.
- **In this song:** new `SectionLabels.customKinds(in document: SongDocument) -> [SectionKind]` (Core, Editing, pure): the custom kinds of the document's section blocks, de-duplicated with `sameSectionKind`, in order of first appearance, spelled as first written.
- **In the library:** new `SectionLabels.customKinds(in documents: some Sequence<SongDocument>) -> [SectionKind]`: the same rule over every song, ranked by the number of songs that use the kind (descending), then display name (`localizedStandardCompare`), at most 20. Ranking by song count keeps a one-off typo at the bottom.

### 7a.3 Chip bar and menus

- `SectionChipBar` gains `extras: [SectionChip]`, drawn **after Outro and before "Custom..."**, in the song's first-appearance order: `SectionChip(key: "", title: SectionLabels.displayName(kind), kind: kind)`, kind-coloured like the other chips (`SectionBandStyle.color(for:)` already handles `.custom`), no key cap. At most 4 extras in the bar (the bar is `.fixedSize()` and floats over the text); further names stay reachable through Custom..., which suggests them (7a.4). Identifier `segue.editor.sectionBand.chip.<lowercased title>`, as the fixed chips (`:118-120`); a name that would collide with a fixed chip's id cannot occur, since fixed kinds are excluded.
- `SectionChipBarHost.show` takes the extras; `VisualEditorController.updateChipBar()` (`SectionChipBar.swift:226-244`) passes `SectionLabels.customKinds(in: model.snapshot.document)` mapped to chips. A section of a custom kind made a moment ago appears on the next selection, since the snapshot is rebuilt synchronously on every change.
- One shared list, `VisualEditorController.sectionOffers: [SectionChip]` = `SectionChip.all` + the song's extras (all of them, not capped, in menus), used by:
  - the slot menu's "Make <name>" items (`VisualEditorController+SectionActions.swift:223-227`): extras after "Make Outro";
  - `kindMenu` (`:286-298`): extras after Outro and before Tab and "Custom...";
  - the VoiceOver custom actions (`VisualEditorController+SectionAccessibility.swift:48-54, 75-79`), so VoiceOver users get the same offers.
- The keys V / C / B / I are unchanged; extras have no key.

### 7a.4 Custom... suggests library names

- `askSectionName()` uses an `NSComboBox` instead of the `NSTextField` (same 240 x 24 frame, placeholder, and `AccessibilityID.sectionBandCustomField`), with `completes = true` (inline completion as you type) and its list = the library's custom names (7a.2), names already in this song first. The user can still type any new name; the combo box never replaces what was typed unless a completion is accepted. Run the `apple-api-check` skill for `NSComboBox` before using it (not in the codebase today).
- Section names are often romanized Hindi ("Antara", "Mukhda"): the field turns automatic spelling correction, text replacement and automatic capitalisation off on its field editor, and no step "corrects" a name.
- `SongEditorViewModel` gains `@ObservationIgnored var librarySectionKinds: () -> [SectionKind] = { [] }`, set by `LibraryViewModel` at both construction sites (`LibraryViewModel+Editing.swift:205`, `:235`) to compute `SectionLabels.customKinds(in: catalog.map(\.document))` when called. It is called only when Custom... opens (one pass over the in-memory catalog, no store call); no caching is needed at library sizes.
- Out of scope (R159 names the chip bar, the section menu and the Custom... field): the Text mode slash menu (`EditorSuggestions.sectionKinds`, `Editor/EditorSuggestions.swift:132-134`) keeps its fixed list. Ask the orchestrator if the session thinks it should follow.

### 7a.5 Tests

- **Core** (`SectionOperationTests`, extend, or a new `SectionLabelsTests` beside it; pure): `customKinds(in:)` for one song: `hook`, `tag`, a second `Hook` (case differs) -> [Hook, Tag], first spelling kept; `intro`, `outro`, `grid`, `verse`, `tab` never listed; a labelled verse `{start_of_verse: Hook}` not listed. Library form: counts across songs order the list, ties by name, limit 20, a kind used twice in one song counts once.
- **SegueUI in-process** (`SectionBandTests`, `Packages/SegueUI/Tests/SegueThemeTests/SectionBandTests.swift`): a song with a `{start_of_hook}` section: selecting other lines shows a chip "Hook" between Outro and Custom... (assert the bar's chip titles in order); applying it creates a `start_of_hook` section and one undo step; the slot menu lists "Make Hook" after "Make Outro"; Change Kind lists Hook before Tab; the VoiceOver action "Make Hook" exists; five custom kinds show four chips while the menus list all five. `askSectionName`'s suggestions: with a catalog of three songs using "Tag" and one using "Solo", the combo box's list is [Tag, Solo] (and this song's names first); the field's automatic correction and replacement are off.
- **E2E:** none new. `UITests/SegueSectionBandE2ETests.swift` (the class `UITests/e2e-map.tsv:81` maps to `Editor/*`) runs once at the end (section 8).

## 8. Test plan

In-process first, through real components (the real `LiveSession` with `TestEnvironment` and `LiveFixture`, the real `LibraryStore` on a temp library, the real `SetlistStore`). No mocks beyond the existing failing file systems.

Pedal safety (`LiveHardeningTests`, extending the existing "key repeats" test and its `key(_:repeat:)` helper):

- Repeated Page Down (key code 121, `repeat: true`) 30 times on a song that fits: still "1 of 3". Repeated `a`, `c`: auto-scroll and columns unchanged. Repeated Down arrow on a long song: the offset moves (scroll still repeats). Repeated Cmd-= : zoom changes.
- `LiveCommand.repeatsWhenHeld` is true for exactly the six scroll and zoom commands (a table test in the Core `LiveCommand` tests).
- Two `dispatch(.pageForward)` back to back on a song that fits: ends on "2 of 3", never "3 of 3" (the in-flight regression). Same for two `dispatch(.pageBack)` (R158 Q1): never two songs back.
- Page-forward at the bottom of the last song: `positionText` stays "3 of 3", `indicator == "Last song"` (also with a request queued: no request variant, R158 Q3), no `advanced` event appended. Explicit `.next` there still gives "End of 3".

Crash class:

- `SmartFilterSessionTests` (in-process, real draft and sheet state): add three rows, set From/To on the middle one, remove it, then write through the binding captured before the removal: no trap, the remaining rows unchanged, the write ignored. Remove the last row while its binding is live: same.
- `LiveModeTests` (where `resolveReorderReview` is already exercised, `:236`): with two pending reviews, call `resolveReorderReview(save: true, ...)` twice concurrently (`async let`): exactly one `saveShowOrder` (one undo step), the second review still pending; with one pending review, two concurrent calls do not trap.

Robustness:

- Setlist undo (the suite that owns `SetlistsViewModel` undo, else a new `SetlistUndoOrderTests` in SegueThemeTests): start two edits on one setlist without awaiting the first (`async let` move + delete), then undo twice: the setlist reads back exactly as before each step, in reverse order. Undo issued while an edit is in flight restores the right snapshot.
- End Show failure (`LiveHardeningLifecycleTests`, using `ToggleFailingFileSystem` from `LiveHardeningTests.swift:306`): make the show write fail, confirm End Show: the stage closes, `pendingResume` is the unended run, then End Show from the prompt with writes working closes it into the gig log.
- Import (`SongImportTests`, real `LibraryStore` on a temp folder with real symlinks): a folder containing a symlink to itself imports its one song and terminates; a folder nested 20 deep imports up to depth 16 and reports one "Folder nested too deeply"; a folder of 600 small `.cho` files reads at most 501 and reports the limit. A UTF-16 LE and a UTF-16 BE file with BOM (each with `{title}` on line one) import with the right title and "converted from UTF-16"; a UTF-16 file without BOM and a binary file with NULs stay "Not a text file".

Near-duplicate:

- `NearDuplicateIndexTests` (Core, tricky pure logic, so a direct table-driven test with `@Test(arguments:)`, each row a tiny library plus an incoming title, artist and lyrics): every row of the worked-values table in 6.1, asserting the `breakdown` (T, A, C to two decimals) and whether it matches; an identical hash never matches `match` but is found by `identical`; a pasted lyric re-wrapped at different line breaks keeps `C` within 0.05 of the original; a chords-only side gives `C == 0.5`; blocking: `Pen` / `Pin` and `Kesariya` / `Tum Hi Ho` are never scored (assert through a candidate-count hook or an internal `candidates(for:)` test), `Kesariya` / `Kesriya` is; tie-break order (two candidates with equal score: shorter title wins, then title, then ID) is stable; the 400-word cap (a 5,000-word lyric scores the same as its first 400 words).
- `PasteReviewTests` / `ImportUITests` (in-process): importing a `.txt` that looks like a library song shows the item's `nearDuplicate`; editing its title in the card to an unrelated title clears it; a pasted byte-identical song shows "Already in your library"; an already-ChordPro lookalike opens the review sheet as a `fileCho` item with the warning while a non-lookalike `.cho` in the same drop imports directly, both landing in one undo step at Accept and the lookalike's file byte-identical to the dropped one; analytics row 6 carries `segue.nearDuplicate = true`.

Custom section names (R159): section 7a.5.

E2E: no new XCUITest. A held pedal cannot be synthesized reliably through XCUITest, and every other change is covered in-process. At the end: one `make quick`, one `make e2e-one TEST=SegueLiveE2ETests` (stage input changed), one `make e2e-one TEST=SeguePasteE2ETests` (review sheet changed) and one `make e2e-one TEST=SegueSectionBandE2ETests` (chip bar and section menu changed). Nothing else.

## 9. Steps and files owned

1. **Pedal safety** (section 3): `Shows/LiveCommand.swift` (`repeatsWhenHeld` only; P8-2, built next, removes `toggleCollapseRepeats` in the same file), `Shows/ShowRecord+Transitions.swift` (`hasNextItem` only), `SegueUI/Live/LiveKeyInput.swift`, `Live/LiveSession.swift` (`perform`, the in-flight counter), `Live/LiveSession+Viewport.swift` (`pageForward`, `pageBack` only). Suites: `LiveHardeningTests`, the Core `LiveCommand` tests.
2. **Crash class** (section 4): `SmartFilters/SmartFilterEditorSheet.swift`, `App/AppModel+Shows.swift` (`resolveReorderReview`), `App/AppModel.swift` (`isResolvingReview`), `Live/LivePresentations.swift` (`reviewHost`), `Setlists/ReorderDiffSheet.swift`. Suites: `SmartFilterSessionTests`, `LiveModeTests`.
3. **Robustness** (section 5): `Setlists/SetlistsViewModel.swift`, `Setlists/SetlistsViewModel+Undo.swift`, `App/AppModel+Shows.swift` (`finishRun`, `endPendingShow`), `Library/LibraryStore+Import.swift`. Suites: as in section 8.
4. **Near-duplicate warning** (section 6): new `Library/NearDuplicates.swift`, `LibraryStore` accessor, `Paste/PasteReviewModel.swift`, `Paste/PasteReviewItem.swift`, `Paste/PasteItemColumns.swift`, `Paste/LibraryViewModel+Paste.swift` (lookalike routing), `Services/AnalyticsEvent.swift` (row 6), `Services/AnalyticsEvent+AI.swift` (`PasteSource.fileCho`), the accessibility ID file for Paste, `docs/release/specs/WS3-services.md` section 5 row 6. Suites: `NearDuplicateIndexTests`, `PasteReviewTests` / `ImportUITests`, `ServicesVocabularyTests`.
5. **Sentry** (section 7): no code; a note in the step's commit body or the handoff.
6. **Custom section names** (section 7a, R159): `Editing/SectionLabels.swift` (`customKinds`), `Editor/SectionChipBar.swift`, `Editor/VisualEditorController+SectionActions.swift`, `Editor/VisualEditorController+SectionAccessibility.swift`, `Editor/SongEditorViewModel.swift` (`librarySectionKinds`), `Library/LibraryViewModel+Editing.swift` (the two construction sites). Suites: `SectionOperationTests` (or `SectionLabelsTests`), `SectionBandTests`.
7. **Wrap-up**: `make quick`, the three `make e2e-one` runs.

Ask before touching anything else, in particular any P8-2..P8-5 file.

## 10. Done criteria

- No held, repeating or stuck key changes songs, toggles auto-scroll, cycles columns or flips any panel; scroll and zoom still repeat.
- A double Page Down never skips a song; Page Down at the bottom of the last song stays there and says "Last song"; explicit Next still ends the chart.
- Removing Smart Filter rows with a focused field never traps; a double click in the reorder review saves once and never loses or traps on the next review.
- Two quick setlist edits undo as two correct steps; a failed End Show shows the resume prompt right away; folder imports terminate on symlink loops and deep trees; UTF-16 files with a BOM import.
- Importing or pasting a song whose title, artist and content score at least 0.72 against a library song (romanized Hindi spelling variants included) says "Looks like ..." beside it in the review sheet without blocking, already-ChordPro lookalikes included; a byte-identical paste says "Already in your library".
- A custom section name used in the song is offered as a chip after Outro and in the section menu; Custom... suggests the library's custom names; nothing rewrites a typed name.
- SEGUE-MACOS-2 checked against a build containing dce53bc and resolved by Ryan, or reported back with new events.
- `make quick` green; the three `make e2e-one` runs green; the wave gate green.

## 11. Closed questions

Closed by Ryan on 2026-10-30 (**R158**; letters refer to the options as they were offered). The body above already reflects each answer.

1. **Page-back while a song change is in flight.** (a) Guarded the same way as page-forward: a double Page Up never goes back two songs (R158 Q1; section 3.3).
2. **Which commands repeat when held.** (a) Only the six continuous ones: scroll a page up or down, scroll faster or slower, zoom in or out (R158 Q2; section 3.2).
3. **Last-song hint text.** (b) Plain "Last song" always; no "R plays a request" variant (R158 Q3; section 3.4). This differs from the recommendation.
4. **Lookalikes among already-ChordPro files.** (b) A ChordPro file that looks like an existing song is routed through the review sheet so the warning sits beside it; an exception to R96's direct import, for lookalikes only. Non-lookalike ChordPro files still import directly (R158 Q4; section 6.3). This differs from the recommendation; there is no `ImportSummary.lookalikes`.
5. **End Show fails while quitting.** (a) Quit anyway; the launch check offers the show next time (R158 Q5; section 5.2).
6. **Symlinked folders inside a dropped folder.** (a) Followed, with the visited set and the depth cap (R158 Q6; section 5.3).
7. **How a huge folder's overflow is reported.** (a) One skip line, "Import limit of 500 files reached; the rest of <folder> was not read" (R158 Q7; section 5.3).
8. **Artist rule for the warning.** Replaced: the near-duplicate check is a basic similarity score over title, artist and content together, not a title-plus-artist rule (R158 Q8; section 6.1). A blank artist counts as unknown (0.5), neither a match nor a miss.
9. **Byte-identical pastes.** (a) "Already in your library as “<title>”", the same non-blocking callout (R158 Q9; section 6.3).
10. **Warning action.** (a) Text only, no "Show" link (R158 Q10; section 6.3).

R159 (custom section names, section 7a) was a new ruling, not an open question here; it has no open points beyond the slash-menu note in 7a.4.
