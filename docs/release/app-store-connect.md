# App Store Connect, top to bottom (Segue 0.5)

One file to follow once the App Store Connect account works (it is blocked today with `STATE_ERROR.DPLA_OUTDATED_ERROR`; Apple is resolving it). Every value is in the order App Store Connect asks for it, with its limit and count, and the rule it comes from. Values are copied from `docs/release/specs/WS5-store-listing.md`, `docs/release/decisions.md` and the code (`Project.swift`, `Config/Version.xcconfig`, `scripts/release.sh`); WS5 stays canonical, so if the two ever differ, WS5 wins and this file is corrected.

Every value that waited on a decision is ruled (R129, 2026-10-20: WS5 section 17 questions 1-8); the evidence is in `docs/research/phase3-store-ai.md`. Apple renames sidebar items now and then: match by meaning.

Counts: characters as App Store Connect counts them; bytes as UTF-8 (`len(s.encode())`). Every value below is plain ASCII except where noted.

## 1. Account prerequisites

| # | Step | Where | Value | Source |
|---|---|---|---|---|
| 1.1 | Accept the latest Apple Developer Program License Agreement (Account Holder only). This is what clears `DPLA_OUTDATED_ERROR`. | appstoreconnect.apple.com > Business > Agreements (also prompted at developer.apple.com/account) | Accept | 01 step 4, R1 |
| 1.2 | Free Apps: covered by the DPLA, nothing to sign. Leave **Paid Apps** unsigned (no banking or tax) | Business > Agreements | Paid Apps: not signed | R2, 01 D2 |
| 1.3 | EU Digital Services Act status | Business > Agreements > Compliance > Digital Services Act > Complete Compliance Requirements | **Not a trader** | R4 |
| 1.4 | App Store Connect API key for `make validate` / `make upload` | Users and Access > Integrations > App Store Connect API > Request Access (if shown), then Team Keys > + | Name `Segue uploads`; Access **App Manager**. Note the **Issuer ID** (top of the page) and the **Key ID**; Download API Key (only once) | R13, WS1 3.7, B-8 |
| 1.5 | Store the key in 1Password, never in the repo | 1Password, vault **`Private`**, item **`Segue ASC API Key`** (category API Credential) | text field **`key_id`** = Key ID; text field **`issuer_id`** = Issuer ID; file attachment renamed **`AuthKey.p8`**. Then Trash the downloaded `.p8` and empty the Trash. Other names: set `SEGUE_ASC_OP_VAULT` / `SEGUE_ASC_OP_ITEM` | R46, `scripts/release.sh` |
| 1.6 | Check from Terminal.app (not an agent shell) | Terminal.app | `op read "op://Private/Segue ASC API Key/key_id"` prints the Key ID | R46 |

Certificates and profiles (`Apple Distribution`, `3rd Party Mac Developer Installer`, profiles `Segue Mac App Store` and `Segue Mac App Store QuickLook`) are WS1 [RYAN] steps 2-6; they do not need App Store Connect.

## 2. Create the app record

Apps > + > New App (needs 1.1 done).

| Field | Value | Limit / count | Source |
|---|---|---|---|
| Platforms | **macOS** only | | R14 |
| Name | `Segue - Setlists & Chords` | 25 chars / 25 bytes, max 30 | R3 |
| Primary Language | English (U.S.) | | R8, A46 |
| Bundle ID | `dev.ryandsilva.segue` (the explicit App ID from WS1 step 6; locked once a build is uploaded) | | R11 |
| SKU | `segue-macos` (permanent, never reusable) | | B-33 |
| User Access | Full Access | | 01 step 14 |

Alternative: the record can also be created from Xcode > Organizer > Distribute App on the first upload, but create it here so the SKU and name are exactly these. If the name is taken, stop and ask (fallbacks in `docs/release/research/01-account-and-connect.md` D1). After creating it, copy the numeric **Apple ID** (App Information) for the website badge (`content/site.json` `appStore.appleId`) and Help > Rate Segue (A35).

