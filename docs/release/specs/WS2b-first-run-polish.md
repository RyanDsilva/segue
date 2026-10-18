# WS2b - First run, discovery and polish (implementation spec)

Status: **final, implementation-ready**, 2026-10-17. All open questions are resolved (see "Resolved decisions" below); one focused implementation session executes this spec standalone.

Canonical inputs (read these first; on conflict they win over this spec, and the session stops and asks):
- `docs/release/decisions.md`: R15 (accessibility pass, honest labels), R16 (What's New, TipKit, Finder integration, export archive), R19 (Welcome library), R20 (review prompt), R25-R26 (consent; WS3 owns the store and the UI pieces), R30 (copyright), R36 (Appearance option kept), R39 (design directions before building), R41 (Xcode 27.1 / Swift 6.4, arm64 only).
- `docs/release/open-questions.md`: the A answers listed below, the B defaults (B-14, B-17 to B-23, B-26) and the section 4 cross-spec resolutions (I-1 to I-7, I-10, I-11, I-13, I-14, I-16).
- `docs/release/research/08-polish-features.md` (survey, HIG rules), `03-review-risk.md` (sections 5, 7, 8: review notes, accessibility labels, consent), `04-store-listing.md` (section 4.2: screenshot pipeline), `05-landing-page.md` (section 1.5: `changelog.json`).
- `docs/brand.md` (tokens, components, motion), `docs/decisions.md` (testing, language rules: English + romanized Hindi, casual romanization, no auto-correct of lyrics).

Neighbouring workstreams (referenced, not specified here):
- **WS1**: signing, versioning (`MARKETING_VERSION = 0.5`), bundle-ID split (R11), privacy manifest, logging, the F5 accessibility-help deletion (I-13), Gig Mode defaults and the Focus-row confirmation (R18, R35), the Quick Look App ID and profile (I-14).
- **WS2a**: import (drag and drop, File > Import, the shared extension list), Delete Song, Trash for all deletes, autosave, File/Setlist/Help menus and their `AppHooks`, About, the single main `Window` with Window > Segue Library (Cmd-0), `?` shortcut overlay and status line, Show in Finder (`WorkspaceActions`), setlist undo, state restore, `SegueLinks`.
- **WS3**: services and consent: `ConsentStore`, `ConsentChoiceView`, `ConsentSheet`, `PrivacySettingsView` (the Privacy pane content).
- **WS4**: website and the changelog pipeline (`content/changelog.json` -> generated `website/changelog.json`, schema 1), the help URL and anchor table.
- **WS5**: store listing, screenshots (`UITests/AppStoreScreenshots.swift`, `make screenshots`, the `-SegueScreenshotLibrary` composite flag and the screenshot-only songs), App Store Connect entries including the accessibility labels this spec determines.

Conventions for the session:
- In Bash never use plain `cat` (it is aliased to eza and hangs); use `command cat` or the Read tool. Pass this to any subagent.
- No em dashes in docs or UI strings; use "-".
- Commit locally, signed (`git commit -S`), one commit per step below; never push. If signing fails with "failed to fill whole buffer", 1Password is locked: stop and ask Ryan to unlock.
- Never hand-edit generated files (`ColorTokens.generated.swift`, `Tokens.xcassets`, `website/changelog.json` and other generated website HTML). Edit the source and run the generator.
- Toolchain: Xcode 27.1 / Swift 6.4, arm64 only (R41).

### Resolved decisions (applied throughout this spec)

| Item | Ruling | Where applied |
|---|---|---|
| A10 | Consent is WS3's `ConsentChoiceView` (two rows: analytics, crash reports) as the last page of the Welcome flow on a new install; upgraders get WS3's standalone `ConsentSheet`; WS3 labels and copy | 4.1 |
| A12 | Review prompt after the **1st** completed gig, once per app version, plus the OS cap; no extra day gates | 4.5 |
| A13 | Welcome checkbox on for an empty library, off when the folder has songs; automatic seeding once per install, later only via "Add Welcome Songs" | 4.1, 4.2 |
| A14 | The four songs in Appendix A approved as written, after Ryan's title search | 4.2, Appendix A |
| A15 | "Remove Welcome Songs" keeps edited Welcome songs and lists them in the dialog | 4.2 |
| A16 | What's New is bundled only (never fetched); the sheet shows only for releases with `showInApp: true` | 4.3 |
| A17 | "Reset All Settings..." scope as in 4.6; no "Forget Library Folder", no "Reset to first run" | 4.6 |
| A24 / I-10 | One extension list in SegueCore (`cho`, `chopro`, `chordpro`, `pro`, `txt`); UTType tags `cho`, `chordpro`, `chopro` (`.pro` not claimed) | 4.7 |
| A30 | **Imported** type `dev.ryandsilva.segue.chordpro`, `LSHandlerRank` **Default** | 4.7 |
| A31 | Open With outside the library copies the file in through WS2a's import | 4.7 |
| A32 / I-11 | Single main `Window`; no multi-window handling | 4.1, 4.7 |
| A35 | "Rate Segue on the App Store" is WS2a's Help item (user-initiated link); not built here | 4.5 |
| A37 | The pre-show Focus row is hidden until Gig Mode Shortcuts are configured (WS1); `GigModeTip` is the discovery path | 4.4 |
| A40 | No on-stage hint; the Start Show tip says "Press ? on stage", and WS2a's stage status line ends "? keys" | 4.4 |
| A41 / R39 | 2-3 design directions each for the Welcome sheet, What's New sheet and `.cho` document icon, picked by Ryan before building them | 6 (step 3) |
| A42 / R36 | **Keep** the Appearance pane: Match System (default) / Light / Dark | 4.6 |
| A43 | Control borders reach 3:1 only under Increase Contrast, provided Apple's "Sufficient Contrast" criteria accept that route (verified first); otherwise also in the default look | 4.9.1 |
| A44 | New `indicatorOff` token (#8A8A92 / #66676E) and `played` dark #8E8E96, shown to Ryan as a before/after render first | 4.9.1, 6 (step 1) |
| A45 | No main-window text scaling in 0.5 | 4.9.4 |
| A48 | Screenshot-only original songs exist; WS5 owns their content and location; they reuse this spec's seeder | 4.2 |
| B-17 / I-5 | WS2a owns the Help list and reserves hooks; WS2b fills `AppHooks.showWelcome`, `AppHooks.showWhatsNew` and the File export-archive hook | 4.1, 4.3, 4.8 |
| B-18 | Welcome content stays in the SegueUI resource bundle (Personal carries it too) | 4.2 |
| B-19 | No Larger Text claim; re-check in App Store Connect | 4.9.4 |
| B-20 | Quick Look: view-based preview reusing the app's renderer and fonts | 4.7 |
| B-21 | Sequencing per open-questions section 5 | 6 |
| B-22 / I-1 | WS3's `ConsentStore` is the single consent store and writer | 3, 4.1, 4.6 |
| B-23 | Archive includes `songs/`, `setlists/`, `shows/`, `timings/`; excludes `.segue/`; no restore in 0.5 | 4.8 |
| B-26 / I-2 | The app bundles the generated `website/changelog.json`; WS4's schema 1 | 4.3 |
| I-3 | No remote changelog fetch anywhere (WS2a drops `changelogFeed`) | 4.3 |
| I-4 | WS2b owns the seeder and `-SegueSeedWelcome`; WS5's `-SegueScreenshotLibrary YES` composes it | 4.2 |
| I-6 | Settings host in a new `SegueSettingsView.swift`; "Show Library in Finder" only in General; Privacy = WS3's view as-is | 4.6 |
| I-7 | First-run order: library, Welcome songs, consent | 4.1 |
| I-13 | WS1 deletes the F5 accessibility-help calls; WS2b only verifies | 4.9.1 |
| I-14 | WS1 creates the Quick Look App ID and profile "Segue Mac App Store QuickLook" and maps it in ExportOptions | 4.7 |
| I-16 | Changelog `help` paths come only from WS4's URL and anchor table | 4.3 |

---

## 1. Goal

A first-time user (and an App Reviewer on a clean Mac) gets from launch to a library full of playable, original songs and a ready setlist in under a minute, with honest, equal-weight choices for analytics and crash reports; a returning user learns about new features through a short What's New sheet (when the release author asks for one) and a few contextual tips; the app looks and behaves like a well-made Mac app in Finder (file type, icon, Open With, Quick Look) and in Settings; the library can be exported as one zip; and every App Store accessibility label Segue claims is earned and verified.

Out of scope: consent storage, consent UI pieces and vendor wiring (WS3; this spec hosts WS3's views), the Help/File/Setlist menus themselves (WS2a; this spec fills their hooks), screenshot capture and composition and the screenshot-only songs (WS5), the website and the changelog generator (WS4), archive restore/import, a bundled Help Book, localisation, main-window text scaling, a remote changelog fetch.

---

## 2. Current state (code evidence, 2026-10-17)

- First run: `LibraryChooserView` (`Packages/SegueUI/Sources/SegueUI/SegueRootView.swift:37-114`) with "Create Library in Music…" / "Choose Existing Folder…"; `AppModel.start()` / `createLibrary()` / `chooseLibrary()` (`Packages/SegueUI/Sources/SegueUI/App/AppModel.swift`); bookmark in `LibraryLocation` (`App/LibraryLocation.swift`, key `libraryFolderBookmark`). No sample content, no onboarding, no consent.
- Library layout: `Packages/SegueCore/Sources/Support/LibraryRoot.swift` (`songs/<slug>.cho` + `<slug>.segue.json`, `setlists/<slug>.setlist.json`, `shows/`, `timings/`, `.segue/index.sqlite`). Only `.cho` is scanned.
- Song creation: `LibraryStore.createSong(source:)` (unique slug, new sidecar). Sidecar metadata and live prefs: internal `LibraryStore.updateMetadata(id:_:)` and `updateLivePrefs(id:_:)` (`Library/LibraryStore+Phase2.swift:108`, `:127`). `LivePrefs.columns` pins a column count (`Library/Sidecar.swift:87`).
- Setlists: `SetlistStore.create(name:)`, `insertSongs`, `updateEntry`, `updateDetails` (`Setlists/SetlistStore.swift`); `SetlistOverrides.transpose/capo`, `SetlistEntry.note`, `Setlist.targetDuration`.
- Settings: one "Live" tab (`Settings/LiveSettingsView.swift`, which also declares `SegueSettingsView` today): minimum lyric size, default columns, Gig Mode Shortcuts, pre-show checklist rows. Stored by `LiveSettingsStore` (keys `live.settings`, `live.rehearsalShortcuts`). The Library menu has Refresh, Rebuild Index, Choose Library Folder… (`SegueRootView.swift`, `SegueCommands`).
- Show end: `AppModel.finishRun(_:)` (`App/AppModel+Shows.swift`) ends the run, closes the stage, runs the end Shortcut, queues reorder reviews; `ShowKind.gig/.rehearsal`, `ShowClosure.ended/.stale` (`Shows/ShowRecord.swift`).
- Test hooks: Debug-only `LaunchOptions` (`App/Sources/LaunchOptions.swift`), test defaults suite `<bundle>.uitest`, `UITesting.isActive` (`-SegueUITesting YES`). E2E runs only on `Segue-Personal`/`Debug-Personal` (Project.swift `personalScheme`); `/private/tmp/segue-e2e/` sandbox exception there only.
- Info.plist: no `CFBundleDocumentTypes`, no UTType declarations (`Project.swift` `appTarget`). Version literal `0.1.0` (WS1 moves it to `MARKETING_VERSION = 0.5`).
- Tokens (`design/tokens.json`, generated by `scripts/gen-tokens.swift`, `make tokens`): `played` #55555C/#55555C, `lineStrong` #B9B9C0/#2A2B2F. Stage is forced dark (`Live/StageWindowController.swift:57`). Progress dots in `Live/StageChrome.swift:53-82`: played = `played`, pending = `lineStrong`, skipped = `played` ring, current = 20px `cue` pill; `accessibilityRepresentation` already reads the position text.
- Accessibility: ~80 a11y modifiers across ~35 files; visual-editor canvas exposes chord pills and slots (`Editor/CanvasViews.swift:105-142`, test `EditorCanvasAccessibilityTests`); Reduce Motion read only in `Live/LiveView.swift`. 03 F5 (`SourceEditorController.swift:85`, `VisualEditorController.swift:65` setting a machine report as accessibility help) is fixed by WS1 (I-13).
- No StoreKit, TipKit, UTType or What's New code anywhere.

Assumed landed before this session's app-shell steps (section 6): WS1 steps 1-5, WS2a (including `AppHooks.showWelcome`, `AppHooks.showWhatsNew`, the export-archive hook, the Help slots, the single `Window`, `WorkspaceActions`, the Trash API, the import flow and its extension list), WS3 step 3 (`ConsentStore`, `ConsentChoiceView`, `ConsentSheet`, `PrivacySettingsView`, Privacy tab), WS4's changelog pipeline (generated `website/changelog.json`).

---

## 3. Shared preferences (new, all UserDefaults in the launch's defaults suite)

All keys are written only through the stores below (one writer per key). Test runs use the `.uitest` suite like every other key, so `-SegueResetState` wipes them.

| Key | Type | Writer | Meaning |
|---|---|---|---|
| `onboarding.completed` | Bool | `OnboardingStore` | The first-run flow finished (all applicable pages answered). |
| `welcome.decision` | String `added` / `declined` | `OnboardingStore` | Answer to the Welcome-songs page; absent = not asked yet. |
| `welcome.seeded` | JSON `{ "seededAt": ISO8601, "libraryPath": String, "songIDs": [ULID], "setlistID": ULID? }` | `OnboardingStore` | The last seed. Used by "Remove Welcome Songs" to find the demo setlist. |
| `whatsNew.lastSeenVersion` | String | `WhatsNewStore` | Highest version whose notes the user has seen (or been silently credited with). |
| `review.completedGigs` | Int | `ReviewPromptStore` | Gigs the user ended in-session (`ShowKind.gig`, `closure == .ended`). |
| `review.lastRequestedVersion` | String | `ReviewPromptStore` | App version for which `requestReview` was last called. |
| `settings.selectedPane` | String | `SegueSettingsView` | Restores the last Settings pane (HIG). |
| `appearance.mode` | String `system` / `light` / `dark`, absent = `system` | `AppearanceStore` | R36 Appearance option. |
| `tips.resetPending` | Bool | Settings > Data | TipKit datastore reset on next launch (TipKit requires reset before `Tips.configure`). |

**Consent is not stored here.** WS3's `ConsentStore` (SegueUI `Services/`, key `privacy.consent`, `ConsentState { analytics, crashReports: Decision (.undecided / .granted(Date) / .declined(Date)), version }`) is the single store and the single writer (I-1, B-22). WS2b reads `ConsentStore.needsPrompt` and embeds WS3's `ConsentChoiceView(store:source: .welcome)`; it never writes consent itself. The `source` WS3 records with its `Privacy.analyticsEnabled` event is `welcome` for the Welcome flow (it replaces the earlier `via` field).

---

## 4. Feature behaviour

### 4.1 Welcome sheet (first run)

The Welcome flow is driven by `OnboardingModel` (`@MainActor @Observable`, SegueUI `Onboarding/`), which exposes `isPresentingWelcome: Bool` for WS3 (I-1, WS3 4.4): while it is true, WS3's `SegueRootView` rule never presents `ConsentSheet`.

**When it shows**
- Full flow (pages 1-3): `LibraryLocation.resolveStored() == .notChosen` and `onboarding.completed` is false. That is a genuinely new install. Page 3 is included only if `ConsentStore.needsPrompt` is true at the moment page 2 is answered (it normally is); otherwise the flow ends after page 2.
- Resume flow: the library resolved but `onboarding.completed` is false (the user quit mid-flow). Show only the unanswered pages: page 2 if `welcome.decision` is absent, page 3 if `ConsentStore.needsPrompt`. If neither applies, set `onboarding.completed = true` silently.
- Upgraders (a library bookmark already exists from a pre-WS2b build: Ryan's own installs, TestFlight upgrades) with `onboarding.completed` absent: WS2b shows nothing. It silently sets `onboarding.completed = true` and `welcome.decision = declined`; never seeds. If their consent is undecided, WS3's standalone `ConsentSheet` handles it (A10), because `isPresentingWelcome` stays false.
- `accessLost` and `openFailed` keep today's plain chooser with its existing messages; they never trigger onboarding.
- Test runs: with `-SegueLibraryPath` and no `-SegueOnboarding`, onboarding is treated as done (and WS3's own test flags govern consent, so the existing E2E suite is untouched). `-SegueOnboarding fresh` forces the full flow for the override library, starting at page 2 (page 1 is covered by its own test, section 7). `-SegueOnboarding done` marks it done.

**Design direction gate (R39, A41).** The visual design of this sheet is built only after Ryan picks one of 2-3 directions (section 6, step 3). The behaviour, copy, sizes and accessibility rules below are fixed regardless of direction; the direction decides layout, imagery, card treatment and typographic hierarchy within `brand.md`.

**Presentation.** A sheet on the main window, 560 pt wide, brand ground, Schibsted Grotesk, a small "Step n of m" label (m = number of pages in this flow). Behind page 1 the window shows the existing wordmark ground (today's chooser visuals without its buttons); behind pages 2-3 the opened library is visible. The sheet cannot be dismissed with Esc or a click outside (`interactiveDismissDisabled`); Cmd-Q still quits. Page changes cross-fade in 150 ms or less, and not at all with Reduce Motion (brand.md section 8). If the user closes the main window (Cmd-W) the sheet goes with it; Window > Segue Library (Cmd-0, WS2a) brings back the single main window and the sheet re-presents from persisted state.

**Page 1 - Library.** Title "Where should your songs live?". Body: "Segue keeps every song as a plain ChordPro file in a folder you choose. We suggest a Segue folder in Music." Buttons: "Create Library in Music…" (primary, default) and "Choose Existing Folder…" (secondary), calling the existing `AppModel.createLibrary()` / `chooseLibrary()`. Footer: "Songs are plain ChordPro files you can open in any editor."
- Panel cancelled: stay on page 1, nothing changes.
- Open fails: show the `openFailed` message inline under the buttons (same text as today) and stay on page 1.
- Success: the library opens (`AppModel.state == .ready`) and the sheet advances to page 2.

**Page 2 - Welcome songs.** Title "Welcome to Segue". Three compact cards in one row (icon + one line each): "Write or drop in songs" (ChordPro or plain text), "Build a setlist" (drag songs, see the running time), "Play on stage" (full screen, keys and pedals; press ? for every key). Below them a checkbox: "Add 4 songs and a setlist written for Segue (you can delete them anytime)". Button: "Continue" (default).
- Checkbox default (A13): **on** when the library has no songs (`songs/` absent or no `.cho`), **off** when it has any (never surprise someone who pointed Segue at their real library).
- Continue with the box ticked runs the seed (section 4.2) with an inline progress indicator, then records `welcome.decision = added` and advances. Unticked records `declined` and advances. If page 3 is not part of this flow, Continue finishes the flow (see "Finishing").
- Seed failure (read-only folder, disk full): inline message "Segue could not add the Welcome songs (reason)." with "Try Again" and "Skip". Songs already written stay (they carry the Welcome tag and can be removed later); a retry is idempotent (section 4.2).

**Page 3 - Help improve Segue? (R25, R26, A10).** The page hosts WS3's `ConsentChoiceView(store: consentStore, source: .welcome)` unchanged: WS3 owns its title, row copy, labels, "What's sent" disclosures and the "Privacy Policy" link. As specified by WS3 it shows two rows, each with two equal-weight buttons (same style and size, neither default, neither preselected, neither in accent colour):
- "Share usage analytics": **Don't Share** / **Share**
- "Send crash reports": **Don't Send** / **Send**

WS2b adds only the page chrome: the "Step n of m" label and a **Continue** button, enabled when `ConsentChoiceView.isComplete` (both rows answered). Continue is not the default button until it is enabled, and Return/Esc never answer a row. Links open in the default browser (never a web view; 03 F16).

**Finishing.** When the last page is answered (Continue on page 3, or on page 2 when page 3 is skipped): set `onboarding.completed = true`, set `whatsNew.lastSeenVersion` to the running version (so a fresh install never sees What's New), set `isPresentingWelcome = false`, close the sheet, then run any queued Open With URLs (section 4.7). If the app quits before Continue on page 3, consent stays undecided (nothing sent) and the resume flow shows page 3 next launch.

**Re-opening.** WS2b fills WS2a's `AppHooks.showWelcome` (Help > "Welcome to Segue...", the slot WS2a reserves per B-17/I-5); it never edits `SegueCommands`. It opens page 2 standalone in "revisit" mode: the cards plus, when no Welcome-tagged song is in the open library, an "Add Welcome Songs" button (seed), otherwise the line "The Welcome songs are in your library (tag: Welcome)." Revisit mode never shows the consent page (consent changes live in Settings > Privacy) and is dismissable with Esc or "Done". Disabled while performing.

**Ordering with other launch UI.** One priority function in `AppModel`, highest first: crash-resume prompt (`pendingResume`), pre-show checklist, reorder reviews, start-failure alert, then the Welcome flow (or WS3's `ConsentSheet` when the Welcome flow is not running), then What's New. Lower items wait until higher ones are gone. Never more than one of Welcome / consent sheet / What's New per launch.

### 4.2 The Welcome library

**Content rules (R19, A14, 03 section 5.2.1, decisions.md "Language").** Four songs written for Segue (full text in Appendix A, approved as written subject to Ryan's title search, section 10), one in romanized Hindi using casual romanization without diacritics, all lyrics clean (4+ age rating), no real song titles or lines (in particular never "tum hi ho" or any film-song title), artist "Segue Originals" on every song. Lyrics are ASCII-only (no Devanagari, no smart quotes). The existing E2E fixture titles ("Harbor Lights", "Paper Boats", "Dil Ki Raah", ...) are test-only and are not reused, because some of them collide with real song titles.

**What the four songs demonstrate.**

| Song | Key / capo | Tempo, time, length | Shows off |
|---|---|---|---|
| Soundcheck at Seven | G shapes, capo 2 (concert A) | 96, 4/4, 3:20 | Capo, verse/chorus/bridge, collapsed repeat choruses, a cue, Pro mark |
| Kitaabon Wali Gali | Am | 84, 4/4, 4:05 | Romanized Hindi, spelling-tolerant search, a `{comment}`, a setlist transpose override (-2), Ready mark |
| Kettle On, Lights Low | G shapes, capo 3 (concert Bb) | 72, 3/4, 3:05 | Waltz, `{time}`, `{define}` (custom Cadd9 shape), Em7/D/F#/Am7, intro chord line, Ready mark |
| Ferry Lights Over Calder Bay | D | 120, 4/4, 4:40 | The **2-column** song: long form with intro, two identical pre-choruses (collapse demo), bridge, outro, slash chords and Asus4; sidecar pins `live.columns = 2`; Learning mark |

**Demo setlist "Welcome Set"**: Soundcheck at Seven, Kitaabon Wali Gali (override `transpose: -2`, so the key chip shows Gm), Kettle On, Lights Low (note "Brushes, start soft"), Ferry Lights Over Calder Bay (note "Closer: big finish"); `targetDuration` 1200 s (20:00), so the builder shows 15:10 of 20:00. No venue or date (a date would go stale).

**Bundling (B-18).** The content ships in the SegueUI resource bundle, the same mechanism as the fonts and licence texts, so both app targets (and therefore the App Store target) carry it and `swift test` can load it with `Bundle.module`:
- `Packages/SegueUI/Sources/SegueUI/App/WelcomeLibrary/manifest.json`
- `Packages/SegueUI/Sources/SegueUI/App/WelcomeLibrary/soundcheck-at-seven.cho`, `kitaabon-wali-gali.cho`, `kettle-on-lights-low.cho`, `ferry-lights-over-calder-bay.cho`
- `Packages/SegueUI/Package.swift`: add `.copy("App/WelcomeLibrary")` to the SegueUI resources.

`manifest.json` (schema 1; the seeder rejects other majors). `tag` is the seed's identity tag; the optional `setlist` block may be absent.

```json
{
  "schema": 1,
  "tag": "Welcome",
  "songs": [
    { "file": "soundcheck-at-seven.cho", "tags": ["Welcome", "folk"], "proficiency": "pro",
      "notes": "Count in 1-2-3-4. Brushes on the snare until the first chorus.",
      "cues": [ { "section": "Chorus", "occurrence": 3, "text": "Big stop on the last line" } ] },
    { "file": "kitaabon-wali-gali.cho", "tags": ["Welcome", "hindi"], "proficiency": "ready" },
    { "file": "kettle-on-lights-low.cho", "tags": ["Welcome", "waltz"], "proficiency": "ready" },
    { "file": "ferry-lights-over-calder-bay.cho", "tags": ["Welcome", "upbeat"], "proficiency": "learning",
      "live": { "columns": 2 } }
  ],
  "setlist": {
    "name": "Welcome Set",
    "targetDuration": 1200,
    "entries": [
      { "song": "soundcheck-at-seven.cho" },
      { "song": "kitaabon-wali-gali.cho", "overrides": { "transpose": -2 } },
      { "song": "kettle-on-lights-low.cho", "note": "Brushes, start soft" },
      { "song": "ferry-lights-over-calder-bay.cho", "note": "Closer: big finish" }
    ]
  }
}
```

**Seeding (once, idempotent, deletable).**
- Core: `Packages/SegueCore/Sources/Library/WelcomeSeed.swift` (manifest model, `Codable`) and `LibraryStore+Welcome.swift` with `func seedSongs(fromManifestFolder folder: URL) throws -> [SeededSong]`. The function is generic over any schema-1 manifest folder (the Welcome folder, or WS5's screenshot-only folder). For each manifest song: if a song carrying the manifest's `tag` with the same title and byte-identical source already exists, reuse it (idempotency); otherwise `createSong(source:)`, then `updateMetadata` (tags, proficiency, notes, cues) and `updateLivePrefs` (columns) in the same module (they are internal today).
- Orchestration: `Packages/SegueUI/Sources/SegueUI/App/LibrarySession+Welcome.swift` seeds the songs, then, if the manifest has a `setlist`, creates it through the public `SetlistStore` API (`create`, `insertSongs`, `updateEntry`, `updateDetails`), unless a setlist with the recorded `setlistID` (or with the manifest's name whose entries are all songs carrying the manifest's tag) already exists; then reloads the library and setlists. Only the Welcome seed writes `welcome.seeded`.
- "Seeded once" (A13): automatic seeding happens only from the onboarding page 2 checkbox, once per install. After that only the explicit "Add Welcome Songs" actions (Help > Welcome to Segue..., Settings > Data) seed, and each is idempotent. A second, new library later gets them only by "Add Welcome Songs".
- Deleting (A15): each song is deletable like any song (WS2a Delete Song, to the Trash). Settings > Data > "Remove Welcome Songs…" finds songs tagged "Welcome" whose `.cho` is byte-identical to the bundled original plus the recorded demo setlist, shows a confirmation ("Move 4 Welcome songs and the Welcome Set setlist to the Trash?"), and trashes them through WS2a's Trash API. Edited Welcome songs are kept and listed in the dialog ("2 edited songs are kept: <titles>"). Setlists that reference a removed song show it as missing (existing behaviour).

**Screenshot and test reuse (WS5, I-4, A48).**
- WS2b owns the seeder and the Debug-only flag `-SegueSeedWelcome YES` (inside `#if DEBUG`, B-7): after the library opens and before the first frame settles, run the Welcome seed. It never wipes anything.
  - With `-SegueLibraryPath <dir>` (Debug-Personal, `/private/tmp/segue-e2e/`), it seeds that folder: this is what WS2b's own E2E tests use.
  - Without a library path, it seeds and opens the fixed in-container folder `Library/Application Support/Segue-Screenshots/Library`, defined once as `LaunchOptions.screenshotLibraryFolder` (WS2b adds the constant). No sandbox exception, no entitlement drift, and the user's real library bookmark is never touched.
- WS5 owns the composite flag `-SegueScreenshotLibrary YES` (defined in `LaunchOptions` by WS5, `#if DEBUG`). It wipes `LaunchOptions.screenshotLibraryFolder`, then applies `-SegueSeedWelcome YES`, then seeds WS5's screenshot-only songs by calling the same `seedSongs(fromManifestFolder:)` with WS5's own schema-1 manifest folder (content, tag, location and approval are WS5's, A48; they never ship), plus `-SegueOnboarding done`, `-SegueTips hide`, consent declined through WS3's `ConsentStore`, and no What's New or review prompt. WS2b's job is only that the seeder, the folder constant and the three WS2b flags it composes work as specified here.
- Deterministic content: fixed text, fixed setlist order and durations. IDs are generated, so tests and screenshots address songs by title, never by ID.

### 4.3 What's New sheet

**Source of truth (I-2, B-26).** WS4 owns the changelog: `content/changelog.json` is the hand-edited original; WS4's `gen-site.swift` validates it and writes the generated `website/changelog.json` (drafts removed). The app bundles that generated file: `Project.swift` adds `"website/changelog.json"` to both app targets' `resources`, so it lands in `Bundle.main` with no copy step and no second generator output. WS2b never creates or edits either file. If `website/changelog.json` does not exist when step 8 starts (WS4 not landed), stop and ask.

**No network (A16, I-3).** The app never fetches `changelog.json`; the bundled copy is the only source. There is no `SegueLinks.changelogFeed` (WS2a drops it).

**Schema 1 (WS4's contract, as the app reads it).**

```json
{
  "schema": 1,
  "releases": [
    {
      "version": "0.6",
      "date": "2027-01-15",
      "title": "Rehearsal notes and faster search",
      "summary": "Notes you take in rehearsal now follow the song onto the stage.",
      "showInApp": true,
      "highlights": [
        { "kind": "new", "text": "Rehearsal notes appear on stage under the song title.", "help": "/help/live" },
        { "kind": "improved", "text": "Deleted songs and setlists go to the Trash.", "help": "/help#trash" },
        { "kind": "fixed", "text": "The pre-show checklist only ticks Focus when the Shortcut really ran." }
      ]
    }
  ]
}
```

App-side rules:
- `schema`: integer major. The app ignores a file whose major it does not know (no sheet, one log line) and never crashes on it.
- `releases`: newest first. `version` is the marketing version (`MARKETING_VERSION`, e.g. `0.5`); comparison is numeric per component with missing components as 0, so `0.5` == `0.5.0`, `0.10` > `0.9.1`.
- `date`: `YYYY-MM-DD`. `title`: 1-60 characters. `summary`: optional, up to 200 characters, shown under the title. `showInApp`: bool, the author's decision whether this release gets the automatic sheet (0.5 is `false`).
- `highlights`: 1-8 items; `kind` is exactly `new`, `improved` or `fixed`; `text` is one plain sentence, 1-120 characters (I-2 tightens WS4's 140 so the sheet wraps to at most two lines), no Markdown, HTML or em dashes; `help` optional, a site-relative path from WS4's URL and anchor table (I-16), which the app turns into `SegueLinks.site` + `help` for a "Learn More" link.
- `draft` never appears in the generated file; if it does, a release with `draft: true` is skipped.
- Unknown keys within schema 1 are ignored by the app.
- The same `highlights` text is what WS5 pastes into App Store "What's New".

**Design direction gate (R39, A41).** The sheet's visual design is built only after Ryan picks one of 2-3 directions (section 6, step 3). The rules here are fixed regardless of direction.

**When the sheet shows.** On launch, after the library is ready and nothing of higher priority is pending (section 4.1 ordering), when all hold:
- `whatsNew.lastSeenVersion` exists and is lower than the running version. Absent means either a fresh install (onboarding credits the running version silently) or an upgrader from a pre-WS2b build: credit them with the newest release strictly lower than the running version, so the current release's notes show once if its `showInApp` is true;
- at least one release in (lastSeen, current] has `showInApp: true` (A16); otherwise `lastSeenVersion` is set to the running version silently;
- not performing, not starting a show, no Welcome flow or consent sheet this launch.

**Content.** Title "What's New in Segue <version>". The releases in range whose `showInApp` is true, newest first, each with its title, date and summary; each highlight is a row with a text badge "New" / "Improved" / "Fixed" (a word, not only a colour) and its text, plus "Learn More" when `help` is present. At most 8 rows in total; overflow shows "and N more changes" linking to `SegueLinks.changelog` (`/changelog`). Footer: "All Release Notes" link (default browser) and "Continue" (default button). Dismissing (Continue, Esc, or closing) sets `lastSeenVersion` to the running version.

**Reopening.** WS2b fills WS2a's `AppHooks.showWhatsNew` (Help > "What's New in Segue"), replacing WS2a's development fallback (B-14). It opens the sheet for the running version's entry (or the newest entry if the running version has none) and the two previous releases, regardless of `showInApp`. Never while performing.

**Edge cases.** File missing or unreadable: no sheet, log once; the Help item falls back to opening `SegueLinks.changelog`. Running version newer than every entry: no automatic sheet, Help item shows the newest entry; the release check in section 7 catches a missing entry before upload. Downgrade (lastSeen > current): no sheet, `lastSeenVersion` untouched. No releases at all (the 0.5 entry is still `draft` in `content/`): no sheet, the Help item opens `SegueLinks.changelog`.

### 4.4 TipKit tips

Configure once at launch: `Tips.configure([.displayFrequency(.daily), .datastoreLocation(.applicationDefault)])`. With `tips.resetPending` set, call `Tips.resetDatastore()` first and clear the flag. Test runs hide all tips (`Tips.hideAllTipsForTesting()`) unless `-SegueTips show` (which calls `showAllTipsForTesting()`); `-SegueTips hide` forces hiding; `-SegueResetState` also resets the datastore.

Global rules shared by every tip (TipKit `@Parameter`s set by `AppModel`): `isPerforming == false`, `isOnboarding == false` (Welcome flow or consent sheet up), `isWhatsNewShowing == false`. Tips live only in main-window views; **no tip is ever placed in the stage window or the pre-show checklist**, and there is no on-stage hint of any kind (A40).

| Tip | Anchor and style | Message (1-2 sentences) | Eligible when | Invalidated when |
|---|---|---|---|---|
| `SearchAnyLineTip` | Popover on the library search field | "Search by any line you remember. Spellings like pyar and pyaar find the same song." | Library has 5 or more songs (parameter) and the `searched` event has 0 donations | First search (donate `searched`) |
| `TransposeViewTip` | Popover on the detail pane transpose control | "Change the key or capo for this view without touching the file." | `songViewed` donated 3 or more times | Transpose or capo changed in the detail pane |
| `MoveChordTip` | Inline `TipView` above the visual editor canvas | "Drag a chord onto another syllable to move it." | Visual editor opened (`visualEditorOpened` donated at least once) | First chord drag in the canvas |
| `StartShowTip` | Popover on the builder's Start Show button | "Start Show goes full screen and dark. Press ? on stage to see every key." | The open setlist has at least 1 entry and `showStarted` has 0 donations | First show or rehearsal started |
| `GigModeTip` | Inline `TipView` at the top of the setlist builder, action "Open Settings" (opens Settings > Live) | "Silence notifications while you play: set up Gig Mode Shortcuts in Settings > Live." | `showStarted` donated at least once (any show or rehearsal, so it follows `StartShowTip` and can appear before the first real gig) and no Gig Mode Shortcut is configured (WS1's `LiveSettings` state, R18) | A Gig Mode Shortcut is configured |

`GigModeTip` is the only discovery path for Gig Mode, because the pre-show Focus row is hidden until the Shortcuts are configured (A37, WS1). Its text does not describe how the Focus row gets confirmed (that mechanism is WS1's, R35); Settings > Live explains it.

The daily display frequency means a user never sees more than one tip per day. Tips are accessible by default (TipKit); their text is checked in the VoiceOver pass.

### 4.5 Review prompt (R20, A12)

- Use SwiftUI's `@Environment(\.requestReview)` (StoreKit `RequestReviewAction`), called from a view in the main window, never from a button (HIG: the API may show nothing). The user-initiated "Rate Segue on the App Store" link is WS2a's Help item (A35), not built here.
- Counting: in `AppModel.finishRun(_:)`, when `live.kind == .gig` and `controller.end()` succeeded, increment `review.completedGigs`. Rehearsals never count. Gigs closed by "End Show" in the resume prompt count too; stale auto-closed gigs (`closure == .stale`) do not.
- Trigger: only from `finishRun` (so never at launch). Set `AppModel.reviewPromptPending = true` when all hold: `completedGigs >= 1` (the 1st completed gig, A12), `review.lastRequestedVersion != current version` (once per app version), `quitsAfterEnding == false`. No other gates: no days-since-install, no days-between-prompts (A12; the OS cap of 3 per 365 days applies).
- Firing: `MainView` observes `reviewPromptPending`. It fires only when the stage window is closed and `app.live == nil`, no show is starting, `pendingResume == nil`, `preShow == nil`, `pendingReorderReviews` is empty (the end-of-show flow is done), no other sheet or alert is up, no error banner, and the main window has been key for 3 continuous seconds. It then calls the injected `ReviewRequester`, writes `lastRequestedVersion`, and clears the flag. If a show starts first, the flag is cleared (re-armed by the next completed gig, still once per version).
- **Never in live mode**: the check runs only in the main window, and both `app.live == nil` and the stage window being closed are required at fire time.
- `ReviewRequester` port: the real one wraps the environment action; Debug test runs with `-SegueReviewLog <file>` append one line per request instead. The OS caps prompts and TestFlight shows nothing, so the E2E log is the oracle.

### 4.6 Settings restructure (R36, I-6)

`SegueSettingsView` moves to a new file `Settings/SegueSettingsView.swift` and becomes a `TabView(selection:)` with five panes, 560 pt wide, the window title following the pane (SwiftUI default), the last pane restored from `settings.selectedPane`. `LiveSettingsView.swift` keeps only the Live pane and is left to WS1's text changes. Everything that exists today keeps its behaviour and identifiers. If WS3 has already added its Privacy tab to the old host, move it into the new host unchanged.

| Pane | Contents | Source |
|---|---|---|
| **General** (`gearshape`) | Library folder: abbreviated path (`~/Music/Segue`), "Change…" (`AppModel.chooseLibrary()`, disabled while performing with the existing help text), "Show Library in Finder" (WS2a's `WorkspaceActions` reveal; the only place it appears in Settings). Note: "Songs are plain ChordPro files in this folder. Back it up like any folder; Time Machine works." | Moves "Choose Library Folder…" into a pane (the Library menu item stays). |
| **Appearance** (`circle.lefthalf.filled`) | One picker "Appearance": **Match System** (default) / Light / Dark, bound to `appearance.mode` via `AppearanceStore`. Applies to the main window, Settings and other non-stage windows (sets `NSApp.appearance`: `nil` / `.aqua` / `.darkAqua`); takes effect immediately. The line "The stage is always dark." Nothing else; no accessibility duplicates. | New (R36) |
| **Live** (`music.mic`) | Unchanged: minimum lyric size, default columns, Gig Mode Shortcuts (WS1 owns the text and defaults per R18/R35), "Also run them for rehearsals", pre-show checklist rows. | Existing `LiveSettingsView` |
| **Privacy** (`hand.raised`) | WS3's `PrivacySettingsView` hosted as-is: WS3's toggles "Share usage analytics" and "Send crash reports" bound to `ConsentStore`, its disclosures and captions, links to the Privacy Policy and `/privacy#usage-statistics`, no Terms link. WS2b adds nothing to it. | WS3 |
| **Data** (`externaldrive`) | "Export Library Archive…" (section 4.8); "Rebuild Index" (same action as the menu); Welcome songs: "Add Welcome Songs" / "Remove Welcome Songs…" (section 4.2); Reset: "Reset Tips" (sets `tips.resetPending`, message "Tips will show again after you restart Segue.") and "Reset All Settings…" (A17, below). | New, partly existing actions |

**"Reset All Settings…" scope (A17).** Resets: Live settings (`live.settings`, `live.rehearsalShortcuts`) to defaults, `appearance.mode` to Match System, `settings.selectedPane`, and the tips (sets `tips.resetPending`). Keeps: the Privacy decisions (consent is changed only in the Privacy pane), the library choice and the library files, onboarding state, What's New and review counters, the shape library and key bindings. The confirmation dialog lists exactly both lists. There is no "Forget Library Folder" (Library > Choose Library Folder covers it) and no "Reset to first run" (`-SegueResetState` is the test tool).

Every library-affecting control is disabled while performing (`app.isPerforming`) or while no library is open. No control is added that does nothing (no placeholder toggles).

### 4.7 Finder integration

**Extension list (A24, I-10).** One list in SegueCore, owned with WS2a's import (`cho`, `chopro`, `chordpro`, `pro`, `txt`), is used by import, the UTType declaration (a declared subset) and Open With routing. Never a second hard-coded list.

**UTType (A30: imported, rank Default).** In both app targets' Info.plist (`Project.swift`):
- `UTImportedTypeDeclarations`: identifier `dev.ryandsilva.segue.chordpro`, description "ChordPro Song", conforms to `public.plain-text` (so TextEdit and other editors still open it), tags `public.filename-extension` = `cho`, `chordpro`, `chopro` (`.pro` is not claimed: too generic); `public.mime-type` = `text/x-chordpro`. Imported, not exported, because Segue does not own the ChordPro format: if another installed app exports a type for these extensions, its declaration wins and Segue still opens the files.
- `CFBundleDocumentTypes`: one entry for `dev.ryandsilva.segue.chordpro`, `CFBundleTypeRole` = `Editor`, `LSHandlerRank` = `Default` (Segue becomes the default app for `.cho` on Macs where no other app claims it, without fighting other ChordPro apps), with the document icon below.

**Document icon.** **Design direction gate (R39, A41):** the icon artwork is built only after Ryan picks one of 2-3 directions (section 6, step 3). Mechanism: preferred, the macOS 13+ composed document icon (`UTTypeIcons` / document-type icon with a badge image from the asset catalog and text "CHO"); fallback, a generated `.icns` from `scripts/gen-icon.swift` (new `--document` output in `design/icon/`). Whether the composed form renders on macOS 26 with an imported declaration is UNVERIFIED: verify both in Finder (icon view at 16/32/128/512, list view, light and dark) and keep the one that renders.

**Open With.** `SegueAppDelegate` gains `application(_:open:)` (the app has a single main `Window`, not a `DocumentGroup`):
- File inside the open library's `songs/`: select that song in the library (switching the sidebar to Library) and bring the main window forward (reopening it via `openWindow(id: "segue.main")` if closed).
- File elsewhere (A31): hand the URLs to WS2a's import flow (copy into the library, with its confirmation and duplicate handling; `.chordpro`/`.chopro` are imported as `.cho` by WS2a).
- No library yet (first run): queue the URLs and run the import when the Welcome flow finishes (section 4.1).
- While performing: queue until the show ends; never interrupt the stage.
- Extension not in the list, or unreadable file: the error banner via `UserMessage` ("Segue can only open ChordPro song files.").

**Quick Look preview extension (sandboxed, Tuist).**
- Targets: one extension per app flavor, because an extension's bundle ID must extend its host's and WS1 splits the hosts (R11): `SegueQuickLook` (`dev.ryandsilva.segue.quicklook`, embedded in `SegueAppStore`) and `SegueQuickLookPersonal` (`dev.ryandsilva.segue.personal.quicklook`, embedded in `Segue`). Generate both from one `quickLookTarget(hostName:hostBundleID:)` helper in `Project.swift`; product `.appExtension`; sources `Extensions/QuickLook/Sources/**`; the host lists it in `dependencies` so Tuist embeds it in `Contents/PlugIns`.
- Info.plist: `NSExtension` = { `NSExtensionPointIdentifier`: `com.apple.quicklook.preview`, `NSExtensionPrincipalClass`: `$(PRODUCT_MODULE_NAME).PreviewViewController`, `NSExtensionAttributes`: { `QLSupportedContentTypes`: [`dev.ryandsilva.segue.chordpro`], `QLSupportsSearchableItems`: false } }.
- Entitlements: `Extensions/QuickLook/QuickLook.entitlements` with `com.apple.security.app-sandbox` only (Quick Look hands the extension read access to the previewed file). No network, no user-selected files.
- Rendering (B-20): view-based `QLPreviewingController` hosting a new public `SongPreviewView` in SegueUI that wraps the existing `SongSheetView` (chords over lyrics, brand fonts registered via `Theme.registerFonts()`), light appearance, no sidecar (Quick Look sees only the `.cho`): key and capo chips from the directives, sections, chords in `cueText`. Parse with `ChordProParser`; a file that fails to parse still previews as plain text. Large files: render the first 400 lines plus "…".
- Signing: Personal/Debug automatic. App Store manual (R12): WS1's manual step creates the App ID `dev.ryandsilva.segue.quicklook` and the Mac App Store profile "Segue Mac App Store QuickLook", and maps it in `ExportOptions-AppStore.plist` beside the app's profile; verify-archive checks the embedded appex signature and profile (I-14). WS2b adds to `scripts/verify-appstore.sh`: the App Store product embeds exactly `SegueQuickLook.appex`, it carries the sandbox entitlement, and it has no personal-module symbols.
- Thumbnail extension: not in scope.

**Show in Finder** is WS2a's; this spec reuses its helper from Settings > General.

### 4.8 Export library archive (zip)

- Entry points: WS2b fills WS2a's File-menu export-archive hook ("Export Library Archive…", no shortcut; I-5) and Settings > Data. Disabled while performing or without an open library.
- Save panel: default name `Segue Library YYYY-MM-DD.zip` (local date), allowed type `.zip`. Debug-only `-SegueExportPath <file>` bypasses the panel for tests.
- Contents (B-23): one top folder `Segue Library YYYY-MM-DD/` containing `songs/` (`.cho` and `.segue.json`), `setlists/`, `shows/`, `timings/`, as they are on disk. Excluded: `.segue/` (the rebuildable index and app-private state), `.DS_Store`, and anything else at the library root that is not one of those four folders (a user's own files there are theirs, not Segue's). Empty or missing folders are simply absent.
- Mechanism (no third-party code, works in the sandbox): copy the four folders into a staging directory under `FileManager.temporaryDirectory`, then `NSFileCoordinator.coordinate(readingItemAt:options: .forUploading)`, which yields a zip of the staging folder, then move it to the chosen URL (replacing an existing file the user confirmed in the panel). Core logic in `Packages/SegueCore/Sources/Library/LibraryArchive.swift` (pure Foundation, injectable file system and clock for the date); the panel and progress in SegueUI. Runs off the main actor with a small progress indicator in the Data pane / a sheet; large libraries are text and stay small.
- Errors (no space, destination not writable, folder unreadable mid-copy): no partial file at the destination; the error banner with the `UserMessage` text. The staging folder is always removed.
- Restore/import of an archive: not in 0.5 (B-23).

### 4.9 Accessibility pass (R15)

**4.9.1 Known fixes, done first**
1. 03 F5 (I-13): WS1 deletes the `setAccessibilityHelp(EditorTextInput.report(textView))` calls. WS2b only verifies they are gone (`grep -n setAccessibilityHelp` in `SourceEditorController.swift` and `VisualEditorController.swift`) and that VoiceOver hears the label, never the machine report. If WS1 has not landed it, stop and ask.
2. Progress dots and other state indicators below 3:1 (03 section 7, brand.md section 5). Ratios computed with the WCAG 2.x formula against `ground`. Ruling A44: option a, **after** Ryan approves a before/after render (section 6, step 1):

| Element | Today (light / dark) | Ratio today | New | Ratio after |
|---|---|---|---|---|
| Pending progress dot | `lineStrong` #B9B9C0 / #2A2B2F | 1.95 / 1.34 | new token `indicatorOff` #8A8A92 / #66676E | 3.43 / 3.36 |
| Played progress dot | `played` #55555C / #55555C | 7.39 / 2.56 | `played` dark becomes #8E8E96 (light unchanged) | 7.39 / 5.81 |
| Skipped dot (ring) | `played` ring | 7.39 / 2.56 | follows `played` | 7.39 / 5.81 |
| Current song pill | `cue` #F2555A | 3.37 / 5.60 | unchanged (also differs by shape) | 3.37 / 5.60 |
| Unrated gig-log stars (`GigLogViews.swift:96`, `GigDetailView.swift:194`) | `lineStrong` | 1.95 / 1.34 | `indicatorOff` | 3.43 / 3.36 |

   On the stage (always dark) the order stays readable by lightness: pending 3.36 < played 5.81, with current as a coral pill (shape and hue). `lineStrong` keeps its value for icon greys and piano black keys, which are not state indicators. Changes go to `design/tokens.json` (then `make tokens`), `docs/brand.md` sections 5 and 7 (token table, contrast list, progress-dot spec), `Live/StageChrome.swift` (pending uses `indicatorOff`), and the expected values in `ThemeTokenTests`.
3. Control borders (A43): `controlBorder` is `line` in light (1.27:1 on paper) and about 1.9:1 in dark; secondary buttons, chips and steppers have no fill, so the border is their only edge. First, read Apple's current App Store Connect "Sufficient Contrast" criteria text and record the quote and date in `docs/release/accessibility-audit.md`.
   - If the criteria accept meeting contrast under the Increase Contrast setting (expected): add Increase Contrast variants only (`"appearance": "contrast", "value": "high"` in the generated asset catalog; `tokens.json` gains optional `lightHigh`/`darkHigh`) with `controlBorder` at #8A8A92 / #66676E (3.43 / 3.36). The default look is unchanged.
   - If they do not: apply the same values in the default look as well (visibly heavier borders), update brand.md, and tell Ryan in the step's commit message and the final report.
4. Add a contrast test: `ThemeTokenTests` computes WCAG ratios for a declared table of (foreground, background, minimum, appearance incl. high contrast) pairs (text 4.5, state indicators and control edges 3.0 where required by item 3's outcome), so a token edit that breaks contrast fails `make test`.

**4.9.2 VoiceOver audit plan (every main screen).** Executed by the session agent where automatable (accessibility-tree dumps from XCUITest, `performAccessibilityAudit`, section 7) and by Ryan walking the checklist with VoiceOver (VO-Right through each screen, VO-Space to act, rotor for headings). For each screen: every control has a name that matches its visible text (Voice Control needs this), icon-only buttons have labels, decorative images are hidden, state is announced (selected, on/off, value), reading order follows the visual order, and every common task can be completed without a mouse or drag.

| Screen | Checks | Known gaps to fix |
|---|---|---|
| Welcome sheet (pages 1-3, revisit mode) | Page title read first; "Step n of m" read; consent page: all four choice buttons reachable and equal, Continue state announced, policy link announced as a link | New UI: build it right (consent rows are WS3's view; report gaps to WS3's code, fix in place) |
| WS3 `ConsentSheet` (upgraders) | Same as the consent page | Verify |
| Library chooser (accessLost / openFailed) | Message read before buttons | - |
| Sidebar | Library, Gig Log, setlists, tags announced with counts | - |
| Song list + filter chips + search | Row reads title, artist, key, proficiency; chips announce on/off | Check `ProficiencyMark` is a label, not just a dot |
| Song detail pane | Title, key/capo chips, transpose and Nashville controls announce value; sheet text reads chord then lyric per line | Line reading format: one element per line, read as "<chords>: <lyric>" (e.g. "G, D: Van door slides and the street lamps hum") |
| Diagram strip | Each diagram reads chord name and frets ("G, frets 3 2 0 0 0 3") | Verify existing labels |
| Editor, text mode | Label "ChordPro source", no machine help text (F5) | Verify WS1's fix |
| Editor, visual mode | Pills and slots are elements (exists); every pill offers custom actions "Move left one syllable", "Move right one syllable", "Edit chord", "Delete chord" (`NSAccessibilityCustomAction`) so moving a chord needs no drag | Add custom actions |
| Setlist builder | Library column rows offer "Add to Setlist" (and WS2a's Setlist > Add Selected Song to Setlist submenu, A33); set rows read position, title, key, start time; reorder without drag via custom actions "Move up" / "Move down" (and WS2a's menu commands); running total and target read | Add move actions |
| Gig log + gig detail | Rating reads "3 of 5 stars"; star buttons labelled | Verify |
| Settings (5 panes) | Pane titles; toggles and pickers named; Test buttons say which Shortcut | New panes: build it right |
| Stage (live) | Header reads title and "G, capo 2, 96"; progress reads position text (exists); song body reachable line by line; panels (queue, notes, quick search) and pre-show checklist rows named; keyboard control does not depend on VoiceOver focus | Verify the body and panels |
| Reorder review sheet, resume prompt, alerts | Buttons named; default announced | Verify |
| What's New sheet | Badge words read ("New", "Improved", "Fixed"); links named | New UI |
| Acknowledgements, About | Licence texts readable | - |
| Tips | Tip text and close button read | Verify on one tip |

Full Keyboard Access: with FKA on, Tab reaches every control on every screen above, including sheets, and focus is visible.

**4.9.3 Reduced Motion checks.** With System Settings > Accessibility > Display > Reduce motion on: stage song transitions and indicators (already gated in `LiveView.swift`); `SelectableList` selection animation (`Components/SelectableList.swift:40`) and button press animation (`Theme/ButtonStyles.swift:101`) become instant; Welcome page changes and What's New have no slide; scroll-to-current in lists does not animate; auto-scroll never starts by itself (it starts on `A`/Space, or on advance only when the user set the song's `autoStartScroll`) and pauses on demand; stage entry and exit have no zoom. Record each item as pass/fail.

**4.9.4 Larger Text checks.** No Larger Text claim on Mac (B-19; 03 records that Apple does not offer it there; re-check in App Store Connect at entry time) and no main-window text scaling in 0.5 (A45). Still check: stage at the maximum minimum lyric size (48 pt, `LiveSettings.minLyricSizeRange`) on a 13-inch window size, with zoom (Cmd +) at its limit: no clipped text, scroll instead of shrink; main window at its minimum size (820x520) with long titles: truncation with tooltips, no overlap; macOS 26 Text Size setting (Accessibility > Display), if it applies to third-party apps: record the effect.

**4.9.5 App Store Accessibility labels: final list and verification.** Claim only what passes every common task (primary functionality plus first launch, settings): first-run sheet, library browse and search, edit (both modes), build a setlist, play a show, gig log, Settings.

| Label | Expected after this session | Verification (all must pass, both appearances where relevant) |
|---|---|---|
| Dark Interface | Claim | Every screen in section 4.9.2 in Dark Mode (and with Appearance set to Dark); no white flash on sheet presentation, window open, stage enter/exit, Quick Look; save/open panels follow the system. |
| Sufficient Contrast | Claim after fixes 2-4 | Contrast test green; manual pass with Increase Contrast on and off, light and dark, on every screen; `performAccessibilityAudit(for: .contrast)` clean on each screen; item 3's criteria quote recorded. |
| Reduced Motion | Claim if 4.9.3 passes | Section 4.9.3 checklist all pass. |
| Differentiate Without Color Alone | Claim if audit passes | Each paired state differs by shape, weight or text as well as colour: progress dots (pill/ring/lightness), proficiency (fill vs outline), chips on/off (fill), errors (icon + text), What's New badges (words), current row (selection, not only coral). |
| VoiceOver | Claim only if 4.9.2 passes end to end, including chord moves and set reordering without drag | Ryan's VoiceOver walk of every row in 4.9.2 plus the automated audits green. |
| Voice Control | Claim only if every control can be addressed by its visible name | Voice Control on, "Show names" and "Show numbers" on each screen; perform: create library, add Welcome songs, answer both consent rows, open a song, transpose, add to setlist, start and end a show. |
| Larger Text | Not claimed (B-19) | Re-check in App Store Connect. |
| Captions, Audio Descriptions | Not applicable (no in-app video or audio content) | - |

The outcome (claimed / not claimed with the failing step) is recorded in `docs/release/accessibility-audit.md`, which WS5 uses to fill App Store Connect.

---

## 5. File-level changes

New files (paths relative to the repo root; `SegueUI/` = `Packages/SegueUI/Sources/SegueUI/`):
- `SegueUI/App/WelcomeLibrary/manifest.json` and the four `.cho` files (Appendix A).
- `Packages/SegueCore/Sources/Library/WelcomeSeed.swift` (manifest model), `LibraryStore+Welcome.swift` (generic manifest seeding and tag lookup), `LibraryArchive.swift` (export staging + zip).
- `SegueUI/App/LibrarySession+Welcome.swift` (seed songs + setlist, remove Welcome songs), `SegueUI/App/OnboardingStore.swift`, `SegueUI/App/WhatsNew.swift` (changelog model, version compare, `WhatsNewStore`), `SegueUI/App/ReviewPrompt.swift` (`ReviewPromptStore`, `ReviewPromptPolicy`, `ReviewRequester` + log double), `SegueUI/App/OpenDocuments.swift` (Open With routing and queue), `SegueUI/App/Tips.swift` (tip types, events, parameters, configure).
- `SegueUI/Onboarding/OnboardingModel.swift` (`isPresentingWelcome`, page state machine), `SegueUI/Onboarding/WelcomeSheet.swift` (pages 1-3 hosting WS3's `ConsentChoiceView`, revisit mode), `SegueUI/Onboarding/WhatsNewSheet.swift`.
- `SegueUI/Settings/SegueSettingsView.swift` (the TabView host), `GeneralSettingsView.swift`, `AppearanceSettingsView.swift` + `AppearanceStore.swift`, `DataSettingsView.swift`.
- `SegueUI/Rendering/SongPreviewView.swift` (public wrapper for Quick Look).
- `Extensions/QuickLook/Sources/PreviewViewController.swift`, `Extensions/QuickLook/QuickLook.entitlements`.
- `SegueUI/AccessibilityID+Polish.swift` (identifiers for all new UI, `segue.welcome.*`, `segue.whatsNew.*`, `segue.settings.*`, `segue.export.*`; consent identifiers are WS3's).
- Design directions (step 3): `design/directions/ws2b/` with the mockups and `README.md` naming the picked direction.
- Tests: `Packages/SegueCore/Tests/SegueCoreTests/WelcomeLibraryTests.swift`, `LibraryArchiveTests.swift`; `Packages/SegueUI/Tests/SegueThemeTests/WhatsNewTests.swift`, `ReviewPromptPolicyTests.swift`, contrast tests (inside `ThemeTokenTests.swift`); UI tests in section 7.
- `docs/release/accessibility-audit.md` (session output: results of 4.9).

Not created by WS2b (owned elsewhere): `ConsentStore`, `ConsentChoiceView`, `ConsentSheet`, `PrivacySettingsView` (WS3); `content/changelog.json`, `website/changelog.json` (WS4); the `-SegueScreenshotLibrary` flag and screenshot-only songs (WS5).

Changed files:
- `Project.swift`: `website/changelog.json` in both app targets' resources; `UTImportedTypeDeclarations` and `CFBundleDocumentTypes`; Quick Look targets and embedding (WS1 owns versions, bundle IDs and the export options).
- `Packages/SegueUI/Package.swift`: `.copy("App/WelcomeLibrary")`.
- `App/Sources/SegueApp.swift`: build `OnboardingStore`/`OnboardingModel`, `WhatsNewStore`, `ReviewPromptStore`, `ReviewRequester`, `AppearanceStore`, Welcome folder URL into `AppDependencies`; fill `AppHooks.showWelcome`, `AppHooks.showWhatsNew` and the export-archive hook; pass `OnboardingModel.isPresentingWelcome` to WS3's consent-sheet rule; apply `appearance.mode` at launch; call tips configure.
- `App/Sources/LaunchOptions.swift`: new Debug-only flags inside `#if DEBUG` (all included in `isTestRun`): `-SegueOnboarding fresh|done`, `-SegueSeedWelcome YES`, `-SegueChangelogPath <file>`, `-SegueLastSeenVersion <v>`, `-SegueAppVersion <v>` (overrides the running version for What's New and review tests), `-SegueReviewLog <file>`, `-SegueTips show|hide`, `-SegueExportPath <file>`, `-SegueCompletedGigs <n>` (presets the counter); the constant `screenshotLibraryFolder` (section 4.2). Add the flag strings to verify-appstore's grep list (B-7).
- `SegueUI/App/AppModel.swift`, `AppModel+Shows.swift`: launch-UI priority function, gig counting and `reviewPromptPending`, `isPerforming` mirrored into TipKit parameters.
- `SegueUI/SegueRootView.swift`: present the Welcome / What's New sheets; `LibraryChooserView` keeps `accessLost`/`openFailed`. No `SegueCommands` edits (hooks only, I-5).
- `SegueUI/Settings/LiveSettingsView.swift`: the `SegueSettingsView` declaration moves out to the new host; the Live pane is otherwise untouched (WS1 owns its text).
- `SegueUI/Editor/UnsavedChangesGuard.swift` (`SegueAppDelegate`): `application(_:open:)`.
- `SegueUI/Editor/VisualEditorController+Geometry.swift` (custom actions on pills), `SegueUI/Setlists/SetEntriesList.swift` (move actions), `SegueUI/Live/StageChrome.swift` (dot tokens), `SegueUI/GigLog/GigLogViews.swift`, `GigDetailView.swift` (star token), `SegueUI/Components/SelectableList.swift`, `SegueUI/Theme/ButtonStyles.swift` (Reduce Motion), `SegueUI/Library/LibraryViews.swift` / `SearchField.swift` / `SongDetailPane.swift` / `SetlistBuilderView.swift` / `EditorTopBar.swift` (tip anchors and event donations, per-line accessibility in the sheet).
- `design/tokens.json`, `scripts/gen-tokens.swift` (high-contrast variants; rebase onto WS4's CSS output if it landed first), regenerated `ColorTokens.generated.swift` + `Tokens.xcassets`, `docs/brand.md` sections 5 and 7.
- `scripts/verify-appstore.sh`: Quick Look checks and WS2b flag strings.
- `UITests/LaunchSmokeTests.swift`: the chooser identifiers move into the Welcome sheet page 1.

---

## 6. Prerequisites and step order

Prerequisites (B-21, open-questions section 5): steps 1-2 (and the SegueCore half of step 7) touch no app-shell files and may run in phase 1, in parallel with WS1/WS4/WS3. Steps 3 onward run in phase 4, after WS1 steps 1-5, WS2a (hooks, Help slots, single `Window`, Trash, import, `WorkspaceActions`), WS3 step 3 (`ConsentStore`, `ConsentChoiceView`, `ConsentSheet`, Privacy tab) and WS4's changelog pipeline have landed. If a prerequisite for a step has not landed, do not stub it: stop and ask. Siblings may be editing the tree concurrently: expect unrelated diffs, do not revert them.

Each implementation step ends with `make quick` and the targeted `make e2e-one TEST=<Class>`; commit (signed) per step.

1. **Accessibility quick fixes**. First produce the A44 before/after render: the stage progress dots (pending, played, skipped, current) and unrated gig-log stars, light and dark, today's tokens beside the proposed `indicatorOff` / `played` dark values, as one PNG (`design/directions/ws2b/progress-dots-before-after.png`, rendered with the existing snapshot support). **Stop and show it to Ryan; continue only after he approves.** Then: verify F5 is gone (WS1); read and record the Sufficient Contrast criteria (A43) and pick the border route; `indicatorOff` token and `played` dark value; Increase Contrast variants; contrast test; dots and stars use the new token; Reduce Motion gates. `make tokens`, update brand.md.
2. **Welcome content and core seeding**: the four songs and manifest; `WelcomeSeed`, `LibraryStore+Welcome` (generic manifest seeding); `WelcomeLibraryTests`.
3. **Design directions (R39, A41), before any of the three are built.** Produce 2-3 distinct design directions each for: (a) the Welcome sheet (all three pages, including the hosted consent rows), (b) the What's New sheet (with a realistic two-release, six-row example), (c) the `.cho` document icon (at 512 and 32 px, light and dark Finder). Starting points: brand.md, Ryan's taste (Apple-native minimal, dark-first; Linear/Things and Logic as references). Deliver them as static mockups (SwiftUI previews rendered to PNG, or HTML) in `design/directions/ws2b/`, each labelled with a one-line rationale, shown side by side in light and dark. **Stop and ask Ryan to pick one per item** (or a named mix); record the picks in `design/directions/ws2b/README.md` and commit. Steps 5, 8 and the icon half of step 11 implement the picked directions. This step needs no other prerequisite and may run as soon as step 2 is done.
4. **Preference stores and launch flags**: `OnboardingStore`, `WhatsNewStore`, `ReviewPromptStore`, `AppearanceStore`; `LaunchOptions` flags and `screenshotLibraryFolder`; wiring in `SegueApp.swift`.
5. **Welcome sheet** (picked direction): pages 1-3 hosting `ConsentChoiceView`, resume flow, silent upgrader marking, `isPresentingWelcome`, launch ordering, `AppHooks.showWelcome` revisit mode; `SegueWelcomeE2ETests`; update `LaunchSmokeTests`.
6. **Settings restructure**: `SegueSettingsView.swift` host with five panes (General, Appearance, Live, Privacy = WS3's view, Data), Remove/Add Welcome Songs, reset actions; `SegueSettingsE2ETests`.
7. **Export archive**: `LibraryArchive` + tests; the File hook and Data pane entry points; export E2E.
8. **What's New** (picked direction): changelog model, bundled generated resource, sheet, `AppHooks.showWhatsNew`; `WhatsNewTests`, `SegueWhatsNewE2ETests`.
9. **Review prompt**: counting, policy, requester, firing rules; `ReviewPromptPolicyTests`, `SegueReviewPromptE2ETests`.
10. **TipKit**: tips, events, parameters, test switches; `SegueTipsE2ETests`.
11. **Finder**: imported UTType + document type + icon (picked direction), Open With routing, Quick Look targets, verify-appstore checks; `SegueFinderE2ETests`.
12. **Accessibility pass**: custom actions (visual editor, set reordering), per-line sheet reading, VoiceOver/Voice Control/FKA walk, `AccessibilityAuditE2ETests`, `docs/release/accessibility-audit.md` with the claim list.
13. **Gate**: one `make check` (lint, tokens-check, icon-check, both builds, tests, full E2E, verify-appstore). Fix anything red, including pre-existing flakiness.

---

## 7. Test plan

Integration and E2E first (decisions.md "Testing"); unit tests only for tricky pure logic. Every E2E starts from a reset baseline (`-SegueResetState YES`, a fresh `/private/tmp/segue-e2e/run-<uuid>` library from `SetlistFixture.makeRoot()` or an empty folder). Budget: `make quick` after each small change, `make e2e-one TEST=<Class>` for the class touched, one `make check` at the end.

**SegueCore (`swift test`, real parser, real file store, real index)**
- `WelcomeLibraryTests`: each bundled song parses with zero diagnostics, round-trips byte-identical, has title, artist "Segue Originals", key, tempo and duration; detected key agrees with `{key}`; every chord parses strictly; lyrics are ASCII and contain no Devanagari; the Hindi song's search finds it by "kitabon" and "kitaabon" (romanization-tolerant index); the manifest references only existing files; seeding into an empty temp library creates 4 songs with the manifest's tags, proficiency, cues and `live.columns`; seeding twice creates nothing new; seeding into a library that already has songs leaves them untouched; a second manifest folder with a different tag and no setlist seeds alongside without touching the Welcome songs (the WS5 path); a read-only library fails with a typed error and no partial sidecars without `.cho`.
- `LibraryArchiveTests`: archive a seeded temp library; unzip with `/usr/bin/ditto -x -k` into another temp dir; the tree equals `songs/`, `setlists/`, `shows/`, `timings/` byte for byte; `.segue/` and stray root files are absent; the name uses the injected clock's date; failure to write the destination leaves no file and removes staging.

**SegueUI (`swift test`)**
- `WhatsNewTests`: decodes the real generated `website/changelog.json` (via `#filePath`) under the app-side schema 1 rules (kinds, title 60, text 120, `help` is site-relative, newest-first order, unique versions); fixture-based cases: version comparison table (`0.5` == `0.5.0`, `0.10` > `0.9.1`); range selection; a range with no `showInApp: true` release is silent; `help` resolves to `SegueLinks.site` + path; unknown keys ignored; unknown schema major ignored. Release check `testRunningVersionHasEntry` (the bundled file has a non-draft entry for `MARKETING_VERSION`) runs only when `SEGUE_RELEASE_CHECK=1`, which WS5's release checklist sets; it is skipped otherwise, because the 0.5 entry stays `draft` until release time.
- `ReviewPromptPolicyTests`: table of states (gig count 0/1/2, version already requested, performing, pending review, sheet up, quitsAfterEnding) to fire / not fire.
- `ThemeTokenTests`: the contrast table (section 4.9.1 item 4).
- Quick Look rendering: `SongPreviewView` renders each Welcome song and a malformed fixture to a non-empty image in light appearance (reuse the snapshot support in `StageLayoutRenderSupport`/`DiagramSnapshotSupport`).

**XCUITest (`UITests/`, Personal flavor, `E2ESupport.swift` helpers for launch, focus and input)**
- `SegueWelcomeE2ETests`:
  - `testFreshInstallShowsLibraryStep`: `-SegueResetState YES`, no path: sheet page 1 with both buttons; WS3's `ConsentSheet` is not shown (`isPresentingWelcome`); screenshot attachment. Then try the real open panel: click "Choose Existing Folder…", Cmd-Shift-G to an empty `/private/tmp/segue-e2e/run-x`, "Use as Library"; if the sandboxed panel is not scriptable, record that in the test comment and keep only the presence checks (UNVERIFIED whether XCUITest can drive the remote panel).
  - `testFirstRunSeedsWelcomeLibrary`: empty override folder + `-SegueOnboarding fresh` + consent undecided: page 2 checkbox is on; Continue; page 3 shows WS3's two rows with four buttons of identical frame sizes, none default; Continue disabled; Return and Esc change nothing; answer "Don't Share" and "Send"; Continue; sheet closes; library lists the 4 titles; sidebar has "Welcome Set" and tag "Welcome"; files exist on disk with the expected sidecar JSON; relaunch with `-SegueTestDefaults YES`: Settings > Privacy shows analytics off and crash reports on, no sheet of any kind.
  - `testExistingFolderDefaultsToNoSeed`: override folder seeded with `SetlistFixture` songs + `-SegueOnboarding fresh`: checkbox off; Continue adds nothing.
  - `testQuitMidOnboardingResumes`: answer page 2, terminate, relaunch preserving defaults: only page 3 shows ("Step 1 of 1").
  - `testUpgraderSeesOnlyConsentSheet`: library bookmark stored by an earlier launch (`-SegueRememberLibrary YES`), onboarding keys absent, consent undecided: no Welcome sheet; WS3's `ConsentSheet` appears; no seeding; `onboarding.completed` is true afterwards.
  - `testWelcomeSongsPlayOnStage`: `-SegueSeedWelcome YES`; start "Welcome Set"; the Ferry Lights song renders in 2 columns (existing live accessibility IDs); end show.
  - `testSeedWelcomeWithoutPathUsesScreenshotFolder`: `-SegueSeedWelcome YES -SegueOnboarding done`, no library path: the library at `screenshotLibraryFolder` opens with the 4 songs; a second launch adds nothing.
- `SegueSettingsE2ETests`: Cmd-, opens Settings; the five panes exist; last pane restored after reopening; General shows the library path and "Show Library in Finder"; Appearance: choose Dark, the main window's effective appearance is dark, relaunch keeps it, Match System restores; Privacy is WS3's view (its identifiers present); Data > Remove Welcome Songs trashes the 4 unedited songs and the setlist (files gone from the library folder, via WS2a's `-SegueTrashPath`) and keeps an edited one, listed in the dialog; Reset Tips sets the flag; Reset All Settings resets Live and Appearance and keeps the library; Live pane still drives `minLyricSize` (existing identifiers).
- `SegueWhatsNewE2ETests`: `-SegueChangelogPath` fixture with 0.7 (`showInApp: true`, new) and 0.6.1 (`showInApp: false`, fixed only), `-SegueAppVersion 0.7`, `-SegueLastSeenVersion 0.6`: the sheet shows the 0.7 rows with "New" badges and no 0.6.1 section; Continue; relaunch: no sheet. Range with only `showInApp: false`: no sheet, last-seen updated. Fresh install (no last-seen, onboarding done via override): no sheet. Help > What's New in Segue reopens it. With a pending resume prompt the sheet waits until it is answered.
- `SegueReviewPromptE2ETests` (live fixtures from `SegueLiveE2ETests+Support.swift`): `-SegueReviewLog`: run a gig, end it, resolve the reorder review, wait 4 s: exactly one line. Second gig in the same version: no new line. With `-SegueAppVersion` bumped and `-SegueCompletedGigs 1`: the next gig adds a line. A rehearsal: no line. While the stage is up (assert at several points): no line.
- `SegueTipsE2ETests`: `-SegueTips show`, seeded Welcome library: the search tip popover appears on the search field; typing a search dismisses it; starting the stage shows no tip in the stage window; relaunch without `-SegueTips show`: no tips anywhere (other suites stay deterministic).
- `SegueFinderE2ETests`: `-SegueExportPath /private/tmp/segue-e2e/run-x/out.zip`: File > Export Library Archive… writes the zip (size > 0, starts with `PK`); the zip's contents are checked by the SegueCore test. Open With: open a `.cho` from `/private/tmp/segue-e2e/` with `XCUIApplication.open(_:)` (or `NSWorkspace.open(_:withApplicationAt:configuration:)` from the runner; UNVERIFIED which works for file URLs on macOS 26): inside the library it selects the song; outside it starts WS2a's import confirmation; a `.pdf` shows the error banner.
- `AccessibilityAuditE2ETests`: for each main screen (library, detail, editor text, editor visual, builder, gig log, each Settings pane, Welcome pages, What's New, stage) call `app.performAccessibilityAudit(for:)` with the audit types available on macOS (at least element description, contrast, hit region, clipped text; UNVERIFIED exact set on macOS 26) and fail on issues; plus explicit assertions that every button in each screen has a non-empty label, that the visual-editor pill exposes the four custom actions and the set rows expose Move up / Move down.

**Manual checks (recorded in `docs/release/accessibility-audit.md` or the commit message)**
- App Store flavor first run on a clean macOS user account (`make build-appstore`, run from DerivedData): Welcome flow, seed, both consent rows, What's New absent.
- `mdls -name kMDItemContentType` on a `.cho` reports `dev.ryandsilva.segue.chordpro` (or another app's exported type, which is acceptable under A30; record which); `pluginkit -m -p com.apple.quicklook.preview | grep segue` lists the extension; `qlmanage -p` and Finder spacebar preview a Welcome song; the document icon in Finder at all sizes, light and dark; double-clicking a `.cho` opens Segue on a Mac with no other ChordPro app.
- VoiceOver, Voice Control, FKA, Reduce Motion, Increase Contrast walks per section 4.9.

---

## 8. Acceptance criteria

1. On a clean install, launch -> page 1 -> "Create Library in Music…" -> page 2 (box ticked) -> page 3 (both consent rows answered, Continue) -> library shows the 4 Welcome songs and "Welcome Set" with no further action, in both flavors.
2. The consent page is WS3's `ConsentChoiceView`: two rows, four equal-weight buttons, no default, no pre-selection; Continue stays disabled until both rows are answered; nothing is recorded by WS2b code; Settings > Privacy (WS3's view) shows and changes the same `ConsentStore` state immediately. WS3's standalone `ConsentSheet` never appears while the Welcome flow is up.
3. Existing installs are never seeded and never see the Welcome sheet (they get WS3's consent sheet if undecided); test runs with a library override see no onboarding, What's New, tips or review prompt unless asked by flag (the existing E2E suite passes unchanged apart from the smoke test identifiers).
4. All four Welcome songs pass `WelcomeLibraryTests`; Ryan has done the title search; the Ferry Lights song plays in 2 columns; the setlist totals 15:10 of 20:00.
5. Welcome songs and the demo setlist can be deleted individually (WS2a) and together (Settings > Data, keeping edited songs), to the Trash, never permanently.
6. What's New reads only the bundled generated `website/changelog.json` (WS4 schema 1), never touches the network, shows automatically only for a release in range with `showInApp: true`, never on first install, never with or before higher-priority launch UI, never during a show, and is reachable from Help.
7. `requestReview` is called at most once per app version, only after the 1st completed gig, after the end-of-show flow, with the stage closed; never on launch, never from a button, never while performing.
8. The five TipKit tips appear only under their rules, at most one per day, never in the stage window.
9. Settings has General, Appearance (Match System default / Light / Dark), Live, Privacy, Data; restores the last pane; loses none of today's Live settings.
10. `.cho` files show the Segue document icon and type name in Finder (unless another app exports the type), "Open With > Segue" routes as in 4.7, and Quick Look previews them from the sandboxed extension in both flavors; `make verify-appstore` checks the extension.
11. Export Library Archive produces a zip with exactly `songs/`, `setlists/`, `shows/`, `timings/` under one dated folder; failures leave nothing behind.
12. Ryan approved the progress-dot before/after render and picked a direction for each of the three designed items before they were built; the picks are in `design/directions/ws2b/README.md`.
13. All state indicators and control edges (per A43's recorded route) meet 3:1, text 4.5:1, in both appearances and with Increase Contrast; the contrast test enforces it.
14. `docs/release/accessibility-audit.md` lists each label as claimed or not, with evidence, and only passing labels are claimed.
15. `make check` is green at the end, with no new warnings and no flaky tests left behind.

---

## 9. Risks

- **Sandboxed panels in XCUITest**: driving NSOpenPanel/NSSavePanel may be impossible; mitigated by the override flags, with the real-panel path verified manually on the App Store flavor.
- **Quick Look extension signing**: the manual App Store profile for the extension (R12, I-14) can block archiving; WS1 creates it early. Two Segue flavors installed on one Mac both declare the type and both register a preview extension; LaunchServices picks one, which is harmless but can confuse testing (test with one flavor installed, or check `pluginkit` output).
- **UTType ownership**: with an imported declaration (A30), another installed ChordPro app that exports a type for `.cho` wins; then Segue's description and icon may not apply on that Mac, and Quick Look may not use Segue's extension. Accepted by A30.
- **TipKit datastore**: tips persist in the container; a test that forgets `-SegueTips` could see stale tips; the default-hide rule for test runs prevents flakiness. The datastore adds files the WS1 privacy manifest may need to account for.
- **Contrast changes alter the brand look** (brand.md is canonical); hence Ryan's before/after approval in step 1 and A43's recorded route.
- **Lyric originality**: accidental resemblance to an existing song cannot be fully excluded; mitigated by Ryan's title search (section 10).
- **Changelog drift**: the app bundles whatever WS4 generated at build time; a release without an entry shows no sheet. Mitigated by `WhatsNewTests` (release check) and WS5's release checklist.
- **Cross-workstream contracts**: WS3's `ConsentChoiceView`/`isComplete`/`needsPrompt`, WS2a's hooks and WS4's generated file are consumed as specified; a missing piece stops the session rather than being stubbed.
- **requestReview silence**: TestFlight shows nothing and the OS rate-limits, so only the log double proves wiring; a real prompt is seen only in a development build.
- **Ordering complexity at launch** (resume prompt, reviews, onboarding, consent sheet, What's New): one explicit priority function in `AppModel` with tests in `SegueWelcomeE2ETests`/`SegueWhatsNewE2ETests` avoids stacked sheets.
- **Accessibility claims**: VoiceOver and Voice Control depend on a human walk; if Ryan cannot do it before submission, those labels stay unclaimed.

---

## 10. Manual actions for Ryan

1. Before step 2 ships the songs: run a title search for each Welcome song (Apple Music, Spotify, Google "<title> song"); if one collides, tell the session which title to change.
2. Step 1: approve the progress-dot before/after render.
3. Step 3: pick one design direction each for the Welcome sheet, the What's New sheet and the `.cho` document icon.
4. The Quick Look App ID and profile are created in WS1's manual signing step (I-14); confirm it is done before step 11's App Store build.
5. Do the VoiceOver and Voice Control walks in section 4.9 (the agent prepares the checklist and fixes what you find).
6. Answer the open questions below before step 6 (Settings) starts.

---

## 11. Open questions for Ryan

1. **RESOLVED (option b, default taken): consent is kept.** Resetting consent from "Reset All Settings…"** (A17 kept "Privacy decisions back to undecided", but I-1 makes WS3's `ConsentStore` the only writer, and WS3's spec defines no reset API). Options: a) WS3 adds `ConsentStore.resetToUndecided()` (swaps in Null adapters, discards queues, WS3's sheet re-asks next launch) and WS2b calls it; b) drop Privacy from the reset scope (the Privacy pane already turns each off), and the confirmation says consent is kept. Recommend b: resetting to undecided adds a re-prompt with no user benefit and a second consent-changing path WS3 would have to test.
2. **`GigModeTip` timing** (follows from A37 hiding the Focus row): this spec makes the tip eligible after the first show or rehearsal starts, so a user can discover Gig Mode before their first real gig. The earlier draft waited for the first completed gig. Keep the new rule?

---

## Appendix A - Welcome library songs (original, written for Segue)

Each block is the exact file content (UTF-8, LF line endings, final newline).

### A.1 `soundcheck-at-seven.cho`

```
{title: Soundcheck at Seven}
{artist: Segue Originals}
{key: G}
{capo: 2}
{tempo: 96}
{duration: 3:20}

{start_of_verse: Verse 1}
[G]Van door slides and the [D]street lamps hum,
[Em]Cables coiled like a [C]sleeping drum,
[G]Someone tapes the [D]setlist down,
[C]Loudest piece of [D]paper in town.
{end_of_verse}

{start_of_chorus}
[C]Soundcheck at [G]seven, [D]doors at [Em]eight,
[C]Tune it, count it, [G]never mind the [D]wait,
[C]One, two, can you [G]hear me in the [Em]back?
[C]Turn the monitor [D]up and we're on [G]track.
{end_of_chorus}

{start_of_verse: Verse 2}
[G]Coffee's cold on the [D]amplifier,
[Em]Bass is singing a [C]little higher,
[G]Lights go blue and the [D]lights go red,
[C]Every word we [D]never said.
{end_of_verse}

{chorus}

{start_of_bridge}
[Em]Empty [C]chairs will [G]fill up [D]soon,
[Em]Strangers [C]humming [D]half our tune.
{end_of_bridge}

{chorus}
```

### A.2 `kitaabon-wali-gali.cho` (romanized Hindi)

```
{title: Kitaabon Wali Gali}
{artist: Segue Originals}
{key: Am}
{tempo: 84}
{duration: 4:05}

{comment: Slow intro, guitar only}

{start_of_verse: Verse 1}
[Am]Purani si gali mein [G]kitaabon ki dukaan,
[F]Panne palatte haathon mein [E]chhupi thi muskaan,
[Am]Chai ka cup thanda tha, [G]baatein thi garam,
[F]Shaam ne dheere dheere [E]badle apne kadam.
{end_of_verse}

{start_of_chorus}
[F]Kitaabon wali [G]gali, [C]phir se bula [Am]rahi,
[F]Har ek kahaani [G]mein teri [E]yaad chhupi,
[F]Lafzon ke [G]mele mein [C]main kho [Am]jaaun,
[Dm]Tera naam likha [E]panna dhoondh [Am]laaun.
{end_of_chorus}

{start_of_verse: Verse 2}
[Am]Baarish ki boondein [G]khidki pe likhti,
[F]Adhoori si kavita [E]jo tujh tak pahunchti,
[Am]Raaste wahi hain, [G]mausam naya,
[F]Dil ne phir se [E]wahi geet gaaya.
{end_of_verse}

{chorus}

{start_of_bridge}
[Dm]Na koi [Am]jaldi, [E]na koi [Am]shor,
[Dm]Bas ek [Am]kahaani [E]aur nayi si [Am]bhor.
{end_of_bridge}

{chorus}
```

Gloss for review (not shipped): "The lane of books" - an old lane with a bookshop, a smile hidden in hands turning pages, cold tea and warm talk; the lane calls again, every story hides your memory, I lose myself in a fair of words and find the page with your name; rain writes on the window, an unfinished poem reaches you; no hurry, no noise, just a story and a new dawn.

### A.3 `kettle-on-lights-low.cho` (waltz, capo, custom shape)

```
{title: Kettle On, Lights Low}
{artist: Segue Originals}
{key: G}
{capo: 3}
{time: 3/4}
{tempo: 72}
{duration: 3:05}
{define: Cadd9 base-fret 1 frets x 3 2 0 3 3}

{start_of_intro: Intro}
[G]  [Cadd9]  [G]  [D/F#]
{end_of_intro}

{start_of_verse: Verse 1}
[G]Kettle on, [Cadd9]lights low,
[G]Rain on the [D/F#]window glass,
[Em7]Nowhere we [Cadd9]need to go,
[G]Let the [D]evening [G]pass.
{end_of_verse}

{start_of_verse: Verse 2}
[G]Two old [Cadd9]chairs that creak,
[G]One old [D/F#]song we know,
[Em7]Half of it [Cadd9]hummed, not sung,
[G]Kettle [D]on, lights [G]low.
{end_of_verse}

{start_of_chorus}
[Cadd9]Turn, turn, [G]round the room,
[Cadd9]Slow as the [D]clock can go,
[Em7]One more [Cadd9]waltz for the [G]afternoon,
[Am7]Kettle [D]on, lights [G]low.
{end_of_chorus}

{start_of_verse: Verse 3}
[G]Cups gone [Cadd9]cold again,
[G]Records [D/F#]spinning slow,
[Em7]Stay till the [Cadd9]morning, then,
[G]Kettle [D]on, lights [G]low.
{end_of_verse}

{chorus}
```

### A.4 `ferry-lights-over-calder-bay.cho` (the 2-column song)

Its sidecar pins `live.columns = 2` (manifest), so the stage shows two columns regardless of window size; its length alone makes auto-fit choose two columns on a typical laptop screen.

```
{title: Ferry Lights Over Calder Bay}
{artist: Segue Originals}
{key: D}
{tempo: 120}
{duration: 4:40}

{start_of_intro: Intro}
[D]  [A/C#]  [Bm]  [G]
{end_of_intro}

{start_of_verse: Verse 1}
[D]Ticket in my pocket and the [A/C#]gulls above the pier,
[Bm]Every engine idling like it's [G]waiting for the year,
[D]Ropes come off the bollards with a [A]sound like letting go,
[G]Calder Bay is [A]shining in the [D]last of the glow.
{end_of_verse}

{start_of_prechorus: Pre-Chorus}
[Em]Hold the rail, [G]hold your breath,
[Em]Half the town is [A]waving yet.
{end_of_prechorus}

{start_of_chorus}
[D]Ferry lights, [A]ferry lights,
[Bm]Carry me home a[G]cross the night,
[D]Every window [A]burning bright,
[G]Over Calder [A]Bay, the [D]ferry lights.
{end_of_chorus}

{start_of_verse: Verse 2}
[D]Someone plays a fiddle by the [A/C#]lifeboat on the deck,
[Bm]Children count the buoys with their [G]scarves around their necks,
[D]Engines turn to thunder and the [A]harbour turns to blue,
[G]Every lamp on [A]shore is a [D]promise coming true.
{end_of_verse}

{start_of_prechorus: Pre-Chorus}
[Em]Hold the rail, [G]hold your breath,
[Em]Half the town is [A]waving yet.
{end_of_prechorus}

{chorus}

{start_of_bridge}
[Bm]Out past the [A]breakwater, [G]out where the [D]water's wide,
[Bm]Nothing but the [A]engine and the [G]moon on the [Asus4]tide [A]
{end_of_bridge}

{chorus}

{start_of_outro: Outro}
[G]Over Calder [A]Bay, the [D]ferry lights.
{end_of_outro}

{comment: Let the last D ring}
```

Total set length: 3:20 + 4:05 + 3:05 + 4:40 = 15:10.
