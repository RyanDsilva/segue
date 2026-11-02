# P9-5 - Mac polish: Help Book, String Catalogs and four extras

Phase 9 workstream (new, 2026-10-31). Rulings: `docs/release/decisions.md` **R176** (the first App Store release is v1.0 and, before submission, also builds the Mac polish list, specced with its open questions closed first) and **R179** (this spec's questions closed, section 12: v1.0 ships English only with String Catalogs per module in place for later; an offline Apple Help Book generated from the guide; Report... on the error banner, dragging a song out to Finder or Messages, Quick Look thumbnails and a launch-time metric). The candidate list and its first tiering are `docs/release/research/08-polish-features.md`. Built on: **R109** (nothing about paste or import may disturb the live view), **R126** (the user guide at `segue.ryandsilva.dev/guide`, Astro Starlight, in-app Help buttons open guide pages), **R8** (one listing localisation, English U.S.), **R39** (design directions before new UI), **R113** (test budget), **R11** (two bundle IDs: App Store `dev.ryandsilva.segue`, Personal `dev.ryandsilva.segue.personal`), and the product language rules in `docs/decisions.md:83-93` (English + romanized Hindi content only, no Devanagari display, no auto-transliteration, lyric preservation, autocorrect off in lyric text).

**Build order:** three sessions (section 10). **P9-5a** (Help Book, plus Quick Look thumbnails) may start at once: it touches the guide build, the Help menu, `GuideHelp.swift` and the Quick Look extension. **P9-5b** (Report... on the error banner, drag-out) is independent of P9-5a. **P9-5c** (String Catalogs, plus the launch metric) runs **last in the Phase 9 wave**, after the sibling P9 workstreams have landed their UI, because it sweeps every SegueUI view file and would otherwise conflict with them; until then, new P9 code follows the string rules in section 4.3 so the sweep finds less to do. Index: `README.md` in this folder.

## Session rules (apply to every session)

- `cat` and `ls` are aliased to eza and can hang: use `command cat` / `command ls` or the Read / Grep / Glob tools, and pass this warning to any subagent. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-". Ignore `.build/`.
- Sibling P9 workstreams edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, stage only your own hunks, keep the tree compiling between steps. `docs/release/walkthrough.md` and the guide sidebar (`guide/astro.config.mjs`) are shared: edit them hunk by hunk, never by overwriting the file.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget (R113): per step only targeted in-process suites (`swift test --filter <Suite>`); tricky pure logic (the anchor map, the catalog coverage check) gets table-driven in-process tests; UI behaviour gets in-process SegueUI tests. Exactly **one** new XCUITest class for the workstream (section 12.4), grown one test per session that needs it. At the end of each session ONE `make quick`, plus ONE `make e2e-one` per UI test class the session added or changed. No `make gate`, no `make check`, no E2E retry loops (a failure is investigated, not re-run), no scratch-worktree builds. Every build or test runs under `lockf -k .build/make.lock`. Write this budget into any subagent's prompt.
- Before using any Apple API not already in the codebase, run the `apple-api-check` skill. The APIs named below were checked on 2026-10-31 against MacOSX27.0.sdk (Xcode 27.1) at the project's deployment target macOS 26.0 (`Project.swift:48`): SwiftUI declarations with `sdk-api.sh`, AppKit / Foundation Objective-C declarations in the SDK headers, and a `typecheck.sh -t 26.0` probe that compiled every call in sections 3-5 with no warnings. Behaviour marked **UNVERIFIED** is checked in the step 0 spikes.
- Ryan's real library is never opened by a test or a session.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency, including any case section 12's closed questions do not cover.

## 1. Goal

Segue works well inside its own window. After P9-5:

- **Help works offline.** Help > Segue Help opens a built-in Apple Help Book generated from the same guide source as the website, searchable from the Help menu's search field, so a question at a venue with no signal still gets an answer. In-app Help buttons open the matching page of the book, with the web as fallback.
- **The strings are ready for other languages.** Every UI string moves into a String Catalog per module, while v1.0 ships English only (R179); song content (titles, lyrics, chord names, section labels, romanized Hindi) is shown exactly as written and never enters a catalog.
- **Four extras** (R179): Report... on the error banner, dragging a song out to Finder or Messages, Quick Look thumbnails for `.cho` files, and a launch-time metric.

**In scope:** the items above; their analytics (section 6); their guide edits (section 7); the Help menu and Help button rewiring; the Info.plist keys `CFBundleHelpBookFolder` and `CFBundleHelpBookName`.

**Unchanged:** the website guide (still built and deployed as today; the Help Book is a second output of the same source); the stage, its keys and its window; the App Store listing localisation (R8, English U.S.); entitlements (section 8).

## 2. Current behaviour (verified 2026-10-31)

### 2.1 Scenes, menus and the app delegate

- Scenes: one `Window("Segue Library")` with `.commandsRemoved()` and `SegueCommands`, a `Keyboard Shortcuts` window, and `Settings` (`App/Sources/SegueApp.swift:247-273`). 
- `SegueCommands` composes App, File, Library, Song, Setlist, Live, Window and Help menus (`Packages/SegueUI/Sources/SegueUI/App/Commands/SegueCommands.swift:16-25`); `isMainWindowBusy` lists the sheets and prompts commands must wait behind (`:31-37`).
- The app delegate is `SegueAppDelegate` (`Packages/SegueUI/Sources/SegueUI/Editor/PendingEditsGuard.swift:84`), extended for Finder's Open With in `App/OpenDocuments.swift:33-39`. One Segue per user session (`App/SingleInstance.swift:5-32`).
- Settings panes: General, Appearance, Instrument, Audio, Live, AI, Privacy, Data (`Settings/SegueSettingsView.swift:17-26`); General lives in `Settings/GeneralSettingsView.swift`.

### 2.2 Help today

- The Help menu replaces the system group (`App/Commands/HelpCommands.swift:16-31`): Segue Help (Cmd-?, `MenuShortcuts.swift:156`) opens `SegueLinks.help`, the web guide (`HelpCommands.swift:79-84`, `SegueLinks.swift:11`); Keyboard Shortcuts (Cmd-/); Welcome to Segue...; What's New; Report a Problem...; Request a Feature...; Rate (once the App Store ID exists); Privacy Policy; Terms of Use (`HelpCommands.swift:76-148`). Only Welcome and What's New are `disabledWhilePerforming`.
- In-app Help buttons and tips open guide pages in the browser through `OpenGuideAction` (`App/GuideHelp.swift:11-52`); the pages and anchors are the closed enum `SegueLinks.Guide` (`SegueLinks.swift:51-103`), each raw value resolved against the built guide by `gen-site.swift --check`.
- The guide: Astro Starlight in `guide/`, 30 pages in `guide/src/content/docs/`, sidebar in `guide/astro.config.mjs:9-55`, base `/guide`, built into `website/guide` (`astro.config.mjs:57-62`), Pagefind search on, absolute asset URLs (`guide/scripts/postbuild.mjs:1-3`). Built size 6.7 MB (shots 4.3 MB, clips 0.9 MB, Pagefind 0.7 MB). `make guide` / `guide-check` (`Makefile:81-90`).
- No Help Book in the bundle; no `CFBundleHelpBookFolder` in `appInfoPlist` (`Project.swift:103-157`).
- **Observed on this Mac (macOS 26.6.2):** there is no standalone Help Viewer app. `/System/Applications/Tips.app` has bundle ID `com.apple.helpviewer`, declares the `help:` URL scheme and the `com.apple.help` (`.help`) document type, and carries `PlugIns/HelpViewer-Quicklook.appex`. So on macOS 26 a Help Book opens in Tips. Skim (`/Applications/Skim.app/Contents/Resources/Skim.help`) is a local third-party book to compare against in the spike.

### 2.3 Localisation today

- `developmentRegion: "en"` (`Project.swift:404`), `CFBundleDevelopmentRegion` from `DEVELOPMENT_LANGUAGE` (`Project.swift:104`). No `.xcstrings` file anywhere in the repo, no `defaultLocalization` in `Packages/SegueUI/Package.swift:13-47` or SegueCore's manifest, no `String(localized:)` or `LocalizedStringResource` in either package.
- About 800 string literals in SwiftUI initialisers across 368 SegueUI source files (`Text(`, `Button(`, `Label(`, `Toggle(`, `Section(`, `Picker(`, `Menu(`, `.help(`, `navigationTitle(`), only 4 `verbatim:` uses. Several menus build titles as plain `String` values (for example `HelpMenuItem.title: String`, `HelpCommands.swift:52`, rendered by `Button(item.title)` at `:21`), which SwiftUI treats as verbatim and would never localise.
- In a Swift package, `Text("Start Show")` looks the key up in `Bundle.main`, not in the package's own bundle. The `#bundle` macro (Foundation, macOS 12+, confirmed in the SDK) gives the package bundle.
- Tools present: `xcrun xcstringstool` (`extract`, `sync`, `compile`, `generate-symbols`); the Xcode MCP server offers `LocalizationPlanner`, `StringCatalogRead`, `StringCatalogEdit` and `StringCatalogContext` (with its translation skills) for P9-5c.

### 2.4 Analytics

- The closed vocabulary is `AnalyticsEvent` (`SegueCore/Sources/Services/AnalyticsEvent.swift:14-95`, rows 1-30, no `String` payloads), `FeatureKey` (`Services/FeatureKey.swift:5-87`), `HelpItem` (`AnalyticsEvent.swift:245-253`). Documented in `docs/release/specs/WS3-services.md` section 5 (rows up to 30 at `:319-321`). Help menu items record `helpOpened` (`HelpCommands.swift:22-24`).

### 2.5 The stage and what must never interrupt it

- `AppModel.live` non-nil means a show (gig or rehearsal) is up; `isPerforming` (`App/AppModel.swift:442-444`); `isStartingShow` blocks a second start (`:431-440`); setting `live` already gates the AI, sound and tips (`:175-184`).
- The stage is a borderless window covering the screen, made key, with `NSApp.presentationOptions = [.hideDock, .hideMenuBar]` (`Live/StageWindowController.swift:40-87`, `:131-137`). On a second display the menu bar is still visible. Stage keys come from a local key monitor on the stage window (`Live/LiveKeyInput.swift`), so **any other Segue window or panel that becomes key steals pedal and keyboard input from the stage**.
- `startShow` refreshes the library, builds the pre-show checklist and only then presents the stage (`App/AppModel+Shows.swift:91-130`).

## 3. Help Book (P9-5a)

### 3.1 Why it helps a gigging musician

Gigs happen in basements, temples, wedding halls and pubs with no signal. The web guide is useless there; a bundled book answers "how do I turn on the metronome" or "why did my Shortcut not run" offline, and the Help menu's search field finds both guide pages and menu items in one box (HIG, The menu bar: "When you use the Help Book format... macOS automatically includes a search field").

### 3.2 Behaviour and UI (R179: an offline Apple Help Book generated from the guide, English; in-app Help buttons open its anchors with the web as fallback; Help is disabled while a show is up)

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

Size: about 6 MB (shots and clips kept, Pagefind dropped; R179). The book documents the App Store flavour, as the guide does today; Personal-only features (LRCLIB) are not in it.

### 3.4 Opening it (APIs)

- `NSApp.showHelp(nil)` for Help > Segue Help (AppKit `NSApplication`; compiled at 26.0). `NSHelpManager.shared.openHelpAnchor(_:inBook:)` for anchors, the book name read from `CFBundleHelpBookName` (`NSHelpManager.h:37`, no deprecation in the SDK header). `NSHelpManager.shared.registerBooks(in:)` is not needed: the main bundle registers itself (`NSHelpManager.h:40`).
- `OpenGuideAction` gains a book route: `guideLinks(_:)` (`GuideHelp.swift:30-32`) builds an action that tries the anchor and falls back to `workspace.open(page.url)`. The help routing lives in a new `App/HelpBook.swift` behind a small protocol (`HelpBookOpening`: `openHome()`, `open(anchor:) -> Bool`) so tests inject a recorder; the live one wraps `NSHelpManager`.
- Anchor names: `SegueLinks.Guide.helpAnchor` maps `https://segue.ryandsilva.dev/guide/go-on-stage#checklist` to `go-on-stage-checklist`, the home to `index`. `gen-site.swift --check` is extended to resolve every `helpAnchor` against `Derived/HelpBook` when it exists.

### 3.5 App Store implications

- A Help Book is ordinary bundled content; no entitlement, no review risk. It also removes the "Help isn't available" class of reviewer impression for good (research 08, section 2).
- It must match the App Store build: the guide already documents that flavour. The book is versioned with the app (its home page names the version), so a reviewer never reads about a feature the build lacks.
- 5.1.1(i) is unchanged: Privacy Policy stays a Help menu item opening the web page.

### 3.6 Spike results (step 0, 2026-11-01, macOS 26.6.2, Xcode 27.1)

- Tips (`com.apple.helpviewer`) opens a third-party book from an app's main bundle: `NSApp.showHelp` shows its home, `openHelpAnchor(_:inBook:)` opens the page holding the anchor. Starlight's CSS, the bundled web fonts, AVIF shots, dark mode (`prefers-color-scheme`) and relative links all render.
- The Help menu's search field lists book topics beside menu items ("metronome" finds the Metronome page).
- A heading anchor (`go-on-stage-checklist`) opens the right page but at its top: Tips did not scroll to the `<a name>` (an `id` on it changed nothing). Page-level anchors are exact; heading anchors land on the page.
- `HPD*` keys as in `Skim.help`: `HPDBookAccessPath`, `HPDBookIndexPath`, `HPDBookTitle`, `HPDBookType` 3, `CFBundleSignature` `hbwr`. The index is `hiutil -I lsm -Caf <out> -s en -l en en.lproj`.
- Built as specced with one change: the help-mode build keeps `base: '/guide'`, so `helpbook.mjs` tells guide pages (`/guide/...`, made relative) from site pages (`/privacy`, made absolute) without guessing. Scripts and the Pagefind box are dropped from the book. Each page's footer names the app version and links "Read this guide online". The book is rebuilt by `scripts/help-book.sh` before every `scripts/xcodebuild.sh` build (a hash of the sources skips it when current), `make help-book-check` (in `make quick`) fails a stale book, and `check_help_book` (verify-appstore for both flavours, verify-archive check 8) checks the shipped book carries every `helpAnchor`. UI test runs use no book (Help logs its web fallback) unless `-SegueHelpBook YES`.

## 4. String Catalogs (P9-5c; R179: English only, catalogs per module in place for later)

### 4.1 Language

- v1.0 ships **English (U.S.), `en`, only** (R179). No second UI language is added, translated or reviewed in this workstream; the catalogs exist so a later language is a translation job, not a code sweep.
- `developmentRegion` stays `en`; the binary's "Languages" line on the product page reads "English".

### 4.2 What is never localised (romanized Hindi untouched)

- Song content in every view, the stage, PDFs and Quick Look: titles, artists, Movie / Album, lyrics, chord names, section labels (including the default "Verse" / "Chorus" labels written into files), comments, notes, setlist names, venues, smart filter names, tag names. These are already `String` values rendered with `Text(_ content: some StringProtocol)`, which is verbatim; the sweep keeps it that way and converts any content literal that slipped into a `LocalizedStringKey` initialiser to `Text(verbatim:)`.
- ChordPro directives and file content written by the app (`{start_of_chorus}`, section labels, `{key}`), and the Welcome library files.
- Search, `RomanNormalizer`, the set composer grammar ("in A", "key of D", "by <artist>") and the set assistant lexicon.
- The AI prompts; analytics vocabulary and log lines; the Help Book and guide.

### 4.3 Catalog layout (R179: per module)

- **One catalog per module that shows text**, Apple's package pattern: `Packages/SegueUI/Sources/SegueUI/Localizable.xcstrings` with `defaultLocalization: "en"` in `Packages/SegueUI/Package.swift`; SegueCore gets a catalog only for the few user-facing messages it owns (pre-show checklist reasons, `FillSpan` errors such as "A fill covers at most 8 bars", `SegueCore/Sources/Library/FillSpan.swift:21`); the app target gets `InfoPlist.xcstrings` (`NSAppleEventsUsageDescription`; `CFBundleDisplayName` stays "Segue"); the Quick Look extensions share SegueUI's catalog through the package bundle.
- **Lookups name their bundle**: every localisable literal in a package uses `bundle: #bundle` (`Text("Start Show", bundle: #bundle)`, `String(localized: "...", bundle: #bundle)`, `LocalizedStringResource("...", bundle: #bundle)`; all compiled at 26.0). A SwiftLint custom rule in the packages flags `Text("`, `Button("`, `Label("`, `Toggle("`, `.help("`, `navigationTitle("` and friends without `bundle:` or `verbatim:`.
- **Menu and model titles** that are `String` today (`HelpMenuItem.title`, `MenuShortcut` titles, `UserMessage` texts, Settings pane names, `SegueLinks.Guide.title`, stage status-line strings) become `LocalizedStringResource`. `MenuShortcut` titles double as lookup keys for tests: tests compare against the resource's key, not the rendered text.
- Extraction: Xcode's build-time extraction (`SWIFT_EMIT_LOC_STRINGS`, default for packages with `defaultLocalization`) fills the catalogs; `make strings` runs `xcrun xcstringstool sync` over the build's `.stringsdata` so the catalogs can be refreshed from the command line, and `make quick` fails when a build adds a key the committed catalog lacks (the "generated, dirty tree fails" pattern).
- Formats: plurals and variables use catalog variations (`"\(count) songs"` with English plural variants), never string concatenation.
- A language change still takes effect on the next launch (macOS behaviour); nothing changes mid-show.

## 5. The four extras (R179)

- **P1 - "Report..." on the error banner** (research #28; the banner has only Dismiss, `SegueRootView.swift:324-347`). A button beside Dismiss opens Report a Problem with the error's `ErrorCode` and message pre-filled (the diagnostics preview shows it). Never shown on stage. Session P9-5b, S effort. Why: a solo developer's support channel; the musician reports the problem when it happens instead of forgetting it before the gig.
- **P2 - Drag a song out to Finder or Messages** (research #19; drop-in exists, `Library/LibraryViews.swift:92`, drag-out does not). Library rows drag their `.cho` as a file (`.draggable` with the file URL), so sending a chart to the bass player is a drag into Messages. Disabled while performing. Session P9-5b, S-M effort.
- **P3 - Quick Look thumbnails** (research #20; the preview extension exists, `Extensions/QuickLook/Sources/PreviewViewController.swift:8`, but `.cho` files show the generic document icon in Finder's icon and gallery views). A thumbnail extension renders the chart's first lines with the same SegueUI renderer. Session P9-5a, M effort (a new extension target, sandboxed, both flavours; `scripts/verify-appstore.sh`'s Quick Look-only `PlugIns` check is extended to allow it).
- **P4 - Launch-time metric** (research #30; unmeasured). One `XCTApplicationLaunchMetric` performance test (no assertion) and a 500-song index timing recorded in `docs/test-performance.md`, so Help Book registration and the catalogs are proven not to slow launch. Session P9-5c, S effort.

## 6. Analytics (non-PII, closed vocabulary, WS3)

Enums, booleans and buckets only. `ServicesVocabularyTests` extended; `docs/release/specs/WS3-services.md` section 5 documents the changes. Everything is sent only after consent, as today.

- Row 14 `Segue.Help.opened` gains `segue.via` (`book`, `web`): which route a Help item or Help button took (the fallback rate shows a broken book). `GuideHelpButton` and Learn More start recording row 14 with a new `HelpItem.contextHelp` (no page name; the page is a closed enum, so `segue.page` with the `SegueLinks.Guide` case name is allowed: rendered values match the vocabulary regex).
- P1: the Report a Problem item of row 14 gains `segue.from` (`menu`, `errorBanner`), so banner reports are counted apart.
- P2: `FeatureKey` (row 8) gains `songDragOut` (context `library`, daily).
- P3 and P4 send nothing (the thumbnail extension has no analytics; the launch metric is a test).

## 7. Guide pages and site

- `troubleshooting.mdx` gains `#help` ("Built-in help": the Help Book, searching it from the Help menu, the online copy, and "Segue Help opens in the browser" for the fallback) and a "Report a problem from an error" line for P1; `SegueLinks.Guide` gains the anchor.
- `library-folder.mdx` (or the page the library rows live on at build time): "Drag a song out to Finder or Messages" (P2), and a line on Finder thumbnails (P3).
- `keyboard.mdx`: no change (no new shortcuts).
- Real screenshots via `make docs-shots` for the new shots only (Tips showing the book, a Finder thumbnail); verify every `SegueLinks.Guide` URL against the local build and every `helpAnchor` against `Derived/HelpBook`, and against the live site once deployed.

## 8. Entitlements and Info.plist (summary)

- **No new entitlement** in either flavour (`App/SegueAppStore.entitlements`, `App/Segue.entitlements` unchanged; `scripts/verify-archive.sh` check 4 still asserts the App Store set exactly).
- `appInfoPlist` (`Project.swift:103-157`) gains `CFBundleHelpBookFolder` and `CFBundleHelpBookName` (3.3). The English localisation comes from the catalogs (Xcode writes the `.lproj` folder; `CFBundleLocalizations` is not hand-maintained).
- Resources: `Derived/HelpBook/Segue.help` in both app targets; `InfoPlist.xcstrings` in both app targets; SegueUI's catalog in its package bundle; the thumbnail extension target (P3) in both flavours.

## 9. Tests (R113 budget)

### 9.1 SegueUI, in-process

- `HelpBookRoutingTests`: every `SegueLinks.Guide` case has a `helpAnchor`; the route tries the book then falls back to the web URL; every Help item and Help button is disabled or a no-op while performing; row 14 `via`.
- `LocalizationCoverageTests`: every localisable key the build emits is in its module's catalog with an `en` value; no stale keys; format specifiers well formed; no catalog key is a content-looking string (a guard list of Welcome song titles).
- `ContentVerbatimTests`: the library row, song page, stage page and Quick Look render of a romanized Hindi Welcome song show the source text unchanged, including "Chorus" section labels, and none of those strings is looked up in a catalog.
- `ErrorBannerReportTests` (P1): the banner's Report... opens Report a Problem with the code and message; absent on stage; row 14 `from`.
- `SongDragOutTests` (P2): a library row's drag item is the song's `.cho` file URL; no drag while performing.
- `QuickLookThumbnailTests` (P3): the thumbnail renderer draws a Welcome chart's first lines in-process (a pixel sample, the existing snapshot support's tolerance).

### 9.2 Build and site checks

- `make help-book` then `guide-check`: no absolute `/guide/` URLs in the book, every anchor present, `Segue.helpindex` built, source hash written; `gen-site.swift --check` resolves every `helpAnchor`; `make quick`'s staleness check on the book and on the catalogs (4.3).

### 9.3 E2E: `SegueMacPolishE2ETests` (new, one class)

- `testHelpOpensTheBook` (P9-5a): Help > Segue Help; Tips (`com.apple.helpviewer`) runs in the foreground; then a Help button in Settings > Live opens it too. Quits Tips at the end.
- Existing UI tests changed: `SegueCoreUXE2ETests+Menus` if it asserts Help menu items (one `make e2e-one` in P9-5a).

### 9.4 Performance (no assertions)

- P4's launch metric and the 500-song index timing, written to `docs/test-performance.md`.

## 10. Sessions and steps

**P9-5a - Help Book and Quick Look thumbnails**

0. Spike (scratch, nothing committed): hand-build a two-page `Segue.help` from the current guide, compare its Info.plist with `Skim.help`, index it with `hiutil`, open it from a Debug build via `NSApp.showHelp` and `openHelpAnchor`; record in this spec: Tips renders Starlight's CSS, dark mode, images and clips; anchors work with `<a name>`; Help menu search finds topics; which `HPD*` keys are needed. Stop and report if Tips cannot open a third-party book on macOS 26.
1. `helpbook.mjs`, the help-mode config branch, `make help-book`, the source hash. Check: `guide-check`.
2. `Project.swift` resources and Info.plist keys, the build-phase presence check, `verify-archive.sh` anchor check.
3. `HelpBook.swift`, `SegueLinks.Guide.helpAnchor`, `OpenGuideAction` book route with web fallback, Help menu changes and performing guards, row 14 `via` / `contextHelp`. Suite: `HelpBookRoutingTests`, `ServicesVocabularyTests`.
4. P3 (Quick Look thumbnails). Suite: `QuickLookThumbnailTests`; `make verify-appstore` once for the extension check.
5. Guide `#help` section and the thumbnail line; `testHelpOpensTheBook`. ONE `make quick`, ONE `make e2e-one` for `SegueMacPolishE2ETests` and for any changed menu test class.

**P9-5b - Report... and drag-out** (independent)

1. P1 (Report... on the error banner), row 14 `from`. Suite: `ErrorBannerReportTests`, `ServicesVocabularyTests`.
2. P2 (drag a song out), `FeatureKey.songDragOut`. Suite: `SongDragOutTests`.
3. Guide lines (section 7). ONE `make quick`.

**P9-5c - String Catalogs and the launch metric** (last in the Phase 9 wave, after the sibling P9 UI work lands)

1. Infrastructure: `defaultLocalization`, catalogs, `InfoPlist.xcstrings`, the SwiftLint rule, `make strings`, the staleness check.
2. The sweep, module by module (one commit per folder of `SegueUI/Sources/SegueUI/`): `bundle: #bundle`, `LocalizedStringResource` for model titles, `verbatim:` for content; build green after each folder. Suites: the folder's existing in-process suites.
3. `LocalizationCoverageTests`, `ContentVerbatimTests`.
4. P4 (launch metric) and its `docs/test-performance.md` entry. ONE `make quick`; launch the app for Ryan's walkthrough.

## 11. Done criteria

- Help > Segue Help and every in-app Help button open the bundled Help Book in Tips at the right anchor, offline; Help menu search finds book topics; the web page opens only as a logged fallback; nothing in Help opens while a show is up or starting; the book is rebuilt from the guide source and a stale book fails `make quick`; the archive check finds every anchor.
- Every UI string is in its module's String Catalog, English only; song content, chord names, section labels and romanized Hindi are verbatim and never catalog keys.
- The error banner's Report... pre-fills Report a Problem; a library song drags out as its `.cho`; Finder shows chart thumbnails for `.cho` files; the launch time is recorded.
- No new entitlement; Info.plist keys as in section 8.
- Analytics changes as in section 6, closed vocabulary only, documented in WS3.
- Guide edits of section 7 published with real screenshots; links verified locally and on the live site.
- Every 9.1 suite passes; `make quick` green; `make e2e-one` green for `SegueMacPolishE2ETests` and each changed class; the app launched for Ryan.

## 12. Closed questions (R179, 2026-11-01)

1. **UI languages for v1.0:** English only, with String Catalogs per module in place for later (R179; section 4).
2. **Catalog layout:** one catalog per module with `bundle: #bundle` and a lint rule (R179; 4.3).
3. **Help Book form:** an offline Apple Help Book generated from the guide, opened in Tips (R179; section 3).
4. **Help Book language:** English (R179; 4.2).
5. **In-app Help buttons:** open the book's anchors, the web as fallback (R179; 3.2, 3.4).
6. **Help while performing:** disabled while a show is up or starting (R179; 3.2).
7. **Extras:** Report... on the error banner, dragging a song out to Finder or Messages, Quick Look thumbnails and a launch-time metric (R179; section 5).
