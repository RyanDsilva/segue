# Release open questions - consolidated decision sheet (v0.5)

Compiled 2026-10-17 from the "Open questions" sections of the six release specs:
`specs/WS1-release-pipeline.md` (17), `specs/WS2a-core-ux.md` (33), `specs/WS2b-first-run-polish.md` (22), `specs/WS3-services.md` (12), `specs/WS4-website.md` (15), `specs/WS5-store-listing.md` (13). 112 source questions in total.

`decisions.md` (R1-R29) is canonical. This sheet does not change any spec; once Ryan answers, the answers go into `decisions.md` as new R-numbers and the specs are corrected in place.

Source references are written `WS2a-17` (= WS2a open question 17).

## Counts

| | Merged questions | Source questions covered |
|---|---|---|
| Already answered by `decisions.md` (section 1) | 5 | 6 |
| (A) NEEDS RYAN (section 2) | 62 | 75 |
| (B) ENGINEERING DEFAULT (section 3) | 33 | 34 |
| **Total** | **100** | **115** references to 112 distinct source questions (3 sources appear twice; see notes) |

Sources used twice: WS4-6 feeds A1 (name) and A2 (governing state); WS2b-18 feeds A45 (text scaling) and B-19 (Larger Text claim); WS1-6 is answered by R12 and its residual placement is B-1. Merges across specs: e.g. A1 (4 sources), A25 (4), A33 (3), A4 (WS4-5 + WS3-2), A10 (WS2b-13 + WS3-9, laid out per R25). Two rulings are "decided but flagged for confirmation" in `decisions.md` itself (R8, R20); they stay as A items (A46, A12) with the ruling as the recommended option.

Cross-spec contract conflicts are in section 4 (17 found). The proposed build order is section 5.

Two referenced documents do not exist yet: `research/09-shortcut-confirmation.md` (A36 waits on it) and, until today, `specs/WS3-services.md` (now written and included).

---

## 1. Already answered (dropped)

| Source | Question | Answered by |
|---|---|---|
| WS2b-3, WS4-4 | Is crash-report consent asked in onboarding, or folded into the analytics answer? | **R25**: separate toggles for "Share usage analytics" and "Send crash reports"; both are asked at first run. WS3 4.2 already builds it this way. (The layout of the two-question step is still open: A10.) |
| WS2a-20 | Terms vs EULA: what does Help > Terms of Use open? | **R7**: Apple's standard EULA for the app plus short site terms. Help > Terms of Use opens `/terms`; `/terms` section 1 already links Apple's EULA (WS4 9.5). |
| WS1-6 | Manual signing in Release-AppStore build settings, or only at export? | **R12** rules manual signing with the distribution certs and a MAS profile. Residual placement is an engineering choice, taken as B-1. |
| WS2a-33 | Record that R17/brief override research 08 (autosave; separate Report a Problem / Request a Feature) | **R17** and R15. Informational only. |
| WS2b-21 | Should research 08's placement of Quick Look (post-launch) and sample songs (public-domain) override? | **R16** (Quick Look in 0.5) and **R19** (original songs seeded on first run). |

Also answered, but embedded in spec text rather than asked: WS4 (canonical-inputs line, `githubIssues` variant, vendor table) and WS5 section 6 (`BUGREPORT` row) still assume a GitHub bridge "if the vendor supports it". **R24** rules it out (Sentry only). See I-8.

---

## 2. (A) NEEDS RYAN, grouped for batched asking

Format per question: the question; options; **Recommend**; **Blocks**.

### 2.1 Legal and identity (includes privacy declarations)

**A1. Copyright line and legal name** (WS1-12, WS2a-29, WS5-2, WS4-6 first half)
One string is used by Info.plist `NSHumanReadableCopyright`, the About panel, the App Store "Copyright" field, the site footer and the privacy policy's controller name.
- a) `© 2026 Ryan Rony Dsilva` (seller legal name per R1 and the team name in Xcode)
- b) `© 2026 Ryan D'Silva` (today's Project.swift)
- c) `© 2026 Ryan Dsilva` (WS4 `site.json` displayName)
- **Recommend a** - App Store shows the seller name next to the copyright; one legal name everywhere avoids a mismatch Apple or a reader could query.
- **Blocks**: WS1 step 2 (Info.plist, verify-archive check 8) and B-6 (resource bundle plist); WS2a About panel test; WS4 `site.json owner.legalName`; WS5 `copyright.txt` and review contact name.

**A2. Governing-law state for the site terms** (WS4-6 second half)
- a) Your U.S. state of residence (tell us which)
- b) No governing-law clause
- **Recommend a** - standard for U.S. terms; costs nothing.
- **Blocks**: WS4 `/terms` section 12, `make site-check STRICT=1`.

**A3. GDPR controller contact and EU/UK representative** (WS4-10)
- a) Email only (`segue@ryandsilva.dev`) and rely on the GDPR Art. 27(2) exemption (occasional, low-risk processing)
- b) Email plus a postal address in the policy
- c) Appoint an EU/UK representative (a paid service)
- d) Research ticket
- **Recommend a** - no personal address published, processing is opt-in and anonymous, and c conflicts with free-only tooling.
- **Blocks**: WS4 privacy policy "Who we are" and "Legal bases".

**A4. Retention periods, including the TelemetryDeck mismatch** (WS4-5, WS3-2)
Settled: bug reports 30 days (R24, Sentry free); crash reports 30 days (Sentry Developer plan, WS3 10.1). Open: TelemetryDeck has no deletion schedule (cold storage 7-10 years, double-hashed and anonymous), against R26's ~13-month target (R26 allows "the vendor's free-tier default"). Also open: board posts, support email.
- a) Accept TelemetryDeck's default and say so plainly in the policy; board posts "until deleted by you or on request"; support email "as long as needed to answer, at most 2 years"
- b) Ask TelemetryDeck support for a shorter retention first, then decide (a or c)
- c) Switch analytics to PostHog Cloud (1-year retention) behind the same port
- d) Research ticket
- **Recommend a** (ask TelemetryDeck in parallel, and tighten the wording if they offer less) - R26 explicitly allows the vendor default, the data is anonymous, and a vendor swap reopens R23.
- **Blocks**: WS4 `site.json` `vendors.*.retention` and the retention table; WS3 4.3 revocation caption.

**A5. Sentry data region** (WS3-7). Cannot be changed after the org is created.
- a) EU (`de.sentry.io`)
- b) US
- **Recommend a** - matches TelemetryDeck and Featurebase hosting, simplest transfer story in the policy.
- **Blocks**: WS3 [RYAN] step 1 (org creation) and everything after WS3 step 5; WS4 vendor location values.

