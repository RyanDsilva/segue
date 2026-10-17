# Journal

## 2026-10-17 - Discovery, specs, phases 0-2 built and hardened

### What changed
- Discovery interview + research -> `docs/00-vision.md`, `docs/research.md`, `docs/research/phase{3,5,7}-*.md`, `docs/decisions.md` (all rulings), `docs/brand.md`, 8 phase specs in `docs/phases/`, interface contracts `docs/phases/{1,2}-interfaces.md`, review logs `docs/reviews/phase{0,1,2}-review.md`.
- Name: **Segue** (bundle `dev.ryandsilva.segue`). Brand direction C "Precise" + taped-setlist icon. Design canvas (mockups, layout picks): https://claude.ai/artifact/XizqyqzA1chVfBSGThAzcQ
- Built (local signed commits, NOT pushed): phase 0 skeleton (Tuist, SegueCore/SegueUI/SeguePersonalModules, ChordPro round-trip parser, files-canonical library + GRDB index with romanized-Hindi search, theme/tokens/font/icon, App Store exclusion check), phase 1 (music theory on Tonic, guitar/piano diagrams, editing engine, TextKit 2 text + visual canvas editor), phase 2 (show engine with crash resume + gig log, setlists builder, live layout auto-fit, stage UI with checklist/Shortcuts/quick search/requests/autoscroll, settings). Each phase got an independent adversarial review and a hardening pass.

### State
- `make check` green at 9feaf72 (lint, tokens/icon checks, both schemes 0 warnings, 288 core + 86 UI-package tests, 19 XCUITests, verify-appstore).
- Test budget: `make quick` while iterating, `make e2e-one TEST=Class/test` for touched UI, one full `make check` per gate.
- Uncommitted: `docs/research/phase3-spikes.md` may be written by a still-running phase 3 spike agent (FM/MLX eval in scratchpad) - review and commit it when it lands.
- Remote `origin` = github.com/RyanDsilva/segue (private); nothing pushed since the docs commits - push only when Ryan asks.

### Decisions (see docs/decisions.md for all)
- Files canonical (.cho + .segue.json sidecar), index rebuildable; macOS 26 min; integration-first tests; personal-only features (audio, LRCLIB, URL import) live in `Packages/SeguePersonalModules`, never in the AppStore scheme.
- Signing: free Personal Team `V6BM673U35` (contact@ryandsilva.dev). **App Store needs the paid program.**
- Phases 3-7 are now post-launch features; App Store publishing comes first.

### Surprises
- Researcher-agent output was often wrong (licences, versions, SDK facts); verify against SDK headers/primary sources.
- XCUITest flakiness came from focus: a full-screen VS Code Space stole activation; E2E now brings Segue to front before every action. A stray system dialog or the user typing still breaks runs.
- zsh aliases `cat` -> `eza`; agent `cat` heredocs hung for hours. Use `command cat` / file tools.
- Guard hook blocks `rm -rf`; leftover git-ignored scratch dirs (`Packages/*/.build-*`, `.build/att-*`) can be deleted by hand.

### Open manual items for Ryan
- Run the Shortcut focus check: create Shortcut "Segue Focus Probe" (Wait 1s), grant terminal Accessibility, `make build && scripts/verify-shortcut-focus.sh "Segue Focus Probe"`, record result in docs/phases/0-walking-skeleton.md.
- Optionally inspect `design/icon/Segue.icon` in Icon Composer.
- Manual USPTO search for "Segue" before a paid launch.

### Polish noted, not done
- Short songs on 13" now fit one column at ~28.5pt, leaving the right half empty; consider whether 2 columns at a similar size reads better.

### Next
Start the App Store publishing session: enrol in / confirm the paid Apple Developer Program, then work through App Store Connect setup (app record, bundle ID, signing switch from Personal Team, privacy manifest + sandbox review, metadata, screenshots, privacy policy, archive + TestFlight) using the AppStore scheme and `make verify-appstore`.
