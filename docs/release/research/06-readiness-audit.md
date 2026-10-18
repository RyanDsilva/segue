# 06 - Mac App Store readiness audit (SegueAppStore)

Date: 2026-10-17. Scope: the `SegueAppStore` target, scheme `Segue-AppStore`, configuration `Release-AppStore` (the one that ships). Read-only audit of sources, the Tuist manifests, the real build settings (`xcodebuild -showBuildSettings -configuration Release-AppStore`) and the existing signed product at `.build/DerivedData-verify/Build/Products/Release-AppStore/Segue.app` (left there by `make verify-appstore`).

Kinds: `blocker` (cannot ship), `required-change` (must fix before submission or review is likely to bounce), `polish` (should fix, not gating), `ok` (checked and fine).

## Summary

| Kind | Count |
|---|---|
| blocker | 2 |
| required-change | 7 |
| polish | 7 |
| ok | 15 |

## Findings

### Blockers

| # | Citation | Summary | Suggested fix |
|---|---|---|---|
| B1 | Project.swift:12, Project.swift:24-32, docs/decisions.md:8, JOURNAL.md:18 | Signing is the free Personal Team `V6BM673U35` with identity `Apple Development`. A free team cannot create Mac App Store distribution certificates/profiles or an App Store Connect record, so an archive can be built but never exported or uploaded. | Enrol in the paid Apple Developer Program, set `developmentTeam` to the paid team ID, register `dev.ryandsilva.segue` under that team (if the free team holds it, it may need to lapse first), regenerate. |
| B2 | JOURNAL.md:36 | No privacy policy URL or support URL exists anywhere (repo, app, docs). App Store Connect requires a privacy policy URL for every app and a support URL for every version; submission cannot be completed without them. | Publish a short privacy policy ("Segue collects no data; songs stay in the folder you choose") and a support page (e.g. GitHub Pages / personal site), enter both in App Store Connect, and reuse the support URL in the Help menu (P2). |

### Required changes

| # | Citation | Summary | Suggested fix |
|---|---|---|---|
| R1 | Project.swift:109-115, Packages/SegueCore/Sources/Library/SongFiles.swift:311, Packages/SegueCore/Sources/Library/SongFiles.swift:316 | `ITSAppUsesNonExemptEncryption` is missing. The only crypto is CryptoKit SHA-256 hashing (exempt). Without the key every upload stops for an export-compliance questionnaire. | Add `"ITSAppUsesNonExemptEncryption": false` to the `infoPlist` dictionary. |
| R2 | Project.swift:112-113, Derived/InfoPlists/SegueAppStore-Info.plist:21-24 | Version `0.1.0` and build `1` are literals in the Info.plist; `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` are unset. Every upload needs a strictly increasing `CFBundleVersion`, and the About panel would show "0.1.0 (1)" publicly. | Set `MARKETING_VERSION` (1.0.0 for launch) and `CURRENT_PROJECT_VERSION` as build settings, reference them as `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` in the plist, and bump the build number per upload (script or `agvtool` in the archive target). |
| R3 | Project.swift:119 (resources: only the icon); see required-reason table below | No app-level `PrivacyInfo.xcprivacy`. The app uses UserDefaults, file timestamp APIs and `CACurrentMediaTime` (mach_absolute_time based). Only GRDB's bundle ships a manifest (empty). | Add `App/PrivacyInfo.xcprivacy` to the target resources with `NSPrivacyTracking=false`, no collected data, and accessed-API reasons: UserDefaults `CA92.1`; file timestamp `3B52.1` (user-granted library folder) plus `C617.1` (container files); system boot time `35F9.1`. Declare "Data Not Collected" in App Store Connect. |
| R4 | Packages/SegueUI/Sources/SegueUI/Editor/SourceTextView.swift:35-38, Packages/SegueUI/Sources/SegueUI/Editor/SongEditorViewModel.swift:364, Packages/SegueUI/Sources/SegueUI/Editor/EditorPerformance.swift:78-91 | Release builds log editor performance to the unified log, and the slow-key line logs the typed character with `privacy: .public`, i.e. fragments of the user's lyrics end up readable in Console. Confirmed in the Release-AppStore binary (`slow key %{public}s`). | Drop the character from the message (or use `.private`), and gate the hitch monitor and slow-key/keystroke logging behind `#if DEBUG` or `UITesting.isActive`. |
| R5 | Packages/SegueCore/Sources/Shows/LiveSettings.swift:23-24, Packages/SegueCore/Sources/Shows/LiveSettings.swift:43-44, Packages/SegueUI/Sources/SegueUI/App/AppModel+Shows.swift:364-386, Packages/SegueUI/Sources/SegueUI/Live/ShortcutRunner.swift:36-46 | Default settings run Shortcuts named "Gig Mode On"/"Gig Mode Off" on every gig. On a reviewer's clean machine those Shortcuts do not exist: starting a gig bounces to the Shortcuts app with a "not found" error, and the pre-show checklist still reports `.ran` (handover succeeded), so "Focus on" is ticked untruthfully. | Default both Shortcut names to nil (opt-in in Settings > Live with a short explainer), or check existence before running and report "not found" honestly. Mention the optional Shortcut setup in App Review notes. |
| R6 | Packages/SegueUI/Sources/SegueUI/SegueRootView.swift:99-103, Packages/SegueUI/Sources/SegueUI/Library/LibraryViews.swift:122-130 | First launch for a reviewer: create/choose a library, then an empty library with only "New Song". No sample content or guidance; live mode needs a setlist with songs, so a reviewer must type several ChordPro songs to see the core feature (Guideline 2.1 risk). | Write App Review notes with a 60-second walkthrough, and add an "Add Sample Songs" action on the empty state that writes 2-3 public-domain or original songs plus a sample setlist into the chosen library (no copyrighted lyrics). |
| R7 | Makefile:41-42, Makefile:71-72, Project.swift:182, scripts/verify-appstore.sh:132-136 | No archive/export path: the Makefile only builds `Debug-AppStore`, there is no `ExportOptions.plist`, and `verify-appstore` checks the build products, not the archived/exported `.app` that is uploaded. | Add `make archive-appstore` (xcodebuild archive with `-allowProvisioningUpdates`, then `-exportArchive` with `method = app-store-connect` and the paid team ID) and run the verify-appstore bundle/entitlement checks against the exported app. |