**A6. TelemetryDeck default parameters** (WS3-3)
The SDK adds ~40 default parameters (time zone, screen resolution, accessibility settings...).
- a) Keep the SDK and its defaults (richer dashboards)
- b) Own small ingest client: only the section 5 parameters plus OS/app version and region leave the Mac
- c) Keep the SDK and strip defaults if the pinned SDK allows it (verify first)
- **Recommend b** - keeps the "closed vocabulary" and "coarse country" promises literally true, and the adapter port already isolates it.
- **Blocks**: WS3 step 5 (VendorServices), WS3 10.2/10.3 label, WS4 policy "Usage statistics".

**A7. Analytics event list** (WS3-10)
- a) WS3 section 5 as written
- b) a) plus a romanized-Hindi search hit metric and chord-palette use
- c) Trim (name what you do not care about)
- **Recommend b** - romanized search is a differentiator worth measuring; the closed-vocabulary rules still hold.
- **Blocks**: WS3 step 4 (event emission).

**A8. Coarse Location on the App Privacy label** (WS3-4)
TelemetryDeck derives "country" from the locale region setting, not IP.
- a) Declare Location > Coarse Location anyway
- b) Do not declare it
- **Recommend a** - over-disclosure is safe, under-disclosure is a 5.1 risk.
- **Blocks**: WS3 10.2/10.3, WS5 section 6 entry.

**A9. "Linked to user" for bug-report data** (WS3-5)
- a) Declare Crash, Performance, Other Diagnostic Data, Customer Support, Other User Content and Email as Linked (a report can carry an email)
- b) Drop the in-app email field (replies only through "Email Instead"), keep everything Not Linked
- c) Only Email, Customer Support and Other User Content Linked; diagnostics Not Linked
- **Recommend a** - conservative and honest; the email field is useful for replies.
- **Blocks**: WS3 10.2/10.3 and 8.2 (email field), WS5 section 6.

### 2.2 First run and onboarding

**A10. Consent step: placement, layout and copy** (WS2b-13, WS3-9, R25 follow-up)
WS2b specced one question ("Share Usage Data" / "Don't Share", choosing closes the sheet). WS3 specs the R25-compliant layout: two rows ("Share usage analytics": Don't Share / Share; "Send crash reports": Don't Send / Send), each row equal weight, Continue enabled once both are answered, policy link.
- a) WS3's `ConsentChoiceView` as the last page of the Welcome flow on a new install; WS3's standalone `ConsentSheet` for upgraders; WS3 labels and copy
- b) Always the standalone sheet, outside the Welcome flow
- c) Consent as the first page, before the library step (what WS5's review notes describe)
- **Recommend a** - one guided flow for new users, reviewers see the library first, and upgraders get the same view without the Welcome steps.
- **Blocks**: WS2b step 4, WS3 step 3, WS4 home and privacy copy, WS5 review notes (4.6).

**A11. Re-enabling crash reports in the same session** (WS3-8)
If the pinned Sentry SDK cannot restart after `close()`:
- a) Accept "Crash reporting starts next time you open Segue" as the caption
- b) Require in-session restart (pin a version that supports it, or do our own restart workaround)
- **Recommend a** - rare edge case, the caption is truthful.
- **Blocks**: WS3 step 5 (6.4).

**A12. Review prompt threshold and extra gates** (WS2b-1, WS5-12; R20 asks to confirm)
- a) After the 1st completed gig, once per app version, plus the OS cap (R20 as ruled)
- b) After the 3rd completed gig
- c) a) plus research 08's gates (at least 14 days since install and 14 days between prompts)
- **Recommend a** - the end of a real gig is the strongest positive moment; the OS already caps prompts at 3 a year.
- **Blocks**: WS2b step 8, WS5 14.3 check.

**A13. Welcome-songs checkbox default and "once per install"** (WS2b-4)
- a) On for an empty library, off when the folder already has songs; automatic seeding once per install, later only via "Add Welcome Songs" (as specced)
- b) Always on
- c) Always off (opt in)
- **Recommend a** - never surprises someone who points Segue at a real library.
- **Blocks**: WS2b step 4.

**A14. Approve the Welcome songs** (WS2b-12)
Four original songs in WS2b Appendix A (one romanized Hindi), artist "Segue Originals", demo setlist "Welcome Set".
- a) Approve as written (after your title search per WS2b section 10)
- b) Approve with edits (name them)
- c) Add a fifth song (R19 allows 3-5)
- **Recommend a** - four songs already cover every showcase feature; run the title search first.
- **Blocks**: WS2b step 2; WS5 screenshots, preview video and review notes (titles).

**A15. "Remove Welcome Songs" and edited songs** (WS2b-22)
- a) Keep edited Welcome songs and list them in the dialog (as specced)
- b) Offer to trash edited ones too (second checkbox)
- **Recommend a** - an edited song is the user's work now.
- **Blocks**: WS2b step 5.

**A16. What's New behaviour** (WS2b-14; ties to I-2, I-3)
- a) Bundled `changelog.json` only (never fetched); the sheet shows for a release only when its `showInApp` flag is true (author decides, WS4 schema)
- b) Bundled only; the sheet shows automatically when a release in range has a `new` or `improved` item (WS2b rule)
- c) Bundled plus a remote refresh from `/changelog.json`
- **Recommend a** - no network call (the policy and FAQ stay simple), and the author explicitly decides which releases deserve a sheet.
- **Blocks**: WS2b step 7, WS4 6.2 and the privacy/FAQ text, WS2a `SegueLinks.changelogFeed`.

**A17. Settings > Data reset scope** (WS2b-8)
- a) "Reset All Settings..." as proposed in WS2b 4.6 (keeps the library, files, onboarding, What's New and review counters, shape library, key bindings)
- b) a) plus "Forget Library Folder"
- c) a) plus a full "Reset to first run"
- **Recommend a** - Library > Choose Library Folder already covers b; c is a test tool (`-SegueResetState`).
- **Blocks**: WS2b step 5.

### 2.3 Editing and library behaviour (includes menus and windows)

**A18. New songs under autosave: file naming** (WS2a-1)
- a) Create on first autosave, never rename (a half-typed title becomes `ha.cho`)
- b) Create on first autosave, file name follows `{title}` until that editor closes
- c) Write nothing until Done/navigation; keep a crash-recovery draft in Application Support
- **Recommend b** - readable file names without losing a crash.
- **Blocks**: WS2a step 4.

