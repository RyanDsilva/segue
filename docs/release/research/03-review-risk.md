# 03 - Mac App Store review risk

Research date: 2026-10-17. Scope: the `SegueAppStore` target only (Release-AppStore), as built from `Project.swift`, `App/`, `Packages/SegueCore`, `Packages/SegueUI`. `Packages/SeguePersonalModules` is not linked (enforced by `scripts/verify-appstore.sh`).

Guidelines text below was read from the live page on 2026-10-17, which reports "Last Update: October 16, 2026" (https://developer.apple.com/app-store/review/guidelines/). Items marked UNVERIFIED come from secondary sources or inference only.

Ryan's decisions already taken (2026-10-17): free, no IAP; v1 creates a deletable "Welcome" library of 3-5 original demo songs (one in romanized Hindi) plus a demo setlist on first run; internal TestFlight first, then App Store review; support email `segue@ryandsilva.dev`, site `segue.ryandsilva.dev`.

**Scope update (2026-10-17, later):** v1 also ships usage analytics (TelemetryDeck, Aptabase, or an own endpoint - undecided), an in-app bug report that sends diagnostics, a feature-request board link, and in-app links to the privacy policy and terms. This adds `com.apple.security.network.client` and means the App Privacy label can no longer be "Data Not Collected". Section 8 covers the consequences; the code audit below describes the tree as it is today (no network code yet).

## 1. Summary

Overall risk is **low-to-medium**. Today the App Store flavor is a sandboxed, offline, single-bundle utility with no network entitlement, no accounts, no IAP, no third-party SDKs. With the scope update, **analytics consent (5.1.1(ii)) becomes the single largest review risk** - see item 0 and section 8. The other likely rejection causes are reviewer-experience and metadata issues:

0. **Analytics without consent** (5.1.1(ii): "Apps that collect user or usage data must secure user consent for the collection, even if such data is considered to be anonymous", plus "an easily accessible and understandable way to withdraw consent"). Read literally this calls for opt-in. Recommendation: opt-in on first run, toggle in Settings, privacy label and policy that name the vendor.

1. **Missing in-app privacy policy link** (5.1.1(i) now requires the link both in App Store Connect *and* "within the app in an easily accessible manner"). Nothing in the app links to one today. Required fix.
2. **No way to reopen the main window from the menu bar** after closing it (Guideline 4 Design, a classic Mac rejection). `SegueCommands` replaces the `.newItem` group, which removes SwiftUI's "New Window" item. Required fix.
3. **Reviewer has no content** (2.1 / 4.2). Resolved by Ryan's Welcome-library decision, provided the demo songs are genuinely original and the romanized Hindi one does not reuse any film-song title or line.
4. **Copyrighted lyrics in screenshots/previews** (2.3.9, 5.2.1). Screenshots must be made from the Welcome library, never Ryan's real library.
5. **Gig Mode Shortcuts default ON** with names "Gig Mode On/Off" (`Packages/SegueCore/Sources/Shows/LiveSettings.swift:23-24`). On a reviewer's Mac those Shortcuts do not exist, so "Start Show" hands `shortcuts://run-shortcut?name=Gig%20Mode%20On` to the Shortcuts app, which is likely to surface a "shortcut not found" error and possibly come forward (UNVERIFIED exact behavior on macOS 26). Looks like a bug to a reviewer. Decision for Ryan.

## 2. Risk table

| Guideline | What it says (short) | Segue status | Risk | Mitigation |
|---|---|---|---|---|
| 2.1(a) App completeness | Final build, no placeholder/temporary content, no crashes; demo account if login | No login. Empty library on first launch today. Editor placeholder (`SongEditorViewModel.placeholder`) is instructional ChordPro template text - fine. | Med -> Low after Welcome library | Ship Welcome library; TestFlight soak on a clean Mac account; test first launch with no `~/Music/Segue`. |
| 2.1(b) IAP | IAP visible and complete | None | n/a | - |
| 2.3.1(a) Notes for Review | New features "described with specificity"; generic descriptions rejected | - | Low | Use the draft notes in section 5. |
| 2.3.3 / 2.3.4 Screenshots, previews | App in use; previews only screen captures | Not made yet | Low | Capture from Welcome library, stage mode + editor + setlist. |
| 2.3.5 Category | Most appropriate category | `LSApplicationCategoryType = public.app-category.music` | Low | Primary Music; secondary Productivity optional. |
| 2.3.6 Age rating | Answer honestly | See section 6 | Low | 4+. |
| 2.3.7 Name/keywords | Unique name, <=30 chars, no trademark stuffing, subtitle may not reference other apps | "Segue - Setlists & Chords" = 25 chars | Low | Do not put "OnSong", "Ultimate Guitar", "SongbookPro", "Bollywood" song names, etc. in keywords. "ChordPro" as a descriptive format keyword is nominative (trademark status UNVERIFIED; no registration found). |
| 2.3.8 Metadata 4+ | Icons/screenshots appropriate for 4+ | Icon is a taped setlist | Low | - |
| 2.3.9 Rights to materials | You must own rights to everything in screenshots | Risk if screenshots show real songs | **Med** | Only original demo songs in screenshots/preview. |
| 2.3.10 Other platforms | No names/imagery of other platforms | Shipped sources have no iOS/Android/Windows mentions in UI (only a `windowsCP1252` decoder, invisible). | Low | Don't write "iPhone version coming" in description. |
| 2.4.5(i) Sandbox | Sandboxed, follow file system docs | `com.apple.security.app-sandbox`, `files.user-selected.read-write`, `files.bookmarks.app-scope` only (`App/Segue.entitlements`). Library created via save panel; Debug-only `/tmp` exception verified absent from AppStore products by `scripts/verify-appstore.sh`. | Low | Keep the verify script in the release checklist. |
| 2.4.5(ii) Self-contained, Xcode packaging | No installers, no shared-location installs | Single .app, fonts/licences in SegueUI resource bundle | Low | - |
| 2.4.5(iii) No auto-launch / lingering processes; no Dock/desktop icons | - | No login item, no helper, no `SMAppService`. Shortcuts runs in Shortcuts' own process, user-configured. | Low | - |
| 2.4.5(iv) / 2.5.2 No downloaded code | - | No downloaded code; network (planned) only sends analytics/bug reports; no MLX/model download in v1 | Low | Revisit when phase 3 AI ships: Foundation Models is fine; an MLX *weights* download is data not code, but 4.2.3(ii) then requires disclosing size and prompting first. |
| 2.4.5(v)-(vii) Root, licence screen, own updater | - | None | Low | - |
| 2.4.5(viii) / 2.5.1 Current OS, public APIs | - | macOS 26 min; public APIs (IOKit.ps power source read, `ProcessInfo` activity, NSWorkspace URL open) | Low | - |
| 2.4.5(ix) Localizations in bundle | - | English only | Low | - |
| 2.5.9 Don't alter native UI behaviors | - | Stage mode sets `NSApp.presentationOptions = [.hideDock, .hideMenuBar]` only while performing, restored on exit (`StageWindowController.swift:85,121`); Esc / End Show exits | Low | Mention in review notes so the reviewer knows how to leave stage mode. |
| 2.5.14 Recording user activity | Consent + indicator when recording | Gig log is user-entered; Segue records no audio or video | Low | - |
| 4 Design (Mac) | Main window must be reopenable from the menu | `.newItem` group replaced by "New Song" -> no "New Window"; no Window-menu entry for the main window | **Med-High** | Add a Window menu item (e.g. "Library" Cmd-0) calling `openWindow(id: "segue.main")`, or quit on last window close. |
| 4.1 Copycats | Don't copy other apps/brands | Own name, own brand | Low | USPTO check on "Segue" still open (vision doc). |
| 4.2 Minimum functionality | Lasting utility | Editor, transpose, diagrams, setlists, stage mode, gig log | Low | Welcome library shows it off. |
| 4.2.3(i) Works without another app | - | Shortcuts optional | Low (Med if defaults stay on) | Make Gig Mode opt-in or describe as optional in notes. |
| 5.1.1(i) Privacy policy | Link in ASC **and within the app** | No link anywhere in the app | **High (certain finding)** | Publish `https://segue.ryandsilva.dev/privacy`; add "Privacy Policy" to the Help menu (and optionally Acknowledgements window). Opening a URL via `NSWorkspace.open` needs no network entitlement. |
| 5.1.1(ii) Consent | Consent for user or usage data "even if ... anonymous"; easy withdrawal; paid features may not depend on it | Analytics + bug-report diagnostics planned | **High if opt-out / silent; Low if opt-in** | First-run consent choice (default off or an explicit Yes/No), Settings > Privacy toggle that stops sending immediately, review notes say where the toggle is. |
| 5.1.1(iii) Minimization | Only data needed for the task | Analytics events, diagnostics | Med | No lyrics, song titles, file paths or library names in events or diagnostics; event allowlist in code; bug report shows the exact payload before sending. |
| 5.1.2(i) Data use and sharing | Disclose third parties; share only to improve the app or serve ads; ATT for tracking | Analytics vendor is a third party (unless own endpoint) | Med | Name the vendor in the privacy policy with the "same or equal protection" statement (5.1.1(i)); no cross-app identifiers, so no ATT prompt (ATT is only for tracking). |
| Third-party AI (5.1.2(i)) | Disclose and get permission before sharing with third-party AI | No AI in v1 | Low | When phase 3 ships, on-device only, so nothing to disclose; reconfirm then. |
| Network entitlement | `com.apple.security.network.client` | Needed for analytics/bug report | Low | Normal for sandboxed apps; describe network use in review notes. Never add `network.server`. |
| Links out (feature board, privacy, terms) | 2.1 "fully functional URLs"; age-rating "unrestricted web access" | Planned | Low | Open in the default browser with `NSWorkspace.open` (or SwiftUI `Link`/`openURL`), not an in-app `WKWebView`; then "unrestricted web access" stays No. If an in-app web view is used, lock it to the own domain with no address bar. Board must be live and public at review time. |
| 5.2.1 IP | Don't use protected material | No bundled songs today; test fixtures (`Packages/SegueCore/Tests/Fixtures`) are test-target resources only and are original ("Lanterns on the Water" etc.) | Low -> watch demo content | Demo songs must be written by Ryan; avoid real film-song titles (note `docs/decisions.md` uses "tum hi ho" as an example; that is the title of a real 2013 film song - do not use it in the Welcome library or screenshots). |
| 5.2.1 user content | Users type/import lyrics | User's own files, stored locally, never distributed | Low | Don't advertise "import any song from the web"; personal URL/LRCLIB import is not in this flavor. |
| 5.2.2 Third-party services | Must be permitted by the service ToS | No third-party services in AppStore flavor | Low | Keep `scripts/verify-appstore.sh` green. |
| 5.2.5 Apple products | Don't look like Apple apps | Distinct brand | Low | "Shortcuts" is an Apple trademark: refer to it as "the Shortcuts app", don't use its icon in screenshots. |
| 1.2 UGC | Filters/reporting/blocking for apps where users share content | No sharing, no server; PDF export later is local | Low | Not UGC in the 1.2 sense. |
| 3.1 Payments | - | Free, no IAP | n/a | - |
| Export compliance | ASC asks about encryption on every upload | `ITSAppUsesNonExemptEncryption` not set | Low (friction) | Add `ITSAppUsesNonExemptEncryption = NO` to Info.plist in `Project.swift` (app uses no encryption beyond OS). |
| Privacy manifest | `PrivacyInfo.xcprivacy` | None in app; GRDB 7.11.1 ships its own (`GRDB/PrivacyInfo.xcprivacy`) | Low | Secondary sources say required-reason API declarations are not enforced for macOS (UNVERIFIED; Apple's page did not render). Adding an app-level manifest declaring no tracking/no collected data and `NSPrivacyAccessedAPICategoryUserDefaults` (CA92.1) + file timestamp (C617.1) is cheap insurance. |

## 3. Shipping-bundle audit (what really ships)

Read from source, not from a built archive (a sibling or Ryan should confirm on the actual `.xcarchive`).

- **Resources in the App Store app:** `design/icon/Segue.icon`; SegueUI resource bundle with `Theme/Tokens.xcassets`, Schibsted Grotesk TTFs + `OFL.txt`, `App/Licenses/GRDB.txt`, `App/Licenses/Tonic.txt` (MIT, "Copyright (c) 2022 Audulus LLC"). Acknowledgements window lists all three (`Packages/SegueUI/Sources/SegueUI/App/AcknowledgementsView.swift`). Good: OFL and MIT notice obligations met.
- **No bundled songs, lyrics or samples.** `Fixtures` belong to `SegueCoreTests` only.
- **No debug menu.** Test hooks are compiled out in Release: `LaunchOptions` only parsed under `#if DEBUG` (`App/Sources/SegueApp.swift`), `UITesting.isActive` is `false` in Release (`Packages/SegueUI/Sources/SegueUI/App/UITesting.swift`). `ThemeSwatchView` is public but only referenced from previews/tests.
- **No mentions of other platforms/stores** in user-facing strings.
- **Findings to fix:**
  1. `Packages/SegueUI/Sources/SegueUI/Editor/SourceEditorController.swift:85` and `VisualEditorController.swift:65` set `setAccessibilityHelp(EditorTextInput.report(textView))` unconditionally. In Release, VoiceOver users hear a machine report like "spelling … continuousSpelling … grammar …" as the text view's help. This is E2E instrumentation leaking into the shipping UI; gate it on `UITesting.isActive` like the other instrumentation. Blocks an honest VoiceOver label.
  2. `Packages/SegueUI/Sources/SegueUI/Editor/SourceTextView.swift:36-38` logs the typed character of any keystroke slower than 8 ms with `privacy: .public` in Release. Not "collection" under App Privacy rules (stays on device), but it writes lyric keystrokes into the unified log readable in sysdiagnoses. Change to `.private` or `#if DEBUG`.
  3. Help menu: SwiftUI's default Help item shows "Help isn't available for Segue." Not a guideline violation, but a visible rough edge. Replace with links to the support site and privacy policy (this also satisfies 5.1.1(i)).
  4. Info.plist: `CFBundleShortVersionString` "0.1.0" is valid; decide if v1 ships as 1.0. Add `ITSAppUsesNonExemptEncryption`.

## 4. Required pre-submission fixes (checklist)

| # | Fix | Where | Why |
|---|---|---|---|
| F1 | In-app "Privacy Policy" and "Terms" links (Help menu, plus the consent screen and Settings > Privacy) to `https://segue.ryandsilva.dev/privacy` and `/terms`; publish both pages | `Packages/SegueUI/Sources/SegueUI/SegueRootView.swift` (`SegueCommands`, add `CommandGroup(replacing: .help)`) | 5.1.1(i) |
| F2 | Menu item to reopen the main window (e.g. Window > "Segue Library" Cmd-0 via `openWindow(id: "segue.main")`), or terminate after last window closed | `SegueRootView.swift` `SegueCommands`; `UnsavedChangesGuard.swift` `SegueAppDelegate` | Guideline 4 Mac rejection pattern |
| F3 | Welcome library: 3-5 original songs (one romanized Hindi, no real film-song titles/lines) + demo setlist, deletable | new, per Ryan's decision | 2.1, 4.2, 5.2.1 |
| F4 | Gig Mode Shortcuts opt-in for fresh installs (default `nil`), or keep defaults but skip running a Shortcut that has never been tested successfully | `Packages/SegueCore/Sources/Shows/LiveSettings.swift:23-44` | Reviewer sees Shortcuts error on Start Show |
| F5 | Gate `setAccessibilityHelp(EditorTextInput.report...)` behind `UITesting.isActive` | `SourceEditorController.swift:85`, `VisualEditorController.swift:65` | Accessibility correctness; label honesty |
| F6 | Slow-key log: `privacy: .private` or Debug-only | `SourceTextView.swift:36-38` | Privacy hygiene |
| F7 | `ITSAppUsesNonExemptEncryption = NO` | `Project.swift` infoPlist | Export compliance prompt |
| F8 | Optional `PrivacyInfo.xcprivacy` (no tracking; collected types per F15; UserDefaults CA92.1, file timestamp C617.1) | `App/` resources | Insurance; macOS enforcement UNVERIFIED |
| F9 | Support page `https://segue.ryandsilva.dev/support` (ASC requires a Support URL) and privacy page live before submission | website | 2.1 "fully functional URLs" |
| F10 | Screenshots/preview from the Welcome library only | marketing | 2.3.9, 5.2.1 |
| F11 | Analytics consent: first-run choice (opt-in), Settings > Privacy toggle, no events before consent, toggle off stops sending and drops queued events | new analytics port + Settings | 5.1.1(ii) |
| F12 | Event allowlist: no lyrics, titles, artists, file/folder names, Shortcut names in analytics or diagnostics; review in code | analytics adapter | 5.1.1(iii), privacy label accuracy |
| F13 | Bug report: user-initiated only, shows the exact payload (log excerpt, OS/app version, optional email, optional attached song only if ticked) before Send; F6 must land first so logs carry no typed lyrics | new | 5.1.1(ii)/(iii), 2.5.14 spirit |
| F14 | Add `com.apple.security.network.client` to `App/Segue.entitlements` only (both flavors share it); no `network.server` | `App/Segue.entitlements` | Sandbox |
| F15 | Update F8 manifest: declare collected types (Product Interaction, Device ID if vendor uses one, diagnostics) not linked, not tracking; check the chosen vendor SDK ships its own `PrivacyInfo.xcprivacy` | `App/` | Consistency with privacy label |
| F16 | Feature board, privacy and terms open in the default browser, not an in-app web view | Help menu / Settings | Keeps age-rating web access = No |

## 5. Draft App Review notes

Paste into App Store Connect > App Review Information > Notes (stay under the field limit; trim if needed):

> Segue is a song book and live-performance app for solo and duo musicians. Songs and setlists stay in a folder on the user's Mac: no account, no sign-in, no in-app purchases. The only network use is (a) anonymous usage analytics, sent only if the user opts in on first launch (Settings > Privacy turns it off at any time), and (b) a bug report the user sends explicitly from Help > Report a Bug, which shows exactly what will be sent first. Help also links to the privacy policy, terms and a public feature-request board, which open in the default browser.
>
> First launch: Segue asks where to keep the song library. Click "Create Library in Music…" and accept the suggested folder. Segue fills it with a small Welcome library of original demo songs (written by the developer, including one in romanized Hindi) and a demo setlist. You can delete them at any time. Songs are plain ChordPro text files in that folder (security-scoped bookmark; the app only touches the folder you choose).
>
> Things to try:
> 1. Library: select a song to preview it. Use the transpose controls and the Nashville toggle; open the chord diagram strip for guitar or piano shapes.
> 2. Editor: double-click a song, switch between text and visual mode, drag a chord onto a different syllable, save.
> 3. Setlists: open the "Welcome Set" setlist, drag to reorder; the running total shows the set length.
> 4. Live: click "Start Show". The pre-show checklist appears (each row can be dismissed). Stage mode is full screen and dark; it hides the Dock and menu bar only while performing. Arrow keys / Space move between songs and start auto-scroll. Press Esc, then confirm "End Show", to leave stage mode; the show is saved to the Gig Log.
> 5. Optional Shortcuts integration: Settings > Live can run a Shortcut the user creates (for example one that turns on a Focus) when a show starts and ends, via the Shortcuts URL scheme. This is off by default and not needed to use the app.
>
> Support: segue@ryandsilva.dev - https://segue.ryandsilva.dev

Adjust step 4 key names and step 5 "off by default" to match what ships (see F4). If a short screen recording (60-90 s: first launch -> edit -> setlist -> stage mode -> exit) is attached under App Review Information > Attachment, reviewers can see stage mode without guessing the keys. Apple's own guidance to attach a demo video for hard-to-reach features is UNVERIFIED as a stated requirement; it costs little and directly addresses the "reviewer could not find feature" class of 2.1 rejections.

Other review-information fields: contact name/phone/email (`segue@ryandsilva.dev`), "Sign-in required" = No.

Rollout note: internal TestFlight testers need no Beta App Review; external TestFlight groups do (UNVERIFIED detail, see the TestFlight sibling doc if any).

## 6. Age rating (2025 questionnaire)

Apple's tiers are now 4+, 9+, 13+, 16+, 18+ (and Unrated, which cannot be published) - https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/. Apple announced the change in July 2025 and required the new questionnaire for all apps by 31 January 2026 (secondary sources: 9to5mac 2025-07-24, AppleInsider 2025-07-25, Apple forums thread 810473). For a new app the new questionnaire is simply part of setup.

Likely answers for Segue:

| Question | Answer | Reason |
|---|---|---|
| Parental controls | No | - |
| Age assurance | No | - |
| Unrestricted web access | No | No web view; Help/privacy/terms/feature-board links open the default browser, which is not in-app browsing. If an in-app web view is ever added, keep it locked to own pages or this becomes Yes |
| User-generated content | No | Users write their own songs, but nothing is distributed to others ("broad distribution" is the test) |
| Social media | No | - |
| Messaging and chat | No | - |
| Advertising | No | - |
| Profanity or crude humor | None | App ships no such content (Welcome songs must be clean) |
| Horror/fear, alcohol/tobacco/drugs | None | Same - keep demo lyrics clean |
| Medical/treatment, health/wellness | None | - |
| Mature/suggestive, sexual content/nudity, graphic | None | - |
| All violence items, guns | None | - |
| Gambling, simulated gambling, contests, loot boxes | None | - |

Expected result: **4+**. Note user-imported lyrics can contain anything, but Apple rates the app's own content and capabilities; a local text editor is not UGC distribution. When phase 3 AI ships, re-answer any AI-related question (secondary sources mention AI-feature questions; not shown on the Apple reference page read today - UNVERIFIED).

## 7. Accessibility Nutrition Labels

What: per-feature claims shown on the product page; voluntary for now, "over time" required for new apps and updates, no date given (https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels). A claim means the feature works across all **common tasks**: the app's primary functionality plus first launch, login, purchase, settings.

Mac-applicable labels: VoiceOver, Voice Control, Dark Interface, Differentiate Without Color Alone, Sufficient Contrast, Reduced Motion, Captions, Audio Descriptions. **Larger Text is not supported on Mac** ("This label isn't supported on Mac"). Captions and Audio Descriptions are n/a (no media).

| Label | Candidate? | Evidence / gap | Verification steps |
|---|---|---|---|
| Dark Interface | **Yes, likely** | Tokens have light/dark values (`design/tokens.json`), main window follows system appearance, stage forced dark (`StageWindowController.swift:57`). Criteria: claim allowed if the app supports system Dark Mode with no bright flashes (https://developer.apple.com/help/app-store-connect/manage-app-accessibility/dark-interface-evaluation-criteria) | Run every common task in Dark Mode: first-launch chooser, save/open panels, editor (both modes), diagrams, setlist builder, Settings, Acknowledgements, sheets/alerts, stage enter/exit. Look for white flashes during transitions and in AppKit text views. |
| Sufficient Contrast | **Not yet** | Text passes: ink 18.9/16.0, muted 7.4/5.8, cueText 5.6/6.8, muted on surfaceAlt dark 5.3. **Non-text state indicators fail 3:1**: `lineStrong` inactive progress dots 1.95 (light) / 1.34 (dark); `played` dots 2.56 (dark). Criteria: 4.5:1 text, 3:1 controls and state indicators, both modes, also with Increase Contrast (https://developer.apple.com/help/app-store-connect/manage-app-accessibility/sufficient-contrast-evaluation-criteria) | Fix token values or add an Increase Contrast variant; recheck chip borders (`line` token, also below 3:1) where they are the only boundary of a control; test with Increase Contrast on. |
| Reduced Motion | **Probably yes, after check** | `LiveView.swift` reads `accessibilityReduceMotion` and drops animations. Auto-scroll counts as "ongoing motion"; criteria accept a control to stop it (https://developer.apple.com/help/app-store-connect/manage-app-accessibility/reduced-motion-evaluation-criteria). Auto-scroll is user-started and pausable. | Confirm auto-scroll never starts by itself with Reduce Motion on (or default it off then); check editor/sidebar/sheet transitions and stage window entry (full-screen zoom) for remaining motion. |
| Differentiate Without Color Alone | Maybe | Played/pending/current states in setlist and live header use color dots; coral cue is the "current" signal | Audit each state: does a shape, label, or weight also change? Check proficiency marks and chips. |
| VoiceOver | **Not yet** | Only ~31 `accessibilityLabel`s across 22 files; the visual editor is a custom-drawn AppKit canvas (chord pills over syllables) and diagrams are drawn views; F5 leak above | Full VoiceOver pass of every common task, including drag-a-chord (needs an accessible alternative action) and stage mode. Claim only after it passes end to end. |
| Voice Control | Not yet | Depends on labels; untested | Same pass with Voice Control "show names/numbers". |
| Larger Text | n/a on Mac | - | - |

Recommendation: at launch claim **Dark Interface** (and **Reduced Motion** if the check passes); add Sufficient Contrast after the token fix; defer VoiceOver/Voice Control.

## 8. App Privacy label, consent, and network features

### 8.1 Rules (primary)

- "Collect" = transmitting data off the device so the developer or partners can access it beyond servicing the request in real time; on-device-only data is not collected (https://developer.apple.com/app-store/app-privacy-details/).
- "You are not responsible for disclosing data collected by Apple." Crash logs that users share with developers through Apple (Xcode Organizer / App Store Connect) are Apple's collection. But "if you collect data about your app from Apple frameworks or services, you should indicate what data you collect and how you use it" - e.g. MetricKit payloads the app uploads to its own server must be disclosed.
- A data type may be left off only if it meets **all** optional-disclosure criteria: not tracking, not used for third-party ads / own marketing / other purposes, collected only infrequently and not part of primary functionality, optional, and provided by the user in the UI each time with clear notice (same page).
- 5.1.1(ii): consent for user or usage data "even if such data is considered to be anonymous", and "an easily accessible and understandable way to withdraw consent".
- 5.1.1(i): the privacy policy must name what is collected, how, all uses; confirm third parties (analytics tools, SDKs) give equal protection; explain retention/deletion and how to revoke consent or request deletion.
- 5.1.2(i): data may be shared with third parties only to improve the app or serve ads; ATT permission is required only for tracking.
- Privacy Policy URL is required in App Store Connect ("Privacy Policy (Required)").

### 8.2 Without the scope update

"Data Not Collected" was correct: no network entitlement, so the app physically could not transmit.

### 8.3 With analytics + bug report (v1 scope)

"Data Not Collected" is **no longer possible** once analytics are on (consent does not remove the disclosure: the label describes what the app can collect, not what a given user agreed to). Likely label, assuming a privacy-first vendor used as documented:

| Data type | When | Linked to user? | Tracking? | Purposes |
|---|---|---|---|---|
| Usage Data > Product Interaction | Analytics events (feature used, show started, etc.) | No | No | Analytics |
| Identifiers > Device ID | If the SDK sends a (hashed) installation/device identifier - TelemetryDeck's own guide says to declare Device ID, not linked, not tracking (https://telemetrydeck.com/docs/articles/apple-app-privacy/); Aptabase's equivalent is UNVERIFIED (docs page 404) | No | No | Analytics |
| Diagnostics > Crash Data / Performance Data / Other Diagnostic Data | Bug report payload (log excerpt, app/OS version, hardware model); only the types actually sent | No (Yes if an email is attached in the same submission) | No | App Functionality (and Analytics if aggregated) |
| Contact Info > Email Address | Only if the bug report has an optional email field | Yes | No | App Functionality (customer support) |
| User Content > Other User Content | Only if the bug report can attach a song file or free-text description | Yes if email attached, else No | No | App Functionality |

Optional-disclosure exemption for the bug report: it is user-initiated, infrequent and optional, but the criterion that the user's name/account be prominently displayed in the form cannot be met without accounts (UNVERIFIED reading), so **disclose it**. Under-disclosure is a 2.3/5.1 risk; over-disclosure is not.

Own endpoint vs vendor: the label answers are the same; with a vendor, the privacy policy must name it and state it gives equal protection (5.1.1(i)).

### 8.4 Opt-in vs opt-out

| Option | Guideline fit | Notes |
|---|---|---|
| Opt-in (first-run "Share anonymous usage data?" with Yes / No, default not pre-selected) | Matches 5.1.1(ii) literally | Lower data volume. Recommended. |
| Opt-out with first-run notice | Arguable: notice is not consent | Many privacy-first-analytics apps ship this and pass review (UNVERIFIED, anecdotal); a reviewer can cite 5.1.1(ii) at any time, including on a later update. |
| Silent, no UI | Fails 5.1.1(ii) text | Not acceptable. |

Whatever is chosen: no events before the choice; Settings > Privacy toggle that takes effect immediately and drops the queue (5.1.1(ii) withdrawal); privacy policy explains retention and how to request deletion; the consent screen links the privacy policy. Also: the consent screen is part of "first launch experience", so it counts for the accessibility labels in section 7.

EU note (not an App Review rule): ePrivacy Art. 5(3) can require consent for storing an identifier on the device even if hashed; opt-in sidesteps the question (UNVERIFIED legal reading; not legal advice).

### 8.5 Links and web views

- Privacy policy and terms links: required in-app for the policy (5.1.1(i)); terms optional unless a custom EULA is used. Put both in the Help menu and on the consent screen.
- Feature-request board: an external website. Opening it in the default browser is a plain link-out; nothing to declare. If the board needs sign-in, that is the board's account, not the app's; no demo account is needed because the app works fully without it (mention in review notes). The board's own data collection is covered by the board's policy; consider a one-line mention in Segue's policy.
- In-app `WKWebView`: avoid. It would need careful navigation locking or the age-rating "Unrestricted Web Access" answer becomes Yes, and pages loaded in-app with their own trackers can be attributed to the app (UNVERIFIED reviewer practice).
- All linked URLs must resolve at review time (2.1 "fully functional URLs").

### 8.6 Review-notes additions

Already folded into the section 5 draft: where analytics consent is asked, where the toggle is, what the bug report sends, that links open in the browser.

## 9. Common Mac App Store rejection reasons relevant here (2024-2026)

- **Main window cannot be reopened from the menu** (Guideline 4) - see F2. Sources: Apple forums threads 96725, 130527.
- **2.1 crash or "could not find feature"** - mitigated by Welcome library, review notes, optional video.
- **5.1.1(i) privacy policy missing in-app** - see F1.
- **Sandbox file access** - apps that assume access to `~/Music` without a panel fail; Segue uses a save panel and bookmarks. Make sure bookmark-stale/permission-lost path (`accessLost` message in `SegueRootView.swift`) works on a clean account.
- **Metadata with other apps' names or copyrighted content** (2.3.7, 2.3.9).
- **Menu items not visible / missing standard menus** (Guideline 4; Apple forums 764643, 841112) - SwiftUI provides standard menus; keep them.

## 10. Decisions for Ryan

1. Gig Mode Shortcuts: (a) opt-in by default for everyone, (b) opt-in only in the App Store flavor, (c) keep defaults and describe in review notes. Recommendation: (a).
2. Main-window reopen: (a) Window menu item + Cmd-0, (b) quit when last window closes. Recommendation: (a), since stage mode and Settings are separate windows.
3. Accessibility labels at launch: claim Dark Interface only, or also Reduced Motion after the check, or wait until Sufficient Contrast tokens are fixed.
4. Version string for first release: keep 0.1.0 or ship 1.0.
5. Attach a screen recording to review notes: yes/no.
6. Analytics consent model: (a) opt-in first-run choice, (b) opt-out with first-run notice, (c) no consent UI. Recommendation: (a) - matches the literal 5.1.1(ii) text and EU ePrivacy; (b) is commonly shipped with privacy-first vendors but carries real rejection risk (UNVERIFIED how strictly reviewers enforce it).
7. Analytics backend: TelemetryDeck / Aptabase / own endpoint. Own endpoint removes the third-party disclosure but makes Ryan the data controller and server operator; a vendor must be named in the privacy policy. Put it behind an analytics port either way.
8. Bug report contact: optional email field (then disclose Contact Info > Email Address, linked) or mailto: to `segue@ryandsilva.dev` (Mail sends it, nothing collected by the app).
9. Terms: Apple's standard EULA or a custom one (custom must be entered in ASC as a custom licence agreement).

## Sources

- App Review Guidelines (last update Oct 16, 2026): https://developer.apple.com/app-store/review/guidelines/
- Age ratings values and definitions: https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/
- Age rating deadline (secondary): https://9to5mac.com/2025/07/24/apple-notifies-developers-of-new-app-store-age-rating-system/ , https://appleinsider.com/articles/25/07/25/app-store-developers-must-now-provide-age-rating-details , https://developer.apple.com/forums/thread/810473
- Accessibility Nutrition Labels overview: https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels
- Dark Interface criteria: https://developer.apple.com/help/app-store-connect/manage-app-accessibility/dark-interface-evaluation-criteria
- Sufficient Contrast criteria: https://developer.apple.com/help/app-store-connect/manage-app-accessibility/sufficient-contrast-evaluation-criteria
- Reduced Motion criteria: https://developer.apple.com/help/app-store-connect/manage-app-accessibility/reduced-motion-evaluation-criteria
- App privacy details: https://developer.apple.com/app-store/app-privacy-details/
- TelemetryDeck App Privacy guide: https://telemetrydeck.com/docs/articles/apple-app-privacy/
- 5.1.x rejection discussions (secondary): https://developer.apple.com/forums/thread/688582 , https://developer.apple.com/forums/thread/815100
- Required-reason API (page did not render; macOS scope UNVERIFIED): https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api ; secondary: https://docs.unity3d.com/Manual/apple-privacy-manifest-policy.html
- Mac window-reopen rejections: https://developer.apple.com/forums/thread/96725 , https://developer.apple.com/forums/thread/130527 , https://developer.apple.com/forums/thread/764643 , https://developer.apple.com/forums/thread/841112
- ChordPro (no trademark registration found; UNVERIFIED): https://www.chordpro.org/
- Repo: `Project.swift`, `App/Segue.entitlements`, `App/Sources/SegueApp.swift`, `scripts/verify-appstore.sh`, `design/tokens.json`, files cited inline.
