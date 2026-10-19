# Release decisions (v0.5, Mac App Store)

Ryan's rulings from the release kickoff, 2026-10-17. They are canonical; specs must follow them. Research behind them is in `research/01-08`.

Release rulings live here; product rulings for phases 0-7 live in [../decisions.md](../decisions.md).

## Account and store
- R1. Paid Apple Developer Program, individual, team `V6BM673U35`. The membership was renewed 2026-10-17; App Store Connect access is pending (up to 48h). Seller name: Ryan's legal name.
- R2. Price: free, no IAP. No Paid Apps agreement, no banking. US resident.
- R3. Store name "Segue - Setlists & Chords"; the in-app/Dock name stays "Segue". Subtitle "Lyrics & chords for live gigs". Primary category Music, secondary Productivity.
- R4. EU DSA: non-trader.
- R5. First version **0.5** ("beta-ish"); the build number increments on every upload.
- R6. Rollout: internal TestFlight on Ryan's Mac, a real gig, then App Review.
  - *Order refined by R79 (phase 3 lands first, then the R56 walkthrough, WS5, TestFlight, gig, submit).*
- R7. Apple standard EULA for the app. The site has short plain-language terms for the website, board and bug reports.
- R8. Only one listing localisation for now: English (U.S.). No separate U.K./India listing (unticked; confirm before store metadata work).
- R9. An app preview video is wanted for 0.5 (15-30 s, 1080p, live mode).
- R10. Screenshots: captioned + framed, brand background, generated from the XCUITest suite.

## Build and signing
- R11. Bundle IDs split: App Store keeps `dev.ryandsilva.segue`; Personal becomes `dev.ryandsilva.segue.personal`.
- R12. **Manual signing** for the App Store build: Apple Distribution cert + Mac Installer Distribution cert + Mac App Store provisioning profile, created by Ryan. Personal/Debug may stay automatic.
- R13. Uploads use an App Store Connect API key (`.p8` kept in 1Password, never in the repo). Local `make` targets; no CI.

## App scope for 0.5
- R14. v0.5 = current AppStore build + readiness fixes (`research/06`) + review fixes (`research/03`) + everything below.
  - *Extended by R61: phase 3 "AI entry & assistant" is in v0.5.*
- R15. Must:
  - in-app import (drag and drop + File > Import) and Delete Song;
  - all deletes go to the Trash;
  - Help menu, About panel, a reopen-main-window command;
  - Setlist menu (Start Show, Rehearse, New Setlist) with shortcuts, and a `?` keyboard overlay;
  - review prompt;
  - full accessibility pass, after which only the labels that are actually earned get claimed.
- R16. Nice (also in 0.5):
  - What's New sheet + TipKit tips;
  - Finder integration (`.cho` UTType, Open With, Quick Look preview, Show in Finder);
  - export library archive;
  - restore selected song/section;
  - setlist builder undo.
- R17. **Autosave** replaces explicit Save (Cmd-S becomes a confirming no-op).
- R18. Gig Mode Shortcuts are OFF until the user sets them up. A checklist row ticks only when its Shortcut actually ran successfully.
- R19. First run seeds a deletable Welcome library: 3-5 ORIGINAL songs written for Segue (one romanized Hindi; never real song titles or lyrics) + a demo setlist.
  - *See R78: Welcome songs carry `{duration}` lengths.*
- R20. Review prompt after the 1st completed gig (the "after 3 gigs" option was unticked; confirm), never during a show.
- R21. Help docs are web pages at segue.ryandsilva.dev/help.
- R22. Bug report may offer "attach current song" (off by default) and must preview everything it sends.

## Services
- R23. **Hosted, trusted vendors only.** We never run a backend. Each service sits behind a Swift protocol so the vendor can be swapped. The stack (all free tiers, approved 2026-10-17):
  - **TelemetryDeck** for analytics;
  - **Sentry** for crashes, hangs and MetricKit upload, plus bug reports through Sentry User Feedback with attachments;
  - **Featurebase** for the feature board, a web board linked at /feedback;
  - Apple App Analytics as the baseline.
- R24. Bug reports stay in **Sentry only**: no GitHub bridge, no Make.com. Ryan copies anything worth keeping into GitHub by hand. Sentry free keeps them 30 days.
- R25. Crash/hang reports auto-upload MetricKit via Sentry, with consent. **Separate consent toggles** for "Share usage analytics" and "Send crash reports". **Sentry's per-install ID is kept**; it is declared as Device ID, Not Linked.
- R26. Analytics are opt-in, asked once on first run with equal-weight choices and changeable in Settings > Privacy. Coarse country OK. Retention: about 13 months target, or the vendor's free-tier default (unconfirmed for TelemetryDeck; flag it). Optional email on board posts (handled by Featurebase).

