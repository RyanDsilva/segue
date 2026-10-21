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
  - *Extended again by R138: phase 4 PDFs, N1, N4 and N8 are in v0.5.*
- R15. Must:
  - in-app import (drag and drop + File > Import) and Delete Song;
  - all deletes go to the Trash;
    - *One exception, R99: a downloaded AI model is removed directly after a confirmation (re-downloadable app data, not a user document).*
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
  - *Amended by R138 (2026-10-20): the phase 4 PDFs, N1 Singer view, N4 Medleys and N8 Gig stats join v0.5; phases 5-7 stay post-launch in the R138 order.*
- R62. AI scope: **both flavours** ship Apple Foundation Models plus **one curated local MLX model**, downloaded only on user request. Choosing an arbitrary `mlx-community` model (Settings > AI > Advanced) is **Personal-only**. Narrows the earlier "any mlx-community model" ruling in `../decisions.md` (Phase 3).
- R63. **Paste routing:** curated MLX if installed, else Foundation Models if available, else the deterministic converter alone. The review sheet is always shown. Deterministic conversion runs first; models only refine (labels, metadata, ambiguous lines). **Supersedes** the "Romanized Hindi AI cleanup: try Apple Foundation Models first" ruling in `../decisions.md` (Phase 3 research outcomes) and the spec's FM-first rule.
- R64. **Curated model candidate:** `mlx-community/Qwen3-4B-Instruct-2507-4bit` (2.28 GB), **not locked**. It is locked only after the spike scorer is re-run on 10-20 of Ryan's own real pastes (UG and others, some Hinglish) and reaches >= 90%. The pastes live in the gitignored `research/phase3-eval/pastes/` (format in its README) because they contain copyrighted lyrics; they are never committed.
- R65. **Set assistant:** requests are parsed by an instant code lexicon, then an async model pass whose additions appear as suggested chips. On stage (NL pick during a show): lexicon + text search only; **no model is loaded during a show**. Supersedes the spec's "NL pick < 1 s on FM" (unachievable, spike section 4).
- R66. **Model download:** directly from huggingface.co, pinned revision + SHA256, with R54 header stripping (no Accept-Language, no device User-Agent). No mirror, nothing bundled.
- R67. **Model store shared** between the Personal and App Store flavours through an app-group container (new entitlement; `scripts/verify-archive.sh` check 4 must change with it). Needs proof in the P3-A spike (Mac App Store app-group rules, both flavours signed by team V6BM673U35). Excluded from backup; never in a library export.
  - *Proven locally by P3-A, R100 (group `V6BM673U35.dev.ryandsilva.segue.models`, no profile regeneration); App Store Connect validation pending at the first real `make validate`.*
- R68. **Low RAM:** show the memory need and warn under 16 GB; never block.
- R69. **Foundation Models unavailable:** a reason-specific inline note per `UnavailableReason` with "Open System Settings"; no nag prompts.
- R70. **Durations:** learned from shows, rehearsals and a new per-song timer, and where nothing is known, **estimated from tempo + line count, always visibly marked** ("~" on the length; totals say e.g. "incl. 3 estimated"). Songs with neither a learned length nor a tempo stay unknown. **Supersedes** the phase 2 build ruling "Unknown song length: ... no made-up default" in `../decisions.md`. Storage: learned lengths derive from the existing canonical `shows/` and `timings/` files (timer samples as `timings/<ulid>.timer.json`); no duplicate store. Ryan did not choose a sidecar `timings` block; the storage choice is listed for confirmation in the phase 3 spec's open questions.
  - *Superseded by R91 (2026-10-19): no learned lengths and no estimates; manual length plus a per-song "Time it" timer; unknown stays unknown and is flagged in totals (the phase 2 rule stands again).*
