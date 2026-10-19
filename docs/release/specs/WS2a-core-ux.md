# WS2a - Core UX for 0.5

Implementation spec for one focused build session. Read it standalone; everything needed is here or linked.

- Canonical rulings: `docs/release/decisions.md` R15 (import, Delete Song, Trash, Help, About, window reopen, Setlist menu, `?` overlay), R16 (Show in Finder, setlist builder undo, restore selected song/section), R17 (autosave, Cmd-S a confirming no-op), R20 (review prompt; WS2b owns it, mentioned only for the "never during a show" rule), R21 (help docs are web pages at segue.ryandsilva.dev/help), R29 (site pages), R30 (copyright string), R36 (Settings > Appearance, owned by WS2b), R41 (Xcode 27.1 / Swift 6.4).
- Resolved questions: `docs/release/open-questions.md` A18-A35 and A39 (each took its **Recommend** option) and B-10 to B-17 (stated defaults), plus the section 4 cross-spec resolutions I-2, I-3, I-5, I-6, I-10, I-11 and I-16. Each is applied inline below and tagged with its ID, e.g. *(A23)*.
- Research behind them: `docs/release/research/08-polish-features.md` (menus, About, cheat sheet, Trash, import), `docs/release/research/03-review-risk.md` F1/F2 (privacy link in app, main window reopen: a known Guideline 4 rejection).
- Project rules still in force: files are canonical, the index is a rebuildable projection, every write atomic (`docs/phases/2-interfaces.md` "Files stay canonical"); integration-first testing (`docs/decisions.md` "Testing").
- **Status: final, implementation-ready.** Every decision is closed; section 9 lists none open.

Prerequisite: WS1 steps 1-5 have landed (bundle IDs, `Version.xcconfig` / Info.plist with `MARKETING_VERSION = 0.5` and copyright `© 2026 Ryan Rony Dsilva` per R30, `#if DEBUG` launch options per B-7). WS2a is the app-shell owner in phase 2 of the build order (`open-questions.md` section 5): it runs alone on `AppModel`, `SegueRootView`/`SegueCommands`, `SegueApp.swift`, `LaunchOptions.swift`; later workstreams fill the hooks it reserves instead of editing menus.

Out of scope here (owned elsewhere, referenced only):
- WS1: version/build numbers and the copyright string in Info.plist (About reads them), signing, logging, Gig Mode Shortcuts, the Settings > Live pane text (`LiveSettingsView.swift`).
- WS2b: first run and Welcome library (fills `AppHooks.showWelcome`), What's New sheet (fills `AppHooks.showWhatsNew`; reads the bundled changelog), TipKit, review prompt, the Settings window host and its panes (see 3.13), `.cho` UTType / Open With / Quick Look (all reuse WS2a's importer and extension list), Export Library Archive (fills `AppHooks.exportArchive`), the accessibility pass.
- WS3: the bug report and feature request flows (fills `AppHooks.reportProblem` / `requestFeature`), the Settings > Privacy pane.
- WS4: the web pages the links point at, and the changelog pipeline. WS5: store metadata and the App Store app ID (`SegueLinks.appStoreID`).

Shell note for agents: `cat` is aliased to eza on this machine and can hang; use `command cat` or file-reading tools.

Sibling agents may be editing other files in this tree at the same time; expect unrelated changes in `git status` and do not treat them as conflicts.

---

## 1. Goal

Ship the core desktop affordances a reviewer and a gigging musician expect from a polished Mac app, without weakening the files-are-canonical model:

1. Songs get into the library in-app (drag and drop, File > Import) and leave it in-app (Delete Song).
2. Nothing is ever destroyed: every delete (song, setlist, gig) goes to the Trash and can be undone.
3. Edits save themselves (autosave); Cmd-S only confirms.
4. Every command lives in the menu bar: full Help menu, Setlist menu (incl. Add Selected Song to Setlist), Window > Segue Library, About panel with credits.
5. The keyboard is discoverable: a `?` overlay on stage, Help > Keyboard Shortcuts in the main window.
6. Show in Finder, undo/redo for the setlist builder and song metadata, and the selected song/section restored across launches.
7. All external URLs live in one file.

---

## 2. Current state (code facts this spec builds on)

| Area | Today | Evidence |
|---|---|---|
| Scenes | `WindowGroup(id: "segue.main")`, `Window` Acknowledgements (`.commandsRemoved()`, restoration disabled), `Settings` | `App/Sources/SegueApp.swift` |
| Menus | App menu: "Acknowledgements" after About. File: New Song Cmd-N **replacing `.newItem`** (this removes "New Window", so a closed main window cannot be reopened). `CommandMenu("Library")`: Refresh Cmd-R, Rebuild Index, Choose Library Folder. No Help group (default "Segue Help" dead-ends), no Setlist menu. | `SegueUI/SegueRootView.swift` `SegueCommands` |
| Save | Editor is a mode (Edit button) with Cancel / Save (Cmd-S, `canSave`). Saves go through `LibraryViewModel.updateSong(basedOn: RevisionBox)`; conflicts raise a modal alert (Reload / Overwrite / Save as Copy / Keep Editing). Navigation, window close and quit with unsaved edits prompt Save / Discard / Cancel. | `Editor/SongEditorView.swift`, `Library/LibraryViewModel.swift`, `Library/LibraryViewModel+SaveConflict.swift`, `Editor/UnsavedChangesGuard.swift`, `SegueRootView.swift` `MainView` alerts |
| Editor undo | Its own `UndoManager` per editor (`SourceEditorController.undoManager`), shared by text and visual modes. It is not the window's undo manager. | `Editor/SourceEditorController.swift:27`, `VisualEditorController.swift:273` |
| Every save | `updateSong` then `await reload()` (all songs, tags, play stats, re-search). Fine for a click; too heavy for autosave on every pause. | `LibraryViewModel.updateSong` |
| External changes | Picked up only by Refresh (Cmd-R) or at open. No file presenter, no refresh on app activation. | `LibraryStore.refresh()` |
| Song create | `LibraryStore.createSong(source:)`: slug from `{title}` (`Slug.make`, fallback `untitled`), de-duplicated `-2`, `-3`; new sidecar (new ULID); index upsert. File name never changes afterwards. | `Library/LibraryStore.swift`, `Support/Slug.swift` |
| Song files | Only `songs/*.cho` are scanned (`LibraryRoot.songExtension = "cho"`). Non-UTF-8 text loads read-only with a guessed encoding. | `Library/SongFiles.swift`, `SongFiles+Scan.swift` |
| Deletes | Songs: no delete at all. Setlists: `SetlistStore.delete` uses `removeItem` (permanent). Gigs: `ShowStore.delete` uses `removeItem` (permanent) and clears its plays. Both behind confirmation dialogs. | `Setlists/SetlistStore.swift:240`, `Shows/ShowStore.swift:222`, `Library/MainSidebar.swift`, `Setlists/SetlistBuilderView.swift`, `GigLog/GigDetailView.swift` |
| FileSystem port | `writeAtomically`, `removeItem`, `moveItem`, coordinated. No trash. Core tests use `LiveFileSystem` on temp dirs (real IO). | `Support/FileSystem.swift` |
| Setlist edits | `SetlistsViewModel.mutate` writes through `SetlistStore` and reloads; no undo. `add(_:to:)` appends a song (repeats allowed). Setlists are loaded once and never re-read from disk. | `Setlists/SetlistsViewModel.swift`, `Setlists/SetlistStore.swift` |
| Song metadata | Tags, proficiency, notes and cues: `LibraryViewModel.updateMetadata(id:_:)` / `editMetadata(id:_:)` -> `LibraryStore.updateMetadata(id:_:)` (`SongMetadata` value, sidecar write), then `reload()`; no undo. | `Library/LibraryViewModel+Metadata.swift`, `Core/Library/LibraryStore+Phase2.swift`, `Library/SongMetadataViews.swift` |
| Stage keys | `InputBindingTable.defaults` + optional `bindings.json`; `LiveKeyInput` local monitor; character keys carry Shift (`"?"` arrives as `"?"`). Overlays: `.search`, `.endConfirm`. Status line lists the main keys as hard-coded text. | `Shows/InputBindings.swift`, `Live/LiveKeyInput.swift`, `Live/StageChrome.swift` |
| About | Standard panel from Info.plist: `0.1.0` (1), "Copyright 2026 Ryan D'Silva". No credits. | `Project.swift:109-115` |
| Restoration | System window restoration only; no stored section or selection. | `SegueApp.swift` |
| Precedent | Gig details already autosave: 600 ms debounce in `.task(id: draft)`, flush on disappear. | `GigLog/GigDetailView.swift` |
| E2E | Library at `/private/tmp/segue-e2e/` (the only path the Debug sandbox exception allows); `E2E.launch` adds `-ApplePersistenceIgnoreState YES -SegueUITesting YES`; test doubles via launch options (`-SegueShortcutLog`, `-SegueBindingsPath`, ...). | `UITests/E2ESupport.swift`, `App/Sources/LaunchOptions.swift`, `App/Segue-Debug.entitlements` |

---

## 3. Behaviour per feature

### 3.1 URL constants (one place)

New `Packages/SegueUI/Sources/SegueUI/App/SegueLinks.swift`, a caseless `public enum SegueLinks` with `static let` `URL`s. Nothing else in the codebase may spell `segue.ryandsilva.dev` or the support address (add a SwiftLint `custom_rules` regex for `ryandsilva\.dev|apps\.apple\.com` excluding this file, so drift fails `make lint`).

