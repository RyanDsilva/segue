# Data compatibility

How Segue's persisted formats stay readable across versions, from v1.0 (the first public release, which sets the baseline) onwards. Every change to anything Segue writes to disk or to UserDefaults follows the rules in section 3; section 4 is the policy for a file written by a newer Segue; section 5 is the mechanism; section 6 is the test suite and its guard.

Ruling basis: **R196** (the v1.0 compatibility rules, closing the audit's open decisions); the owner's requirement (2026-11-01) "once we have the data schema down in this version, releasing newer versions must be backward compatible ... our data schema is extendable"; R177 / R179 and `docs/phases/9-workstreams/P9-6-icloud-sync.md` (iCloud sync after v1.0: one record per ULID, per-top-level-field merge, "an older Mac stops syncing until updated").

Section 8 records how R196 closed the audit's decisions.

## 1. Terms

- **Backward compatible**: a newer Segue opens every file an older one wrote (migrations, section 3.3).
- **Forward compatible**: an older Segue opening a file a newer one wrote never destroys data (section 4).
- **Schema version**: the integer `schemaVersion` at the top of a versioned JSON file (`schema` in `library.json`). A file without one is version 0 (pre-versioned).
- **Minimum reader version**: the integer `minReaderVersion` beside it (R196): the oldest schema version whose builds may edit the file. v1.0 writes it equal to `schemaVersion`; a file without one (written before R196) counts as its own `schemaVersion`.
- **Kept keys**: keys a build does not model, plus known keys whose value it could not read, held verbatim in a value's `unknown` (`UnknownFields`) and written back on save.
- **Released versions**: none before v1.0. The development numbers (sidecar 6, setlist 7, show 5, filter 1, bindings 2, shapes 1, library identity 1) are frozen as the v1.0 baseline (R196); Ryan's own library holds files at the earlier dev versions, so their migrations stay.

## 2. Inventory

Verdicts: **compliant** (met the requirement before this audit), **fixed** (gaps closed in this change), **decision** (needs a ruling, section 8), **n/a** (not user data, or never written).

| Format | Where | Version (dev history) | Newer file | Unknown keys / values | Migrations tested | Sync | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Song source `.cho` | `songs/<slug>.cho` | none (ChordPro text) | n/a | Unknown directives kept verbatim: the parser and serializer round-trip byte for byte and edits are text patches (`ChordProParser` doc) | n/a | whole text is the `source` field | compliant |
| Song sidecar | `songs/<slug>.segue.json` | **6** (0 pre, 1 P0, 2 P1 display prefs, 3 cues + live, 4 cue IDs, 5 bass, 6 parts) | editable when its `minReaderVersion` is met; else read-only, never rewritten | kept at the top level and in `cues[]`, `displayPrefs`, `live`, `bass`, `parts[]`; unreadable cues and parts kept and written back | v0-v6 fixtures + goldens | ULID `id`; top-level fields merge alone; `updatedAt` excluded | fixed |
| Setlist | `setlists/<slug>.setlist.json` | **7** (0 pre, 1 P0, 2 item IDs, 3 breaks, 4 locked, 5 arrangements, 6 passes, 7 medleys) | editable when its minimum is met; else read-only, never rewritten | kept at the top level, per entry, per medley and medley member; unreadable members kept | v0-v7 fixtures + goldens | ULID `id`, entries keyed by ULID `itemId`; `entries` merges whole (R179) | fixed |
| Show record / Gig Log | `shows/<ulid>.show.json` | **5** (1 P2, 2 breaks, 3 arrangements, 4 passes, 5 medleys) | editable when its minimum is met; else read-only (gig log shows it), never rewritten | kept at the top level, per item, in `gig`; unreadable requests and events kept | v1-v5 fixtures + goldens | ULID `id`; only finished gig shows sync (P9-6 7.4) | fixed |
| Smart filter | `filters/<slug>.filter.json` | **1** (0 hand-written) | editable when its minimum is met; else usable read-only, never rewritten | kept at the top level and in `conditions` (unknown proficiencies kept); the removed `length` is dropped on purpose | v0-v1 fixtures + goldens | ULID `id`; `name`, `conditions` | fixed |
| Key bindings | App Support `bindings.json` | **2** (0 pre, 1 P2, 2 bumped so older builds read `toggleSingerView` best effort) | read as current when its minimum is met; else applies what it can, reports the rest | the app never writes it | v0-v2, compatible-newer and newer fixtures | `.key` bindings sync as one field (P9-6 14.1) | compliant |
| Chord shape library | App Support `shape-library.json` | **1** | read when its minimum is met; else refused with a message, never rewritten | the app never writes it | v1, compatible-newer and newer fixtures | `shapes` as one field | compliant |
| Library identity | `.segue/library.json` | `schema` **1** (P9-6 S0) | refuses to open the library ("update Segue"); the ID is never re-minted for it (R196) | never rewritten once valid | v1, compatible-newer and newer fixtures | the library ULID keys the zone | fixed |
| Library state | App Support `Libraries/<id>/state.json` | none (per Mac) | n/a | kept | in-process test | never synced | fixed |
| Upgrade marks | `.segue/upgrades.json` | none | n/a | kept (an older build no longer forgets a newer build's marks) | in-process test | not synced | fixed |
| Settings blobs | UserDefaults `instrument.profile`, `live.settings`, `audio.settings`, `fill.editor` | none; lenient per field | n/a | kept; unknown enum cases read as the default | in-process test | per property (P9-6 14.1) | fixed |
| Settings scalars | UserDefaults `appearance.mode`, `setlists.defaultChangeoverSeconds`, `live.rehearsalShortcuts`, `live.metronome`, `ai.useAI`, `privacy.consent`, onboarding, Welcome, What's New, review, tips, `segue.preview.singer`, `libraryFolderBookmark` | none | n/a | an unknown raw value reads as the default and is not rewritten until the user changes it | n/a | per P9-6 14.1 / 14.2 | compliant |
| PDF export options | UserDefaults `export.pdf.options` | none | n/a | kept (R196) | in-process test | per Mac | fixed |
| Session restore | UserDefaults (`SessionRestore.RestoredState`) | none | n/a | dropped; unreadable state reads as none | none | per Mac | compliant (transient) |
| Archive export | `Segue Library <date>.zip` | none: `songs/`, `setlists/`, `shows/`, `filters/` copied verbatim; no manifest (R196) | each file carries its own version | the files themselves | `LibraryArchiveTests` | not synced | compliant |
| Search index | App Support `Libraries/<id>/index.sqlite` | `SongIndex.schemaVersion` 4 x 1000 + `RomanNormalizer.version` | a different version rebuilds it | rebuildable projection | `SongIndex` tests | never synced | compliant |
| Library and show locks | App Support `library.lock`, `shows/<ulid>.show.lock` | none (flock only) | n/a | no content | n/a | never synced | n/a |
| AI models | App group `custom-models.json`, per-model `.segue-installed.json` | catalog `schemaVersion` 1 (not migrated) | n/a | `custom-models.json` keeps unknown keys, unreadable entries and entries this build refuses (R196); an unreadable marker re-downloads | in-process test | per Mac | fixed |
| Services | consent and throttle in UserDefaults, `latest-diagnostic.json`, report drafts, the TelemetryDeck `queue.json` | none | n/a | transient: an unreadable file is dropped | services tests | never synced | compliant (transient) |
| SeguePersonalModules | nothing persisted (the page cache is in memory, per launch); `segue-import-eval` writes only `research/` files | n/a | n/a | n/a | n/a | n/a | n/a |
| Bundled data | Welcome seeds `manifest.json`, `AIConfig/assistant.json`, fixtures | ships with the app, read-only | n/a | n/a | n/a | n/a | n/a |

## 3. Rules for every change to a persisted format

### 3.1 Evolution is additive

1. **New fields are optional, with a default.** Decoding a file without the field must give exactly today's behaviour. Never make an existing optional field required.
2. **No rename, no removal, no change of meaning or type** without a schema bump and a migration step. A field removed on purpose (a dropped feature) goes in the type's `retired` keys so it is dropped instead of kept, and its migration (or the owner's cleanup rule) strips it from files.
3. **Adding a value to an always-set enum field requires a schema bump** (R196), and a `minReaderVersion` raise if older builds must not edit such files: an older build reads the new case as the default and writes the default back (section 5.3). In an optional field or a list a new case degrades without loss.
4. **Identity never changes.** Every record and every list element that can be edited on its own has a ULID (`SongID`, `SetlistID`, `SetlistItemID`, `ShowID`, `ShowRequestID`, `SmartFilterID`, `CueID`, `PartID`, the library ID). IDs are minted once and never derived from paths; deterministic derivation is allowed only in migrations (so two Macs migrating the same file get the same IDs: `SetlistItemID.migrated`, `SidecarCodec.derivedCueID`).
5. **Don't store derived data** that another Mac could compute differently, unless it is a snapshot that must not change (a show's `setlistName` and item `title`) or a hint never merged (P9-6 7.2 `hints`). Timestamps written on save (`updatedAt`) are not merged.
6. **One field, one meaning, at the top level.** Sync merges per top-level field (R177): put a value that changes independently in its own top-level key rather than inside another field.
7. **`.cho` files stay standard ChordPro.** App metadata goes in the sidecar, never in a new directive. A Segue-only directive, if ever needed, uses ChordPro's `x_` prefix.
8. **Every JSON file is written through `SegueJSON`** (sorted keys, ISO 8601 with milliseconds), so equal values give equal bytes and hashes.