## 3. App Information (sidebar, General)

| Field | Value | Limit / count | Source |
|---|---|---|---|
| Name | `Segue - Setlists & Chords` | 25 chars / 25 bytes | R3 |
| Subtitle | `Lyrics & chords for live gigs` | 29 chars / 29 bytes, max 30 | R3 |
| Category, primary | Music | matches `LSApplicationCategoryType = public.app-category.music` | R3 |
| Category, secondary | Productivity | | R3 |
| Content Rights | "Yes, it contains, shows, or accesses third-party content, and I have the necessary rights" (the app fetches the Apache-2.0 Qwen3 weights on request; licence and credits ship) | | R129, R66, research 2 |
| Age Rating | section 3.1 below | expected **4+** | WS5 5 |
| License Agreement | Apple's Standard License Agreement (leave the default) | | R7 |
| Regulated medical device (if asked) | No | | 01 step 13 |
| Made for Kids (in the age rating flow) | Not Applicable (no override) | | WS5 4.1 |

### 3.1 Age rating questionnaire (App Information > Age Ratings > Set Up Age Ratings)

The questionnaire has no AI item (read at source 2026-10-20). Answer as below: **4+**, no override (R129).

| Item | Answer | Why |
|---|---|---|
| Parental Controls | No | none |
| Age Assurance | No | none |
| Unrestricted Web Access | No | links open in the default browser; the model download is one fixed URL |
| User-Generated Content | No | "broad distribution" only; songs and pastes stay on the Mac |
| Social Media | No | |
| Social Media Disabled for Users Under 13 | No (not applicable) | |
| Messaging and Chat | No | |
| Advertising | No | R2 |
| Profanity or Crude Humor | None | Welcome songs are clean |
| Horror/Fear Themes | None | |
| Alcohol, Tobacco, or Drug Use or References | None | |
| Medical or Treatment Information | None | |
| Health or Wellness Topics | No / None | |
| Mature or Suggestive Themes | None | |
| Sexual Content or Nudity | None | |
| Graphic Sexual Content and Nudity | None | |
| Cartoon or Fantasy Violence | None | |
| Realistic Violence | None | |
| Prolonged Graphic or Sadistic Realistic Violence | None | |
| Guns or Other Weapons | None | |
| Gambling | No | |
| Simulated Gambling | None | |
| Contests | None | |
| Loot Boxes | No | |
| Override to Higher Age Rating | Not Applicable | |

## 4. Pricing and Availability

| Field | Value | Source |
|---|---|---|
| Price | Free (USD 0.00) | R2 |
| In-App Purchases | none | R2 |
| Availability | All countries or regions **except China mainland** (select all, untick China mainland) | A47 |
| Pre-order | No | WS5 |
| Mac availability of iPhone/iPad apps | n/a (Mac app) | |

## 5. App Privacy (sidebar, General)

Privacy Policy URL: `https://segue.ryandsilva.dev/privacy`. Privacy Choices URL: leave empty. Get Started > **"Yes, we collect data from this app"**, then tick these nine types and Set Up each exactly as below. Every row: **Tracking: No**. Then Publish. Source: WS3 10.2 (single source of truth) = WS5 section 6. The optional Hugging Face model download and Apple Intelligence add no rows (research 3; R129: label unchanged).

| Data type | Purposes | Linked to the user | Tracking |
|---|---|---|---|
| Usage Data > Product Interaction | Analytics | No | No |
| Identifiers > Device ID | Analytics; App Functionality | No | No |
| Location > Coarse Location | Analytics | No | No |
| Diagnostics > Crash Data | App Functionality | Yes | No |
| Diagnostics > Performance Data | App Functionality | Yes | No |
| Diagnostics > Other Diagnostic Data | App Functionality | Yes | No |
| User Content > Customer Support | App Functionality | Yes | No |
| User Content > Other User Content | App Functionality | Yes | No |
| Contact Info > Email Address | App Functionality | Yes | No |

