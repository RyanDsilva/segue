# Accessibility audit (WS2b section 4.9)

Session output of the WS2b accessibility pass. WS5 fills App Store Connect's Accessibility labels from the final claim list (section 4 below, completed in WS2b step 12).

## 1. Apple's Sufficient Contrast criteria (A43)

Source: App Store Connect Help, "Sufficient Contrast evaluation criteria", https://developer.apple.com/help/app-store-connect/manage-app-accessibility/sufficient-contrast-evaluation-criteria, read 2026-10-17 (the page shows no last-updated date).

> You may indicate your app supports Sufficient Contrast if the user interface for your common tasks, including text, buttons, and other controls, meets general contrast guidelines by default - usually 4.5 to 1 for most text elements.
>
> If your app doesn't provide this minimum contrast by default:
>
> - If your app uses Apple-provided UI frameworks, verify that the Increase Contrast setting applies sufficient contrast.
> - If your app supports custom frameworks, provide users with a choice of multiple color schemes that meet contrast minimums.
> - If third-party or user-generated content is required in your common tasks, refer to the detailed guidance for third-party content on the Overview of Accessibility Nutrition Labels.

> Make sure to provide sufficient contrast on interactive controls and non-text representations of a state, such as a selection. For example, if you design a custom checkbox, make sure there is sufficient contrast between the checked and unchecked states. Meeting a 3:1 minimum contrast ratio is commonly recommended for non-text contrast.

The page also asks testers to check contrast in light and dark mode with Bold Text, Increase Contrast and Reduce Transparency, including Increase Contrast on with Reduce Transparency both off and on.