### Polish

| # | Citation | Summary | Suggested fix |
|---|---|---|---|
| P1 | Project.swift:109, Derived/InfoPlists/SegueAppStore-Info.plist:31-32 | Tuist's default plist adds `NSMainStoryboardFile = Main` (and `CFBundleIconFile = ""`), but there is no storyboard; harmless today but misleading and a possible launch-time warning. | Switch `infoPlist` from `.extendingDefault` to an explicit `.dictionary` (or `.file`) so `NSMainStoryboardFile` is not emitted and the shipped plist only has real keys. |
| P2 | Packages/SegueUI/Sources/SegueUI/SegueRootView.swift:298-345 | No Help command group: the default Help menu shows "Help isn't available for Segue". | `CommandGroup(replacing: .help)` with "Segue Support" (opens the support URL via `openURL`; no network entitlement needed) and optionally "ChordPro Reference". |
| P3 | Project.swift:114, Packages/SegueUI/Derived/InfoPlists/SegueUI_SegueUI-Info.plist:19-20 | App copyright reads "Copyright 2026 Ryan D'Silva" (fine, no ©); the SegueUI resource bundle ships Tuist's placeholder "Copyright ©. All rights reserved." and bundle id `SegueUI.generated.resources` (not prefixed by the app id). | Use "© 2026 Ryan D'Silva"; set the resource bundle's copyright and a `dev.ryandsilva.segue.SegueUI-resources` style identifier via Tuist package settings. |
| P4 | Project.swift:43, Project.swift:107, Packages/SegueUI/Sources/SegueUI/App/SingleInstance.swift:33-37, docs/decisions.md:107 | Personal and App Store flavors share the bundle id. If both are on one Mac (e.g. dev build plus the store build) they share the sandbox container, defaults and bookmark, and the single-instance guard hands one over to the other. Deliberate per decisions.md, but a TestFlight/store copy next to the dev copy will cross-talk. | Accept and document, or give the Personal flavor a `.personal` suffix (separate container). |
| P5 | Packages/SegueUI/Sources/SegueUI/SegueRootView.swift:99-113 | No String Catalog; many user-facing strings are built as `String` (not `LocalizedStringKey`), so they would not be extracted. Fine for an English-only v1. | Leave for v1; add `Localizable.xcstrings` and `String(localized:)` when localising. |
| P6 | Packages/SegueUI/Sources/SegueUI/Live/ShortcutRunner.swift:63-85, App/Sources/LaunchOptions.swift:19-103 | Test-only types (RecordingShortcutRunner, launch-option parser) are compiled into Release; unreachable because parsing is `#if DEBUG` (App/Sources/SegueApp.swift:44-50). | Optionally wrap them in `#if DEBUG` to keep test hooks out of the shipping binary. |
| P7 | docs/decisions.md:80-82 | Store name "Segue - Setlists & Chords"; "SEGUE EDITOR" is a live US registration (audio software) and the manual USPTO search is still open. | Run the USPTO/App Store name check before reserving the name in App Store Connect. |

