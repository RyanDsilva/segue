# Phase 0 - Walking skeleton

Canonical context: `docs/00-vision.md` (product, decisions), `docs/research.md` (verified findings) and `docs/decisions.md` (closed answers). This doc is self-contained for one implementation session.

## Goal

The thinnest end-to-end Segue: one song travels through every stage - **add song -> library on disk -> index -> setlist -> live view** - on a properly structured, sandboxed, signed, two-flavor project with a working integration + E2E test harness. Every later phase thickens a slice that already runs.

## Scope

- Tuist-generated Xcode workspace, packages, schemes, entitlements, signing, build/test scripts.
- ChordPro parser v0 + serializer (round-trip).
- Library folder: choose folder, persist bookmark, read/write `.cho` + sidecar, rebuildable GRDB index.
- Song list with search, a plain text editor (raw ChordPro), "New song".
- One setlist type: ordered list of song refs, create/add/reorder.
- Basic live view: full-screen, dark, one song at a time, next/previous.
- Integration test suite over real Core components + one XCUITest E2E flow.

## Non-goals

Visual editor, transpose/capo/Nashville, chord diagrams, auto-fit/auto-scroll, request queue, gig log, AI, import/export, plugins, MIDI. No design polish - the 2-3 design directions are presented before phase 1/2 UI work.

## Project structure

```
Tuist.swift, Project.swift      Tuist manifests (checked in); Segue.xcworkspace/.xcodeproj generated + gitignored
Tuist/Package.swift             external SPM deps (GRDB, Tonic) pinned via Tuist
.mise.toml                      pins tuist, swiftlint, swiftformat
  App/                     macOS app target "Segue" (thin: app entry, scenes, DI wiring)
  Packages/
    SegueCore/           platform-neutral, no SwiftUI/AppKit imports
      Sources/ChordPro      AST, parser, serializer
      Sources/Library       LibraryStore, bookmark access, sidecars, index
      Sources/Setlists      Setlist model + store
      Sources/Plugins       empty registry protocols (placeholder for phase 5)
      Sources/Support       Clock, FileSystem protocols + live/fake impls
    SegueUI/             SwiftUI views; depends on Core
    SeguePersonalModules/ empty package, one target with a no-op plugin registration
  UITests/                 XCUITest target
  scripts/ , Makefile
```

- **Project generation:** Tuist. `tuist install && tuist generate` produces the workspace; nobody hand-edits project files. Schemes, configurations, entitlements and signing settings all live in `Project.swift`.
- **Dependencies:** GRDB (index), Tonic (music theory types, used from phase 0 so `Segment.chord` can hold a parsed chord later without a model change). Both pinned to exact versions.
- **Deployment target:** macOS 26.0. **Swift 6** language mode, strict concurrency complete in every target; warnings treated as errors.
- **Schemes / configurations:**
  - `Segue-Personal` - build configurations `Debug-Personal` / `Release-Personal`, links `SeguePersonalModules`, defines `SEGUE_PERSONAL`.
  - `Segue-AppStore` - `Debug-AppStore` / `Release-AppStore`, does **not** reference the personal package at all. A script check (`make verify-appstore`) builds this scheme and fails if any `SeguePersonalModules` symbol or path appears in the build product or its link map.
  - Plugin wiring: app calls `PluginRegistry.registerAll()`; the personal package provides the implementation via a small `#if SEGUE_PERSONAL` import in the app target only. Core never knows the package exists.
- **Entitlements (both flavors):** `com.apple.security.app-sandbox`, `com.apple.security.files.user-selected.read-write`, `com.apple.security.files.bookmarks.app-scope`. No network entitlement in phase 0.
- **Signing:** bundle id `dev.ryandsilva.segue` (UI tests `dev.ryandsilva.segue.uitests`), automatic signing with the free Personal Team `V6BM673U35` (contact@ryandsilva.dev), set as the single `DEVELOPMENT_TEAM` constant in `Project.swift`; ad-hoc signing remains a one-switch fallback. A paid team replaces it before App Store work.

## ChordPro parser v0

### Grammar (line oriented)

```
document   := line*
line       := directive | comment | lyricLine | blank
directive  := "{" name ( ":" | " " ) value? "}"        ; name case-insensitive, short forms mapped
comment    := "#" text                                 ; file comment, preserved
lyricLine  := ( chordToken | text )+
chordToken := "[" chordText "]"                         ; chordText kept verbatim in v0
```