| Constant | Value | Used by |
|---|---|---|
| `site` | `https://segue.ryandsilva.dev` | About credits; WS2b prefixes changelog `help` paths with it (I-2) |
| `help` | `https://segue.ryandsilva.dev/help` | Help > Segue Help (R21) |
| `privacy` | `https://segue.ryandsilva.dev/privacy` | Help > Privacy Policy (5.1.1(i)); WS3 Privacy pane |
| `terms` | `https://segue.ryandsilva.dev/terms` | Help > Terms of Use (site terms; their section 1 links Apple's standard EULA, which governs the app, R7) |
| `support` | `https://segue.ryandsilva.dev/support` | About credits |
| `changelog` | `https://segue.ryandsilva.dev/changelog` | What's New fallback hook (B-14); WS2b's "All Release Notes" link |
| `feedback` | `https://segue.ryandsilva.dev/feedback` | Request a Feature fallback hook (redirects to the board, R29) |
| `acknowledgements` | `https://segue.ryandsilva.dev/acknowledgements` | About credits (A34). *Removed 2026-10-18: no app UI links it; see 3.6.* |
| `supportEmail` | `mailto:segue@ryandsilva.dev` (R28) | Report a Problem fallback hook |
| `appStoreID` | `String?`, `nil` until WS5 creates the App Store Connect app record and fills in the numeric Apple ID | Gates Help > Rate Segue on the App Store (A35) |
| `writeReview` | computed `URL?`: `macappstore://apps.apple.com/app/id<appStoreID>?action=write-review`, `nil` while `appStoreID` is `nil` | Help > Rate Segue on the App Store |

There is **no** remote changelog feed constant: What's New reads only the changelog bundled in the app and never fetches it over the network (A16, I-3). The bundled file is WS4's generated `website/changelog.json` (original `content/changelog.json`, schema per WS4, I-2), added to the app's resources by WS2b through `Project.swift`; WS2a does not touch it.

Also expose `helpPage(_ path: String) -> URL` for deep links (e.g. `helpPage("keyboard")` -> `/help/keyboard`). Only paths and anchors listed in WS4's URL and anchor table may be used (I-16); WS4's link checker is the contract. WS2b, WS3 and WS4 specs reference this file instead of defining their own.

All links open in the default browser through a `WorkspaceActions` port (3.12), never an in-app web view (keeps the age-rating "unrestricted web access" answer at No, research 03 F16).

### 3.2 In-app import (R15)

**Entry points**
- File > Import Songs… (Shift-Cmd-I): `NSOpenPanel`, multiple selection, files and folders, `allowedContentTypes` built from the accepted extensions.
- Drag and drop onto the Library destination: the song list column (including its empty state) and the detail pane only. Drop highlight: a 2pt `cue` inset border on the list column plus "Drop to import" label. Not the builder library column, sidebar or Dock icon *(A25)*. The Dock / Open With path for a file outside the library is WS2b's UTType work and copies the file in through this same importer *(A31)*.
- The empty-library state gains "Import Songs…" beside "New Song" and the line "or drop ChordPro files here".
- Disabled (menu greyed, drop refused with no highlight) while performing or while no library is open.

**Accepted files** *(A24, I-10)*: extensions `.cho`, `.chopro`, `.chordpro`, `.pro`, `.txt` (case-insensitive). `.crd` is not accepted in 0.5 (it is mostly chords-over-lyrics and belongs with phase 3's converter). The list lives in one place in SegueCore, `SongFileTypes` (new, `Core/Library/SongFileTypes.swift`): `importExtensions = ["cho", "chopro", "chordpro", "pro", "txt"]` used by import and the open panel, and `claimedExtensions = ["cho", "chordpro", "chopro"]` which WS2b's UTType declaration and Open With routing use (`.pro` and `.txt` are too generic to claim, but `.pro` is imported). Anything else is skipped with reason "Not a ChordPro or text file". Folders are expanded recursively, hidden files and packages skipped, at most 500 files per import; beyond that the rest are skipped with "Import limit of 500 files reached" *(A25)*.

**Per file, in order** (all in Core, `LibraryStore.importSongs`):
1. Read bytes through `FileSystem.readData` (coordinated). Unreadable: skip, "Could not be read: <reason>".
2. Reject > 1 MB ("Too large to be a song") and data containing a NUL byte ("Not a text file").
3. Decode: UTF-8 (strip a leading UTF-8 BOM). Otherwise decode with `SongFiles.decodeText`'s fallback chain and write the new library file as UTF-8, noting "Converted from Windows Latin 1" (the detected encoding's name) in the summary *(B-11)*. The source file is never modified. Line endings and all other bytes are kept as they are (byte round-trip ruling).
4. Content is not converted: `.txt` chords-over-lyrics is imported as-is (it renders as lyrics until phase 3's converter) *(A24)*.
5. Skip if a song with the same content hash is already in the library or earlier in this batch: "Already in your library as “<title>”" *(A25)*. A file dropped from the library's own `songs/` folder always hits this.
6. Slug: `Slug.make(from: {title})`; when the song has no `{title}`, from the source file name without extension (not `untitled`); then `Slug.unique` against loaded slugs and `SongFiles.isTaken` (`.cho` or sidecar present). Do not inject a `{title}` into the content; the list shows the slug-derived name as its title *(A25)*.
7. Sidecar: always a fresh sidecar, new ULID, `createdAt = updatedAt = now`. If `<stem>.segue.json` sits next to the source and decodes as an editable sidecar, copy its tags, proficiency, notes, cues, displayPrefs and live prefs, but never its ID *(B-12)*.
8. Write `.cho` then sidecar (`SongFiles.write`, same order as `createSong`), upsert the index row, add to `songs`.

Failures are per file; one bad file never aborts the batch. A write failure mid-batch keeps what was already imported.

**Result**: `ImportSummary { imported: [SongRecord], skipped: [ImportSkip { fileName, reason }], converted: [String] }`.
- UI selects the first imported song (after flushing any pending autosave) and shows a non-error summary bar at the bottom of the window (reuse the error banner's layout, neutral icon): "Imported 3 songs." / "Imported 3 songs. 1 skipped." with a "Details" popover listing every skipped file and reason (same style as `LoadIssuesList`). Nothing imported and all skipped: same bar, "No songs imported" + Details.
- Undo: Edit > Undo Import (window undo manager) moves the imported files to the Trash through the Delete Song path (3.3); Redo restores them.

**Sandbox**: panel and drag URLs carry a sandbox extension for the process lifetime; read them immediately (within the drop/panel callback's task). The library folder is already writable via its bookmark. In Debug E2E the sources live under `/private/tmp/segue-e2e/import-src/` (inside the exception path).

**Relation to phase 3**: phase 3 (Personal flavor first) will route import through the always-on review sheet ("nothing reaches the library without Accept"). Ruled *(A29)*: when phase 3 lands, direct import stays for files that are already ChordPro; only files that need conversion go through the review sheet. Build `importSongs` so that review step can sit between "decoded" and "written" (split into `prepareImport(urls) -> [ImportCandidate]` and `commitImport([ImportCandidate])`); phase 3 routes only conversion candidates through review.

> *Superseded (phase 3 ships in 0.5): R61/R62/R76: phase 3 ships in both flavours; `.crd` and `.txt` that need conversion go through the review sheet (A29 still holds for files that are already ChordPro); handled in P3-4 (`docs/phases/3-workstreams/P3-4-paste-import-ui.md`).*

### 3.3 Delete Song and Trash for every delete (R15)

**Core: `FileSystem.trashItem(at:) throws -> URL`** returns the item's new URL in the Trash. `LiveFileSystem` gets an init parameter `trash: TrashLocation = .system`:
- `.system`: `FileManager.trashItem(at:resultingItemURL:)` inside a coordinated write with `.forDeleting`.
- `.directory(URL)`: moves into that folder (unique name if taken). Used by every Core test (so `swift test` never fills Ryan's Trash) and by E2E through `-SegueTrashPath`; the real Trash is covered by one Core test and the manual check in 6.4 *(B-15)*.
- If `.system` trashing fails because the volume has no Trash (some network volumes), throw `FileSystemError.trashUnavailable(url)`; the UI says "This volume has no Trash, so Segue did not delete it." Never fall back to permanent removal.

New `Support/Trash.swift`: `public struct TrashReceipt: Sendable, Equatable { public var items: [TrashedItem] }`, `TrashedItem { original: URL, trashed: URL }`, and `restore(receipt, fileSystem)` that moves each item back with `moveItem` (fails per item if the original path is taken or the trashed file is gone, e.g. Trash emptied: "It is no longer in the Trash.").

**Songs** (`Library/LibraryStore+Trash.swift`):
- `deleteSong(id:) throws -> TrashReceipt`: trash `.cho` **first**, then the sidecar if present. Rationale: if the sidecar trash fails, a stray sidecar without a `.cho` is harmless (scans only enumerate `.cho`; it just blocks that slug), whereas a `.cho` left without its sidecar would be re-adopted with a **new** ID and setlists would lose it. A sidecar failure is reported but the song is still deleted. Then remove the index row (`IndexChanges.deletes`) and the `songs` entry. Read-only songs (newer schema, unreadable sidecar, not UTF-8) can be deleted. Plays stay in show files; `playStats` for an unknown ID is ignored.
- `restoreSong(_ receipt:) throws -> SongRecord?`: moves files back. If the original slug is now taken, restore both files under `Slug.unique(slug)` (the pair keeps the same new stem). Then `refresh()` and return the record by the sidecar's ID, so setlists resolve it again.

**Setlists**: `SetlistStore.delete` trashes instead of `removeItem` and returns `TrashReceipt` (a file already gone is forgotten, as today, with an empty receipt). New `restore(_ receipt:) throws -> Setlist?` moves the file back and loads that one file (duplicate-ID rule as in `load`).

**Gigs**: `ShowStore.delete` trashes and returns `TrashReceipt` (still refuses read-only shows, still clears the show's plays). New `restore(_ receipt:) async throws -> ShowRecord?` moves it back, decodes it, re-adds it and calls `playHistory.replacePlays(forShow:with:)` from the record.

**UI entry points for Delete Song**
- Song row context menu: "Move to Trash".
- Song detail pane header: a "…" menu next to Edit with "Show in Finder", "Move to Trash".
- File > Move to Trash (Cmd-Delete), enabled only when the **song list is focused** with a selection and no editor is open (published with `.focusedSceneValue`, never a global flag), so Cmd-Delete keeps its text meaning (delete to line start) in the editor and in every text field.
- Disabled while performing.

**Confirmation** *(A23: confirm only when there is a hidden consequence, like Finder's Move to Trash)*:
- Song used by one or more setlists: a confirmation dialog, title "Move “<title>” to the Trash?", message "It is in 2 setlists: Friday at Blue Frog, Sunday Brunch. They will show it as missing. You can undo this." (names every referencing setlist, sorted as in the sidebar), buttons "Move to Trash" (destructive) and Cancel (default).
- Song used by no setlist, any setlist, any gig: **no confirmation**; the item moves to the Trash at once and Edit > Undo brings it back.
- The existing confirmation dialogs for setlist delete (`MainSidebar`, `SetlistBuilderView`) and gig delete (`GigDetailView`) are removed; the menu and context-menu items are renamed "Move to Trash".

**After delete**
- Song: if it was selected, selection moves to the next row (else previous, else none). If its editor is open, **flush the pending autosave first, then trash** *(B-10)*, so the trashed file holds the latest text; then close the editor. If that flush fails (conflict or write error), do not trash: show the editor's "Not saved" state and the error, and leave the song in place. Setlists referencing it show the existing "Missing song / No longer in the library folder" row. The pre-show warning already removes missing songs at show start.
- Setlist: if shown in the builder, section goes to Library (existing `followSetlistSelection`).
- Gig: gig log selection clears; play stats reload (`onPlaysChanged`).

**Undo** (window `UndoManager`, action names "Move to Trash" / "Move Setlist to Trash" / "Move Gig to Trash"): Undo restores via the receipt and reselects the item; Redo trashes again (new receipt). Undo failure (Trash emptied, path taken and unrecoverable) shows the error banner and drops the action. Clear these actions when the library switches.

### 3.4 Autosave (R17)

**Model**: the editor stays a mode (Edit opens it), but its text is persisted automatically. Replace the Cancel / Save toolbar pair with a single **Done** button (closes the editor after flushing). No "Revert to Opened" command: the editor's undo stack, which survives saves, covers the session, and the Trash and Time Machine cover the rest *(A21)*.

**When a save runs** (`SongEditorViewModel` owns an `AutosaveScheduler` driven by the injected `Clock`, so tests can control time):
- 1.0 s after the last text change (idle debounce), and at most 5 s after the first unsaved change during continuous typing (max latency). Both values live in one `AutosavePolicy` constant (`UI/Support/AutosavePolicy.swift`, `idle = .seconds(1)`, `maxLatency = .seconds(5)`), used by the song editor **and** gig details *(B-13)*: `GigDetailView` drops its hard-coded 600 ms sleep and drives the same `AutosaveScheduler` (flush on disappear unchanged). `-SegueAutosaveDelay` overrides `idle` for both.
- Immediately ("flush") on: song switch, section switch, Done, window close, quit, app resign-active, Start Show / Rehearse (so the stage reads the saved file), library switch, Import, Delete of another song, Cmd-S.
- Display-prefs and live-prefs writes keep their current immediate behaviour and ordering (`prefsTask` lands before a source save).
- One save in flight at a time; changes made during a save schedule the next one (today's `commit` already keeps text typed mid-save as unsaved).

**What a save does**: the existing conflict-checked path, `LibraryStore.updateSong(id:source:basedOn:)` with the editor's `RevisionBox`. On success the VM applies the returned record **incrementally** (new `LibraryViewModel.applySaved(_ record:)`: replace the record in `catalog`, `catalogIndex` and `results`, re-sort if the title changed, refresh `tags` only if the sidecar tags changed) instead of `reload()`. A full `reload()` still runs on Done. Budget: autosave must not move `testKeystrokeLatencyOn200LineSong` or `EditorPerformanceTests`.

**New songs** *(A18)*: the first autosave creates the file once the text is non-blank (slug from the title at that moment, as `createSong` does today). While that same editor session stays open, a later change of `{title}` renames the file pair to the new slug on the next save (`LibraryStore.renameSong(id:toSlugFor:)`: unique slug, move `.cho` then sidecar, update index path; the ID is unchanged, so setlists are unaffected). Once the editor closes, the file name is stable forever (existing rule). Blank text on Done creates nothing.

**Read-only songs** never open an editor (unchanged), so never autosave.

**Status UI (replaces the dirty-state UI)** *(A22)*:
- Navigation subtitle: "Saved" (idle and clean), "Saving…" (in flight), "Not saved" (failure or conflict). The word "Edited" goes away; the pending-debounce state is shown only by the window's standard edited dot (`NSWindow.isDocumentEdited` true while anything is unsaved), which clears on save.
- `canSave` / the Save button are deleted. `AccessibilityID.editorSave` and `.editorCancel` are replaced by `editorDone` and a new `editorSaveStatus` (the subtitle's accessible value, for E2E).
- The modal Save / Discard / Cancel prompt on navigation is deleted. Navigation now flushes and proceeds. It only blocks when the flush fails (next bullet).

**Failures and conflicts (files are canonical and may change on disk)**:
- Proactive pickup *(A19)*: on `NSApplication.didBecomeActiveNotification` the app runs `LibraryStore.refresh()` (stat-based, cheap) and reloads songs, and reloads setlists (3.9, B-16), so edits made in another editor appear without Cmd-R. Skipped while performing. Phase 7's file presenter work stays phase 7.
- Clean editor (nothing unsaved) whose song changed on disk (found by that refresh or Cmd-R): reload the editor text silently through `sourceController.replaceAll` (one undoable step named "Reload from Disk") and move the `RevisionBox` to the new revision.
- Dirty editor and the save hits `LibraryError.conflict`: autosave pauses for that song (no retries that would hammer the conflict), the subtitle reads "Not saved", and an **inline conflict bar** appears at the top of the editor (replacing today's modal alert) *(A19)*: "“<title>” was changed in another app. Your edits are not saved." with Reload (drop my edits), Overwrite, Save as Copy; for `.deleted`: "…was deleted in another app" with Save as New Song; for `.metadataChanged`: Reload, Save as Copy. Typing continues to work; nothing is written until the user picks. Resolution logic is today's `resolveSaveConflict` minus `.cancel`.
- Other save errors (disk full, permission lost): subtitle "Not saved", the error in the editor's existing `errorMessage` banner, retry on the next change and on every flush trigger.
- Navigation, window close or quit while a conflict or failure is unresolved: one prompt, "Your edits to “<title>” aren't saved", buttons Save as Copy (default), Discard Edits (destructive), Cancel. This is the only remaining unsaved-edits prompt.
- Quit (`applicationShouldTerminate`): if nothing is pending, terminate now. If a save is pending or in flight, return `.terminateLater`, flush, then reply true; if the flush fails, show the prompt above. While anything is unsaved, call `ProcessInfo.processInfo.disableSuddenTermination()` (balanced on save).
- Stage: the main window is inert while performing (existing). Start Show flushes first; if the flush fails, the show still starts and the stage shows the last saved version (the show already snapshots songs from disk), and the editor keeps the conflict bar.

**Cmd-S** *(A20)*: File > Save stays in the menu (Cmd-S), enabled whenever a library is open. In the editor it flushes now and briefly shows "All changes saved" in the subtitle (1.5 s, then "Saved"); outside the editor it shows the same text as a 1.5 s transient in the bottom bar. It never opens a panel and never creates anything.

**Other editors already autosave**: gig details (moved onto `AutosavePolicy`, above). Notes/cues sheet keeps its explicit Save (it is a sheet with Cancel, not a document) - out of scope.

### 3.5 Menus

Implemented as separate `Commands` types under `Packages/SegueUI/Sources/SegueUI/App/Commands/`; `SegueCommands` composes them. Every command that needs the main window and finds it closed reopens it first (3.5.5). All key equivalents come from one `MenuShortcuts` table that the Keyboard Shortcuts window (3.7) also reads, so the help can never drift from the menus.

#### 3.5.1 App menu
About Segue (custom options, 3.6) · separator · Settings… (Cmd-,) · standard items. "Acknowledgements" moves out of the App menu into Help *(A34)*. Settings… opens WS2b's Settings window (3.13).

#### 3.5.2 File
New Song (Cmd-N) · Import Songs… (Shift-Cmd-I) · Export Library Archive… (no shortcut; calls `AppHooks.exportArchive`, hidden while `nil`, filled by WS2b) · separator · Show in Finder (Opt-Cmd-R) · Move to Trash (Cmd-Delete) · separator · Close (Cmd-W, system) · Save (Cmd-S, confirming, 3.4). `CommandGroup(replacing: .newItem)` stays (no "New Window"); `CommandGroup(replacing: .saveItem)` provides Save.

#### 3.5.3 Setlist (new `CommandMenu("Setlist")`, placed after Library)
| Item | Shortcut | Enabled when | Action |
|---|---|---|---|
| Start Show | Cmd-Return | a setlist builder is shown, not performing, not starting, setlist has at least one resolvable song | flush autosave, `app.startShow(setlist, kind: .gig)` (same path as the builder button, incl. pre-show checklist) |
| Rehearse | Opt-Cmd-Return | same | `.rehearsal` |
| separator | | | |
| New Setlist… | Shift-Cmd-N | library open, not performing | opens the existing `SetlistNameSheet(.create)` (lift its presentation state from `MainSidebar` into `LibrarySession` so the menu can trigger it) |
| Add Selected Song to Setlist ▸ | none | a song is selected (focused song list, or the song detail/editor shown), library open, not performing, no sheet up | submenu, below |

*(A33, option b.)* New Setlist lives only in this menu, not also in File. Start Show and Rehearse are disabled outside a builder (no "Start Show ▸ <setlists>" picker). The builder's Start show / Rehearse buttons show the shortcuts in their `.help` tooltips.

**Add Selected Song to Setlist ▸** (a keyboard and VoiceOver path for adding songs without dragging, which WS2b's accessibility audit relies on):
- One item per setlist, in the sidebar's order, titled with the setlist name. Read-only (newer-schema) setlists are listed but disabled. A setlist that already contains the song shows a checkmark (`state: .on`); choosing it still appends another copy, matching `SetlistsViewModel.add(_:to:)` and the builder's `+`.
- No setlists: a single disabled item "No Setlists".
- Action: flush any pending autosave of that song, then `SetlistsViewModel.add(songID, to: setlistID)` (appends at the end). Registers the undo action "Add Song" on that setlist's undo target (3.9). Selection and section do not change; the bottom bar shows a 1.5 s transient "Added “<song>” to <setlist>." (same transient style as Cmd-S outside the editor, 3.4).
- The same submenu appears as "Add to Setlist ▸" in the song row context menu and in the song detail pane's "…" menu (built from one `AddToSetlistMenu` view).

#### 3.5.4 Library (existing)
Refresh (Cmd-R) · Rebuild Index · separator · Show Library in Finder (new, reveals the root folder) · Choose Library Folder…

#### 3.5.5 Window: reopen the main window (review risk F2)
*(A32, I-11)* Change the main scene from `WindowGroup(id: "segue.main")` to a **single** `Window("Segue Library", id: "segue.main")` with `.keyboardShortcut("0", modifiers: .command)` on the scene. SwiftUI then lists it in the Window menu as "Segue Library" with Cmd-0, and choosing it (or `openWindow(id: "segue.main")`) brings the one window back instead of creating a second (a second main window would break `PendingEditsGuard`'s single-window assumptions; WS2b drops its multi-window case accordingly). The title bar keeps showing the view's `navigationTitle`, not the scene title. If spike 0d shows the automatic Window menu entry missing, duplicated or without Cmd-0, fall back to `.commandsRemoved()` on the scene plus an explicit `CommandGroup(before: .windowList)` item "Segue Library" (Cmd-0) that calls `openWindow(id: "segue.main")`; either way exactly one such item exists. There is no File > New Window. Also implement `applicationShouldHandleReopen(_:hasVisibleWindows:)` in `SegueAppDelegate`: no visible windows -> reopen the main window. Keep `.restorationBehavior` default for the main window. Cmd-0 is free in the main window; on stage the local key monitor handles Cmd-0 (reset zoom) before the hidden menu, so no clash. Verify restoration still reopens the window at its last frame after this change.

#### 3.5.6 Help (`CommandGroup(replacing: .help)`)
WS2a owns this canonical list (I-5); WS2b and WS3 never edit `HelpCommands` and only fill hooks. Names are exact (other specs, the website and the review notes quote them):

1. Segue Help (Cmd-?) - opens `SegueLinks.help`. Never the system "Help isn't available" dead end.
2. Keyboard Shortcuts (Cmd-/) - opens the Keyboard Shortcuts window (3.7).
3. Welcome to Segue… - calls `AppHooks.showWelcome` (WS2b reopens its Welcome sheet; B-17). Hidden while the hook is `nil` (the default until WS2b lands).
4. What's New in Segue - calls `AppHooks.showWhatsNew` (WS2b's sheet, bundled changelog only, A16). Default hook until WS2b lands: opens `SegueLinks.changelog` *(B-14)*.
5. separator
6. Report a Problem… - `AppHooks.reportProblem` (WS3, Sentry User Feedback). Default hook: `mailto:` support with subject "Segue <version> (<build>) problem" *(B-14)*.
7. Request a Feature… - `AppHooks.requestFeature` (WS3). Default hook: opens `SegueLinks.feedback` *(B-14)*.
8. Rate Segue on the App Store - opens `SegueLinks.writeReview` (persistent, user-initiated counterpart to WS2b's `requestReview` prompt) *(A35)*. Hidden while `SegueLinks.appStoreID` is `nil`; WS5 fills the ID once the App Store Connect record exists, and the item appears with no other change.
9. separator
10. Privacy Policy - `SegueLinks.privacy` (Guideline 5.1.1(i)).
11. Terms of Use - `SegueLinks.terms`. These are the site terms (website, board, bug reports); the app itself is under Apple's standard EULA, which `/terms` section 1 links (R7, WS4). No separate EULA item.
12. Acknowledgements - opens the existing in-app Acknowledgements window *(A34)*. *(Removed 2026-10-18; see 3.6.)*

`AppHooks` (new, `App/AppHooks.swift`): a struct of `@MainActor` closures in `AppDependencies`: `showWhatsNew`, `reportProblem`, `requestFeature` (non-optional, defaults above), and `showWelcome`, `exportArchive` (optional, default `nil`; their menu items are hidden while `nil`). WS2b fills `showWelcome`, `showWhatsNew`, `exportArchive`; WS3 fills `reportProblem`, `requestFeature`; both from the app target, so core UI never knows which implementation runs. Hooks are never invoked while performing (menus are hidden on stage anyway); WS2b's What's New must also respect R20's "never during a show". The fallbacks are development-time only; WS2b and WS3 replace them before any release build (B-14).

### 3.6 About panel
Replace the About item (`CommandGroup(replacing: .appInfo)`) with one that calls `NSApp.orderFrontStandardAboutPanel(options:)`:
- Name and icon: defaults (the taped-setlist icon).
- Version: `CFBundleShortVersionString` and `CFBundleVersion` from Info.plist, shown as "Version 0.5 (12)". WS1 sets the numbers (R5); WS2a only reads them and adds a test that the panel string matches Info.plist.
- Copyright: `NSHumanReadableCopyright` from Info.plist, which WS1 sets to exactly `© 2026 Ryan Rony Dsilva` (R30; the same string is used on the App Store, the site and the policy). WS2a never hard-codes it; `AboutPanelTests` asserts the panel shows the Info.plist value and that it equals `© 2026 Ryan Rony Dsilva`.
- Credits (`.credits`, an `NSAttributedString` built in `App/AboutPanel.swift`, brand font, muted colour, both appearances): "segue.ryandsilva.dev · Help · Support · Privacy Policy" as links from `SegueLinks`, then "Built with open-source software: Schibsted Grotesk (SIL OFL 1.1), GRDB (MIT), Tonic (MIT)." with "Acknowledgements" linking to the web page `SegueLinks.acknowledgements` *(A34; a credits link cannot open an in-app window without a custom URL scheme, and no `segue://` scheme is registered in 0.5)*.
- *(Superseded 2026-10-18, walkthrough feedback: the app shows no third-party notices; no Acknowledgements window or Help item, no credits in About. THIRD_PARTY_NOTICES.md and the licence texts ship in the bundle's Resources, `make verify-appstore` checks them, and the web `/acknowledgements` is linked from /privacy, /terms and the footer.)*
- The in-app Acknowledgements window (`AcknowledgementsView`, already bundles `OFL.txt`, `GRDB.txt`, `Tonic.txt`) stays the authoritative licence view, reached from Help > Acknowledgements. Add an AppHardening test that all three licence resources load in the App Store flavor bundle (no empty disclosure).

### 3.7 Keyboard shortcuts: `?` on stage and Help > Keyboard Shortcuts (R15)

**Stage overlay**
- New `LiveCommand.showKeys` (title "Keyboard Shortcuts", scope `.chrome`), default binding `KeyStroke("?")` added to `InputBindingTable.defaults`. Because it is a binding, `bindings.json` can move it (a newer-schema file stays lenient; older builds do not read it, which is acceptable).
- New `LiveSession.Overlay.keys`. `?` toggles it; Esc closes it (existing `closeTopmost` path). While it is open, every other bound command still works and closes it first, so the stage never traps the performer *(A39)*; `?` is never auto-repeated (chrome scope) and stays rebindable through `bindings.json` *(A39)*.
- Content generated from `session.context.bindings` (so custom bindings show truthfully): grouped as Songs (next, previous, skip, play next request), Scrolling (page down/up, auto-scroll, faster/slower, back to top), View (zoom in/out/actual size, columns, collapse repeats), Panels (search, requests, set order), Show (end show). Each row: `LiveCommand.title` and every trigger's `KeyStroke.description` rendered as keycaps (arrows as glyphs). Unbound commands show "Not bound". A footer line: "Change keys in bindings.json (Help > Keyboard Shortcuts)".
- Visual: centred `StagePanelBackground` panel, two columns, stage typography, readable at 3 m (label size >= 18pt), respects Reduce Motion (no scale animation), VoiceOver reads it as a list.
- Status line: replace the hard-coded summary with one generated from the bindings (first trigger per command for the same set as today) and append "? keys".
- Never shown automatically, and there is no on-stage hint: discovery is the status line's "? keys" plus WS2b's Start Show tip in the main window (A40, WS2b).

**Help > Keyboard Shortcuts window**
- New `Window("Keyboard Shortcuts", id: "segue.shortcuts")`, `.commandsRemoved()`, restoration disabled, content min 560x520, scrolls.
- Section "Main window": generated from `MenuShortcuts` (every menu item with an equivalent) plus the editor's own keys that are not menu items (chord palette, completion: list them in a static table next to the editor code that owns them).
- Section "On stage": the same generator as the overlay, from `InputBindingTable.load(from: dependencies.live.bindingsURL)`; on a malformed file, show the defaults plus the same warning the stage shows.
- Accessible identifiers for both sections.

### 3.8 Show in Finder (R16)
- Uses `WorkspaceActions.reveal([URL])` (live: `NSWorkspace.shared.activateFileViewerSelecting`), works in the sandbox for paths inside the bookmarked library.
- Song: selects `songs/<slug>.cho` (from `SongRecord.relativePath` resolved against the root). Entry points: row context menu, detail "…" menu, File > Show in Finder (Opt-Cmd-R, focused song list or the song detail/editor shown).
- Setlist: selects its `.setlist.json`. Needs `SetlistStore.fileURL(for:)` (slug is private today). Entry points: sidebar context menu and builder "…" menu; File > Show in Finder when the builder is shown.
- Gig: selects its `shows/<ulid>.show.json` from the gig detail "…" menu *(A28)*.
- Library: Library > Show Library in Finder (root folder).
- A file missing on disk (deleted outside Segue since the last refresh): reveal the containing folder instead and show the banner "The file is no longer there; showing its folder."

### 3.9 Setlist builder undo/redo (R16)
Undo scope in this workstream *(A27, option b)*: the setlist builder (here), deletes and restores (3.3), import (3.2), Add to Setlist (3.5.3) and song metadata edits (3.9.1).

- Undo manager: the window's `UndoManager` from the builder's environment (`@Environment(\.undoManager)`), passed into `SetlistsViewModel` calls. The song editor's undo manager is separate (unchanged), so the stacks never mix.
- Undo target: one `SetlistUndoTarget` object per setlist ID (a small final class held in a dictionary on `SetlistsViewModel`), so `removeAllActions(withTarget:)` can drop exactly one setlist's actions.
- Mechanism: snapshot. Before a mutation, capture the `Setlist` value; after success, register an undo that writes that snapshot back through a new `SetlistStore.replace(_ setlist: Setlist) throws -> Setlist` (whole value, same slug, `updatedAt` stamped, refused for read-only), and whose own undo registers the redo with the post-mutation snapshot. One user gesture = one undo group (a multi-row drag is one step).
- Undoable, with action names: Add Song / Add Songs (insert, drag from library, `+`, Add Selected Song to Setlist), Remove Song, Move Song, Rename Setlist, Edit Details (venue/date/target), Edit Song Settings (`updateEntry` overrides and note), New Setlist (undo = Move to Trash), Duplicate Setlist (undo = Move to Trash), Move Setlist to Trash (undo = restore receipt, 3.3).
- The optimistic local reorder in `move` stays; undo snapshots are taken from the store's value, not the optimistic one.
- Disabled while performing (window inert). Show-end "Save to setlist" (`replaceEntries` from the reorder sheet) registers "Save Show Order" so a mistaken Save can be undone in the main window afterwards.
- If a write fails during undo/redo, show the error banner and remove the remaining actions for that setlist (`removeAllActions(withTarget:)`), never leave a stack that lies.
- **External edits** *(B-16)*: undo must never overwrite someone else's edit. `SetlistsViewModel.reload()` now also runs on Cmd-R (Library > Refresh) and on app activation (3.4), not only at library open. On each reload, compare every loaded `Setlist` value with the value the view model last held (last loaded or last written by Segue); for each setlist whose value differs (edited in another app) or that disappeared, call `removeAllActions(withTarget:)` on its undo target. A setlist that only Segue changed keeps its stack. If the shown setlist disappeared, the section falls back to Library (existing `followSetlistSelection`).
- Library switch clears all actions.

#### 3.9.1 Song metadata undo *(A27)*
- Covers tags, proficiency, notes and cues: every call to `LibraryViewModel.updateMetadata(id:_:)` (and `editMetadata`, which goes through it), from `SongMetadataViews` and the notes/cues sheet's Save.
- Mechanism: the same snapshot pattern. Before the write, capture the song's current `SongMetadata(record.sidecar)`; after success, register on the window `UndoManager` (passed in from the view's environment) an undo that writes the old `SongMetadata` back through `updateMetadata`, whose own undo re-applies the new value. Target: one `SongUndoTarget` per song ID (same pattern as setlists).
- Action names: "Edit Tags", "Change Proficiency", "Edit Notes", "Edit Cues"; a change touching several fields at once (the notes/cues sheet) is "Edit Song Details". One gesture = one group (a tag token typed and committed is one step).
- Undo reselects the song if it is still in the library; if the song was moved to the Trash meanwhile, undoing the metadata edit is not possible: the action is dropped with the banner "That song is no longer in the library.". Moving a song to the Trash, and a song file changed on disk (found by refresh), both `removeAllActions(withTarget:)` its song target. A write failure during undo/redo shows the error banner and drops that song's actions.
- The editor's text undo is unaffected (separate undo manager). Library switch clears all actions.

### 3.10 Restore selected song and section across launches (R16)
*(A26)* "Section" means the sidebar destination (Library / Gig log / a setlist), not a song's Verse/Chorus scroll position. Restored: sidebar destination + selected song + selected gig. An open editor is never reopened.
- Persist per library, in the app's `UserDefaults` (the test suite in test runs), under key `restoredState.<sha256 of root path>`: `{ section: "library" | "gigLog" | "setlist:<ULID>", song: "<ULID>"?, gig: "<ULID>"? }` (Codable, versioned).
- Written on every change of `LibrarySession.section`, `LibraryViewModel.selection` and the gig log selection (cheap; debounced 0.5 s).
- Restored once after the library opens and its first `reload()` finishes, before the launch check's resume prompt is presented (restoration must not delay or replace the resume prompt; if a resume is pending, restore anyway underneath it).
- Missing targets fall back: setlist gone -> Library; song gone -> no selection; gig gone -> gig log list without selection.
- The editor never reopens on launch (autosave means nothing is lost); the search text and filter chips are not restored.
- Not `@SceneStorage`: the E2E suite launches with `-ApplePersistenceIgnoreState YES`, which disables scene storage, and restoration must survive a window close/reopen too.

### 3.11 Window and app wiring details
- `UnsavedChangesGuard` becomes `PendingEditsGuard` (same file renamed): `shouldTerminate` flushes (3.4); `shouldClose` flushes and allows close; the stage branch is unchanged.
- `SegueRootView` loses the unsaved-changes alert and the save-conflict alert (moved inline); it gains the import summary bar and the single "aren't saved" prompt.

### 3.12 Test seams (Debug-only launch options; Release never parses them)
All flags below sit inside the `#if DEBUG` launch-option parser WS1 introduces (B-7); WS1's verify-appstore grep must not find their strings in the App Store binary.
Following the existing `ShortcutRunner` / `-SegueShortcutLog` pattern:
- `WorkspaceActions` protocol (`open(URL)`, `reveal([URL])`): live `NSWorkspaceActions`; `RecordingWorkspaceActions` appends one JSON line per call to the file given by `-SegueWorkspaceLog <file>`. Lets E2E assert every Help link and every Show in Finder without opening a browser or Finder.
- `-SegueTrashPath <dir>`: `LiveFileSystem(trash: .directory(dir))` *(B-15)*. Must be under `/private/tmp/segue-e2e/` (sandbox exception).
- `-SegueImportPanelPaths <p1:p2>`: replaces the `NSOpenPanel` result through an `ImportPanel` port (sandboxed open panels run out of process and are not reliably drivable from XCUITest).
- `-SegueAutosaveDelay <seconds>`: overrides the idle debounce (E2E uses 0.3 to stay fast; one test keeps the real 1.0).
- Add each flag to `LaunchOptions.flags`, `isTestRun`, and the doc comment.

### 3.13 Settings panes (ownership only; WS2a builds none of them)
The Settings window (Cmd-,) has these panes, in this order (I-6, R36). WS2a adds no pane and no Settings code; this table exists so menu items and links here agree with the owners.

| Pane | Contents | Owner |
|---|---|---|
| General | incl. "Show Library in Finder" (the only Settings copy of it; the menu copy is WS2a's Library > Show Library in Finder) | WS2b |
| Appearance | "Match System" (default) / "Light" / "Dark" for the main window (R36) | WS2b |
| Live | existing live settings; text rewritten by WS1 in `LiveSettingsView.swift` | WS1 (text), WS2b (pane host) |
| Privacy | WS3's consent toggles "Share usage analytics" / "Send crash reports", links to the Privacy Policy and `/privacy#usage-statistics` (no Terms link) | WS3 |
| Data | Reset All Settings… (A17) and WS2b's other data controls | WS2b |

WS2b puts the `TabView` host in a new `SegueSettingsView.swift`; WS3 adds its tab to whichever host exists when it lands.

---

## 4. File-level changes

Paths relative to the repo root; `UI/` = `Packages/SegueUI/Sources/SegueUI/`, `Core/` = `Packages/SegueCore/Sources/`.

**Core**
- `Core/Support/FileSystem.swift`: `trashItem(at:) throws -> URL` in the protocol; `TrashLocation`; `LiveFileSystem(trash:)`; `FileSystemError.trashUnavailable`.
- `Core/Support/Trash.swift` (new): `TrashReceipt`, `TrashedItem`, restore helper.
- `Core/Library/LibraryStore+Trash.swift` (new): `deleteSong`, `restoreSong`.
- `Core/Library/SongFileTypes.swift` (new): `importExtensions`, `claimedExtensions` (3.2, I-10); WS2b's UTType and Open With read it.
- `Core/Library/LibraryStore+Import.swift` (new): `prepareImport`, `commitImport`, `importSongs`, `ImportSummary`, `ImportSkip`, `ImportCandidate`; reuses `ChordProParser`, `Slug`, `SongFiles.write`, `SongFiles.decodeText`, `SidecarCodec`.
- `Core/Library/LibraryStore.swift`: internal `createSong(source:slugBase:)` used by `createSong` and import; `renameSong(id:toSlugFor:)` (new-song autosave, A18).
- `Core/Library/SongFiles.swift`: `moveSong(slug:to:)` (pair move) for rename/restore.
- `Core/Setlists/SetlistStore.swift`: `delete` -> trash + receipt, `restore(_:)`, `replace(_:)`, `fileURL(for:)`.
- `Core/Shows/ShowStore.swift`: `delete` -> trash + receipt, `restore(_:)`, `fileURL(for:)`.
- `Core/Shows/LiveCommand.swift`: `.showKeys`. `Core/Shows/InputBindings.swift`: default `?` binding; a `KeyHelp` builder (pure: bindings -> grouped rows) used by both overlay and window.
- Tests (`Packages/SegueCore/Tests/SegueCoreTests/`): `InstrumentedFileSystem.swift` implements `trashItem`; new `LibraryTrashTests.swift`, `SongImportTests.swift`, `SongMetadataUndoTests.swift` (restoring an old `SongMetadata` writes the sidecar back exactly), `SetlistStoreTrashUndoTests.swift`, `ShowStoreTrashTests.swift`, `KeyHelpTests.swift`; new fixtures under `Packages/SegueCore/Tests/Fixtures/import/` (see 6.1). Update existing `SetlistStore*` / `ShowStore*` delete tests to assert "moved to the trash dir" instead of "removed".

**UI**
- `UI/App/SegueLinks.swift`, `UI/App/AppHooks.swift`, `UI/App/WorkspaceActions.swift`, `UI/App/AboutPanel.swift`, `UI/App/SessionRestore.swift`, `UI/App/MenuShortcuts.swift`, `UI/Support/AutosavePolicy.swift` (all new).
- `UI/App/Commands/` (new folder): `FileCommands.swift`, `SetlistCommands.swift`, `LibraryCommands.swift`, `HelpCommands.swift`, `WindowCommands.swift` (only if spike 0d needs the explicit fallback item), `AppInfoCommands.swift`, `AddToSetlistMenu.swift` (shared by the Setlist menu and the context/"…" menus); `SegueCommands` moves here from `SegueRootView.swift` and composes them.
- `UI/App/KeyboardShortcutsView.swift` (new window content).
- `UI/App/AppModel.swift`: `AppDependencies` gains `hooks`, `workspace`, `importPanel`, `autosaveDelay`; flush-before-start in `AppModel+Shows.swift` `startShow`; refresh of songs and setlists on app activation (skipped while performing).
- `UI/App/LibrarySession.swift`: lifted `isNamingNewSetlist` state; restore wiring; window undo manager clearing on switch.
- `UI/SegueRootView.swift`: remove the two alerts, add the summary bar, the "aren't saved" prompt and the reopen-aware commands.
- `UI/Editor/UnsavedChangesGuard.swift` -> `PendingEditsGuard.swift`; add `applicationShouldHandleReopen`.
- `UI/Editor/SongEditorViewModel.swift`: `SaveState`, `AutosaveScheduler`, `flush()`; delete `canSave`; keep `commit()` as the internal save step.
- `UI/Editor/SongEditorView.swift`: Done button, subtitle, `isDocumentEdited`, `UI/Editor/SaveConflictBar.swift` (new).
- `UI/Library/LibraryViewModel.swift`: navigation flushes instead of prompting; `applySaved`; `pendingNavigation` only for failed flushes. `LibraryViewModel+SaveConflict.swift`: drop `.cancel`. `LibraryViewModel+Metadata.swift`: snapshot undo (3.9.1); `UI/Library/SongMetadataViews.swift` passes `undoManager`. New `LibraryViewModel+Import.swift`, `LibraryViewModel+Delete.swift` (song confirmation only when setlists reference it, A23; flush-then-trash, B-10).
- `UI/Library/LibraryViews.swift`: drop target and highlight, context menu (Add to Setlist ▸, Show in Finder, Move to Trash), empty state Import button, focused song value. `UI/Library/SongDetailPane.swift`: "…" menu (Add to Setlist ▸, Show in Finder, Move to Trash). New `UI/Library/ImportSummaryBar.swift`.
- `UI/Library/MainSidebar.swift`, `UI/Setlists/SetlistBuilderView.swift`: Move to Trash wording, confirmation dialogs removed (A23), Show in Finder, shortcut tooltips. `UI/Setlists/SetlistsViewModel.swift` + new `SetlistsViewModel+Undo.swift` (per-setlist undo targets, external-change detection on reload, B-16); views pass `undoManager`.
- `UI/GigLog/GigLogViewModel.swift`, `UI/GigLog/GigDetailView.swift`: trash + undo + Show in Finder; confirmation dialog removed (A23); details autosave moves onto `AutosavePolicy` (B-13).
- `UI/Live/LiveSession.swift` (`.keys`), `LiveSession+Commands.swift` (dispatch), new `UI/Live/KeysOverlay.swift`, `UI/Live/LiveView.swift` (present it), `UI/Live/StageChrome.swift` (generated status line).
- `UI/AccessibilityID*.swift`: `editorDone`, `editorSaveStatus`, `editorConflictBar` (+ `.reload/.overwrite/.copy`), `importSummary`, `importSummaryDetails`, `songMoveToTrash`, `songMoreMenu`, `libraryDropZone`, `keysOverlay`, `shortcutsWindow`, `shortcutsMainSection`, `shortcutsStageSection`, `setlistStartShowMenu`, `addToSetlistMenu`, `songDeleteConfirm`, `helpRateItem`, `helpWelcomeItem` etc. Remove `editorSave`, `editorCancel`.
- UI tests (`Packages/SegueUI/Tests/SegueUITests/`): `AutosaveTests.swift` (scheduler with a manual clock: debounce, max latency, flush triggers, in-flight coalescing, conflict pause), `SessionRestoreTests.swift`, `AboutPanelTests.swift`, `MenuShortcutsTests.swift` (no duplicate key equivalents across all menus; every `MenuShortcuts` entry is used by a command), `SegueLinksTests.swift` (`writeReview` is `nil` while `appStoreID` is `nil`, correct URL otherwise; no `changelog.json` constant exists).

**App target**
- `App/Sources/SegueApp.swift`: main scene to `Window("Segue Library")` with Cmd-0 (A32), Keyboard Shortcuts window, hooks/workspace/trash/import-panel injection.
- `App/Sources/LaunchOptions.swift`: the four flags in 3.12.
- `.swiftlint.yml`: the `ryandsilva\.dev|apps\.apple\.com` custom rule.

**UITests**
- New `UITests/SegueCoreUXE2ETests.swift` and `UITests/SegueCoreUXE2ETests+Support.swift` (scenarios in 6.3).
- Update `SegueE2ETests.swift` (`createSong`, `createSongSavingFromPrompt`, `discardEditFromPrompt`), `SegueEditorE2ETests.swift` (`testUnsavedEditsPromptOnCloseAndQuit` becomes "quit flushes"), `SegueEditorE2ETests+Steps.swift` (`saveEditor` becomes `finishEditing`: click Done, assert file content), `SegueSetlistBuilderE2ETests.swift` (`renameDuplicateDelete`: no confirmation dialog any more, file in trash dir, then Undo restores), `SegueSetlistGigLogE2ETests.swift` (`playStatsAndDelete`: no confirmation dialog, file in trash dir), and the AXID mirrors in each `*Support.swift`.

---

## 5. Step order

Run `make quick` at the end of every step; run the step's E2E with `make e2e-one TEST=<Class>/<test>`; one `make check` at the very end. Commit each step locally as it lands (signed, per repo convention), no pushes.

0. **Spike (time-box 1 h, record results at the top of the PR/commit message)**: (a) `FileManager.trashItem` from the sandboxed Debug build for a file inside a bookmarked user folder and for `/private/tmp/segue-e2e/` (expect the first to work; the second confirms `-SegueTrashPath` works there, B-15); same from the App Store flavor build. (b) Whether XCUITest can drive the sandboxed `NSOpenPanel` (expect no -> `-SegueImportPanelPaths`). (c) Whether an XCUITest cross-app drag from Finder onto Segue works (`XCUIApplication(bundleIdentifier: "com.apple.finder")`, `press(forDuration:thenDragTo:)`); if not, drop is covered by a SegueUI test feeding `NSItemProvider`s into the drop handler plus the manual check in 6.4. (d) Whether `Window("Segue Library")` with a scene `.keyboardShortcut("0")` (vs `WindowGroup`) keeps frame restoration and Dock-click reopen, shows exactly one "Segue Library" Window menu item with Cmd-0, and keeps the `navigationTitle` in the title bar (else use the 3.5.5 fallback). (e) The `macappstore://...?action=write-review` URL opens the App Store app's review page for a known existing app ID (use any live Mac app's ID; Segue's is not known yet); if it does not, use `https://apps.apple.com/app/id<ID>?action=write-review` instead and record which.
1. **Core trash**: `FileSystem.trashItem`, `Trash.swift`, `LibraryStore.deleteSong/restoreSong`, `SetlistStore`/`ShowStore` trash + restore + `replace`. Core tests. Fix the existing delete tests.
2. **Core import**: `LibraryStore+Import.swift` with fixtures and tests.
3. **Links, ports, launch options**: `SegueLinks`, `AppHooks`, `WorkspaceActions`, `ImportPanel`, the four flags, lint rule.
4. **Autosave**: `AutosavePolicy`, scheduler (also adopted by gig details), VM changes, Done button, status, conflict bar, `PendingEditsGuard`, refresh on activation, incremental `applySaved`, new-song rename. Update the existing editor/library E2E tests in the same step (they break otherwise). Run `SegueEditorE2ETests` and `SegueE2ETests` fully here, since this is the riskiest change.
5. **Delete and Trash UI**: song delete entry points, confirmation only for songs in setlists, flush-then-trash, setlist/gig dialogs removed, undo for all three, Show in Finder everywhere.
6. **Import UI**: menu, panel, drop zone, empty state, summary bar, undo import.
7. **Menus**: split `SegueCommands`, File (incl. the hidden-until-filled Export hook)/Setlist (incl. Add Selected Song to Setlist)/Library/Help (12 slots incl. the hidden Welcome and Rate items)/Window, `MenuShortcuts`, main scene change, reopen handling, About panel.
8. **Undo**: setlist builder undo/redo with per-setlist targets and the setlist reload on Cmd-R / activation (B-16); song metadata undo (3.9.1).
9. **Keyboard help**: `LiveCommand.showKeys`, overlay, generated status line, Keyboard Shortcuts window.
10. **State restore**.
11. **Pixel pass**: screenshots (attached by E2E) of every new surface in light and dark; fix anything off. Then `make check`.

---

## 6. Test plan

Integration and E2E first; unit tests only for the scheduler and the pure key-help builder.

### 6.1 Core integration (`make test`, real `LiveFileSystem` on temp dirs with `trash: .directory(tmp)`)
- **Trash, songs**: delete moves `.cho` and sidecar into the trash dir, index row gone, `search` no longer finds it, `refresh` does not resurrect it; restore brings both back with the same ID and the index row back; restore when the slug was reused in between lands as `<slug>-2` with the same ID; restore after the trashed file vanished fails cleanly and changes nothing; sidecar trash failure (instrumented FS) still deletes the song and reports; read-only song deletes.
- **Trash, `.system`**: one test trashes a temp file through the real Trash and then deletes the returned URL (leaves the user's Trash clean).
- **Setlists/shows**: delete -> trash dir; restore reloads identical value; show restore re-projects plays (`playStats` before delete == after restore); `replace` writes the snapshot byte-for-byte except `updatedAt`, refuses read-only.
- **Import** (fixtures in `Tests/Fixtures/import/`): `.cho` with title; `.chopro`; `.chordpro`; `.pro`; `.crd` (skipped as not accepted); `.txt` chords-over-lyrics (kept byte-identical); no `{title}` (slug from file name); title collision with existing song (`-2`); two files with the same title in one batch; byte-identical duplicate (skipped with the existing title); file from the library's own `songs/` (skipped); CRLF and no final newline (bytes kept); UTF-8 BOM (stripped); Windows-1252 file (converted and reported, B-11); 2 MB file and a PNG renamed `.cho` (skipped with reasons); folder with nested files and a hidden file; neighbour `.segue.json` (metadata copied, ID fresh); romanized Hindi title "Pyaar Ki Raah" (slug `pyaar-ki-raah`, search "pyar" finds it). Each asserts files on disk, sidecar JSON, index row and summary.
- **Rename (new-song autosave)**: rename moves both files, keeps ID, updates index path; collision picks `-2`.
- **KeyHelp**: defaults produce every `LiveCommand` exactly once; a `bindings.json` override moves `?` and the help follows.

### 6.2 SegueUI tests (`make test`)
- `AutosaveTests`: manual clock; `AutosavePolicy` values (1.0 s / 5 s) used by both the editor and gig details; idle debounce fires once after a burst; max latency fires during continuous changes; each flush trigger saves immediately; change during in-flight save schedules exactly one more; conflict pauses autosave and sets `SaveState.conflict`; clean editor reloads silently on external change.
- `MenuShortcutsTests`: no duplicate key equivalent across all menus; Setlist and Help items exist with the specified shortcuts.
- `SegueLinksTests`: `writeReview` nil/non-nil with `appStoreID`; every constant parses; `helpPage("keyboard")` path.
- `SessionRestoreTests`: round trip per library root; fallbacks for missing targets.
- `AboutPanelTests`: version string from Info.plist; copyright equals `© 2026 Ryan Rony Dsilva` (R30); credits contain every `SegueLinks` it should; acknowledgements resources load.

### 6.3 E2E (`UITests/SegueCoreUXE2ETests.swift`, each test starts from a wiped `/private/tmp/segue-e2e/` and `-SegueResetState YES`, with `-SegueTrashPath`, `-SegueWorkspaceLog`, `-SegueAutosaveDelay 0.3`)
1. `testAutosaveWritesWithoutSave`: open a song, type a line, wait for subtitle "Saved", assert the `.cho` on disk contains it with no Save click; Cmd-S shows "All changes saved".
2. `testAutosaveRealDebounce`: same with the default delay (no override) to prove the shipped timing.
3. `testSwitchingSongsFlushes`: type, click another song within 0.1 s, assert the first file saved and no prompt appeared.
4. `testQuitFlushes`: type, Cmd-Q immediately, app quits, file contains the edit.
5. `testExternalEditConflict`: open editor, type (unsaved), test runner rewrites the `.cho`, type again: conflict bar appears, nothing written; Save as Copy creates a second song with the edits; original file holds the external text. Variant: external delete -> Save as New Song.
6. `testCleanEditorPicksUpExternalEdit`: editor open and saved, test runner rewrites the file, re-activate the app: editor shows the new text.
7. `testNewSongFileFollowsTitleUntilDone` (A18): type `{title: Ha`, wait for save, continue to `{title: Harbour}`, Done: only `harbour.cho` exists.
8. `testImportFromMenu`: `-SegueImportPanelPaths` with 4 fixtures (one duplicate, one `.png`): summary "Imported 2 songs. 2 skipped.", Details lists both reasons, first import selected, files and sidecars on disk; Edit > Undo Import moves them to the trash dir.
9. `testImportByDrop` (if spike 0c succeeded): drag a `.cho` from Finder onto the song list.
10. `testDeleteSongToTrashAndUndo`: a song in no setlist: Move to Trash trashes at once with no dialog; Cmd-Z restores it. Then a song in a setlist: Move to Trash from the context menu; the confirmation names the setlist (A23); files in trash dir; builder shows "Missing song"; Cmd-Z restores; builder resolves it again; Cmd-Shift-Z trashes again.
11. `testDeleteShortcutNeverFiresInText`: in the editor and in the search field, Cmd-Delete edits text and trashes nothing.
12. `testSetlistAndGigDeleteGoToTrash` (extends existing builder/gig-log tests): no confirmation dialog appears; files in trash dir; undo restores; gig undo restores play counts.
13. `testShowInFinder`: song, setlist, gig and library entries write the expected paths to the workspace log.
14. `testHelpMenu`: the visible Help items match 3.5.6 in order and by exact name (Welcome to Segue… and Rate Segue on the App Store absent, since their hook and app ID are unset in this build); each link item writes the right `SegueLinks` URL to the workspace log; Keyboard Shortcuts opens the window; Acknowledgements opens its window; the default hooks write their fallback URLs. File > Export Library Archive… is absent.
15. `testReopenMainWindow`: Cmd-W closes the main window; Window > Segue Library (and Cmd-0) brings it back, single window; clicking the Dock icon with no window (via `app.activate()` after close) also brings it back.
16. `testSetlistMenuShortcuts`: in a builder, Cmd-Return starts a show (pre-show checklist appears), Opt-Cmd-Return a rehearsal, Shift-Cmd-N opens the name sheet; outside a builder Start Show is disabled.
16a. `testAddSelectedSongToSetlist`: select a song in the library, Setlist > Add Selected Song to Setlist > <setlist>: the `.setlist.json` gains the entry at the end, the submenu now shows a checkmark for that setlist; Cmd-Z removes it; the same from the song row's "Add to Setlist ▸" context menu.
17. `testStageKeysOverlay`: on stage, `?` shows the overlay listing every command; Esc closes; with a `-SegueBindingsPath` file that rebinds Next to `n`, the overlay shows `N` for Next Song; right arrow while open advances and closes it.
18. `testKeyboardShortcutsWindow`: both sections present; a main-window row matches the menu (Start Show Cmd-Return).
19. `testSetlistBuilderUndoRedo`: add, move, remove, rename, details: Cmd-Z walks back each with the right file contents after each step; Cmd-Shift-Z replays. Then make one edit, have the test runner rewrite that `.setlist.json`, re-activate the app: the builder shows the external content and Edit > Undo no longer offers the setlist action (B-16).
19a. `testSongMetadataUndo`: add a tag and change proficiency in the detail pane; Cmd-Z reverts proficiency, then the tag, checking the sidecar on disk after each; Cmd-Shift-Z replays.
20. `testRestoresSectionAndSongAcrossLaunches`: select a setlist, relaunch without `-SegueResetState` (keep the test defaults suite): builder of that setlist shown; select Library + a song, relaunch: that song selected, editor closed. Then trash the song's file from the test runner, relaunch: no selection, no crash.

Every test attaches screenshots of the new surfaces (conflict bar, summary bar, overlay, shortcuts window, About panel, Help menu) in both appearances for the pixel pass.

Updated existing tests (step 4/5) must stay green; `SegueLiveE2ETests` must pass untouched apart from the status line string if it asserts it.

### 6.4 Manual checks (record results in the commit message)
- Real Trash from the App Store flavor build on a library in `~/Music/Segue`: Delete Song, check Finder's Trash, Put Back works, Undo works.
- Drag from Finder onto the list (if 6.3.9 is not automatable), including a folder.
- About panel in light and dark: links clickable, version from Info.plist.
- VoiceOver reads the overlay and the conflict bar (WS2b's accessibility pass will audit fully).

### 6.5 Budget
`make quick` after each step; `make e2e-one TEST=SegueCoreUXE2ETests/<test>` per feature (and the touched existing classes in step 4 and 5); one full `make check` at the end. No full E2E reruns after small fixes.

---

## 7. Acceptance criteria

1. File > Import Songs… and drag and drop import `.cho/.chopro/.chordpro/.pro/.txt` (one list in `SongFileTypes`) into `songs/<slug>.cho` + fresh sidecar, indexed and searchable immediately; collisions get `-2`; duplicates and invalid files are skipped with a visible reason; one bad file never stops a batch; Undo Import works.
2. Songs can be deleted in-app; songs, setlists and gigs go to the Trash (never `removeItem`), the index and play stats stay in sync, and each delete is undoable from Edit > Undo in the same session. Only a song used by setlists asks for confirmation. `grep -rn "removeItem" Packages/*/Sources` shows no delete path for user data (only temp/index cleanup).
3. No Save button exists; edits reach disk within 1 s of a pause, 5 s during continuous typing, and immediately on switch/close/quit/start show; quitting right after typing never loses the edit; Cmd-S confirms; an external edit is never silently overwritten (conflict bar) and a clean editor follows external edits.
4. The Help menu has the 12 slots of 3.5.6 with exact names, in order; the 10 always-visible items are functional (hooks fall back until WS2b/WS3), Welcome to Segue… appears once WS2b sets its hook and Rate Segue on the App Store once `appStoreID` is set; "Segue Help" never shows "Help isn't available"; Privacy Policy is reachable in-app (5.1.1(i)).
5. The Setlist menu has Start Show (Cmd-Return), Rehearse (Opt-Cmd-Return), New Setlist (Shift-Cmd-N) and Add Selected Song to Setlist ▸, with correct enabling.
6. After closing the main window, Window > Segue Library, Cmd-0 and a Dock click each reopen exactly one main window.
7. About shows "Version x (y)" from Info.plist, copyright `© 2026 Ryan Rony Dsilva`, links and credits; Help > Acknowledgements shows the OFL and both MIT licence texts in the App Store build.
8. `?` on stage shows an overlay generated from the live bindings; Help > Keyboard Shortcuts lists main-window and stage keys from the same sources as the menus and the stage.
9. Show in Finder works for songs, setlists, gigs and the library.
10. Setlist builder edits and song metadata edits are undoable and redoable with named actions; a setlist changed on disk loses its undo actions instead of being overwritten.
11. The sidebar section and selected song (and gig) are restored on relaunch per library, with safe fallbacks.
12. All URLs live in `SegueLinks.swift` (lint-enforced); no changelog feed URL exists and the app makes no network request for release notes.
13. `make check` green (lint, tokens, icon, both flavors, core + UI tests, full E2E, verify-appstore), no new warnings, no flakiness across two consecutive `make e2e-one` runs of each new test.

---

## 8. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| `trashItem` behaviour in the sandbox (bookmark scope, `/private/tmp` exception path, volumes without Trash) is UNVERIFIED (research 08) | Delete may fail on real libraries | Spike step 0a on both flavors; `trashUnavailable` error, never permanent fallback; manual check 6.4 |
| Core and E2E tests polluting Ryan's real Trash | Annoying, and leaves test data behind | `TrashLocation.directory` in tests, `-SegueTrashPath` in E2E; the single `.system` test deletes its result |
| Autosave writes + full `reload()` per save on a large library | Typing lag, battery | Incremental `applySaved`; debounce; keep the latency tests as the gate |
| Removing Save/Cancel breaks many existing E2E helpers | Red suite mid-session | Update them in the same step (step 4), run those classes before moving on |
| Autosave writing while another app edits the same file | Lost external edit | Every write stays conflict-checked against the revision; activation refresh; conflict bar never auto-resolves |
| New-song slug from a half-typed title | Ugly permanent file names | A18: the file follows `{title}` while the creating session is open |
| Cmd-Delete / Cmd-Return stealing keys from text views and sheets | Destroying text or starting a show from a sheet | Focus-scoped enabling (`focusedSceneValue`); disable Setlist commands while a sheet is up; E2E 11 |
| `WindowGroup` -> `Window` changes restoration and SwiftUI's automatic menus | Regressed window frame restore, duplicate Window items | Spike 0d; E2E 15 |
| NSOpenPanel and Finder drags not drivable from XCUITest | Import UI path less covered | Panel port stub for E2E; SegueUI provider test; manual drag check |
| `?` vs `/` on non-US layouts (`?` may need Shift+other key) | Overlay unreachable on some keyboards | Character-based binding already follows the produced character; Help > Keyboard Shortcuts is the fallback; bindings.json can rebind |
| Rate item needs the Apple ID | Item absent at first upload | Hidden while `appStoreID` is `nil`; WS5 fills it once the App Store Connect record exists, before the review build |
| Help links point at pages WS4 has not published yet | 404s during review | WS4 must publish /help, /privacy, /terms, /support, /changelog, /feedback, /acknowledgements before submission; add to the WS5 release checklist |
| About version shows 0.1.0 until WS1 lands | Wrong version in review | About reads Info.plist only; WS1 owns the numbers; acceptance 7 checked after WS1 merges |
| Undo snapshots overwriting a setlist edited externally in between | Lost external change | B-16: setlists reload on Cmd-R and app activation; a setlist whose file changed on disk loses its undo actions (3.9) |

---

## 9. Open questions for Ryan

None. Every question this spec raised is closed; the map below records where each answer now lives.

| Former question | Ruling | Applied in |
|---|---|---|
| New songs under autosave | A18: file created on first autosave, name follows `{title}` until the editor closes | 3.4 |
| What "restore section" means | A26: sidebar destination + song + gig; editor never reopens | 3.10 |
| Delete confirmations | A23: confirm only when a song is used by setlists | 3.3 |
| Delete with editor open | B-10: flush, then trash | 3.3 |
| Import extensions | A24, I-10: `.cho .chopro .chordpro .pro .txt`, no `.crd`; `.txt` as-is | 3.2 |
| Non-UTF-8 imports | B-11: convert, report | 3.2 |
| No `{title}`, duplicates, folders, drop targets | A25: defaults | 3.2 |
| Neighbour `.segue.json` | B-12: copy metadata, fresh ID | 3.2 |
| Autosave conflict UX | A19: inline bar, activation refresh, silent reload of a clean editor | 3.4 |
| Cmd-S feedback | A20: transient "All changes saved" | 3.4 |
| Editor controls | A21: Done only, no Revert | 3.4 |
| Autosave timing | B-13: one `AutosavePolicy` (1.0 s / 5 s), editor and gig details | 3.4 |
| Dirty-state UI | A22: Saved / Saving… / Not saved + edited dot | 3.4 |
| Acknowledgements | A34: in Help; About links the web page. *Superseded 2026-10-18: not in the app; notices ship in the bundle, the web page is linked from /privacy, /terms, footer* | 3.5.1, 3.5.6, 3.6 |
| Hooks before WS2b/WS3 | B-14: fallbacks | 3.5.6 |
| Rate Segue | A35: in Help, shown once the Apple ID is known | 3.1, 3.5.6 |
| Terms vs EULA | R7: Terms of Use opens `/terms`, which links Apple's EULA | 3.1, 3.5.6 |
| Main window | A32, I-11: single `Window` "Segue Library", Cmd-0 | 3.5.5 |
| Setlist menu | A33 (b): New Setlist here only, Cmd-Return / Opt-Cmd-Return, disabled outside a builder, plus Add Selected Song to Setlist ▸ | 3.5.3 |
| `?` overlay | A39: non-modal, rebindable | 3.7 |
| Trash in E2E | B-15: `-SegueTrashPath` + manual real-Trash check | 3.3, 3.12, 6.4 |
| Undo scope | A27 (b): plus song metadata | 3.9, 3.9.1 |
| Setlist undo vs external edits | B-16: reload on Cmd-R / activation, drop changed setlists' undo | 3.9 |
| Copyright string | R30: `© 2026 Ryan Rony Dsilva`, set by WS1 | 3.6 |
| Show in Finder for gigs | A28: included | 3.8 |
| Import vs phase 3 review | A29: direct import stays for ChordPro; only conversions are reviewed | 3.2 |
| Help "Getting Started" | B-17, I-5: slot reserved as "Welcome to Segue…", filled by WS2b | 3.5.6 |
| Remote changelog feed | A16, I-3: none; bundled `changelog.json` only (I-2) | 3.1 |
| Settings panes | R36, I-6: General, Appearance, Live, Privacy, Data; none owned by WS2a | 3.13 |
| Help URL slugs | I-16: WS4's table is the contract | 3.1 |

Recorded only: research 08 recommended keeping explicit Save for 1.0 and one combined Send Feedback item; R17 and R15 override both (autosave; separate Report a Problem / Request a Feature). The spec follows the rulings.

## Addendum - R45 page-turner pedals (added after the spec was finalised)
On stage, Page Down scrolls the current song. When the song is already at its bottom, the next Page Down advances to the next song in the set, at its top. Page Up mirrors this: it scrolls up, and at the top it goes to the previous song at its bottom. Arrow keys and Space keep their current meanings. Stay consistent with key rebinding (`bindings.json`) and the `?` overlay text. E2E: a long song is paged to its end; the next Page Down shows the next song's title; Page Up at the top returns to the previous song at its bottom.