### OK

| # | Citation | Summary |
|---|---|---|
| O1 | App/Segue.entitlements:5-10 | Shipping entitlements are minimal: app-sandbox, files.user-selected.read-write, files.bookmarks.app-scope. Signed Release-AppStore product confirms exactly these (plus `get-task-allow` from the development signature, which App Store export re-signing removes). No network client/server, no Apple Events, no camera/mic. |
| O2 | App/Segue-Debug.entitlements:11-15, Project.swift:126, Project.swift:136-139, scripts/verify-appstore.sh:116-130 | The `/private/tmp/segue-e2e/` temporary exception exists only in Debug-Personal; the AppStore target never gets it, and verify-appstore asserts it is absent from Release-AppStore, Debug-AppStore and Release-Personal. |
| O3 | Packages/SegueUI/Sources/SegueUI/Live/ShortcutRunner.swift:36-46 | Shortcuts integration uses `NSWorkspace.open(shortcuts://...)`, which needs no automation/Apple Events entitlement under the sandbox. |
| O4 | Project.swift:52, Project.swift:72, Project.swift:177-185 | A `Release-AppStore` configuration exists and is the scheme's archive and profile configuration. Real build settings: `-O`, no `DEBUG` condition, `ENABLE_DEBUG_DYLIB = NO`, `STRIP_INSTALLED_PRODUCT = YES`, dSYM, hardened runtime, universal arm64 + x86_64. An archive builds and signs today; only distribution is blocked (B1). |
| O5 | Project.swift:98-101, App/Sources/SegueApp.swift:87-93, scripts/verify-appstore.sh:24-111 | SeguePersonalModules is linked only by the Personal target and mechanically checked absent from the AppStore build graph, link map, bundle and symbols. |
| O6 | Packages/SegueUI/Package.swift:28-35, Packages/SegueCore/Package.swift:111-112 | Shipped bundle contents (inspected): icon, Assets.car, 5 Schibsted Grotesk TTFs + OFL.txt, GRDB/Tonic licence texts, GRDB privacy manifest. No sample songs, fixtures, test data or lyrics; SegueCore fixtures belong to the test target only. |
| O7 | Packages/SegueUI/Sources/SegueUI/App/AcknowledgementsView.swift:26-48, App/Sources/SegueApp.swift:103-110, Packages/SegueUI/Sources/SegueUI/SegueRootView.swift:299-303 | Segue > Acknowledgements window credits Schibsted Grotesk (OFL 1.1), GRDB (MIT), Tonic (MIT) with full licence texts; bundled texts match upstream LICENSE files for GRDB 7.11.1 and Tonic 2.1.2 (no other transitive dependencies in Tuist/Package.resolved). |
| O8 | Project.swift:111, Derived/InfoPlists/SegueAppStore-Info.plist:25-30 | `LSApplicationCategoryType = public.app-category.music`, `LSMinimumSystemVersion = $(MACOSX_DEPLOYMENT_TARGET)` = 26.0, `NSHumanReadableCopyright` present, `CFBundleDisplayName = Segue`. |
| O9 | App/Sources/SegueApp.swift:44-50, Packages/SegueUI/Sources/SegueUI/App/UITesting.swift:9-15 | Test launch arguments and UI-test instrumentation are honoured in Debug only; the Release-AppStore binary contains no `-SegueLibraryPath` string. No `print`/`NSLog`, no hardcoded `/tmp` or `/Users` paths in shipping sources. |
| O10 | Packages/SegueUI/Sources/SegueUI/SegueRootView.swift:37-97, Packages/SegueUI/Sources/SegueUI/App/LibraryLocation.swift:68-69, Packages/SegueUI/Sources/SegueUI/App/LibraryLocation.swift:145-176 | No library folder on a fresh account: the chooser appears (Create in Music / Choose Existing). Panels grant user-selected access, the folder is created inside the granted URL, and a missing `~/Music/Segue` falls back to `~/Music`. |
| O11 | Packages/SegueCore/Sources/Shows/InputBindings.swift:191-193, Packages/SegueCore/Sources/Diagrams/ShapeResolver.swift:48-52, Packages/SegueUI/Sources/SegueUI/App/AppModel.swift:51-55 | Application Support files (bindings, shape library) live in the sandbox container, a missing file falls back to defaults, and the directory is created on first write. No crash path found for a clean machine. |
| O12 | Packages/SegueUI/Sources/SegueUI/App/SingleInstance.swift:10-28, Packages/SegueUI/Sources/SegueUI/Editor/UnsavedChangesGuard.swift:66-71 | Single-instance guard picks the earliest launch with a pid tie-break, so two simultaneous launches never both quit; it runs before any window or library opens. |
| O13 | Packages/SegueUI/Sources/SegueUI/Library/SongMetadataViews.swift:182, Packages/SegueUI/Sources/SegueUI/Setlists/SetEntriesList.swift:245, Packages/SegueUI/Sources/SegueUI/Setlists/BuilderLibraryColumn.swift:179, Packages/SegueUI/Sources/SegueUI/GigLog/GigDetailView.swift:198, Packages/SegueUI/Sources/SegueUI/Editor/EditorTopBar.swift:248 | Accessibility spot check: icon-only buttons (remove tag, remove entry, add to set, rating stars, steppers) carry labels; decorative icons are hidden or merged (GigLogViews.swift rating). |
| O14 | Packages/SegueUI/Sources/SegueUI/Theme/Tokens.xcassets/ink.colorset/Contents.json:16, Packages/SegueUI/Sources/SegueUI/Live/StageWindowController.swift:112 | Light/dark: colour tokens carry dark appearance variants; the stage is forced dark by design. |
| O15 | Packages/SegueUI/Sources/SegueUI/Live/PowerSource.swift:18-21, Packages/SegueUI/Sources/SegueUI/Live/KeepAwake.swift:9 | IOKit power-source read and `ProcessInfo.beginActivity` (keep display awake) need no entitlement in the sandbox. Re-check "Charger connected" once in a sandboxed Release run. |

