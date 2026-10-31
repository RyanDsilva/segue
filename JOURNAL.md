# Journal

## 2026-10-17 - Discovery, specs, phases 0-2 built and hardened

### What changed
- Discovery interview + research -> `docs/00-vision.md`, `docs/research.md`, `docs/research/phase3-*.md`, `docs/decisions.md` (all rulings), `docs/brand.md`, phase specs in `docs/phases/`, interface contracts `docs/phases/{1,2}-interfaces.md`, review logs `docs/reviews/phase{0,1,2}-review.md`.
- Name: **Segue** (bundle `dev.ryandsilva.segue`). Brand direction C "Precise" + taped-setlist icon. Design canvas (mockups, layout picks): https://claude.ai/artifact/XizqyqzA1chVfBSGThAzcQ
- Built (local signed commits, NOT pushed): phase 0 skeleton (Tuist, SegueCore/SegueUI/SeguePersonalModules, ChordPro round-trip parser, files-canonical library + GRDB index with romanized-Hindi search, theme/tokens/font/icon, App Store exclusion check), phase 1 (music theory on Tonic, guitar/piano diagrams, editing engine, TextKit 2 text + visual canvas editor), phase 2 (show engine with crash resume + gig log, setlists builder, live layout auto-fit, stage UI with checklist/Shortcuts/quick search/requests/autoscroll, settings). Each phase got an independent adversarial review and a hardening pass.

### State
- `make check` green at 9feaf72 (lint, tokens/icon checks, both schemes 0 warnings, 288 core + 86 UI-package tests, 19 XCUITests, verify-appstore).
- Test budget: `make quick` while iterating, `make e2e-one TEST=Class/test` for touched UI, one full `make check` per gate.
- `docs/research/phase3-spikes.md` landed and is committed (see the addendum below).
- Remote `origin` = github.com/RyanDsilva/segue (private); nothing pushed since the docs commits - push only when Ryan asks.

### Decisions (see docs/decisions.md for all)
- Files canonical (.cho + .segue.json sidecar), index rebuildable; macOS 26 min; integration-first tests; personal-only features (LRCLIB, URL import) live in `Packages/SeguePersonalModules`, never in the AppStore scheme.
- Signing: free Personal Team `V6BM673U35` (contact@ryandsilva.dev). **App Store needs the paid program.**
- Phase 3 is built; Phase 8 and PDF export ship before the App Store release; phases 5 and 6 come after launch.

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

### Addendum - phase 3 spikes landed
- Results: `docs/research/phase3-spikes.md`; spike code/fixtures/scoring kept in `research/phase3-spikes/` (models excluded, lint-excluded).
- Headline: Apple FM on this M1 Pro: 89% label accuracy but median 18 s/song (5-69 s), Hindi songs sometimes rejected (`unsupportedLanguageOrLocale`, fails fast). MLX Qwen3-4B-Instruct-2507 4bit: 98% labels, ~6.5 s, 3 GB RAM, 2.28 GB download. Set requests: code-first parsing beats both models.
- Phase 3 decisions these fed (settled when phase 3 was built, see `docs/decisions.md`): MLX-first routing when installed, the curated model (Qwen3-4B vs Gemma 4 E2B), and whether set requests keep a model call.
- The ~10 GB of downloaded models in the session scratchpad are gone (checked 2026-10-17); a phase 3 re-run re-downloads them into `research/phase3-spikes/models/` (git-ignored).

## 2026-10-17 - Release kickoff, build phase 1, repo health, pre-push clean-up

