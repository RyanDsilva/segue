# P9-5 - Mac polish: Help Book, Services, Handoff, menu bar extra, localisation

Phase 9 workstream (new, 2026-10-31). Ruling: `docs/release/decisions.md` **R176** (the first App Store release is v1.0 and, before submission, also builds "the Mac polish list (Services menu, localisation, Handoff, menu bar extra, Help Book), each specced with its open questions closed first"), restating **R170**'s roadmap entry. The candidate list and its first tiering are `docs/release/research/08-polish-features.md` (sections 1.2, 4 and 6: all five were "post-launch" there; R176 pulls them into v1.0). Built on: **R109** (nothing about paste or import may disturb the live view; every route into the review sheet is disabled during a show), **R161** (audio never plays in a Live show), **R126** (the user guide at `segue.ryandsilva.dev/guide`, Astro Starlight, in-app Help buttons open guide pages), **R8** (one listing localisation, English U.S.), **R39** (design directions before new UI), **R113** (test budget), **R11** (two bundle IDs: App Store `dev.ryandsilva.segue`, Personal `dev.ryandsilva.segue.personal`), and the product language rules in `docs/decisions.md:83-93` (English + romanized Hindi content only, no Devanagari display, no auto-transliteration, lyric preservation, autocorrect off in lyric text). Related research in flight: `docs/research/phase9-icloud-sync.md` (optional iCloud sync between the owner's Macs, R176; being written), which decides how much Handoff can rely on both Macs holding the same library.

**This spec has open questions (section 15). Close them before P9-5a starts.** Each has a recommendation.

**Build order:** five sessions (section 13). **P9-5a** (Help Book) may start once section 15 is closed: it touches the guide build, the Help menu and `GuideHelp.swift` only. **P9-5b** (Services) and **P9-5c** (Handoff) are independent of each other and of P9-5a. **P9-5d** (menu bar extra) starts with its design step 0 and needs Ryan's pick before step 2. **P9-5e** (localisation) runs **last in the Phase 9 wave**, after the sibling P9 workstreams (PDF export, Singer view, Medleys, LRCLIB) have landed their UI, because it sweeps every SegueUI view file and would otherwise conflict with them; until then, new P9 code follows the string rules in section 7.4 so the sweep finds less to do. Index: a `README.md` in this folder (owned by the orchestrator, not this workstream).

## Session rules (apply to every session)

