# WS2b design directions (R39, A41)

Ryan picked one direction per item on 2026-10-17 (docs/release/decisions.md R52). Only the picked renders are kept here; the full side-by-side boards (2-3 directions each, light and dark) were reviewed in the session scratchpad.

| Item | Pick | One-line rationale | Renders |
|---|---|---|---|
| Welcome sheet | **A Native** | Left-aligned, grouped `surfaceAlt` boxes, actions bottom right, like System Settings and Things | `welcome-A-p{1,2,3}-{light,dark}.png` |
| What's New sheet | **A Notes** | Left-aligned release notes, outlined word badges ("New", "Improved", "Fixed"), footer link plus Continue | `whatsnew-A-{light,dark}.png` |
| `.cho` document icon | **B Taped page** | A paper page with a coral tape strip, an ink title bar and grey lines, "CHO" below; reads at 16 and 32 px | `docicon-B-512.png`, `docicon-B-32-x8.png` (32 px, 8x) |

Implementation notes:
- In-app links use the shared `.appLink` style (`cueText`), not the underlined ink link in the renders.
- The consent page hosts WS3's `ConsentChoiceView` unchanged inside one grouped surface; the renders showed each row in its own box.