Directives understood in v0: `title|t`, `subtitle|st`, `artist`, `key`, `capo`, `tempo`, `time`, `duration`, `comment|c`, `start_of_verse|sov`, `end_of_verse|eov`, `start_of_chorus|soc`, `end_of_chorus|eoc`, `start_of_bridge|sob`, `end_of_bridge|eob`, `chorus` (repeat reference), plus `start_of_<x>`/`end_of_<x>` generic sections with optional label (`{start_of_verse: Verse 2}`). Unknown directives are kept as `.unknown(name, value)` and re-serialized verbatim.

### AST

```swift
struct SongDocument: Sendable, Equatable { var metadata: Metadata; var blocks: [Block] }
struct Metadata { title, subtitle, artists: [String], key, capo: Int?, tempo: Double?, time, duration: TimeInterval?, extra: [String: [String]] }
enum Block { case section(Section), line(Line), comment(String), directive(UnknownDirective), chorusRef(label: String?), blank }
struct Section { kind: SectionKind /* verse, chorus, bridge, tab, custom(String) */; label: String?; lines: [Line] }
struct Line { var segments: [Segment] }          // lyric line
struct Segment { var chord: String?; var text: String }  // chord sits above start of text
```

Requirements: never throws on malformed input - unclosed braces/brackets become text and produce a `Diagnostic` (line, column, message) list alongside the AST. `serialize(parse(x))` is byte-identical for canonical input and stable (idempotent) for any input. Parsing a 300-line song < 5 ms.

## Library folder

- First launch: "Choose library folder" (NSOpenPanel, create allowed). Store a security-scoped bookmark in UserDefaults; resolve on launch, re-prompt if stale. Default suggestion: `~/Music/Segue` (not Desktop/Documents).
- Layout:

```
<Library>/
  songs/<slug>.cho              canonical song
  songs/<slug>.segue.json     sidecar (ALL app-only metadata): id, schemaVersion, tags, proficiency, notes, displayPrefs, createdAt, updatedAt
  setlists/<slug>.setlist.json  id, schemaVersion, name, entries: [{songId}]
  .segue/index.sqlite         rebuildable projection, safe to delete
```

- The `.cho` stays clean, portable ChordPro: app metadata (tags, proficiency, notes, display prefs) lives only in the sidecar, never mirrored into `{meta}`.
- **Schema versioning:** integer `schemaVersion` in every sidecar and setlist file. Older versions are migrated forward on read and written back at the latest version on next save. A **newer** version than the app knows opens the song **read-only** with a visible warning ("created by a newer Segue - update to edit"); it stays performable and searchable, edits are blocked, the file is never rewritten.
- Song identity: ULID in the sidecar (stable across renames); filename slug from title, de-duplicated (`-2`). A `.cho` with no sidecar gets one created on index.
- Writes: atomic (write temp + rename) through `NSFileCoordinator`; all IO goes through the injected `FileSystem` protocol.
- **Index (GRDB):** `DatabasePool` (WAL) with tables `songs(id, path, title, artist, key, tempo, mtime, content_hash)` + FTS5 virtual table over title/artist/lyrics. Schema changes bump an index version and trigger drop-and-rebuild from files - no data migrations, since the index is a projection. On launch: scan, compare mtime/hash, upsert changes, delete missing. "Rebuild index" deletes and re-creates from files. The index is never written to by anything except the indexer.
- **Romanized Hindi search:** lyrics and titles may be Hindi written in Latin script with no fixed spelling ("pyaar/pyar", "hai/hain", "kabhi/kabhie"). The indexer stores a deterministic `norm_*` form of title, artist, first line and lyrics alongside the originals, and FTS5 indexes both. `RomanNormalizer` (pure function, Core) applies, in order: lowercase + strip punctuation; collapse doubled letters (`pyaar`->`pyar`, `dill`->`dil`); vowel folding `aa->a`, `ee->i`, `ii->i`, `oo->u`, `uu->u`; `w->v`; drop `h` after consonants where it only marks aspiration (`bh->b`, `kh->k`, `dh->d`, `th->t`, `ph->p`, `gh->g`, `jh->j`, `chh->ch`); nasal endings `n` after a long vowel at word end dropped (`hain->hai`, `mein->mei`). The same function runs on the query. Matching order: exact FTS on originals, then FTS on normalized forms, then a trigram/edit-distance fallback (distance <= 1 per word for words of 4+ letters) over normalized titles and first lines. Original text is never modified; normalization exists only in the index. The rules live in one table so they can be tuned without touching callers, and changing them bumps the index version (drop-and-rebuild).
- External edits (file changed in another editor) picked up on next launch or manual refresh.