### 3.2 When to bump `schemaVersion` and `minReaderVersion` (R196)

- **`schemaVersion`** goes up with every change to a file's shape, so a newer file is always recognisable as newer.
- **`minReaderVersion`** (the static `currentMinReaderVersion` beside `currentSchemaVersion`) goes up only when a build at the old version would lose or misread data by editing the file: a reshaped value (`steps` to `passes`), a changed meaning, a new required field, a new case in an always-set enum field. An added optional field leaves it alone: older builds edit the file and keep the new key (section 5.1).
- v1.0 writes `minReaderVersion` equal to `schemaVersion` for every format.

### 3.3 Checklist for a bump

1. Raise `currentSchemaVersion` and add the history line in its doc comment; raise `currentMinReaderVersion` only if section 3.2 says so.
2. Add `steps[n]` to the format's `SchemaMigrator` (even `{ _ in }` for an additive shape).
3. Add `Packages/SegueCore/Tests/Fixtures/compat/<format>/v<N>.json`: a file exactly as this build writes it, exercising the new shape.
4. Record goldens: `SEGUE_UPDATE_COMPAT_GOLDENS=1 swift test --filter DataCompatibility` in `Packages/SegueCore`, and review every changed `*.saved.json`: older versions' goldens change only if the migration meant them to.
5. Keep `future.json` (999, no minimum: never editable) and `compatible-newer.json` (999, minimum = the current version) newer than the new version.
6. Sync: add the field to P9-6 section 7.3's lists (`RecordCodecTests`, P9-6 7.5).

