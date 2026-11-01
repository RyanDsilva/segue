# Phase 9 research - optional iCloud sync between two Macs (2026-10-31)

Feasibility pass for **opt-in** sync of one Segue library between two Macs on the same Apple Account (a desktop Mac and a MacBook Neo, 8 GB). No iOS. Primary sources where possible. **V** = VERIFIED (source given), **U** = UNVERIFIED (needs a spike or a doc that was not found). Local SDK: Xcode 27.1 (27A9275), `MacOSX.sdk`.

Product rules from the brief: songs (`.cho` + `songs/<slug>.segue.json`), setlists with arrangements, smart filters, the Gig Log (`shows/`) and app settings sync. Conflicts are resolved automatically, newest edit wins, the other version goes to a recoverable history. Gig safety is a hard rule: every synced item is always fully local, sync pauses during a Live show and catches up after, and a show never depends on the network.

**Recommendation in one line:** option **B**, CKSyncEngine over the CloudKit private database, with the local library folder staying canonical, behind a `SyncPort` with an in-memory fake. Details in section 6.

---

## 1. What the app has today (code facts)

| Fact | Where | Sync consequence |
|---|---|---|
| Library is a **user-picked folder** (default `~/Music/Segue`) held by a security-scoped bookmark in UserDefaults key `libraryFolderBookmark`. | `Packages/SegueUI/Sources/SegueUI/App/LibraryLocation.swift` | A user can already pick a folder inside iCloud Drive today, with no entitlement (user-selected read-write). See finding 1.1. |
| Layout: `songs/<slug>.cho`, `songs/<slug>.segue.json`, `setlists/<slug>.setlist.json`, `shows/<ulid>.show.json`, `filters/<slug>.filter.json`, `.segue/index.sqlite`, `.segue/library.lock`. | `Packages/SegueCore/Sources/Support/LibraryRoot.swift` | The **GRDB index and the `flock` lock live inside the library folder.** |
| `SongIndex` (GRDB/SQLite) at `<root>/.segue/index.sqlite`, "a projection; only this store writes to it", rebuildable, "Safe to delete". | `LibraryStore.swift` doc comment, `LibraryRoot.indexDatabase` | Must never be file-synced. |
| `LibraryLock` uses `flock` on `<root>/.segue/library.lock`; its own comment says "network or synced folders that do not honour `flock` are not protected". `ShowClaim` uses `flock` on `shows/<ulid>.show.lock`. | `Support/LibraryLock.swift`, `Shows/ShowClaim.swift` | `flock` is per kernel: it never excludes the other Mac. Lock files must not sync. |
| All file IO goes through the `FileSystem` port; `LiveFileSystem` writes atomically through `NSFileCoordinator` (`.forReplacing`), deletes go to the Trash, never `removeItem` for user data. | `Support/FileSystem.swift` | Good base for both options; deletions are already recoverable. |
| Edits are optimistic: `updateSong(id:source:basedOn:)` checks the on-disk content hash and throws `LibraryError.conflict(.sourceChanged / .deleted / .metadataChanged)`. | `LibraryStore.swift` | A remote apply that races a local editor session is already detected. |
| No live file watching: no `NSFilePresenter`, FSEvents or dispatch sources. The library refreshes on `NSApplication.didBecomeActiveNotification` and after sessions. | grep over `Packages/*/Sources`, `AppModel.swift:234` | Option A would need a presenter; option B applies changes through the stores. |
| **Identity is ULID everywhere:** `SongID` (in the sidecar), `SetlistID`, `SetlistItemID`, `ShowID` (also the show file name), `SmartFilterID`, `CueID`. File names are slugs (except shows). | `Support/ULID.swift`, `Sidecar.swift`, `Setlist.swift`, `ShowRecord.swift`, `SmartFilter.swift` | Record names can be the ULIDs, so identity never depends on a file name. Two Macs can mint IDs with no allocator. |
| Timestamps: `Sidecar.createdAt/updatedAt`, `Setlist.createdAt?/updatedAt?` (nil before phase 2), `SmartFilter.updatedAt`. `.cho` has only mtime. Clock and IDs are injected (`Clock`, `IDGenerator`, `ManualClock`). | same | Usable for newest-wins, but not per field, and `.cho` needs its own stamp. Injected clock/IDs make deterministic sync tests easy. |
| Schemas are versioned (`Sidecar.currentSchemaVersion = 6`, `Setlist.currentSchemaVersion = 6`); a newer schema opens **read-only**. | `Sidecar.swift`, `Setlist.swift` | Protects an older app version on one Mac from overwriting newer data, if sync honours it too. |
| Welcome seed songs are created with fresh ULIDs per library and a seed tag. | `LibraryStore+Welcome.swift`, `WelcomeSeed.swift` | Two Macs that were both seeded hold the same songs under different IDs (duplicates on first sync). |
| Settings are UserDefaults: `instrument.profile`, `live.settings`, `live.rehearsalShortcuts`, `live.metronome`, `audio.settings` (includes the output device), appearance (`AppearanceStore`), `setlists.defaultChangeoverSeconds`, `fill.editor`, `ai.useAI`, `privacy.consent`, plus per-Mac state (bookmark, onboarding, What's New, review prompt, analytics IDs, `services.environment`). App Support files: `bindings.json` (keys + MIDI), `shape-library.json`. | `Packages/SegueUI/Sources/SegueUI/Settings/*`, `LiveDependencies.swift:44`, `AppModel.swift:127` | Settings need an allowlist: some are per Mac by nature (audio output device, MIDI device bindings, consent). |
| Entitlements (all three files): sandbox, user-selected read-write, app-scope bookmarks, network.client, apple-events to Shortcuts, app group `V6BM673U35.dev.ryandsilva.segue.models`. **No iCloud, CloudKit or push.** The App Store set is "asserted exactly by `scripts/verify-archive.sh` check 4". | `App/Segue.entitlements`, `App/SegueAppStore.entitlements`, `App/Segue-Debug.entitlements` | Any option adds entitlements, and check 4 must change in the same commit. |
| Bundle IDs `dev.ryandsilva.segue` (App Store, manual signing with profile "Segue Mac App Store", R12) and `dev.ryandsilva.segue.personal` (automatic). Team `V6BM673U35` (paid, R1). Deployment target macOS 26.0. | `Project.swift:12,45-48`, `Config/ExportOptions-AppStore.plist` | Both App IDs need the capability if both flavours sync; CKSyncEngine's macOS 14 floor is no constraint. |

### 1.1 Latent issue found along the way
Today a user can pick an iCloud Drive (or Dropbox) folder as the library. Then `.segue/index.sqlite` and `.segue/library.lock` sync between Macs: SQLite files under file sync can be uploaded mid-write and corrupt (U for iCloud specifically; community evidence: Zotero forum, forums.zotero.org/discussion/83344), and the lock protects nothing across Macs. This exists independently of phase 9 and deserves its own small ticket (see open question 16).

### 1.2 History of this question
- R7.2 (2026-10-17, `git show 2840356:docs/research/phase7-sync.md`) recommended a user-picked iCloud Drive folder over CKSyncEngine, because "CKSyncEngine adds a second source of truth and has had two 2026 regressions", and found `NSMetadataQuery` unreliable for picked folders (DTS: "doesn't behave as documented", forums thread 689468), with `NSFilePresenter` + rescan as the working change signal.
- R132 then removed "7.2 iCloud Drive library sync with its conflict UI"; R134 made the (iOS) library a Files-app folder with "no Segue sync engine and no conflict UI". The phase 7 spec and its research were deleted on 2026-10-31 (bd61cfb).
- **What changed since:** that recommendation assumed iOS + a Files-provider-neutral design and accepted provider behaviour as-is. The new brief adds three hard requirements the folder approach cannot meet (always-local, pause during a show, newest-wins with history), and drops iOS. Section 2 shows why those requirements flip the answer. This brief reverses R132 for Mac-to-Mac sync; the owner should record that explicitly (open question 1).

---

## 2. Option A - the library folder in iCloud Drive

Two variants: (A1) the app's ubiquity container (`~/Library/Mobile Documents/iCloud~dev~ryandsilva~segue/`), or (A2) a user-picked folder inside iCloud Drive (works today with no new entitlement).

### Mechanics
- **Coordination:** "In the iCloud environment, every file access in your app, unless it is in the context of the reading or writing methods of UIDocument or NSDocument, should go through NSFileCoordinator" (V, TN2336). Segue already coordinates every read and write.
- **Change discovery:** an `NSFilePresenter` on the root (`presentedSubitemDidChange(at:)`) plus a full rescan on launch and activation (V as developer report, forums thread 689468; carried from R7.2). `NSMetadataQuery` covers only the app's own container scopes (V, `NSMetadata.h`), so A2 cannot use it.
- **Download forcing:** `startDownloadingUbiquitousItem(at:)`: "If a cloud-based file or directory has not been downloaded yet, calling this method starts the download process" (V, Apple doc). It only starts a download; it pins nothing. `evictUbiquitousItem(at:)` is the opposite (V, `NSFileManager.h:808,820`).
- **Eviction prevention: there is no API.** For the Keep Downloaded option, DTS: "The option is designed to be used via user interaction only. There is no API for developers to programmatically set the option." (V, forums thread 756963, June 2024, Ziqiao Chen). Since macOS 14 iCloud Drive runs on FileProvider and "Optimise Mac Storage" evicts files to dataless placeholders; reading one materialises it from iCloud (V as third-party analysis, eclecticlight.co 2023-10-25 and 2024-03-18). Eviction state is per Mac.
- **Keeping the index out:** `.nosync` suffixes are folklore with no Apple documentation found (U). The robust fix is to move `index.sqlite`, `library.lock` and the show locks to the sandbox container's Application Support, keyed by a library ID. That is a code change to `LibraryRoot` either way.
- **Conflicts:** two cases (V, TN2336). In the *document scope* (`Documents/`), a new-file conflict yields a bounced `abc 2.txt`. In the *data scope*, "iCloud Drive won't create bounced files - it instead resolves them automatically by picking up a winning version and keeping the other changes in a losing version", surfaced via `NSFileVersion.unresolvedConflictVersionsOfItem(at:)` and presenter callbacks; un-removed losers "will continue to synchronize to all iCloud peers and consume the user's iCloud quota". The winner is "chosen as the current version" by iCloud (V, `NSFileVersion` doc), **not by newest edit**. DTS-confirmed inconsistency: after a near-simultaneous edit the second device saw its own version as current with no conflict reported, contrary to the documented `presentedItemDidGain` timing (V, forums thread 804253, DTS asked for a Feedback report). A user-picked folder outside a ubiquity container may produce bounced names rather than `NSFileVersion`s (U, R7.2 spike never ran).

### Against the requirements
| Requirement | A1 / A2 |
|---|---|
| Correct under concurrent edits | **Weak.** Each `.cho` and its sidecar are separate files that sync independently, so a Mac can see a new chart with an old sidecar (cue fingerprints, fill anchors) for a while. Conflict detection relies on behaviour DTS has called inconsistent. |
| Newest wins + history | Buildable on top: on each conflict compare versions' `modificationDate`, `replaceItem` the winner, copy losers to history, `removeOtherVersionsOfItem`. But bounced `name 2.cho` duplicates (A2/document scope) need a second path that reconciles by sidecar ID. |
| Always fully local | **Fails.** No API to pin; Optimize Mac Storage can evict any song. A read of a dataless file blocks on a network download, so a show can depend on the network. Only mitigation is a private local mirror, which makes iCloud Drive a non-canonical transport anyway. |
| Pause during a show | **Fails.** `fileproviderd`/`bird` sync the folder whatever the app does; the app can only refuse to re-read, while files still change underneath it. |
| Owner's rules | Violates "never sync an automation-driven folder through file-sync" (autosave writes the library constantly) and "dataless placeholders break things". |
| Entitlements | A2: none new. A1: iCloud Documents (`com.apple.developer.icloud-services` = CloudDocuments, `com.apple.developer.icloud-container-identifiers`, `com.apple.developer.ubiquity-container-identifiers`) (V, "Configuring iCloud services"). |
| Privacy label | No change (data goes to the user's iCloud via Apple; see section 5). |
| Testing | Hard to make deterministic: the real behaviour lives in a daemon. A fake `FileSystem` cannot reproduce eviction or conflict versions. |
| Migration | Trivial for A2 (move the folder), but every existing library also has to move its index out. |
| Turn sync off | Move the folder back out of iCloud Drive; any evicted files must download first, or data is lost. |
| Data-loss risk | **Highest:** iCloud picks winners, losing versions can be removed by any peer, SQLite/locks in the folder (unless moved), and evicted files that never come back on a full disk. |

**Verdict: rejected.** It cannot meet "always fully local" or "pause during a show", and both are hard rules.

---

## 3. Option B - CloudKit via CKSyncEngine, local folder canonical

### Facts
- `CKSyncEngine`: macOS 14.0+ (V, doc; `CKSyncEngineConfiguration.h:18` `API_AVAILABLE(macos(14.0), ...)` in the local SDK). "CKSyncEngine requires the CloudKit and Remote notifications entitlements." Only private and shared databases (V, doc).
- **The app owns state and conflicts.** "It's your responsibility to persist that state to disk and make it available across app launches"; "CKSyncEngine does *not* handle errors that require application-specific logic. For example, if you try to save a record and get a serverRecordChanged, you need to handle that error yourself." (V, doc). WWDC23 shows the pattern: on `.serverRecordChanged`, merge `serverRecord` into local data, re-add the pending save (V, WWDC23 session 10188 "Sync to iCloud with CKSyncEngine").
- **Retries are automatic** for `networkFailure`, `networkUnavailable`, `serviceUnavailable`, `requestRateLimited`, `zoneBusy`, `notAuthenticated`, `accountTemporarilyUnavailable` (V, doc). Offline is the normal case: changes stay pending.
- **Scheduling** is the system's: "the engine's sync schedule is indeterminate"; usually seconds. Manual `fetchChanges` / `sendChanges` / `cancelOperations` exist (V, doc). `automaticallySync = false` gives full manual control, documented for "deterministically simulate certain conditions in your unit tests" (V, `CKSyncEngineConfiguration.h:60-70`).
- **Batches** are bounded at 250 records per request (saves plus deletes) (V, doc). A record's own fields are limited to 1 MB; larger values belong in a `CKAsset` (V, Core Data doc "Reading CloudKit records for Core Data"; asset ceiling U, forums 651358/827897).
- **Push:** the engine creates a `CKDatabaseSubscription` and uses silent pushes (V, doc). On macOS the push entitlement is `com.apple.developer.aps-environment` (V, entitlement doc). Xcode adds Push Notifications automatically when CloudKit is enabled (V, "Configuring iCloud services"). CloudKit sends its own pushes, so no APNs certificate or key is needed (U, standard behaviour; the account help page describes APNs certificates only for apps that run their own push server).
- **Environments:** "Apps in the App Store can access only the production environment. Before you publish your app, you must deploy the development schema"; "you can't delete record types or fields that are already in production"; "your app in development can access either the development or the production environment" (V, "Deploying an iCloud container's schema"). So a dev-signed Personal build defaults to Development and would not see App Store data unless it is pointed at Production (`com.apple.developer.icloud-container-environment`, U on the exact macOS behaviour; spike in session S2).
- **Reliability record (2025-2026):** iOS 26.4 dropped CloudKit pushes so apps missed remote changes, fixed in 26.5; one report says macOS Tahoe 26.4 was not affected (V, forums thread 820550; TidBITS 2026-04-06). macOS 26.5: pending changes added during event handling not sent until relaunch, open (V, forums thread 829402). macOS-specific: automatic fetch "often taking minutes", manual `fetchChanges()` also delayed with automatic sync on; no Apple reply (V that it was reported, forums thread 785368). API design gaps (no batch identity, coalescing) with DTS advice to "figure out the difference between the server record and the local one" at `SentRecordZoneChanges` (V, forums thread 771941). Apple uses it for Freeform, and NSUbiquitousKeyValueStore was rebuilt on it (V, WWDC23 10188).

### Design sketch
- **Zone:** one custom zone per library in the private DB, named by a new library ID (ULID) stored in the library root (e.g. `<root>/segue-library.json`). Opening a different library folder can never merge into the wrong zone.
- **Record per item, named by its ULID:** `Song` (`.cho` text as a String field, under the 1 MB limit with an asset fallback above ~512 KB; slug; content hash; schemaVersion), `SongMeta` (the sidecar, one CKRecord field per top-level sidecar key: tags, notes, proficiency, cues, displayPrefs, live, bass, parts), `Setlist`, `SmartFilter`, `Show`, `Settings` (one record per settings group). The brief suggested assets for the `.cho`; a String field is better because it lands atomically with the record and leaves no asset files to download. Use assets only for oversize text.
- **Stamps:** each syncable field carries a hybrid logical clock stamp `(wallMillis, counter, deviceULID)` in a `stamps` map field. Newest-wins is decided per field, so a fill added on the Neo and a lyric fix on the desktop both survive. Each field has a single writer per merge; the losing value goes to history. HLC keeps "newest" equal to human time while guarding against clock skew.
- **Local folder stays canonical.** Remote changes are applied **through the stores** (`LibraryStore`, `SetlistStore`, `ShowStore`, `SmartFilterStore`) with an origin of `.remote`, so the index, undo and conflict checks stay correct and the apply does not echo back as a local change.
- **Sync ledger** (GRDB, in the sandbox container's Application Support, per library ID): per item the record's encoded system fields (change tag), last-synced content hash per field, HLC, and the serialized engine state. It is a **rebuildable projection**: if it is lost, a full fetch re-merges by ULID, and equal hashes are no-ops (idempotent replay).
- **Change capture:** store hooks enqueue pending saves; a launch and activation rescan compares file hashes against the ledger, which catches edits made outside Segue (the `.cho` is a plain file users edit in other editors).
- **Deletes:** tombstones propagate a delete; the receiving Mac moves its file to the Trash (the existing `trashItem`), so a remote delete is always recoverable.
- **Gig safety:** every item is a real local file before and after sync, so always-local holds by construction. At Live start the coordinator calls `cancelOperations()` and releases the engine (no network activity at all); local edits made during the show (show record, reorder review, a quick chart fix) go into the ledger as pending. At show end a new engine is created from the saved state, fetches, applies and sends. Nothing on the show path awaits the sync layer.
- **Account events:** `signOut` / `switchAccounts` stop sync and **keep every local file** (unlike apps that wipe local data); a different account needs an explicit re-join.
- **Memory on the 8 GB Neo:** records are tiny (KB), batches are 250 records, and nothing loads the whole library into CloudKit objects at once. Measure in S4 against the R168 budget style (flag over 400 MB) (U until measured).

### Against the requirements
| Requirement | B |
|---|---|
| Concurrent edits | Strong: server change tags detect every race (`serverRecordChanged` carries the server record), and per-field HLC merge is deterministic and the same on both Macs. |
| Newest wins + history | Implemented in our code, fully testable. Losers are written to a local history store. |
| Offline / gig safety | Meets all three rules by construction (local canonical files, engine released during Live, no awaits on sync). |
| Entitlements | `com.apple.developer.icloud-services` = `[CloudKit]`, `com.apple.developer.icloud-container-identifiers` = `[iCloud.dev.ryandsilva.segue]`, `com.apple.developer.aps-environment` (V, "Configuring iCloud services"; aps doc). network.client is already present. Provisioning profiles must include the capabilities (regenerate the manual Mac App Store profile). |
| Testing | Deterministic fake (section 7) plus `automaticallySync = false` multi-engine tests against the Development environment, as WWDC23 recommends: "you can simulate device-to-device user flows using multiple CKSyncEngine instances" (V, WWDC23 10188). |
| Migration | Merge by ULID (section 8). |
| Turn off | Nothing local changes; cloud copy stays unless the user deletes it (section 8). |
| Data-loss risk | Lowest: local files never become placeholders, every overwrite (local or remote) writes the loser to history first, deletes go to the Trash, and the ledger is rebuildable. Residual risks: our own merge bugs (mitigated by the fake-cloud suite) and CloudKit regressions delaying sync (they delay, they do not lose data). |
| Cost | Highest build cost (record codecs, ledger, applier, history, UI). Per the owner's rules this weighs little against correctness. |

---

## 4. Option C - hybrids and NSUbiquitousKeyValueStore

- **NSUbiquitousKeyValueStore for settings:** 1024 keys, 1 MB total, key 128 UTF-16 chars; entitlement `com.apple.developer.ubiquity-kvstore-identifier`; "You must distribute the app through the App Store or Mac App Store" (V, doc); unencrypted on disk; changes arrive via `didChangeExternallyNotification`. **No documented conflict policy** (V, absence in the doc). Pros: tiny code. Cons: a second transport with its own semantics, no per-key stamps or history, a third entitlement, and the distribution note puts the dev-signed Personal build in doubt (U). It was rebuilt on CKSyncEngine anyway (V, WWDC23).
- **CloudKit for data + KVS for settings:** workable, but two conflict policies and two test stories. **Rejected in favour of `Settings` records in the same engine.**
- **iCloud Drive as transport with a private local mirror:** the app copies a hidden synced folder into its local canonical folder. It inherits all of A's conflict behaviour and adds a mirror, so it is worse than B on every axis. Rejected.
- **CKSyncEngine + CKAsset of a whole-library archive** (snapshot sync): simple, but last-writer-wins on the whole library loses concurrent edits. Rejected.

---

## 5. Sandbox, App Review and privacy label

- **Sandbox:** CloudKit works in the sandbox with the iCloud entitlements; no file exceptions are needed because B never touches iCloud Drive. Push needs `com.apple.developer.aps-environment` on macOS (V). `verify-archive.sh` check 4 and `SegueAppStore.entitlements` change together (repo rule).
- **Privacy label:** "Collect" means "transmitting data off the device in a way that allows you and/or your third-party partners to access it"; under Apple frameworks such as CloudKit, "You are not responsible for disclosing data collected by Apple" (V, App Store "App privacy details"). Private-database records are not accessible to the developer, so **no new label entry** is expected (U as a ruling; consistent with Apple's definition). The website privacy policy should still say that sync stores the library in the user's own iCloud account and that the developer cannot read it.
- **App Review:** no guideline found that restricts CloudKit private-database sync (U). Sync is opt-in and the app works fully without an Apple Account or iCloud, which is the safe posture. The schema must be deployed to Production before the build is submitted (V, schema doc); a missing production schema is a classic review-time failure (U).
- **Quota:** private-database data counts against the user's iCloud storage; `quotaExceeded` must surface as a clear "iCloud is full, this Mac keeps working locally" status, never a failure of local saves (U for exact error flow, standard CloudKit behaviour).

---

## 6. Recommendation

**Option B: CKSyncEngine over the CloudKit private database, one zone per library, records per item named by ULID, per-field HLC newest-wins, local files canonical, history kept locally, settings as records in the same engine, engine released during a Live show.**

It is the only option that meets the three gig-safety rules by construction, it puts the newest-wins and history behaviour in our deterministic code instead of a daemon's, and it follows the owner's rules (no automation-driven folder under file sync, no dataless placeholders, idempotent replay keyed on ULIDs, a rebuildable ledger, graceful degradation when iCloud is unreachable). The 2026 CloudKit regressions delay sync but do not lose data, because nothing on the local side depends on sync finishing.

### Port and adapter design

```swift
/// SegueCore (platform-neutral). Core sync logic depends only on this.
public protocol SyncPort: Sendable {
    /// Starts or resumes syncing a library zone; delivers events until stopped.
    func start(zone: LibraryZoneID, state: SyncEngineState?, events: SyncEventSink) async throws
    /// Releases every operation and network activity (Live show, sync off, sign-out).
    func stop() async
    func enqueue(_ changes: [PendingChange]) async        // saves and deletes by ItemKey
    func fetchNow() async throws                          // catch-up after a show, menu "Sync Now"
    func sendNow() async throws
    func deleteZone(_ zone: LibraryZoneID) async throws   // "Delete iCloud data", explicit only
    var capabilities: SyncCapabilities { get }            // e.g. push-driven fetch, honest flags
}

/// Plain values the adapter renders; no CKRecord crosses the port.
public struct SyncRecord: Sendable, Equatable {           // inward: no raw vendor blob
    public var key: ItemKey                               // kind + ULID
    public var fields: [FieldName: FieldValue]
    public var stamps: [FieldName: HLCStamp]
    public var schemaVersion: Int
}
public enum SyncEvent: Sendable {                         // outward; may carry a raw payload for logs
    case fetched([SyncRecord], deleted: [ItemKey])
    case sent(saved: [ItemKey], failed: [SendFailure])    // .conflict(server: SyncRecord), .quota, ...
    case stateUpdated(SyncEngineState)
    case account(AccountChange)
}
```

- **Core (SegueCore, `Sync/`):** `SyncCoordinator` (actor) owning the ledger, change capture, `FieldMerger` (pure HLC newest-wins, emits `HistoryEntry`s), `RemoteApplier` (calls the stores with `.remote` origin), `ShowGate` (stop at Live start, catch up at end), `HistoryStore`. Clock, ULIDs and the port are injected.
- **Adapters:** `FakeCloudSync` (in-memory server with change tags, zones, tombstones, scripted latency, drop and duplicate delivery, and quota errors; several "devices" share one server), and `CloudKitSync` in a new package (e.g. `Packages/SegueCloud`, the only module that imports CloudKit) wrapping `CKSyncEngine`, the record codecs and the error mapping.
- **Config-driven:** a `sync.backend` setting `off | cloudkit | fake` (fake only in test and E2E launch options), plus `sync.enabled` per library. Off is the default.
- **What gets no port:** the merge policy, history and ledger are ordinary core code with one implementation; the clock and ULID generator are dependency injection for testing, not pluggability. The adapter-swap rule holds: swapping the bound adapter means a fresh full merge, never a ledger reuse.

### Build-session split
- **S0 (independent, small):** move `index.sqlite`, `library.lock` and show `.lock` files out of the library folder (or detect a file-provider folder and warn), fixing finding 1.1. Optional; see question 16.
- **S1 Core sync, no CloudKit:** library ID file, `SyncPort`, `SyncRecord` codecs for all six kinds, HLC, ledger (GRDB in Application Support), store hooks + rescan capture, `FieldMerger`, `RemoteApplier` with echo suppression, Trash on remote delete, `HistoryStore`, `ShowGate`, `FakeCloudSync`. Integration tests: two simulated Macs, each with a real temp library folder and real stores, on one fake server.
- **S2 CloudKit adapter:** prerequisites are the owner's portal steps (section 9). `SegueCloud` package, `CKSyncEngine` delegate, zone and `serverRecordChanged` handling, account changes, quota, state persistence, entitlements in all three files + `verify-archive.sh` check 4 + Project.swift, Development-environment test host, the Personal Production-environment spike.
- **S3 UI and settings:** Settings > Sync pane (toggle, status, last sync, "iCloud full", Sync Now, Turn Off, Delete iCloud Data), the first-enable join flow, a per-item "Previous Versions" history browser with restore, `Settings` records with the per-Mac allowlist, non-PII analytics events (enabled, items synced, conflicts resolved, catch-up time), the user guide page.
- **S4 Real-cloud E2E and release:** a scripted two-Mac checklist (desktop + Neo): concurrent edit of the same field and of different fields, offline edit on both, edit during a Live show then catch-up, delete and restore, sign-out, sync off and on, first join with two existing libraries; the Neo CPU and memory check; deploy the schema to Production; update the privacy policy and site guide.

### Testing strategy
- **Default gate:** in-process tests against `FakeCloudSync` with real stores and temp folders, injected `ManualClock` and ULIDs (deterministic, fast). Cover: field-level merge, HLC skew, duplicate and out-of-order delivery (idempotent), tombstones vs edits, schema-version skew, show pause and catch-up, ledger loss followed by rebuild.
- **Real CloudKit:** an opt-in `make cloud-test` (never in `make gate`) that runs two `CKSyncEngine` instances with `automaticallySync = false` against the Development environment, in a signed test host on a Mac signed in to iCloud, as WWDC23 demonstrates. Real pushes cannot be faked; the two-Mac S4 checklist covers them.
- **Before each E2E run:** delete the dev zone and reset both libraries to a known baseline (owner rule).

---

## 7. Migration, turning off, data-loss summary

- **First enable on Mac 1:** create the library ID and zone, then upload everything (250 records per batch).
- **Enable on Mac 2:** choose "Join the iCloud library" (the local library adopts the zone's library ID). Empty local library: download everything. Existing local library: merge by ULID (same ID: per-field newest-wins with history; different IDs: both kept), then show a near-duplicates list (reusing `NearDuplicates`) for the user to merge by hand. Welcome seed songs are de-duplicated by seed tag + content hash.
- **Different app versions on the two Macs:** a record with a newer `schemaVersion` is stored and opened read-only (today's rule), and the older Mac never uploads over it.
- **Turn off:** release the engine and delete the ledger and engine state. Every file stays local, so nothing is lost. The cloud copy remains until "Delete iCloud Data" (explicit, confirmed). Turning on again re-joins by ULID with idempotent hashes.
- **Sign-out / account switch:** stop, keep local, and require an explicit join for the new account.
- **Data-loss posture:** every overwrite writes history first, every delete goes to the Trash, the ledger is a projection, and local files are never placeholders.

---

## 8. Open questions for the owner (each with a recommendation)

1. **Does phase 9 supersede R132's removal of iCloud sync (and R134's "no Segue sync engine") for Mac-to-Mac?** Rec: yes, recorded as a new R-ruling scoped to macOS.
2. **Approach.** Rec: B (CKSyncEngine, local canonical). A fails two hard rules.
3. **Merge granularity:** whole item vs per field. Rec: per top-level field for sidecars, setlists (name, venue, date, target, changeover, entries as one field), filters and settings; the `.cho` text whole (no text merge).
4. **History location and retention.** Rec: `<root>/history/<kind>/<ulid>/<HLC>.json|.cho` inside the library (it is not rebuildable, so not in `.segue/`), never synced, kept for 90 days or the last 20 versions per item, whichever keeps more; excluded from the archive export by default.
5. **Which flavours sync, and do they share data?** Rec: both, sharing `iCloud.dev.ryandsilva.segue`, with the Personal build pinned to the Production environment so both see one library (spike in S2).
6. **Settings allowlist.** Rec, sync: instrument profile, live/stage settings, metronome, rehearsal shortcuts, audio sounds and volume, appearance, changeover default, fill editor, `shape-library.json`, key bindings. Per Mac: audio output device, MIDI bindings, privacy consent, AI toggle and downloaded models, bookmark, onboarding, What's New, review prompt, analytics IDs.
7. **Settings transport.** Rec: `Settings` records in the same CKSyncEngine zone, not NSUbiquitousKeyValueStore (one conflict policy, history, testable, no KVS distribution caveat).
8. **What pauses, and when.** Rec: the engine is fully released during a Live show only; Rehearsal and single-song sessions keep syncing, but a remote change to the song on screen applies when that song is left.
9. **Local edits during a show.** Rec: queued in the ledger, sent at show end with the catch-up.
10. **First join with two existing libraries.** Rec: merge by ULID, never auto-merge different IDs, show the near-duplicate list; seed songs de-duplicated automatically.
11. **Remote deletes.** Rec: move to the Trash + history entry, never a hard delete.
12. **Turning off.** Rec: keep local and cloud; separate confirmed "Delete iCloud Data".
13. **Sign-out / account switch.** Rec: stop, keep local, explicit re-join.
14. **Clock for "newest".** Rec: HLC on wall-clock milliseconds with a device-ULID tiebreak.
15. **Schema skew between app versions.** Rec: newer records are read-only on the older Mac and are never overwritten by it; show "Update Segue on this Mac to edit".
16. **Latent issue 1.1 (index + lock inside a file-synced folder today).** Rec: S0 ticket that moves the index and locks to Application Support keyed by library ID, plus a gentle warning when the library sits in a file-provider folder.
17. **Roadmap slot.** Rec: after the v0.5 submission, as its own release (new entitlements, schema deployment and review).
18. **Status surface.** Rec: a quiet sync status in the library footer and the Settings > Sync pane; a push notification only for sustained failure (e.g. 24 h unsynced with pending changes).
19. **Research ticket option.** If question 5 or 8 feels load-bearing, Rec: run the S2 Personal-environment spike and the Live-pause spike first as a research ticket, before S1 starts.

---

## 9. Owner's manual steps (Apple's current docs)

Account Holder or Admin role (you are both). Do these before session S2.

**A. Create the iCloud container** (help/account/identifiers/create-an-icloud-container):
1. In Certificates, Identifiers & Profiles (developer.apple.com/account/resources), click **Identifiers** in the sidebar, then click **+** at the top left.
2. Select **iCloud Containers**, click **Continue**.
3. Description `Segue`, identifier `iCloud.dev.ryandsilva.segue` (must begin with `iCloud.`, per "Configuring iCloud services"). Click **Continue**, then **Register**.

**B. Enable iCloud + CloudKit on each App ID** (help/account/identifiers/enable-app-capabilities). Repeat for `dev.ryandsilva.segue` and `dev.ryandsilva.segue.personal` (not the `.quicklook` extensions):
1. **Identifiers** in the sidebar, select the App ID.
2. Under Capabilities, tick **iCloud**; under Compatibility choose **Include CloudKit support**.
3. Click **Edit** next to iCloud, select `iCloud.dev.ryandsilva.segue` in the table, click **Continue**.
4. Tick **Push Notifications** on the same App ID (no APNs certificate is needed: CloudKit sends its own pushes; U, see section 3).
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
5. Review the pending changes and click **Deploy**. Fields cannot be deleted from production afterwards, so S2 should settle the record schema first.

**E. Both Macs:** System Settings > [your name] > iCloud: signed in to the same account, iCloud Drive not required. During S4, check that Segue appears under the apps using iCloud.

---

## Sources
- Apple: CKSyncEngine (developer.apple.com/documentation/cloudkit/cksyncengine-5sie5); `CKSyncEngineConfiguration.h` (local SDK); WWDC23 10188 "Sync to iCloud with CKSyncEngine"; sample github.com/apple/sample-cloudkit-sync-engine; "Configuring iCloud services" (documentation/xcode/configuring-icloud-services); `com.apple.developer.aps-environment`; NSUbiquitousKeyValueStore; FileManager `startDownloadingUbiquitousItem(at:)`; NSFileVersion; TN2336 "Handling version conflicts in the iCloud environment"; "Deploying an iCloud container's schema"; App Store "App privacy details"; Account help: create an iCloud container, enable app capabilities, edit/download profiles.
- Forums: 756963 (no Keep Downloaded API), 804253 (inconsistent conflict winner), 820550 and 829402 (2026 CloudKit regressions), 785368 (slow automatic fetch on macOS), 771941 (CKSyncEngine API gaps), 689468 (NSMetadataQuery for picked folders, from R7.2), 651358 / 827897 (asset limits).
- Third party: eclecticlight.co 2023-10-25 and 2024-03-18 (Sonoma FileProvider, eviction); TidBITS 2026-04-06 (iOS 26.4 CloudKit bug); forums.zotero.org/discussion/83344 (SQLite under cloud sync).
- Repo: `git show 2840356:docs/research/phase7-sync.md` (R7.2); `docs/release/decisions.md` R1, R11, R12, R132, R134 (history via `git log -S R134`), R143.
