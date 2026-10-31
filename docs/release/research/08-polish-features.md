# 08 - Production polish features: survey and gap analysis

Date: 2026-10-17. Scope: the in-app UX surfaces that well-regarded Mac apps ship, the Apple HIG and App Review rules that apply, and where Segue (App Store flavor, `SegueAppStore` target) stands. Vendors for analytics, crash reporting, the feature board and the bug-report transport are covered by a sibling doc; here only *where the entry points live and how they look*.

Legend: **UNVERIFIED** = not confirmed against a primary source in this session (from memory or a secondary write-up). Code evidence is `path:line` relative to the repo root; `SegueUI/` is short for `Packages/SegueUI/Sources/SegueUI/`.

---

## 1. Survey: what polished Mac apps ship

### 1.1 Apps surveyed and what was observed

| App | Category | Observed polish surfaces (source) |
|---|---|---|
| **NetNewsWire** (open source, AppKit) | Reader | Help menu, read from the shipped `MainMenu.xib`: *NetNewsWire Help, Keyboard Shortcuts, Add NetNewsWire News Feed, Open Application Support Folder,* separator, *Website, Release Notes, How To Support NetNewsWire, GitHub Repository, Bug Tracker, Discourse Forum*. App menu: About, Preferences, Check for Updates. File: Import / Export Subscriptions. Edit: full Undo/Redo, Find. Window menu: Activity Log, Error Log, Account Stats. Separate About window, Crash Reporter window, and a credits window ("Dinosaurs"). https://github.com/Ranchero-Software/NetNewsWire/blob/main/Mac/MainMenu/Base.lproj/MainMenu.xib , https://github.com/Ranchero-Software/NetNewsWire/tree/main/Mac (About/, CrashReporter/, Dinosaurs/, ErrorLog/) , help book https://netnewswire.com/help/mac/5.0/en/getting-more-help.html |
| **Ice** (open source, SwiftUI menu bar app) | Utility | Settings panes: General, Menu Bar Layout, Menu Bar Appearance, Hotkeys, Advanced, About (About lives as a Settings pane). Dedicated first-run Permissions window explaining each permission before asking. https://github.com/jordanbaird/Ice/tree/main/Ice/Settings/SettingsPanes , https://github.com/jordanbaird/Ice/tree/main/Ice/Permissions |
| **Things 3** | Tasks | Help > Keyboard Shortcuts window; customisable shortcuts for any menu command via System Settings; Quick Entry global panel; public release notes page. https://culturedcode.com/things/support/articles/2785159/ , https://culturedcode.com/things/releasenotes/ . Bundled "Welcome" sample project on first run: UNVERIFIED. |
| **Linear** | Issues | `?` (or Cmd-/) opens a searchable keyboard-shortcuts window; "Help & Feedback" entry at the bottom of the sidebar (shortcuts, changelog, contact). https://linear.app/enablement/guide/navigating-linear , https://linear.app/changelog/2021-03-25-keyboard-shortcuts-help |
| **Raycast** | Launcher | "Send Feedback" command with category picker (Bug / Feature Request / Store / General); bug-report hotkey; onboarding walkthrough that points at Send Feedback; troubleshooting page. https://manual.raycast.com/windows/send-feedback , https://manual.raycast.com/troubleshooting , https://manual.raycast.com/keyboard-shortcuts.md |
| **CleanShot X** | Screenshots | Menu bar extra as primary surface; Settings tabs including General, Shortcuts, Advanced (API access toggle). https://thesweetsetup.com/take-better-screenshots-with-cleanshot-x/ . In-app What's New panel after update: UNVERIFIED. |
| **Bear 2** | Notes | File > Backup Notes / Restore Backup (single `.bear2bk`, a zip of TextBundles so it is readable without Bear); export to txt/md/TextBundle/rtf (free) and html/docx/pdf/epub. https://bear.app/faq/backup-restore/ , https://bear.app/faq/export-your-notes/ |
| **Craft** | Docs | Keyboard shortcut sheet (Cmd-Opt-, or the `?` button bottom right); Quick Entry; support centre organised by task. https://support.craft.do/en/introduction/shortcuts , https://support.craft.do/en/introduction/quick-entry |
| **Arc / Dia** | Browser | Dia onboarding: account, import passwords/history/bookmarks from other browsers, theme pick; Arc's command bar replaced Cmd-T. https://en.wikipedia.org/wiki/Dia_(web_browser) . Arc "Command Bar" details: UNVERIFIED beyond the Wikipedia summary. |
| **Ivory** | Mastodon | Per-release "What's New" notes; timeline sync across devices; behaviour settings (e.g. alt-text reminder). https://www.macstories.net/news/tapbots-releases-ivory-2-0-with-hashtag-lists-and-a-redesigned-share-sheet-extension/ . In-app tips: UNVERIFIED. |
| **Tot** | Scratchpad | Optional menu bar mode (preference). https://daringfireball.net/2020/02/tot |
| **MainStage / Logic Pro** | Live music | Perform in Window (Cmd-3) / Perform in Full Screen (Cmd-4) as menu commands with shortcuts; dedicated keyboard-shortcut chapters in the user guide; Quick Help (hover help). https://support.apple.com/guide/mainstage/mstg565a2019/mac |
| **Ableton Live 12** | Live music | Learn View (built-in lessons, shown on first launch, reopen from Help menu), Info View (hover-to-explain, toggled with `?`), links to manual and knowledge base. https://www.ableton.com/en/live-manual/12/first-steps/ |
| **forScore** | Sheet music (iPad, Mac) | Tools > Backup: backup (metadata only) vs archive (everything, recommended); restore; "Recently Deleted" for scores and setlists; extensive knowledge base. https://forscore.co/backup , https://forscore.co/?p=1299 , https://forscore.co/?p=1413 |
| **OnSong** | Chord charts (iPad, Mac) | Utilities > Backup with automatic backups, a `.backup` zip of the whole library and settings; export to ChordPro and other formats; user manual and KB. https://onsongapp.com/docs/1.999/features/backup , https://desk.zoho.com/portal/onsong/kb/articles/how-do-i-make-onsong-automatically-backup-my-library |
| **Mimestream** (indie) | Mail | In-app feedback form: pick a category, relevant logs attach automatically, private content needs manual opt-in, everything previewed before sending; public release notes. https://mimestream.com/blog/1.2-released , https://mimestream.com/releases |