- R71. **Energy deferred** out of 0.5 ("decide later"): no energy field. The set assistant shapes sets with tags (existing sidecar tags), length, key flow and repeat avoidance. Starter tag suggestions are fine (manual pick); **no AI energy or AI tag guesses at import**. **Supersedes** the energy rulings in `../decisions.md` (Phase 3 "energy 1-5 per song" and Round 2 "Energy at import ... AI suggestion").
- R72. **Smart filters** are library files `filters/<slug>.filter.json`, added to `LibraryRoot` and `LibraryArchive.includedFolders`.
- R73. **Settings gets a sixth pane, "AI"** (model download/status; Advanced in Personal only). Reset All Settings resets AI preferences but keeps downloaded models.
- R74. **AI stats are analytics only:** no local stats screen, no local metrics database. Opt-in (existing consent), closed-vocabulary, non-personal TelemetryDeck events: paste outcome, which provider handled it, fallback reason, latency bucket, correction-amount bucket, model download result, assistant and smart-filter use. Never song text or titles. Requires an `AnalyticsEvent`/`IngestBody` allowlist change and an update to the privacy policy's example list. Supersedes the spec's local "Observability" store and Stats view.
  - *Amended by R98: `pasteFinished` carries an opt-in "romanized Hindi detected" Bool. Requests made during a show no longer occur for paste (R95), so the `duringShow` fallback value is dropped.*
- R75. **Paste entry points:** File > New Song from Clipboard (`⌥⌘V`; verify it is free), a button in the empty-library state, and `⌘V` while the song list has focus.
- R76. **`.crd` import accepted**, routed through the converter and review sheet.
- R77. **Code placement:** new `Packages/SegueAI` (FM + MLX adapters, downloader); the provider port types and a `ScriptedProvider` (replays recorded real outputs) live in SegueCore. One code path on macOS 26; the macOS 27 `LanguageModel` / `MLXFoundationModels` path is revisited in 0.6.
- R78. **Welcome songs get `{duration}` lengths** (no energy) so set timing works out of the box (the four shipped Welcome songs already carry them).
- R79. **Release order:** phase 3 lands -> Ryan's R56 walkthrough -> WS5 screenshots, preview and metadata -> TestFlight -> real gig -> submit. New UI gets its own accessibility walk before any accessibility label is claimed. Refines R6 and R56.

Not yet decided (open questions for the WS5-stage fold-in, listed in the phase 3 spec section 16.2): a 9th screenshot vs replacing one; a keywords swap; the age-rating AI questionnaire and content-rights answer with a downloadable model (a quick research ticket before WS5 is recommended); "Apple Intelligence" trademark usage in marketing copy.

Walkthrough rule (2026-10-18, Ryan): **a song appears at most once per setlist**, enforced in code; the phase 3 set assistant and request queue treat it as an invariant.
  - *Extended to live mode by R102 (no repeats within a show).*

## Metadata entry, fast set building and the phase 3 open questions (2026-10-18/19)

Ryan's rulings on the metadata/set-building brainstorm (from his R56 walkthrough: "the song markers and metadata need to be thought out well, it is hard to type in and remember everything and insert everything correctly, it should be very easy and quick to build a setlist") and on the phase 3 spec's open questions 1-16 (section 16.1). The brainstorm's mockups (`mock-a/b/c`) live in a session scratchpad and are not in the repo; the design is written out in the phase 3 spec section 16.0. Workstreams: `docs/phases/3-workstreams/P3-10` to `P3-15`.

Metadata entry and fast set building:

