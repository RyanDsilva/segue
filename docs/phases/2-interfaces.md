# Phase 2 - Frozen interfaces

Cross-unit contract for the parallel phase 2 build (spec: `2-setlists-and-live-mode.md`, rulings: `decisions.md` phase 2 and round 2, look: `brand.md` section 7 plus the chosen mockups: setlist builder layout **a** "library to set", live view **C Precise**). Every type and signature below exists as a compiling skeleton. Bodies that are still `fatalError("unimplemented: unit X")` are that unit's work. Change a frozen signature only by agreement with the units that consume it. Adding members is fine.

`make lint build test` is green at the freeze. Stubs are only reached by new code paths, so the existing app and suites still run.

## Module graph (SegueCore)

```
Support ── ChordPro ── MusicTheory ── Diagrams ── Editing
                                                    |
                               Library (GRDB) ──────+
                                  |                  \
                  Setlists (Editing, Library)       LiveLayout (ChordPro, Editing, Library)  <- unit B
                                  |
                  Shows (Library, Setlists, Support)                                         <- unit A
```

`Shows` and `LiveLayout` are new targets. They are in the `SegueCore` product, the test target and the Tuist strict-settings list. `Setlists` now also depends on `Editing` (for `DisplayOptions`). SegueUI reaches everything through the `SegueCore` product.

## Conventions

- **Files stay canonical.** The index projects plays and tags but is never the source of truth. Every write is atomic (`FileSystem.writeAtomically`).
- **Layout on disk.** These follow the existing conventions, which differ from the spec's sketch:
  - `setlists/<slug>.setlist.json` (slug filenames as in phase 0; the JSON key stays `entries`)
  - `shows/<ulid>.show.json`
  - `timings/<ulid>.rehearsal.json`

  `LibraryRoot` has `showsDirectory`, `timingsDirectory`, `showSuffix` and `rehearsalSuffix`.
- **Time and IDs** always come from the injected `Clock` / `IDGenerator`, and dates are stamped with `SegueJSON.stamp`. Calendar dates (gig date) are `CalendarDay` ("2026-10-23"), which never shifts with the time zone.
- **Versioning** follows the sidecar rules everywhere: older versions migrate forward in memory, newer ones open read-only, and unreadable files are reported, never deleted.
- **Command naming.** The spec's `ShowCommand` is `LiveCommand`, which covers both gigs and rehearsals. Argument-free commands (bindable to keys, pedals and MIDI) are `LiveCommand`. Actions with arguments (from search, the request panel or the drawer) are `ShowAction`. `LiveCommand.showAction` bridges the two.
- **Show item state** lives on each `ShowItem`. `ShowRecord.items` is kept in performed order, which replaces the spec's separate `order` and `states`, so the "order is a permutation" invariant cannot drift. An item interrupted by "Play now" goes back to `pending`, and the event log records `jumped` / `requestPlayed` with `fromItemId`.
- **Sidecar key names.** Per-song live memory is the sidecar key `live` (the spec says `display`), because `displayPrefs` already holds the phase 1 toggles. The scroll nudge is stored as a multiplier, `scrollSpeedFactor`, not as an absolute speed, so it survives screen changes.

## Implemented at the freeze (shared by everyone; owners listed in "File ownership")

- **Setlist schema v2** (`Setlists/Setlist.swift`):
  - `SetlistItemID`.
  - `SetlistEntry { itemId, songId, overrides, note }`.
  - `Setlist { createdAt?, updatedAt?, venue?, date?, targetDuration? }`.
  - The v1-to-v2 migration gives entries deterministic item IDs (`SetlistItemID.migrated`), and `create`/`addSong` stamp the dates.
- **`SetlistOverrides.applied(to:songCapo:)`.** A per-setlist transpose/capo that keeps the concert key. It is paired with the new `RenderModel(document:options:userShapes:capo:)`.
- **Sidecar schema v3:**
  - `cues: [SongCue]` and `live: LivePrefs`, with lenient per-field decoding and the 2-to-3 migration.
  - `collapseRepeats` defaults to true.
  - The goldens were updated.