The guard (section 6) fails the build's tests when step 3 or 4 is missing, or when a new versioned format is not registered.

## 4. Policy: a newer file opened by an older Segue (R196)

Every versioned file carries `schemaVersion` and `minReaderVersion`. A build reading a file with a newer `schemaVersion`:

- **Editable when the build meets the file's minimum** (`minReaderVersion` <= the build's `currentSchemaVersion`; `SchemaMigrator` decodes it as current). Everything the build does not model is kept, and a save writes the file back at **its own** `schemaVersion` and `minReaderVersion`, never downgrading it.
- **Otherwise read-only.** The item is shown with every field this build can read, marked "Created by a newer Segue - update to edit." (`ReadOnlyReason.newerSchema`, `UserMessage.readOnlyText`). Edits are refused before anything is written, and the file is never rewritten: not by a background save, a rename of another item, a tag rename across the library or an upgrade step. Setlists that reference such a song keep resolving.
- **App-level files**: `bindings.json` reads as current when its minimum is met, else applies what it understands and says how many bindings it skipped; `shape-library.json` reads when its minimum is met, else it is refused with a message and built-in shapes are used.
- **`.segue/library.json`** from a newer Segue whose minimum this build does not meet **refuses to open the library**: "This library was set up by a newer version of Segue. Update Segue to open it." (`LibraryIdentityError.newerSchema`). The file is never moved to the Trash and the ID is never re-minted for it. The key stays `schema`.
- **Current-version files with an unreadable entry keep today's behaviour** (R196): a bindings file falls back to the defaults with a message; a setlist or show is not loaded and is reported as a load issue, untouched.
- **Sync** (P9-6 13.5): a Mac that meets a record from a newer schema or protocol stops syncing until updated; local edits queue.

## 5. Mechanism

### 5.1 Kept keys (`Support/UnknownFields.swift`)

- `JSONValue`: any JSON value, verbatim.
- `UnknownFields`: the kept keys of one object and the unreadable elements of its known arrays. Not part of a value's identity (`==` always true, no hash), so `prefs == .init()` still means the defaults and no change check reacts to keys the app cannot show.
- `LenientObject<CodingKeys>`: reads an object field by field. `value(_:)` returns nil (or a default) for a missing or unreadable field and keeps the unreadable raw value; `required(_:)` throws for identity fields; `elements(_:)` reads an array element by element and keeps the unreadable ones.
- A type's `encode(to:)` calls `unknown.encode(to:)` **first**, then writes its own keys, which replace any kept raw value of the same name; arrays go through `unknown.appending(_:to:)` so kept elements follow the readable ones.
- Editors that rebuild a nested value from UI state (display prefs, live prefs, bass prefs, gig details, filter conditions) carry the kept keys of the value they replace.