- R80. **Direction B, the song card.** An inspector card (library detail pane and editor) whose controls write the ChordPro directives and the sidecar for the user: title, artist, key, tempo, length (with "Time it", R91), capo, time signature, proficiency, tags. Files stay standard ChordPro; Text mode is the escape hatch. **Set essentials** = key + length + tempo, each marked with a dot when missing. The paste review sheet's metadata block is the same component.
- R81. **Text mode helpers, from direction A:** a `/` slash-command menu (plain names; a section entry wraps the selected lines; value pickers for key, tempo and length), plus the `{` completion fixes from the brainstorm audit (offer `start_of_*` when a section word is typed, short forms, labelled forms, value help, and key validation: `{key: Hm}` is flagged with a fix).
- R82. **Section band** in the visual editor, Logic-style: select lines, then V / C / B / I keys or chips make or relabel a section; drag a band's edge to resize it.
- R83. **New song starts with the paste flow**, with a "Start blank" link that opens a blank editor plus the song card.
- R84. **Set builder Pick and Arrange modes.** Pick: Space ticks, ⌘A ticks the filtered list, tick order = set order. Arrange: ⌥↑ / ⌥↓ and drag. **Plus real multi-select in the main Library** (⌘-click, ⇧-click) with Add to Setlist.
- R85. **Break rows inside one setlist**; each part shows its own total.
- R86. **Changeover time** per setlist, with a global default, added to the totals.
- R87. **One section note:** `{comment}` and live cues merge into a single "section note" concept with a "Show on stage only" toggle.
- R88. **Missing-lengths list:** the set total's "N unknown" becomes a button that lists exactly which songs lack a length (each row opens that song's card on Length).
- R89. **No ⌘K add palette in 0.5** (direction A's palette is not built).
- R90. **Visual metronome in 0.5:** a small corner overlay on stage pulsing at the song's tempo and time signature; toggled per show and by a key; **sound only in rehearsal mode, never during a show**.

Lengths:

- R91. **Manual length plus "Time it".** Length is entered on the song card (writes `{duration}`), and a per-song "Time it" timer fills the field. **No learning** from shows or rehearsals and **no estimates**. Unknown stays unknown and is flagged in totals: the phase 2 rule ("Unknown song length: ... no made-up default", `../decisions.md`) stands again. **Supersedes R70.** Phase 3 spec questions 1, 2, 5 and 6 are moot; P3-5 shrinks to the timer and the length field.

Set assistant:

- R92. Tempo is usable **as an explicit filter only** (question 3 = b). Opener/closer shaping **only when asked**, via tags (question 4 = a). The async refinement pass uses the **local model if installed, else Apple Foundation Models** (question 14 = a); its output stays suggested chips the user accepts. Energy stays deferred (R71).

AI runtime:

- R93. **One toggle**, "Use AI to refine pastes and set requests", default on (question 9 = b). The curated model is offered only through a **quiet download link** in Settings > AI, the Welcome card and the review sheet footer; no popups or tips (question 10 = b).
- R94. **Model residency: load per paste or request, unload right after** (question 11 = b). The cold-load cost is accepted (spec estimate about 2.3 s; P3-A measured a load of 0.8-1.2 s in the archived app).
- R95. **Paste is disabled while a show is running** (question 12, option c). Supersedes the spec's "a paste during a show gets the deterministic result".
- R96. **Bulk import of files that need conversion:** ONE review sheet lists every converted file with a per-file preview and a checkbox; the ticked ones import together (question 13, a new option replacing "one sheet per file with Skip Remaining").
- R97. **Custom-model code** (Personal-only Advanced) lives in `SeguePersonalModules` (question 7 = a).
- R98. **`Segue.AI.pasteFinished` carries an opt-in "romanized Hindi detected" flag** (question 15 = a). Amends R74's parameter list (the spec recommended excluding it).
- R99. **Deleting the downloaded model removes it directly after a confirmation**, not via the Trash (question 16 = b). The one exception to R15's "all deletes go to the Trash".
- R100. **The shared app-group store is proven** (question 8 is moot): P3-A showed both flavours reading one store under the team-prefixed group `V6BM673U35.dev.ryandsilva.segue.models`, with no profile regeneration (`docs/research/phase3-mlx-in-app.md`). App Store Connect acceptance of the entitlement is still pending and is checked at the first real `make validate` (Ryan, R46). Refines R67.

Paste converter (P3-1, built in `Packages/SegueCore/Sources/Ingest`, commit 55d8701):

- R101. Rulings on the converter's open choices:
  - An unheaded block whose lyrics repeat an earlier block: **label both Chorus** (raises deterministic label accuracy from 92% to 99% on the gold set). A follow-up code change, done as P3-2 step 0.
  - With a capo, **`{key}` is the shapes key** (the key of the chords as written).
  - Unknown pasted lines (tuning, strumming patterns) become **`{comment}`**.
  - Accepted as defaults: detected keys are **not written into the `.cho`** (they are shown in the review sheet only); chord-site credits map Singer -> artist, Music -> composer, Lyrics -> lyricist, Movie -> album; a chord over a space attaches to the next word.

Live mode and About:

- R102. **No repeats in live mode either.** During a show, adding a song (Insert Next, a request, Play Now) that was already played or is still upcoming in that show is refused with a clear message; for an upcoming song it offers to move it to next instead. Extends the walkthrough rule. A follow-up workstream (P3-15).
- R103. **About panel: variant A**, the native system About panel, tightened: icon, name, version, copyright and ONE row of links (Website, Help, Support, Privacy Policy). The system panel dims its credits in dark mode, so the implementer must verify the links stay legible (contrast) in dark mode.

Phase 3 spec questions 21-29 (Ryan, 2026-10-19):

- R104. Break rows on stage: a break interstitial ("Break - Set 2 starts with <song>"); Next continues; the show clock keeps running (question 21 = a).
- R105. A break row may carry an optional length, counted in the whole-setlist total only (question 22 = a).
- R106. Section notes: chart notes stay `{comment}` in the `.cho`, stage-only notes stay sidecar cues; the toggle moves a note between them (question 23 = a).
- R107. The set assistant's packer leaves songs with no length out and says "N songs left out: no length", linking to the missing-lengths list (question 24 = a).
- R108. Metronome: hidden for songs without `{tempo}`; the per-show toggle remembers the last choice; rehearsal sound off by default (question 25 = a).
- R109. During a show, every route into the review sheet is disabled (clipboard paste, `.txt`/`.crd` conversion imports, New Song's paste flow goes straight to Start blank); already-ChordPro imports stay allowed (question 26 = a).
- R110. Set essentials outside the card: a quiet dot on library rows and the builder's library column, plus a built-in "Missing essentials" filter (question 27 = c).
- R111. Tap tempo on the song card: yes (question 28 = a).
- R112. "Already played" for R102 means actually played, in gigs and rehearsals alike; a skipped song may be added back (question 29 = a).

Test budget (Ryan, 2026-10-19, fourth flag: "Over testing is a habit we want to avoid"):

- R113. Per step: only targeted in-process suites. New UI behaviour is covered by in-process SegueUI tests; a new XCUITest only for a flow that cannot be tested in-process. End of a workstream: ONE `make quick` plus ONE `make e2e-one` per UI test class added or changed. **No `make gate` per workstream:** the orchestrator runs one `make gate` per wave after the wave's workstreams land. `make check` only at the phase gate. No E2E retry loops, no duplicate builds in scratch worktrees. Supersedes the per-workstream gate in R58/R60 and the P3 workstream briefs.

Set assistant (Ryan, 2026-10-19):

- R114. Set assistant UI: design A, a command bar above the set in Arrange; Build fills the open setlist as one undo step (no draft setlist).
- R115. Locked songs are saved in the setlist file and survive reopening; Rebuild honours them.
- R116. Apple Foundation Models is NOT used for set requests (it invented tags and proficiencies in testing); suggestion chips come only from the downloaded local model, else the lexicon alone. "Start soft / end soft" phrases are dropped. Supersedes the FM fallback in R92.

Paste review and metronome (Ryan, 2026-10-19):

- R117. Paste review sheet: design D1 (a small sparkle marks AI-decided labels and fields; quiet "Refining with..." status; one-line footer). During a show, already-ChordPro imports stay allowed and New Song opens blank (R109); a mixed import is one undo step.
- R118. Visual metronome: design A (one pulsing dot plus BPM, bottom right; beat 1 red). Compound meters count the dotted-quarter pulse (6/8 = 2 pulses per bar). M toggles it for the current show only. The rehearsal click starts off in every rehearsal and is toggled with K (rehearsal only).

Curated model (Ryan, 2026-10-19, after the 51-paste bake-off, docs/research/phase3-model-bakeoff.md):

- R119. The curated local model is locked: Qwen3-4B-Instruct-2507 4-bit (revision 50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b), with a small MLX cache (about 64 MB; same output, about 0.8 GB less memory). No smaller model and no second "quality" tier: every model under about 2 GB scored at or below the converter alone.
- R120. On Macs with less than 16 GB of memory (e.g. the 8 GB MacBook Neo), Apple Foundation Models is the default; the Qwen3-4B download stays available as an opt-in with a clear speed and memory note. Refines R68 and the routing in R63 for low-memory Macs.
- R121. Title and artist: the converter wins. Skip the model's metadata call when the converter found both; never take a model artist when the converter found the title or a site heading.

Gig arrangements (Ryan, 2026-10-19):

- R122. Per-slot arrangements ship in 0.5 (new workstream P3-16). A setlist slot may override which sections of the song are played: skip sections, set repeat counts and reorder them, for that gig only. The `.cho` stays the master and is never changed; "Reset to full song" removes the override. Section references use the same label-plus-occurrence anchoring as section notes; an arrangement whose sections no longer exist is flagged "out of date" and the stage shows the full song. A slot with an arrangement takes a manually entered (or timed) length for that slot; the song file keeps the full song's length. If no slot length is entered, the slot's length is unknown and flagged (never derived from the full length). No named song-level arrangements and no stage-time section jumping in 0.5.
- R123. Per-slot arrangement details (P3-16 open questions): the editor is the "Arrange Sections" sheet with a live stage preview, opened from the slot popover's Arrangement row, the slot context menu and a Setlist menu item (question 7 = B). An extra play follows the song's collapse-repeats setting (1 = b). "Play Again Later" duplicates a row to drag anywhere (2 = b). Each block of lines outside any section is its own row (tickable, skippable, movable, with a play count); lines before the first section are a "Lead-in" row (3). Sections are matched by label + occurrence plus a fingerprint of the first two lyric lines; a mismatch marks the arrangement out of date, and new sections appear unticked under "New in the song" without marking it out of date (4 = b). Out of date: builder mark, a pre-show checklist row with Edit, totals keep the slot length, a quiet "Full song" note on stage (5 = a). Every setlist saved by this build is written at schema 5 (6 = a). A running show copies arrangements exactly as it copies key and capo when the setlist is edited mid-show.

AI accuracy follow-up (Ryan, 2026-10-19, after reconciling eval-ai with the bake-off; correction section in docs/research/phase3-model-bakeoff.md):

- R124. The lyric guard stays strict. The lost "other" labels are recovered in the converter instead: chord-site menu and settings text ("Transpose", "Display Settings" and similar) becomes junk deterministically. Also fix the guard defect where adjacent inline-chord blocks regroup and the whole song's labels are thrown away (drop only the offending labels).
- R125. Qwen3-4B stays the optional download (R119 stands): in the shipped app it scores 90.1% vs Apple FM 89.7% on the 51 pastes, about 2.5x faster, and with no Hindi refusals.

User guide (Ryan, 2026-10-19):

- R126. A user guide with screenshots ships with 0.5 at `segue.ryandsilva.dev/guide` (same site and deploy; it replaces `/help`, which redirects to it), built with Astro Starlight (free, open source; Node/bun toolchain pinned via mise for the docs only). Screenshots are generated from the real app by a scripted capture (`make docs-shots`, Welcome library, light and dark) so they never go stale; a few short silent how-to clips (paste a song, build a set, go on stage); in-app Help buttons and tips open the matching guide page. Spec: docs/release/specs/WS6-user-guide.md.

User guide build rulings (Ryan, 2026-10-19, WS6 open questions 1-8):

- R127. WS6 (docs/release/specs/WS6-user-guide.md) is built as specified with: direction **C "Tiles"** (1); the guide's theme **follows the system only**, no toggle (2); **WS6 builds the shared capture layer** (WS5 8.2-8.3 flags and the `SegueAppStoreUITests` target) exactly as WS5 specifies (3); screenshots and clips **committed as AVIF and MP4** with size budgets (4); clips are **click to play** with no JavaScript (5); **numbered coral callout dots** placed from element frames recorded at capture (6); **Starlight's own scripts are allowed under `/guide/*` only**, so search works, with the path-scoped CSP (7). Order (8): the guide site, theme, IA, all page copy, redirects, deep links (`SegueLinks.Guide`, app wiring, `/help` redirects), CI and the `docs-shots`/`docs-clips` tooling land now; the final screenshots and clips are generated after Ryan's R56 walkthrough fix round (placeholders or current captures until then).

Screenshot content (Ryan, 2026-10-20, WS5 question 1):

- R128. The screenshot-only setlist is named **"JamFest Opener"** (replaces "Late Set" in the WS5 and release README docs; the unrelated "Late Set" test data in `UITests/SegueSetlistGigLogE2ETests.swift` stays). The approved screenshot-only songs are five, deliberately fewer than the old 6-10 guideline: **Lanterns on Pier Nine** (D, 92, 3:48), **Chai at Platform Four** (Em, 96, 3:40), **Northbound Before Dawn** (Bb, 76, 4:30), **Saltwater Telegraph** (Am, 100, 3:35), **Last Tram to Wexley** (G, 132, 3:10); the other five proposed titles are dropped. Each approved title still goes through the title search before use. The rest of WS5 8.4.1 stands: "Ferry Lights Over Calder Bay" in position 3, "Kitaabon Wali Gali" not in the set, and a total a little under the target.
  - *Title search 2026-10-20 (P3-9, `docs/research/phase3-store-ai.md` section 7): "Northbound Before Dawn" has an exact hit on Apple Music ("Northbound Before Dawn (Delta Blues)" by Cora Flood), so by the search rule it drops unless Ryan keeps it; the replacement is an open question. The other four had no hit on Apple Music, Spotify or Google.*

Store answers and copy (Ryan, 2026-10-20, from docs/research/phase3-store-ai.md and WS5 section 17):

- R129. "Northbound Before Dawn" (title-search hit) is replaced by "Northbound at First Light" (Bb, 76, 4:30). A 9th App Store screenshot is added: the paste review sheet (light), headline "Paste a song from anywhere.", subline "Segue converts it. You check it before it saves." Age rating 4+ (no AI item; user-generated content No). Content rights: Yes, has the necessary rights (Apache-2.0 weights). App Privacy label unchanged. "Apple Intelligence" only in referential use ("works with Apple Intelligence"), never in a feature name, no trademark symbol, plus "Apple Intelligence is a trademark of Apple Inc." on /acknowledgements. Keywords unchanged (R37). The new promotional text, description and review notes in WS5 / app-store-connect.md are approved.

- R130 (Ryan, 2026-10-20). App Store screenshot layout A (store/screenshots.json direction A) and the 23 s preview cut are approved; the poster frame is set at about 6 s in App Store Connect. The phase 3 site copy (privacy, support, acknowledgements) is approved and published.
- R131 (Ryan, 2026-10-20). The phase 3 walkthrough is done with no changes requested; every open walkthrough question keeps the as-built behaviour.

## Roadmap prioritization (Ryan, 2026-10-20)

Ryan's session on what phases 4-7 keep, what joins them and in which order. Item numbers follow Ryan's session list (phase.item): 4.3 is the phase 4 spec's "Setlist one-pager" and 4.5 its "ChordPro export"; 5.1-5.3 are the phase 5 goals; 6.1-6.4 are the phase 6 scope bullets (pedals, MIDI input, mapping UI, presets); 7.1-7.4 are the phase 7 goals and scope (iOS app, iCloud Drive sync, partner follow, personal modules on iOS). N1-N9 are the session's new-feature suggestions. The phase specs (`docs/phases/4-7`) and `docs/00-vision.md` are edited in place to match.

- R132. **Removed from the roadmap:** 4.3 the setlist one-pager (floor sheet); 4.5 ChordPro export (the library already is ChordPro files, and the Settings export archive covers a whole-library copy); 5.1 audio-to-chart (recording, separation, transcription, chord detection and its eval); 6.1 Bluetooth HID pedals and 6.4 the pedal presets; 7.2 iCloud Drive library sync with its conflict UI (replaced by R134). Supersedes the matching rulings in `../decisions.md` (Phase 4 "ChordPro export applies current transpose", Phase 5 in-app recording, ASR default and accuracy gate, Phase 7 "user-picked iCloud Drive folder" and the R7.2 research outcome).
- R133. **Kept:** phase 4 single chart PDF and songbook PDF, with print and the embedded preview as their infrastructure; 5.2 LRCLIB lyrics search and 5.3 URL import (Personal-only, `SeguePersonalModules`); 6.2 MIDI input and 6.3 the mapping UI with MIDI learn; 7.1 the iOS/iPadOS app, 7.3 live partner follow and 7.4 personal modules on iOS.
- R134. **iOS library source replaces 7.2:** the iOS app opens a library folder the user picks in the Files app (any provider: iCloud Drive, Dropbox, On My iPhone) and reads the ChordPro files and sidecars in it directly. There is no Segue sync engine and no conflict UI; syncing is the file provider's job. Supersedes the phase 7 library sync design and the vision's "iOS sync later via iCloud Drive folder".
- R135. **MIDI output reopened (research first).** Ryan wants per-song preset switching on his Ampero II Stomp, which reopens the phase 6 non-goal "MIDI output (per-song program changes) - decided: not built" and `../decisions.md` Phase 6 "None of: MIDI program-change out". A research ticket comes first: Ampero II Stomp program change over USB MIDI and TRS MIDI, timing on song change, banks and preset numbering. Scope is decided after it lands: a Personal module (Ryan's suggestion) or a generic MIDI-out feature in the store build. The ticket runs alongside the MIDI input phase (R138).
- R136. **New features added** (specs not written yet):
  - N1 **Singer view:** a lyrics-only view with the chords hidden.
  - N4 **Medleys:** several songs joined into one set slot with a written transition.
  - N5 **Share by file:** AirDrop or Share a setlist plus its songs as one file; goes with the iOS phase.
  - N8 **Gig stats:** most played, not played lately and per-venue history, built on the existing play history (gig log).
- R137. **Considered and declined:** N2 an external stage display; N3 Shortcuts/Siri/Spotlight App Intents; N6 OnSong/OpenSong import; N7 extra instrument diagrams (ukulele, bass); N9 a per-singer default key.
- R138. **Order.** Launch is blocked on the Apple account anyway, so v0.5 (pre-launch) gains: the phase 3 leftovers, the phase 4 PDFs (single chart, songbook, print, embedded preview), N1 Singer view, N4 Medleys and N8 Gig stats. Then phase 6 (MIDI input and mapping with MIDI learn) with the R135 Ampero research alongside. Then phase 5 (LRCLIB search, URL import). Then phase 7 (iOS app, partner follow, personal modules on iOS) with N5 Share by file. Ryan did not rank phase 5 against phase 7; iOS last is the orchestrator's default and open to change. Amends R61 ("phases 4-7 stay post-launch") and extends R14.
- R139. **App Store only.** No DMG and no direct (Developer ID) distribution.

## Store media, controls, phase 3 leftovers and section note placement (Ryan, 2026-10-20)

Ryan's answers to the follow-ups from the roadmap session (R132-R139) and to the Featurebase bug "Section Notes Exact Placement". The phase specs `docs/phases/6-hands-free-control.md` and `docs/phases/7-ios-and-partner-sync.md` are edited in place to match; the section note work has its own spec, `docs/phases/3-workstreams/P3-17-section-note-placement.md`.

- R140. **One store media pass for v0.5.** After the phase 4 PDFs, N1 Singer view, N4 Medleys and N8 Gig stats are built (R138), ONE pass re-captures the App Store screenshots, the preview video and the user guide captures (`make screenshots`, `make preview`, `make docs-shots` / `docs-clips`), followed by ONE walkthrough of the whole v0.5 build. No re-capture before then. Amends R130: layout A and the preview cut stay approved as designs, but the approved captures are replaced by that pass.
- R141. **Controls mapping UI takes MIDI and keyboard keys.** The phase 6.3 mapping UI binds any live command to a MIDI trigger AND/OR a keyboard key, with **MIDI learn and key learn** ("press the pedal or key now"). Page-turn pedals and clickers that send keystrokes (AirTurn, PageFlip, presenter clickers) work through key bindings; there is no dedicated pedal feature, no HID pedal input path and no pedal presets (R132 stands for those). Amends R132's removal of key learn.
- R142. **Phase 3 leftovers in v0.5** (the "phase 3 leftovers" of R138) are exactly: de-flake `VendorConsentTests`, and close the paste converter gaps: en-dash metadata lines, emoji-prefixed `Song:` / `Singer:` lines, footnotes, fingering lines and a lone `0`. Everything in the phase 3 spec section 16.0.8 stays out of v0.5: no ⌘K add palette, no gaps queue and no "Detect sections and key" on existing songs, no learned or estimated lengths, no energy, no metronome sound during a show. The set assistant's MLX recordings were not picked and are not in v0.5.
- R143. **Phase 7 open questions 3 and 4, and the custom model.** Keep "Gig ready": before a gig the iOS app eagerly downloads a setlist's files from a cloud-provider Files folder and pins them offline, rather than relying on the provider's own offline setting (question 3). Keep one gig-log file per device per gig (question 4). The Personal-only custom model setting (R97) stays Mac-only and is not offered on iOS.
- R144. **Section note placement** (Featurebase "Section Notes Exact Placement"). The crash when adding notes to several sections is fixed in commit dce53bc (pending rows keyed by id). Placement is option B: an **instance picker** when adding a note (Chorus #1, #2, ..., Every time), defaulting to the instance whose band context menu opened the sheet, **plus stable note IDs**. For `{chorus}` repeats the picker lists them as targets, and picking one explains that only a stage note can go there (a `{comment}` line cannot sit inside a repeat). A second note on the same section is **appended after the existing notes**, never inserted above them (today's `insertComment` at the section header in `SectionNotes+Edits.swift:104` puts it first). Spec and its open questions (how chart notes in the `.cho` get a stable identity): `docs/phases/3-workstreams/P3-17-section-note-placement.md`.