**A19. Autosave conflict UX** (WS2a-12)
- a) Inline conflict bar in the editor, refresh on app activation, silent reload of a clean editor on external change
- b) Keep today's modal alert, no activation refresh
- c) Inline bar, no activation refresh
- **Recommend a** - a modal on every autosave conflict is disruptive; reloading on activation is standard Mac behaviour (TextEdit).
- **Blocks**: WS2a step 4.

**A20. Cmd-S feedback** (WS2a-13)
- a) Transient "All changes saved"
- b) Silent flush
- c) Nothing (a literal no-op)
- **Recommend a** - R17 says "confirming".
- **Blocks**: WS2a step 4.

**A21. Editor controls** (WS2a-14)
- a) A single Done; no "Revert to Opened"
- b) Done plus "Revert to Opened"
- c) Keep Cancel / Save
- **Recommend a** - undo covers the session, the Trash and Time Machine cover the rest.
- **Blocks**: WS2a step 4.

**A22. Dirty-state indicator** (WS2a-16)
- a) "Saved / Saving... / Not saved" plus the window's edited dot
- b) Keep "Edited" during the debounce
- **Recommend a** - an honest state.
- **Blocks**: WS2a step 4.

**A23. Delete confirmations now that deletes go to the Trash and can be undone** (WS2a-3)
- a) Keep a confirmation for songs, setlists and gigs
- b) No confirmation for any
- c) Confirm only when a song is used by setlists
- **Recommend c** - matches Finder's Move to Trash; asks only when there is a hidden consequence.
- **Blocks**: WS2a step 5.

**A24. Import file types** (WS2a-5; ties to I-9)
Today's default: `.cho`, `.chopro`, `.pro`, `.txt` (chords-over-lyrics imported as-is).
- a) Default list
- b) Default list plus `.chordpro`
- c) b) plus `.crd`
- d) b) plus a minimal chords-over-lyrics converter pulled forward from phase 3
- **Recommend b** - `.chordpro` is a common ChordPro extension and WS2b's UTType already claims it; `.crd` is mostly chords-over-lyrics and belongs with phase 3.
- **Blocks**: WS2a step 2; WS2b UTType tags; WS5 review notes.

**A25. Import edge rules (four small defaults, asked together)** (WS2a-7, -8, -10, -11)
Defaults: no `{title}` -> title from the file name, content untouched; byte-identical duplicate -> skipped with a reason; folder drop -> recurse, 500-file cap; drop targets -> library list and detail pane only.
- a) Accept all four defaults
- b) a), but insert `{title: <file name>}` into untitled copies
- c) a), plus drops on the setlist builder's library column (import and insert into the set)
- d) Other edits (name them)
- **Recommend a** - conservative, file contents untouched.
- **Blocks**: WS2a steps 2 and 6.

**A26. What "restore selected song/section" means** (WS2a-2)
- a) Sidebar destination + selected song + selected gig; the editor never reopens
- b) a) plus the song's Verse/Chorus scroll position
- c) a) plus reopening an open editor
- **Recommend a** - autosave means nothing is lost, and the view restores where you were.
- **Blocks**: WS2a step 10.

**A27. Undo scope** (WS2a-27)
- a) Setlist builder, deletes and import (as specced)
- b) a) plus song metadata edits (tags, proficiency, notes/cues)
- **Recommend b** - Cmd-Z doing nothing on a metadata edit feels broken; it uses the same snapshot pattern.
- **Blocks**: WS2a step 8.

**A28. Show in Finder for gig-log entries** (WS2a-30)
- a) Include (reveals `shows/<ulid>.show.json`)
- b) Only songs, setlists and the library
- **Recommend a** - files are canonical; consistent everywhere.
- **Blocks**: WS2a step 5.

**A29. Import after phase 3's review sheet lands** (WS2a-31). Blocks nothing in 0.5.
- a) Direct import stays for files that are already ChordPro; only conversions go through review
- b) Every import goes through the review sheet
- **Recommend a** - review where judgement is needed, not on valid files.
- **Blocks**: the phase 3 spec only.

**A30. `.cho` file type and default-app claim** (WS2b-6)
- a) Exported type `dev.ryandsilva.segue.chordpro`, rank Owner (Segue becomes the default app)
- b) Exported type, rank Alternate (Open With only)
- c) Imported type, rank Default (default only if nothing else owns `.cho`)
- **Recommend c** - Segue does not own ChordPro (research 08); this still makes Segue the default on most Macs without fighting other ChordPro apps.
- **Blocks**: WS2b step 10.

**A31. Open With for a file outside the library** (WS2b-7)
- a) Copy it in through WS2a's import (as specced)
- b) Open it read-only in place
- c) Ask each time
- **Recommend a** - the library folder is the canonical home.
- **Blocks**: WS2b step 10.

**A32. Main window scene and reopen item** (WS2a-21)
- a) A single `Window`; Window menu item "Segue Library", Cmd-0
- b) A single `Window`; item named "Library", Cmd-0
- c) Keep `WindowGroup` plus a custom reopen command
- **Recommend a** - one main window prevents duplicate-editor bugs, and it is the reviewer's known Guideline 4 trap.
- **Blocks**: WS2a step 7; WS2b 4.1/4.7 assumptions (I-11).

**A33. Setlist menu layout** (WS2a-22, -23, -24)
- a) Defaults: New Setlist in the Setlist menu only; Start Show Cmd-Return, Rehearse Opt-Cmd-Return, disabled outside a builder; no extra submenu
- b) a) plus "Add Selected Song to Setlist >" submenu
- c) b) plus a "Start Show > <setlists>" submenu outside a builder
- d) a) plus New Setlist also in File
- **Recommend b** - adding a song without dragging is a core keyboard and VoiceOver path, which the accessibility claims need.
- **Blocks**: WS2a step 7; WS2b 4.9 VoiceOver audit.

**A34. Acknowledgements placement** (WS2a-17)
- a) Move to Help; the About panel links the web `/acknowledgements`
- b) a), but register a `segue://` scheme so the About link opens the in-app window
- c) Custom About window with an Acknowledgements button
- **Recommend a** - standard panel, HIG placement. If A36 picks x-callback-url, a `segue` scheme exists anyway and b becomes free.
- **Blocks**: WS2a step 7.
- *(Superseded 2026-10-18, walkthrough feedback: the app shows no third-party notices; no Acknowledgements window or Help item, no credits in About. THIRD_PARTY_NOTICES.md and the licence texts ship in the bundle's Resources, `make verify-appstore` checks them, and the web `/acknowledgements` is linked from /privacy, /terms and the footer.)*

**A35. "Rate Segue on the App Store" in Help** (WS2a-19)
- a) Add it (`?action=write-review`), shown once the Apple ID is known
- b) Not in 0.5
- **Recommend a** - Apple's guidance pairs `requestReview` with a persistent user-initiated link.
- **Blocks**: WS2a step 7 (item slot), WS5 (Apple ID).