## Minimal setlist + live view

- Sidebar: Library, Setlists. Library: searchable song list (FTS), "New song" opens the raw text editor (TextEditor, monospace) with a rendered preview below.
- Setlist: create, add songs from library, drag reorder, delete entry.
- "Perform" on a setlist opens a full-screen window: black background, lyrics in large light text, chords in an accent color above their syllable, section labels, title + key + capo header. Arrow keys / space go to next/previous song; Esc exits. Disable idle sleep while open (`ProcessInfo.beginActivity` with `.idleDisplaySleepDisabled`).

## Test strategy

Integration-first: tests exercise real components wired together, not mocks. Unit tests exist only where pure logic is tricky enough to earn them.

- **Core integration suite (Swift Testing, `swift test`):** each test builds a real `LibraryStore` (real parser, real file store, real GRDB index) on a fresh temp directory on disk. Scenarios: create song -> `.cho` + sidecar on disk with expected bytes -> FTS search finds it; external edit of a `.cho` -> refresh updates index; delete `index.sqlite` -> rebuild yields identical search results; rename/duplicate titles -> stable ULIDs and de-duplicated slugs; orphan `.cho` gets a sidecar; older sidecar migrates forward, newer sidecar opens read-only and is never rewritten; setlist create/add/reorder persists and reloads; corrupted sidecar/setlist JSON surfaces an error without losing the song.
- **Romanized Hindi search integration:** fixture songs with Hindi titles and lyrics in Latin script (original, licence-free text written for the fixtures) indexed through the real store; queries with spelling variants ("pyar", "dil", "hai", "kabhie") find the expected songs, English queries are unaffected, and a rebuilt index gives identical results. A small table test of `RomanNormalizer` pairs is the only unit test here.
- **Parser corpus test:** one parameterized test over `Tests/Fixtures/*.cho`: byte-identical round trip for canonical files, idempotence for all, malformed fixtures produce diagnostics and never crash. (This is the only parser-level test; no per-rule unit tests.)
- **Determinism:** `Clock`, ID generation and the root directory are injected, so integration runs are reproducible; Core never calls `Date()` directly. File IO is real (temp dirs), not faked.
- **E2E (XCUITest):** launch with `-SegueLibraryPath <tmp dir>` and `-SegueResetState YES` (test-only launch args that bypass the open panel and wipe UserDefaults/bookmark) so each run starts from a clean baseline. Flow: create song by typing ChordPro -> appears in list -> search finds it -> create setlist -> add song -> Perform -> live view shows title and a chord -> next/exit. Also asserts the `.cho` and sidecar exist on disk with expected content.

## Lint, format, commands

Formatter/linter: **SwiftLint + SwiftFormat** (nicklockwood), both pinned in `.mise.toml`; configs `.swiftlint.yml` and `.swiftformat` at repo root; lint runs in `make check`, not as an Xcode build phase (keeps builds fast and sandbox-friendly). `Makefile` targets (thin wrappers over `tuist` / `xcodebuild` / `swift`):

| target | does |
|---|---|
| `make bootstrap` | `mise install`, `tuist install`, `tuist generate` |
| `make build` / `make build-appstore` | build each scheme |
| `make test` | Core integration suite (`swift test`) + parser corpus, then the SegueUI suite with Swift Build (`swift test --build-system swiftbuild`; its theme and diagram snapshot tests need the compiled asset catalog, so run them through `make test`, not plain `swift test`) |
| `make e2e` | XCUITest suite (Personal scheme) |
| `make lint` / `make format` | lint check / auto-format |
| `make verify-appstore` | build AppStore scheme and assert no personal-module symbols |
| `make check` | lint + build both + test + e2e + verify-appstore |

## Acceptance criteria

