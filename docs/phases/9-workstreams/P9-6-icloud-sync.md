# P9-6 - iCloud sync between the owner's Macs

Phase 9 workstream (new, 2026-10-31). Ruling: `docs/release/decisions.md` **R177** (optional iCloud sync ships in v1.0: CKSyncEngine over the CloudKit private database, one zone per library, one record per item keyed by its ULID, the local folder canonical, opt-in, macOS only; per-field newest-wins by a hybrid logical clock; losers to `<library>/history/`; deletes mirror; Live releases the engine; first join merges by ULID; an older Mac stops syncing; both builds share `iCloud.dev.ryandsilva.segue`, Personal on Production; S1 starts with two spikes; the index and locks leave the library folder) and **R179** (this spec's questions closed, section 24). Design basis: `docs/research/phase9-icloud-sync.md` (cited below as "research N"). Built on: **R176** (v1.0 and its pre-release scope), **R132** / **R134** (superseded for Mac-to-Mac by R177), **R1** (paid team `V6BM673U35`), **R11** / **R12** (bundle IDs, manual App Store signing), **R59** (Apple-events entitlements), **R67** / **R100** (the shared app group), **R113** (test budget), **R39** (design directions before new UI), **R158** P8-1 Q8 (`NearDuplicateIndex`), and the owner's rules on deterministic simulation testing, rebuildable projections, ULID identity, idempotent replay, graceful degradation and no automation-driven folder under file sync.

**Sibling specs in this folder, written in parallel:** P9-1 (PDF export), P9-2 (Singer view), P9-3 (medleys), P9-4 (lyrics and URL import), P9-5 (Mac polish). None of them owns sync, but P9-3 (medleys) and any sibling that adds a sidecar or setlist field must add that field to the record field lists in section 7.3 in the same change (section 7.5 makes this a test failure, not a convention).

**Build order:** five sessions (section 22). **S0** (library state out of the folder, the file-sync warning) is independent of everything else and may start now, beside any sibling. **S1** (owner portal steps, then the two R177 spikes, entitlements, `SyncPort` and the fake) needs section 21 steps A-C done by the owner first, and **returns to the owner if either spike fails**. S2 (core sync), S3 (CloudKit adapter) and S4 (UI, settings, release) follow in order; S2 and S3 may overlap once S2's record codecs have landed. All before the v1.0 submission (R176, R177); the schema deploy (section 21 D) is the last step before archiving.

## Session rules (apply to every session)

- `cat` and `ls` are aliased to eza and can hang: use `command cat` / `command ls` or the Read / Grep / Glob tools, and pass this warning to any subagent. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-". Ignore `.build/`.
- Sibling workstreams (P9-1 to P9-5) edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, stage only your own hunks, keep the tree compiling between steps.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget (R113): per step only targeted in-process suites (`swift test --filter <Suite>`). The HLC, the merger, the codecs and the retention rule are tricky pure logic and get table-driven tests; the sync behaviour is proven by the deterministic simulation (section 17.1) in-process. Exactly **one** new XCUITest class for the workstream (`SegueSyncE2ETests`, section 17.4, in S4) plus the S0 warning check inside an existing class. At the end of each session ONE `make quick`, plus ONE `make e2e-one` per UI test class added or changed. No `make gate`, no `make check`, no E2E retry loops (a failure is investigated, not re-run), no scratch-worktree builds. `make cloud-test` (section 17.3) is opt-in and runs at most once per session that changes the adapter. Every build or test runs under `lockf -k .build/make.lock`. Write this budget into any subagent's prompt.
- Before using any Apple API not already in the codebase (all of CloudKit, `UserNotifications`, `URLResourceValues.isUbiquitousItem`, `getpwuid`), run the `apple-api-check` skill.
- Ryan's real library is never opened by a test or a session, and no session signs in to, writes to or deletes from Ryan's Production iCloud data. Spikes and cloud tests use throwaway zones named `spike-<ulid>` / `test-<ulid>` and delete them afterwards.
- The 1Password CLI does not work from the agent shell: anything that needs a credential is handed to Ryan as an exact command for Terminal.app.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency, including any case section 24's closed questions do not cover.

## 1. Goal

Ryan plays from a desktop Mac at home and a MacBook Neo (8 GB) at gigs. Today he copies the library folder by hand or risks putting it in iCloud Drive, where a song can be evicted to a placeholder and the search index can corrupt. After P9-6: he turns on sync once on each Mac, edits anywhere, and both Macs converge within seconds when online; every song is always a real local file; a show never touches the network; a clash between two edits keeps the newest and puts the other in Previous Versions.

**In scope (R177):** the library state (index, locks) moved to the shared app group keyed by a library ID, with a file-sync folder warning (S0); `SyncPort` with an in-memory fake and a CloudKit adapter in its own package; the record schema for songs (`.cho` and sidecar), setlists (with arrangements), smart filters, finished shows (the Gig Log) and the musical settings; the HLC and the per-field merge; the sync ledger; change capture (store hooks plus a rescan); the remote applier; the history store with retention and the Previous Versions UI; the Live release and the Rehearsal deferral; first join with merge by ULID, the look-alike review and seed de-duplication; sign-out, turn off, "Delete iCloud Data", a zone deleted elsewhere, quota, version skew; the library footer indicator, Settings > Sync and the 24-hour notification; entitlements in both flavours and the release checks; the deterministic sync simulation, the conformance suite, the opt-in real-CloudKit tests and the two-Mac checklist; the privacy policy, App Review notes, analytics and guide pages.

**Not in scope:** iOS or iPadOS; sharing a library with another Apple Account (CloudKit shared database); syncing several libraries at once (only the open library's zone sends; others queue, section 9.6); text merge inside a `.cho`; syncing per-Mac state (section 14.2); a web or Windows client; iCloud Drive as a library location (rejected by R177; S0 warns instead).

**Unchanged:** the on-disk file formats (`.cho`, `.segue.json`, `.setlist.json`, `.show.json`, `.filter.json`): no sync stamp is ever written into a library file; the stores' public edit APIs and their optimistic conflict checks; the archive export's contents; every behaviour with sync off (the default).

## 2. Decisions (R177) and where the owner chose differently from the research

| Topic | R177 ruling | Research recommendation | Spec consequence |
| --- | --- | --- | --- |
| Approach | B: CKSyncEngine, private DB, zone per library, record per ULID, local canonical | same (research 6) | sections 6-9 |
| What syncs | songs + sidecars, setlists + arrangements, smart filters, Gig Log, musical settings | same, settings as records in the same engine (research Q6, Q7) | sections 7, 14 |
| Merge | per top-level field, newest by HLC with device tiebreak; `.cho` whole | same (Q3, Q14) | section 8 |
| History | `<library>/history/`, never synced, 90 days or last 20 per item (whichever keeps more), not in the archive by default, restorable via Previous Versions | same (Q4) | section 10 |
| **Remote delete** | **"A delete on one Mac deletes on the other (recoverable from history)"** | the receiving Mac moves the file to the Trash plus a history entry, "never a hard delete" (Q11, research 3 "Deletes") | **The delete mirrors fully: the item leaves the library on the other Mac, and the in-app recovery path is history (Previous Versions > Recently Deleted), not the Finder Trash.** The repo invariant "user data is trashed, never `removeItem`" is kept underneath (section 9.5, open question 1). |
| Turn off / sign-out | keep local and cloud; separate confirmed "Delete iCloud Data"; sign-out stops and keeps local, explicit re-join | same (Q12, Q13) | section 13 |
| Live / Rehearsal | engine fully released during a Live show, edits queue; Rehearsal keeps syncing, a remote change to the song on screen applies when it is left | same (Q8, Q9) | section 11 |
| First join | merge by ULID, look-alikes listed for review, Welcome seeds de-duplicated | same (Q10) | section 12 |
| **Version skew** | **"A Mac on an older Segue stops syncing until updated."** | newer records stored and opened read-only on the older Mac, never overwritten by it (Q15, research 7) | **The older Mac stops its engine entirely (no fetch applied, no send) and says "Update Segue on this Mac to keep syncing"; local edits keep queuing and send after the update. No read-only remote copies exist.** (section 13.5) |
| Status | quiet library-footer indicator, Settings > Sync, notification only after 24 h of unsynced changes | same (Q18) | section 15 |
| Flavours | both share `iCloud.dev.ryandsilva.segue`, Personal on Production | same (Q5) | section 16 |
| Spikes | S1 starts with two spikes (Personal sharing data; the full Live pause) and returns to the owner if either fails | offered as a research-ticket option (Q19) | section 16.4, session S1 |
| Index and locks | move to Application Support keyed by library ID, gentle warning in a file-sync folder, in v1.0 | S0, optional (Q16) | section 5; **refined**: the shared app-group container's Application Support, because the per-flavour container would break the cross-flavour library lock (section 5.2) |
| Roadmap | v1.0 | after v0.5 as its own release (Q17) | before submission |

## 3. Terms

- **Item**: one synced unit with a ULID identity: a song (its `.cho` plus sidecar), a setlist, a smart filter, a finished show, or a settings group.
- **Field**: one top-level member of an item that merges on its own (section 7.3). The `.cho` text is one field (`source`).
- **Stamp**: the HLC value `(wall, counter, device)` of the last write to a field (section 8.1).
- **Library ID**: a ULID naming a library folder's identity, stored in the folder (section 5.1). The zone name derives from it.
- **Device ID**: a ULID naming one Mac (shared by both flavours on that Mac, section 5.2).
- **Ledger**: the local GRDB database of sync state: stamps, last-synced field hashes, server system fields, the inbox, pending sends and the engine state (section 9.1). A rebuildable projection.
- **Inbox**: fetched remote records persisted but not yet applied (gated by Live, by the Rehearsal deferral, or by a closed library).
- **Tombstone**: a record that marks an item deleted, carrying the delete's stamp and the item's last fields (section 8.4).
- **History entry**: a local snapshot of an item before a sync change replaced or deleted it (section 10).
- **Released**: the engine object is destroyed and no CloudKit operation exists; the coordinator keeps capturing local changes into the ledger.

## 4. Current code (verified 2026-10-31)

### 4.1 Library storage and identity

- **Folder and layout:** `LibraryRoot` (`Packages/SegueCore/Sources/Support/LibraryRoot.swift:18-72`): `songs/`, `setlists/`, `shows/`, `filters/` (26-44), `appDirectory` = `<root>/.segue` "app-private, rebuildable state" (46-49), `lockURL` = `.segue/library.lock` (51-55), `indexDatabase` = `.segue/index.sqlite` "Safe to delete" (57-60), suffixes (62-71). The folder is user-picked and held by a security-scoped bookmark in UserDefaults `libraryFolderBookmark` (`Packages/SegueUI/Sources/SegueUI/App/LibraryLocation.swift:21`).
- **Other `.segue` content:** `LibraryUpgrade` keeps one-time upgrade marks in `.segue/upgrades.json` (`Library/LibraryUpgrade.swift:36-38`, written 62-75). This is per-library and not rebuildable: it stays in the folder.
- **Store:** `LibraryStore` (actor, `Library/LibraryStore.swift:55-88`) "a rebuildable GRDB index at `.segue/index.sqlite` (a projection; only this store writes to it)"; `open(root:)` creates `songs/`, `setlists/` and `.segue/` and opens the index at `root.indexDatabase` (98-118); `updateSong(id:source:basedOn:)` checks the on-disk hash and throws `.conflict(.deleted / .sourceChanged)` (165-181); `overwriteSong` (186-192); `refresh()` (248-289); `rebuildIndex()` deletes and re-creates at the same URL (293-). Deletes: `deleteSong(id:)` / `restoreSong(_:)` return and take a `TrashReceipt` (`LibraryStore+Trash.swift:14, 49`).
- **Index:** `SongIndex.schemaVersion = 4`, stored version `schemaVersion * 1000 + RomanNormalizer.version` (`Library/SongIndex.swift:62-66`); `open(at:)` re-creates a missing, stale or corrupt index (83-94); `deleteFiles` removes the db and its `-wal` / `-shm` (96-103).
- **Library lock:** `LibraryLock` (`Support/LibraryLock.swift:14-58`) takes `flock(LOCK_EX | LOCK_NB)` on `root.lockURL`, creating `.segue/` (39-53). Its purpose (3-6): the Personal and App Store flavours have different bundle IDs, so this lock is what stops both opening one library. Its own caveat (12-13): "network or synced folders that do not honour `flock` are not protected". Taken first in `LibrarySession.open` (`SegueUI/App/LibrarySession.swift:157-165`); `LibraryLockPolicy.exclusive / .unlocked` (221-235); "in use" mapped to `inUseByAnotherCopy` in `AppModel.open` (`SegueUI/App/AppModel.swift:347-399`, 387).
- **Show locks:** `ShowClaim` `flock`s `shows/<ulid>.show.lock` (`Shows/ShowClaim.swift:4-40`; release with `removingFile` 49-58); path from `ShowStore.claimURL` and `claimSuffix = ".show.lock"` (`Shows/ShowStore.swift:176-182`); `claim` / `isClaimedElsewhere` (159-174).
- **File IO:** every write goes through the `FileSystem` port; `LiveFileSystem.writeAtomically` uses `NSFileCoordinator` `.forReplacing` (`Support/FileSystem.swift:37-38, 165-170`); `trashItem(at:)` (45, 194).
- **Archive:** `LibraryArchive.includedFolders = ["songs", "setlists", "shows", "filters"]` (`Library/LibraryArchive.swift:26-27`): an allowlist, so `.segue/` and anything else at the root (a future `history/`) is excluded by construction (doc 11-17).
- **Activation refresh:** no file watching; `AppModel.observeActivation` refreshes on `didBecomeActiveNotification` and saves on resign, never while performing (`SegueUI/App/AppModel.swift:225-250`).

### 4.2 ULIDs, clock, timestamps

- `ULID` (`Support/ULID.swift:7-31`); `IDGenerator` (105-108); `ULIDGenerator(clock:seed:)` with a seeded SplitMix64 stream for tests and monotonic IDs (110-131).
- `Clock` protocol (`Support/Clock.swift:9-12`), `SystemClock` (15-20), `ManualClock` with `set` (24-44), `MonotonicClock` for durations only (46-72).
- IDs: `SongID` (`Library/SongRecord.swift:6`), `SetlistID` (`Setlists/Setlist.swift:9`), `ShowID` (`Shows/ShowRecord.swift:9`, also the show file name), `SmartFilterID` (`Library/SmartFilter.swift:9`), `SetlistItemID`, `CueID`. File names are slugs except shows.

### 4.3 Sidecars, setlists, shows, filters

- **Sidecar** (`Library/Sidecar.swift:14-42`): `currentSchemaVersion = 6` (23); top-level fields `id`, `tags`, `proficiency`, `notes`, `cues`, `displayPrefs`, `live`, `bass`, `parts`, `createdAt`, `updatedAt` (26-42). Newer schema opens read-only and is never rewritten (doc 8-11).
- **Setlist** (`Setlists/Setlist.swift:285-304`): `currentSchemaVersion = 6` (287); `id`, `schemaVersion`, `name`, `entries` (each with `itemId`, `kind`, `overrides`, `note`, `locked`, `arrangement`, 158-170), `createdAt?`, `updatedAt?`, `venue`, `date`, `targetDuration`, `changeoverSeconds`; `readOnly` runtime only. Store edits: `create`, `addSong`, `move`, `remove`, `rename`, `duplicate`, `insertSongs`, `updateDetails`, `replaceEntries` (`Setlists/SetlistStore.swift:118-273`); delete / restore (`SetlistStore+Trash.swift:12, 33`).
- **ShowRecord** (`Shows/ShowRecord.swift:296-335`): `ShowKind.gig / .rehearsal` (62-68, a rehearsal run is "never in the gig log or play stats"); `endedAt`, `closure`, `gig: GigDetails` (venue, date, notes, rating, 249-254), `reorderReview`. `ShowStore.save` (122), `updateGigDetails` (214), `delete` / `restore` (235, 258), `launchCheck` (292) resumes or auto-closes unended shows; shows feed play stats through `playHistory` (`LibrarySession.swift:191-195`).
- **SmartFilter** (`Library/SmartFilter.swift:179-188`): `id`, `schemaVersion`, `name`, `conditions`, `updatedAt`. Store: `create`, `rename`, `update`, `replace`, `delete`, `restore` (`Library/SmartFilterStore.swift:138-204`).
- **Welcome seeds:** the manifest's `tag` is the seed identity (`Library/WelcomeSeed.swift:9-29`); `seedSongs`, `seedInventory`, `seededMatch(for:tag:)` (`Library/LibraryStore+Welcome.swift:19, 68, 92`). Each library mints fresh ULIDs, so two seeded Macs hold the same songs under different IDs.
- **Look-alikes:** `NearDuplicateIndex` with `Breakdown` / `Match`, `contentHash(of:)`, `match(...)`, `identical(contentHash:)` (`Library/NearDuplicates.swift:10-151`).

### 4.4 Settings stores

| Store / key | Where | Sync? (R177) |
| --- | --- | --- |
| `instrument.profile` (`InstrumentProfile`: `playsBass`, `strings`, `tuning`, `bassNotes`, `chordBeside`, `stageNeck`, `fretboard`) | `SegueUI/Settings/InstrumentProfileStore.swift:16`; `Editing/InstrumentProfile.swift:10-22` | yes |
| `live.settings` (`minLyricSize`, `startShortcut`, `endShortcut`, `hiddenChecklistItems`, `defaultColumns`, ...), `live.rehearsalShortcuts`, `live.metronome` | `Settings/LiveSettingsStore.swift:14, 30, 41`; `Shows/LiveSettings.swift:30-39` | yes |
| `audio.settings` (`chordSound`, `chordStyle`, `bassSound`, `volume`, `outputUID`, `outputName`, play-along and tap fields) | `Settings/AudioSettingsStore.swift:10-33, 111` | yes **except `outputUID` / `outputName`** (per Mac) |
| `appearance.mode` | `Settings/AppearanceStore.swift:40` | yes |
| `setlists.defaultChangeoverSeconds` | `Settings/ChangeoverSetting.swift:9` | yes |
| `fill.editor` | `Settings/FillEditorSettings.swift:26` | yes |
| `shape-library.json` (Application Support) | `UserShapeLibrary` (`Diagrams/ShapeResolver.swift:8`); URL `AppModel.swift:125-130` | yes |
| `bindings.json` (Application Support): `InputTrigger.key` only today; "phase 6 adds a `.midi` case" | `Shows/InputBindings.swift:90-120, 137-139`; URL `Live/LiveDependencies.swift:44-48` | key bindings yes; any future `.midi` trigger per Mac |
| `privacy.consent`, `analytics.firstLaunch` | `Services/ConsentStore.swift:19`, `Services/AnalyticsSupport.swift:65` | per Mac |
| `ai.useAI`, downloaded models | `Settings/AIPreferences.swift:11`; app group store `SegueAI/ModelStore/ModelStoreLocation.swift:9-31` | per Mac |
| `onboarding.completed`, `welcome.decision`, `welcome.seeded`, `whatsNew.lastSeenVersion`, `review.*`, `settings.selectedPane`, `tips.resetPending`, `services.environment`, `libraryFolderBookmark` | `App/OnboardingStore.swift:41-43`, `App/WhatsNew.swift:271`, `App/ReviewPrompt.swift:12-13`, `App/PolishDependencies.swift:130-131`, `App/Sources/ServicesWiring.swift:225`, `LibraryLocation.swift:21` | per Mac |

### 4.5 Entitlements and release checks

- All three files (`App/Segue.entitlements`, `App/SegueAppStore.entitlements`, `App/Segue-Debug.entitlements`) hold sandbox, user-selected read-write, app-scope bookmarks, `network.client`, the Apple-events pair (R59) and the app group `V6BM673U35.dev.ryandsilva.segue.models` ("A team-prefixed group needs no portal registration and no profile entry on macOS", lines 25-30); Debug adds the `/private/tmp/segue-e2e/` temporary exception (31-35). **No iCloud, CloudKit or push.** `SegueAppStore.entitlements:4-5`: "The set is asserted exactly by scripts/verify-archive.sh check 4; change both together."
- `scripts/lib/verify-common.sh:31-51` `app_entitlements`: the exact set "the same in both flavors' Release builds". `scripts/verify-archive.sh:154-190` check 4: the signed set must equal `app_entitlements` plus `application-identifier` and `team-identifier` (the Quick Look appex gets sandbox only). `scripts/verify-appstore.sh:164-176` compares a local build against `app_entitlements` ignoring only `get-task-allow`. Check 3 extracts every `-Segue...` launch flag from `App/Sources/LaunchOptions*.swift` and fails if any ships (`verify-common.sh:16-29`).
- `Project.swift:159-219` `appTarget`: per-flavour entitlements path (166), app dependencies (167-177); `Project.swift:250-258` the Debug-Personal entitlements override; deployment target macOS 26.0 (48, 79). CKSyncEngine needs macOS 14 (research 3).
- Vendor isolation precedent: `Packages/SegueVendorServices/Package.swift:1-35` (the only package that imports a vendor SDK, linked only by the app targets) and the SwiftLint `vendor_sdk_import` rule (`.swiftlint.yml:119-128`).

### 4.6 Shows, sessions and UI hooks

- `AppModel.startShow(_:kind:)` flushes the editor and refreshes the library before the checklist, then `ShowController.start` (`SegueUI/App/AppModel+Shows.swift:91-130`); `finishRun(_:)` ends the run, closes the stage and runs the end Shortcut (389-420). `startSongSession(_:kind:slot:onEnd:)` and `finishSongSession` (`App/AppModel+SongSession.swift:28-40, 113`). A pending resume blocks both (`pendingResume == nil` guards).
- Library footer: `LibraryViews` puts `loadIssuesFooter` in `.safeAreaInset(edge: .bottom)` (`Library/LibraryViews.swift:146, 211-225`); the sidebar has its own (`Library/MainSidebar.swift:51, 174`).
- Settings panes: `general`, `appearance`, `instrument`, `audio`, `live`, `ai`, `privacy`, `data` (`Settings/SegueSettingsView.swift:18-71`).
- Launch options: `App/Sources/LaunchOptions.swift:68-96` (`-SegueLibraryPath`, `-SegueResetState`, `-SegueTestDefaults`, ...).
- Analytics: closed vocabulary `AnalyticsEvent` (`Services/AnalyticsEvent.swift:16-92`), rows documented in `docs/release/specs/WS3-services.md` (rows 29-30 at 320-321 are the latest at writing); `LibraryLocation` (`AnalyticsEvent.swift:181-185`).
- No `UserNotifications` use anywhere today; no `NSFileVersion` or file presenters.
- Help links: `Packages/SegueUI/Sources/SegueUI/App/SegueLinks.swift` (`guide/...` cases from 53); guide sidebar `guide/astro.config.mjs:55` ("Settings and data": AI, Privacy, Back up and restore).

## 5. S0 - library state out of the folder, and the file-sync warning

Independent of sync; fixes research 1.1 (an index and a lock inside a file-synced folder can corrupt and protect nothing). It also gives sync its library ID and the per-library state directory.

### 5.1 Library ID

- New file `<root>/.segue/library.json`: `{"schema": 1, "id": "<ULID>", "createdAt": "<ISO8601>"}`, written atomically through `FileSystem`. Minted from the injected `IDGenerator` on the first open of a folder that lacks it (or holds an unreadable one; the bad file is moved to the Trash first). New SegueCore type `LibraryIdentity` (`Support/LibraryIdentity.swift`), read before anything else in the open (by `LibraryState.open`, ahead of the lock, 5.2).
- `.segue/` is redefined (doc comment in `LibraryRoot`): "per-library state that travels with the folder: its identity and its upgrade marks. Never a database or a lock." `LibraryRoot.lockURL` and `indexDatabase` are removed; their callers move to `LibraryStateDirectory` (5.2).
- The ID is never derived from the path, so moving or renaming the folder keeps it, and an archive restored into a new folder gets a fresh one (its items still merge by ULID, section 12).

### 5.2 Where the state goes: the shared app group, keyed by library ID

R177 says "Application Support keyed by library ID". The **sandbox container's** Application Support is per flavour (`Library/Containers/<bundle id>/`), so a lock there would no longer stop the Personal and App Store builds opening one library at once, which is the lock's whole purpose (`LibraryLock.swift:3-6`). The app group `V6BM673U35.dev.ryandsilva.segue.models` is already in every entitlements file and shared by both flavours (R67, R100), so the state goes to **its** Application Support:

```
<group container>/Library/Application Support/
  Libraries/<libraryID>/
    index.sqlite (+ -wal, -shm)     the SongIndex (rebuildable)
    library.lock                    LibraryLock's flock
    shows/<showULID>.show.lock      ShowClaim's flock
    state.json                      {lastRoot, lastOpened, rootIdentifier, rootBookmark,
                                     fileSyncWarningDismissed}
  Device/device.json                this Mac's device ULID (S2; shared by both flavours)
  Sync/                             the ledger and engine lock (S2, section 9.1)
```

- New SegueCore type `LibraryStateDirectory` (`Support/LibraryStateDirectory.swift`): `init(base: URL, libraryID: ULID)` with `indexDatabase`, `lockURL`, `showLockURL(_:)`, `stateFile`. The base is injected through a `LibraryStateLocation` value: `.appGroup()` in the app (`FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`, the same call `ModelStoreLocation.appGroup` makes), a temp folder in tests. When the group container is unreachable (a build without the entitlement, command-line tools) it falls back to the flavour's own Application Support and logs a diagnostic; the cross-flavour lock is then lost and Settings > Data says so.
- `LibraryLock(root:)` becomes `LibraryLock(state:)`, `ShowStore` takes the state directory for claims, `LibraryStore.open(root:state:)` opens the index there. The `-SegueStatePath <dir>` launch option (new, in `LaunchOptions.swift`; check 3 catches it automatically) points the base at a per-run folder so every E2E run starts from a clean state (owner reset rule).
- **Copy versus move (R185):** `state.json` records the folder's file identifier (`URLResourceValues.fileIdentifier`, the inode, macOS 13.3+; `fileResourceIdentifier` is not used because Apple documents it as not persistent across restarts) and a security-scoped bookmark to the folder (`LibraryFolderReference`), both rewritten on every open, plus `lastRoot` for diagnosis. On open, if the identifier differs from the stored one and the stored bookmark still resolves to another existing folder whose `library.json` has the same ID, this folder is a Finder copy: it gets a new ID (old `library.json` to the Trash, new one written) and a one-time note "This folder is a copy of another Segue library, so it now has its own identity." If the identifier differs and the original is gone (a move to another volume), or the identifier is unchanged (a move or rename on the same volume), it is the same library and keeps its ID. A re-keyed copy is never joined to any iCloud zone (sync stays off for it). Identity is resolved and the lock taken (`LibraryState.open`) before `LibraryStore.open(root:state:)`, because the lock path needs the ID; after locking, `library.json` is re-read and a mismatch (two copies of Segue minting at once) starts over on the winning ID.
- **TTL backstop:** at launch, `Libraries/<id>/` folders not opened for 180 days and whose lock is free are moved to the Trash (an index is rebuildable). Never a folder whose library is open.

### 5.3 Upgrade from the in-folder state

On the first open by an S0 build (recorded in `upgrades.json` as `stateMoved`):
1. Build the new index in the state directory (a full scan, as after `rebuildIndex`).
2. Delete `<root>/.segue/index.sqlite`, `-wal`, `-shm` with `SongIndex.deleteFiles` (a projection, not user data).
3. Try `flock(LOCK_EX | LOCK_NB)` on `<root>/.segue/library.lock` and each `shows/*.show.lock`: if it succeeds (no older build holds it), unlink it; if not, leave it and retry next open.
4. An older Segue build that still uses the in-folder lock is no longer excluded by the new one. Both flavours are built from one tree, so this is accepted (R179: pre-S0 builds are not covered by the moved lock).

### 5.4 The file-sync folder warning

- **Detection** (`LibraryFolderKind.detect(_ url: URL) -> .local | .iCloudDrive | .fileProvider(name)`, SegueUI `App/LibraryFolderKind.swift`): `URLResourceValues.isUbiquitousItem` on the root (true for iCloud Drive, including Desktop and Documents in iCloud); else the resolved real path under `<real home>/Library/CloudStorage/` (Dropbox, Google Drive, OneDrive, Box; the folder name gives the provider) or `<real home>/Library/Mobile Documents/`. The real home comes from `getpwuid(getuid())`, because the sandboxed `homeDirectory` is the container. Verify both APIs with `apple-api-check`.
- **When:** after each library open, and in the folder picker when a folder is chosen.
- **Surface:** a dismissible banner at the top of the library list, never a modal, never during a show, with a muted grey icon (an info note, not an error; R185): "This library is in iCloud Drive. Files there can be moved off this Mac to save space, so a song might not be here at a gig. For shows, keep your library in a folder on this Mac." (v1.0 wording, R195: v1.0 has no Settings > Sync, so the banner and the guide section name the risk and the local-folder fix only; the sync slice that adds the pane may point at it then.) Buttons **Learn More** (guide `library-folder#file-sync`) and **Don't Show Again** (remembered per library ID in the state directory's `state.json`). Settings > Data shows the same line permanently while it applies. A Dropbox / other provider reads "is in Dropbox" with the same text.
- **Analytics:** `LibraryLocation` gains `fileSyncFolder` for `libraryCreated` / opened (no provider name).

### 5.5 S0 tests

In-process (`LibraryStateTests`, `LibraryIdentityTests`, `LibraryFolderKindTests`), on real temp folders: ID minted once and stable across reopen, move and rename; a copy with the original present is re-keyed, and only the copy; a folder whose identifier changed and whose original is gone (the cross-volume case) keeps its ID; the index and locks are created only under the state directory (assert nothing new appears in `<root>/.segue/` but `library.json` and `upgrades.json`); the upgrade deletes the old index and removes a free lock but leaves a held one; two `LibraryLock(state:)` exclude each other; the TTL prunes only stale, unlocked folders. Detection is table-driven over paths with an injected resource-value reader. The banner is asserted in the existing library UI test class with a `-SegueLibraryFolderKind iCloudDrive` launch override (one test, `make e2e-one` for that class).

## 6. Architecture: the port and its adapters

### 6.1 Modules

- **SegueCore `Sync/`** (new target in the SegueCore package, platform-neutral, no CloudKit import): `SyncPort`, value types, `HLC`, `FieldMerger`, `RecordCodec`, `SyncLedger`, `ChangeCapture`, `RemoteApplier`, `HistoryStore`, `ShowGate`, `SyncCoordinator`, `FakeCloudSync` (in a `SyncTesting` product used by tests and the E2E fake backend, never by release code paths except through the `fake` backend selection).
- **`Packages/SegueCloud`** (new package, `CloudSync` product): the only code that imports CloudKit. Depends on SegueCore. Linked only by the two app targets (`Project.swift` `appTarget` dependencies), like `SegueVendorServices`. A SwiftLint rule `cloudkit_import` (regex `^\s*(@\w+(\([^)]*\))?\s+)*import\s+CloudKit`) fails a CloudKit import anywhere else; `Packages/SegueCloud` is excluded from it.
- **SegueUI `Sync/`**: the settings bridge (section 14), the status model, the footer indicator, Settings > Sync, the join flow, Previous Versions, the notification scheduler.

### 6.2 The port

```swift
/// SegueCore Sync. Core sync logic depends only on this.
public protocol SyncPort: Sendable {
    var capabilities: SyncCapabilities { get }
    /// Starts (or resumes from `state`) one engine for the private database and delivers
    /// events to `sink` until `stop()`. Never blocks on the network.
    func start(state: SyncEngineState?, zones: [ZoneName], sink: any SyncEventSink) async throws
    /// Releases every operation and all network activity; returns once no operation exists.
    func stop() async
    /// Pending saves and deletes, by key. The adapter asks `sink.record(for:)` for the
    /// contents only when it sends, so repeated edits to one item coalesce.
    func enqueue(_ changes: [PendingChange]) async
    func fetchNow() async throws
    func sendNow() async throws
    func createZone(_ zone: ZoneName) async throws
    /// "Delete iCloud Data": explicit and confirmed only.
    func deleteZone(_ zone: ZoneName) async throws
    func accountStatus() async -> SyncAccountStatus
}

public struct SyncCapabilities: Sendable, Equatable {
    public var pushDrivenFetch: Bool     // remote changes arrive without polling
    public var maxBatch: Int             // 250 for CloudKit
    public var maxInlinePayloadBytes: Int
}

public protocol SyncEventSink: Sendable {
    func handle(_ event: SyncEvent) async
    /// The record to send for `key` now (nil = nothing to send any more).
    func record(for key: ItemKey) async -> SyncRecord?
}

public enum SyncEvent: Sendable {
    case fetched([SyncRecord], deletedKeys: [ItemKey])     // deletedKeys: hard deletes only (zone purge)
    case sent(saved: [ItemKey], failed: [SendFailure])     // .conflict(server: SyncRecord), .quota, .rejected, ...
    case stateUpdated(SyncEngineState)
    case zoneDeleted(ZoneName, reason: ZoneDeletionReason) // .deleted, .purged, .encryptedDataReset
    case account(SyncAccountChange)                        // .signIn, .signOut, .switched
    case transient(SyncTransientProblem)                   // offline, rate limited (status only)
}
```

`SyncRecord` (section 7.2) is a plain value: no `CKRecord`, no raw vendor blob, crosses the port inward. Outward events may carry a `debugDescription` string for the diagnostic log only; core never branches on it. `SyncEngineState` is opaque `Data` the adapter produces and consumes (the serialized `CKSyncEngine.State`); core only stores it.

### 6.3 Adapters

- **`FakeCloudSync`**: an in-memory server shared by several "devices": zones, records with change tags, `serverRecordChanged` with the server copy on a stale tag, tombstones, zone deletion and purge, account events, quota errors, batches capped at `maxBatch`, and a seeded `SyncScheduler` that decides delivery order, latency, drops (retried), duplicates and pushes (section 17.1). Its server can be persisted to a JSON file for the E2E backend.
- **`CloudKitSync`** (SegueCloud): wraps `CKSyncEngine` (one per process, private database), maps `SyncRecord` to and from `CKRecord` (section 7), maps `CKError` codes to `SendFailure` / `SyncTransientProblem` (automatic retries stay the engine's, research 3), persists nothing itself (the state goes out through `stateUpdated`). Its private fast paths must be observationally equivalent to the portable contract, proven by the shared conformance suite (section 17.2).

### 6.4 Selection and injection

- `sync.backend` = `off | cloudkit | fake`. Release builds: `cloudkit` when the iCloud entitlement is present, else `off`. The launch option `-SegueSyncBackend fake` with `-SegueSyncFakeServer <file>` selects the fake (Debug only; check 3 fails if either flag string ships). `sync.enabled` is per library ID, stored in the ledger, default off.
- `SyncCoordinator` gets `clock: any Clock`, `ids: any IDGenerator`, `random: any RandomSource` (seeded in tests; used only for retry jitter and the simulation scheduler, never for merge decisions), `fileSystem`, the stores, the ledger and the port. No `Date()` or `UUID()` or `SystemRandomNumberGenerator` inside `Sync/` (a lint rule `sync_no_ambient_time` greps the folder for `Date()`, `.now`, `UUID()`, `random(`).
- **What gets no port:** the merge policy, the ledger, history and the applier are core code with one implementation; the clock, IDs and randomness are dependency injection for testing, not pluggability. Swapping the bound adapter (fake to CloudKit, or a future one) invalidates the ledger's server state (change tags, engine state) and forces a full re-merge by ULID; it never reuses them.

## 7. Record schema

### 7.1 Zones and record names

- **Zones:** `library-<libraryULID>` per joined library, plus one `settings` zone for the musical settings (they are app-wide, not per library; one engine still covers both zones, as CKSyncEngine is per database). R179: settings sync in their own zone.
- **Record types (CloudKit schema, fixed for good):** `Library` and `Item`. Because production fields can never be deleted (research 3), item contents are **not** CloudKit fields: they travel in one encrypted payload, so adding a sidecar key later never touches the CloudKit schema.

| Type | Fields (CloudKit) | Notes |
| --- | --- | --- |
| `Library` (record name `library`, one per library zone) | `protocol` Int64, `minProtocol` Int64, `payload` Bytes (encrypted: name, createdAt, created-by device) | zone metadata, read first on fetch |
| `Device` (record name `device-<deviceULID>`, in each zone it writes) | `payload` Bytes (encrypted: the Mac's name, `Host.current().localizedName`, and its Segue version) | for "Replaced by a change from MacBook Neo"; never in analytics |
| `Item` (record name `<kind>-<ULID>`, or `settings-<group>`) | `kind` String, `protocol` Int64, `schema` Int64, `payload` Bytes (encrypted), `payloadAsset` Asset (only above the inline limit) | one per item |

- `protocol` is the sync wire version (starts at 1); `schema` is the item's own file schema version (`Sidecar.currentSchemaVersion`, `Setlist.currentSchemaVersion`, ...). Section 13.5 uses both.
- Payloads use `encryptedValues` (end-to-end with Advanced Data Protection; verify with `apple-api-check`). The inline limit is 700 KB of payload; above it the payload goes to `payloadAsset` and `payload` is empty (records' own fields are limited to 1 MB, research 3).

### 7.2 The payload

Canonical JSON (sorted keys, no whitespace), so equal content has an equal hash:

```json
{
  "kind": "song",
  "id": "01JC...",
  "schema": 6,
  "fields": {
    "source": {"v": "{title: Kitabon}\n...", "t": "000001761900000000-000003-01JD..."},
    "tags":   {"v": ["Welcome", "slow"],       "t": "000001761900004000-000000-01JE..."}
  },
  "deleted": null,
  "hints": {"slug": "kitabon"}
}
```

`t` is the stamp's sortable string form (section 8.1). `hints` never merge (the slug is a local file name; identity is the ULID). `SyncRecord` is the decoded form: `key: ItemKey` (kind + id), `schema`, `fields: [FieldName: FieldValue]` (`FieldValue` = the field's canonical JSON bytes), `stamps: [FieldName: HLCStamp]`, `deleted: HLCStamp?`, `hints`.

### 7.3 Fields per kind

| Kind | Fields (each merges alone) | Not synced |
| --- | --- | --- |
| `song` | `source` (the whole `.cho` text), and every sidecar top-level key: `tags`, `proficiency`, `notes`, `cues`, `displayPrefs`, `live`, `bass`, `parts`, `createdAt` (first writer, never changes) | `updatedAt` (recomputed on write), `id` (the key), `schemaVersion` (record level), the slug (a hint) |
| `setlist` | `name`, `entries` (the whole ordered list with overrides, notes, locks, arrangements), `venue`, `date`, `targetDuration`, `changeoverSeconds`, `createdAt` | `updatedAt`, `readOnly` |
| `filter` | `name`, `conditions` | `updatedAt` |
| `show` | every top-level `ShowRecord` key; in practice only `gig` and `reorderReview` change after a show ends | `readOnly`; **unfinished shows never sync** (section 7.4) |
| `settings-<group>` | each top-level property of the group's stored value (section 14.1) | the per-Mac keys (section 14.2) |

`entries` merges whole (R177 "per top-level field"): a reorder on one Mac and a slot note on the other is a clash on `entries`, and the older one goes to history. R179: setlist entries merge as one field.

### 7.4 Shows

- A show record is enqueued only once it is finished (`endedAt != nil` and `closure` set). An unfinished show, including a running Rehearsal or a crash-resumable Live show, never leaves its Mac: otherwise the other Mac's `launchCheck` would offer to resume or auto-close a show that is running elsewhere.
- Finished **gig** shows sync (the Gig Log, play stats on both Macs through `playHistory`). Finished **rehearsal** records stay local by default (they are crash-resume records, never in the Gig Log). R179: finished rehearsal records do not sync.

### 7.5 Field lists are checked, not remembered

`RecordCodecTests` encodes a fully populated value of each kind and asserts the field set equals the type's encoded top-level keys minus the documented "not synced" list. A new sidecar, setlist, show or filter key added by any sibling workstream therefore fails this test until it is added to section 7.3's table in code.

## 8. HLC and field-level merge

### 8.1 The hybrid logical clock

`HLCStamp { wall: UInt64 (Unix milliseconds), counter: UInt32, device: ULID }`, totally ordered by `(wall, counter, device)` (device compared by its string form, the R177 tiebreak). String form `%018llu-%06u-<deviceULID>` sorts the same way.

`HLC` (one per device, persisted in the ledger after every tick so a relaunch never goes backwards):
- **Local event:** `now = clock.now()` in ms; if `now > last.wall` then `(now, 0)` else `(last.wall, last.counter + 1)`.
- **Receive:** `wall = max(last.wall, remote.wall, now)`; counter = the matching rule of the standard HLC (increment the counter of whichever input owns `wall`, 0 if `now` alone does).
- **Skew:** stamps are compared as they are on every Mac (determinism and convergence come first). A remote stamp more than 5 minutes ahead of `now` is still accepted, logged as a `clockAhead` diagnostic and shown in Settings > Sync ("The clock on MacBook Neo is ahead by 12 minutes"). The local HLC never jumps more than 24 hours on receive (a stamp beyond that is clamped for the local clock only, not for the comparison).

### 8.2 Stamping local changes

The ledger keeps, per item and field, the stamp and the hash of the value last written or synced. When a local change is captured (section 9.2), the item is decoded into fields; each field whose hash differs from the ledger gets a fresh local stamp; unchanged fields keep theirs. A field changed **outside Segue while it was not running** (a `.cho` edited in another editor) is stamped from the file's modification date (`wall = mtime ms`, `counter = 0`) rather than "now", so the stamp says when the edit happened, not when it was noticed.

### 8.3 The merge (pure `FieldMerger`)

`merge(local: ItemState?, remote: SyncRecord) -> MergeResult { merged: ItemState?, toWrite: [FieldName], lost: [LostValue], sendBack: Bool }`:

1. For every field present on either side: the winner is the value with the greater stamp. A field missing on one side (an older build that does not know it, or a field never set) is not a deletion: the side that has it wins.
2. Equal stamps imply equal values (a stamp is written once); if values differ under equal stamps (a bug), the greater canonical hash wins and an `invariant` diagnostic is logged.
3. `lost` = each field where the losing value differs from the winner and the losing value was the local one (it goes to history before the write, section 10).
4. `sendBack` = any field where the local side won (the server copy is stale).
5. The same inputs produce the same output on every Mac: this is a last-writer-wins register per field, so the two Macs converge whatever the delivery order.

### 8.4 Deletes and tombstones

- A delete is a write: the deleting Mac stamps `deleted = HLC.tick()` and sends the item's record with its last fields kept and `deleted` set (a tombstone). CloudKit records are never hard-deleted except by "Delete iCloud Data" (zone deletion).
- Alive or dead: an item is alive when `max(field stamps) > deleted` (or `deleted` is nil). So an edit made after the delete (on a Mac that had not yet heard of it) brings the item back on both Macs, and a delete after the last edit wins on both. Both orders converge.
- Applying a winning tombstone: the item's current files go to history first (reason `deleted elsewhere`), then the store's ordinary delete removes it (section 9.5).
- Restoring from history (section 10.3) writes the item again with fresh stamps newer than the tombstone, so it comes back on the other Mac too.
- Tombstone lifetime: kept 180 days, then the Mac that wrote the delete strips its payload to the key and `deleted` stamp (one record per deleted item stays). R179.

### 8.5 Worked examples

| Case | Desktop | Neo | Result on both |
| --- | --- | --- | --- |
| Different fields | adds tag `slow` at 10:00:00 | fixes a lyric (`source`) at 10:00:05 | both kept: tags from Desktop, source from Neo; no history entries |
| Same field | source edit at 10:00:00 | source edit at 10:00:05 | Neo's source wins; Desktop's version goes to Desktop's history ("Replaced by a change from MacBook Neo") |
| Offline both | edits `notes` at 09:00 offline | edits `notes` at 11:00 offline, syncs at 12:00 | Neo's notes win when Desktop comes online at 13:00, Desktop's 09:00 notes to its history |
| Delete vs later edit | deletes the song at 10:00 | (offline) edits its tags at 10:30 | the song survives with Neo's tags; Desktop restores it from the record and writes a history entry "Brought back by a change from MacBook Neo" |
| Delete vs earlier edit | deletes at 10:30 | edited at 10:00 | deleted on both; Neo's copy goes to Neo's history |
| Equal wall clock | both edit `name` at 10:00:00.000, counters 0 | | the greater device ULID wins on both |

## 9. Ledger, change capture and the applier

### 9.1 The ledger

`SyncLedger` (GRDB) at `<group>/Library/Application Support/Sync/ledger.sqlite`, shared by both flavours on one Mac; `Sync/engine.lock` (`flock`) makes sure only one running Segue owns the engine at a time (the other shows "Syncing in the other copy of Segue"). Tables:

| Table | Columns | Purpose |
| --- | --- | --- |
| `meta` | key, value | device ULID, HLC last stamp, account fingerprint (hash of the user record ID), backend kind, protocol |
| `engine` | state blob, updatedAt | `SyncEngineState` |
| `zones` | zone, libraryID, enabled, joinedAt, lastFetch, lastSend, status | which libraries sync |
| `fields` | zone, key, field, stamp, valueHash | last written or synced value per field |
| `items` | zone, key, systemFields (encoded CloudKit system fields), deleted stamp, lastSyncedHash | change tags for conflict detection |
| `pending` | zone, key, since, reason | queued sends (survive relaunch and Live) |
| `inbox` | zone, key, record payload, receivedAt | fetched, not yet applied |
| `devices` | device, name, lastSeen, version | for history labels and Settings > Sync |

It is a **rebuildable projection**: if it is missing or unreadable, the coordinator recreates it, re-stamps local fields from file modification dates (8.2), and does a full fetch; equal values are no-ops (idempotent replay keyed on ULID + field hash). It is never in the library folder and never in the archive.

### 9.2 Change capture

- **Store hooks:** each store gets an injected `ItemChangeObserver` (default no-op): after every successful local write or delete, `observer.changed(ItemKey, .local)` (song create, update, overwrite, rename, display prefs, tags, cues, notes, bass, parts, delete, restore; setlist create to replace-entries and delete / restore; filter create to replace and delete / restore; show save when finished, `updateGigDetails`, `resolveReview`, delete / restore). The coordinator then reads the item, stamps changed fields (8.2) and enqueues a pending send.
- **Rescan:** at library open, on app activation (the existing hook, `AppModel.swift:225-250`) and at show end, every item's file hash is compared with `items.lastSyncedHash`; a difference is captured as a local change (edits made in other editors, or in Finder). Cheap: hashes come from the index's existing content hashes where available.
- The `.remote` origin never reaches the observer (9.4), so applies never echo.

### 9.3 Sending

The adapter asks `record(for:)` at send time; core reads the current files, encodes the fields with their ledger stamps and returns the record (or a tombstone if the item is gone). Batches are ordered songs, then filters, then setlists, then shows, so a setlist rarely arrives before its songs (a setlist that does shows its missing slots as today until they land). `sent(saved:)` updates `items.systemFields` and clears `pending`. A `.conflict(server:)` failure merges the server record (8.3), applies any remote-won fields locally (with history), and re-enqueues.

### 9.4 Applying

`RemoteApplier` drains the inbox in receipt order whenever the gate is open (section 11) and the record's zone is the open library (or the settings zone):
1. Decode; check protocol and schema (section 13.5).
2. Load the local item (files plus ledger stamps); merge (8.3).
3. Write history for `lost` (section 10) **before** any file changes.
4. Write the winning fields through the store's new remote-apply methods (`LibraryStore.applyRemoteSong`, `SetlistStore.applyRemote`, `SmartFilterStore.applyRemote`, `ShowStore.applyRemote`, and their remote deletes), which write exactly like the local paths (atomic, coordinated, index updated) but do not call the observer. A new song uses `hints.slug` if free, else the next free slug.
5. Update the ledger (`fields`, `items`) in the same coordinator step, so the next rescan sees matching hashes.
6. If `sendBack`, enqueue a send. Remove the inbox row.

A store conflict during step 4 (the user saved the same song between steps 2 and 4) aborts the apply for that item; it stays in the inbox and is retried after the local change is captured, so the merge sees both.

### 9.5 Remote deletes mirror (R177)

The applier deletes the item with the store's ordinary delete path (`deleteSong(id:)`, `SetlistStore.delete`, ...), the same thing the user's own delete does, after the history snapshot. The item disappears from the library, setlists show the slot as missing as they do today, and the user recovers it from Previous Versions > Recently Deleted. The store's delete moves the files to the Finder Trash (repo invariant: user data is never `removeItem`d); that copy is a backstop, not the recovery path the UI offers. Open question 1 asks whether the Trash copy should be skipped.

### 9.6 Libraries that are not open

Fetched records for a joined library that is not the open one stay in the inbox until that library opens; nothing is sent for it (its changes are captured by the rescan when it opens). Records for a zone no local library has joined are ignored and not stored.

## 10. History and Previous Versions

### 10.1 Store

- `<root>/history/<kind>/<ULID>/<stamp>.json` (the item snapshot) and, for songs, `<stamp>.cho` beside it. Inside the library because it is not rebuildable; outside `.segue/` for the same reason. Never synced, never in the archive (the archive's allowlist already excludes it; `LibraryArchive.includedFolders` gains a comment and a test that `history` is absent). An "Include previous versions" archive option is not built (R177 "not in the archive export by default"; open question 7).
- Entry JSON: `{"schema": 1, "kind", "id", "title", "reason", "byDevice", "at", "fields": [changed field names], "snapshot": {...}}`. `reason` is a closed set: `replacedByRemote`, `lostToRemote` (a local edit lost a clash), `deletedElsewhere`, `broughtBack`, `beforeRestore`, `beforeJoinMerge`, `beforeLookAlikeMerge`.
- **When written:** before every sync step that changes or removes local content (every remote overwrite, not only clashes, so Previous Versions can always undo a sync), before a restore, and before the join and look-alike merges. Local edits by the user on this Mac are not versioned here (Undo covers them).
- **Coalescing:** consecutive `replacedByRemote` entries for one item from one device within 10 minutes keep only the oldest snapshot (a Mac editing a chart with autosave sends many small changes).

### 10.2 Retention (R177)

Per item, an entry is removed only when it is **both** older than 90 days **and** not among the item's 20 newest entries ("whichever keeps more"). Pruning runs at library open and then daily while open, never during a show; removed entries go to the Trash. Table-driven `HistoryRetentionTests` (e.g. 25 entries all 100 days old keeps the 20 newest; 30 entries all 10 days old keeps 30; 5 entries 200 days old keeps 5).

### 10.3 Previous Versions UI

- **Entry points:** File > Previous Versions... (enabled when a song, setlist or smart filter is selected, or a show in the Gig Log); the song card's "..." menu; the setlist builder's menu. A **Recently Deleted** list sits in the same window (all `deletedElsewhere` entries, newest first). Available whether sync is on or off.
- **Window:** a list of versions (date, "from MacBook Neo", the reason in words: "Replaced by a change from MacBook Neo", "Your edit here lost to a newer one from Desktop", "Deleted on Desktop") beside a preview: a song renders as its chart (the existing page renderer) with the changed fields named; a setlist shows its rows; a filter its conditions; settings their values.
- **Restore** writes the snapshot's fields as a local change with fresh stamps (one undo step "Restore Version"), syncs to the other Mac, and first records the current state as `beforeRestore`. For a deleted item it re-creates the files with the same ULID (next free slug if taken). **Restore as Copy** (songs and setlists) creates a new item with a new ULID.
- Design: S4 starts with 2-3 directions for this window, the Settings > Sync pane, the footer indicator and the join review (R39).

## 11. Live pause and Rehearsal

### 11.1 `ShowGate`

- **Release:** at the top of `AppModel.startShow(_:kind: .gig)`, before `flushEditor()` and `refresh()` (`AppModel+Shows.swift:91-100`), and when a pending gig resume is offered at launch (sync does not start until it is answered). The gate closes synchronously on the coordinator: new fetched records go to the inbox only, no apply starts. Then `port.stop()` runs in a detached task: `cancelOperations()` and the engine released. The show path waits for the gate close (an actor hop) for at most 500 ms, never for `stop()`; an apply already writing finishes within that window or is a normal file change the stage does not re-read.
- **During the show:** no CloudKit object exists, so no network. Local edits (the show record, a gig details change, a quick chart fix from the stage) are captured into `pending` as usual. The footer reads "Paused for the show" (not visible on stage anyway).
- **Resume:** after `finishRun` completes (`AppModel+Shows.swift:389-420`), after a cancelled checklist, after a declined resume, and after a crash-resumed show ends: a new engine from the saved state, a rescan (9.2), fetch, the inbox drains, pending sends. The finished show record is sent in that batch.
- **Never** does any step of the show path `await` the network or the port; `ShowGateTests` assert this with a port fake whose `stop()` and `fetchNow()` never return.

### 11.2 Rehearsal and single-song sessions

Rehearsal runs (`kind: .rehearsal`) and single-song sessions keep syncing. The applier holds a **busy set**: the song currently on the stage in Rehearsal or a single-song session, and every song open in an editor (unsaved or not). An inbox record for a busy song is not applied; it is applied as soon as the song leaves the set (the stage moves on, the session ends, the editor closes after its final autosave), and its merge then sees the local edit with its true stamp. Setlists and filters apply at once and their views reload as they do after a local change; a setlist open in the builder mid-drag defers until the drag ends.

### 11.3 Spike 2 (S1) proves the full pause

On the Personal build with a real iCloud account and a `spike-<ulid>` zone: start a Live show, keep it 10 minutes while the other Mac edits songs; `nettop -p <pid>` (and `log stream --predicate 'subsystem == "com.apple.cloudkit"'`) show no CloudKit traffic from Segue and no `cloudd` activity on its behalf beyond what macOS does on its own; local edits queue; at End Show the remote edits apply and local ones send within a minute. Also: `cancelOperations()` returns promptly offline, and a push arriving while released does not wake the engine (no engine exists). Failure of any of these returns to the owner (R177).

## 12. First join, merge by ULID, look-alikes and seeds

### 12.1 Turning sync on (Settings > Sync > Turn On...)

1. Account check (`accountStatus`): no account, restricted or temporarily unavailable each get a plain message and nothing else happens.
2. Fetch the database's zones and their `Library` records.
3. **No library zone in the account:** "Upload this library to iCloud" (shows song, setlist and show counts). Creates `library-<id>` with this folder's library ID and uploads everything (batches of 250).
4. **One or more library zones exist:** a sheet lists them (name, songs, last change, from which Mac) with **Join "<name>"** and **Start a new iCloud library from this one**. Joining a zone whose ID differs from this folder's: this folder **adopts the zone's library ID** (writes `library.json`, renames the state directory). If the local library is empty (only the Welcome seeds or nothing), it downloads; otherwise it merges (12.2).
5. The settings zone joins too (section 14).

### 12.2 Merge by ULID

- Before the merge, a full snapshot of every local item goes to history as `beforeJoinMerge` (one entry per item), so the join can be undone item by item.
- Same ULID on both sides: field merge (8.3) with local stamps from file modification dates (8.2). Remote only: created locally. Local only: uploaded. Different ULIDs are never merged automatically.
- Then the Welcome seed de-duplication (12.4) and the look-alike review (12.3).

### 12.3 Look-alike review

`NearDuplicateIndex.match` over local-only songs against remote songs with different IDs (the R158 score over title, artists and content). Pairs above the existing "possible duplicate" threshold are listed in a review sheet, each with both charts side by side and **Keep Both** (default) or **Merge** with a choice of which to keep. Merge: the other song's setlist slots are re-pointed to the kept song's ID (`SetlistStore.replaceEntries`), its tags are added to the kept song's (open question 8), the other song is deleted with a `beforeLookAlikeMerge` history entry, and both changes sync. Shows are never re-pointed (they are history). The review can be closed and reopened from Settings > Sync until it is empty.

### 12.4 Welcome seeds

A local song carrying the seed manifest's `tag` whose content hash (`NearDuplicateIndex.contentHash`) equals a remote seed song's (same tag, same title) is a duplicate: the local one is deleted (history `beforeJoinMerge`), its setlist slots re-point to the remote ID. The seed setlist ("Welcome Set") is de-duplicated the same way when its entries are only seed songs and its fields equal the remote one's. A seed song that was edited on either Mac (hash differs) is a look-alike for review instead.

## 13. Account events, turning off, deletion, version skew

### 13.1 Sign-out and account switch

- `.signOut`: stop the engine, keep every local file, clear the ledger's server state (`engine`, `items.systemFields`), keep `fields` stamps and `pending`. Status "Signed out of iCloud. Your library is still on this Mac." Signing back in to the same account (same fingerprint) offers **Resume Sync**, which rejoins by ULID (idempotent).
- `.switched` (a different fingerprint): the same stop, and status "Signed in to a different Apple Account. Turn on sync to use it." No automatic join.

### 13.2 Turn Off

Stops the engine, marks the zone `enabled = false`, deletes the engine state and server state; local files and the cloud copy stay. Turning on again is a join (12.1) that finds this library's zone and merges by ULID.

### 13.3 Delete iCloud Data

Settings > Sync > **Delete iCloud Data...**, a confirmation naming what goes: "Delete this library from iCloud? Songs, setlists, smart filters and the Gig Log stay on this Mac. Other Macs stop syncing this library and keep their copies." Options: this library's zone only (default), or also the settings zone. Runs `deleteZone`, then Turn Off. Available while signed in, also when sync is already off.

### 13.4 A zone deleted elsewhere or purged

`.zoneDeleted(.deleted)` (the other Mac deleted it): stop for that library, keep local files, status "This library's iCloud copy was deleted on another Mac. Your files here are kept." with **Upload Again**. `.purged` (the user deleted Segue's data in System Settings > iCloud): the same with "deleted from iCloud". `.encryptedDataReset` (the user reset Advanced Data Protection keys): re-upload everything automatically, since the local copy is complete.

### 13.5 Version skew: an older Mac stops syncing (R177)

- This build supports sync `protocol` P and knows each kind's file schema S. On fetch, if the zone's `Library.minProtocol > P`, or any record has `protocol > P` or `schema` newer than this build reads, the coordinator **stops**: the batch's records stay in the inbox (so nothing is lost and the engine state may advance), no apply runs, no send runs, the engine is released. Status and a one-time alert: "A newer Segue on MacBook Neo changed this library. Update Segue on this Mac to keep syncing. Your edits here are kept and will sync after the update."
- Local edits keep being captured into `pending`. After the update the inbox drains first, then pending sends, merging per field as usual.
- The newer Mac writes records at its own schema. A record from an older Mac (lower schema) is migrated forward on decode like a file; fields it does not have are untouched (8.3 rule 1).
- `protocol` bumps only when the payload format or merge rules change; `minProtocol` is raised only when an older reader would corrupt data. `VersionSkewTests` cover both directions.

### 13.6 Quota and other failures

- `quotaExceeded`: status "iCloud is full. This Mac keeps working, and changes will sync when there is space." Local saves never fail because of sync. Retries follow the engine.
- Rejections the engine does not retry (a malformed record, a permission error) park the item in `pending` with a reason shown in Settings > Sync > Details and a `syncProblem` event; they never block other items.

## 14. Settings records

### 14.1 What syncs, by group (`settings` zone)

| Record | Fields | Source |
| --- | --- | --- |
| `settings-instrument` | each `InstrumentProfile` property | `InstrumentProfileStore` |
| `settings-live` | each `LiveSettings` property, plus `rehearsalShortcuts` and `metronome` | `LiveSettingsStore` |
| `settings-audio` | `chordSound`, `chordStyle`, `bassSound`, `volume`, play-along and tap fields | `AudioSettingsStore` (minus output) |
| `settings-appearance` | `mode` | `AppearanceStore` |
| `settings-setlists` | `defaultChangeoverSeconds` | `ChangeoverSetting` |
| `settings-fillEditor` | each `fill.editor` property | `FillEditorSettings` |
| `settings-shapes` | `shapes` (the whole user shape library) | `shape-library.json` |
| `settings-bindings` | `keyBindings` (every `InputBinding` whose trigger is `.key`) | `bindings.json` |

### 14.2 Per Mac (never synced)

Audio output device (`outputUID`, `outputName`); MIDI bindings (any non-`.key` trigger, when phase 6 adds them: the bridge writes back only `.key` bindings and keeps the rest of the file); privacy and analytics consent and IDs; AI toggle and downloaded models; the library bookmark; onboarding, Welcome, What's New, review prompt, tips, the selected Settings pane; `services.environment`; sync's own state. `SettingsAllowlistTests` assert the exact synced key set so a new setting is a deliberate choice.

### 14.3 The bridge

`SettingsSyncBridge` (SegueUI `Sync/`) is the settings zone's "store": it reads the groups from the stores, receives each store's change callback as a local change, and applies remote fields through each store's normal update (with a `remote` flag that suppresses the callback). Stamps live in the ledger like any item. A Live show releases it like everything else.

## 15. Status UI

### 15.1 Library footer indicator

A quiet line in the library list's bottom inset beside `loadIssuesFooter` (`LibraryViews.swift:146`), secondary colour, small symbol plus at most five words; click opens Settings > Sync. Shown only while sync is on.

| State | Text |
| --- | --- |
| up to date | "Synced" (symbol only after 10 s) |
| sending or fetching | "Syncing..." |
| released for a Live show | "Paused for the show" |
| offline with pending | "Offline, 3 changes waiting" |
| iCloud full | "iCloud is full" |
| older version | "Update Segue to sync" |
| signed out / switched | "iCloud sync is off" |
| other problem | "Sync problem" |

Accessibility: one element, label = the text, hint "Opens Sync settings".

### 15.2 Settings > Sync (new pane, after Data)

Turn On / Turn Off; the account and this library's iCloud name; last sync time; pending count; other Macs seen (name, Segue version, last seen); the look-alike review while non-empty; problems with their reason; **Sync Now** (fetch and send); **Previous Versions...**; **Delete iCloud Data...**; a link "How sync works" (guide `sync`). The pane also explains in one line what stays per Mac.

### 15.3 The 24-hour notification

- When the oldest `pending` entry is older than 24 hours (checked at activation and hourly), one local notification: "Segue hasn't synced for a day. 5 changes on this Mac are waiting." Clicking opens Settings > Sync. Never while a show runs (deferred to its end), at most one per 24 hours, cleared when pending reaches zero.
- `UserNotifications` is new to the app: permission is requested when the user turns sync on, with a one-line reason; declined means the footer and pane carry the status alone. R179.

### 15.4 Menus

File > Previous Versions...; Library > Sync Now (disabled when sync is off or released). No keyboard shortcut for either (P9-5's menu audit may add one).

## 16. Entitlements, flavours and the spikes

### 16.1 Entitlements

All three entitlements files gain:

```xml
<key>com.apple.developer.icloud-services</key>
<array><string>CloudKit</string></array>
<key>com.apple.developer.icloud-container-identifiers</key>
<array><string>iCloud.dev.ryandsilva.segue</string></array>
<key>com.apple.developer.aps-environment</key>
<string>production</string>              <!-- development in Segue-Debug.entitlements -->
<key>com.apple.developer.icloud-container-environment</key>
<string>Production</string>              <!-- Personal and Debug only; see 16.2 -->
```

- `scripts/lib/verify-common.sh` `app_entitlements` gains the first three keys (with `aps-environment: production`), in the same commit as the entitlements files (repo rule). `verify-appstore.sh`'s local-build comparison also ignores `aps-environment` (local development signing makes it `development`) alongside `get-task-allow`. Check 4 is re-read against a real signed archive in S3 (spike output), and the expected set is whatever that archive proves the distribution profile signs, recorded with the archive's `codesign -d --entitlements` output in the commit message.
- The Quick Look extension gets no iCloud entitlement (check 4's appex branch is unchanged).
- `Project.swift`: `appTarget` links `.external(name: "CloudSync")` in both flavours; no setting changes beyond that (the entitlements files carry the capability).

### 16.2 Both flavours, one container, Production (R177)

- Both App IDs (`dev.ryandsilva.segue`, `dev.ryandsilva.segue.personal`) carry iCloud with CloudKit and the container `iCloud.dev.ryandsilva.segue`, and Push Notifications (section 21 B).
- The App Store build can reach only Production (research 3). The Personal build is development-signed, which defaults to the Development environment; `com.apple.developer.icloud-container-environment = Production` points it at Production so both builds see one library. Whether a development-signed macOS build honours it is unverified (research 3 "U on the exact macOS behaviour"): spike 1.
- The `cloud-test` host (17.3) is the only build on Development.
- The engine state and ledger are shared by both flavours on one Mac (one device); spike 1 also proves that a `CKSyncEngine.State` written by one flavour resumes in the other.

### 16.3 Signing

App Store: manual, profile "Segue Mac App Store" regenerated after the capability change (section 21 C), name unchanged so `Config/ExportOptions-AppStore.plist` is untouched. Personal: automatic with `-allowProvisioningUpdates`; the MacBook Neo must be a registered device for a development profile with iCloud (Xcode registers it on the first build there).

### 16.4 The two R177 spikes (first thing in S1, before any production code)

| Spike | Steps | Pass |
| --- | --- | --- |
| 1. The Personal build shares data | A throwaway target in `research/icloud-spike/` (gitignored build output) signed as each flavour, same container, Personal with the Production environment key. The App Store-signed spike runs from a TestFlight-free local distribution-signed build if Xcode allows, otherwise an Ad Hoc-style development build with Production. Each writes a record to `spike-<ulid>`; each reads the other's; then `CKSyncEngine.State` serialized by one flavour is loaded by the other and fetches without a full refetch. | both flavours read and write the same Production zone; the state resumes across flavours; the signed entitlements of each are recorded |
| 2. The full Live pause | Section 11.3. | no CloudKit traffic while released; queued edits send at the end; prompt `cancelOperations()` offline |

If either fails, S1 stops, writes the evidence to `docs/research/phase9-icloud-sync-spikes.md`, and returns to the owner with options (for spike 1: separate containers per flavour with one flavour syncing; for spike 2: polling with `automaticallySync = false` while performing). The spike zones are deleted afterwards.

## 17. Testing

### 17.1 Deterministic sync simulation (the default gate for sync)

The owner's DST preference: time, randomness and IO are injected, so a whole two-Mac history replays bit for bit from a seed.

- **Harness** `SyncSimulation` (SegueCore tests): one `FakeCloudSync` server; two devices, each with its own temp library folder, real `LibraryStore` / `SetlistStore` / `ShowStore` / `SmartFilterStore` on `LiveFileSystem`, its own ledger and state directory, its own `ManualClock` (with a configurable skew, up to minutes) and `ULIDGenerator(seed:)`, and a `SyncCoordinator` on the fake port. A seeded `SimulationRandom` (SplitMix64) drives a `SyncScheduler`.
- **Operations** the scheduler picks: edit a field (each kind, each field), create, delete, restore from history, go offline / online, deliver a push, deliver late / out of order / twice, drop a send (retried), start and end a Live show, start a Rehearsal on a song and leave it, open and close an editor, crash (drop all in-memory state and relaunch from disk), delete the ledger, sign out and back in, an older-protocol device, quota full then free, advance a clock.
- **Invariants** after the scheduler drains (everything online, no show): (1) convergence: both libraries' synced content is byte-equal per item (files compared after canonical decode; slugs may differ); (2) no loss: every value ever overwritten or deleted on a device is present in that device's history or is the converged value; (3) no CloudKit call while a device is released (the fake counts calls per state); (4) idempotency: replaying the whole inbox again changes nothing; (5) never a write into `<root>/.segue/` except `library.json` / `upgrades.json`; (6) ledger loss followed by rebuild converges to the same state.
- **Budget:** `SyncSimulationTests` runs 64 pinned seeds x 300 steps in the normal package tests (target under 10 s); a failure prints the seed and the operation trace and a `SYNC_SEED=<n>` environment variable replays one. `make sync-soak` (opt-in, never in `quick` or `gate`) runs 5,000 random seeds and saves any failing seed into the pinned list.
- **Pure units:** `HLCTests`, `FieldMergerTests` (section 8.5's table and its mirror, every pair of orders), `RecordCodecTests` (7.5), `HistoryRetentionTests` (10.2), `VersionSkewTests` (13.5), `ShowGateTests` (11.1), `SettingsAllowlistTests` (14.2).

### 17.2 Conformance suite

`SyncPortConformance` (a shared test body parameterised by an adapter factory): zone create / delete, save and fetch round trip, `serverRecordChanged` carries the server record, tombstone round trip, a batch over `maxBatch` splits, `stop()` leaves no operation, state resume after `stop()`, account events. It runs on every `swift test` against `FakeCloudSync`, and against `CloudKitSync` only under `make cloud-test`. The CloudKit adapter's capability flags may only be declared where a conformance case covers them.

### 17.3 Real CloudKit (`make cloud-test`, opt-in)

- A signed test host `SegueCloudTestHost` (a minimal app target in `Project.swift`, Debug only, Personal-team signed, entitlements `App/SegueCloudTest.entitlements` with the container on **Development**) runs XCTest cases that build two `CKSyncEngine` instances with `automaticallySync = false`, as WWDC23 10188 recommends, against zones `test-<ulid>`. Requires a Mac signed in to iCloud; deletes every `test-` zone before and after (clean baseline).
- Cases: the conformance suite; a two-engine concurrent edit of one field and of two fields; offline then online; a tombstone vs an edit; an asset-sized payload; a quota error is not reproducible and stays covered by the fake.
- Real pushes, the Production environment and two physical Macs are covered by the S4 checklist (17.5), not by automation.

### 17.4 E2E (`SegueSyncE2ETests`, one class)

Personal Debug build with `-SegueSyncBackend fake -SegueSyncFakeServer /private/tmp/segue-e2e/sync-server.json -SegueStatePath /private/tmp/segue-e2e/state`, the server file and library reset before each test. A helper in the UI test bundle writes a "remote device" change into the server file. Tests: turn on and upload (footer "Synced"); a remote edit appears in the library; a remote delete then Restore from Recently Deleted; a Live show shows "Paused for the show" in the footer after the stage closes and the remote edit made during it applies after End Show; Turn Off keeps the library.

### 17.5 The two-Mac checklist (S4, Ryan's desktop and MacBook Neo, real iCloud)

Before it: delete the library's zone (Delete iCloud Data) and reset both Macs to copies of a known baseline library (never the real one until the last step). Then: first enable on the desktop; join on the Neo with an existing library (look-alikes, seeds); concurrent edit of one field and of different fields; offline edits on both; an edit during a Live show on the Neo then catch-up; delete and restore; sign out and back in; Turn Off and on; version skew (an older build on one Mac); quota (skipped unless reproducible); the 24-hour notification with a shifted clock on a test account. **Neo budget:** with a 500-song library, first upload and a full fetch keep Segue under 400 MB resident (R168 style) and finish within 5 minutes on Wi-Fi; Activity Monitor CPU returns to idle within 30 s after sync. Then Ryan's real library is joined on both Macs.

## 18. Privacy label, privacy policy and App Review

- **Privacy label: no change.** CloudKit private-database data is not accessible to the developer, and Apple's definition excludes data collected by Apple through its frameworks (research 5). Recorded in `docs/release/app-store-connect.md` section 5 beside R129's note.
- **Privacy policy** (`website/privacy.html`): a new short section "iCloud sync (optional)": sync is off until you turn it on; it stores your library and musical settings in your own iCloud account's private CloudKit database, end-to-end encrypted where your account uses Advanced Data Protection; the developer cannot read it; per-Mac settings and consent never leave the Mac; turning sync off keeps the iCloud copy until you choose Delete iCloud Data, or delete it in System Settings > [your name] > iCloud.
- **App Review notes** (`docs/release/app-store-connect.md` review notes): add "ICLOUD SYNC (optional): Settings > Sync can keep a library in step between the user's own Macs through CloudKit's private database. Off by default; the app works fully without an Apple Account or iCloud. Nothing is sent to the developer." and add "(e) iCloud sync through Apple's CloudKit, only after the user turns it on" to NETWORK USE.
- The schema is deployed to Production before the build is submitted (section 21 D).

## 19. Analytics (closed vocabulary, non-PII)

New rows in `docs/release/specs/WS3-services.md` after the last row present when S4 starts (31+ at writing; siblings may take numbers first), with `AnalyticsEvent` cases in `Services/AnalyticsEvent+Sync.swift`:

| Signal | Parameters | When | Throttle | Question it answers |
| --- | --- | --- | --- | --- |
| `Segue.Sync.enabled` | `segue.join` (`uploaded`, `downloaded`, `merged`), `segue.songs` (SongBucket), `segue.lookAlikes` (SmallBucket), `segue.seedsMerged` (Bool) | sync turned on and the first merge finished | per occurrence | how people join, how messy first merges are |
| `Segue.Sync.disabled` | `segue.reason` (`turnOff`, `signOut`, `accountSwitch`, `deletedHere`, `deletedElsewhere`, `updateRequired`) | sync stops | per occurrence | why sync stops |
| `Segue.Sync.daily` | `segue.sent`, `segue.received`, `segue.clashes` (fields that lost), `segue.history` (entries written) (SmallBucket each), `segue.devices` (SmallBucket) | once per day with sync on | daily | volume and clash rate |
| `Segue.Sync.catchUp` | `segue.pending` (SmallBucket), `segue.seconds` (DurationBucket), `segue.outcome` (`done`, `offline`, `failed`) | after a Live show's resume | per show | does the post-show catch-up work and how long |
| `Segue.Sync.restored` | `segue.kind` (`song`, `setlist`, `filter`, `show`, `settings`), `segue.reason` (history reason), `segue.copy` (Bool) | Restore in Previous Versions | daily per (kind, reason) | is history used, for what |
| `Segue.Sync.problem` | `segue.code` (`quota`, `unsynced24h`, `rejected`, `clockAhead`, `updateRequired`, `invariant`) | first occurrence per day | daily per code | where sync hurts |

No titles, IDs, device names, zone names or counts finer than the buckets. `ErrorCode` gains `syncApplyFailed` and `syncEngineFailed` for crash breadcrumbs.

## 20. Guide pages and site

- New `guide/src/content/docs/sync.mdx` "Sync between Macs" in the "Settings and data" group (`guide/astro.config.mjs:55`): turning it on and joining, what syncs and what stays per Mac, what happens during a show and a rehearsal, clashes and Previous Versions (with Recently Deleted), turning off and Delete iCloud Data, updating both Macs, the statuses (the footer table), with real screenshots (`make docs-shots ONLY=settings-sync,previous-versions`).
- `library-folder.mdx`: a `#file-sync` section (S0's warning, why iCloud Drive or Dropbox is a bad home for a library, and the sync alternative).
- `back-up.mdx`: sync is not a backup; history is not in the archive; the archive is still the way to keep a copy.
- `troubleshooting.mdx`: "Sync says Update Segue", "iCloud is full", "Syncing in the other copy of Segue", "This library's iCloud copy was deleted".
- `SegueLinks` gains `sync`, `syncPreviousVersions`, `libraryFolderFileSync`; every in-app link is verified against the live deployment once it is up.

## 21. Owner's manual steps (copied from research section 9)

Account Holder or Admin role (you are both). **Steps A-C before session S1** (the spikes need them); step D before release.

**A. Create the iCloud container** (help/account/identifiers/create-an-icloud-container):
1. In Certificates, Identifiers & Profiles (developer.apple.com/account/resources), click **Identifiers** in the sidebar, then click **+** at the top left.
2. Select **iCloud Containers**, click **Continue**.
3. Description `Segue`, identifier `iCloud.dev.ryandsilva.segue` (must begin with `iCloud.`, per "Configuring iCloud services"). Click **Continue**, then **Register**.

**B. Enable iCloud + CloudKit on each App ID** (help/account/identifiers/enable-app-capabilities). Repeat for `dev.ryandsilva.segue` and `dev.ryandsilva.segue.personal` (not the `.quicklook` extensions):
1. **Identifiers** in the sidebar, select the App ID.
2. Under Capabilities, tick **iCloud**; under Compatibility choose **Include CloudKit support**.
3. Click **Edit** next to iCloud, select `iCloud.dev.ryandsilva.segue` in the table, click **Continue**.
4. Tick **Push Notifications** on the same App ID (no APNs certificate is needed: CloudKit sends its own pushes; U, see research section 3).
5. Click **Save**; if a warning dialog appears, click **Confirm**. Apple: "Provisioning profiles that contain a modified App ID become invalid."

**C. Regenerate the Mac App Store profile** (help/account/provisioning-profiles/edit-download-or-delete-profiles):
1. **Profiles** in the sidebar, select **Segue Mac App Store** (now invalid), click **Edit**.
2. Click **Generate** (keep the name, so `Config/ExportOptions-AppStore.plist` needs no change), then **Download** and double-click the `.provisionprofile` to install it.
3. Personal is automatic signing: the next `make` build with `-allowProvisioningUpdates` regenerates its development profile. On the MacBook Neo, sign in to Xcode with the same team once so it can run the Personal build.

**D. Before release, deploy the schema** (cloudkit/deploying-an-icloud-container-s-schema):
1. Sign in to CloudKit Console at icloud.developer.apple.com.
2. Select the **CloudKit Database** app.
3. In the top section, choose `iCloud.dev.ryandsilva.segue`.
4. On the left, select **Deploy Schema Changes**.
5. Review the pending changes and click **Deploy**. Fields cannot be deleted from production afterwards, so S3 should settle the record schema first. (This spec's schema is two record types with a handful of fields, section 7.1, so the deploy is expected to happen once.)

**E. Both Macs:** System Settings > [your name] > iCloud: signed in to the same account, iCloud Drive not required. During S4, check that Segue appears under the apps using iCloud.

The sessions tell Ryan before each of these is needed, with the values above, and wait.

## 22. Build sessions

Each session ends with its section of done criteria (23) and its test budget (session rules).

### S0 - Library state out of the folder (independent)

1. `LibraryIdentity` and `.segue/library.json`; `LibraryStateLocation` / `LibraryStateDirectory` in the app group with the fallback; copy-vs-move detection; the TTL backstop (5.1, 5.2).
2. `LibraryLock(state:)`, `ShowClaim` paths, `LibraryStore.open(root:state:)`, `LibrarySession.open` and `AppModel.open` wiring, `-SegueStatePath`; the upgrade (5.3).
3. `LibraryFolderKind` and the banner, Settings > Data line, `LibraryLocation.fileSyncFolder` (5.4).
4. Tests (5.5); the `library-folder.mdx` `#file-sync` section and the `LibraryLock` / `LibraryRoot` doc comments; `make quick`, one `make e2e-one` for the library class.

### S1 - Spikes, entitlements, the port and the fake

Prerequisite: Ryan has done section 21 A-C (ask and wait).
1. Spike 1 and spike 2 (16.4). **On failure, stop and return to the owner.** Record results in `docs/research/phase9-icloud-sync-spikes.md`.
2. Entitlements in the three files, `verify-common.sh`, `verify-appstore.sh`, check 4 comment; `Packages/SegueCloud` skeleton linked by both app targets; the `cloudkit_import` and `sync_no_ambient_time` lint rules (16.1, 6.1).
3. SegueCore `Sync/` target: `SyncPort` and value types (6.2), `FakeCloudSync` with the seeded scheduler (6.3), the conformance suite against the fake (17.2).

### S2 - Core sync on the fake

1. `HLC`, `HLCStamp`, `RecordCodec` for all kinds with the field tables and the field-list test (7, 8.1, 7.5).
2. `SyncLedger` (9.1), device ID; `ItemChangeObserver` hooks in the four stores and the rescan (9.2).
3. `FieldMerger`, tombstones (8.3, 8.4); `RemoteApplier` with the stores' remote-apply methods, echo suppression, the busy set (9.4, 11.2); remote deletes (9.5).
4. `HistoryStore`, coalescing, retention (10.1, 10.2).
5. `ShowGate` and the `AppModel` show hooks (11.1); version skew (13.5); account / zone events in core (13.1-13.4).
6. `SyncSimulation` with the pinned seeds and `make sync-soak` (17.1).

### S3 - CloudKit adapter

1. `CloudKitSync`: engine creation from state, delegate events, the `Item` / `Library` / `Device` mapping with `encryptedValues` and the asset fallback, error mapping, `serverRecordChanged`, zone create / delete, account changes, quota (6.3, 7.1, 13).
2. `SegueCloudTestHost`, `make cloud-test`, the conformance suite on CloudKit Development (17.3).
3. Re-read check 4 against a real signed archive and fix the expected set (16.1).

### S4 - UI, settings, release

1. Design directions (R39): 2-3 each for Settings > Sync, the footer indicator, Previous Versions and the join / look-alike sheets; Ryan picks.
2. `SettingsSyncBridge` and the allowlist (14).
3. Settings > Sync, the footer, the join flow with the look-alike review and seed de-duplication, Previous Versions with Recently Deleted, File and Library menu items, the 24-hour notification (12, 10.3, 15).
4. Analytics rows and cases (19); guide pages and links (20); privacy policy and review notes (18).
5. `SegueSyncE2ETests` (17.4); `make quick`; `make e2e-one TEST=SegueSyncE2ETests`.
6. The two-Mac checklist and the Neo budget with Ryan (17.5); then Ryan deploys the schema (21 D) and checks 21 E.

## 23. Done criteria

- **S0:** no new file is created inside a library folder except `.segue/library.json` (and the existing `upgrades.json`); the index and every lock live under `<group>/.../Libraries/<id>/`; the two flavours still cannot open one library together (tested with two `LibraryLock(state:)`); old in-folder index files are gone after the first open; a library in iCloud Drive or a CloudStorage folder shows the banner once per library until dismissed; the guide section is live.
- **S1:** both spikes passed and recorded (or the owner has been asked); all three entitlements files, `app_entitlements` and the checks agree; CloudKit is imported only in `Packages/SegueCloud`; the conformance suite passes on the fake.
- **S2:** the simulation's 64 pinned seeds pass with all six invariants; section 8.5's table holds in both delivery orders; no sync stamp appears in any library file; the show path never awaits the port; an older-protocol record stops sync and loses nothing.
- **S3:** the conformance suite and the two-engine cases pass on CloudKit Development; the adapter maps every `CKError` the engine surfaces to a named failure or problem; check 4 matches a real archive.
- **S4:** every R177 behaviour is reachable from the UI (no CLI-only control); the footer and pane never claim "Synced" with pending changes or while released; Previous Versions restores songs, setlists, filters, shows and settings, including deleted items; the E2E class passes; the two-Mac checklist passes on Ryan's Macs within the Neo budget; analytics rows, guide pages, privacy policy and review notes are in; the Production schema is deployed.

## 24. Closed questions (R179, 2026-11-01)

All closed as the spec recommended.

1. **Remote delete and the Finder Trash:** remote deletes also keep a Finder Trash copy; the UI points at Recently Deleted (R179; 9.5).
2. **Older builds and the moved lock:** accepted; pre-S0 builds are not covered by the moved lock (R179; 5.3).
3. **Settings zone:** settings sync in their own `settings` zone (R179; 7.1, 14.1).
4. **`entries` merges whole:** setlist entries merge as one field; `segue.clashes` is measured (R179; 7.3).
5. **Finished rehearsal records:** do not sync (R179; 7.4).
6. **Tombstone lifetime:** tombstones keep their fields 180 days, then key and stamp only (R179; 8.4).
7. **History in the archive:** no history option in the archive export (R179; 10.1).
8. **Look-alike Merge and tags:** a look-alike merge carries the removed song's tags to the kept one, nothing else (R179; 12.3).
9. **Notification permission:** asked when sync is turned on (R179; 15.3).
10. **Live settings Shortcut names:** sync as part of `settings-live` (R179; 14.1).
11. **Library ID file location:** `.segue/library.json` (R179; 5.1).
