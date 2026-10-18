# Release decisions (v0.5, Mac App Store)

Ryan's rulings from the release kickoff, 2026-10-17. They are canonical; specs must follow them. Research behind them is in `research/01-08`.

## Account and store
- R1. Paid Apple Developer Program, individual, team `V6BM673U35`. The membership was renewed 2026-10-17; App Store Connect access is pending (up to 48h). Seller name: Ryan's legal name.
- R2. Price: free, no IAP. No Paid Apps agreement, no banking. US resident.
- R3. Store name "Segue - Setlists & Chords"; the in-app/Dock name stays "Segue". Subtitle "Lyrics & chords for live gigs". Primary category Music, secondary Productivity.
- R4. EU DSA: non-trader.
- R5. First version **0.5** ("beta-ish"); the build number increments on every upload.
- R6. Rollout: internal TestFlight on Ryan's Mac, a real gig, then App Review.
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