### 2.4 Live and Shortcuts

**A36. How the pre-show "Focus" row becomes ticked** (WS1-1, R18)
Under separate research: `research/09-shortcut-confirmation.md` (not yet written).
- a) x-callback-url `x-success` (reportedly broken since macOS 26.5; needs a probe on 26.6.2/27)
- b) A Segue App Intent the user adds as the last action of their Shortcut
- c) A manual "Done" tick
- d) b + c
- **Recommend: wait for research 09.** Provisional preference d - truthful, sandbox-safe, with a manual fallback.
- **Blocks**: WS1 step 6 and its E2E (6.3); WS2b `GigModeTip` text; WS5 shot 8 and review notes.

**A37. Focus row when Gig Mode Shortcuts are off** (WS1-15)
- a) Show it unticked with "Set up in Settings > Live" on every gig (dismissable)
- b) Hide it until Shortcuts are configured
- c) Show it for the first gig only, then hide
- **Recommend b** - the checklist should list only actionable rows; WS2b's `GigModeTip` handles discovery.
- **Blocks**: WS1 step 5; WS5 shot 8 content.

**A38. Installs that stored the old "Gig Mode On/Off" names** (WS1-2)
Only your own installs (and the TestFlight build that inherits your container) have them.
- a) Leave them
- b) Clear stored names equal to the old defaults once
- **Recommend a** - you likely have those Shortcuts, and clearing them would silently switch off a working setup.
- **Blocks**: WS1 step 5.

**A39. `?` keyboard overlay on stage** (WS2a-25)
- a) Other stage keys keep working and close it; `?` is rebindable through `bindings.json`
- b) Modal until Esc or `?`
- **Recommend a** - the stage must never trap the performer.
- **Blocks**: WS2a step 9.

**A40. On-stage "Press ? for all keys" hint** (WS2b-19)
- a) No stage hint; the Start Show tip in the main window says it, and WS2a's status line ends "? keys"
- b) a) plus a one-time hint on the first show
- **Recommend a** - nothing new on stage during a gig.
- **Blocks**: WS2b step 9.

### 2.5 Design and visual review

**A41. Design directions before building** (WS2b-11, WS4-15)
- a) Yes: 2-3 directions on the canvas for the Welcome sheet, What's New sheet and `.cho` document icon (WS2b) and for the home page (WS4's Stage / Sheet / Setlist)
- b) Build both from the specs inside `brand.md`
- c) Directions for the website and document icon only
- **Recommend a** - your standing rule for new UI.
- **Blocks**: WS2b steps 4, 7 and 10 (icon); WS4 page build.

**A42. Settings Appearance pane** (WS2b-2)
- a) Drop it (follow the system; four panes)
- b) Keep "Match System / Light / Dark" for the main window
- **Recommend a** - HIG says respect the system appearance, and nothing else would live there.
- **Blocks**: WS2b step 5.

**A43. Control borders at 3:1** (WS2b-9)
- a) Only under Increase Contrast (brand look unchanged)
- b) Also in the default look (visibly heavier borders)
- **Recommend a**, provided Apple's "Sufficient Contrast" criteria accept the Increase Contrast route (WS2b verifies the wording first; if not, b).
- **Blocks**: WS2b step 1; the Sufficient Contrast claim (WS5 section 7).

**A44. Progress-dot and indicator colours** (WS2b-10)
- a) New `indicatorOff` token (#8A8A92 / #66676E) and `played` dark #8E8E96
- b) Shape-based fix (pending as outlined rings)
- c) Both
- **Recommend a**, shown to you as a before/after render first - smallest brand change that reaches 3:1.
- **Blocks**: WS2b step 1, `brand.md`.

**A45. Main-window text scaling** (WS2b-18, second half)
- a) None in 0.5 (the stage has its own sizes)
- b) View > Bigger / Smaller text for the song preview
- **Recommend a** - out of R15/R16 scope.
- **Blocks**: nothing unless b.

### 2.6 Store listing

**A46. Confirm R8: English (U.S.) only** (WS5-1)
India's storefront defaults to English (U.K.).
- a) en-US only (R8 as ruled)
- b) Add en-GB with the India keyword set (`bhajan` in)
- c) Research ticket
- **Recommend a** to keep R8, unless you want Indian search reach now; then b, which reuses the screenshots.
- **Blocks**: WS5 store metadata (section 4.5, deliver layout).

**A47. Territories** (WS5-11)
- a) All 175 storefronts
- b) All except China mainland (needs an ICP filing number)
- c) A smaller subset
- **Recommend b** - an individual U.S. developer cannot easily get an ICP filing; everything else is free to include (R4 covers the EU).
- **Blocks**: WS5 pricing and availability.

**A48. Screenshot library content** (WS5-3)
- a) Welcome library only
- b) Plus 6-10 screenshot-only original songs (titles and chords, never shipped)
- c) Expand the shipped Welcome library
- **Recommend b** - a realistic builder and library without padding the first-run content; you approve the titles.
- **Blocks**: WS5 section 8.4 capture; I-4 (flag design).

**A49. Screenshot appearance per slot** (WS5-4)
- a) 5 dark, 3 light (WS5 8.4 defaults)
- b) All dark
- c) All light except stage
- **Recommend a** - dark-first, with light showing off the paper look.
- **Blocks**: WS5 `store/screenshots.json`.

**A50. Keywords** (WS5-5)
- a) The 4.5 set (keeps `band`)
- b) The alternate with `hindi` and `prompter`, no `band`
- c) Other swaps (`autoscroll`, `repertoire`, `open mic`)
- **Recommend b** - `band` implies band sharing Segue does not have; `hindi` and `prompter` match real use.
- **Blocks**: WS5 `keywords.txt`.

**A51. Release mode** (WS5-7)
- a) Manual release after approval
- b) Automatic on approval
- c) A scheduled date
- **Recommend a** - lets you flip the website from "Coming soon" to the badge at the same moment.
- **Blocks**: WS5 14.5.

### 2.7 Website

**A52. App Store badge count** (WS4-1)
- a) One badge in the hero, a text link in the final call to action
- b) Badges in both places
- **Recommend a** - strict reading of Apple's one-badge-per-layout rule.
- **Blocks**: WS4 home page.

**A53. Hero art** (WS4-2)
- a) Frameless window screenshot with the macOS shadow, stills only
- b) Apple's MacBook Pro bezel (licence to read first)
- c) a) plus a short muted loop from the preview video
- **Recommend a** - no licence question, sharp at any width.
- **Blocks**: WS4 home page.