## Details

### 1. Entitlements and Info.plist (Release-AppStore)

- Entitlements file: `App/Segue.entitlements` for every configuration of `SegueAppStore` (`CODE_SIGN_ENTITLEMENTS = App/Segue.entitlements` in the real Release-AppStore settings). Signed product shows `app-sandbox`, `files.user-selected.read-write`, `files.bookmarks.app-scope`, `get-task-allow` (development signature only). `ENABLE_OUTGOING_NETWORK_CONNECTIONS = NO`, `ENABLE_INCOMING_NETWORK_CONNECTIONS = NO`. No temporary exceptions.
- Shipped Info.plist (built product): CFBundleIdentifier `dev.ryandsilva.segue`, CFBundleShortVersionString `0.1.0`, CFBundleVersion `1`, LSApplicationCategoryType music, LSMinimumSystemVersion 26.0, NSHumanReadableCopyright, CFBundleIconName/IconFile `Segue`, plus stray `NSMainStoryboardFile = Main` (P1). Missing: `ITSAppUsesNonExemptEncryption` (R1). Versions are literals (R2).

### 2. Configurations and signing

- Configurations: Debug-Personal, Release-Personal, Debug-AppStore, Release-AppStore (Project.swift:49-52). The Segue-AppStore scheme archives with Release-AppStore.
- Release-AppStore signing: `CODE_SIGN_STYLE = Automatic`, `DEVELOPMENT_TEAM = V6BM673U35` (free Personal Team), `CODE_SIGN_IDENTITY = Apple Development`, hardened runtime on. The existing product is signed "Apple Development: Ryan Rony Dsilva", TeamIdentifier V6BM673U35.
- Does an archive make sense today? It builds and signs (useful as a dry run of the Release-AppStore build and of verify-appstore), but cannot be exported for App Store distribution or uploaded until B1 is resolved. `Apple Development` as the build identity is fine for automatic signing; Xcode re-signs with Apple Distribution at export.

### 3. Privacy manifest and required-reason APIs