(The original uses an em dash after "by default"; it is replaced with "-" here per the repo's writing rule.)

**Route taken:** Segue is built with SwiftUI and AppKit (Apple-provided frameworks), so the Increase Contrast route is accepted. Control borders (`controlBorder`) reach 3:1 **only with Increase Contrast on**: #8A8A92 on paper (3.43:1) and #66676E on stage (3.36:1). The default look is unchanged (`line` in light, 1.27:1; `muted` at 40% in dark, about 1.9:1). State indicators and text meet their minimums in the default look as well (section 2).

## 2. Contrast fixes (4.9.1 items 2-4)

Ratios use the WCAG 2.x formula against `ground`, enforced by `ThemeTokenTests` ("contrast meets its minimum" and "the indicator ratios match the approved A44 values").

| Element | Token | Light | Dark (stage) | Minimum |
|---|---|---|---|---|
| Pending progress dot, unrated gig-log stars | `indicatorOff` #8A8A92 / #66676E | 3.43 | 3.36 | 3.0 |
| Played progress dot, skipped ring | `played` #55555C / #8E8E96 | 7.39 | 5.81 | 3.0 |
| Current song pill | `cue` #F2555A | 3.37 | 5.60 | 3.0 |
| Control edges, Increase Contrast on | `controlBorder` high #8A8A92 / #66676E | 3.43 | 3.36 | 3.0 |
| Text | `ink`, `muted`, `cueText` | 18.9 / 7.4 / 5.6 | 16.0 / 5.8 / 6.8 | 4.5 |

Ryan approved the A44 before/after render of the dots and stars on 2026-10-17. Today's values were pending 1.95 / 1.34 and played (dark) 2.56.

**Test limitation:** an `NSAppearance` created in-process from a High Contrast name does not select the asset catalog's `contrast: high` entries. AppKit applies them only when the system setting is on. So the contrast test computes from the generated token values, and `make tokens-check` keeps those equal to the catalog. The live Increase Contrast rendering is part of the manual pass (section 4.9.5: Increase Contrast on and off, light and dark, every screen).

## 3. Machine reports read to VoiceOver (F5, I-13, and one more)

- F5: `grep -n setAccessibilityHelp` finds no calls in `SourceEditorController.swift` or `VisualEditorController.swift` (WS1's change; re-checked 2026-10-18 in step 12).
- New in step 12: the stage exposed a layout report ("lyric 31.5 fits scroll 0.00 columns 2") as an accessibility element for every user. It now exists only in UI test runs (`UITesting.isActive`), like the editor's status instrumentation and the checklist row markers.
- Still for Ryan's VoiceOver walk: the editor reads its label ("ChordPro source") and never a report.

## 4. Reduce Motion (4.9.3)

Code audit 2026-10-18: every `withAnimation` and `.animation(` in SegueUI sits behind `accessibilityReduceMotion` (a grep for files that animate without reading it finds none).

| Check | Result | Evidence |
|---|---|---|
| Stage song transitions and indicators | Pass | `LiveView` gates the song change, the indicator and the status line |
| `SelectableList` scroll-to-selection | Pass | instant with Reduce Motion (step 1) |
| Button press feedback | Pass | `SegueButtonStyle`, `ConsentOptionStyle` (step 1, WS3) |
| Welcome page changes | Pass | fade out then in, 150 ms; `.identity` with Reduce Motion |
| What's New | Pass | a standard sheet, no custom motion |
| Scroll-to-current in lists | Pass | `SelectableList` |
| Auto-scroll never starts by itself | Pass | starts on `A`/Space, or on advance only for a song with `autoStartScroll` (unchanged) |
| Stage entry and exit, no zoom | Pass | the stage is a borderless window covering the screen, not native full screen; no animation |
| Spot check with the setting on | For Ryan | docs/release/walkthrough.md |

## 5. VoiceOver audit (4.9.2)

Fixed in step 12:
- **Song sheet lines** (song page, editor preview, Quick Look): one element per line, read "chords: lyric", for example "G, D: Van door slides and the street lamps hum" (`LyricLineView.spokenText`, `EditorCanvasAccessibilityTests`). The stage body keeps separate chord and lyric-run elements: its layout engine places them absolutely and the live E2E suite reads them; reading order there is part of the walk.
- **Chord moves without a drag**: every chord pill in the visual editor offers "Move left one syllable", "Move right one syllable", "Edit chord" and "Delete chord" (`NSAccessibilityCustomAction`; checked in process, including that a move rewrites the source).
- **Set reordering without a drag**: every set row offers "Move up" (not on the first row) and "Move down" (not on the last), next to the existing "Edit" action and WS2a's menu commands. XCUITest cannot read custom actions, so this one is in the walk.
- **The setlist toolbar menu** (icon only) is named "Setlist".
- New UI built to the checklist: Welcome (title read before "Step n of m", cards as one element each, icons hidden, the checkbox is a real checkbox), What's New (badge words, "Learn More: <highlight>" links), Settings panes (named controls), the consent page (WS3's view).

Per screen (automated where possible, VoiceOver walk by Ryan for the rest):

| Screen | Automated (step 12) | VoiceOver walk |
|---|---|---|
| Welcome sheet, all pages and revisit | E2E: titles, steps, four equal consent buttons, Esc/Return answer nothing | Pending |
| WS3 `ConsentSheet` | WS3's E2E | Pending |
| Library chooser (accessLost) | unchanged | Pending |
| Sidebar, song list, chips, search | audit: no unnamed control | Pending |
| Song detail | per-line reading | Pending |
| Diagram strip | existing labels | Pending |
| Editor, text and visual | pill actions (in process) | Pending |
| Setlist builder | audit; Move up / Move down added | Pending |
| Gig log and detail | audit | Pending |
| Settings, 6 panes (AI added in phase 3) | audit | Pending |
| Stage, checklist, panels | audit | Pending |
| Reorder review, resume prompt, alerts | not audited (sheets) | Pending |
| What's New | E2E: badge words | Pending |
| Tips | system TipKit views | Pending (one tip) |
| Phase 3 screens (paste review, song card, section band, section notes, Pick / Arrange, assistant, Arrange Sections, Settings > AI, metronome) | audit, section 6.1 | Pending (walkthrough.md rows) |

## 6. Apple's automated audit (`AccessibilityAuditE2ETests`)

`performAccessibilityAudit(for: .all)` on 15 screens in light appearance (library, song, editor text and visual, builder, gig log, the five Settings panes, Welcome revisit, the pre-show checklist, the stage), 2026-10-18: 303 findings. The test fails on the ones that are Segue's to fix and attaches the full list; the rest are triaged here.

| Finding | Count | Triage |
|---|---|---|
| Element has no description, on a control or a Segue element | 0 | Enforced by the test |
| Element has no description, anonymous SwiftUI layout groups, the Touch Bar, the system "emoji & symbols" item | 106 | Framework structure, not a control; nothing a person acts on |
| Unknown role | 9 | All are UI-test instrumentation that real users never get |
| Action is missing | 34 | SwiftUI `Menu` buttons (they open on press) and anonymous containers; VoiceOver opens them with VO-Space. Walk item |
| Parent/Child mismatch | 19 | SwiftUI sidebar icon images and canvas overlay elements; walk item |
| Contrast failed / nearly passed | 136 | Not trusted as a gate on macOS: it samples screenshots, includes inactive windows behind Settings (AppKit dims their text), translucent sidebars and system views (`ContentUnavailableView`), and flags `muted` text (#55555C, 7.4:1 on white by the WCAG formula). One real issue was found and fixed: "In set" rows in the builder's library column faded the whole row to 55%; the title now uses `muted` instead and nothing fades. The token contrast test (section 2) is the gate; the manual Increase Contrast pass decides the claim |

### 6.1 Phase 3 screens (P3-9, R79, 2026-10-20)

`AccessibilityAuditE2ETests/testPhase3ScreensLight` (in `AccessibilityAuditE2ETests+Phase3.swift`) runs the same audit and the same `ignoredIssue` rules on a fresh Welcome library in light appearance over 13 states: the song card and its tempo field, the Section Notes sheet, the visual editor with section bands, the paste review sheet, Settings > AI, the set builder in Pick and in Arrange, the set assistant after Build and a row's score breakdown, the Arrange Sections sheet, the rehearsal checklist with the metronome rows, and the stage with the metronome and a section-note callout. `testMainScreensLight` now also walks the AI pane. First run: 310 findings on the phase 3 states and 9 failures (below); after the fixes both tests pass.

Fixed (Segue's to fix, enforced by the test):

| Finding | Where | Fix |
|---|---|---|
| Label not human-readable | Settings > AI, the licence link read "Apache-2.0" | Spoken as "Apache 2.0 license" (`AISettingsView.licenseLabel`, in-process test in `AISettingsTests`); the visible text is unchanged, so Voice Control still matches it |
| Element has no description | the song card's "Add tag" field (seen in the paste review sheet's metadata block) | `accessibilityLabel("Add tag")` |
| Unknown role | paste review section labels, the Arrange Sections stage preview, the stage metronome, the stage section-note callout | each is one combined element; they now carry the static-text trait (AXStaticText), so VoiceOver reads them as text. Static text exposes its words as the value, so a label's extra value moved into the one label ("Chorus, labelled by AI", "Stage preview, 5 sections"), and the metronome and section-notes E2E tests read the value when the label is empty, as the WS2b sheet-line checks do |

Triaged as before (section 6 rules), counts from the first run: 115 "no description" on anonymous SwiftUI groups, the Touch Bar and the system "emoji & symbols" item; 57 "action is missing" (SwiftUI `Menu` buttons such as More, Setlist, the editor's instrument and stage-columns menus, and anonymous containers); 16 parent/child mismatches (sidebar icon images); 107 contrast findings sampled from screenshots (the token test is the gate; the Increase Contrast pass decides the claim); 7 unknown roles on UI-test instrumentation.

Walk items the audit cannot see are in `docs/release/walkthrough.md` ("Accessibility of the new screens"): VoiceOver, Voice Control and Full Keyboard Access rows per new screen, including the sparkle read as "AI" on a section label, the metronome never taking focus while it pulses, and the live repeat message. No label in section 8 changes until Ryan walks them.

## 7. Larger Text (4.9.4)

No Larger Text claim (B-19) and no main-window text scaling in 0.5 (A45). The three checks (stage at the 48 pt minimum with zoom at its limit on a 13-inch window, the main window at 820x520 with long titles, and the effect of macOS 26's Text Size setting) were not run in step 12; they are in the walkthrough. Re-check in App Store Connect that Larger Text is still not offered for macOS.

## 8. Label claims

Final list for App Store Connect as of WS2b step 12 (WS5 fills it in):

| Label | Claim | Why |
|---|---|---|
| Dark Interface | **Claim** | Every screen follows the system or Settings > Appearance; the new sheets and panes were captured in dark by the E2E suite; the stage is always dark. The Quick Look preview is light by design (B-20) and is Finder's surface, not a common task in Segue. Walk: no white flash on sheets, window open and stage enter/exit |
| Differentiate Without Color Alone | **Claim** | Progress dots differ by shape and lightness (pill, ring, filled); proficiency by fill vs outline; chips by fill; errors carry an icon and text; What's New badges are words; "In set" is a word; the current set row is the selection, not only coral |
| Reduced Motion | **Claim** | Section 4, all pass in code; Ryan's spot check confirms |
| Sufficient Contrast | **Not yet** | Token test green and the Increase Contrast route recorded (sections 1-2), but the automated contrast audit is not clean (section 6) and the manual pass with Increase Contrast on and off, light and dark, on every screen has not been done. Claim it after that pass |
| VoiceOver | **Not yet** | Claim only after Ryan's VoiceOver walk (section 5) passes end to end, including chord moves and set reordering without a drag |
| Voice Control | **Not yet** | Claim only after Ryan's Voice Control walk (walkthrough.md) passes on every screen |
| Larger Text | Not claimed | B-19 |
| Captions, Audio Descriptions | Not applicable | No in-app video or audio |