### 5.2 Where keys are kept

Top level of every library file and every unversioned record; plus the first level of records inside them: sidecar `cues[]`, `displayPrefs`, `live`, `bass`, `parts[]`; setlist `entries[]`, `medley`, medley `members[]`; show `items[]`, `gig`, and unreadable `requests[]` / `events[]`; filter `conditions`. Deeper values (arrangement passes, walk-up picks, part events, overrides) are replaced whole by the field that holds them: a change inside them follows rule 3.1.2 (bump).

### 5.3 Known limits

- An unreadable value in a field that always has a value (for example `displayPrefs.capoMode: "sideways"`) reads as the default, and the default is written on the next save. Optional fields and list elements keep the raw value. Hence rule 3.1.3 (R196).
- A kept raw value of an optional field the user sets and then clears in the same session comes back on save (the app never showed it). Harmless and rare.
- Unreadable list elements are written after the readable ones: their position is not kept. Ordered lists where position matters (setlist entries, show items, planned entries) are strict instead: an unreadable element fails the file, which is reported and left untouched (R196 keeps this).

## 6. Tests and the guard

- **Suite**: `Packages/SegueCore/Tests/SegueCoreTests/DataCompatibilityTests.swift` (fixtures, registry, guard, sidecars, setlists) and `DataCompatibilityRecordTests.swift` (shows, filters, read-only files, unversioned records). In-process, real stores on a real temp library: every fixture is loaded, edited the way the app edits it, saved, and compared byte for byte with its golden. Each library format also has an unknown-keys round trip and a newer-version check (read-only, bytes unchanged).
- **Fixtures**: `Packages/SegueCore/Tests/Fixtures/compat/<format>/` - `v<N>.json` per version, `future.json` (newer, not editable), `compatible-newer.json` (newer, editable: saved at 999 with its own keys kept), `unknown-keys.json`, and the recorded `*.saved.json` goldens. Fixtures for development versions were authored from each version's documented shape (no released build exists to export from); from v1.0 on, each new version's fixture is a file the shipping build actually wrote.
- **Guard** (`DataCompatibilityGuardTests`): every registered format has a fixture (and, if the app writes it, a golden) for every version from its oldest supported to `currentSchemaVersion`, plus `future.json` and `compatible-newer.json`; `future.json` stays newer; every `static let currentSchemaVersion` / `currentSchema` / `schemaVersion` in `Packages/*/Sources` is registered in `PersistedFormat.all` or listed as rebuildable. It runs in `make quick`.
- Run it alone: `cd Packages/SegueCore && swift test --filter DataCompatibility`.

## 7. Sync readiness (for P9-6 S2)

- Every synced item has a ULID identity, and every independently edited element inside one has its own ULID.
- Top-level fields are independent and merge alone; nothing derived is merged (`updatedAt` is recomputed, slugs are hints).
- Obligation for the record codec (P9-6 7.2/7.3): a value's kept keys are fields too. Encode each kept top-level key as its own field, so a key a newer build added, or a tool wrote, round-trips through a Mac at the same schema instead of being dropped at the sync boundary.
- Watch: setlist entries carry `fileName` (R191), a per-Mac hint inside the `entries` field; a slug that differs between Macs makes `entries` differ without a user edit. Treat it as a hint in the codec or exclude it from the field hash.

## 8. Decisions (R196, 2026-11-01)

| Audit question | Ruling |
| --- | --- |
| D1 newer-file policy | `minReaderVersion` in every versioned file; v1.0 writes it equal to `schemaVersion`; a build edits a newer file whose minimum it meets, keeping what it does not know, else read-only with the existing notice (section 4) |
| D2 read-only notice | the existing "Created by a newer Segue - update to edit." |
| D3 dev schema numbers | frozen as the v1.0 baseline; dev migrations stay |
| D4 newer `library.json` | refuses to open the library and asks to update Segue; the ID is never re-minted; the key stays `schema` |
| D5 always-set enum fields | adding a value requires a schema bump (rule 3.1.3) |
| D6 archive manifest | none: each file carries its own version |
| D7 current-version `bindings.json` with an unknown entry | today's behaviour: defaults and a message |
| D8 current-version setlist or show with an unreadable entry | today's behaviour: not loaded, reported, untouched |
| D9 per-Mac blobs | `export.pdf.options` and `custom-models.json` keep unknown keys like every other format |