## Website
- R27. segue.ryandsilva.dev on **Cloudflare Pages** (static only), source in `website/`; CNAME at Squarespace DNS.
- R28. Support/contact email `segue@ryandsilva.dev`.
- R29. Pages:
  - Home, /privacy, /support, /terms, /help, /changelog (+ changelog.json for What's New), /press, /acknowledgements, /404;
  - /feedback redirects to the board vendor.

## Resolved open questions (2026-10-17)
All 62 "needs Ryan" items in `open-questions.md` are resolved. Each took the **Recommend** option in that doc, except for the overrides below. The 33 engineering-default items take their stated defaults.

Overrides and specifics:
- R30 (A1). Copyright `© 2026 Ryan Rony Dsilva` everywhere (Info.plist, About, App Store, site, policy).
- R31 (A2). Site terms are governed by the law of **Washington** State.
- R32 (A4). Retention: TelemetryDeck's default, stated plainly in the policy (ask them about a shorter period in parallel); bug and crash reports 30 days; board posts until deleted; support email at most 2 years.
- R33 (A5). Sentry data region is **US** (overrides the EU recommendation). The policy notes US processing under standard contractual clauses.
- R34 (A6). TelemetryDeck goes through our own minimal ingest client, which sends only the listed fields.
- R35 (A36). Focus-row confirmation: first PROBE running the Shortcut through Shortcuts Events (Apple events). If it is reliable and acceptable for the Mac App Store, use it, plus a manual Done fallback. Otherwise use an App Intent as the Shortcut's last step, plus manual Done. See `research/09`.
- R36 (A42). **Keep the Appearance option** in Settings: Match System (default) / Light / Dark.
- R37 (A50). Keywords: `chordpro,songbook,transpose,prompter,worship,hindi,guitar,piano,capo,nashville,stage,singer,cover` (97 bytes).
- R38 (A54). Website analytics: **Cloudflare Web Analytics** (cookieless, no banner); the privacy policy gets a paragraph on it.
- R39 (A41). Show 2-3 design directions each for the Welcome sheet, the What's New sheet, the `.cho` document icon and the website home page before building them.
- R40 (A60). Before the TestFlight install, move Ryan's current `dev.ryandsilva.segue` container aside, and copy his shapes and bindings into the Personal container.
- R41. Xcode 27.1 / Swift 6.4 is the release toolchain (baseline `make check` green, commit 78d2a1d). arm64 only (A59).
- R42 (A44). Ryan approved the indicator token change as rendered: light #8A8A92, dark #66676E, dark played dot #8E8E96.
- R43 (R39). Home page direction: **Stage** (centred hero, wide screenshot, hairline sections, numbered stage callouts, 4-column feature grid).
- R44 (A14). The Welcome titles were searched with no conflicts: "Soundcheck at Seven", "Kitaabon Wali Gali", "Kettle On, Lights Low", "Ferry Lights Over Calder Bay", setlist "Welcome Set".
- R45. Page-turner pedals: on stage, Page Down scrolls, and at the end of a song the next press moves to the next song; Page Up mirrors this backwards (forScore-style, so one pedal runs a whole gig). Owned by WS2a, with an E2E test.
- R46. Credential-carrying steps (`make upload`, the Sentry dSYM upload, anything that runs `op`) are run by **Ryan in Terminal.app**. The 1Password CLI works there but not from the agent shell (sandboxed). Agents prepare and verify everything up to `make validate`, then hand Ryan the exact command. Scripts must fail with a clear message when `op` is unavailable, and must never fall back to plaintext keys.

## Repo health (2026-10-17)
- R47. The GitHub repo stays **private but polished**: README, LICENSE (all rights reserved), third-party notices, SECURITY, CONTRIBUTING, issue forms, PR template, CODEOWNERS.
- R48. CI is **lightweight Linux only** (lint, site check, docs checks, actionlint). Builds and tests stay local under `make check`.
- R49. GitHub Issues are Ryan's dev tracker. Users go to Report a Problem (Sentry) and Featurebase.
- R50. Extras: Dependabot, and release automation (a `v*` tag creates a GitHub Release from changelog.json). GitHub settings changes and pushes need Ryan's explicit go-ahead.
- R51. Branch protection is NOT available: GitHub Free blocks protection and rulesets on private repos, and paying is out. The pre-push hook (`.githooks/pre-push`) enforces it instead: signed commits only, `make repo-check`, and the site strict check. `SEGUE_ALLOW_SITE_PLACEHOLDERS=1` skips only the site check, and only while the site is still "Coming soon" (first pushes before launch). The protection command stays ready in docs/github-setup.md in case the repo goes public.
- R52 (R39). In-app designs: Welcome sheet **A Native**; What's New sheet **A Notes**; `.cho` document icon **B Taped page**. Renders are in the session scratchpad, ws2b-directions.
- R53. The icon fix for the App Store .icns uses the build setting `ASSETCATALOG_COMPILER_STANDALONE_ICON_BEHAVIOR = all` (all ten sizes from Segue.icon), not tracked PNGs. The installer certificate name is `3rd Party Mac Developer Installer`. WS1 owns the dSYM upload (WS3 step 9 is folded into it).
- R54. The vendor HTTP client replaces the system User-Agent and Accept-Language headers, so the Mac's language list and device details are not sent.
- R55. Landing page redesign (supersedes R43 "Stage"): a **mix**. The base and the rounded tiles come from **C Keynote**; the **spotlight hero** comes from **B House Lights**. The "days of the week" story (Monday-Friday) is dropped: the copy becomes a **musician's workflow**, e.g. bring your songs in, make each chart yours, build the set, play the show. The exact wording is drafted by the site agent for Ryan's review. Mockups are in the session scratchpad, ws4-classy.
- R56. Once every app workstream is done (WS2a, WS3, WS2b through their gates), the orchestrator builds and launches the App Store flavour on Ryan's Mac, on a clean first-run state, for a full hands-on walkthrough. His feedback becomes a fix round BEFORE screenshots (WS5), the TestFlight upload and the real gig.
  - *Refined by R79: the walkthrough runs (again) after phase 3 lands.*
- R57. The landing page (R55 build, commits through c3a8fb4) is approved FOR NOW, with the quick-search scrim kept as art direction. Ryan's note: "too much text and site is too long". A later session, once the app is ready, does a trim pass: fewer words and fewer sections. It is recorded as a post-app task in the release README.
- R58. Test speed (Ryan: "cannot be spending so much time as a solo developer"): do ALL of docs/test-performance.md groups A, B and C NOW, before phase 3.
  - A: fast-polling wait helper, animations off in test mode, no duplicate builds or indexing in command-line builds, verify-appstore run in parallel.
  - B: logic checks move to in-process SegueUI integration tests (real stores, files and parser); real user flows stay as XCUITest; tests sharing setup merge into scenario flows; one app launch per class.
  - C: `make gate` runs mapped E2E classes plus a smoke set; `make check` becomes the release gate only.
  Coverage must not drop: every assertion removed from XCUITest must reappear in an in-process test, with a mapping table in the doc.
- R59 (R35 result, 2026-10-18, macOS 26.6.2). The probe passed every rule: OK runs return in about 0.2-0.3 s with no error; the failing Shortcut returns -1753 with its own message; a missing Shortcut returns -1728; there was one Automation prompt only (Ryan); the notification appeared; nothing came to the front. **Path SE** is chosen: run Gig Mode Shortcuts through Shortcuts Events (Apple events, scripting-targets entitlement `com.apple.shortcuts.events: [com.apple.shortcuts.run]`), plus a manual Done fallback. Error mapping: -1728 means not found / not set up; anything else, including -1753, is `.failed` with the Shortcut's message. Results are in .build/shortcuts-probe/results; the research 09 addendum is owed by WS1 step 9.
- R60. Test speed results: `make check` went from about 25.5 to about 13 min, with `make gate` about 6 min. B4 (one app launch per class) is SKIPPED: it would need a Debug-only launch-args-from-file hook to save 30-45 s. A2 (animations off) stays OUT: it measured as noise. C4 (E2E in a VM) is research ticket GitHub #1 (v0.6).

## Phase 3 in v0.5 (2026-10-18)

Ryan's rulings after the phase 3 spikes (`docs/research/phase3-spikes.md`). The canonical phase 3 spec is `docs/phases/3-ai-entry-and-assistant.md`; its workstreams are `docs/phases/3-workstreams/P3-*.md`.

- R61. **Phase 3 "AI entry & assistant" ships in v0.5, before the upload**, in both flavours (extends R14). Phases 4-7 stay post-launch. URL import stays phase 5, Personal-only.
- R62. AI scope: **both flavours** ship Apple Foundation Models plus **one curated local MLX model**, downloaded only on user request. Choosing an arbitrary `mlx-community` model (Settings > AI > Advanced) is **Personal-only**. Narrows the earlier "any mlx-community model" ruling in `../decisions.md` (Phase 3).
- R63. **Paste routing:** curated MLX if installed, else Foundation Models if available, else the deterministic converter alone. The review sheet is always shown. Deterministic conversion runs first; models only refine (labels, metadata, ambiguous lines). **Supersedes** the "Romanized Hindi AI cleanup: try Apple Foundation Models first" ruling in `../decisions.md` (Phase 3 research outcomes) and the spec's FM-first rule.
- R64. **Curated model candidate:** `mlx-community/Qwen3-4B-Instruct-2507-4bit` (2.28 GB), **not locked**. It is locked only after the spike scorer is re-run on 10-20 of Ryan's own real pastes (UG and others, some Hinglish) and reaches >= 90%. The pastes live in the gitignored `research/phase3-eval/pastes/` (format in its README) because they contain copyrighted lyrics; they are never committed.
- R65. **Set assistant:** requests are parsed by an instant code lexicon, then an async model pass whose additions appear as suggested chips. On stage (NL pick during a show): lexicon + text search only; **no model is loaded during a show**. Supersedes the spec's "NL pick < 1 s on FM" (unachievable, spike section 4).
- R66. **Model download:** directly from huggingface.co, pinned revision + SHA256, with R54 header stripping (no Accept-Language, no device User-Agent). No mirror, nothing bundled.
- R67. **Model store shared** between the Personal and App Store flavours through an app-group container (new entitlement; `scripts/verify-archive.sh` check 4 must change with it). Needs proof in the P3-A spike (Mac App Store app-group rules, both flavours signed by team V6BM673U35). Excluded from backup; never in a library export.
- R68. **Low RAM:** show the memory need and warn under 16 GB; never block.
- R69. **Foundation Models unavailable:** a reason-specific inline note per `UnavailableReason` with "Open System Settings"; no nag prompts.
- R70. **Durations:** learned from shows, rehearsals and a new per-song timer, and where nothing is known, **estimated from tempo + line count, always visibly marked** ("~" on the length; totals say e.g. "incl. 3 estimated"). Songs with neither a learned length nor a tempo stay unknown. **Supersedes** the phase 2 build ruling "Unknown song length: ... no made-up default" in `../decisions.md`. Storage: learned lengths derive from the existing canonical `shows/` and `timings/` files (timer samples as `timings/<ulid>.timer.json`); no duplicate store. Ryan did not choose a sidecar `timings` block; the storage choice is listed for confirmation in the phase 3 spec's open questions.
- R71. **Energy deferred** out of 0.5 ("decide later"): no energy field. The set assistant shapes sets with tags (existing sidecar tags), length, key flow and repeat avoidance. Starter tag suggestions are fine (manual pick); **no AI energy or AI tag guesses at import**. **Supersedes** the energy rulings in `../decisions.md` (Phase 3 "energy 1-5 per song" and Round 2 "Energy at import ... AI suggestion").
- R72. **Smart filters** are library files `filters/<slug>.filter.json`, added to `LibraryRoot` and `LibraryArchive.includedFolders`.
- R73. **Settings gets a sixth pane, "AI"** (model download/status; Advanced in Personal only). Reset All Settings resets AI preferences but keeps downloaded models.
- R74. **AI stats are analytics only:** no local stats screen, no local metrics database. Opt-in (existing consent), closed-vocabulary, non-personal TelemetryDeck events: paste outcome, which provider handled it, fallback reason, latency bucket, correction-amount bucket, model download result, assistant and smart-filter use. Never song text or titles. Requires an `AnalyticsEvent`/`IngestBody` allowlist change and an update to the privacy policy's example list. Supersedes the spec's local "Observability" store and Stats view.
- R75. **Paste entry points:** File > New Song from Clipboard (`⌥⌘V`; verify it is free), a button in the empty-library state, and `⌘V` while the song list has focus.
- R76. **`.crd` import accepted**, routed through the converter and review sheet.
- R77. **Code placement:** new `Packages/SegueAI` (FM + MLX adapters, downloader); the provider port types and a `ScriptedProvider` (replays recorded real outputs) live in SegueCore. One code path on macOS 26; the macOS 27 `LanguageModel` / `MLXFoundationModels` path is revisited in 0.6.
- R78. **Welcome songs get `{duration}` lengths** (no energy) so set timing works out of the box (the four shipped Welcome songs already carry them).
- R79. **Release order:** phase 3 lands -> Ryan's R56 walkthrough -> WS5 screenshots, preview and metadata -> TestFlight -> real gig -> submit. New UI gets its own accessibility walk before any accessibility label is claimed. Refines R6 and R56.

Not yet decided (open questions for the WS5-stage fold-in, listed in the phase 3 spec section 16.2): a 9th screenshot vs replacing one; a keywords swap; the age-rating AI questionnaire and content-rights answer with a downloadable model (a quick research ticket before WS5 is recommended); "Apple Intelligence" trademark usage in marketing copy.

Walkthrough rule (2026-10-18, Ryan): **a song appears at most once per setlist**, enforced in code; the phase 3 set assistant and request queue treat it as an invariant.