- `cat` and `ls` are aliased to eza and can hang: use `command cat` / `command ls` or the Read / Grep / Glob tools, and pass this warning to any subagent. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-". Ignore `.build/`.
- Sibling P9 workstreams edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, stage only your own hunks, keep the tree compiling between steps. `docs/release/walkthrough.md` and the guide sidebar (`guide/astro.config.mjs`) are shared: edit them hunk by hunk, never by overwriting the file.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget (R113): per step only targeted in-process suites (`swift test --filter <Suite>`); tricky pure logic (tonight's setlist pick, the Handoff payload, the selection-to-lines splitter, the anchor map) gets table-driven in-process tests; UI behaviour gets in-process SegueUI tests. Exactly **one** new XCUITest class for the workstream (section 12.4), grown one test per session that needs it. At the end of each session ONE `make quick`, plus ONE `make e2e-one` per UI test class the session added or changed. No `make gate`, no `make check`, no E2E retry loops (a failure is investigated, not re-run), no scratch-worktree builds. Every build or test runs under `lockf -k .build/make.lock`. Write this budget into any subagent's prompt.
- Before using any Apple API not already in the codebase, run the `apple-api-check` skill. The APIs named below were checked on 2026-10-31 against MacOSX27.0.sdk (Xcode 27.1) at the project's deployment target macOS 26.0 (`Project.swift:48`): SwiftUI declarations with `sdk-api.sh`, AppKit / Foundation Objective-C declarations in the SDK headers, and a `typecheck.sh -t 26.0` probe that compiled every call in sections 3-7 with no warnings. Behaviour marked **UNVERIFIED** is checked in the step 0 spikes.
- Ryan's real library is never opened by a test or a session.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency, including any section 15 question still open when a step reaches it.

## 1. Goal

Segue works well inside its own window. A gigging musician lives in other apps too: the band's group chat where tonight's set list arrives as a text, Safari where a chord sheet is found, a second Mac at home or at the venue, a menu bar that is always there, and a venue with no Wi-Fi where the online guide will not load. After P9-5:

- **Help works offline.** Help > Segue Help opens a built-in Apple Help Book generated from the same guide source as the website, searchable from the Help menu's search field, so a question at a venue with no signal still gets an answer.
- **Other apps can hand Segue text.** Select a chord sheet anywhere and choose Services > New Segue Song from Selection: the paste review opens on it. Select a set list in Messages and choose New Segue Setlist from Selection: a new setlist is built from it with the set composer's matching.
- **Pick up on the other Mac.** The song or setlist open on one Mac appears as a Handoff icon on the other Mac's Dock; clicking it opens the same song or setlist there.
- **Tonight is one click away.** An optional menu bar extra shows tonight's setlist and starts the usual pre-show flow (never the stage directly), and gets out of the way entirely while a show runs.
- **The app speaks the owner's audience's language.** All UI strings move into String Catalogs, and a second UI language ships (section 7; which one is Q1), while song content - titles, lyrics, chord names, section labels, romanized Hindi - is shown exactly as written in every language.

**In scope:** the five R176 items above; the analytics rows for them (section 9); their guide pages (section 10); the Help menu and Help button rewiring; Info.plist keys (`NSServices`, `NSUserActivityTypes`, `CFBundleHelpBookFolder`, `CFBundleHelpBookName`, `CFBundleLocalizations` via the catalogs); the proposals in section 8 that Ryan accepts (Q19).

**Unchanged:** the website guide (still built and deployed as today; the Help Book is a second output of the same source); the stage, its keys and its window; the paste review and the set composer's logic (Services feed them, they are not changed); the App Store listing localisation (R8, English U.S.); entitlements (no item needs a new one, section 11).

## 2. Current behaviour (verified 2026-10-31)

### 2.1 Scenes, menus and the app delegate

- Scenes: one `Window("Segue Library")` with `.commandsRemoved()` and `SegueCommands`, a `Keyboard Shortcuts` window, and `Settings` (`App/Sources/SegueApp.swift:247-273`). No `MenuBarExtra`.
- `SegueCommands` composes App, File, Library, Song, Setlist, Live, Window and Help menus (`Packages/SegueUI/Sources/SegueUI/App/Commands/SegueCommands.swift:16-25`); `isMainWindowBusy` lists the sheets and prompts commands must wait behind (`:31-37`).
- The app delegate is `SegueAppDelegate` (`Packages/SegueUI/Sources/SegueUI/Editor/PendingEditsGuard.swift:84`), extended for Finder's Open With in `App/OpenDocuments.swift:33-39`. One Segue per user session (`App/SingleInstance.swift:5-32`).
- Settings panes: General, Appearance, Instrument, Audio, Live, AI, Privacy, Data (`Settings/SegueSettingsView.swift:17-26`); General lives in `Settings/GeneralSettingsView.swift`.

### 2.2 Help today

- The Help menu replaces the system group (`App/Commands/HelpCommands.swift:16-31`): Segue Help (Cmd-?, `MenuShortcuts.swift:156`) opens `SegueLinks.help`, the web guide (`HelpCommands.swift:79-84`, `SegueLinks.swift:11`); Keyboard Shortcuts (Cmd-/); Welcome to Segue...; What's New; Report a Problem...; Request a Feature...; Rate (once the App Store ID exists); Privacy Policy; Terms of Use (`HelpCommands.swift:76-148`). Only Welcome and What's New are `disabledWhilePerforming`.
- In-app Help buttons and tips open guide pages in the browser through `OpenGuideAction` (`App/GuideHelp.swift:11-52`); the pages and anchors are the closed enum `SegueLinks.Guide` (`SegueLinks.swift:51-103`), each raw value resolved against the built guide by `gen-site.swift --check`.
- The guide: Astro Starlight in `guide/`, 30 pages in `guide/src/content/docs/`, sidebar in `guide/astro.config.mjs:9-55`, base `/guide`, built into `website/guide` (`astro.config.mjs:57-62`), Pagefind search on, absolute asset URLs (`guide/scripts/postbuild.mjs:1-3`). Built size 6.7 MB (shots 4.3 MB, clips 0.9 MB, Pagefind 0.7 MB). `make guide` / `guide-check` (`Makefile:81-90`).
- No Help Book in the bundle; no `CFBundleHelpBookFolder` in `appInfoPlist` (`Project.swift:103-157`).
- **Observed on this Mac (macOS 26.6.2):** there is no standalone Help Viewer app. `/System/Applications/Tips.app` has bundle ID `com.apple.helpviewer`, declares the `help:` URL scheme and the `com.apple.help` (`.help`) document type, and carries `PlugIns/HelpViewer-Quicklook.appex`. So on macOS 26 a Help Book opens in Tips. Skim (`/Applications/Skim.app/Contents/Resources/Skim.help`) is a local third-party book to compare against in the spike.

### 2.3 Text from other apps

- Paste today: File > New Song from Clipboard reads the clipboard only when asked (`App/AppModel+Paste.swift:33-50`), into `LibraryViewModel.beginPasteReview(text:source:)` (`Paste/LibraryViewModel+Paste.swift:38-46`), refused while `canPaste` is false (`:19-23`, "Paste is unavailable while a show is running", R109). `PasteSource` is `clipboard`, `newSong`, `emptyState`, `listPaste` (`SegueCore/Sources/Services/AnalyticsEvent+AI.swift:42-50`).
- Finder's Open With already has the queue pattern Services need: requests wait in `pendingOpenURLs` until the library is open, the Welcome flow is over and no show is on stage or starting, then run (`App/OpenDocuments.swift:47-63`; the field at `App/AppModel.swift:170-171`).
- The set composer parses one typed line (`SegueCore/Sources/Setlists/SetComposerLine.swift:9-19`: a song query with an optional key, `---` for a break, the user's spelling kept) and resolves it against the library (`Setlists/SetComposer.swift:5-18`, at most five ranked matches, romanized-Hindi tolerant via `RomanNormalizer`).
- No `NSServices` key, no `servicesProvider`.

### 2.4 Identity and restoration (what Handoff can carry)

- A song's identity is a ULID in its sidecar, unchanged by renames (`SegueCore/Sources/Library/SongRecord.swift:5-28`); setlists have `SetlistID` ULIDs and an optional `date: CalendarDay` and `venue` (`Setlists/Setlist.swift:289-299`).
- `SessionRestore` keeps the sidebar section ("library", "setlist:<ULID>", ...), selected song and gig per library, keyed by the SHA-256 of the root path (`App/SessionRestore.swift:9-33`, `:70-78`). The editor autosaves ("autosave means nothing is lost", `:10`).
- No `NSUserActivity` anywhere, no `NSUserActivityTypes`.

### 2.5 The stage and what must never interrupt it

- `AppModel.live` non-nil means a show (gig or rehearsal) is up; `isPerforming` (`App/AppModel.swift:442-444`); `isStartingShow` blocks a second start (`:431-440`); setting `live` already gates the AI, sound and tips (`:175-184`).
- The stage is a borderless window covering the screen, made key, with `NSApp.presentationOptions = [.hideDock, .hideMenuBar]` (`Live/StageWindowController.swift:40-87`, `:131-137`). On a second display the menu bar is still visible. Stage keys come from a local key monitor on the stage window (`Live/LiveKeyInput.swift`), so **any other Segue window or panel that becomes key steals pedal and keyboard input from the stage**.
- `startShow` refreshes the library, builds the pre-show checklist and only then presents the stage (`App/AppModel+Shows.swift:91-130`).

### 2.6 Localisation today

- `developmentRegion: "en"` (`Project.swift:404`), `CFBundleDevelopmentRegion` from `DEVELOPMENT_LANGUAGE` (`Project.swift:104`). No `.xcstrings` file anywhere in the repo, no `defaultLocalization` in `Packages/SegueUI/Package.swift:13-47` or SegueCore's manifest, no `String(localized:)` or `LocalizedStringResource` in either package.
- About 800 string literals in SwiftUI initialisers across 368 SegueUI source files (`Text(`, `Button(`, `Label(`, `Toggle(`, `Section(`, `Picker(`, `Menu(`, `.help(`, `navigationTitle(`), only 4 `verbatim:` uses. Several menus build titles as plain `String` values (for example `HelpMenuItem.title: String`, `HelpCommands.swift:52`, rendered by `Button(item.title)` at `:21`), which SwiftUI treats as verbatim and would never localise.
- In a Swift package, `Text("Start Show")` looks the key up in `Bundle.main`, not in the package's own bundle. The `#bundle` macro (Foundation, macOS 12+, confirmed in the SDK) gives the package bundle.
- macOS's own localisations on this Mac include `hi.lproj` (Devanagari Hindi) and no Latin-script Hindi (`/System/Library/Frameworks/AppKit.framework/Resources/`, `Notes.app`).
- Tools present: `xcrun xcstringstool` (`extract`, `sync`, `compile`, `generate-symbols`); the Xcode MCP server offers `LocalizationPlanner`, `StringCatalogRead`, `StringCatalogEdit` and `StringCatalogContext` (with its translation skills) for P9-5e.

### 2.7 Analytics

- The closed vocabulary is `AnalyticsEvent` (`SegueCore/Sources/Services/AnalyticsEvent.swift:14-95`, rows 1-30, no `String` payloads), `FeatureKey` (`Services/FeatureKey.swift:5-87`), `HelpItem` (`AnalyticsEvent.swift:245-253`), `SetlistSource` (`:217-221`). Documented in `docs/release/specs/WS3-services.md` section 5 (rows up to 30 at `:319-321`). Help menu items record `helpOpened` (`HelpCommands.swift:22-24`).

## 3. Help Book (P9-5a)

### 3.1 Why it helps a gigging musician

Gigs happen in basements, temples, wedding halls and pubs with no signal. The web guide is useless there; a bundled book answers "how do I turn on the metronome" or "why did my Shortcut not run" offline, and the Help menu's search field finds both guide pages and menu items in one box (HIG, The menu bar: "When you use the Help Book format... macOS automatically includes a search field").

### 3.2 Behaviour and UI

- **Help > Segue Help (Cmd-?)** opens the bundled book's home page in Tips (the macOS 26 Help Viewer, 2.2). Same title, same shortcut, same position.
- **Help menu search**: typing "metronome" in Help's search field lists the matching Help Book topics under "Help Topics" beside the menu items.
- **In-app Help buttons and tip "Learn More"** (`GuideHelpButton`, `GuideTipAction`) open the matching **anchor** in the book instead of the browser. The `SegueLinks.Guide` enum stays the single list; it gains a computed `helpAnchor` (page slug, or `slug#id` flattened to `slug-id`, section 3.4).
- **The online guide stays reachable**: every book page's footer reads "Read this guide online" (the page's web URL), and the book's home page says which app version it describes. The Help menu does not grow an extra item (HIG: keep it short).
- **Fallback**: if the book cannot be opened (`NSHelpManager` registration fails, or a test build without the book), Segue opens the web page for the same `SegueLinks.Guide` case, so a Help button is never dead. The fallback is logged once (OSLog), not shown.
- **While performing** (`isPerforming` or `isStartingShow`): Segue Help, every Help button and Learn More are disabled or no-ops, because opening Tips makes another app key and the stage loses its keys (2.5). `HelpMenuItem` for Segue Help gets `disabledWhilePerforming: true`; Keyboard Shortcuts stays enabled (an in-app window, but it must not become key over the stage either: it is also disabled while performing; the stage has its own `?` overlay). The Help menu is unreachable on the stage's screen anyway (menu bar hidden), so this guards the shortcut and the second display.

### 3.3 Building the book from the guide

One source, two outputs. `make help-book` builds the same `guide/src/content/docs` pages a second time in a help mode and packages them:

1. `HELP_BOOK=1 astro build` with a help-mode config branch in `guide/astro.config.mjs`: `base: '/'`, `outDir: '../Derived/HelpBook/site'`, Pagefind off (Help Viewer indexes the book itself), the sidebar and pages unchanged, the theme following the system (Tips renders in light and dark: spike 0 checks `prefers-color-scheme`). No analytics, no external fonts or scripts.
2. `guide/scripts/helpbook.mjs` post-processes the output: rewrites every absolute `/...` URL to a relative one (Help Viewer loads `file:` URLs inside the bundle), turns each heading `id` and each page into an Apple Help anchor (`<a name="slug-id"></a>` before the heading; `<a name="slug"></a>` at the top of each page), adds `<meta name="AppleTitle" content="Segue Help">` to the home page and `<meta name="robots" content="anchors">` to every page (**UNVERIFIED** for macOS 26 Tips; spike 0), and the "Read this guide online" footer with the page's `https://segue.ryandsilva.dev/guide/...` URL. Links to site pages outside the guide (`/privacy`, `/support`, `/changelog`, `/feedback`) become absolute web URLs.
3. Packages `Segue.help`: `Contents/Info.plist` (`CFBundleIdentifier` `dev.ryandsilva.segue.help`, `CFBundleDevelopmentRegion` `en`, `HPDBookAccessPath` `index.html`, `HPDBookIndexPath` `Segue.helpindex`, `HPDBookTitle` `Segue Help`, `HPDBookType` `3`, `CFBundlePackageType` `BNDL`; keys **UNVERIFIED** against current Apple documentation, which is archived: spike 0 compares with `Skim.help`'s Info.plist), `Contents/Resources/en.lproj/` with the site, and the search index built with `hiutil -I lsm -Caf Segue.helpindex en.lproj` (`/usr/bin/hiutil` is present; exact flags from `hiutil -h` in the spike).
4. Output `Derived/HelpBook/Segue.help` (gitignored, like `Derived/`). `Project.swift` adds it to both app targets' resources and adds `CFBundleHelpBookFolder: "Segue.help"` and `CFBundleHelpBookName: "dev.ryandsilva.segue.help"` to `appInfoPlist`. `make build` and the release scripts depend on `help-book`; the Xcode build itself never runs Node (a build phase only checks the folder exists and fails with "run make help-book" otherwise).
5. **Staleness**: `help-book` writes `Derived/HelpBook/source.sha256` (hash of `guide/src/**`, `guide/public/**`, `astro.config.mjs`, `helpbook.mjs`); `make quick` fails if it does not match the sources, and `scripts/verify-archive.sh` checks the archived app contains `Segue.help` with every `SegueLinks.Guide.helpAnchor` present in the book.

Size: about 6 MB (shots and clips kept, Pagefind dropped; Q16). The book documents the App Store flavour, as the guide does today; Personal-only features (LRCLIB) are not in it.

### 3.4 Opening it (APIs)

- `NSApp.showHelp(nil)` for Help > Segue Help (AppKit `NSApplication`; compiled at 26.0). `NSHelpManager.shared.openHelpAnchor(_:inBook:)` for anchors, the book name read from `CFBundleHelpBookName` (`NSHelpManager.h:37`, no deprecation in the SDK header). `NSHelpManager.shared.registerBooks(in:)` is not needed: the main bundle registers itself (`NSHelpManager.h:40`).
- `OpenGuideAction` gains a book route: `guideLinks(_:)` (`GuideHelp.swift:30-32`) builds an action that tries the anchor and falls back to `workspace.open(page.url)`. The help routing lives in a new `App/HelpBook.swift` behind a small protocol (`HelpBookOpening`: `openHome()`, `open(anchor:) -> Bool`) so tests inject a recorder; the live one wraps `NSHelpManager`.
- Anchor names: `SegueLinks.Guide.helpAnchor` maps `https://segue.ryandsilva.dev/guide/go-on-stage#checklist` to `go-on-stage-checklist`, the home to `index`. `gen-site.swift --check` is extended to resolve every `helpAnchor` against `Derived/HelpBook` when it exists.

### 3.5 App Store implications

- A Help Book is ordinary bundled content; no entitlement, no review risk. It also removes the "Help isn't available" class of reviewer impression for good (research 08, section 2).
- It must match the App Store build: the guide already documents that flavour. The book is versioned with the app (its home page names the version), so a reviewer never reads about a feature the build lacks.
- 5.1.1(i) is unchanged: Privacy Policy stays a Help menu item opening the web page.

## 4. Services (P9-5b)

### 4.1 Why it helps a gigging musician

Charts and set lists arrive everywhere except in Segue: a chord sheet in Safari, a WhatsApp or Messages thread from the band leader with tonight's order, a Notes page of requests. Services turn "select, copy, switch to Segue, File > New Song from Clipboard" into one menu choice from where the text already is, and turn a texted set list into a real setlist in seconds - the step most likely to be rushed an hour before the gig.

### 4.2 Behaviour and UI

Two services, both in the system Services menu (app menu > Services, and the text context menu's Services submenu) whenever text is selected in any app:

1. **New Segue Song from Selection** (Q6 names it). Segue comes forward (launching if needed), the Library section shows, and the paste review opens on the selected text with `PasteSource.service`, exactly as New Song from Clipboard does: the same deterministic parser, the same AI refinement and lyric-preservation rule, the same near-duplicate warning, nothing written until Accept. The pasteboard is read inside the service call only; Segue never reads the general clipboard for this.
2. **New Segue Setlist from Selection** (proposal, Q7). The selection is split into lines (section 4.3); each line goes through `SetComposerLine.parse` and `SetComposer.resolve` unchanged. Segue creates a new setlist named "Set from <app name, else 'selection'> <date>" (renamable at once, the name field focused), opens its builder and shows a review strip above the entries: "12 lines: 10 matched, 2 need a pick". Matched lines are entries (with their parsed gig key); unmatched lines stay as composer rows with their candidates, just as if typed; a `---` line becomes a break. Nothing is saved until the first edit or "Keep Setlist"; "Discard" removes it. Romanized Hindi lines are matched through `RomanNormalizer` and never rewritten.

Rules for both:

- **Empty or whitespace-only selection**: Segue does not come forward; the service returns an error string ("There's no text in the selection."), which macOS shows in its standard alert (**UNVERIFIED** how macOS 26 presents a service's error; spike 0).
- **Too long**: more than 64 KB of text (a chart is 2-8 KB) is refused the same way with "That selection is too long to be one song." / "...one setlist.".
- **No library yet, or the Welcome flow is up**: the request is queued (in memory, like `pendingOpenURLs`) and runs when the library opens.
- **While performing, starting a show, or with the pre-show checklist, a resume prompt or a reorder review up** (`isPerforming`, `isStartingShow`, `isMainWindowBusy`): the request is queued, Segue does **not** activate, no window moves, and the stage keeps the keyboard. When the show ends and the end-of-show flow is done, queued requests run one at a time, and a quiet flash says "1 song waiting from Safari" before the first opens (the source app name from the service's pasteboard owner is never recorded in analytics).
- **Another review already open** (`canPaste` false): the request waits behind it and opens when it closes.
- Several quick invocations queue in order; at most 10 are held, the 11th is refused with "Segue already has 10 selections waiting.".

### 4.3 Lines from a selection (SegueCore, pure)

`Setlists/SelectionLines.swift`: `SelectionLines.split(_ text: String) -> [String]` normalises line endings (CR, CRLF, U+2028), drops blank lines, trims each line, and strips list furniture only at the start of a line: `1.`, `1)`, `#1`, `-`, `*`, `•`, `·`, `>` and emoji bullets, then a run of spaces. A line that is only dashes (`---`, a long dash) stays as the break line `SetComposerLine` already parses. Headers such as `Set 1`, `Set 2:`, `Second set` become a break (Q7 confirms). Trailing durations and notes in parentheses stay in the line for the composer's key parse to accept or ignore. Nothing else is changed: spelling, case and romanized Hindi words pass through byte for byte.

### 4.4 APIs and Info.plist

- `appInfoPlist` gains `NSServices`, one dictionary per service: `NSMenuItem` (`default`: the title), `NSMessage` (`newSongFromSelection`, `newSetlistFromSelection`), `NSPortName` `Segue`, `NSSendTypes` `[public.utf8-plain-text]`, no `NSReturnTypes`, and `NSRequiredContext` `{}` so the services are enabled by default (**UNVERIFIED** that an empty context still enables a service on macOS 26; spike 0 checks System Settings > Keyboard > Keyboard Shortcuts > Services).
- The provider: `App/SystemServices.swift`, an `NSObject` with `@objc func newSongFromSelection(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>)` and the setlist twin (signature compiled at 26.0); it reads `pboard.string(forType: .string)` and hands the text to `AppModel.requestService(_:)`, which owns the queue and the rules of 4.2. Registered in `applicationDidFinishLaunching` with `NSApp.servicesProvider = provider` (`NSApplication.h:549`), and `NSUpdateDynamicServices()` (`NSApplication.h:628`) once per new app version so a fresh install shows the items without a logout.
- Activation: `NSApp.activate()` only when the request runs, never while queued.
- Name clash: the WS3 "hosted services" code is `Services` (the package and `SegueServicesE2ETests`). This feature is **system Services** in code and docs: `SystemServices`, `requestService`, `SystemServicesTests`.

### 4.5 Flavours

Both flavours share `appInfoPlist` (`Project.swift:159-161`), so both vend the same two titles. On a Mac with both installed, the Services menu lists each title twice (**UNVERIFIED**; spike 0). The Personal build appends " (Personal)" to its `NSMenuItem` titles through a per-flavour build setting so the two are distinguishable; the App Store build's titles are the plain ones.

### 4.6 App Store implications

Services are a standard, sandbox-compatible AppKit mechanism; no entitlement. The provider reads only the pasteboard macOS hands it for that one invocation, which matches the privacy policy's "the clipboard is read only when you ask" (the policy wording gets "or when you choose a Segue service" in the same step). Reviewers can try it from TextEdit; the guide page describes it.

## 5. Handoff (P9-5c)

### 5.1 Why it helps a gigging musician

The owner has two Macs: one at home for preparing charts and sets, one that goes to the gig (or a second one on stage as a backup). Editing a chart at the desk and then carrying the laptop to rehearsal, the laptop's Dock offers that same chart; building the set on one and running it on the other is one click. The proposal in 5.4 goes further: if the gig laptop fails mid-set, the backup Mac's Dock offers "continue the show at song 7".

### 5.2 Behaviour and UI

- **What is advertised** (one current activity at a time, as macOS allows):
  - a **song** while the main window shows a song's detail or editor (`dev.ryandsilva.segue.song`);
  - a **setlist** while the main window shows a setlist builder (`dev.ryandsilva.segue.setlist`);
  - nothing in the Gig Log, Smart Filters or Settings, and nothing while the main window is closed or Segue is hidden (macOS stops advertising a resigned activity).
- **On the other Mac**: macOS shows the Segue Handoff icon at the Dock's end and in Cmd-Tab. Clicking it opens Segue there, brings the main window forward and selects the same song (Library section, detail shown) or opens the same setlist's builder. The editor is not opened automatically; the song is selected, so a click or Return edits it.
- **Before the other Mac reads the file**: when the activity is about to be sent (`NSUserActivityDelegate.userActivityWillSave`), the sending Mac flushes the open editor (`flushEditor`), so a library shared through iCloud Drive or a sync folder carries the latest text. Concurrent edits on both Macs keep using the existing save-conflict alert.
- **Resolving on the receiving Mac**, in order: the song's ULID in the open library's catalog; else the same library-relative path; else not found. A setlist resolves by its ULID only.
- **Not found** (the other Mac's library does not have it): the main window's banner says "“Tum Hi Ho” isn't in this Mac's library." with a Help button to the guide's Handoff anchor ("Handoff opens the same song when both Macs use the same library folder, for example in iCloud Drive."). Nothing is imported or created (Q9).
- **Receiving Mac busy**: no library yet or Welcome flow - the continuation waits and runs after; performing, starting a show or a main-window prompt up - it waits, Segue does not activate, and it runs after the end-of-show flow with a flash "Opened from your other Mac". A newer continuation replaces a waiting one.
- **Unsaved changes on the receiving Mac** are not a concern: the editor autosaves (2.4); a navigation away from a dirty editor runs the existing `navigate` guard.

### 5.3 Payload and APIs

- `SegueCore/Sources/Support/ContinuityPayload.swift` (pure, Codable to a `[String: Any]` of strings and ints only): `v` (1), `kind` (`song`, `setlist`, `show`), `id` (ULID), `path` (library-relative path, songs only), `title` (for the not-found banner), and for `show` `position` and `showKind`. `requiredUserInfoKeys = ["v", "kind", "id"]`. A payload with an unknown `v` or `kind` is refused with no banner. Small enough for Handoff's userInfo (well under a few hundred bytes); no continuation streams.
- Advertising: SwiftUI `.userActivity(_:isActive:_:)` on the main window's detail and builder views (SwiftUI, macOS 11+, `sdk-api.sh` confirmed), setting `isEligibleForHandoff = true`, `targetContentIdentifier` `song:<ULID>` / `setlist:<ULID>` (Foundation `NSUserActivity.h:117`, `:139`), and `title`.
- Receiving: `SegueAppDelegate.application(_:willContinueUserActivityWithType:)` and `application(_:continue:restorationHandler:)` (`NSApplication.h:470-486`) route into `AppModel.requestContinuation(_:)` with the same queue rules as Open With. The delegate path is chosen over SwiftUI's `onContinueUserActivity` because the main window may be closed (single `Window` scene) and the delegate already hosts Open With; spike 0 confirms the delegate is called for a SwiftUI app (**UNVERIFIED**).
- Info.plist: `NSUserActivityTypes` = `[dev.ryandsilva.segue.song, dev.ryandsilva.segue.setlist]` (plus `dev.ryandsilva.segue.show` if Q10 is accepted).
- Entitlements: none. Handoff between a user's Macs requires both builds signed by the same team (`V6BM673U35`) declaring the type in `NSUserActivityTypes` (**UNVERIFIED** that no entitlement is needed for a sandboxed Mac App Store app on macOS 26; spike 0 runs it between Ryan's two Macs).
- Flavours: both flavours declare the same activity types (Q11), so an App Store build on one Mac continues to a Personal build on the other. Which app macOS picks when both flavours are installed on the receiving Mac is **UNVERIFIED** (spike 0).

### 5.4 Show continuation on a backup Mac (proposal, Q10)

- While a show runs, the stage advertises `dev.ryandsilva.segue.show` with the setlist ULID, the current entry position and the kind (gig or rehearsal). It is updated on each song change by setting `needsSave = true`, with the payload filled lazily in the delegate callback: no file I/O and no main-thread work beyond a dictionary write, so the stage pays nothing measurable (13.3 records the timing).
- On the other Mac, clicking the Handoff icon opens that setlist's builder and starts the normal pre-show checklist primed with "Start at song 7: Kesariya" (the existing start path, `startShow`, gains a starting position). The stage appears only after the user confirms the checklist. A show on that Mac is a separate gig in its Gig Log.
- If the receiving Mac is itself performing, it ignores the continuation (it never queues a second show).

### 5.5 Owner actions (manual, Ryan)

For Handoff to appear at all, on both Macs: signed into the same Apple Account; System Settings > General > AirDrop & Handoff > "Allow Handoff between this Mac and your iCloud devices" on; Bluetooth and Wi-Fi on; a Segue build signed with team `V6BM673U35` installed. The session tells the orchestrator to ask Ryan for this before spike 0.

### 5.6 App Store implications

No entitlement (pending spike 0); Handoff data travels between the user's own devices through Apple's encrypted continuity channel and never reaches the developer, so the App Privacy answers are unchanged. The privacy policy gains one line: "Handoff passes the name and identifier of the open song or setlist to your other Mac through Apple; Segue never sees it."

## 6. Menu bar extra (P9-5d)

### 6.1 Why it helps a gigging musician

The musician's day revolves around one question: what's tonight's set? The menu bar extra answers it without opening the library, and starts a rehearsal of tonight's set or the gig itself from anywhere, through the same safe pre-show flow.

### 6.2 What it is for (decision, Q12-Q14)

Tonight's setlist and a quick start. **Not** a metronome (Q14): a click track in the menu bar is a second product, would need its own audio rules next to R161, and the stage and rehearsal already have the metronome.

"Tonight's setlist" is picked by `SegueCore/Sources/Setlists/TonightSetlist.swift` (pure, injected `CalendarDay` today): the setlist dated today (two on one day: the earlier `createdAt` first, both listed); else the next dated setlist within 7 days ("Next: Saturday"); else none, and the extra shows the three most recently updated setlists instead. It re-evaluates at midnight and on library change (the clock is injected, so tests move it).

### 6.3 Behaviour and UI (direction from step 0; this is the content every direction carries)

- **Status item**: a template glyph (the taped-setlist motif as a monochrome symbol, designed in step 0), no text.
- **Content**:
  - Tonight: the setlist name, venue and date, song count and time total (the P8-8 slot times, with "≥" and the unknown flag as in the builder), and the first three songs.
  - **Rehearse** and **Start Show...**: both bring the main window forward and run the existing `startShow` path, so the pre-show checklist appears there; nothing starts from the extra itself. Disabled with a reason when the setlist has no songs.
  - **Open Setlist** (the builder), **Open Segue** (the main window), and **New Song from Clipboard** (the existing command, with its existing rules).
  - Recent setlists when nothing is dated (each opens its builder).
- **Setting**: Settings > General > "Show Segue in the menu bar" (`MenuBarExtra(_:image:isInserted:)` bound to it; SwiftUI macOS 13+, confirmed). Default off (Q13); a TipKit tip in the builder offers it the first time a user sets a setlist's date ("See tonight's set from the menu bar").
- **Lifetime**: the extra exists while Segue runs. No login item, no `SMAppService` (Q15): quitting Segue removes it, as with any app's extra.
- **Before a library exists** (first run, Welcome flow): the extra is not inserted.

### 6.4 Live safety (hard rules)

- While `isPerforming` or `isStartingShow` the extra is **removed** (`isInserted` is `setting && !isPerforming && !isStartingShow && session != nil`). On a second display, where the menu bar stays visible during a show, there is nothing to click that could open a panel and take the keyboard from the stage (2.5). It returns when the show and its end-of-show flow are done.
- Any extra content that is open when a show starts (a show started from the main window or a pedal while the panel is open) is dismissed first.
- The extra never plays sound and never triggers a Shortcut itself; Gig Mode Shortcuts run where they run today, inside `startShow`.

### 6.5 APIs

`MenuBarExtra` and `.menuBarExtraStyle(.window)` or `.menu` (SwiftUI, macOS 13+, confirmed; the style follows the chosen direction) as a fourth scene in `SegueApp.body`; its view `App/MenuBarExtra/SegueMenuBarExtra.swift` reads a small `MenuBarExtraModel` (tonight, recents, enabled actions) derived from `AppModel`, so tests drive the model without the status item. Opening the main window uses the existing `PendingEditsGuard.shared.reopenMainWindow` path (`OpenDocuments.swift:60`).

### 6.6 App Store implications

Guideline 2.4.5 (research 08, section 2): no auto-launch at login without consent; this spec adds no login item. HIG treats menu bar extras as optional and user-removable: the Settings toggle provides that. The extra must not be the only route to any feature (everything in it is in the main window and menus), which also keeps Full Keyboard Access coverage intact.

### 6.7 Design directions (step 0 of P9-5d, R39)

Three directions, light and dark, rendered in the session scratchpad `p9-5/menu-bar/` with real content (a Welcome-library setlist dated today at "The Blue Door", 14 songs including romanized Hindi titles such as "Tum Hi Ho" and "Kesariya", one song without a tempo so the total shows "≥ 52:10 + 1 unknown"), plus the no-dated-set state, for Ryan to pick before step 2:

- **A - Tonight card** (`.window` style): a compact 300 pt panel like Control Center modules: header "Tonight - The Blue Door, 8:00", the total, the first three songs as rows, two buttons "Rehearse" (secondary) and "Start Show..." (prominent), a footer "Open Setlist" / "Open Segue". Richest glance; a real panel.
- **B - Native menu** (`.menu` style): a plain NSMenu: a disabled header item "Tonight: Blue Door set (14 songs, ≥ 52:10)", then "Rehearse", "Start Show...", "Open Setlist", separator, "Recent Setlists ▸", "New Song from Clipboard", "Open Segue". Most Apple-native (Things, Fantastical-style menus), keyboard navigable, nothing custom to maintain.
- **C - Setlist peek** (`.window` style): the whole set as a scrolling numbered list with keys and slot times (like the builder's left column), a sticky footer with "Rehearse" and "Start Show...". Most useful the hour before a gig; the largest surface.

Recommendation: **B** (Q12): it matches the Apple-native minimal taste, needs no custom panel focus handling, and carries everything the extra is for; A is the fallback if a glance at the first songs matters more than nativeness.

## 7. Localisation (P9-5e)

### 7.1 Why it helps a gigging musician

The owner's audience is musicians who play Hindi film and Indian music, many of whom read Hindi more comfortably than English, and for whom an app that greets them in their language is a signal it was made for them. The rule that matters most is the reverse one: whatever the UI language, their lyrics, titles and chords must be exactly what they typed.

### 7.2 Languages (Q1, Q2)

- **Source**: English (U.S.), `en`, complete.
- **Added for v1.0**: **Hindi (`hi`, Devanagari)** for UI chrome only (recommended in Q1). Rationale: macOS itself ships Hindi (`hi.lproj`, 2.6), so a Mac set to Hindi, or Segue set to Hindi in System Settings > General > Language & Region > Applications, shows Segue in Hindi consistently with the system; a Latin-script "Hinglish" UI has no system locale, no standard spelling and would show only through the per-app setting (**UNVERIFIED** whether macOS offers `hi-Latn` there; Q1 option c). This **amends** `docs/decisions.md:85` ("No Devanagari display") for UI chrome only; content rules are untouched (7.3).
- Translation: Xcode's String Catalog translation tooling (the MCP `LocalizationPlanner` / `StringCatalogEdit` flow) drafts every `hi` string, each left in **needs review** state; Ryan reviews every string (in Xcode's catalog editor or a generated review sheet) and only reviewed strings ship. A gate test fails while any `hi` string is untranslated, stale or needs review (12.2), so a partial Hindi UI can never ship.
- **Glossary** (Q4): music terms stay English in the Hindi UI, as Indian musicians say them: Capo, Transpose, Key, BPM, Tempo, Metronome, Verse, Chorus, Bridge, Intro, Outro, Nashville, Setlist, Gig, Rehearse, Live, Walk-up, Fill. They are written in Latin script inside Hindi sentences ("Capo लगाएँ"). The glossary lives in `docs/localization-glossary.md` and is fed to the translation step.
- Numbers: every musical number (tempo, capo fret, Nashville degrees and suffixes, bar counts, times like "3:40", fret numbers on tab) is formatted with Latin digits in every language, via one `MusicNumberFormat` helper that pins the numbering system to `latn`. Dates and plain counts follow the locale (Hindi uses Latin digits by default; the helper makes it explicit for music).

### 7.3 What is never localised (romanized Hindi untouched)

- Song content in every view, the stage, PDFs, Quick Look and the menu bar extra: titles, artists, Movie / Album, lyrics, chord names, section labels (including the default "Verse" / "Chorus" labels written into files), comments, notes, setlist names, venues, smart filter names, tag names. These are already `String` values rendered with `Text(_ content: some StringProtocol)`, which is verbatim; the sweep keeps it that way and converts any content literal that slipped into a `LocalizedStringKey` initialiser to `Text(verbatim:)`.
- ChordPro directives and file content written by the app (`{start_of_chorus}`, section labels, `{key}`), and the Welcome library files: English as today, in every UI language. A Hindi UI never writes Hindi into a `.cho`.
- Search, `RomanNormalizer`, the set composer grammar ("in A", "key of D", "by <artist>") and the set assistant lexicon: unchanged and English-keyed; the Hindi UI's placeholder text shows the English request forms in quotes.
- The AI paths: prompts stay English; nothing in them depends on the UI language; lyric preservation is unchanged.
- Help Book and guide: English only (Q17).
- Analytics vocabulary and log lines: English, never localised.

### 7.4 String Catalog approach (Q5)

- **One catalog per module that shows text**, Apple's package pattern: `Packages/SegueUI/Sources/SegueUI/Localizable.xcstrings` with `defaultLocalization: "en"` in `Packages/SegueUI/Package.swift`; SegueCore gets a catalog only for the few user-facing messages it owns (pre-show checklist reasons, `FillSpan` errors such as "A fill covers at most 8 bars", `SegueCore/Sources/Library/FillSpan.swift:21`); the app target gets `InfoPlist.xcstrings` (`NSAppleEventsUsageDescription`, the `NSServices` titles; `CFBundleDisplayName` stays "Segue") and the Quick Look extension shares SegueUI's catalog through the package bundle.
- **Lookups name their bundle**: every localisable literal in a package uses `bundle: #bundle` (`Text("Start Show", bundle: #bundle)`, `String(localized: "...", bundle: #bundle)`, `LocalizedStringResource("...", bundle: #bundle)`; all compiled at 26.0). A SwiftLint custom rule in the packages flags `Text("`, `Button("`, `Label("`, `Toggle("`, `.help("`, `navigationTitle("` and friends without `bundle:` or `verbatim:`.
- **Menu and model titles** that are `String` today (`HelpMenuItem.title`, `MenuShortcut` titles, `UserMessage` texts, Settings pane names, `SegueLinks.Guide.title`, stage status-line strings) become `LocalizedStringResource`. `MenuShortcut` titles double as lookup keys for tests: tests compare against the resource's key, not the rendered text.
- Extraction: Xcode's build-time extraction (`SWIFT_EMIT_LOC_STRINGS`, default for packages with `defaultLocalization`) fills the catalogs; `make strings` runs `xcrun xcstringstool sync` over the build's `.stringsdata` so the catalogs can be refreshed from the command line, and `make quick` fails when a build adds a key the committed catalog lacks (the "generated, dirty tree fails" pattern).
- Formats: plurals and variables use catalog variations (`"\(count) songs"` with plural variants for `en` and `hi`), never string concatenation.

### 7.5 Layout and Live safety

- The stage chrome (status line, pre-show checklist, end-of-show flow, `?` overlay, quick search) is localised with the rest (Q3), and checked under Hindi at the minimum stage size by an in-process layout test (12.2): no string truncates into ambiguity, no row wraps into the lyric area. Devanagari falls back from Schibsted Grotesk to the system's Devanagari face; the stage keeps its own font for lyrics, so lyric metrics and `LiveLayout` fitting do not change with the UI language.
- Pseudo-localisation: the in-process layout tests also run the main window and Settings under an "accented, 40% longer" pseudo-locale generated from the English catalog at test time, so clipping shows up before translations exist.
- A language change takes effect on the next launch (macOS behaviour); nothing changes mid-show.

### 7.6 App Store implications

- The binary's localisations appear on the product page's "Languages" line ("English, Hindi"). The listing stays English U.S. only (R8); a Hindi listing is a later, separate decision.
- A partially translated UI reads as broken to a reviewer in any storefront: the gate test (7.2) blocks it.
- `PrivacyInfo.xcprivacy` and entitlements are unaffected.

## 8. Proposals from the research list (Q19)

`08-polish-features.md` sections 4 and 6 list items that are still missing or partial today and fit this workstream's "Mac citizen" theme. Each is a **proposal**, built only if Ryan accepts it in Q19, as an extra step in the session named:

- **P1 - "Report..." on the error banner** (research #28; missing: the banner has only Dismiss, `SegueRootView.swift:324-347`). A button beside Dismiss opens Report a Problem with the error's `ErrorCode` and message pre-filled (the diagnostics preview shows it). Never shown on stage. Session P9-5b, S effort. Why: a solo developer's support channel; the musician reports the problem when it happens instead of forgetting it before the gig.
- **P2 - Drag a song out to Finder, Mail or Messages** (research #19; drop-in exists, `Library/LibraryViews.swift:92`, drag-out does not). Library rows drag their `.cho` as a file (`.draggable` with the file URL), so sending a chart to the bass player is a drag into Messages. Session P9-5b, S-M effort.
- **P3 - Quick Look thumbnails** (research #20; the preview extension exists, `Extensions/QuickLook/Sources/PreviewViewController.swift:8`, but `.cho` files show the generic document icon in Finder's icon and gallery views). A thumbnail extension renders the chart's first lines with the same SegueUI renderer. Session P9-5a, M effort (a new extension target, sandboxed, both flavours).
- **P4 - Launch-time metric** (research #30; unmeasured). One `XCTApplicationLaunchMetric` performance test (no assertion) and a 500-song index timing recorded in `docs/test-performance.md`, so Help Book registration, the menu bar extra and the catalogs are proven not to slow launch. Session P9-5e, S effort.

Not proposed: autosave (exists), Trash for deletes (exists, `LibraryStore+Trash.swift:22-30`), Show in Finder (exists, `FeatureKey.showInFinder`), state restoration (exists, `SessionRestore`), document type and icon (exist, `Project.swift:131-150`), What's New and TipKit (exist).

## 9. Analytics (non-PII, closed vocabulary, WS3)

Enums, booleans and buckets only: never song or setlist names, selected text, source app names, venue or language strings beyond the closed enum. New file `Services/AnalyticsEvent+Mac.swift`; rows take the next free WS3 numbers at build time (31-33 if no sibling took them); `ServicesVocabularyTests` extended; `docs/release/specs/WS3-services.md` section 5 documents them. Everything is sent only after consent, as today.

| Signal | Params | When | Throttle | Question |
| --- | --- | --- | --- | --- |
| Row 31 `Segue.Mac.service` | `segue.service` (`newSong`, `newSetlist`), `segue.outcome` (`opened`, `queued`, `empty`, `tooLong`, `full`), `segue.lines` (SmallBucket; setlist only, else `0`), `segue.matched` (SmallBucket; setlist only) | a service call arrives | daily per (service, outcome) | Do people use Services, and does a texted set list match well |
| Row 32 `Segue.Mac.handoff` | `segue.activity` (`song`, `setlist`, `show`), `segue.outcome` (`continued`, `notFound`, `waited`, `ignored`) | the receiving Mac resolves a continuation | daily per (activity, outcome) | Does Handoff land on the same library, or is iCloud sync needed |
| Row 33 `Segue.Mac.menuBar` | `segue.action` (`opened`, `rehearse`, `startShow`, `openSetlist`, `openApp`, `newSong`, `recent`), `segue.tonight` (Bool: a dated set was shown) | an action in the extra | daily per action | Is the extra used, and for tonight's set or as a launcher |

- Row 14 `Segue.Help.opened` gains `segue.via` (`book`, `web`): which route a Help item or Help button took (the fallback rate shows a broken book). `GuideHelpButton` and Learn More start recording row 14 with a new `HelpItem.contextHelp` (no page name; the page is a closed enum, so `segue.page` with the `SegueLinks.Guide` case name is allowed: rendered values match the vocabulary regex).
- Row 2 `Segue.App.launched` gains `segue.language` (`en`, `hi`, `other`: the UI language the bundle resolved, never the system's preferred list) and `segue.menuBar` (Bool: the extra is on).
- `PasteSource` gains `service`; `SetlistSource` gains `service`, so rows 19 and 10 attribute service-made songs and setlists.
- `FeatureKey` (row 8) gains `menuBarExtra` (turned on in Settings, settings context).

## 10. Guide pages and site

- New page `guide/src/content/docs/mac-integration.mdx`, "Segue and your Mac", in the sidebar's "Settings and data" group, with anchors the app links to (added to `SegueLinks.Guide`): `#services` (both services, where the Services menu is, enabling them in System Settings > Keyboard > Keyboard Shortcuts > Services, what happens during a show), `#handoff` (the owner actions of 5.5, "same library folder" and the not-found banner), `#menu-bar` (turning it on, what tonight's set means, why it disappears during a show), `#language` (choosing Segue's language per app, what stays English, romanized Hindi untouched), `#help` (the built-in help, searching it from the Help menu, the online copy).
- `paste-a-song.mdx`: "From another app" with the New Segue Song from Selection screenshot.
- `build-a-set.mdx`: "Paste a set list from a message" (the setlist service and the review strip).
- `go-on-stage.mdx`: one line: during a show Segue ignores Services and Handoff until you finish, and the menu bar extra hides. If Q10 is accepted, a `#backup-mac` section.
- `troubleshooting.mdx`: "The Segue services are missing", "Handoff doesn't show Segue", "Segue Help opens in the browser" (the fallback).
- `keyboard.mdx`: no change (no new shortcuts; services have none, Q8).
- Real screenshots via `make docs-shots` for the new shots only (the Services menu in TextEdit, the review strip, the menu bar extra in its chosen direction, Tips showing the book); verify every `SegueLinks.Guide` URL against the local build and every `helpAnchor` against `Derived/HelpBook`, and against the live site once deployed.
- The website's privacy policy gets the two lines of 4.6 and 5.6.

## 11. Entitlements and Info.plist (summary)

- **No new entitlement** in either flavour (`App/SegueAppStore.entitlements`, `App/Segue.entitlements` unchanged; `scripts/verify-archive.sh` check 4 still asserts the App Store set exactly). Pending spike 0 for Handoff (5.3).
- `appInfoPlist` (`Project.swift:103-157`) gains `NSServices` (4.4, Personal titles suffixed by build setting), `NSUserActivityTypes` (5.3), `CFBundleHelpBookFolder` and `CFBundleHelpBookName` (3.3). Localisations come from the catalogs (Xcode writes the `.lproj` folders; `CFBundleLocalizations` is not hand-maintained).
- Resources: `Derived/HelpBook/Segue.help` in both app targets; `InfoPlist.xcstrings` in both app targets; SegueUI's catalog in its package bundle.

## 12. Tests (R113 budget)

### 12.1 SegueCore, pure (Swift Testing, table-driven)

- `TonightSetlistTests`: today, two today, next within 7 days, 8 days out, past only, undated only, midnight rollover with an injected day, a deleted setlist.
- `ContinuityPayloadTests`: round trip of song, setlist and show payloads; unknown `v` or `kind` refused; missing required keys; a title with romanized Hindi and emoji survives byte for byte.
- `SelectionLinesTests`: numbered, bulleted and emoji lists; CRLF and U+2028; "Set 2:" headers to breaks; `---` and a long dash; a line that is only a number; romanized Hindi lines byte-identical; 64 KB boundary.
- `MusicNumberFormatTests`: tempo, capo, Nashville `3(7)`, "3:40" under `en` and `hi` give Latin digits.

### 12.2 SegueUI, in-process

- `HelpBookRoutingTests`: every `SegueLinks.Guide` case has a `helpAnchor`; the route tries the book then falls back to the web URL; every Help item and Help button is disabled or a no-op while performing; row 14 `via`.
- `SystemServicesTests`: the provider with a private pasteboard (`NSPasteboard(name:)` with a unique name) opens the paste review with source `service`; empty and too-long errors; queued with no activation while performing, starting or with the checklist up, drained after the end-of-show flow; the 10-request cap; the setlist service builds entries, composer rows and breaks from the Welcome library.
- `HandoffActivityTests`: the advertised type and payload for a selected song, an open builder, nothing for the Gig Log; resolution by ULID, by path, not found (banner text); held while performing; a newer continuation replaces a waiting one; the editor flush on will-save.
- `MenuBarExtraModelTests`: inserted only with the setting on, a library open and no show up or starting; actions call `startShow` through the main window (the checklist appears there); tonight vs recents; disabled Start with no songs.
- `LocalizationCoverageTests`: every key in each catalog has a `hi` value in state translated (not new, stale or needs review); format specifiers match across languages; no catalog key is a content-looking string (a guard list of Welcome song titles).
- `ContentVerbatimTests`: the library row, song page, stage page and Quick Look render of a romanized Hindi Welcome song under `\.locale` `hi` show the source text unchanged, including "Chorus" section labels.
- `StageChromeLayoutTests`: the stage status line, checklist and `?` overlay at the minimum stage size under `hi` and the pseudo-locale: no truncation of a command name, nothing overlapping the lyric area.

### 12.3 Build and site checks

- `make help-book` then `guide-check`: no absolute `/guide/` URLs in the book, every anchor present, `Segue.helpindex` built, source hash written; `gen-site.swift --check` resolves every `helpAnchor`; `make quick`'s staleness check on the book and on the catalogs (7.4).

### 12.4 E2E: `SegueMacPolishE2ETests` (new, one class)

- `testMenuBarExtraRehearsesTonight` (P9-5d): launch with the setting on and a Welcome setlist dated today; open the status item; Rehearse; confirm the checklist; the stage is up and the status item is gone; end the rehearsal; the status item is back.
- `testHelpOpensTheBook` (P9-5a): Help > Segue Help; Tips (`com.apple.helpviewer`) runs in the foreground; then a Help button in Settings > Live opens it too. Quits Tips at the end.
- `testHindiUIKeepsLyrics` (P9-5e): launch with `-AppleLanguages (hi)`; the Library menu title is the Hindi string from the catalog; the Welcome song "Tum Hi Ho" shows its romanized title and first lyric line unchanged; Start Show's checklist title is Hindi.
- Services and Handoff are not driven by XCUITest (another app's Services menu and a second Mac are outside the runner): they are walkthrough steps for Ryan (`docs/release/walkthrough.md`, hunk by hunk): select text in TextEdit and run both services, including once during a rehearsal; Handoff a song, a setlist and (if accepted) a show between the two Macs.
- Existing UI tests changed: `SegueCoreUXE2ETests+Menus` if it asserts Help menu items (one `make e2e-one` in P9-5a).

### 12.5 Performance (no assertions)

- The show activity update per song change (5.4) and the menu bar extra's model refresh on a 500-song library, timed once and written to `docs/test-performance.md`; if P4 is accepted, the launch metric.

## 13. Sessions and steps

**P9-5a - Help Book** (after section 15 is closed)

0. Spike (scratch, nothing committed): hand-build a two-page `Segue.help` from the current guide, compare its Info.plist with `Skim.help`, index it with `hiutil`, open it from a Debug build via `NSApp.showHelp` and `openHelpAnchor`; record in this spec: Tips renders Starlight's CSS, dark mode, images and clips; anchors work with `<a name>`; Help menu search finds topics; which `HPD*` keys are needed. Stop and report if Tips cannot open a third-party book on macOS 26.
1. `helpbook.mjs`, the help-mode config branch, `make help-book`, the source hash. Check: `guide-check`.
2. `Project.swift` resources and Info.plist keys, the build-phase presence check, `verify-archive.sh` anchor check.
3. `HelpBook.swift`, `SegueLinks.Guide.helpAnchor`, `OpenGuideAction` book route with web fallback, Help menu changes and performing guards, row 14 `via` / `contextHelp`. Suite: `HelpBookRoutingTests`, `ServicesVocabularyTests`.
4. If accepted, P3 (Quick Look thumbnails).
5. Guide `#help` section and troubleshooting entry; `testHelpOpensTheBook`. ONE `make quick`, ONE `make e2e-one` for `SegueMacPolishE2ETests` and for any changed menu test class.

**P9-5b - Services** (independent)

0. Spike: a Debug build with one `NSServices` entry; does it appear enabled with `NSRequiredContext {}`, how does macOS 26 show the error string, what happens with both flavours installed, does `NSUpdateDynamicServices` make it appear at once.
1. `SelectionLines`. Suite: `SelectionLinesTests`.
2. `SystemServices` provider, `requestService` queue and rules, Info.plist entries, `PasteSource.service`, row 31. Suites: `SystemServicesTests`, `ServicesVocabularyTests`.
3. The setlist service (if Q7 accepted): new setlist, review strip, Keep / Discard, `SetlistSource.service`. Suite: `SystemServicesTests`.
4. If accepted, P1 (Report... on the banner) and P2 (drag-out).
5. Privacy policy line; guide `#services`, `paste-a-song`, `build-a-set`; walkthrough steps. ONE `make quick`.

**P9-5c - Handoff** (independent; needs Ryan's two Macs set up, 5.5)

0. Spike between the two Macs with a Debug build: does a song activity appear with no entitlement; is `application(_:continue:restorationHandler:)` called in this SwiftUI app with the window closed; which flavour receives when both are installed. Stop and report if an entitlement or capability is needed.
1. `ContinuityPayload`. Suite: `ContinuityPayloadTests`.
2. Advertising (detail and builder `.userActivity`), will-save editor flush, Info.plist types.
3. Receiving: delegate route, `requestContinuation` queue, resolution, not-found banner, row 32. Suites: `HandoffActivityTests`, `ServicesVocabularyTests`.
4. If Q10 accepted: the show activity and "Start at song N" in the pre-show checklist; the 12.5 timing. Suites: `HandoffActivityTests`, `ShowScenarioTests`.
5. Privacy policy line; guide `#handoff` (and `#backup-mac`); walkthrough steps. ONE `make quick`; ONE `make e2e-one` for any existing class touched by the checklist change.

**P9-5d - Menu bar extra**

0. Section 6.7's renders; Ryan picks a direction (wait for it before step 2). The status glyph is part of the renders.
1. `TonightSetlist`. Suite: `TonightSetlistTests`.
2. `MenuBarExtraModel`, the scene, the General setting, the performing removal, the builder tip, row 33, `FeatureKey.menuBarExtra`. Suites: `MenuBarExtraModelTests`, `ServicesVocabularyTests`.
3. Guide `#menu-bar`, `go-on-stage` line; `testMenuBarExtraRehearsesTonight`; 12.5 timing. ONE `make quick`, ONE `make e2e-one` for `SegueMacPolishE2ETests`.

**P9-5e - Localisation** (last in the Phase 9 wave, after the sibling P9 UI work lands)

1. Infrastructure: `defaultLocalization`, catalogs, `InfoPlist.xcstrings`, the SwiftLint rule, `make strings`, the staleness check, `MusicNumberFormat`. Suite: `MusicNumberFormatTests`.
2. The sweep, module by module (one commit per folder of `SegueUI/Sources/SegueUI/`): `bundle: #bundle`, `LocalizedStringResource` for model titles, `verbatim:` for content; build green after each folder. Suites: the folder's existing in-process suites.
3. `ContentVerbatimTests`, `StageChromeLayoutTests` with the pseudo-locale; fix clipping.
4. Hindi draft through the Xcode translation tooling with the glossary; generate the review sheet for Ryan; **wait for Ryan's review** of every string; apply corrections. Suite: `LocalizationCoverageTests`.
5. Row 2 `language`; guide `#language`; `testHindiUIKeepsLyrics`; if accepted, P4 (launch metric). ONE `make quick`, ONE `make e2e-one` for `SegueMacPolishE2ETests`. Tell the orchestrator the app is ready to try in Hindi and English, and launch it for Ryan's walkthrough.

## 14. Done criteria

- Help > Segue Help and every in-app Help button open the bundled Help Book in Tips at the right anchor, offline; Help menu search finds book topics; the web page opens only as a logged fallback; nothing in Help opens while a show is up or starting; the book is rebuilt from the guide source and a stale book fails `make quick`; the archive check finds every anchor.
- Selecting text in another app and choosing New Segue Song from Selection opens the paste review on exactly that text; (if accepted) New Segue Setlist from Selection builds a setlist through the composer; during a show nothing activates or moves and requests run after the end-of-show flow; empty, too-long and full queues are refused with a message.
- The song or setlist open on one Mac is offered by Handoff on the other and opens there by ULID or path; a missing one shows the banner and creates nothing; a continuation never interrupts a show; (if accepted) a show continues on a backup Mac only through the pre-show checklist.
- The menu bar extra, when switched on, shows tonight's set (or recents), starts Rehearse and Start Show only through the main window's checklist, and is absent from the moment a show starts until its end-of-show flow is done.
- Every UI string is in a String Catalog; Hindi (or the language Q1 picks) is complete and reviewed by Ryan; song content, chord names, section labels and romanized Hindi are byte-identical in every UI language; musical numbers use Latin digits; the stage chrome fits under Hindi and the pseudo-locale.
- No new entitlement; Info.plist keys as in section 11; the privacy policy lines added.
- Analytics rows and params as in section 9, closed vocabulary only, documented in WS3.
- Guide pages of section 10 published with real screenshots; links verified locally and on the live site.
- Every 12.1-12.2 suite passes; `make quick` green; `make e2e-one` green for `SegueMacPolishE2ETests` and each changed class; the walkthrough steps for Services and Handoff done by Ryan; the app launched for Ryan.

## 15. Open questions

Each needs Ryan's answer before the session that reaches it. Recommendation first.

1. **UI languages for v1.0.** (a) English only, with the catalogs in place for later; (b) English + Hindi in Devanagari for UI chrome, amending the "No Devanagari display" rule for chrome only; (c) English + romanized Hindi UI (`hi-Latn`, if macOS offers it per app: unverified, spike in P9-5e step 1); (d) b and c; (e) make this a research ticket (survey which languages the owner's audience uses on their Macs, and whether any comparable Indian music app ships a Hindi UI). **Recommendation: (b).** It is the only Hindi the OS itself speaks, so menus and system dialogs agree; (c) has no standard spelling and shows only through the per-app setting.
2. **Who translates.** (a) machine draft through Xcode's String Catalog tooling, every string reviewed by Ryan before it ships; (b) Ryan translates from scratch; (c) a paid or community translator. **Recommendation: (a)**, with the gate test blocking any unreviewed string.
3. **Stage chrome language.** (a) the stage follows the UI language, with the layout tests of 12.2; (b) the stage chrome is always English (the most tested surface stays fixed). **Recommendation: (a)**; the stage has little chrome and a Hindi user would find an English-only stage odd.
4. **Music terms in the Hindi UI.** (a) the glossary of 7.2 stays English in Latin script; (b) translate them. **Recommendation: (a)**, as Indian musicians actually speak.
5. **Catalog layout.** (a) one catalog per module with `bundle: #bundle` and a lint rule (Apple's package pattern; works for the Quick Look extension and tests); (b) one app-target catalog that SegueUI's `Bundle.main` lookups hit, filled by `xcstringstool sync` (no call-site edits, but the extension needs its own copy and package tests see no translations). **Recommendation: (a).**
6. **Service names.** (a) "New Segue Song from Selection" / "New Segue Setlist from Selection" (the Services menu lists items without their app, so the name says whose it is); (b) "New Song from Selection" / "New Setlist from Selection". **Recommendation: (a).**
7. **The setlist service** (proposal). (a) ship New Segue Setlist from Selection with the review strip of 4.2 and "Set 2" headers as breaks; (b) ship only the song service. **Recommendation: (a)**: a texted set list is the gigging case Services fit best.
8. **Service keyboard shortcut.** (a) none (users can assign one in System Settings); (b) ship a default `NSKeyEquivalent`. **Recommendation: (a)**: any default collides with some app's shortcut.
9. **Handoff when the other Mac lacks the song.** (a) the banner only, nothing imported, until the iCloud sync research decides the library story; (b) offer "Import a Copy" carried over a continuation stream (the `.cho` and sidecar, same ULID). **Recommendation: (a)**; (b) creates second copies that a later sync would have to reconcile.
10. **Show continuation on a backup Mac** (proposal, 5.4). (a) yes, through the pre-show checklist primed at the current song; (b) not in v1.0. **Recommendation: (a)**: the one Handoff use that can save a gig, and it never touches the running stage.
11. **Handoff across flavours.** (a) both flavours declare the same activity types; (b) per-flavour types (Personal to Personal only). **Recommendation: (a)**, confirmed by the P9-5c spike.
12. **Menu bar extra direction.** A Tonight card, B Native menu, C Setlist peek (6.7). **Recommendation: B**, picked from the renders in P9-5d step 0.
13. **Menu bar extra default.** (a) off, with the Settings toggle and a tip when a setlist first gets a date; (b) on for everyone. **Recommendation: (a)**; a new icon in someone's menu bar should be their choice.
14. **Metronome in the menu bar.** (a) no; (b) a practice click with tap tempo, silenced and removed during shows. **Recommendation: (a)** for v1.0.
15. **Open at login.** (a) no login item; (b) an "Open Segue at login" toggle, off by default (`SMAppService.mainApp`, consent per 2.4.5). **Recommendation: (a)**; the extra is useful while Segue runs, and a login item is a separate decision.
16. **Help Book form and size.** (a) Apple Help Book generated from the guide, shots and clips kept (about 6 MB), opened in Tips; (b) a bundled static copy opened in the default browser from the app bundle (no Help menu search, Pagefind does not work over `file:`); (c) web only, as today. **Recommendation: (a).**
17. **Help Book language.** (a) English only, also under a Hindi UI; (b) translate the guide too. **Recommendation: (a)** for v1.0; screenshots would need a second capture set.
18. **In-app Help buttons.** (a) open the book's anchor, web as fallback; (b) keep opening the web page; the book serves only Help > Segue Help. **Recommendation: (a)**: one help, offline everywhere.
19. **Proposals P1-P4 (section 8).** P1 Report... on the error banner, P2 drag a song out, P3 Quick Look thumbnails, P4 launch-time metric: tick the ones to build. **Recommendation: all four**; P1, P2 and P4 are small, and P3 reuses the existing Quick Look renderer.
20. **Help while performing.** (a) Segue Help, Keyboard Shortcuts and Help buttons disabled while a show is up or starting; (b) allowed in rehearsals only. **Recommendation: (a)**: any of them takes the keyboard from the stage, rehearsal included.