No `PrivacyInfo.xcprivacy` for the app or for SegueCore/SegueUI. GRDB ships one (empty arrays) inside `GRDB_GRDB.bundle`. Tonic ships none and uses none of the listed APIs.

| Category | Use | Citation | Reason code |
|---|---|---|---|
| UserDefaults | Library folder bookmark | Packages/SegueUI/Sources/SegueUI/App/LibraryLocation.swift:69, Packages/SegueUI/Sources/SegueUI/App/LibraryLocation.swift:99 | CA92.1 |
| UserDefaults | Live settings | Packages/SegueUI/Sources/SegueUI/Settings/LiveSettingsStore.swift:31, Packages/SegueUI/Sources/SegueUI/Settings/LiveSettingsStore.swift:38, Packages/SegueUI/Sources/SegueUI/Settings/LiveSettingsStore.swift:44, Packages/SegueUI/Sources/SegueUI/Settings/LiveSettingsStore.swift:56 | CA92.1 |
| UserDefaults | Test suite (Debug runs only, code ships) | App/Sources/LaunchOptions.swift:114, App/Sources/LaunchOptions.swift:123, Packages/SegueUI/Sources/SegueUI/App/UITesting.swift:11 | CA92.1 |
| File timestamp | `resourceValues` contentModificationDate / creationDate | Packages/SegueCore/Sources/Support/FileSystem.swift:187-193 | 3B52.1 (user-selected library), C617.1 (container files) |
| File timestamp | mtime change detection, created date into index | Packages/SegueCore/Sources/Library/SongFiles.swift:14, Packages/SegueCore/Sources/Library/SongFiles.swift:194, Packages/SegueCore/Sources/Library/SongFiles+Scan.swift:195 | 3B52.1 |
| System boot time | `CACurrentMediaTime` (mach_absolute_time based) for keystroke timing | Packages/SegueUI/Sources/SegueUI/Editor/SourceTextView.swift:29, Packages/SegueUI/Sources/SegueUI/Editor/CanvasViews.swift:58, Packages/SegueUI/Sources/SegueUI/Editor/EditorPerformance.swift:79 | 35F9.1 (or remove in Release with R4) |
| Monotonic clock | `SuspendingClock` for auto-scroll | Packages/SegueCore/Sources/Support/Clock.swift:58, Packages/SegueUI/Sources/SegueUI/Live/LiveDependencies.swift:57 | Not a listed API (Swift runtime); covered anyway by 35F9.1 |
| Disk space | none found | - | - |
| Active keyboards | none found | - | - |

### 4. Bundled resources

Inspected `Segue.app/Contents/Resources`: `Segue.icns`, `Assets.car`, `SegueUI_SegueUI.bundle` (token Assets.car, Fonts/*.ttf + OFL.txt, Licenses/GRDB.txt, Licenses/Tonic.txt), `GRDB_GRDB.bundle` (PrivacyInfo.xcprivacy). No sample songs, fixtures, lyrics, test data or debug menus. `ThemeSwatchView` is compiled in but never presented. Log noise: only the `editor-perf` Logger (R4).

### 5. Legal and attribution

Acknowledgements window exists and is reachable from the app menu (after About). Licence texts verified identical to upstream. The OFL requires the licence to travel with the font: satisfied (OFL.txt in bundle and shown in-app). About panel is the SwiftUI default: icon, name, version (fix in R2), copyright (P3).

### 6. First-launch UX for a reviewer

Fresh sandbox: chooser screen with "Create Library in Music..." (save panel prefilled `~/Music/Segue`) or "Choose Existing Folder...". Then an empty library ("No Songs Yet" + New Song). No sample content or onboarding (R6). Starting a gig runs non-existent default Shortcuts (R5). Help menu is the empty default (P2). The app contains no web links at all; support and privacy URLs must be created (B2).

### 7. Clean-machine robustness

No assumptions about pre-existing directories: library folder created by the save panel flow, `.segue/`, setlists, shows and timings directories are created on demand (LibraryStore.swift:107, SetlistStore.swift:88, ShowStore.swift:77, DurationSamples.swift:82 under Packages/SegueCore/Sources). Real home is read via `getpwuid` only to seed panel locations (LibraryLocation.swift:58-63), never for direct file access. Single-instance edge: shared bundle id with the Personal build (P4).

### 8. Quality

Accessibility spot check passed (O13). Localisation: English-only, no String Catalog (P5). Dark/light both supported via asset-catalog appearances (O14).