- **`CalendarDay`**, `LiveCommand`, `InputBindingTable` (default keys, the `bindings.json` format and merge), and `LiveSettings`.
- **UI shell:**
  - `ProficiencyMark`.
  - `LibrarySession.stores: LibraryStores` (library, setlists, an unloaded `ShowStore`, fs, clock, ids).
  - `LibrarySession` moved to `App/LibrarySession.swift`.
  - The `liveModePresentations(_:)` modifier, already applied in `MainView`.
  - Empty `AccessibilityID+Live` and `AccessibilityID+Setlists` extensions.
- Tests: `Tests/SegueCoreTests/Phase2ModelTests.swift`.

## Unit A - Show engine and persistence (Core)

It can be split into **A1** (the `Shows` module) and **A2** (Setlists and Library additions) if two agents are available. Their files don't overlap.

### A1 - `Packages/SegueCore/Sources/Shows/`

| Type / function | Contract |
|---|---|
| `ShowID`, `ShowRequestID`, `ShowItemID` (= `SetlistItemID`) | ULID wrappers. |
| `ShowKind` | `.gig` / `.rehearsal`. A rehearsal is never written to `shows/` and never in the gig log; it only emits `DurationSample`s. |
| `ItemOrigin`, `ItemState`, `ShowItem`, `ShowRequest`, `ShowEvent(.Kind)`, `GigDetails`, `ShowClosure` | The data model, documented in `ShowRecord.swift`. Events carry `itemId` (became current / acted on), `fromItemId` (left / interrupted) and `requestId`. |
| `ShowRecord` | `shows/<ulid>.show.json`, schema 1. `planned` is the setlist entries at start; `items` is in performed order; also `currentItemId`, `scrollPosition` 0...1, `requests`, `events`, `startedAt`/`updatedAt`/`endedAt`, `closure` and `gig` (prefilled venue from the setlist, date = setlist date or the start day). Derived: `isFinished`, `currentIndex`, `currentItem`, `queuedRequests`. |
| `ShowSongSource` | `cachedSong(id:)` reads memory only; `freshSong(id:)` re-reads from disk. `LibraryStore` conforms (through A2's `reloadSong`). |
| `ShowAction` | `next`, `previous`, `skipCurrent`, `skip`, `unskip`, `jump`, `playNow(SongID)`, `insertNext`, `addRequest(_:note:)`, `playNextRequest`, `playRequest`, `dropRequest`, `move(fromOffsets:toOffset:)`. The semantics are in the doc comments; see also open questions 4 and 5. |
| `ShowState { record, current: ShowSlot?, upNext: UpNext? }` | Replaced wholesale after each action. `ShowSlot.song` is the in-memory snapshot: taken when the item becomes current, never refreshed mid-song, and kept if the file disappears. `UpNext.request` wins over the next item. |
| `ShowEnvironment` | `store`, `songs`, `clock`, `ids`, `durations` sink and `scrollWriteInterval` (1 s). |
| `ShowController` (actor) | Methods: `start(setlist:kind:omitting:environment:)`, `resume(_:environment:)`, `state`, `perform(_:)`, `updateScrollPosition(_:)`, `flushScrollPositionIfDue()`, `end() -> ShowEnding`. A gig is written atomically on every action that changes state. Scroll is written with the next action or at most once per `scrollWriteInterval`. `omitting` starts missing-song entries as `skipped`. |
| `ShowEnding { record, diff?, gigLogEntry? }` | `diff` is nil when nothing changed (no sheet) and always nil for a rehearsal. |
| `ShowStore` (actor) | `load(root:)` loads shows and rebuilds the play projection; `save` writes atomically (a finished show also replaces its plays); also `show(id:)`, `gigLog()` (newest first), `updateGigDetails`, `delete`, `launchCheck() -> LaunchShowCheck { resumable?, autoClosed: [ShowEnding] }`. `staleInterval` is 12 h. A stale show is closed with `closure = .stale` and `endedAt = updatedAt`. |
| `PlayHistoryIndex` | Has `replacePlays(forShow:with:)` and `replaceAllPlays(_:)`. `LibraryStore` conforms. |
| `GigLogEntry(_ record:)`, `PlayedSong`, `ShowRecord.playedSongs` / `.playRecords` | The played list comes from events: start = the last time the item became current, end = advanced past it as played. These are also the phase 3 learned-duration input. |
| `ReorderDiff` | `compute(_:)` returns nil when the items are the planned entries in planned order with nothing inserted. Rows are `.unchanged` / `.moved(fromPosition:)` (not in the longest kept run) / `.inserted(origin)`. `entries(including:)` builds what Save writes. |
| `DurationSample`, `DurationSampleSink`, `RehearsalTimingStore` | One sample per completed song. Rehearsals write `timings/<run ulid>.rehearsal.json` atomically after each sample. `loadAll(root:fileSystem:)` is for phase 3. |
| `LiveCommand`, `InputBindingTable`, `KeyStroke`, `KeyModifiers`, `InputTrigger`, `InputBinding` | Implemented. Each command has a `scope` (`.show` / `.viewport` / `.chrome`), a `showAction` and a `title`. In `bindings.json`, a trigger is written `{"key": "k", "modifiers": ["command"]}`; phase 6 adds HID and MIDI trigger cases. |
| `LiveSettings`, `ChecklistItem` | Implemented value types. The UI persists them. |

### A2 - `Setlists/SetlistStore.swift`, `Library/LibraryStore+Phase2.swift`, `Library/SongIndex.swift`

| Function | Contract |
|---|---|
| `SetlistStore.rename`, `duplicate(_:name:)`, `delete`, `insertSongs(_:into:at:)`, `updateEntry(_:in:)`, `updateDetails(_:of:)`, `replaceEntries(_:in:)` | Each saves atomically and stamps `updatedAt`. `duplicate` gives fresh setlist and item IDs. `replaceEntries` is the diff sheet's Save. `SetlistDetails { venue, date, targetDuration }`. |
| `LibraryStore.updateMetadata(id:_ SongMetadata)` | Writes tags, proficiency, notes and cues to the sidecar and reindexes, so quick search matches tags. Tags are trimmed, blanks dropped, and case-insensitive duplicates removed. |
| `LibraryStore.updateLivePrefs(id:_:)` | Sidecar only, like `updateDisplayPrefs`. |
| `LibraryStore.allTags() -> [TagCount]` | Most used first. |
| `LibraryStore.reloadSong(id:)` | Re-reads one song's files now, updating its index row if it changed. Returns nil if the file is gone. |
| `LibraryStore.replacePlays(forShow:with:)`, `replaceAllPlays(_:)`, `playStats() -> [SongID: PlayStats]` | The projection behind "last played" and "times played". It is re-applied after `rebuildIndex()` from the in-memory copy. |
| `SongIndex` | Add tags to FTS (original and normalized columns) and a `plays` table. Bump `SongIndex.schemaVersion`; the index is a projection, so it rebuilds itself. Quick search: under 50 ms for 2,000 songs. |

**Tests (A):** integration-first, as the spec's test strategy describes:
- show JSON reloaded after each command, and the debounced scroll;
- show finished, then a gig log entry, then GRDB play stats;
- stale vs fresh resume with a `ManualClock`;
- an external edit or deleted file mid-show;
- the diff with Save and Discard (Discard leaves the setlist byte-identical);
- a property test over random command sequences: unique item IDs, at most one current, every file reloads.

## Unit B - Live layout engine (`Sources/LiveLayout/`, `SegueUI/Live/Layout/`)

| Type / function | Contract |
|---|---|
| `LayoutRequest { model, viewport, minLyricSize, zoom, collapseRepeats, columns?, cues, notes, style }` | Built by C from `RenderModel` (with overrides applied), the sidecar `live`/`cues`/`notes`, the item note and `LiveSettings.minLyricSize`. |
| `TextMeasuring`, `TextRole`, `FixedAdvanceMetrics` | Metrics are injected. `FixedAdvanceMetrics` (implemented) is for golden tests. |
| `LayoutStyle.stage` | Gutter 64, gap 12, column gap 48, min column width, max 3 columns, max lyric size, line height 1.25, chord ratio 0.82, spacing and fixed role sizes. B tunes the values in this one place. |
| `LayoutEngine.plan(_:metrics:) -> LayoutPlan` | Implements the spec's auto-fit steps 1-6 (largest size wins, ties go to fewer columns, columns break only at section boundaries, scroll below the minimum, zoom multiplies but never goes below the minimum). Deterministic and pure. |
| `LayoutPlan { lyricSize, chordSize, fit, columns, contentHeight, viewport, pageStops, lineCount }`, `overflow`, `needsScroll` | Fully positioned: `LayoutColumn` contains `LayoutBlock`s (label, `isChorusLabel`, `SectionTint`, content `.rows` / `.collapsed(line:differing:)` / `.notes`, cues), which contain `LayoutRow`s (baselines and `PlacedText` runs with `x`, `width`, `role` and `ChordKind`). C draws exactly this and never re-flows text. |
| `RepeatCollapser.collapse(_:enabled:) -> [CollapsedSection]` | The first occurrence is in full. A later equal section (normalized lyrics plus display chords) and every `{chorus}` repeat collapse to a reference with any differing items. |
| `ScrollSpeedModel.speed(_ ScrollSpeedInput) -> ScrollSpeed` | Speed is the overflow over (`{duration}` minus the lead-in). Without a duration it is estimated from `{tempo}`/`{time}` and `lineCount`; otherwise `defaultSpeed`. It is multiplied by `factor` (`LivePrefs.scrollSpeedFactor`), and `nudgeStep` is 1.1. |
| `AutoScroller` | A value type driven by injected instants (no timers). Methods: `offset(at:)`, `start`, `pause`, `restart`, `seek(to:at:)`, `setSpeed(_:at:)`, `setOverflow(_:at:)`. It never moves before `start`. |
| `StageTextMetrics` (SegueUI) | Core Text with the bundled Schibsted Grotesk faces and the monospaced face for verbatim lines. |
| `StageTypography.font(_:size:)` (SegueUI) | The same face table as SwiftUI `Font`s, so what C draws is exactly what B measured. |

**Tests (B):**
- Pure unit tests for golden layouts with `FixedAdvanceMetrics`: the minimum-font scroll fallback, `collapseRepeats` on and off, forced columns and zoom clamping.
- Scroll-speed derivation for duration, tempo and fallback.
- An `AutoScroller` timeline that reaches the bottom of a `3:00` song at about 180 s, and holds while paused.
- One acceptance test with `StageTextMetrics`: every fixture of up to 40 lines fits at 22pt on a 13" viewport.

## Unit C - Live view UI (`SegueUI/Live/**` except `Live/Layout/`)

C implements:
- **App surface:**
  - the `AppModel` phase 2 surface: `pendingResume`, `pendingReorderReviews`, `runShowLaunchCheck()` (call it after a library opens), `startShow(_:kind:)`, `resumePendingShow()`, `endPendingShow()` and `resolveReorderReview(save:including:)`;
  - the `liveModePresentations` modifier: the pre-show checklist, "Resume show?", the missing-songs check (move it out of `MainView`) and `ReorderDiffSheet` for `pendingReorderReviews.first`.
- **The stage:**
  - Replace `LiveViewModel` with a session model that owns a `ShowController`, the current `LayoutPlan` and an `AutoScroller`.
  - It dispatches every `LiveCommand`: `.show` goes to `perform`, `.viewport` drives scroll and zoom (and saves `LivePrefs` through `updateLivePrefs`), `.chrome` drives the overlays.
  - Key events become `KeyStroke`s and then `InputBindingTable` commands (bindings from Application Support `bindings.json`, with defaults otherwise).
- **Stage parts:** the header, progress dots, elapsed time and footer as in `brand.md` section 7. The status line fades in on mouse move. Cross-fade between songs (150 ms or less, none with Reduce Motion).
- **Overlays:**
  - the quick search overlay (Cmd-K or `/`): `LibraryStore.search`, never blocking, with the actions Play now, Add to requests and Insert next, and `ProficiencyMark` badges;
  - the request queue panel (`q`);
  - the set-order drawer (`s`): reorder, skip and un-skip.
- **Session plumbing:**
  - Scroll position goes to `updateScrollPosition`, plus a timer of about 0.5 s on `flushScrollPositionIfDue`.
  - Keep-awake through the existing `DisplaySleepAssertion`.
  - The stage stays the phase 0 borderless window.
- **Settings > Live** (a new Settings scene in `SegueApp.swift`): the minimum lyric size, the two Shortcut names with Test buttons and a guide paragraph, and the checklist rows. Settings persist as `LiveSettings` in UserDefaults.
- **Shortcuts and checklist:**
  - A `ShortcutRunner` port: the real one uses `NSWorkspace.open(shortcuts://run-shortcut?name=...)` and then re-asserts the stage as key; a recording fake is selected by a Debug launch argument for E2E #9.
  - A power-source reader for the "charger connected" row.
- **Rehearse run:** `startShow(_, kind: .rehearsal)` skips the checklist and Shortcuts, and passes a `RehearsalTimingStore` as the `durations` sink.
- **E2E:** the spec's E2E 1-9, using new Debug-only launch arguments in `LaunchOptions` (for example a test clock for auto-scroll E2E #3, and the fake Shortcut runner). C also owns the snapshot tests of the stage at 13" and 16".

## Unit D - Setlist builder and library metadata UI (`SegueUI/Setlists/**`, `Library/**`, `GigLog/**`, `Components/**`)

D implements:
- **Setlist builder**, layout **a** (`S3-Setlist-a`):
  - Left: the library column with search and filter (`SongFilter.parse`), rows showing key, tempo and length, "In set" dimmed, and a `+` button. Right: the set with columns #, title, key (after overrides), capo, length and start time.
  - Header: the name, running total vs target with a bar, and **Start show** (`app.startShow(setlist, kind: .gig)`) plus **Rehearse** (`.rehearsal`).
  - Drag from the library into the set; drag to reorder.
  - Per-item overrides and note; venue, date and target.
  - Create, rename, duplicate and delete setlists.
- **Library metadata:**
  - tags editing, `ProficiencyMark`, notes and cues editors, all saved through `updateMetadata`;
  - simple filters (tag chips, proficiency, key);
  - "last played" and "times played" from `playStats()`.
- **Gig log:** a sidebar destination with a list (newest first) and a detail view (played in order with request markers, skipped items, venue, date, notes and rating editing through `updateGigDetails`, and delete).
- **The real `ReorderDiffSheet`** (same `init`).
- **Core, pure:** `SongFilter` (`matches`, `parse`) and `SetlistTiming`, each with unit tests. `SetlistTiming` gives each row's start, the total of the known lengths and how many lengths are unknown (the build ruling: no made-up fallback length). Notation, through `ItemTiming.startText` and `SetlistTiming.totalText`:
  - a row with an unknown length shows `--:--` and adds nothing;
  - every later start is a lower bound, written `≥13:50`;
  - a lower bound of zero says nothing, so that start reads `--:--`;
  - the total reads `38:20`, `≥38:20 + 2 unknown`, or `2 unknown` when no length is known.

## File ownership

| Unit | Owns |
|---|---|
| A1 | `SegueCore/Sources/Shows/**`; tests `Tests/SegueCoreTests/Show*.swift`, `GigLog*.swift`, `Phase2ModelTests.swift` |
| A2 | `Setlists/SetlistStore.swift`, `Library/LibraryStore+Phase2.swift` (and the `LibraryStore.swift`, `SongIndex.swift`, `SongFiles*.swift` edits it needs); tests `SetlistStore*.swift`, `LibraryMetadata*.swift`, `PlayHistory*.swift` |
| B | `SegueCore/Sources/LiveLayout/**`, `SegueUI/Sources/SegueUI/Live/Layout/**`; tests `Tests/SegueCoreTests/LiveLayout*.swift`, `AutoScroll*.swift` |
| C | `SegueUI/Sources/SegueUI/Live/**` (except `Live/Layout/`), `App/AppModel.swift`, `App/UITesting.swift`, `Settings/**` (new), `AccessibilityID+Live.swift`, `App/Sources/**` (launch options, Settings scene), `UITests/E2ESupport.swift`, `UITests/SegueLive*.swift`, snapshot tests `SegueUI/Tests/SegueThemeTests/Live*.swift` |
| D | `SegueUI/Sources/SegueUI/{Setlists,Library,GigLog,Components}/**`, `SegueRootView.swift`, `App/LibrarySession.swift`, `AccessibilityID.swift` + `AccessibilityID+Setlists.swift`, `SegueCore/Sources/Library/SongFilter.swift`, `Setlists/SetlistTiming.swift`; tests `SongFilter*.swift`, `SetlistTiming*.swift`, `UITests/SegueSetlist*.swift`, `UITests/SegueE2ETests.swift` |

Shared rules:
- Sibling agents edit the same tree at the same time. Expect unrelated changes in `git status`, and don't treat them as conflicts.
- These are frozen: `Package.swift` (both), `Tuist/Package.swift`, `Project.swift` and the `Makefile`. A unit that needs a manifest change, a new module or a new dependency asks the orchestrator.
- Run `make generate` after adding files (the Tuist workspace globs sources).
- New fixtures go in `Tests/Fixtures/` under new names; never edit an existing fixture.
- `LibraryStore.swift`, `SongIndex.swift` and `SongFiles*.swift` are A2's for this stage. Another unit that needs a change there asks A2.
- `LibrarySession.swift` is D's. C reads `session.stores` and only touches it to add the loaded-shows wiring that `runShowLaunchCheck` needs.
- Each unit adds its accessibility IDs only in its own `AccessibilityID+*.swift` file, plus the UITests mirror in its own UITests files.
- The UI units (C, D) can build their views against the stubs, but their E2E needs A (and B, for C). Order integration so A and B land first. Until then, keep stub-reaching UI behind the actions that call it.
- Every unit runs `make lint build test` before handing back. C and D also run their `make e2e` subsets against a freshly reset library.

## Open questions (defaults chosen; confirm or override before the build)

1. **Requests and inserted songs in "Save to setlist".** Inserted rows are shown marked, each with an "Add to setlist" checkbox **unchecked by default**. Save writes the reordered planned items plus only the ticked inserted ones. The sheet still appears when the only change is inserted songs (the spec says "if order differs").
2. **Override transpose vs the song's saved view transpose.** A set override **replaces** the song's view transpose for that slot; nil inherits it. (The alternative is adding the two.)
3. **PgDn when the song fits or is at its bottom.** It does **nothing**; it never advances to the next song. Pedal users bind a separate key to `next`. (The alternative is turning the page into the next song at the end.)
4. **What `next` picks.** The first `pending` item from the **top** of the order, so songs passed over by Play now are revisited before later ones. This is what puts song 3 back after song 7 in E2E #6.
5. **Where `R` (play next request) puts the request.** **Before current**: current goes back to pending, so `next` returns to the interrupted song. This matches E2E #1's "9 played, 1 skipped, 1 request".
6. **Rehearsal.** No crash-safe resume, no reorder sheet, no pre-show checklist and no Shortcuts. Timings go to `timings/<ulid>.rehearsal.json`.
7. **Missing songs at start ("Perform without them").** They start as `skipped` and the gig log lists them as skipped.
8. **Gig rating scale.** 1-5, optional.
9. **Cue anchoring.** A section label (case-insensitive) plus an optional 1-based occurrence; nil means every occurrence. A cue whose label no longer exists is shown in the notes block.
10. **"Smart filters" in the brief vs the spec.** The spec puts smart and saved filters in phase 3 (a non-goal here). D builds **simple** filtering only: typed tokens in the search field ("ready, upbeat, key G") plus chips. Nothing is saved.
11. **Unknown song length in the builder.** Superseded by the build ruling: never estimated. The row shows `--:--`, later starts are lower bounds (`≥13:50`) and the total reads `≥38:20 + 2 unknown` (see unit D's `SetlistTiming` notation above).
12. **Minimum lyric size range** in Settings: 16-48pt (default 22).
13. **`bindings.json` location.** Application Support (per device; pedals are per machine). There is no editor UI in phase 2; defaults apply when the file is missing or malformed (the error is reported).
14. **Stage presentation.** The stage stays the phase 0 borderless window that hides the menu bar and Dock (the spec's "full screen" step reads as this). The "Shortcut from full screen" verification in `0-walking-skeleton.md` is **still open and needs one manual run by Ryan**. C re-asserts the stage window as key after `NSWorkspace.open(shortcuts://...)` regardless, and confirms with the real in-app call.
15. **Stale show `endedAt`.** It is set to the show's last update, not to the launch time.
16. **Play now on a song already in the set** jumps to its first pending item and doesn't move it, so a show whose only change is jumps raises no reorder sheet.
17. **Save after the setlist was deleted or made read-only during the show.** Save is disabled in the sheet with a reason, and only Discard is offered (the show and gig log keep their snapshot).