### 1.2 Shared features, catalogued

| # | Feature | Who ships it (cited above) | Notes |
|---|---|---|---|
| 1 | **Help menu with real content** | NetNewsWire (11 items), Things, Ableton, MainStage | Pattern: Help, Keyboard Shortcuts, separator, Website / Release Notes / Feedback / Bug tracker. HIG: keep the list short. |
| 2 | **About window** | NetNewsWire (custom), Ice (Settings pane), all apps (standard panel) | Version + build, copyright, website link, credits. |
| 3 | **What's New on update** | Things, Ivory, Mimestream (release-notes pages); in-app sheet UNVERIFIED for most | Universal: a public release-notes page. In-app sheet is common but not universal. |
| 4 | **Onboarding / first run** | Ice (permissions window), Dia (import), Ableton (Learn View), Raycast (walkthrough) | The best ones are short, task-first and re-openable from Help. |
| 5 | **Empty states / sample content** | Ableton (lessons as content), Things welcome project (UNVERIFIED) | Sample content lets a new user try the core loop in seconds. |
| 6 | **TipKit-style feature discovery** | HIG recommends tips over a long onboarding flow | macOS 14+. https://developer.apple.com/documentation/tipkit |
| 8 | **Keyboard shortcut cheat sheet** | Things, Linear (`?`), Craft (`?`), NetNewsWire, Ableton Info View | `?` or Help > Keyboard Shortcuts. |
| 9 | **App Store review prompt** | All App Store apps via `RequestReviewAction` | Custom prompts banned (5.6.1). |
| 10 | **Settings structure** | Ice (General / feature panes / Advanced / About), CleanShot (General / Shortcuts / Advanced) | General first, Advanced last; per-feature panes in between. |
| 11 | **In-app feedback + bug report with diagnostics** | Mimestream, Raycast, NetNewsWire (bug tracker link + crash reporter) | Best form: category, auto-attached logs, preview before send. |
| 12 | **Sync / backup status** | forScore, OnSong, Bear | Visible backup location, last backup. |
| 13 | **Data portability / export** | Bear (many formats, readable backup), NetNewsWire (OPML), OnSong (ChordPro) | Open formats are a trust signal. |
| 14 | **Accessibility** | All Apple apps; App Store Accessibility Nutrition Labels | https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels |
| 15 | **Localisation** | Things, Bear, NetNewsWire (many languages) | String Catalogs make it cheap to start. |
| 17 | **Menu bar extra** | CleanShot, Tot, Ice | A small ambient surface beside the main window. |
| 18 | **Services menu** | NetNewsWire (standard app menu) | System-provided; apps can vend services. |
| 19 | **Drag and drop** | Universal | In and out of the app, to and from Finder. |
| 20 | **Quick Look preview / thumbnail extensions** | Apps with custom file types | https://developer.apple.com/documentation/quicklook ; none found for ChordPro on Mac (Chord Provider's repo has no QL target at HEAD). |
| 22 | **Document icons + UTType registration** | Any app owning a file type | https://developer.apple.com/documentation/uniformtypeidentifiers/defining-file-and-data-types-for-your-app |
| 23 | **Handoff** | Things, Bear | Continue an activity on another of the user's Macs. |
| 24 | **Window and state restoration** | HIG "restore the previous state" | https://developer.apple.com/design/human-interface-guidelines/launching |
| 25 | **Full keyboard navigation** | Things, Linear, MainStage | HIG: every command in the menu bar so Full Keyboard Access reaches it. |
| 26 | **Undo everywhere** | NetNewsWire (mark read), Things, Bear | https://developer.apple.com/design/human-interface-guidelines/undo-and-redo |
| 27 | **Autosave and versions** | Document apps (TextEdit, Pages); Bear, Things save continuously | |
| 28 | **Error presentation** | NetNewsWire Error Log window | Plain-language error + recovery action + "report". |
| 29 | **Offline behaviour** | NetNewsWire, Things, Bear (local-first) | |
| 30 | **Performance (launch time)** | Things ("All Things Speed" blog) https://culturedcode.com/things/blog/2021/10/all-things-speed/ | |
| 31 | **Open-source acknowledgements view** | NetNewsWire (Dinosaurs/credits), most apps in About credits | Licence compliance (MIT, OFL). |
| 32 | **Recently Deleted / trash** | forScore (Recently Deleted), Bear (trash) | Undo for destructive file ops. |

