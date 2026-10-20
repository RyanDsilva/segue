# WS5 - App Store listing, screenshots, preview video and submission

> *Phase 3 (AI entry & assistant) ships in 0.5 (R61-R128, `docs/release/decisions.md`). P3-9 rewrote the lines that assumed no AI, no downloads, the R37 keyword set or the old screenshot songs in place (2026-10-20). The section 17 questions it opened are ruled by R129 (2026-10-20) and applied in place; the evidence is in `docs/research/phase3-store-ai.md`.*

Spec date: 2026-10-17 (finalised after the open-question round; all decisions through R41 applied). Target: Segue **0.5**, Mac App Store, App Store flavor only (`SegueAppStore`, bundle `dev.ryandsilva.segue`), arm64 only, built with Xcode 27.1 (R41).

This is the brief for one focused session. It must be executable standalone. Read these before starting:

- `docs/release/decisions.md` - canonical. This spec follows R2-R10, R14-R26 and R30-R41 exactly. If anything below disagrees with it, the decisions file wins: stop and ask Ryan.
- `docs/release/open-questions.md` - the resolved question sheet. Items cited below as `A<n>` / `B-<n>` / `I-<n>` took the option stated inline here.
- `docs/release/specs/WS3-services.md` section 10.2 - the **single source of truth** for the App Privacy label. Section 6 here copies it; if they differ on the day, WS3 wins.
- `docs/release/research/04-store-listing.md` - field limits, competitors, the tooling survey.
- `docs/release/research/03-review-risk.md` - review risks, the age rating, the privacy label and the accessibility labels.
- `docs/release/research/01-account-and-connect.md` - sections E, F and G (app record, TestFlight, pricing).
- `docs/brand.md` - colours, type, voice.

Resolutions this spec builds on (so it reads standalone):

| Topic | Ruling |
|---|---|
| Listing locales | English (U.S.) only (R8, A46) |
| Territories | All storefronts except China mainland (A47; no ICP filing) |
| Screenshot library | Welcome library plus 5 approved screenshot-only original songs and the setlist "JamFest Opener", Debug-only, never shipped (A48, R128, section 8.4.1) |
| Screenshot appearance | 5 dark, 4 light (A49 plus the 9th shot, light, R129) |
| Keywords | R37 set, 97 bytes, unchanged (R129) |
| Release mode | Manual release (A51) |
| Copyright | `2026 Ryan Rony Dsilva` (R30; Apple renders the symbol) |
| Vendors | TelemetryDeck (own minimal ingest client, R34), Sentry (US region, R33; crashes, hangs, bug reports), Featurebase (web board only) (R23-R25) |
| Privacy label | WS3 10.2 copied verbatim: Coarse Location declared (A8), bug-report data Linked (A9) |
| First-run order | Welcome flow: library, then Welcome songs, then consent (two separate questions) as the last step (A10, I-7) |
| Review prompt | After the 1st completed gig, once per app version, never during a show (R20, A12) |
| Seeding flag | WS5's `-SegueScreenshotLibrary YES` is a composite over WS2b's `-SegueSeedWelcome` (I-4, section 8.2) |
| Upload path | fastlane `deliver` via mise for text and screenshots, the rest by hand (B-30) |
| Review attachment | Yes, a 60-90 s walkthrough video (B-31, section 9.5) |
| Accessibility URL | Empty (B-32) |
| Accessibility labels | Only what the WS2b audit earns (R15) |
| Appearance setting | Kept: Match System / Light / Dark (R36) |
| SKU | `segue-macos` (B-33) |
| Preview capture | Scripted XCUITest + `screencapture`; manual QuickTime as fallback (B-33) |
| Help menu names | "Report a Problem...", "Request a Feature..." (I-5) |
| Import types | `.cho .chopro .chordpro .pro .txt .crd`; `.txt`/`.crd` that need conversion go through the review sheet (A24, I-10, R76, R96) |
| Main window | Single window, Window > "Segue Library" Cmd-0 (A32) |
| Pre-show checklist | Gig Mode Shortcut rows hidden until configured (A37) |

Working rules for the session:

- Commit locally, one signed commit (`git commit -S`) per resolved unit. Never push.
- If signing fails with "failed to fill whole buffer", 1Password is locked. Stop, keep the staging, and ask Ryan to unlock it.
- Never write an em dash; use "-".
- In Bash never use plain `cat` (it is aliased to eza and hangs). Use `command cat` or the Read tool.
- Tools come from `.mise.toml` via `mise exec --`. Never install anything globally.
- Ask, don't guess, when the spec and the code disagree.

---

## 1. Goal

Produce everything App Store Connect needs for the 0.5 submission, reproducibly from the repo, plus the runbook Ryan follows from TestFlight to release. That covers:

- the final listing text;
- the questionnaire answers;
- captioned, framed screenshots generated from XCUITest (R10);
- a 15-30 s live-mode preview video (R9).

Once this session is done, "update the screenshots" is one `make screenshots`, and the store text is a reviewed diff in git.

## 2. Preconditions and dependencies