### What changed
- Release planning: `docs/release/` (README guide, `decisions.md` R1-R50, open-questions, WS1-WS5 specs, research 01-09). Build phase 1 (section 3) landed: WS1 steps 1-7, WS2b steps 1-2, WS3 steps 1-2, WS4 steps 1-2 and 4-7 (see `git log`; the home page uses the Stage direction).
- Repo health (R47-R50): README, LICENSE, notices, SECURITY, CONTRIBUTING, `.github/` (issue forms, PR template, CODEOWNERS, Linux CI, Dependabot, release workflow, labels), `make repo-check`, `docs/github-setup.md`. GitHub labels pruned to `labels.yml`.
- Clean-up (approved items): dropped 13 tracked spike binaries/logs/caches, ignore rules for the spike harness outputs; `scripts/xcodebuild.sh` keeps the newest 10 result bundles; `make clean-local` trashes per-agent build dirs, old DerivedData copies, attachments and logs (about 33 GB freed this time, in the Trash until emptied).
- Pre-push hook now stands in for branch protection (needs GitHub Pro on a private repo): signed commits + `make repo-check` + site strict check, with a one-time `SEGUE_ALLOW_SITE_PLACEHOLDERS=1` bypass for the site check only.

### State
- `make lint`, `make repo-check`, `make build` green. Nothing pushed; all commits local and signed.

### Decisions
- See `docs/release/decisions.md` (release R1-R50) and `docs/decisions.md` (product phases); the two now cross-link.

### Surprises
- Branch protection is unavailable on GitHub Free for private repos (403), hence the hook.
- The scratchpad spike models were already gone; only `Spike/` (595 MB, build output) remains there.

### Next
- Empty the macOS Trash to actually reclaim the space.
- First push (needs Ryan's go-ahead; may use the site bypass while the site is "Coming soon"), then build phase 2 per `docs/release/README.md` section 3 (WS2a takes the app shell).

## 2026-10-18 - App Store release build-out (v0.5), phases 1-4 done; walkthrough in progress

### What changed
- Release plan: `docs/release/` covers decisions R1-R60 (canonical), research 01-09, specs WS1-WS5, open-questions, README (Ryan's checklist + build plan), walkthrough.md, accessibility-audit.md.
- Built and gated: WS1 (bundle split, version 0.5, privacy manifest, logging fixes, library lock, archive/validate/upload scripts, Gig Mode via Shortcuts Events after the R35 probe), WS2a (import/delete to Trash, autosave, menus/Help/About, `?` overlay, R45 Page Down paging, restore, undo), WS3 (consent, TelemetryDeck own client, Sentry, Report a Problem, Featurebase link), WS2b (Welcome sheet A Native, What's New A Notes, Settings 5 panes incl. Appearance, export archive, review prompt, TipKit, .cho UTType + Taped page icon + Quick Look, accessibility pass), WS4 website (R55 mix design, approved for now), repo health (README, LICENSE, CI on Linux, issue forms, Dependabot), cleanup, test speed (make check ~25.5 -> ~12-23 min, `make gate`).
- Pushed to origin/main through the pre-push hook (latest c8b949f).

### State
- The phase 4 gate is green (2 harness flakes fixed after the run, re-run in isolation only). The archive builds a 15 MB pkg passing verify-archive.
- Ryan is doing the R56 walkthrough on the Release-AppStore dev-signed build (`.build/DerivedData/Build/Products/Release-AppStore/Segue.app`), with the old container moved to ~/segue-backups.

### Decisions (see docs/release/decisions.md)
- Free app, store name "Segue - Setlists & Chords", individual team V6BM673U35 (renewed), hosted vendors only, analytics opt-in, Sentry US.
- Push at gates + CI fixes. Credential steps (`make upload`) run by Ryan in Terminal.app (R46). No branch protection (free private repo, R51).

### Surprises
- macOS 26.5+ x-callback-url misreports success; Shortcuts Events via Apple events works (needs Shortcuts Events launched first, -600 otherwise).
- The 1Password CLI works in Terminal.app only, not the agent shell. GitHub Free blocks branch protection on private repos.
- Fast polling exposed hidden E2E races; a PreToolUse hook treats `pgrep -f` next to `git push` as a force push (split the commands).

### Next
- Collect Ryan's walkthrough feedback -> one fix round -> `make check` -> WS5 (screenshots, preview video, metadata) -> site live (Cloudflare Pages + DNS) -> `make upload` by Ryan -> TestFlight -> real gig -> submit. Later: website trim pass (R57); post-launch fold of research docs.