Usage data and identifiers are sent only after the user chooses Share; crash data only after Send; the bug-report types only when the user presses Send in Report a Problem... (R25, R26, R22). Do not claim the optional-disclosure exemption for bug reports (WS5 6).

## 6. App Accessibility (sidebar, General)

Claim only what `docs/release/accessibility-audit.md` records as walked and passed for every common task, including the phase 3 surfaces (R15, R79, WS5 7). Today the VoiceOver, Voice Control and Full Keyboard Access walks are still Ryan's (checklist in `docs/release/walkthrough.md`), so **claim nothing until they pass**. Accessibility URL: leave empty (B-32).

## 7. The version page (macOS App > 0.5, Prepare for Submission)

| Field | Value | Limit / count | Source |
|---|---|---|---|
| Version | `0.5` (= `MARKETING_VERSION` in `Config/Version.xcconfig`) | | R5 |
| Promotional Text | 7.1 | 162 chars / 162 bytes, max 170 | WS5 4.2 |
| Description | 7.2 | 3969 chars / 3969 bytes, max 4,000 | WS5 4.3 |
| Keywords | 7.3 | max 100 bytes | R37, WS5 4.5 |
| Support URL | `https://segue.ryandsilva.dev/support` | | R28, R29 |
| Marketing URL | `https://segue.ryandsilva.dev` | | R27 |
| Copyright | `2026 Ryan Rony Dsilva` (Apple adds the symbol; Info.plist says `© 2026 Ryan Rony Dsilva`) | | R30 |
| What's New | not shown for a first version | | Apple |
| Screenshots | 7.4 | | R10, WS5 8.4 |
| App Preview | 7.5 | | R9 |
| Build | 7.6 | | |
| Routing App Coverage File | none | | |

### 7.1 Promotional Text (162 chars / 162 bytes)

The paste-led line (R129):

```
Your chart, your set, your cue. Paste a chord sheet from any site, build tonight's set in minutes, and play it from a stage view that fits every song. No account.
```

### 7.2 Description (3969 chars / 3969 bytes)

Before pasting, the claim pass in WS5 4.4 must have verified every line on the built App Store flavour; delete any line that fails.