**A54. Website analytics** (WS4-3)
- a) None (App Store campaign tokens only)
- b) Cloudflare Web Analytics (cookieless; a script and a policy paragraph)
- **Recommend a** - keeps "no tracking" on the site literally true.
- **Blocks**: WS4 `_headers`, privacy "This website".

**A55. Publish the site before the app is live** (WS4-7)
- a) Yes, with "Coming soon to the Mac App Store" and no badge
- b) Wait for approval
- **Recommend a** - App Store Connect needs live privacy and support URLs before submission.
- **Blocks**: WS4 [RYAN] R-1/R-3; WS5 preconditions.

**A56. Maker note on the home page** (WS4-8)
- a) Include as drafted, signed "Ryan"
- b) Include with your edits
- c) Omit
- **Recommend b** - it should be in your own words.
- **Blocks**: WS4 home page copy.

**A57. Support reply-time promise** (WS4-11)
- a) "Usually within a few days"
- b) "Within a week"
- c) No promise
- **Recommend a** - honest for a single operator, and reassuring.
- **Blocks**: WS4 `/support`.

### 2.8 Build and toolchain

**A58. Xcode version for 0.5** (WS1-9)
Xcode 27.1 (27A9275) replaced 26.6; its licence is not yet accepted.
- a) Ship from 27.1 (macOS 27 SDK; deployment target stays 26.0)
- b) Reinstall 26.6 for the release
- **Recommend a**, provided 27.1 is a release (not beta) build - one toolchain, no downgrade, and Apple will require the new SDK soon. Re-verify the ExportOptions keys, `altool` flags and `xcresulttool export` under 27.1.
- **Blocks**: WS1 [RYAN] step 0 and every build step; WS5 8.5 and 9.3 tool checks.

**A59. Architectures** (WS1-10)
- a) Universal (`arm64 x86_64`; reaches Intel Macs on macOS 26, never tested on Intel)
- b) arm64 only
- **Recommend b** - nothing is tested on Intel, and macOS 26 is Intel's last release.
- **Blocks**: WS1 verify-archive check 11.

**A60. Your existing `dev.ryandsilva.segue` container** (WS1-3)
After the bundle-ID split it belongs to the App Store/TestFlight flavor.
- a) Leave it (the TestFlight run is not a clean first run)
- b) Move it aside before installing TestFlight
- c) Copy `shape-library.json` / `bindings.json` into the new Personal container by hand
- d) b + c
- **Recommend d** - the R6 TestFlight run then walks the reviewer's first-run path, and your daily build keeps its shapes and bindings.
- **Blocks**: WS1 step 1 commit note and [RYAN] step 10.

**A61. Services in the Personal build (also `network.client` on Personal)** (WS1-5, WS3-1)
- a) Yes: Personal links the vendor module, gets `network.client` (Release and Debug entitlements), the same consent UI, Sentry environment `personal`, a separate TelemetryDeck app
- b) Crash and bug reports only, no analytics in Personal
- c) None: Null adapters, no entitlement, bug report falls back to email
- **Recommend a** - your daily build exercises the real crash and consent paths before any TestFlight build, and a separate TelemetryDeck app keeps your own use out of product data.
- **Blocks**: WS1 step 1 (entitlements, verify-appstore assertion); WS3 step 10.

**A62. Upload Segue's source with dSYMs** (WS3-11, `--include-sources`)
- a) Keep (Sentry shows code context)
- b) Drop (stack traces only)
- **Recommend a** - your own Sentry account, App Store builds only, and it makes crash reports much faster to act on.
- **Blocks**: WS3 step 9.

---

## 3. (B) ENGINEERING DEFAULTS

Taken as stated unless Ryan objects.