| Needed | From | Status check at session start |
|---|---|---|
| Welcome library seeder and `-SegueSeedWelcome YES` (R19, A14): four approved songs by "Segue Originals" - Soundcheck at Seven, Kitaabon Wali Gali (romanized Hindi), Kettle On, Lights Low, Ferry Lights Over Calder Bay - and the setlist "Welcome Set" | WS2b | Find the seeder (`LibrarySession+Welcome.swift`) and the flag in `LaunchOptions.swift`. If the shipped titles differ from this list, use the shipped ones everywhere below. |
| Welcome flow with WS3's `ConsentChoiceView` as its last step (A10, I-1) | WS2b + WS3 | Fresh-state launch shows library, Welcome songs, consent, in that order. |
| Accessibility audit result: `docs/release/accessibility-audit.md`, pass/fail per label (R15) | WS2b step 11 | Section 7 is filled from it. |
| R15-R18, R22, R25, R26, R36 features (import, Trash deletes, Help menu, Setlist menu, `?` overlay, autosave, two consent toggles, Report a Problem preview, What's New, TipKit, Appearance setting) | WS1, WS2a, WS2b, WS3 | Each claim in section 4.4 is ticked only against the built App Store flavor. |
| App Privacy table final (WS3 10.2) and `App/PrivacyInfo.xcprivacy` filled (WS3 10.3) | WS3 | Section 6 copies 10.2. |
| Website pages live with "Coming soon" (A55): `/`, `/support`, `/privacy`, `/terms`, `/help` (R27-R29) | WS4 | `curl -sI` each URL and expect 200. |
| `make archive`, `make validate`, `make upload` with manual signing at export and the API key (R12, R13, B-1) | WS1 | The targets exist (section 14). |
| App Store Connect access, app record, DPLA accepted, DSA non-trader (R4) | Ryan | See section 13. |

If WS2a/WS2b have not landed, do sections 4-7, 10 and the compositor only. Stop before section 8.4 capture and tell Ryan. If WS3 has not landed, do not enter section 6.

## 3. Deliverables

1. `store/` - the git-tracked store metadata, laid out the way fastlane `deliver` expects (section 10), holding the final text from section 4.
2. `scripts/check-store-metadata.swift` plus `make store-check`. This is a deterministic gate: field limits, the keyword byte count, banned words and no em dashes. It runs inside `make check`.
3. App-side Debug-only screenshot hooks (section 8.2) and a new UI-test target `SegueAppStoreUITests`, with two test plans:
   - `ScreenshotTests.xctestplan` (configurations Dark and Light);
   - `PreviewTests.xctestplan`.
4. `UITests/AppStore/AppStoreScreenshotTests.swift`, with one test per shot.
5. `scripts/compose-screenshots.swift`. It turns the raw captures into 2880x1800 PNGs with no alpha, with the brand background, headline and window shadow. Captions come from `store/screenshots.json`.
6. `make screenshots`: capture, export, compose and verify.
7. `UITests/AppStore/AppStorePreviewTests.swift` (the scripted storyboard) and `scripts/make-preview.sh` (ffmpeg via mise), behind two targets:
   - `make preview` (capture and edit);
   - `make preview-edit` (edit an existing raw recording, the fallback for a manual QuickTime take).
8. `make review-video`: the App Review attachment (section 9.5), edited by the same `scripts/make-preview.sh` in `--review` mode.
9. `make store-upload`: fastlane `deliver` (via mise) for text and screenshots.
10. The answers in sections 5, 6 and 7, entered by Ryan.
11. The runbook in section 14, executed by Ryan.

The final screenshots and videos are derived binaries. They live under `.build/` (already gitignored) and are not committed.

---

## 4. Final metadata (English (U.S.) only, per R8 and A46)

### 4.1 Field table

| Field | Value | Limit / count | Source |
|---|---|---|---|
| Name | `Segue - Setlists & Chords` | 25 / 30 chars | R3 |
| Subtitle | `Lyrics & chords for live gigs` | 29 / 30 chars | R3 |
| Promotional text | section 4.2 | 162 / 170 chars | |
| Description | section 4.3 | 3,954 / 4,000 chars (P3-9 draft, before the claim pass; recount after) | |
| Keywords | section 4.5 | 97 / 100 bytes | R37, unchanged (R129) |
| Copyright | `2026 Ryan Rony Dsilva` | Apple renders the symbol; must match Info.plist `NSHumanReadableCopyright` (`© 2026 Ryan Rony Dsilva`) | R30 |
| Support URL | `https://segue.ryandsilva.dev/support` | must show `segue@ryandsilva.dev` | R28, R29 |
| Marketing URL | `https://segue.ryandsilva.dev` | | R27 |
| Privacy Policy URL | `https://segue.ryandsilva.dev/privacy` | | R29 |
| Privacy Choices URL | leave empty | optional | |
| Primary category | Music | matches `LSApplicationCategoryType = public.app-category.music` | R3 |
| Secondary category | Productivity | | R3 |
| Version | `0.5` | must equal `CFBundleShortVersionString` | R5 |
| Price | Free (USD 0), no IAP | | R2 |
| Availability | All countries or regions except China mainland | | A47 |
| Compatibility | Apple silicon only (arm64); derived by Apple from the binary, nothing to enter | | R41 |
| SKU | `segue-macos` (permanent, set at record creation) | | B-33 |
| Accessibility URL | leave empty | | B-32 |
| License agreement | Apple standard EULA | | R7 |
| Content rights | "Yes, it contains, shows, or accesses third-party content, and I have the necessary rights" (R129) | | The app fetches the Qwen3 model weights (Apache-2.0, notices shipped) on request (R66); Welcome songs are original (R19); pasted text is the user's own action |
| Regulated medical device | No | | 01 step 13 |
| Made for Kids | No | | |
| What's New | not shown for a first version | | |

### 4.2 Promotional text (162 chars, editable without a new version)

```
Your chart, your set, your cue. Paste a chord sheet from any site, build tonight's set in minutes, and play it from a stage view that fits every song. No account.
```

The 0.5 promo before phase 3 (169 chars) was: "Your chart, your set, your cue. Keep songs as plain ChordPro files, build tonight's set, and play it from a stage view that fits every song. No account, no subscription." It stays true; the new line leads with paste. Approved (R129).

### 4.3 Description (plain text)

```
Segue is a chord chart and setlist app for performing musicians, made for the Mac. Paste a song in from anywhere, build tonight's set in minutes, and play it from a stage view that fits each song on one screen.

Made for the singer with a guitar, the keys player at an open mic, the duo on a three-hour bar gig, and the worship or cover band leader who wants the chart in front of them, not a binder.

TRY IT IN A MINUTE
Segue starts with a small Welcome library: a few original demo songs and a demo setlist. Press Start Show and you are in stage mode. Delete the demo songs whenever you like.

PASTE A SONG, CHECK IT, DONE
- Copy a chord sheet from a website or a note and choose File > New Song from Clipboard. Segue turns it into a ChordPro song with its sections and title, and shows you the result before it saves.
- Text and .crd files convert the same way, several in one review.
- Optional on-device AI double-checks section labels, title and artist. It works with Apple Intelligence, or with a free local model you can download in Settings. It never rewrites your lyrics or chords, and nothing you paste leaves your Mac.

YOUR SONGS, AS FILES
- One ChordPro file per song, in a folder you choose. No account, no sign-in.
- Your songs stay readable by other ChordPro tools, so they are never locked in.
- Everything saves as you type. Deleted songs go to the Trash.
- Fast search across titles, artists, lyrics and tags, including romanized Hindi with loose, casual spelling.
- Tags, proficiency marks and smart filters show what is gig-ready.
- Export your whole library as one archive. Quick Look and Open With in the Finder.

AN EDITOR THAT KEEPS UP
- A song card for key, tempo (tap it in), length, capo, time signature and tags: controls, not syntax. Time it measures a song's length for you.
- Edit the ChordPro text, or place chords on syllables in the visual editor. Select lines and press V, C or B to mark a verse, chorus or bridge.
- Transpose in one step, with a capo that shows shapes or concert pitch, and Nashville numbers.
- Guitar chord diagrams with alternate tunings and your own shapes, plus piano voicings.
- Spell-check and autocorrect stay out of your lyrics.

SETLISTS IN MINUTES
- Tick songs in the order you want them, then fine-tune the order.
- Or type a request like "45 min, songs I know well, upbeat start" and Segue fills the set. Lock the songs you want and rebuild the rest.
- Breaks between sets, changeover time and a running total for each part. Songs without a length are listed, never guessed.
- Arrange a song for one gig: skip, repeat or reorder its sections without changing the song.

STAGE MODE
- A dark stage view that fits each song to the screen, choosing columns and size for you.
- Set a minimum lyric size. If a song cannot fit, Segue scrolls instead of shrinking it.
- Auto-scroll that you can pause, speed up or slow down.
- A visual metronome that pulses at the song's tempo, and a click when you rehearse.
- An "Up next" footer with the next song's key and capo.
- A request comes in? Search the library mid-show and play it next.
- A pre-show checklist, a display that stays awake, and shows that reopen where you were if Segue quits mid-gig.
- Every show is saved to your gig log.

MADE FOR THE MAC
- Native macOS design in light and dark. Follow the system, or pick one in Settings.
- Full keyboard control. Press ? to see every shortcut.
- Optional: run your own shortcuts from the Shortcuts app when a show starts and ends, for example to turn on a Focus.
- Works offline. Nothing on stage depends on a network; only the optional AI model download needs one, once.

PRIVATE BY DESIGN
Your songs stay on your Mac, in files you own, and Segue's AI runs on your Mac too. Segue has no account and no ads. Usage statistics and crash reports are each sent only if you say yes, and you can change your mind at any time in Settings.

Segue is free, with no subscription and no in-app purchases.
```

Writing rules the text already follows. `store-check` enforces the mechanical ones.

- **Nothing personal-only.** No audio, LRCLIB, URL import or custom models. These are personal modules and do not ship in this flavor.
- **AI claims only as built (R61, R62).** On-device, re-checks a paste's sections, title and artist and reads set requests, never rewrites lyrics or chords, nothing pasted leaves the Mac, works without any model. "Apple Intelligence" only in a referential phrase ("works with"), spelled exactly, never in a feature name (section 17, question 5).
- **No other platforms.** No "iPhone", "iPad", "Android" or "Windows" (2.3.10).
- **No competitor names** (2.3.7).
- **No "beta", "preview" or "test" wording.** Guideline 2.2 bars betas from the store. "0.5" appears only as the version number.
- **"the Shortcuts app"** is used, never the Shortcuts icon (5.2.5).
- **No "collects no data".** R25/R26 analytics and crash reports make that false.
- **"free".** If review objects to it, delete the last line and keep "no subscription".


### 4.4 Claim verification (do this against the built App Store flavor, not the plan)

Run the claim pass in two passes:

1. Launch `Debug-AppStore` from a reset state and check every row below.
2. Once a TestFlight build exists, re-check the rows marked (T) on that build.

If a row fails, **delete its line from the description**. Never ship a claim on the strength of a plan. Then rerun `make store-check` and update the character count in 4.1.

| Claim (description line) | Decision | How to verify |
|---|---|---|
| Welcome library + demo setlist, deletable | R19 | Fresh state, create a library, keep the Welcome-songs box ticked, and see the four songs and "Welcome Set". Delete one song; it lands in the Trash. (T) |
| Paste: File > New Song from Clipboard, review before save | R75, R83, R117 | Copy a chord sheet as text, press Option-Command-V: the review sheet shows the converted song, title filled, sections labelled; Accept saves it. |
| Text and .crd files convert, several in one review | R76, R96 | Drag a `.txt` chord sheet and a `.crd` together: one review sheet lists both with checkboxes. |
| Optional on-device AI; works with Apple Intelligence or a free local model; never rewrites lyrics; nothing pasted leaves the Mac | R62, R63, R66, R93 | Settings > AI shows Apple Intelligence status and the local model card (size, licence, Download). With Wi-Fi off a paste still converts. Sparkles mark AI-decided labels only; lyric lines are unchanged. |
| Drag files in; File > Import | R15, A24 | Drag a `.cho` from Finder; use the menu item with a `.chordpro` and a `.txt`. |
| Deletes go to the Trash | R15 | Delete a song and a setlist, then find both in the Trash. |
| Everything saves as you type | R17 | Edit, wait, quit without a prompt, relaunch: the edit is still there. |
| Romanized Hindi loose-spelling search | shipped (`RomanNormalizer.swift`) | Search "kitabon" and find "Kitaabon Wali Gali". |
| Tags, proficiency marks and smart filters | shipped, R72 | Visible in the library; create a smart filter and apply it. |
| Export library archive | R16 (nice) | File menu item produces an archive that reopens. |
| Quick Look and Open With in Finder | R16 (nice) | Space on a `.cho` in Finder shows a preview; Open With lists Segue. (T) |
| Song card: key, tempo with tap, length, capo, time signature, tags; Time it | R80, R91, R111 | Open a song's card; tap tempo; Time it fills Length. |
| Select lines, V / C / B marks a section | R82 | Visual editor: select two lines, press C. |
| Visual editor, transpose, capo, Nashville, diagrams with tunings, custom shapes, piano | shipped | Existing E2E suites; eyeball. |
| Spell-check and autocorrect off in lyrics | shipped | Type a misspelling; it is not underlined or corrected. |
| Tick songs in order (Pick), fine-tune (Arrange) | R84 | Pick: Space ticks in order; Arrange: Option-Down moves. |
| Type a request, Segue fills the set; lock and rebuild | R65, R114, R115 | Arrange: type "45 min, songs I know well, upbeat start", Build; lock one, Rebuild keeps it. |
| Breaks, changeover time, per-part totals; unknown lengths listed, never guessed | R85, R86, R88, R91 | Add a break row; set a changeover; a song with no length makes "N unknown", which lists it. |
| Arrange a song for one gig | R122, R123 | Slot popover > Arrangement: untick a section; the stage skips it; the `.cho` is unchanged. |
| Visual metronome; click in rehearsal | R90, R118 | On stage M shows the pulsing dot for a song with a tempo; in a rehearsal K toggles the click. |
| Auto-fit, min lyric size, auto-scroll controls, Up next, request search and queue, skip, pre-show checklist, keep awake, crash resume, gig log | shipped (phase 2) | `SegueLiveE2ETests`; keep-awake was checked in the real gig (section 14.3). |
| Press ? to see every shortcut | R15 | In the library and on stage. If it works only on stage, reword to "Press ? on stage". |
| Optional shortcuts from the Shortcuts app | R18 | Off on a fresh install; the checklist row ticks only after a successful run. |
| Light and dark; follow the system or pick one in Settings | shipped, R36 | Toggle the system appearance; Settings > Appearance offers Match System / Light / Dark and each applies. |
| Works offline; only the optional model download needs a network, once | shipped, R66 | Wi-Fi off: the full show flow and a paste work, with no error banners. The model card's Download needs the network (Settings > AI). |
| Statistics and crash reports each opt-in; change in Settings | R25, R26, A10 | The last Welcome step asks two separate questions, each with equal-weight buttons; Settings > Privacy has both toggles. |
| No ads, no IAP | R2 | Trivially true. |

Do not add a page-turner pedal claim unless Ryan has verified one with real hardware. The default bindings do map PgUp/PgDn and the arrows.

### 4.5 Keywords (English (U.S.), R37)

```
chordpro,songbook,transpose,prompter,worship,hindi,guitar,piano,capo,nashville,stage,singer,cover
```

- **Byte count: 97** (Python `len(s.encode())`, re-checked 2026-10-17). All ASCII, so bytes equal characters.
- **Excluded words:** words already in the name or subtitle (segue, setlists, chords, lyrics, live, gigs), "app", competitor names, and `band` (implies band sharing Segue does not have).
- No other locale sets: en-US is the only listing (A46).

- **Kept (R129).** `ai` cannot be used: Apple requires each keyword to be "greater than two characters". The `paste` and `metronome` swaps were considered and R37 stays.

### 4.6 App Review Information

| Field | Value |
|---|---|
| Sign-in required | No (no demo account) |
| Contact first/last name | `Ryan` / `Dsilva` (R30 legal name) |
| Contact email | `segue@ryandsilva.dev` |
| Contact phone | Ryan's phone. **Not committed to git.** Enter by hand, or pass it to `deliver` through an environment variable. |
| Notes | below (3,585 / 4,000 bytes as drafted by P3-9: the paste try-it, the ON-DEVICE AI paragraph and the model download in NETWORK USE, with the Welcome, stage and Apple-events paragraphs tightened; recount after the 14.2 pass) |
| Attachment | the 60-90 s walkthrough video from section 9.5 (B-31) |

Notes. The names below follow the resolved specs (WS2a, WS2b, WS3). Before pasting, check each against the built App Store flavor and correct the notes, never the other way round:

- the Welcome step titles and button labels ("Create Library in Music...", the Welcome-songs checkbox, the two consent rows and Continue);
- the setlist name "Welcome Set" and the four song titles;
- the Start Show menu path and shortcut (Setlist > Start Show, Cmd-Return, A33);
- the quick-search and end-show keys (today `Cmd-K` and `Cmd-.`, from `InputBindings.defaults`);
- the Help item "Report a Problem..." and whether its form has the optional email field (WS3 8.2; A9 keeps it);
- the import file types (the single SegueCore list, A24);
- the paste review sheet's Accept button, the shortcut Option-Command-V, Arrange's Command-2 and the request bar's Build;
- the model's name, size and licence in Settings > AI (`curated-models.json`).

```
Segue is a songbook and live-performance app for gigging musicians. Songs and setlists are plain ChordPro text files in a folder the user chooses. No account, no sign-in, no in-app purchases.

FIRST LAUNCH (three-step Welcome window)
1. Click "Create Library in Music..." and accept the suggested folder.
2. Leave "Add 4 songs and a setlist written for Segue" ticked and click Continue: four original demo songs by the developer (one in romanized Hindi, i.e. Hindi in Latin letters) and a setlist "Welcome Set".
3. Two separate questions, "Share usage analytics" and "Send crash reports", each with two equal buttons. Any answer is fine; nothing is sent unless you choose Share or Send. Settings > Privacy changes them later.

THINGS TO TRY
1. Library: select a song; try transpose, capo and Nashville numbers. Search "kitabon" to find the romanized Hindi song despite the spelling.
2. Paste: copy any chord sheet as text (e.g. from a chord website) and choose File > New Song from Clipboard (Option-Command-V). A review sheet shows the converted song before anything is saved; click Accept. Dragging a .txt or .crd file onto the window opens the same sheet.
3. Editor: double-click a song; switch text and visual mode. Changes save automatically.
4. Setlists: open "Welcome Set". Arrange (Command-2) has a request bar: type "15 min" and click Build (one Undo takes it back).
5. Stage: Setlist > Start Show (Command-Return), continue past the checklist. Stage mode is full screen and hides the Dock and menu bar only while performing. Right Arrow next song, A auto-scroll, Command-K search for a request, ? every key, Command-Period then End Show to leave.
6. Window > Segue Library (Command-0) reopens a closed main window.

ON-DEVICE AI (optional)
Segue converts pastes with its own rules first. A model only re-checks section labels, title and artist, and reads set requests; it runs entirely on the Mac and nothing pasted or typed is sent anywhere. Apple Intelligence (Foundation Models framework) is used when the Mac has it turned on; Settings > AI shows its status. A free local model (Qwen3 4B, Apache-2.0, 2.27 GB) is offered in Settings > AI and downloads only when the user clicks Download, with its size shown first. The download is model weights (data files) checked against SHA-256 hashes built into the app; it is run by the MLX framework bundled in the app and adds no code. Delete removes it. Everything works without either model, and Settings > AI has one switch to turn AI off.

NETWORK USE
Writing and performing work fully offline. Segue goes online only for: (a) usage statistics, after the user chooses Share; (b) crash and hang reports, after the user chooses Send; (c) Help > Report a Problem..., sent only after a preview of exactly what is sent; (d) the optional model download above, directly from huggingface.co, only on click. Help, the privacy policy and the feature board open in the default browser.

SHORTCUTS INTEGRATION (APPLE EVENTS, optional)
Settings > Live can run shortcuts the user made in the Shortcuts app when a show starts and ends (e.g. to turn on a Focus). Off until set up. Segue sends only the "run shortcut" Apple event to Shortcuts Events, via com.apple.security.scripting-targets limited to the access group com.apple.shortcuts.run (no temporary exception); the reply tells Segue whether it ran, so the checklist ticks "Focus on" only then. macOS asks for Automation permission when the user presses Test in Settings > Live (type any shortcut name, press Test).

Support: segue@ryandsilva.dev - https://segue.ryandsilva.dev/support
```


#### 4.6.1 Notes gate

- `store-check` enforces the 4,000-byte limit on `review_information/notes.txt`; update the count in the table above after the 14.2 word-for-word pass.
- The reviewer sees the full first-run flow only on a clean container. That is why the 14.2 clean-account pass and R40 (move Ryan's container aside) matter.

---

## 5. Age rating questionnaire (expected result 4+)

Click path: App Store Connect > Apps > Segue > App Information > Age Rating > Edit. The labels follow the 2025 questionnaire as described in `03` section 6. If Apple's wording differs on the day, answer by meaning and tell Ryan.

| Question | Answer | Why |
|---|---|---|
| Parental Controls | No | none in app |
| Age Assurance | No | none |
| Unrestricted Web Access | **No** | Help, privacy, terms and board open in the default browser (`NSWorkspace`/`openURL`), with no in-app web view; the model download is one fixed URL, not browsing. **If any `WKWebView` ships, stop: this becomes a question for Ryan.** |
| User-Generated Content | **No** | Apple's definition is "the broad distribution of content created by users". Songs and pastes are local files, never distributed to other users. The bug report is private to the developer (Sentry, R24). The Featurebase board is a website opened in the browser, never posted to from the app (R23). |
| Social media | No | |
| Messaging and Chat | No | |
| Advertising | No | R2 |
| In-app purchases / loot boxes | No | R2 |
| Gambling, Simulated Gambling, Contests | None / No | |
| Profanity or Crude Humor | None | Welcome songs are clean (check WS2b lyrics) |
| Horror/Fear Themes | None | |
| Alcohol, Tobacco, or Drug Use or References | None | check the Welcome lyrics (a bar-gig song must not mention drinking) |
| Mature or Suggestive Themes | None | |
| Sexual Content or Nudity / Graphic Sexual Content | None | |
| Cartoon or Fantasy Violence / Realistic Violence / Prolonged Graphic or Sadistic Violence | None | |
| Guns or Other Weapons | None | |
| Medical or Treatment Information | None | |
| Health or Wellness Topics | No | |
| AI features | no item exists (checked at source 2026-10-20) | The questionnaire has no AI, chatbot or assistant item. Segue's models only label the user's own paste and read set requests; no chat, no generated content for others. If Apple adds an item on the day, answer by meaning and tell Ryan. Answer as this table, 4+, no override (R129). |

Apple rates the app's own content, not what a user types into a local editor (`03` section 6).

---

## 6. App Privacy questionnaire (copied from WS3 10.2)

Click path: App Store Connect > Apps > Segue > App Privacy (sidebar, under General) > Get Started (or Edit) > "Yes, we collect data from this app". Then tick the nine data types below, and for each one choose Set Up and enter purposes, linkage and tracking exactly as the table. Set the Privacy Policy URL `https://segue.ryandsilva.dev/privacy` on the same page. Finally click Publish.

"Data Not Collected" is **not** possible (`03` 8.3; consent does not remove a disclosure).

**Single source of truth.** WS3 section 10.2 owns this table (I-9). The copy below is from the resolved WS3 spec. Before entering anything, diff it against WS3 10.2 at HEAD; if they differ, WS3 wins and this table is corrected in the same commit.

Vendors behind the rows (fixed, R23-R25, R33, R34):

- **TelemetryDeck** (usage analytics, opt-in), sent through Segue's own minimal ingest client, which sends only the WS3 section 5 fields plus OS/app version and region (R34). Region comes from the locale setting, not IP.
- **Sentry**, US data region (R33): crashes, hangs and MetricKit (opt-in, separate toggle, R25), plus Report a Problem... envelopes (sent only after the preview, R22, R24). Sentry's per-install ID is kept (R25).
- **Featurebase**: the board is a website opened in the browser; the app sends it nothing, so it adds no rows.
- **Hugging Face** (the optional AI model download, R66): adds no rows. Segue's own request on the user's click; the developer receives nothing; Hugging Face is not a partner whose code makes the request; an IP address on a request the developer does not retain needs no disclosure (Apple's "collect" definition, `docs/research/phase3-store-ai.md` section 3). The privacy policy discloses it. No label change (R129).
- **Apple Intelligence** (Foundation Models) runs on the device: adds no rows.

Every row is **Tracking: No** (no cross-app or cross-company linking, no data brokers, no ATT).

| Data type (Apple's name) | Collected by | Purposes | Linked to user | Tracking |
|---|---|---|---|---|
| Usage Data > Product Interaction | TelemetryDeck | Analytics | No | No |
| Identifiers > Device ID | TelemetryDeck hashed user ID; Sentry installation ID (R25) | Analytics; App Functionality | No | No |
| Location > Coarse Location | TelemetryDeck locale region (country level), declared conservatively (A8) | Analytics | No | No |
| Diagnostics > Crash Data | Sentry crashes; MetricKit crash diagnostics in bug reports | App Functionality | **Yes** (A9) | No |
| Diagnostics > Performance Data | Sentry hangs / MetricKit; hang diagnostics in bug reports | App Functionality | **Yes** (A9) | No |
| Diagnostics > Other Diagnostic Data | System info and logs in bug reports | App Functionality | **Yes** (A9) | No |
| User Content > Customer Support | Bug report description | App Functionality | **Yes** (A9) | No |
| User Content > Other User Content | Optional attached song file (off by default, R22) | App Functionality | **Yes** (A9) | No |
| Contact Info > Email Address | Optional reply-to email in the bug report | App Functionality | **Yes** | No |

Why "Linked: Yes" for the bug-report types: a report can carry an email address in the same submission, and Apple asks once per data type, so the linked flow sets the answer (A9).

Rules:

- **Do not claim the optional-disclosure exemption** for the bug report (`03` 8.3). Over-disclosure is safe; under-disclosure is a 5.1 risk.
- **Three-way diff before Publish.** This label, `App/PrivacyInfo.xcprivacy` (WS3 10.3) and the `/privacy` policy (WS4) must list the same types with the same linkage and purposes. Diff all three; any mismatch is fixed at its owner (WS3 for label and manifest, WS4 for the policy) before publishing.
- **Reconcile vendor SDK manifests.** If the Sentry SDK ships its own `PrivacyInfo.xcprivacy` in the bundle, its declared types must appear here too.
- **Re-check on any vendor change.** The label is editable at any time without a new build; a vendor swap behind the WS3 ports means re-running this section.

## 7. Accessibility Nutrition Labels (conditional on the WS2b audit)

Click path: App Store Connect > Apps > Segue > App Accessibility (sidebar, under General) > Add Accessibility Support > macOS. Tick the features, then Publish. This path is from Apple's help as read in `03`; verify it on the day.

A label is claimed **only** if the WS2b audit (`docs/release/accessibility-audit.md`) records a pass for **every common task** (R15): the full Welcome flow (library step, Welcome-songs step, the two-row consent step), library, editor (both modes), setlist builder (including Setlist > Add Selected Song to Setlist, A33), stage mode enter, play and exit, Settings (all panes, including Appearance per R36 and AI per R73), Report a Problem..., import and delete, and the phase 3 surfaces (R79): paste review sheet (single and batch), song card and Time it, section band, section notes, set builder Pick / Arrange with break rows and the missing-lengths list, the set assistant bar and chips, smart filters, the Arrange Sections sheet, the metronome overlay and the live repeat message. The audit decides; this section never overrides it.

| Label | Claim if | Default expectation (`03` section 7) |
|---|---|---|
| Dark Interface | audit pass: no white flashes, all sheets and panels dark, with Appearance set to Dark and to Match System on a dark system | likely yes |
| Reduced Motion | audit pass, and auto-scroll never starts by itself with Reduce Motion on; Welcome step cross-fades are off | likely yes |
| Sufficient Contrast | the A43/A44 fixes landed (3:1 control borders under Increase Contrast, or in the default look if Apple's criteria do not accept the Increase Contrast route; `indicatorOff` token and darker `played`), and the audit passes | only if the fixes landed and the audit passes |
| Differentiate Without Color Alone | every state (played/current/upcoming, proficiency, request) also differs by shape, label or lightness | audit decides |
| VoiceOver | full VoiceOver pass of every common task, including a non-drag way to move a chord in the visual editor and to add a song to a set | audit decides; do not claim on partial coverage |
| Voice Control | full Voice Control pass ("show names/numbers") | audit decides |
| Larger Text | no claim (B-19; not offered on Mac, re-check in App Store Connect) | - |
| Captions, Audio Descriptions | n/a (no media in the app) | do not claim |

Accessibility URL: leave empty for 0.5 (B-32; there is no `/help/accessibility` page in R29).

---

## 8. Screenshot pipeline (R10: captioned + framed, brand background, from XCUITest)

### 8.1 Approach

```
make screenshots
  1. xcodebuild test  (Segue-AppStore scheme, ScreenshotTests plan, configs Dark + Light)
       -> .build/screenshots/run.xcresult      (one XCTAttachment per shot per appearance)
  2. xcrun xcresulttool export attachments --path ... --output-path .build/screenshots/raw
       -> raw/*.png + raw/manifest.json
  3. scripts/compose-screenshots.swift --raw .build/screenshots/raw \
       --captions store/screenshots.json --tokens design/tokens.json \
       --out .build/screenshots/final
       -> final/en-US/01-stage.png ... (2880x1800, sRGB, no alpha)
  4. verify: sips dimensions + hasAlpha on every output; contact sheet for eyeballing
```

The screenshots come from the **App Store flavor** (`Debug-AppStore`), never Personal. That way no personal-module UI can appear.

### 8.2 App-side Debug-only hooks

Parse the flags in `App/Sources/LaunchOptions.swift`. They are honoured only under `#if DEBUG`, like the existing `-SegueLibraryPath`. WS1 wraps the parser and every existing flag string in `#if DEBUG` and greps for them in `verify-appstore` (B-7, I-12). WS5 wraps **its own new flag strings** the same way and adds only those strings, plus one screenshot-only song title (8.4.1), to the `scripts/verify-appstore.sh` grep list, failing if any is found in the Release-AppStore binary.

WS2b owns the Welcome seeder and its flags (`-SegueSeedWelcome YES`, `-SegueOnboarding fresh|done`, `-SegueTips show|hide`). WS5 does not reimplement any of them; it composes them (I-4).

| Flag | Owner | Effect |
|---|---|---|
| `-SegueScreenshotLibrary YES` | WS5 (composite) | 1. Implies `-SegueTestDefaults`, so real UserDefaults are untouched. 2. Wipes one fixed folder **inside the app's own container**, `Library/Application Support/Segue-Screenshots/Library`, defined once as a constant in `LaunchOptions` and shared with WS2b's no-path branch of `-SegueSeedWelcome` (so both flags open the same folder). 3. Applies `-SegueSeedWelcome YES` (the four Welcome songs and "Welcome Set"), then writes the approved screenshot-only songs from 8.4.1. 4. Applies `-SegueOnboarding done` and `-SegueTips hide`. 5. Records both consent answers as declined through WS3's `ConsentStore` (nothing is sent). 6. Suppresses the What's New sheet and the review prompt. No sandbox exception, no entitlement drift, never touches the user's real library bookmark. |
| `-SegueAppearance dark\|light` | WS5 | Writes the R36 Appearance setting (`appearance.mode`, via `AppearanceStore`) in the test-defaults suite, so the app applies `.darkAqua` / `.aqua` through its own shipped path. Deterministic, with no reliance on `-AppleInterfaceStyle`. Stage mode is always dark regardless. |
| `-SegueWindowFrame x,y,w,h` | WS5 | Points, top-left origin on the main screen. It sets the main window frame, and the stage window's when stage is shown windowed (next row). Screenshots use `0,40,1440,900`, which gives 2880x1800 px on Retina. The preview uses a 16:9 frame (section 9). |
| `-SegueStageWindowed YES` | WS5 | Presents stage mode in a normal window at `-SegueWindowFrame` instead of full screen. Full screen on Ryan's 14" MBP (3024x1964, notch) is not 16:10. Rendering inside the window must be identical; only the window chrome and presentation options differ. |
| `-SegueFixedClock <ISO8601>` | WS5 | Only if a captured shot shows a time that changes between runs (set elapsed time, gig log date). It injects a fixed `Clock`; the injectable clock already exists. |

There is no separate `-SegueSuppressFirstRunUI` flag: its job is step 4-6 of the composite above.

Also use the existing `-ApplePersistenceIgnoreState YES` and `-SegueUITesting YES` (via `E2E.freshInstanceArguments`). The run sets `UITesting.isActive`, which hides the E2E instrumentation.

### 8.3 Test target and plans

- **`Project.swift`:** add the target `SegueAppStoreUITests`, modelled on `SegueUITests`:
  - `product: .uiTests`, sources `UITests/AppStore/**` + `UITests/E2ESupport.swift`;
  - `dependencies: [.target(name: "SegueAppStore")]`;
  - `TEST_TARGET_NAME = SegueAppStore`;
  - no `/private/tmp` entitlement needed.

  Add a `testAction: .testPlans([...])` to `appStoreScheme` with configuration `Debug-AppStore`.
- **`UITests/AppStore/ScreenshotTests.xctestplan`:**
  - two configurations: `Dark` (environment `SEGUE_SHOT_APPEARANCE=dark`) and `Light` (`=light`);
  - selected tests: `AppStoreScreenshotTests` only;
  - parallel execution off;
  - automatic screenshots off (`systemAttachmentLifetime: deleteOnSuccess`; only our explicit attachments are kept);
  - no retries. A flaky shot is a bug to fix, not to hide.

  Test-plan environment variables reach the UI test runner, not the app. The test reads `ProcessInfo.processInfo.environment["SEGUE_SHOT_APPEARANCE"]` and passes `-SegueAppearance` in the launch arguments.
- **`UITests/AppStore/PreviewTests.xctestplan`:** a single configuration that selects `AppStorePreviewTests`.
- **`scripts/xcodebuild.sh`:** honour an optional `SEGUE_RESULT_BUNDLE` environment variable as the `-resultBundlePath`. The default behaviour stays unchanged, because the script already passes its own `-resultBundlePath`.
- **`make e2e`:** stays on the Personal scheme and does not run these tests.

Each test:

1. launches with `E2E.launch` and the flags above;
2. drives the UI to the state in 8.4, using `click(in:)`/`typeKey(in:)` from `E2ESupport.swift`;
3. waits for the state to settle (an element-existence wait, never a fixed sleep for correctness);
4. moves the pointer off the window, so there are no hover highlights;
5. attaches the window image: `XCTAttachment(screenshot: <window>.screenshot())`, named `appstore-<NN>-<slug>-<appearance>`, with `lifetime = .keepAlways`;
6. asserts the image is 2880x1800 px. If it is not, fail with the actual size; don't let the compositor paper over it.

### 8.4 Shot list and captions

Nine shots (the 9th, `paste`, added by R129); the first three show in search results. Both appearances are captured for every shot; which one ships per slot is set in `store/screenshots.json`. The mix is **5 dark, 4 light** (A49 plus the light 9th shot), as in the table. At least one must be dark (Apple guidance).

Library content for every shot comes from `-SegueScreenshotLibrary YES` (8.2): the four Welcome songs, "Welcome Set", the screenshot-only songs and the screenshot-only setlist from 8.4.1.

| # | Slug | State to drive to | Appearance | Headline | Subline |
|---|---|---|---|---|---|
| 1 | `stage` | Stage mode from "JamFest Opener" on "Ferry Lights Over Calder Bay" (the 2-column Welcome song): header with key/capo/tempo, two-column auto-fit, gutter labels, progress dots, Up next footer | Dark (stage is always dark) | Your chart, your set, your cue. | A stage view that fits every song on one screen. |
| 2 | `builder` | Setlist builder on "JamFest Opener": library column left (Welcome and screenshot-only songs), set right with start times, running total against its target | Dark | Build tonight's set in minutes. | Drag, reorder, and watch the running time. |
| 3 | `search` | Library search field holding `kitabon`, matching "Kitaabon Wali Gali" with the lyric hit visible | Light | Find the song from one line. | Search lyrics, even romanized Hindi with casual spelling. |
| 4 | `editor` | Editor in visual mode on a Welcome song, chord pills over syllables, a chord mid-selection | Light | Put chords right on the syllable. | Or edit the ChordPro text directly. |
| 5 | `theory` | Song preview of "Kettle On, Lights Low" transposed, capo on, Nashville toggle on, diagram strip showing guitar and piano | Light | Transpose, capo, Nashville numbers. | Guitar and piano diagrams in any tuning. |
| 6 | `request` | Stage mode on "JamFest Opener" with quick search open on `kitabon`, then "Kitaabon Wali Gali" queued: footer shows "Request" and the count dot | Dark | Take a request mid-set. | Search, queue, and play it next. |
| 7 | `minsize` | Stage mode on the longest Welcome song at a large minimum lyric size, scrolled partway (scroll position visible) | Dark | Readable from the mic stand. | Set a minimum size. Segue scrolls rather than shrinks. |
| 8 | `checklist` | Pre-show checklist sheet over the setlist. No Gig Mode Shortcut rows (hidden until configured, A37, R18) | Dark | Ready before you walk on. | A pre-show checklist, and shows that survive a crash. |
| 9 | `paste` | The paste review sheet for a chord-site paste of a Welcome song (the guide's fixture), the original on the left, the converted song on the right with the AI marks of the recorded refinement (R129) | Light | Paste a song from anywhere. | Segue converts it. You check it before it saves. |

Headlines are 23-35 characters and sublines 32-57. Keep any edit within about 36 and about 60, so they set on one line each at the chosen size.

Content rules:

- **Original content only.** Only Welcome-library songs and the approved screenshot-only songs may appear (2.3.9, 5.2.1).
- **Lyrics.** Only Welcome songs have lyrics. Before composing, read every visible lyric in each raw capture and confirm it is the WS2b original text.
- **No real song titles anywhere.** That includes "tum hi ho" (`03` 5.2.1).

#### 8.4.1 Screenshot-only songs and setlist (A48)

Original titles written for these screenshots (R128), artist "Segue Originals", **titles and chords only** (`{title}`, `{artist}`, `{key}`, `{tempo}`, `{duration}`, section labels and chord-only lines; no lyrics). They exist only to make the library and builder look like a real repertoire. They are never shipped:

- they live as string literals in `App/Sources/Debug/ScreenshotSongs.swift`, compiled only under `#if DEBUG`;
- the composite flag writes them into the screenshot folder after the Welcome seeder runs;
- `verify-appstore` greps the Release-AppStore binary for one of the titles and fails if found.

Approved titles (R128, 2026-10-20: five, deliberately fewer than the old 6-10 guideline). Each went through the title search (Apple Music, Spotify, Google "<title> song"); any hit drops the title unless Ryan keeps it. Log: `docs/research/phase3-store-ai.md` section 7.

| # | Title | Key | Tempo | Duration | Title search (2026-10-20) |
|---|---|---|---|---|---|
| 1 | Lanterns on Pier Nine | D | 92 | 3:48 | clean |
| 2 | Chai at Platform Four | Em | 96 | 3:40 | clean |
| 3 | Northbound at First Light | Bb | 76 | 4:30 | clean on Apple Music (R129: replaces the R128 title that hit an existing song) |
| 4 | Saltwater Telegraph | Am | 100 | 3:35 | clean |
| 5 | Last Tram to Wexley | G | 132 | 3:10 | clean |

Dropped (R128): Second Set Shuffle, Tin Roof Weather, Neeli Cycle Ka Safar, Copper Kettle Waltz, Open Mic at the Laundromat.

Tags and proficiency marks are set so the library shows a realistic mix (some "Ready", a few "Learning", two "Pro").

Screenshot-only setlist **"JamFest Opener"** (R128; also Debug-only, created by the composite flag): every approved screenshot-only song plus the Welcome songs except "Kitaabon Wali Gali", so 8 entries with five approved titles, with "Ferry Lights Over Calder Bay" in position 3 (so shot 1 has an Up next song) and "Kitaabon Wali Gali" deliberately **not** in the set, so the request in shot 6 and in the preview (9.2) is a real request. Its target length is chosen so the running total sits a little under target. Example with the five R128 titles: Last Tram to Wexley (3:10), Lanterns on Pier Nine (3:48), Ferry Lights Over Calder Bay (4:40), Chai at Platform Four (3:40), Soundcheck at Seven (3:20), Saltwater Telegraph (3:35), Kettle On, Lights Low (3:05), Northbound at First Light (4:30) = 29:48 against a 30:00 target. Final order and target are fixed in `ScreenshotSongs.swift`.

### 8.5 Export

`xcrun xcresulttool export attachments --path .build/screenshots/run.xcresult --output-path .build/screenshots/raw`. Re-verified present in **Xcode 27.1 (27A9275)** on 2026-10-17 with `xcrun xcresulttool help export` (subcommand `attachments`, alongside `diagnostics`, `coverage`, `evaluations`, `metrics`; `object` is deprecated). Its options there are `--path`, `--output-path`, `--test-id`, `--filter <glob>`, `--only-failures`, `--schema`, `--schema-version` (default manifest schema 0.4.0). Pin `--schema-version 0.4.0` in the make target so a future default change cannot silently reshape the manifest. It writes a `manifest.json` that maps each test to its attachments, with an exported file name and a suggested human-readable name. The compositor reads the manifest. It matches the attachment name prefix `appstore-<NN>-<slug>-<appearance>`, and does not assume the suffix format, which is not documented.

### 8.6 Compositor: `scripts/compose-screenshots.swift`

It is a `#!/usr/bin/env swift` script in the style of `scripts/gen-icon.swift`, using only AppKit/CoreGraphics/CoreText/ImageIO.

Inputs:

- `--raw <dir>` (with `manifest.json`);
- `--captions store/screenshots.json`;
- `--tokens design/tokens.json`;
- `--fonts Packages/SegueUI/Sources/SegueUI/Theme/Fonts` (registered with `CTFontManagerRegisterFontsForURL`, process scope);
- `--out <dir>`;
- optional `--contact-sheet <file>` and `--direction A|B|C`.

`store/screenshots.json` schema:

```json
{
  "canvas": { "width": 2880, "height": 1800 },
  "direction": "A",
  "windowCornerRadius": 0,
  "locales": {
    "en-US": [
      { "id": "01-stage", "raw": "appstore-01-stage", "appearance": "dark",
        "background": "dark", "headline": "Your chart, your set, your cue.",
        "subline": "A stage view that fits every song on one screen.", "crop": null }
    ]
  }
}
```

`windowCornerRadius` is measured from a raw capture on macOS 26 and then fixed in the file; the macOS 26 window radius is **UNVERIFIED**, so don't hard-code a remembered value.

Rendering rules:

- **Canvas.** 2880x1800, drawn in a `CGContext` with `CGColorSpace.sRGB` and `CGImageAlphaInfo.noneSkipLast`, so the output has **no alpha**. Write the PNG with `CGImageDestination`.
- **Background.** Colours come from `tokens.json`, never hard-coded:
  - `dark` = `ground.dark` (#101113);
  - `light` = `surfaceAlt.light` (#F2F2F4), so the white window separates from it.
- **Headline.** Schibsted Grotesk ExtraBold 800, tracking -0.035em (brand Title role), about 96-110 px:
  - colour `ink.dark` on dark and `ink.light` on light;
  - optional cue dot after the headline, like the wordmark (direction-dependent);
  - one line; fail if it overflows rather than shrinking silently.
- **Subline.** Medium 500, about 44-48 px, `muted` for the background's mode.
- **Window.**
  - Scale the raw capture to fit the direction's box (about 80% of canvas width).
  - Clip it to `windowCornerRadius x scale`, inset 1 px so desktop pixels at the corners never bleed. `XCUIElement.screenshot()` crops a screen rect, so the corners contain whatever was behind the window.
  - Draw a 1 px hairline (`controlBorder` logic from `brand.md` section 7: `line` on light, `muted` at 40% on dark).
  - Shadow: `CGContext.setShadow` with offset (0, -24 px), blur 80 px and black at 35% on light. On dark, use a slightly larger blur and 50%, because a black shadow on #101113 is near invisible. The dark-mode window edge relies on the hairline.
- **Crop.** Optional `{x, y, w, h}` in raw pixels, for any capture that is not 16:10.
- **Contact sheet.** A 3x3 grid at 25% scale, for Ryan's review.

Design directions (Ryan picks one before the full set is composed; this is his standing preference):

- **A "Caption over, window rising":**
  - centred headline and subline in the top 22%;
  - the window centred below, bottom-anchored and bleeding off the bottom edge by about 6%.
- **B "Floating window":**
  - headline top-left, aligned to the window's left edge;
  - the window fully inside the canvas with a strong shadow and even margins.
- **C "Split":**
  - headline and subline in a left column (about 30%), with the cue dot;
  - the window on the right, about 66% wide and vertically centred.

Implement all three behind `--direction`, render shots 1 and 3 in each as `.build/screenshots/directions/*.png`, and show Ryan (section 13, step R7). Then lock `direction` in the JSON.

> **As built (2026-10-20).** `make screenshots` renders shots 1-3 in A, B and C (`.build/screenshots/directions/`, with `directions-sheet.png`) and the full set in the JSON's `direction` (A until Ryan picks). A no longer bleeds off the bottom: any bleed hid the stage's Up next footer, so the window sits whole on the canvas, bottom-anchored with a 70 px margin. `windowCornerRadius` is 52 px (measured on a raw macOS 26 capture). The PNGs are written as 24-bit RGB (ImageIO keeps a padding alpha channel for CGContext's RGBX images). The captures run without test plans, like the guide's (`TEST_RUNNER_SEGUE_SHOT_APPEARANCE`); the stage is captured as its borderless window's live view, so stage shots have no title bar or window corners.

### 8.7 Make target

```make
screenshots: ## App Store screenshots: capture (XCUITest, App Store flavor), export, compose, verify
	rm -rf .build/screenshots
	SEGUE_RESULT_BUNDLE=.build/screenshots/run.xcresult \
	  $(XCODEBUILD) -scheme Segue-AppStore -configuration Debug-AppStore \
	  -testPlan ScreenshotTests test
	xcrun xcresulttool export attachments --path .build/screenshots/run.xcresult \
	  --output-path .build/screenshots/raw --schema-version 0.4.0
	scripts/compose-screenshots.swift --raw .build/screenshots/raw \
	  --captions store/screenshots.json --tokens design/tokens.json \
	  --fonts Packages/SegueUI/Sources/SegueUI/Theme/Fonts \
	  --out .build/screenshots/final --contact-sheet .build/screenshots/contact-sheet.png
	scripts/compose-screenshots.swift --verify .build/screenshots/final
```

`--verify` checks every PNG with ImageIO for 2880x1800 and no alpha, and confirms the count is 1-10 per locale. Cross-check once by hand with `sips -g pixelWidth -g pixelHeight -g hasAlpha`.

Add `screenshots` to `.PHONY`. Keep it out of `check`: it is slow and needs the screen.

### 8.8 Pixel review

Open the contact sheet and every final PNG at 100%. Fix each of these at the source, in the app or the test state, not in the compositor:

- clipped text, truncation ellipses, hover/focus rings left over;
- a selection highlight in the wrong colour;
- a stray error banner;
- any personal data (paths, user name) in the window title or path bar;
- wallpaper bleeding at the corners;
- blurry upscales.

---

## 9. App preview video (R9)

### 9.1 Apple's spec (from `04` section 3.2)

| Property | Value |
|---|---|
| Resolution | **1920x1080**, landscape |
| Length | **15-30 s** (target 26 s) |
| Codec | H.264 High Profile 4.0, progressive, 10-12 Mbps, .mov/.m4v/.mp4. ProRes 422 HQ is allowed, but about 220 Mbps for 26 s is about 715 MB, over the cap, so don't use it. |
| Frame rate | at most 30 fps (use exactly 30) |
| Size | at most 500 MB |
| Audio | stereo AAC 256 kbps, 44.1/48 kHz. Use a **silent track**: Segue makes no sound, and the preview autoplays muted. |
| Count | up to 3 per localization; ship 1 |
| Content | screen capture of the app only (2.3.4). Text overlays are allowed. No device frames or non-app end cards (an end card is not app footage; review risk). |
| Processing | up to 24 h after upload |

### 9.2 Storyboard (live mode first, readable without sound)

| t (s) | Action (keyboard-driven, no pointer) | Caption overlay |
|---|---|---|
| 0.0-3.5 | Setlist builder on "JamFest Opener" (8.4.1); the running total is visible; Start Show with Cmd-Return | "Build tonight's set." |
| 3.5-9.0 | Stage opens on song 1: auto-fit columns, header, progress dots; hold so the viewer can read | "Every song fits the screen." |
| 9.0-13.0 | Right Arrow to song 2; A starts auto-scroll; it scrolls smoothly | "Auto-scroll, hands free." |
| 13.0-19.0 | Cmd-K; type `kitabon` at a human pace (about 8 chars/s); "Kitaabon Wali Gali" appears; queue it; the footer shows "Request" | "Take a request mid-set." |
| 19.0-23.5 | R plays the request: the romanized Hindi Welcome song, chords over the syllables | "Romanized Hindi, chords on the syllable." |
| 23.5-26.0 | `?` shows the key overlay briefly, then closes; hold on the stage | "Your chart, your set, your cue." |

The poster frame (chosen in App Store Connect) is a frame at about 6 s, showing the full stage view.

> **As built (2026-10-20).** The cut is five scenes, 23 s, each caption timed from a `scene-<id>` marker the test writes (so captions stay on their scene however long the app takes): Build tonight's set (the JamFest Opener builder, Command-Return, the checklist) -> Every song fits the screen (stage on song 3, Ferry Lights, two columns, Up next) -> Take a request mid-set (Command-K, `kitabon`, queued; the footer shows the request) -> Romanized Hindi, chords on the syllable (R plays Kitaabon Wali Gali) -> Your chart, your set, your cue (`?`, then back). The auto-scroll scene was dropped: at the song's own pace a few seconds of auto-scroll move the chart by a few pixels, so it never read on video, and speeding it up would misrepresent the app. The footage is scaled to 1664x936 under a 112 px `ground.dark` caption band, so captions never cover the stage header (no scrim). Recording is `scripts/record-app.swift` (ScreenCaptureKit, Segue's windows only), not `screencapture -v`: that hung past its time limit after the stage had been up, and a whole-screen recording also caught other apps and XCUITest's "Automation Running" banner.

### 9.3 Capture method

**Primary: scripted.** `AppStorePreviewTests.testPreviewStoryboard` drives the storyboard above with explicit holds. It runs while `screencapture` records the window rectangle:

- Launch flags as in 8.2, plus `-SegueStageWindowed YES -SegueWindowFrame 36,60,1440,810` (16:9, 2880x1620 px on Retina) and `-SegueAppearance dark`.
- `make preview` runs `screencapture -v -V 40 -R36,60,1440,810 .build/preview/raw.mov` in the background, then the test plan `PreviewTests`, then waits for `screencapture` to exit.
- Holds use `XCTWaiter` with a small helper `hold(seconds:)`. This is the one place a timed wait is correct, because pacing is the point.
- The stage is keyboard-driven, so no cursor appears.

Why scripted:

- re-shooting after a UI change is one command;
- every take is identical;
- it matches R10's "from the XCUITest suite" spirit.

Requirements and fallbacks:

- **[RYAN]** must grant Screen Recording permission to the terminal app that runs `make`, the first time (section 13).
- Xcode's built-in UI-test video recording is not used (B-33 picked the scripted `screencapture` path).
- **Fallback: manual.** Ryan records the same storyboard in QuickTime Player:
  1. Open File > New Screen Recording.
  2. Choose "Record Selected Portion" and drag a 16:9 rectangle over the window.
  3. Click Record.
  4. Save to `.build/preview/raw.mov`.
  5. Run `make preview-edit`.

### 9.4 Editing toolchain (free, local, no global installs)

- **Install ffmpeg through mise.** Add `ffmpeg` to `.mise.toml`. The registry resolves it to `conda:ffmpeg` (prebuilt) or the asdf plugin, and `mise ls-remote ffmpeg` shows 9.0.x. Pin an exact version.
  - **Check `libx264`.** Verify that build has `libx264` (`mise exec -- ffmpeg -encoders | grep libx264`).
  - **If it is missing,** use `h264_videotoolbox` (`-profile:v high -level 4.0 -b:v 11M`) or Apple's built-in `avconvert`. Record which one in the script header.
- **Caption overlays** are rendered by the same compositor (`compose-screenshots.swift --video-captions`) as 1920x1080 transparent PNGs, so type and colours match the screenshots exactly and ffmpeg needs no freetype or `drawtext`. Each caption sits on a soft `ground.dark` scrim in the top band, and the stage header must stay readable.
- **`scripts/make-preview.sh` steps** (ffmpeg through `mise exec --`):
  1. Trim to the storyboard window with `-ss/-to`.
  2. `scale=1920:1080:flags=lanczos,fps=30,format=yuv420p`.
  3. Chain `overlay=enable='between(t,a,b)'` per caption PNG, with 150 ms fades (`fade` on the overlay input). Brand motion rule: nothing bounces.
  4. Add a silent track: `-f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000 -shortest -c:a aac -b:a 256k`.
  5. Encode: `-c:v libx264 -profile:v high -level:v 4.0 -b:v 11M -maxrate 12M -bufsize 24M -r 30 -movflags +faststart` to `.build/preview/segue-preview-en-US.mp4`.
  6. Verify with `ffprobe`: 1920x1080, `r_frame_rate` at most 30, duration 15-30 s, H.264 High@4.0, audio AAC stereo 48 kHz, file size at most 500 MB. Exit non-zero on any miss.
- **Make targets:**
  - `make preview` runs capture, edit and verify;
  - `make preview-edit` runs edit and verify from an existing `raw.mov`.

  Both are listed in `.PHONY`, and neither is in `check`.

### 9.5 App Review attachment video (B-31)

A 60-90 s walkthrough attached under App Review Information, so a reviewer who cannot find a feature (2.1) sees it working. It is a review aid, not store art: no captions, no scrim, no music.

Content, in order, matching the review notes (4.6) step for step:

1. First launch on a clean container: the three Welcome steps (library, Welcome songs, the two consent questions, Continue).
2. Library: select a song, transpose, search `kitabon`.
3. Editor: visual mode, drag a chord; close (autosave).
4. Setlist: open "Welcome Set", reorder.
5. Stage: Cmd-Return, checklist, next song, auto-scroll, `?` overlay, Cmd-Period > End Show.
6. Help > Report a Problem...: show the preview, then cancel without sending.

Capture: **[RYAN]** records it with QuickTime Player (File > New Screen Recording > Record Selected Portion, the main window plus room for sheets) during the 14.2 clean-account pass on the TestFlight build. That is the only place the true first run (real `NSOpenPanel`, empty container, consent) happens without test flags. Save to `.build/review/raw.mov`.

Edit: `make review-video` runs `scripts/make-preview.sh --review .build/review/raw.mov`:

- trim (`-ss/-to` from `REVIEW_IN` / `REVIEW_OUT` environment variables), speed up idle stretches only by cutting, never by time-stretching;
- `scale=1920:-2:flags=lanczos,fps=30,format=yuv420p`, H.264 High, 8 Mbps, silent AAC track, `+faststart`, to `.build/review/segue-review-walkthrough.mp4`;
- `ffprobe` gate: duration 60-90 s, at most 30 fps, H.264, file at most 200 MB (Apple's attachment limit is **UNVERIFIED**; 200 MB keeps well clear of any plausible cap).

If App Store Connect rejects the file on the day, note the limit it reports here and adjust the gate.

---

## 10. Metadata upload: fastlane `deliver` via mise (B-30)

Decided: `deliver` for text and screenshots, everything else by hand. The survey that led there:

| Option | Covers | Cost / licence | Verdict |
|---|---|---|---|
| By hand (paste from `store/`) | everything | free | Always the fallback; required anyway for some fields (below) |
| **fastlane `deliver`** (`platform: "osx"`, `--skip_binary_upload`) authenticating with the R13 API key (`api_key_path`) | name, subtitle, promo, description, keywords, URLs, copyright, categories, review info, screenshots | free, MIT; Ruby + fastlane via mise (`ruby` core plugin + `gem:fastlane` backend), never global | **Chosen** for the covered fields |
| Own Swift client for the App Store Connect API | same as `deliver` plus whatever the public API exposes | free; a build session of code | Build only if `deliver` breaks against current App Store Connect |
| Open-source ASC CLIs (e.g. a Go `asc` CLI on GitHub) | varies | free | Maturity **UNVERIFIED**; reference only |

Keep `store/` canonical in git in `deliver`'s layout, and upload with `make store-upload`. That gives the automated path from day one, makes store text a reviewed diff, and re-uploads screenshots with one command.

`deliver` shows an HTML preview and asks for confirmation before uploading. Keep that confirmation, so never pass `--force` from `make`.

`Deliverfile` settings:

- `submit_for_review false`;
- `automatic_release false` (manual release, A51);
- `overwrite_screenshots true`;
- `run_precheck_before_submit false`;
- the phone number from `ENV` (`SEGUE_REVIEW_PHONE`);
- the API key read from 1Password at run time the same way WS1's `make upload` does (R13), never written into the repo; the temporary key file is deleted on exit.

Do these by hand regardless. They are not covered by `deliver`, or not via the API key, or one-off:

- App Privacy (section 6): not in the public API; fastlane's privacy action needs an Apple ID login.
- Age rating (section 5): the new 2025 questionnaire's support in fastlane is **UNVERIFIED**.
- Accessibility labels (section 7).
- Preview video upload: `deliver` app-preview support for Mac is **UNVERIFIED**; drag it in.
- Review attachment video (9.5).
- Pricing, availability (all except China mainland, A47), DSA, content rights and the app record.

Verify `deliver` option names against `mise exec -- fastlane deliver --help` at the pinned version before writing the `Deliverfile`.

---

## 11. File-level changes

| File | Change |
|---|---|
| `store/metadata/en-US/name.txt`, `subtitle.txt`, `promotional_text.txt`, `description.txt`, `keywords.txt`, `support_url.txt`, `marketing_url.txt`, `privacy_url.txt` | new; text from section 4 |
| `store/metadata/copyright.txt` (`2026 Ryan Rony Dsilva`, R30), `primary_category.txt` (`MUSIC`), `secondary_category.txt` (`PRODUCTIVITY`) | new |
| `store/metadata/review_information/{first_name,last_name,email_address,notes}.txt` | new (`Ryan`, `Dsilva`, `segue@ryandsilva.dev`, 4.6 notes); phone via `ENV`, not committed |
| `store/screenshots.json` | new; captions and per-slot appearance (8.4, 8.6) |
| `store/Deliverfile` | new (section 10) |
| `scripts/check-store-metadata.swift` | new. Fails on: name/subtitle over 30 chars; promo over 170; description over 4,000; keywords over 100 bytes, any term of 2 chars or fewer, a term repeating a name/subtitle word, or a space after a comma; review notes over 4,000 bytes; any em dash or en dash; banned words (competitor names from `04` section 5, iPhone, iPad, Android, Windows, beta, "collects no data"); captions in `screenshots.json` over 40 (headline) or 64 (subline) chars; `copyright.txt` not equal to the R30 name (minus the symbol); any `store/metadata/<locale>` directory other than `en-US` (A46); "Report a Bug" in the notes (the item is "Report a Problem...", I-5). |
| `scripts/compose-screenshots.swift` | new (8.6, plus `--video-captions` for 9.4) |
| `scripts/make-preview.sh` | new (9.4, plus `--review` mode for 9.5) |
| `scripts/xcodebuild.sh` | honour `SEGUE_RESULT_BUNDLE` |
| `scripts/verify-appstore.sh` | add WS5's own flag strings (`-SegueScreenshotLibrary`, `-SegueAppearance`, `-SegueWindowFrame`, `-SegueStageWindowed`, `-SegueFixedClock`) and one screenshot-only song title to WS1's absent-from-Release grep list (I-12) |
| `App/Sources/LaunchOptions.swift`, `App/Sources/SegueApp.swift`, and the owning SegueUI types (window frame, stage presentation, `AppearanceStore`) | Debug-only flags from 8.2; the screenshot-folder constant shared with WS2b's `-SegueSeedWelcome` |
| `App/Sources/Debug/ScreenshotSongs.swift` | new, `#if DEBUG` only: approved screenshot-only songs and the "JamFest Opener" setlist (8.4.1) |
| `UITests/AppStore/AppStoreScreenshotTests.swift`, `AppStorePreviewTests.swift`, `ScreenshotSupport.swift`, `ScreenshotTests.xctestplan`, `PreviewTests.xctestplan` | new |
| `Project.swift` | `SegueAppStoreUITests` target; `appStoreScheme` test action with both plans |
| `Makefile` | `store-check` (added to `check`), `screenshots`, `preview`, `preview-edit`, `review-video`, `store-upload`; `.PHONY` |
| `.mise.toml` | `ffmpeg`, `ruby`, `"gem:fastlane"` pinned |
| `.gitignore` | `store/report.xml`, `store/*.html` (deliver's preview), `fastlane/` if it creates one |

Do not touch `CHANGELOG.md` or any generated file by hand.

## 12. Step order (session plan)

1. **Preflight.**
   - Read the inputs.
   - Confirm the section 17 questions are answered (in particular the screenshot-only titles before step 4); if any is still open, ask before the step that needs it.
   - Check the preconditions in section 2.
   - `make generate && make quick`, to get a green baseline.
2. **Metadata and gate.** Create `store/` and `check-store-metadata.swift`; wire `make store-check` into `check`.
   - Commit: "Add App Store metadata and store-check gate".
3. **Claim pass (4.4)** on `Debug-AppStore` from a reset state. Prune unshipped lines and re-run `store-check`.
   - Commit.
4. **Debug hooks (8.2)**, `ScreenshotSongs.swift` with the approved titles (8.4.1), and the `verify-appstore` assertion.
   - `make build-appstore verify-appstore`.
   - Commit.
5. **Test target, plans and the first shot test** (`01-stage`). Get one shot end to end through export, then:
   - write the other seven;
   - run `make screenshots` twice, and check the raw images are identical in content (determinism);
   - commit.
6. **Compositor directions (8.6).** Render the A/B/C samples. **Stop and show Ryan** (R7 in section 13), then lock the direction and compose the full set. Pixel review (8.8).
   - Commit.
7. **Preview (section 9).** ffmpeg via mise, the storyboard test, `make preview`. **Show Ryan the cut** (R8); iterate. Add `--review` mode and `make review-video` (9.5); test it on a short throwaway QuickTime clip until Ryan's real take exists.
   - Commit.
8. **Upload tooling (section 10).** Ruby and fastlane via mise, `Deliverfile`, `make store-upload`.
   - Dry-run to the HTML preview only, if the app record exists.
   - Commit.
9. **Hand over** sections 13 and 14 to Ryan, with section 6 diffed against WS3 10.2 at HEAD and the label list (section 7) filled from the audit.
10. **Phase gate.** Full `make check` (includes `e2e`) once at the end, not after every step.

## 13. [RYAN] manual steps

| # | When | Step | Click path |
|---|---|---|---|
| R1 | before the session | Answer section 17 (the screenshot-only titles are approved by R128; question 1 settles the one title-search hit) | - |
| R2 | before step 8 | Confirm App Store Connect access is live, the 2026-10-13 DPLA is accepted, and DSA non-trader is declared (R4) | appstoreconnect.apple.com > Business > Agreements; Business > Agreements > Compliance > Digital Services Act |
| R3 | before step 8 | Create the app record if the signing/upload workstream has not: macOS, name `Segue - Setlists & Chords`, English (U.S.), bundle `dev.ryandsilva.segue`, SKU `segue-macos` (B-33), User Access Full. Then note the numeric Apple ID (App Information) and hand it to WS2a for Help > Rate Segue on the App Store (A35) and to WS4 for the badge link | Apps > + > New App |
| R4 | before step 8 | Set the price to Free; availability all countries or regions **except China mainland** (A47) | Apps > Segue > Pricing and Availability > Price Schedule > Free; Availability > select all, then untick China mainland |
| R5 | before step 8 | Put the R13 `.p8` key, Key ID and Issuer ID where `make store-upload` reads them, as the signing/upload spec defines (1Password, never the repo) | 1Password |
| R6 | first `make preview` | Grant Screen Recording to the terminal app | System Settings > Privacy & Security > Screen & System Audio Recording > + > your terminal; relaunch it |
| R7 | step 6 | Pick screenshot direction A, B or C (the per-slot appearance is fixed at 5 dark / 4 light, A49, R129) | contact sheet in `.build/screenshots/directions/` |
| R8 | step 7 | Approve the preview cut | `.build/preview/segue-preview-en-US.mp4` |
| R9 | after upload | Enter the age rating (section 5) | Apps > Segue > App Information > Age Rating > Edit |
| R10 | after upload | Enter App Privacy (section 6, as diffed against WS3 10.2), then Publish | Apps > Segue > App Privacy > Get Started/Edit |
| R11 | after upload | Enter the accessibility labels the audit earned (section 7) | Apps > Segue > App Accessibility > Add Accessibility Support > macOS |
| R12 | after upload | Categories Music / Productivity; content rights "Yes ... I have the necessary rights" (R129); check the license agreement is the Apple standard EULA | Apps > Segue > App Information |
| R13 | after upload | Upload the preview video and set its poster frame (about 6 s) | Apps > Segue > macOS App > 0.5 > App Previews and Screenshots > drag the .mp4 > Edit poster frame |
| R14 | after upload | Enter the review contact phone, if not via `ENV`; attach the walkthrough video (9.5) | Apps > Segue > macOS App > 0.5 > App Review Information |
| R16 | 14.2 step 5 | Record the raw review walkthrough with QuickTime on the clean account (9.5), save to `.build/review/raw.mov`, then run `make review-video` | QuickTime Player > File > New Screen Recording |
| R15 | runbook | Everything in section 14 | - |

The click paths follow Apple's help pages as read on 2026-10-17. Apple renames sidebar items, so match by meaning.

## 14. Submission runbook

### 14.1 Gate before any upload

All of these must hold:

- `make check` is green, including `verify-appstore`;
- `make store-check` is green;
- the website URLs return 200;
- the section 4.4 claim table is fully ticked;
- the build number is incremented (R5: every upload increments it).

### 14.2 TestFlight internal test on Ryan's Mac (R6)

1. Upload with WS1's targets (`make archive && make validate`, then `make upload` with the R13 key; B-9 allows an early pipeline-proving upload, but the build tested here is the feature-complete one). Wait for the "has completed processing" email (minutes to about an hour). Builds expire after 90 days.
2. **[RYAN]** Add the build to an internal testing group with yourself in it. Click path: Apps > Segue > TestFlight > Internal Testing > + > group "Ryan" > Builds > +. Internal testers need no Beta App Review.
3. **[RYAN]** Install the TestFlight app from the Mac App Store, accept the invite and install Segue.
4. **[RYAN]** Before installing (R40, A60; the exact commands are WS1 [RYAN] step 10):
   - quit every Segue build;
   - move the existing `~/Library/Containers/dev.ryandsilva.segue` container aside (rename it, do not delete it), so the TestFlight build walks the reviewer's real first-run path;
   - copy `shape-library.json` and `bindings.json` from that old container into the Personal (`dev.ryandsilva.segue.personal`) container, so the daily build keeps its shapes and bindings;
   - **move any locally built Segue.app out of `/Applications`**. The Personal flavor has its own bundle ID (R11) but the same `Segue.app` file name, and the TestFlight install would collide. The collision behaviour is **UNVERIFIED**; avoid it.
5. **Clean-machine pass.** Use a fresh macOS user account (System Settings > Users & Groups > Add User), to simulate the reviewer. Run every "Things to try" step in the review notes **word for word**, and fix the notes where they are wrong. Also check:
   - the Welcome flow runs library, Welcome songs, then consent (A10); the consent step shows two rows with equal buttons, Continue enables only when both are answered, and Settings > Privacy has both toggles;
   - Help > Privacy Policy, Terms of Use, Segue Help and Request a Feature... all open in the browser and resolve;
   - Help > Report a Problem... shows the full payload preview, the "attach current song" box is unticked, the email field is optional, and Send succeeds;
   - Settings > Appearance switches Match System / Light / Dark (R36);
   - a delete lands in the Trash;
   - a drag-in import works;
   - Window > Segue Library (Cmd-0) reopens the main window after closing it (A32);
   - Start Show with no Shortcuts configured shows no error and no Gig Mode rows in the checklist (R18, A37);
   - record the review walkthrough during this pass (R16 in section 13, 9.5).

### 14.3 Real-gig checklist (R6), on the TestFlight build

Before the gig:

- [ ] Quit the Personal build. Both apps must never run against the same library folder at once.
- [ ] Point the TestFlight build at the real library (Choose Existing Folder...). Search, open, edit and autosave work on real songs.
- [ ] Build the real setlist; check the running time against the target.
- [ ] Set up the Gig Mode Shortcuts if you use them; the Focus row ticks only after a confirmed successful run, or by its manual Done fallback (R18, R35).
- [ ] Laptop on battery: run a full rehearsal of the set, and confirm the display never sleeps.

At the gig:

- [ ] Start Show; check the pre-show checklist.
- [ ] Play the full set. Note any song that did not fit, scrolled wrongly, or needed the mouse.
- [ ] Take at least one request via quick search, and play it from the queue.
- [ ] Skip and reorder at least once.
- [ ] End the show; the gig log entry is correct.

After the gig:

- [ ] The review prompt is requested after the 1st completed gig, once per app version, after the end-of-show flow with the stage closed, never during a show (R20, A12). It never appears in TestFlight, so verify it on a development build (`-SegueCompletedGigs 0`, end one gig) instead.
- [ ] Force-quit mid-song once (Activity Monitor) during the rehearsal or soundcheck; relaunch and land on the same song and scroll.
- [ ] Write findings to `JOURNAL.md`. Every finding becomes a fix and a new build (with a new build number), then re-run 14.2 step 5 on that build.
- [ ] Ship only a build that has been through a gig or, for fixes after the gig, through 14.2 step 5.

### 14.4 Submit

1. `make store-upload` (or paste by hand). Then **[RYAN]** does R9-R14 in section 13.
2. **[RYAN]** Open Apps > Segue > macOS App > 0.5 (Prepare for Submission). Check every field against `store/` and the screenshots (all 8, in order). Then:
   - Build > + > pick the **exact TestFlight build that went through the gig**;
   - App Review Information: check the notes, attach `.build/review/segue-review-walkthrough.mp4` (B-31);
   - Version Release: **"Manually release this version"** (A51);
   - Add for Review > Submit to App Review.
3. Apple's figures: 50% are reviewed within 24 h, 90% within 48 h.

### 14.5 Release (manual, A51)

The version is set to **"Manually release this version"**, so approval does not publish it. Ryan picks the moment, in this order:

1. **[RYAN]** Apps > Segue > macOS App > 0.5 > Release This Version.
2. Once the listing is reachable, flip the website from "Coming soon to the Mac App Store" to the badge (WS4: `appStore.status` to `"live"` with the Apple ID), and publish the changelog and press page.

Phased release applies to updates only, so it is n/a for 0.5.

After release:

- **[RYAN]** Open the Mac App Store and search for "Segue setlists" on the US storefront.
- Check the listing renders: screenshots, preview, privacy label, accessibility labels.
- Check the website badge links to the live listing.
- Watch Xcode Organizer and Sentry for 48 h.

### 14.6 On rejection

1. **[RYAN]** Read the message in App Store Connect > Apps > Segue > App Review (the Resolution Center thread). Note the guideline number.
2. Classify it:
   - **Metadata only** (text, screenshots, privacy label, age rating): fix in `store/` (keep git canonical) or in App Store Connect. Run `make store-check` first, then reply in the thread and resubmit the same build.
   - **Binary:** fix in code, increment the build number, upload, run 14.2 step 5 on it, then attach the new build and resubmit. Explain the change in the thread.
   - **Misunderstanding** (the reviewer could not find a feature, or misread network use): reply with specific steps and an attachment video. Fold the same text into the review notes so it doesn't recur.
   - **Disagreement on the guideline:** reply first. If still rejected, appeal via App Store Connect > Contact Us > App Review > "Appeal an App Review decision" (the App Review Board).
3. Log each rejection, with the guideline, the fix and the turnaround, in `JOURNAL.md`.
4. Likely 0.5 triggers, all pre-empted above:
   - 5.1.1 (consent or privacy link; label vs policy mismatch);
   - Guideline 4 window reopen;
   - 2.1 "could not find feature";
   - 2.3 a claim not in the app;
   - 2.2 beta wording.

## 15. Acceptance criteria

- [ ] `make store-check` passes and runs in `make check`. A deliberately over-long subtitle or an em dash makes it fail; test once, then revert.
- [ ] Every description line is backed by a ticked row in 4.4 on the App Store flavor; no unshipped claim remains.
- [ ] Keywords are exactly the R37 set in 4.5 (97 bytes).
- [ ] `make screenshots` from a clean `.build/` produces 9 PNGs in `.build/screenshots/final/en-US/`:
  - each 2880x1800, `hasAlpha: no`, sRGB;
  - captions from `store/screenshots.json`;
  - the chosen direction;
  - at least one dark shot.
- [ ] Two consecutive `make screenshots` runs produce visually identical images.
- [ ] Screenshots show only Welcome-library songs and the approved screenshot-only songs (8.4.1), and no personal-module UI.
- [ ] The shipped mix is 5 dark, 4 light (A49, R129), as in 8.4.
- [ ] `strings` on the Release-AppStore binary finds none of WS5's flags and no screenshot-only song title (`verify-appstore`).
- [ ] `make review-video` produces a 60-90 s walkthrough that passes its ffprobe gate (9.5).
- [ ] `make preview` (or `make preview-edit` on a manual take) produces an mp4 that passes the ffprobe gate: 1920x1080, 30 fps, 15-30 s, H.264 High@4.0, stereo AAC, at most 500 MB. Ryan has approved it.
- [ ] `make store-upload` reaches deliver's HTML preview with the correct text and screenshots (actual upload when the record exists).
- [ ] Sections 5, 6 and 7 are entered in App Store Connect; section 6 matches WS3 10.2, `PrivacyInfo.xcprivacy` and `/privacy` (three-way diff done).
- [ ] Availability is every storefront except China mainland (A47); SKU `segue-macos`.
- [ ] TestFlight build installed; 14.2 and 14.3 done; submitted with manual release (A51) and the walkthrough attachment.
- [ ] `make check` is green at the end; all commits are local and signed; nothing is pushed.

## 16. Risks

| Risk | Mitigation |
|---|---|
| Description claims a feature that slipped from 0.5 (2.3.1 rejection) | 4.4 claim pass on the built flavor; prune, don't hope |
| Privacy label drifts from WS3 or under-discloses after a vendor change | WS3 10.2 is the single source; three-way diff of label, policy and `PrivacyInfo.xcprivacy` before Publish; re-run section 6 on every vendor change (editable anytime) |
| "beta"/"0.5" read as a beta app (2.2) | no beta wording anywhere (store-check); version number alone is fine |
| Screenshot hooks or screenshot-only songs leak into Release | `#if DEBUG` on flag strings and `ScreenshotSongs.swift` + `verify-appstore` grep for flags and a title |
| Review notes describe a first run that differs from the build (2.1) | notes follow WS2b's order (A10); 14.2 word-for-word pass on a clean account; walkthrough video recorded on the same pass |
| Screenshot-only title collides with a real song | title search before step 4; any hit drops the title |
| Screenshot run touches Ryan's real App Store container (same bundle ID as TestFlight/store installs) | library lives in a dedicated container subfolder, `-SegueTestDefaults` suite, never the real bookmark; never use `-SegueResetState` without the test defaults suite in this target |
| Flaky captures (focus stolen on a shared desktop, mid-animation frames) | `E2E.bringToFront` before every input; settle-waits on elements; Reduce Motion-style state for shots; no retries, fix root cause |
| macOS 26 window corner radius / desktop bleed at corners | measured radius in JSON, 1 px inset mask |
| Retina scale differs on another Mac (non-2x) | tests assert 2880x1800 raw and fail loudly; run on Ryan's 14" MBP |
| Windowed stage differs from full-screen stage | flag only changes presentation; compare one windowed vs full-screen capture by eye in step 5 |
| `conda` ffmpeg lacks libx264 | `h264_videotoolbox` or `avconvert` fallback, recorded in script |
| Preview with captions/scrim judged "not app footage" | captions are allowed overlays; no device frame, no end card |
| fastlane breaks against current ASC or new questionnaire | text and screenshots only via deliver; paste from `store/` as fallback |
| Name "Segue - Setlists & Chords" unavailable at record creation | 01 D1 fallbacks; ask Ryan, don't pick |
| TestFlight and Personal both writing one library folder | quit Personal during TestFlight use; checklist item |
| Lyrics in Welcome songs not original or not clean (5.2.1, age rating) | read every visible lyric in raw captures; WS2b owns the text, flag issues to Ryan |
| Contact phone committed to a repo | `ENV` only, never in `store/` |

## 17. Open questions for Ryan

None open. All earlier WS5 questions are closed (A46-A51, B-30 to B-33, R30, R37, R128; see the table at the top). The review walkthrough is captured by Ryan with QuickTime on the clean-account TestFlight pass (section 9.5). The eight questions P3-9 opened (evidence: `docs/research/phase3-store-ai.md`, Q8, Q5, Q1, Q2/Q3, Q4, Q6 and Q7) are ruled by **R129** (2026-10-20) and applied in place above:

1. **The R128 title-search hit:** replaced by "Northbound at First Light" (Bb, 76, 4:30) (8.4.1).
2. **Screenshots:** a 9th shot, the paste review sheet (Light), headline "Paste a song from anywhere.", subline "Segue converts it. You check it before it saves." (8.4).
3. **Age rating with AI:** answer as section 5 (no AI item exists); 4+, no override.
4. **Content rights and App Privacy with the model download:** content rights "Yes, it contains, shows, or accesses third-party content, and I have the necessary rights" (4.1); App Privacy label unchanged (section 6).
5. **"Apple Intelligence" wording:** referential use only ("works with Apple Intelligence"), never in a feature name, no trademark symbol, plus "Apple Intelligence is a trademark of Apple Inc." on /acknowledgements.
6. **Keywords:** R37 unchanged (4.5).
7. **Review notes:** the 4.6 rewrite (3,585 / 4,000 bytes).
8. **Promotional text:** the paste-led line in 4.2 (162 chars).
