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

## 3. F5: machine report as accessibility help (I-13)

2026-10-17: `grep -n setAccessibilityHelp` finds no calls in `SourceEditorController.swift` or `VisualEditorController.swift` in the working tree (WS1's change). VoiceOver check that the editor reads its label and never the report: pending, in Ryan's VoiceOver walk (step 12).

## 4. Reduce Motion (4.9.3), partial

Done in step 1: `SelectableList` scroll-to-selection and the button press animation are instant with Reduce Motion on. The rest of the 4.9.3 checklist is recorded in step 12.

## 5. Label claims

Filled in by WS2b step 12.