| # | Source | Question | Default | Reason |
|---|---|---|---|---|
| B-1 | WS1-6 (residual after R12) | Where manual signing lives | Archive with automatic signing; sign manually at export (`signingStyle manual`, Apple Distribution, Mac Installer Distribution, `Segue MAS`) | The uploaded `.pkg` is identically signed (verify-archive checks it) while `make check` and local Release-AppStore runs keep working without distribution certs |
| B-2 | WS1-4 | Both flavors open one library at once | Advisory lock file in the library's `.segue/`, held by whichever flavor opened it; the other shows the existing "already open" message | Two writers on one index and sidecars is a real corruption risk on your Mac |
| B-3 | WS1-7 | `Segue.icns` lacks 512 / 512@2x | Generate every size from `scripts/gen-icon.swift` and keep verify-archive check 10 strict | Same artwork, deterministic, no dependency on validator leniency |
| B-4 | WS1-8 | Privacy-manifest reasons | Ship `CA92.1` + `3B52.1`; WS3 adds `35F9.1` only if the Sentry/TelemetryDeck symbols need it (verify-archive check 9 decides) | Declarations follow the binary's actual symbols |
| B-5 | WS1-11 | Release bookkeeping | `make bump` makes a signed commit of `Version.xcconfig`; `make upload` creates a signed local tag `v0.5+<build>`; never push | Every uploaded build is traceable to a commit |
| B-6 | WS1-13 | SegueUI resource bundle Info.plist placeholders | Fix in WS1 with the A1 copyright and a real identifier | Shipping hygiene |
| B-7 | WS1-14 | Test hooks in Release | Wrap `RecordingShortcutRunner`, the launch-option parser and every flag string in `#if DEBUG`; verify-appstore greps for them | WS5 8.2 requires it anyway (I-12) |
| B-8 | WS1-16 | API key role | App Manager | Verified to upload; Developer-role keys are unverified |
| B-9 | WS1-17 | First upload timing | Upload build 1 as soon as `make validate` passes, internal TestFlight only; install it only after A60 is done | Proves signing, processing and the API key early; build numbers are free |
| B-10 | WS2a-4 | Delete a song whose editor is open | Flush autosave first, then trash | The trashed file holds the latest text; nothing lost |
| B-11 | WS2a-6 | Non-UTF-8 imports | Convert to UTF-8 on import and say so in the summary | The original stays untouched; the copy is editable |
| B-12 | WS2a-9 | `.segue.json` next to an imported file | Copy its metadata with a fresh ID | No ID collisions between libraries |
| B-13 | WS2a-15 | Autosave timing | One `AutosavePolicy` constant: 1.0 s idle, 5 s max, used by the editor and gig details | One rule, not two |
| B-14 | WS2a-18 | Help hooks before WS2b/WS3 land | Fallbacks (changelog page, support email, feedback page) | Development-time only; replaced before any release |
| B-15 | WS2a-26 | Trash in E2E | `-SegueTrashPath` test folder, plus the manual real-Trash check in WS2a 6.4 | Keeps your Trash clean; step 0 spike confirms |
| B-16 | WS2a-28 | Setlist undo vs external edits | Reload setlists on Cmd-R and app activation; clear a setlist's undo actions if its file changed on disk | Undo must never overwrite someone else's edit |
| B-17 | WS2a-32 | Help "Getting Started" slot | WS2a reserves the slot; WS2b fills it as "Welcome to Segue..." | See I-5 |
| B-18 | WS2b-5 | Welcome content in Personal too | Yes, keep it in the SegueUI bundle | Harmless, and `swift test` loads it with `Bundle.module` |
| B-19 | WS2b-18 (first half) | Larger Text label | No claim; re-check in App Store Connect | Apple does not offer it on Mac (research 03) |
| B-20 | WS2b-15 | Quick Look rendering | View-based preview reusing the app's renderer and fonts | Matches the app pixel for pixel; size is not a concern |
| B-21 | WS2b-16 | WS2b sequencing | See section 5 | |
| B-22 | WS2b-17 | Consent contract with WS3 | WS3's `ConsentStore` wins | See I-1 |
| B-23 | WS2b-20 | Archive scope | Include `songs/`, `setlists/`, `shows/`, `timings/`; exclude `.segue/`; no restore in 0.5 | R16 asks only for export; the index can be rebuilt |
| B-24 | WS3-6 | Bug-report transport | Post the previewed envelope ourselves | Only way to send exactly what was previewed (R22) and to detect offline |
| B-25 | WS3-12 | TestFlight builds in analytics | Mark them as TelemetryDeck test data | Keeps product charts clean |
| B-26 | WS4-9 | App's bundled changelog path | App bundles the generated `website/changelog.json`; drop WS4's separate bundled-copy output | See I-2 |
| B-27 | WS4-12 | Public preview deployments | Turn off previews for non-`main` branches | Avoids public pages with placeholders; nothing needs them |
| B-28 | WS4-13 | DMARC | Add `v=DMARC1; p=none` with no report address ([RYAN] DNS step) | Better deliverability for replies, no report mail |
| B-29 | WS4-14 | Pre-push guard | Versioned hook via `core.hooksPath`, runs `make site-check STRICT=1` when `website/` or `content/` changed | A push to `main` publishes, so placeholders must be caught before it |
| B-30 | WS5-6 | Metadata upload path | fastlane `deliver` via mise for text and screenshots; the rest by hand | Free, local, reproducible from git |
| B-31 | WS5-8 | Review attachment video | Yes, a 60-90 s cut from the preview pipeline | Costs little once the pipeline exists; lowers review risk |
| B-32 | WS5-9 | Accessibility URL | Leave empty for 0.5 | No `/help/accessibility` page in R29 |
| B-33 | WS5-10, WS5-13 | SKU; preview capture method | SKU `segue-macos`; scripted XCUITest + `screencapture`, manual QuickTime as fallback | SKU is never shown to customers; scripted capture is repeatable |

(B-33 covers two source questions.)

---

## 4. Cross-spec inconsistencies

Each needs the proposed resolution applied to the named spec(s) before implementation.

**I-1. Who owns consent state** (WS2b vs WS3; WS1 4 "out of scope" table)
WS2b defines `PrivacySettingsStore` (SegueUI `Settings/`, keys `privacy.analytics` and `privacy.crashReports`, each `{choice, decidedAt, via, promptVersion}`) and its own `PrivacySettingsView.swift`, and calls itself "the only writer". WS3 defines `ConsentStore` (SegueUI `Services/`, one key `privacy.consent` with a `version` that forces a re-ask) plus `PrivacySettingsView`, `ConsentChoiceView`, `ConsentSheet`, and wires it to `ServicesHub.apply`. WS2b also has its own upgrader "consent-only" flow; WS3 handles upgraders with `ConsentSheet`.
**Resolution**: WS3's `ConsentStore` is the single store and writer, and WS3 owns the Privacy pane content. WS2b drops `PrivacySettingsStore`, its Privacy view and its upgrader consent flow; step 3 of the Welcome sheet embeds `ConsentChoiceView`; resume logic uses `ConsentStore.needsPrompt`; WS2b exposes `isPresentingWelcome`. WS2b's `via` field becomes the `source` parameter of WS3's `Privacy.analyticsEnabled` event. WS1's table is right as written.