---

## 2. Apple HIG and App Review expectations (primary sources)

Fetched from Apple's documentation JSON on 2026-10-17.

**Menu bar / Help menu** (https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)
- App menu order: About, Settings…, optional app-specific items, Services, Hide, Hide Others, Show All, Quit. "Display the About menu item first. Include a separator after the About menu item so that it appears by itself in a group."
- Help menu: "provides access to an app's help documentation. When you use the Help Book format for this documentation, macOS automatically includes a search field" (the search field also searches menu items in every app). Items: *YourAppName Help*, then "Use a separator between your primary help documentation and additional items, which might include registration information or release notes. Keep the total number of items you list in the Help menu small."
- "Provide app-specific menus for custom commands... Even when commands are available elsewhere in your app, it's important to list them in the menu bar... makes them more accessible to people using Full Keyboard Access." Provide a View menu and a Window menu even if minimal.
- Consequence for Segue: without a Help Book or a replaced Help group, the default SwiftUI Help menu shows "Segue Help", which opens a "Help isn't available for Segue" alert (standard macOS behaviour; UNVERIFIED on this exact build, check before submission). That looks unfinished to a reviewer.

**Settings** (https://developer.apple.com/design/human-interface-guidelines/settings)
- Cmd-, opens it; Settings item in the App menu, not a toolbar button. Toolbar of panes; "Update the window's title to reflect the currently visible pane. If your settings window doesn't have multiple panes, use the title App Name Settings." "Restore the most recently viewed pane." Dim minimise/zoom.
- "Minimize the number of settings." "Respect people's systemwide settings and avoid including redundant versions of them" - so **no in-app Appearance (light/dark) override**, and no accessibility duplicates.
- Task-specific options belong in the screen they affect (Segue already does this: columns on stage with C, per-song prefs in the editor).

**Ratings and reviews** (https://developer.apple.com/design/human-interface-guidelines/ratings-and-reviews , https://developer.apple.com/documentation/storekit/requestreviewaction , https://developer.apple.com/documentation/storekit/requesting-app-store-reviews)
- System limits display to **3 times per app per 365 days**; after a review, only for a new version and 365+ days later.
- "Avoid asking for a rating on first launch or during onboarding." "Avoid interrupting people while they're performing a task." "Allow at least a week or two between requests."
- "Because this API may not present an alert, don't call it in response to a button tap or other user action." A persistent "Write a Review" link (`...?action=write-review`) is allowed for user-initiated reviews.
- Apple's sample gates on: not yet prompted for this bundle version, the core task completed N times (they use 4), and a pause of a few seconds on the completion screen.
- In development builds it always shows; in **TestFlight it does nothing**.
- App Review 5.6.1: "Use the provided API to prompt users to review your app... we will disallow custom review prompts." (https://developer.apple.com/app-store/review/guidelines/)

**Help, tips and onboarding** (https://developer.apple.com/design/human-interface-guidelines/offering-help , https://developer.apple.com/design/human-interface-guidelines/onboarding)
- Prefer context-specific tips (TipKit) over one onboarding flow; tips for features of three steps or fewer; one or two sentences; eligibility rules so people who already used a feature never see its tip; when several tips exist, a cadence like once per 24 hours.
- Onboarding "fast, fun, and optional", re-findable later from Help; "Postpone nonessential setup... Provide reasonable default settings"; no licence text in onboarding.

**Launching / restoration** (https://developer.apple.com/design/human-interface-guidelines/launching)
- "Restore the previous state when your app restarts... display windows in the same state and location in which people left them." No splash screens on macOS.

**App Review Guidelines** (https://developer.apple.com/app-store/review/guidelines/)
- **5.1.1(i)**: a privacy policy link is required "in the App Store Connect metadata field **and within the app in an easily accessible manner**." -> a Help menu item is the natural home.
- **5.1.1(ii)**: "Apps that collect user or usage data must secure user consent for the collection, even if such data is considered to be anonymous." -> if the sibling doc picks analytics, the in-app UX needs consent (opt-in toggle or first-run ask), not a silent default-on.
- **1.5**: app and Support URL must include an easy way to contact the developer -> a Contact / Send Feedback item.
- **2.4.5**: Mac apps sandboxed, self-contained, no auto-launch at login without consent (relevant if a menu bar extra or login item is ever added).
- **4.2**: minimum functionality - reviewers judge what they can reach. An empty library with no import path is a weak first impression for a reviewer (see sample content below).

**Accessibility Nutrition Labels** (https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels , https://support.apple.com/123073): per-app declarations for VoiceOver, Voice Control, Larger Text, Dark Interface, Differentiate Without Color Alone, Sufficient Contrast, Reduced Motion, Captions, Audio Descriptions. Claim a label only when all common tasks work with that feature. Whether declaring is mandatory for new submissions as of Oct 2026: UNVERIFIED (the sibling technical-submission doc should confirm).

---

## 3. Segue today: what exists (code evidence)

- **Scenes**: one `WindowGroup` main window, an `Acknowledgements` window, a `Settings` scene (`App/Sources/SegueApp.swift:95-115`).
- **Menus**: App menu gets "Acknowledgements" after About (`SegueUI/SegueRootView.swift:299-303`); File > New Song Cmd-N replaces New (`:304-319`); custom **Library** menu: Refresh Cmd-R, Rebuild Index, Choose Library Folder… (`:320-344`). No Help group, no Show/Setlist menu, no "Start Show" command. Save is Cmd-S in the editor (`SegueUI/Editor/SongEditorView.swift:72`).
- **About**: the standard SwiftUI About panel from Info.plist only: version `0.1.0`, build `1`, copyright (`Project.swift:109-115`). No credits, website or support link.
- **Settings**: a single "Live" tab (`SegueUI/Settings/LiveSettingsView.swift:13-23`), which has min lyric size, default columns, Gig Mode Shortcuts with Test buttons and a guide, and pre-show checklist toggles (`:34-91`). With one pane the HIG says the title should be "Segue Settings".
- **Acknowledgements**: Schibsted Grotesk (OFL), GRDB (MIT), Tonic (MIT), with bundled licence texts (`SegueUI/App/AcknowledgementsView.swift:26-48`, `:76-80`). Good.
- **First run**: a branded library chooser ("Create Library in Music…" / "Choose Existing Folder…", reasons for first launch, lost access and open failure) (`SegueUI/SegueRootView.swift:37-114`). No sample content, no tour.
- **Empty states**: `ContentUnavailableView` for the empty library with a New Song action (`SegueUI/Library/LibraryViews.swift:117-133`), no song selected (`:285-291`), missing setlist (`SegueUI/SegueRootView.swift:254-258`), empty gig log and no gig selected (`SegueUI/GigLog/GigLogViews.swift:21-25`, `:44-49`), builder library column (`SegueUI/Setlists/BuilderLibraryColumn.swift:98`). Skipped files get a footer with an explanation popover (`SegueUI/Library/LibraryViews.swift:81-104`, `:159`).
- **Errors**: bottom error banner with Dismiss (`SegueUI/SegueRootView.swift:263-286`), plain-language mapping (`SegueUI/App/UserMessage.swift:7-62`), save-conflict alert with Reload / Overwrite / Save as Copy (`SegueUI/SegueRootView.swift:146-199`), unsaved-changes prompts on navigation and quit (`SegueUI/Editor/UnsavedChangesGuard.swift:63-74`). No "report this" action.
- **Undo**: editor only, with grouped, named undo actions shared by text and visual modes (`SegueUI/Editor/SourceEditorController.swift:27`, `:136-152`; `SegueUI/Editor/VisualEditorController.swift:273-274`). Setlist edits, metadata edits and deletes have no undo. **Setlist delete removes the file permanently** (`Packages/SegueCore/Sources/Setlists/SetlistStore.swift:240-247`, `removeItem`), as does gig delete (`Packages/SegueCore/Sources/Shows/ShowStore.swift:222-230`), each behind a confirmation dialog (`SegueUI/Library/MainSidebar.swift:61-67`, `SegueUI/GigLog/GigDetailView.swift:67`).
- **No in-app song delete or import**: no delete action for songs anywhere in the library UI; the only file panels are for picking the library folder (`SegueUI/App/LibraryLocation.swift:146-178`). Songs arrive by New Song or by copying files into the folder in Finder and pressing Refresh. (Not a "polish" feature, but it shapes several rows below.)
- **Drag and drop**: within the setlist builder only (library -> set, reorder) (`SegueUI/Setlists/BuilderLibraryColumn.swift:61`, `SegueUI/Setlists/SetEntriesList.swift:54-58`, `:116`). No Finder drag in or out.
- **Keyboard on stage**: fully keyboard-driven via a binding table (`Packages/SegueCore/Sources/Shows/LiveCommand.swift`), local key monitor (`SegueUI/Live/LiveKeyInput.swift:13-55`); a fading status line lists the main keys (`SegueUI/Live/StageChrome.swift:266-275`). No full cheat sheet.
- **Crash safety**: show crash-resume prompt (`SegueUI/App/AppModel+Shows.swift:13-28`, `:94`), keep-awake assertion (`SegueUI/Live/KeepAwake.swift:5`). Best-in-class for the stage use case.
- **Accessibility**: 38 `accessibilityLabel/Hint/Value` uses across SegueUI; Reduce Motion respected on stage (`SegueUI/Live/LiveView.swift:16`, `:125`, `:229`); contrast pairs documented to AA (`docs/brand.md:70`, `:95`). No VoiceOver audit recorded.
- **Localisation**: `developmentRegion: "en"` (`Project.swift:193`); no String Catalog in the repo. Product decision: English + romanized Hindi content, English UI (`docs/decisions.md:91-100`).
- **Info.plist**: no `CFBundleDocumentTypes` / `UTImportedTypeDeclarations` (`Project.swift:109-115`), so `.cho` files are not associated with Segue and get no icon.
- **Restoration**: main window uses system window restoration by default; Acknowledgements opts out (`App/Sources/SegueApp.swift:109`); no `@SceneStorage`, so the sidebar section and selected song are not restored.
- **Offline**: everything is local; no network code in the App Store flavor.

---

## 4. Gap analysis

Columns: Status (exists / partial / missing), Value for gigging musicians (H/M/L), Effort (S < 1 day, M 1-3 days, L > 3 days), proposed Tier.

| # | Feature | Status + evidence | Value | Effort | Tier | Reasoning |
|---|---|---|---|---|---|---|
| 1 | Help menu content | **missing** - no `CommandGroup(replacing: .help)`; default item likely dead-ends | H | S | **v1.0 must** | Reviewers and users both click it; 5.1.1(i) needs an in-app privacy-policy link and 1.5 needs a contact path, both naturally live here. |
| 2 | About window | **partial** - standard panel, version 0.1.0, no links (`Project.swift:109-115`) | M | S | **v1.0 must** | Fix version to 1.0 / build from CI, add credits (website, support, privacy, acknowledgements) via `orderFrontStandardAboutPanel(options:)` or a `Credits.rtf`. Near-free. |
| 3 | What's New on update | **missing** | M | S | **v1.0 nice** (mechanism), sheet from 1.1 | Nothing is "new" at 1.0. Ship a Release Notes link plus the last-seen-version check so 1.1 can show a sheet. Never show it while a show is running or resuming. |
| 4 | Onboarding / first run | **partial** - library chooser (`SegueRootView.swift:37-114`) | H | M | **v1.0 must** (small) | Keep the chooser; after it, a one-screen "Welcome" with 3 cards (songs are ChordPro files, build a set, play on stage with keys) and "Add sample songs". Re-openable from Help > Getting Started. No multi-page tour. |
| 5 | Empty states + sample content | **partial** - good empty states, no samples (`LibraryViews.swift:117-133`) | H | S-M | **v1.0 must** | A new user (and the App Reviewer) needs songs to try the editor and stage mode. Opt-in "Add Sample Songs" (3 public-domain songs + 1 sample setlist) written as real `.cho` files, never auto-seeded into a user's existing folder. Lyrics must be verifiably public domain. |
| 6 | TipKit discovery | **missing** | M | S-M | **v1.0 nice** | 3-4 tips: drag a chord in the visual editor, `?` on stage, request queue (Q), Gig Mode Shortcut setup. Never on the stage window. Cheap and on-HIG. |
| 8 | Keyboard shortcut cheat sheet | **partial** - status line hint (`StageChrome.swift:266-275`) | **H** | S-M | **v1.0 must** | Stage mode is keyboard/pedal-driven. A `?` overlay on stage generated from the live `InputBindingTable` (so custom bindings show truly), plus Help > Keyboard Shortcuts window for the main window. |
| 9 | App Store review prompt | **missing** | M | S | **v1.0 must** | Free ratings matter for a new free app. Rules in section 5. |
| 10 | Settings structure | **partial** - one "Live" pane (`LiveSettingsView.swift:13-23`) | M | S-M | **v1.0 must** | Add General (library) and Privacy panes; see section 5. No Appearance pane (HIG: respect system). |
| 11 | Feedback + bug report with diagnostics | **missing** | H | M | **v1.0 must** | Solo dev, no support desk: this is the support channel. Transport per sibling doc; UX here. |
| 12 | Sync / backup status | **missing** (no sync in v1) | M | S | **v1.0 nice** | Settings > General shows the library path, "Show in Finder", and a one-liner "Your songs are plain files; Time Machine backs them up". |
| 13 | Data portability / export | **partial** - data is already open files (.cho + JSON); no in-app export | M | S (archive) / L (PDF, phase 4) | **v1.0 nice**: "Export Library Archive…" (zip). PDF stays phase 4 | Open files already beat OnSong/forScore here; say so in the UI and listing. |
| 14 | Accessibility | **partial** - 38 labels, Reduce Motion, AA contrast | M | M | **v1.0 must** (audit) | Run a VoiceOver + Full Keyboard Access pass on library, editor, builder, stage; then declare honest Nutrition Labels (Dark Interface, Sufficient Contrast, Reduced Motion likely; VoiceOver only if the visual editor canvas is usable). |
| 15 | Localisation | **missing** (English only by decision) | L | S (catalog) / L (translate) | post-launch | Add an empty String Catalog later; no translations for 1.0. |
| 17 | Menu bar extra | **missing** | L | M | post-launch | Must stay out of the way while performing: the stage owns the screen. |
| 18 | Services menu | system default only | L | S | post-launch | "New Segue Song from Selection" is a cute fit with phase 3 paste cleanup. |
| 19 | Drag and drop | **partial** - builder only (`BuilderLibraryColumn.swift:61`) | **H** | M | **v1.0 must** (drop-in import) | Drag `.cho`/`.txt` from Finder onto the library to copy them in, and drag a song out to Finder/Mail as its `.cho`. This is also the minimum in-app import path (see decisions). |
| 20 | Quick Look preview / thumbnail for .cho | **missing** | M | M-L | post-launch | Needs a QL extension target (separate process, sandbox); nice differentiator; no Mac ChordPro app ships one that was found. |
| 22 | Document icons + UTType | **missing** (`Project.swift:109-115`) | M | S-M | **v1.0 nice** | Import `.cho`/`.chordpro`/`.chopro` as UTTypes conforming to `public.plain-text`, role Viewer; "Open With Segue" imports into the library. Keep `.cho` editable by other apps (do not claim Owner). |
| 23 | Handoff | **missing** | L | M | post-launch | Pick up the open song or setlist on another Mac. |
| 24 | Window / state restoration | **partial** - system window restoration; no `@SceneStorage`; strong show crash-resume (`AppModel+Shows.swift:13-28`) | M | S | **v1.0 nice** | Restore sidebar section and selected song/setlist. |
| 25 | Full keyboard navigation | **partial** - stage yes; main window lacks menu commands for Start Show / Rehearse / New Setlist | H | S | **v1.0 must** | HIG: commands belong in the menu bar. Add a **Setlist** menu: New Setlist Shift-Cmd-N, Start Show Cmd-Return, Rehearse Opt-Cmd-Return, Add Song to Setlist. |
| 26 | Undo everywhere | **partial** - editor only; setlist edits, metadata, deletes not undoable | M | M | **v1.0 nice** (setlist builder undo) | Rehearsal-time reorders are fiddly; Cmd-Z expected. |
| 26b | Deletes go to Trash | **missing** - permanent `removeItem` (`SetlistStore.swift:245`, `ShowStore.swift:230`) | **H** | S | **v1.0 must** | A deleted setlist the night before a gig must be recoverable. `FileManager.trashItem` keeps the files-canonical model and works in the sandbox for user-selected folders (UNVERIFIED for the bookmark scope; test). |
| 26c | Song delete in-app | **missing** | H | S | **v1.0 must** | Basic library hygiene; Move to Trash with confirmation, removes sidecar too; setlists that reference it show it as missing (existing behaviour). |
| 27 | Autosave and versions | **missing by design** - explicit Save + guards (`UnsavedChangesGuard.swift:63-74`) | M | M | post-launch (decision) | Explicit save fits the external-edit conflict model; the quit/navigate guards cover data loss. |
| 28 | Error presentation | **exists** (banner + `UserMessage` + conflict alerts) | M | S | **v1.0 nice**: add "Report…" on the banner | Wire errors into the feedback form with the error pre-attached. |
| 29 | Offline behaviour | **exists** (local-only) | H | - | done | Say "works fully offline" in the listing; the only network calls will be feedback/analytics, which must fail silently on stage. |
| 30 | Performance (launch) | unmeasured | M | S | **v1.0 nice** | Add an `XCTApplicationLaunchMetric` test and a large-library (500 songs) index timing once; publish a number to beat. |
| 31 | Acknowledgements view | **exists** (`AcknowledgementsView.swift:26-48`) | L | S | done; keep current | Also link it from About. Add any SDK the sibling doc adopts. |
| 32 | Show in Finder | **missing** | M | S | **v1.0 nice** | Files-canonical app: "Show in Finder" on songs and setlists, and on the library in Settings. |

---

## 5. Proposed v1.0 production surface

### 5.1 Menu bar

**Segue (App menu)**: About Segue · *separator* · Settings… (Cmd-,) · *separator* · Services · Hide / Hide Others / Show All · Quit Segue. Move "Acknowledgements" out of the App menu into Help and the About panel (the HIG App-menu list has no slot for it).

**File**: New Song (Cmd-N) · New Setlist (Shift-Cmd-N) · *separator* · Import Songs… (Shift-Cmd-I) · Export Library Archive… *(nice)* · *separator* · Show in Finder (Opt-Cmd-R) · Move to Trash (Cmd-Delete) · Close (Cmd-W) · Save (Cmd-S).

**Setlist** (new, replaces nothing): Start Show (Cmd-Return) · Rehearse (Opt-Cmd-Return) · Add Selected Song to Setlist ▸.

**Library** (existing): Refresh · Rebuild Index · Choose Library Folder…

**Help** (`CommandGroup(replacing: .help)`), kept to 8 items as the HIG asks:
1. Segue Help - opens the docs page on the landing site (see `05-landing-page.md`). A bundled Help Book is post-launch.
2. Getting Started - reopens the welcome screen (with Add Sample Songs).
3. Keyboard Shortcuts (Cmd-/) - window with main-window and stage tables; stage table generated from the binding table.
4. *separator*
5. What's New in Segue / Release Notes - web release notes for 1.0; in-app sheet from 1.1.
6. Send Feedback… - one form, category picker: Question, Idea, Problem. (Linear/Raycast pattern.)
7. Report a Problem… - same form opened on "Problem" with diagnostics section expanded.
8. *separator*
9. Rate Segue on the App Store - opens `…?action=write-review` (user-initiated, allowed).
10. Privacy Policy - satisfies 5.1.1(i) "within the app".
11. Acknowledgements.

(If 11 feels long, fold 6 and 7 into one "Send Feedback…" and drop 9; that is a decision below.)

### 5.2 Settings (toolbar panes, title follows pane, restore last pane)

- **General**: Library folder (path, Change…, Show in Finder) · "Songs are plain ChordPro files. Back them up like any folder (Time Machine works)." · Rebuild Index button (duplicate of the menu, harmless). *(Later: default instrument/tuning, editor default mode.)*
- **Live** (existing, unchanged): min lyric size, default columns, Gig Mode Shortcuts, pre-show checklist.
- **Privacy**: "Share anonymous usage statistics" toggle and "Send crash reports" toggle *only if* the sibling doc adopts them, defaulting off or asked once (5.1.1(ii) consent); "What is sent" disclosure; Privacy Policy link. If nothing is collected, this pane collapses to a statement ("Segue collects nothing; feedback you send includes only what you preview") and could live in General.
- No Appearance pane (follow system; stage is always dark). No Advanced pane until there is something to put in it. No "Reset" for 1.0 beyond what exists (library folder is user-owned; index rebuild covers corruption).

### 5.3 About

Standard About panel with: name, "Version 1.0 (build N)", copyright, and a Credits block: website · support/feedback · privacy policy · "Built with open-source software - Acknowledgements". Keep the taped-setlist icon. No custom window needed.

### 5.4 What's New

- 1.0: Help > What's New opens the web release notes.
- From 1.1: store `lastSeenVersion`; on first launch of a new minor version show a small sheet (3 bullets max, one image optional) **only on the library window, never on stage, never while a resume prompt is pending, and never on the very first install**. Dismiss forever with Continue; reachable again from Help.

### 5.5 Feedback entry points (UX only; transport per sibling doc)

- Help > Send Feedback… / Report a Problem…
- Error banner: a "Report…" button beside Dismiss that opens the form with the error text pre-filled.
- Crash-resume prompt: after "Resume" or "End Show", a small secondary link "Tell us what happened" (never a modal on the way back to stage).
- Gig log: nothing. No prompts after shows.
- **Form**: category (Question / Idea / Problem) · message · optional email · "Include diagnostics" disclosure listing exactly what is attached: app version/build, macOS version, Mac model, library counts (songs, setlists, skipped files), recent Segue log lines (OSLogStore, current process only), and optionally the current song file (off by default, because lyrics are personal) · Preview before Send (Mimestream pattern) · works offline by queueing or falling back to a pre-filled email.
- Feature requests: an "Idea" submission plus a "See and vote on ideas" link to the board if the sibling doc picks one.

### 5.6 Review prompt rules

Call `requestReview` only when all hold:
- the user has **ended at least 3 gigs** (not rehearsals) in total, the most recent one is the trigger;
- it is shown **after the end-of-show flow is fully done** (reorder diff resolved, gig log entry saved, stage closed) and the library window has been frontmost for ~3 seconds;
- not prompted for this version yet; at least 14 days since first launch and since the last prompt;
- no unsaved edits, no error banner, no pending resume.
Never on launch, never from a button, never on stage. Plus the persistent "Rate Segue on the App Store" Help item. Note it does nothing in TestFlight, so test in a dev build.

### 5.7 First run and empty states

1. **Library chooser** (exists) - keep.
2. **Welcome sheet** (new, once): three short cards (Write or drop in songs · Build a setlist · Play on stage: arrows, Cmd-K, `?`) and two buttons: "Add Sample Songs" (secondary) and "Start" (default). Re-openable from Help > Getting Started.
3. **Empty library** (exists): add "Import Songs…" and "Add Sample Songs" beside New Song, and the line "or drop ChordPro files here".
4. **Empty setlists sidebar**: a one-line hint under "New Setlist": "Build a set, then press Start Show."
5. **Empty gig log** (exists) - fine.
6. **Stage first use**: a TipKit-style hint "Press ? for all keys" shown once, at show start only, fading before the first song is needed (or only in rehearsal runs - decision).

---

## 6. Summary lists

**v1.0 must** (est. total ~8-11 dev days)
- Help menu with real items (S)
- About credits + version (S)
- Setlist menu with Start Show / Rehearse / New Setlist shortcuts (S)
- Keyboard shortcut cheat sheet: stage `?` overlay + Help window (S-M)
- Welcome sheet + opt-in sample songs/setlist (M)
- Import: Finder drop + Import Songs… (copy into library) and drag out (M)
- Song delete; all deletes to Trash (S)
- Settings: General + Privacy panes (S-M)
- Feedback / Report a Problem form with diagnostics preview (M; transport sibling)
- Review prompt with gating rules (S)
- Accessibility pass + honest Nutrition Labels (M)

**v1.0 nice**: TipKit tips (S-M), What's New mechanism (S), UTType/document icon + Open With (S-M), Export Library Archive (S), state restoration via SceneStorage (S), setlist builder undo (M), "Report…" on error banner (S), Show in Finder (S), launch-time metric (S).

**Post-launch**: Quick Look extension, Services, localisation, Handoff, autosave, menu bar extra, bundled Help Book.

---

## 7. Decisions for Ryan

1. **In-app import for 1.0?** Pulling a minimal "copy ChordPro/text files into the library" (no AI cleanup) forward from phase 3. Recommended yes; without it a new user's only path is Finder + Refresh, and a reviewer sees an empty app.
2. **Song delete + Trash for all deletes** in 1.0 (recommended yes).
3. **Sample songs**: opt-in button (recommended) vs auto-seed on "Create Library"; and which public-domain songs (needs a PD check; one romanized-Hindi traditional song would show off search).
4. **Help docs**: web page on the landing site (recommended for 1.0) vs bundled Help Book (searchable from the Help menu, M effort).
5. **Help menu size**: full 11-line list vs merged single "Send Feedback…" and no Rate item.
6. **Analytics consent UX** (if the sibling doc adopts analytics): opt-in toggle in Settings only, default off (simplest, clearly 5.1.1(ii)-safe) vs a one-time ask on the welcome sheet.
7. **Diagnostics**: may the bug report offer to attach the current song file (off by default)? Lyrics are personal content.
8. **Review prompt threshold**: 3 completed gigs (recommended) vs a lower bar (e.g. first gig) to collect ratings faster.
9. **Autosave**: keep explicit Save for 1.0 (recommended) or switch to autosave now.
10. **Stage "Press ? for keys" hint**: shown once at first show start, or only in rehearsal runs (safer).
11. **Terms of use**: rely on Apple's standard EULA (recommended for a free app, no Terms item) vs a custom terms page.