```
Segue is a chord chart and setlist app for performing musicians, made for the Mac. Paste a song in from anywhere, build tonight's set in minutes, and play it from a stage view that fits each song on one screen.

Made for the singer with a guitar, the keys player at an open mic, the duo on a three-hour bar gig, and the worship or cover band leader who wants the chart in front of them, not a binder.

TRY IT IN A MINUTE
Segue starts with a small Welcome library: a few original demo songs and a demo setlist. Press Start Show and you are in stage mode. Delete the demo songs whenever you like.

PASTE A SONG, CHECK IT, DONE
- Copy a chord sheet from a website or a note and choose File > New Song from Clipboard. Segue turns it into a ChordPro song with its sections and title, and shows you the result before it saves.
- Text and .crd files convert the same way, several in one review.
- Optional on-device AI double-checks section labels and title. It works with Apple Intelligence, or with a free local model you can download in Settings. It never rewrites your lyrics or chords, and nothing you paste leaves your Mac.

YOUR SONGS, AS FILES
- One ChordPro file per song, in a folder you choose. No account, no sign-in.
- Your songs stay readable by other ChordPro tools, so they are never locked in.
- Everything saves as you type. Deleted songs go to the Trash.
- Fast search across titles, artists, lyrics and tags, including romanized Hindi with loose, casual spelling.
- Tags, proficiency marks and smart filters show what is gig-ready.
- Export your whole library as one archive. Quick Look and Open With in the Finder.

AN EDITOR THAT KEEPS UP
- A song card for artists, Movie / Album, key, tempo (tap it in), capo, time signature and tags: controls, not syntax.
- Edit the ChordPro text, or place chords on syllables in the visual editor. Select lines and press V, C or B to mark a verse, chorus or bridge.
- Transpose in one step, with a capo that shows shapes or concert pitch, and Nashville numbers.
- Guitar chord diagrams with alternate tunings and your own shapes, plus piano voicings.
- Spell-check and autocorrect stay out of your lyrics.

SETLISTS IN MINUTES
- Tick songs in the order you want them, then fine-tune the order.
- Or type a request like "45 min, songs I know well, upbeat start" and Segue fills the set. Lock the songs you want and rebuild the rest.
- Breaks between sets, changeover time and a running total for each part, timed from each song's tempo and the bars you play. Songs with no tempo are listed, never guessed.
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

### 7.3 Keywords

The R37 set, unchanged (R129; `ai` is not allowed, Apple requires more than two characters per keyword):

```
chordpro,songbook,transpose,prompter,worship,hindi,guitar,piano,capo,nashville,stage,singer,cover
```
97 bytes.

### 7.4 Screenshots (Mac, 2880 x 1800 px, sRGB, no alpha; from `make screenshots`, `.build/screenshots/final/en-US/`)

Generated 2026-10-20 (direction A, provisional until Ryan picks A, B or C from `.build/screenshots/directions/directions-sheet.png`; `make screenshots-compose` re-composes in seconds after `direction` changes in `store/screenshots.json`). Contact sheet: `.build/screenshots/contact-sheet.png`. Sizes: 01 713 KB, 02 563 KB, 03 489 KB, 04 738 KB, 05 714 KB, 06 807 KB, 07 594 KB, 08 579 KB, 09 730 KB.

Drag all nine in this order; the first three show in search results. Shot 9 `paste` was added by R129.

| # | File | Appearance | Headline | Subline |
|---|---|---|---|---|
| 1 | `01-stage.png` | Dark | Your chart, your set, your cue. | A stage view that fits every song on one screen. |
| 2 | `02-builder.png` | Dark | Build tonight's set in minutes. | Drag, reorder, and watch the running time. |
| 3 | `03-search.png` | Light | Find the song from one line. | Search lyrics, even romanized Hindi with casual spelling. |
| 4 | `04-editor.png` | Light | Put chords right on the syllable. | Or edit the ChordPro text directly. |
| 5 | `05-theory.png` | Light | Transpose, capo, Nashville numbers. | Guitar and piano diagrams in any tuning. |
| 6 | `06-request.png` | Dark | Take a request mid-set. | Search, queue, and play it next. |
| 7 | `07-minsize.png` | Dark | Readable from the mic stand. | Set a minimum size. Segue scrolls rather than shrinks. |
| 8 | `08-checklist.png` | Dark | Ready before you walk on. | A pre-show checklist, and shows that survive a crash. |
| 9 | `09-paste.png` | Light | Paste a song from anywhere. | Segue converts it. You check it before it saves. |

The setlist in shots 1, 2 and 6 is "JamFest Opener" with the R128 songs (WS5 8.4.1). Captions are WS5's; the compositor direction is Ryan's pick (WS5 step 6).

### 7.5 App Preview (one, `.build/preview/segue-preview-en-US.mp4`)

1920 x 1080 landscape, 15-30 s, H.264 High 4.0, 30 fps, at most 500 MB, a silent stereo AAC track; app footage only. Generated 2026-10-20 by `make preview`: **23.1 s, 3.4 MB**, passes the ffprobe gate. Poster frame at about **6 s** (Ferry Lights Over Calder Bay on stage, full view). Storyboard WS5 9.2 (as built). Processing can take up to 24 h. `make preview-edit` re-edits the last recording without re-recording.

### 7.6 Build

Build > + > the **exact TestFlight build that went through the real gig** (version 0.5, build `CURRENT_PROJECT_VERSION`, 1 for the first upload). Export compliance is not asked: `ITSAppUsesNonExemptEncryption = NO` is in the Info.plist (`Project.swift`); if App Store Connect asks anyway, answer **No** non-exempt encryption (HTTPS only, via the system).

## 8. App Review Information (same page)

| Field | Value | Limit / count | Source |
|---|---|---|---|
| Sign-in required | No (untick) | | WS5 4.6 |
| First name | `Ryan` | | R30 |
| Last name | `Dsilva` | | R30 |
| Phone | **RYAN: your phone, international format, e.g. `+1 ...`** (never committed) | | WS5 4.6 |
| Email | `segue@ryandsilva.dev` | | R28 |
| Notes | 8.1 | 3,585 / 4,000 bytes | WS5 4.6 |
| Attachment | `.build/review/segue-review-walkthrough.mp4` (60-90 s, from `make review-video`) | | B-31, WS5 9.5 |

### 8.1 Notes (3,585 bytes)

The phase 3 rewrite (R129). Re-check every name against the TestFlight build before pasting (WS5 4.6, 14.2 step 5).

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

## 9. Version Release (same page)

| Field | Value | Source |
|---|---|---|
| Version Release | **Manually release this version** | A51 |
| Phased Release for Automatic Updates | not offered for a first version (n/a) | Apple, WS5 14.5 |
| Reset Mac App Store summary rating | n/a (first version) | |

Then Add for Review > Submit to App Review, only after the R6 order: walkthrough, WS5, TestFlight, real gig (R79).

## 10. TestFlight (before section 7's submit)

| Field | Value | Source |
|---|---|---|
| Internal group | TestFlight > Internal Testing > + > name `Ryan`, add yourself (an App Store Connect user); enable automatic distribution | R6, WS5 14.2 |
| Beta App Description | not needed for internal testing (only external groups ask) | Apple |
| Feedback email | `segue@ryandsilva.dev` | R28 |
| Test Information > What to Test (per build) | below | |
| External testing | none for 0.5 | R6 |

What to Test (424 chars / 424 bytes, max 4,000):

```
Build 0.5 for the R6 gig. Walk the first run on a clean container (move the old one aside first, WS1 step 10), then: paste a chord sheet (Option-Command-V) and Accept; download the local model in Settings > AI and paste again; build a set in Pick and Arrange with the request bar; play a full rehearsal and a real show (metronome M, requests Command-K, page-turner pedal). Report anything odd with Help > Report a Problem...
```

Install: the TestFlight app from the Mac App Store, accept the invite, install. Do WS1 [RYAN] step 10 (move the old `dev.ryandsilva.segue` container aside, copy shapes and bindings to Personal) and move any local `Segue.app` out of `/Applications` **before** installing (R40, WS5 14.2 step 4). Builds expire after 90 days.

## 11. Upload a build (Terminal.app, not an agent shell; R46)

1. Unlock 1Password (the key and the SSH signing agent for the release tag).
2. In Terminal.app:

```sh
cd ~/Desktop/Projects/setlist
make archive              # archive + export the signed .pkg + verify-archive (no credentials)
make validate DRY_RUN=1   # optional: prints the exact commands, reads no key
make validate             # App Store Connect validation with the key from 1Password
make upload               # validate, upload that same .pkg, signed local tag, dSYMs to Sentry
```

3. Wait for the "has completed processing" email, then section 10.
4. The next upload needs a new build number first: `make bump` (commits it), then repeat step 2.

`make validate` is also where App Store Connect first checks the app-group entitlement (`V6BM673U35.dev.ryandsilva.segue.models`, R100); if it is rejected, add App Groups to the App ID and regenerate the `Segue Mac App Store` profile (phase 3 spec 5.3).

## 12. After approval

Release This Version (manual, A51), then flip the site to live: `content/site.json` `appStore.status` `"live"`, `appleId`, the campaign tokens, the legal effective dates and the changelog's `draft: false`, `make site`, commit and push (WS5 14.5, WS4).