1. `make bootstrap && make check` passes from a clean clone with zero warnings and zero lint violations; builds are signed with the team ID.
2. Both schemes build and launch sandboxed; `verify-appstore` proves the personal package is absent from the App Store product.
3. A user can choose a library folder, create a song, find it by search, add it to a setlist, and perform it full screen; relaunching preserves everything (bookmark resolves).
4. Deleting `.segue/index.sqlite` and relaunching restores identical search results.
5. Editing a `.cho` externally and refreshing updates the list.
6. Parser round-trips every fixture byte-identically; malformed fixtures produce diagnostics, never crashes.
7. Searching a romanized Hindi spelling variant ("pyar") finds the song titled "Pyaar", and Hindi lyric text round-trips unchanged through parse, save and reload.

## Resolved decisions

See `docs/decisions.md` for the audit trail.

1. **Project generation: Tuist.** Manifests are the source of truth; generated workspace is gitignored and agents edit Swift manifests, never `.pbxproj`.
2. **SQLite layer: GRDB (FTS5).** Index schema changes drop-and-rebuild from files; no migrations.
3. **Music theory: depend on Tonic.** Phase 1's chord model wraps/extends Tonic types; Tonic is pinned from phase 0.
4. **Newer sidecar schema: open read-only + warn.** Older versions migrate forward on read; newer ones are performable but never rewritten.
5. **Lint/format: SwiftLint + SwiftFormat via mise.** Enforced in `make check`.
6. **Metadata: sidecar JSON only.** `.cho` files stay clean, portable ChordPro.
7. **Default library: `~/Music/Segue`** (any folder pickable; bookmark persists access).
8. **Signing: free Personal Team `V6BM673U35` (contact@ryandsilva.dev), bundle id `dev.ryandsilva.segue`.** Paid team later for App Store.
9. **Team ID committed** as `DEVELOPMENT_TEAM` in `Project.swift` - a team ID is not a secret.
10. **Tuist local-only** - open-source `tuist generate`, pinned in mise, no Tuist cloud account or caching.

## Verification tasks (carried from other phases)

- **Shortcut from full screen (phase 2):** in the phase 0 sandbox build, open `shortcuts://run-shortcut?name=...` while the app is full screen and record whether Shortcuts comes forward or leaves a visible window. Record the result in this doc; if it steals focus, phase 2 runs the start Shortcut from the pre-show checklist screen (before entering full screen) and the end Shortcut after leaving it.

### Result: Shortcut from full screen

**Status: open - needs one manual run by Ryan.** The question can't be answered unattended. The `shortcuts` CLI can run shortcuts but can't create them, importing a `.shortcut` file needs a click in Shortcuts, and this Mac has no shortcuts (`shortcuts list` is empty).

**Harness:** `scripts/verify-shortcut-focus.sh "<name>" [Segue.app]`. It:

1. Launches the sandboxed Debug-Personal build.
2. Puts Segue full screen through Accessibility (`AXFullScreen`).
3. Opens `shortcuts://run-shortcut?name=<name>`.
4. Samples the frontmost app (`lsappinfo`) and Shortcuts' on-screen windows (`CGWindowList`) every 0.25 s for 8 s.
5. Prints `RESULT:` and exits 0 (Segue kept focus, no Shortcuts window) or 2 (focus stolen or a window shown).

The URL is opened from the script, not from inside Segue, because phase 0 has no in-app trigger. Shortcuts' own activation behaviour is the variable under test, so this caveat doesn't change the answer. Phase 2 should still confirm with its in-app call (`NSWorkspace.open`).

**What was observed so far (2026-10-17, partial - no full screen, no real shortcut):** opening `shortcuts://run-shortcut?name=<missing>` while another app was frontmost:

- launched Shortcuts;
- showed its "All Shortcuts" main window on screen within about 1 s;
- did not become frontmost (per `lsappinfo`).

So the URL handler at least puts a visible window on screen in the error path.

**To finish (manual):**

1. In Shortcuts, create a shortcut named `Segue Focus Probe` with a single "Wait 1 second" action.
2. Grant Accessibility to your terminal (System Settings > Privacy & Security > Accessibility).
3. Run `make build`.
4. Run `scripts/verify-shortcut-focus.sh "Segue Focus Probe"`.
5. Paste the `RESULT:` line and the sample log here.
6. Watch the screen during the run too: it shows whether a Shortcuts window or progress banner appears over the full-screen Space or switches Spaces, which the frontmost-app sample alone can't tell.

## Open questions

None open.