**I-2. `changelog.json` location and schema** (WS2b 4.3 vs WS4 6)
Location: WS2b treats `website/changelog.json` as the hand-edited original and bundles it; WS4 makes `content/changelog.json` the original, generates `website/changelog.json`, and also writes a second "bundled copy" to `app.bundledChangelogPath`.
Schema: WS2b has `minimumOS` and absolute `learnMore` URLs, title 40 characters or fewer, text 90 or fewer, sheet trigger "has new/improved"; WS4 has `summary`, `showInApp`, `draft` and site-relative `help`, title 60 or fewer, text 140 or fewer, and its generator rejects unknown keys (so WS2b's fields would fail). Versions: WS2b `0.5.0`, WS4 `0.5` (WS1 sets `MARKETING_VERSION = 0.5`).
**Resolution**: WS4's model. The original is `content/changelog.json`; the generator writes `website/changelog.json`; the app bundles that generated file through `Project.swift` resources (no second output, remove `bundledChangelogPath`). Schema 1 = WS4's fields; the app reads `help` and prefixes `SegueLinks.site`; drop `minimumOS` and `learnMore`; limits: title 60 or fewer, text 120 or fewer (WS2b's sheet wraps to two lines), enforced by both `gen-site --check` and `WhatsNewTests`; versions written as `MARKETING_VERSION` (`0.5`). The sheet trigger follows A16.

**I-3. Remote changelog fetch** (WS2b vs WS2a vs WS4)
WS2b: the app never fetches. WS2a: `SegueLinks.changelogFeed` "used by WS2b What's New". WS4: the sitemap says "What's New (remote refresh)", the privacy policy says "The Segue app may download its release notes", and the support FAQ lists "fetching release notes" as network use.
**Resolution** (if A16 = a or b): delete `changelogFeed` from WS2a; remove the policy sentence and the FAQ mention in WS4; WS5 review notes already omit it.

**I-4. Screenshot seeding flags** (WS2b 4.2 vs WS5 8.2)
WS2b: `-SegueSeedWelcome YES` seeds `Application Support/<bundle id>/ScreenshotLibrary/` without wiping it; it is idempotent, and first-run UI is controlled by `-SegueOnboarding done` and `-SegueTips hide`. WS5: `-SegueScreenshotLibrary YES` wipes and seeds `Application Support/Segue-Screenshots/Library` on every launch, implies `-SegueTestDefaults`, plus `-SegueSuppressFirstRunUI` (consent recorded "No", no What's New, tips or review prompt).
**Resolution**: WS2b owns the seeder and `-SegueSeedWelcome`. WS5's `-SegueScreenshotLibrary YES` is a composite flag defined in `LaunchOptions` that wipes one fixed container folder `Application Support/Segue-Screenshots/Library`, then applies `-SegueSeedWelcome YES` (plus A48's extra songs), `-SegueOnboarding done`, `-SegueTips hide`, consent declined through WS3's `ConsentStore`, and no What's New or review prompt. WS2b's no-path branch of `-SegueSeedWelcome` uses that same folder constant. All under `#if DEBUG` (B-7).

**I-5. Help menu items and names** (WS2a 3.5.6 vs WS2b vs WS3 vs WS4 vs WS5)
WS2a: Segue Help, Keyboard Shortcuts, What's New in Segue, Report a Problem..., Request a Feature..., Privacy Policy, Terms of Use, Acknowledgements; it asks whether to add "Getting Started" (WS2a-32) and "Rate Segue" (WS2a-19). WS2b adds "Welcome to Segue..." and "What's New in Segue" by editing `SegueCommands` directly. WS3 replaces `AppHooks.reportProblem` / `requestFeature` (agrees with WS2a). WS4 calls the item "Help > Release Notes" (sitemap and the `/changelog` intro) and maps `/help/keyboard` as the Keyboard Shortcuts fallback. WS5's review notes say "Help > Report a Bug".
**Resolution**: one canonical list owned by WS2a: Segue Help · Keyboard Shortcuts · Welcome to Segue... · What's New in Segue · separator · Report a Problem... · Request a Feature... · (Rate Segue on the App Store, per A35) · separator · Privacy Policy · Terms of Use · Acknowledgements (per A34). WS2a adds `AppHooks.showWelcome` (and an `exportArchive` hook for File) so WS2b fills closures instead of editing `SegueCommands`. WS4 changes "Release Notes" to "What's New in Segue" (the sheet's "All Release Notes" link stays). WS5 notes say "Help > Report a Problem...".

**I-6. Settings panes and their contents** (WS2b 4.6 vs WS3 4.3 vs WS2a vs WS4 vs WS1)
WS2b: General, Appearance (A42), Live, Privacy, Data. "Show in Finder" appears in General and again as "Show Library in Finder" in Data. WS2a says WS2b owns Settings > General "Show library in Finder". WS3 adds a Privacy tab "beside Live now", with content WS3 owns; it hides the toggles in builds without vendor config. WS2b's Privacy toggles are labelled "Share anonymous usage data" / "Send crash reports automatically"; WS3's are "Share usage analytics" / "Send crash reports". WS4 says Settings > Privacy links `/privacy` and `/terms`. WS1 rewrites the Live pane text in `LiveSettingsView.swift`, the same file WS2b turns into the TabView host.
**Resolution**: panes General, Live, Privacy, Data (plus Appearance only if A42 = b). "Show Library in Finder" only in General. Privacy pane = WS3's view as-is (WS3 labels; links to Privacy Policy and `/privacy#usage-statistics`; no Terms link, since R7 scopes the terms to the site) and WS4's goal text is corrected. WS2b puts the TabView in a new `SegueSettingsView.swift` and leaves `LiveSettingsView.swift` to WS1's text change. WS3 adds its tab to whichever host exists when it lands.

**I-7. First-run order and copy** (WS2b 4.1 vs WS5 4.6 vs WS4 9.2)
WS2b: library, then Welcome songs (checkbox), then consent. WS5 review notes: consent, then library, then automatic seeding with no checkbox mentioned. WS4 home copy: "it asks once, both answers are equal", implying one question.
**Resolution**: WS2b's order (as adjusted by A10); WS5 rewrites the notes after WS2b lands (it already plans to); WS4 home copy says Segue asks two separate questions.

**I-8. Vendor facts still TBD or contradicting R23-R25** (WS4 4 and 9.4, WS5 6)
WS4 cites R24 as "private GitHub issues if the vendor supports it", carries a `githubIssues` variant and lists GitHub in the vendor table; WS5's vendor parameters are all TBD, and its `BUGREPORT` row says "GitHub issue via vendor if possible". R23 names TelemetryDeck, Sentry and Featurebase; R24 rules out any GitHub bridge.
**Resolution**: fill WS4 `site.json` and WS5's parameters from WS3 10.1; delete `githubIssues` (field, variant blocks, vendor-table row) and the GitHub sentence in the policy; bug-report and crash retention 30 days; analytics retention per A4.

**I-9. App Privacy label rows** (WS5 6 vs WS3 10.2)
WS5 declares bug-report types Not Linked unless an email field exists (TBD), with Crash Data purposes "App Functionality, Analytics". WS3 declares them Linked (A9; the email field exists) with purpose App Functionality only, and adds Device ID for Sentry's installation ID (R25: Not Linked).
**Resolution**: WS3 10.2 is canonical for the label and the manifest (10.3); WS5 section 6 copies it; the WS4 policy is written to match. Diff all three before publishing.

**I-10. Accepted import extensions** (WS2a 3.2 vs WS2b 4.7 vs WS5 4.6)
WS2a accepts `.cho .chopro .pro .txt`; WS2b assumes WS2a imports `.chordpro` / `.chopro` and declares UTType tags `cho, chordpro, chopro` (no `.pro`); WS5's notes say ".cho or .txt".
**Resolution**: one extension list in SegueCore (from A24) used by import, the UTType declaration and the Open With routing; WS5 notes list it. Keep `.pro` out of the UTType tags (too generic to claim) but accept it in import.

**I-11. Main window scene** (WS2a 3.5.5 vs WS2b 4.1 and 4.7)
WS2a switches to a single `Window`; WS2b says "the app is a `WindowGroup`" and handles "more than one main window".
**Resolution**: WS2b follows A32 (single `Window`) and drops the multi-window case.

**I-12. Test hooks in the Release binary** (WS1-14 vs WS5 8.2)
WS1 treats wrapping launch options in `#if DEBUG` as optional; WS5 requires it and adds a verify-appstore grep.
**Resolution**: WS1 does it (B-7); WS5 adds only its own flag strings to the grep list.

**I-13. Editor accessibility help (F5)** (WS1 4.8b vs WS2b 4.9.1)
WS1 deletes the `setAccessibilityHelp(...)` calls; WS2b gates them on `UITesting.isActive`.
**Resolution**: WS1's delete wins (it lands first); WS2b already says skip if it has landed.

**I-14. Quick Look extension signing** (WS2b 4.7 vs WS1 3 and 4.5)
WS2b needs App IDs and Mac App Store profiles for `dev.ryandsilva.segue.quicklook` (and a Personal one). WS1's [RYAN] step 6 creates only the app profile, and `ExportOptions-AppStore.plist` `provisioningProfiles` lists only `dev.ryandsilva.segue`.
**Resolution**: WS1 [RYAN] step 6 also creates `dev.ryandsilva.segue.quicklook` with profile "Segue MAS QuickLook"; ExportOptions maps both; verify-archive checks the embedded appex signature and profile.

**I-15. `network.client` on Personal** (WS1 4.2/4.7 vs WS3 9)
WS1 adds it to the App Store flavor only and makes verify-appstore assert that Personal lacks it; WS3 recommends adding it to both Personal entitlements files.
**Resolution**: per A61. If a, WS1 step 1 adds it to both flavors and inverts the assertion, so WS3 does not have to edit WS1's script.

**I-16. Help URL slugs and anchors** (WS2a 3.1 vs WS4 2 vs WS2b 4.3 vs WS5-9)
WS2a's example deep link is `help/keyboard-shortcuts`; WS4 publishes `/help/keyboard`. WS2b's changelog example links `/help#trash`, which is not in WS4's anchor contract. WS5 refers to `/help/accessibility`, which WS4 does not plan.
**Resolution**: WS4's URL and anchor table is the contract. Add `/help#trash` (or `/help/library#trash`) to it; `SegueLinks` constants use only listed paths; WS4's link checker validates the `help` fields in `changelog.json`; no accessibility page in 0.5 (B-32).

**I-17. Toolchain references** (WS5 8.5 and 9.3, WS1 4.5 vs installed Xcode 27.1)
WS5 verified `xcresulttool export` under Xcode 26.6 and mentions "Xcode 26's built-in test recording"; WS1 checked ExportOptions keys against 26.6.
**Resolution**: after A58, re-verify these commands under the chosen Xcode and update the spec text.

---

## 5. Proposed implementation order

Principle: WS2a, WS2b and WS3 all edit the app shell (`AppModel`, `SegueRootView`/`SegueCommands`, `SegueApp.swift`, `LaunchOptions.swift`, `Project.swift`, the Settings host), so they run **one after another on those files**. Their file-disjoint parts run in parallel. WS4 is almost fully disjoint and runs in parallel throughout.

**Phase 0 - decisions and manual setup (Ryan)**
Answer section 2 in batches by theme; record the answers as R30 and later in `decisions.md`; apply section 4's resolutions to the specs. Manual steps that gate later work: accept the Xcode licence (A58), certificates and profiles including the Quick Look one (I-14), Sentry org (region per A5) and TelemetryDeck app(s), App Store Connect API key and app record, Cloudflare/Mailgun/DNS (WS4).

**Phase 1 - baseline (parallel)**
- **WS1 steps 1-5**: bundle-ID split and entitlements (with A61), version xcconfig and Info.plist (A1), privacy manifest, logging and F5, Gig Mode default off with the `.requested`/`.confirmed` split, `#if DEBUG` launch options (B-7). Every other workstream builds on these files, so WS1 goes first.
- **WS4** in full, with placeholders: site generator, pages, changelog pipeline (I-2), checks. One shared file: `scripts/gen-tokens.swift` is also edited by WS2b step 1 (high-contrast variants). Land WS4's CSS output first and rebase WS2b step 1 onto it.
- **WS3 steps 1-2** (envelope spike, services core in a new SegueCore target): new files only.
- **WS2b steps 1-2** (tokens/contrast after A43/A44; Welcome content and core seeding after A14) and the SegueCore half of step 6 (`LibraryArchive`): no app-shell files.

**Phase 2 - WS2a (the app-shell owner)**, steps 0-11, alone on the shell files. In this pass WS2a also reserves `AppHooks.showWelcome`, the export-archive slot in File, and the Help slots from I-5, so later workstreams fill closures instead of editing menus. In parallel: WS3 step 5 (the `SegueVendorServices` package; its `Project.swift` change waits for WS2a to finish) and WS1 steps 7-8 once the certificates exist (signing, release scripts, verify-archive, B-1, B-3).

**Phase 3 - WS3 app integration**, steps 3-4 and 6-9: `ConsentStore` and UI, wiring, event emission at the view-model entry points WS2a just changed, Report a Problem, the privacy manifest and label. **WS2b depends on WS3's `ConsentChoiceView`** (I-1), not the other way round; until WS2b lands, WS3's standalone sheet covers first run.

**Phase 4 - WS2b remainder**, steps 3-12: Welcome flow (with A10 and A41 directions first), Settings host (I-6), export UI, What's New, review prompt, tips, Finder/Quick Look, accessibility pass, `docs/release/accessibility-audit.md`.

**Phase 5 - release gating**
- WS1 step 6 (Shortcut confirmation) as soon as research 09 lands and A36 is answered; it is independent of phases 2-4 apart from `AppModel+Shows.swift`, so schedule it between phases, not during one.
- WS1 steps 9-10: validate. B-9: the first internal upload can happen right after phase 1 plus signing, to prove the pipeline. The feature-complete TestFlight build comes after phase 4.
- WS4 final legal text after WS3's vendor facts (I-8, I-9) and A1-A9; then `STRICT=1` and go live with "Coming soon" (A55), before App Store Connect submission.

**Phase 6 - WS5**
Store text, questionnaires, `store-check` and the compositor can start any time after phase 1. Screenshots and the preview video wait for WS2a and WS2b (UI frozen, pixel pass done) and A48; the App Privacy answers wait for WS3 (I-9); accessibility labels wait for WS2b step 11. Then the runbook: TestFlight on your Mac (after A60), a real gig (R6), submit, manual release (A51), flip the website badge.

Dependency summary:

| Workstream | Depends on |
|---|---|
| WS1 (steps 1-5) | Phase 0 answers A1, A37, A38, A61 |
| WS4 | Nothing to start; WS3 vendor facts and A1-A9 for final legal text |
| WS2a | WS1 steps 1-5 |
| WS3 | WS1 (entitlements, manifest, release.sh), WS2a (`AppHooks`, `SegueLinks`, Help menu) |
| WS2b | WS1, WS2a, WS3 step 3 (consent UI) |
| WS5 | WS2a + WS2b (screenshots, a11y), WS3 (label), WS4 (live URLs), WS1 (upload) |
