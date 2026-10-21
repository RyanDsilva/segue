# Segue 0.5 to the Mac App Store - release guide

The one step-by-step guide for shipping Segue 0.5. Ryan follows section 2 as his checklist; agent sessions follow section 3. `decisions.md` is canonical; where this guide and a spec disagree, the spec's step detail wins and the conflict gets fixed here.

Legend: **-> paste to Claude** = not secret, give it to the session. **-> 1Password only** = never in chat, never in the repo; the scripts read it at run time. Click paths follow Apple's and vendors' labels as of 2026-10-17; match by meaning if a label moved.

---

## 1. Where we are (2026-10-17)

- Done: Apple Developer Program renewed (team `V6BM673U35`, individual); Xcode 27.1 licence accepted, baseline `make check` green (commit `78d2a1d`).
- Done: `Apple Distribution` and `3rd Party Mac Developer Installer` certificates in the login keychain.
- Done: Mac App Store profile installed for `V6BM673U35.dev.ryandsilva.segue` (expires 2027-10-18) as "Segue Mac App Store" (the name WS1 uses).
- Pending: App Store Connect access (up to 48 h after renewal), 1Password CLI integration, vendor accounts (TelemetryDeck, Sentry, Featurebase, Cloudflare).
- Next: the "Now" phase below, then WS1 steps 1-7 (they need nothing from Ryan).
- **2026-10-18: phase 3 (AI entry & assistant) is pulled into 0.5 (R61-R79).** Release order (R79): phase 3 lands -> the R56 walkthrough (with phase 3 items) -> WS5 -> TestFlight -> real gig -> submit. Spec: `docs/phases/3-ai-entry-and-assistant.md`; workstreams: `docs/phases/3-workstreams/`. Your phase 3 items are in 2.3a.
- **2026-10-19: rulings R80-R103** (metadata entry and fast set building from the walkthrough brainstorm, manual lengths + "Time it" instead of learned/estimated lengths, answers to phase 3 questions 1-16, converter rulings, no repeats within a show, About panel A). P3-1 has landed (55d8701); P3-A Part 1 proved MLX in the sandboxed archive and the shared app-group store with no profile regeneration. Six new workstreams P3-10 to P3-15. New questions 21-29 are in the phase 3 spec section 16.1.
- **2026-10-20: roadmap rulings R132-R139.** v0.5 gains the phase 3 leftovers, the phase 4 PDFs (single chart, songbook, print, embedded preview), N1 Singer view, N4 Medleys and N8 Gig stats (launch is blocked on the Apple account anyway). Then phase 6 MIDI (with the Ampero MIDI-output research), phase 5 LRCLIB + URL import, phase 7 iOS + N5 Share by file. App Store only: no DMG or direct distribution (R139). Canonical order: `docs/00-vision.md` section 4.

---

## 2. Ryan's checklist

### 2.1 Now (no App Store Connect needed)

- [x] **1Password CLI integration.** (Works in Terminal.app only; per R46 you run `make upload` there.) 1Password app > Settings > Developer > tick **Integrate with 1Password CLI**. In Terminal: `op whoami` (or `op vault list`) asks to unlock and then shows your account; confirm a vault named **`Private`** exists (the scripts default to it). Keep 1Password unlocked during agent sessions: signed commits and tags fail with "failed to fill whole buffer" when it is locked.
- [ ] **Back up both certificate private keys (.p12).** Keychain Access (Spotlight "Keychain Access") > **login** > **My Certificates** > select `Apple Distribution: Ryan Rony Dsilva (V6BM673U35)` and `3rd Party Mac Developer Installer: Ryan Rony Dsilva (V6BM673U35)` (expand each: a private key must sit under it) > **File > Export Items...** > format **Personal Information Exchange (.p12)** > save outside the repo > set a strong password. In 1Password (vault `Private`) create an item, e.g. `Segue Distribution Certificates`, attach the `.p12` and store its password. Then delete the local `.p12` and empty the Trash. **-> 1Password only.** (p12 export not possible - is this required?)
- [x] **Quick Look App ID and profile (I-14).** Certificates, IDs & Profiles > **Identifiers > "+"** > App IDs > App > Continue > Description `Segue Quick Look`, Bundle ID **Explicit** `dev.ryandsilva.segue.quicklook`, no capabilities > Continue > Register. Then **Profiles > "+"** > Distribution **Mac App Store Connect** > Continue > App ID `dev.ryandsilva.segue.quicklook` > Continue > the Apple Distribution certificate > Continue > Name **`Segue Mac App Store QuickLook`** (exactly) > Generate > Download > double-click. Do not register any `.personal` IDs by hand (automatic signing does it).
- [x] **TelemetryDeck: account and two apps.** dashboard.telemetrydeck.com > sign up (segue@ryandsilva.dev or your usual address; free tier 50k signals/month). Top-left app dropdown > **Create New App** > `Segue`; again > `Segue Personal`. For each: sidebar **Settings > Set Up App** > bottom of page > click the App ID to copy. **-> paste to Claude**, labelled (App Store vs Personal). Also say whether the organisation settings show a **namespace** (paste it if so). Values: [Service values](#service-values).
- [x] **TelemetryDeck: retention.** Look in the app and organisation settings for any retention or deletion option and tell Claude what exists. Email TelemetryDeck support (dashboard contact link) asking whether raw signals for this app can be deleted after a shorter period, e.g. 13 months, or on request. Runs in parallel, blocks nothing; if they offer one, tell the WS4 session (only `vendors.analytics.retention` changes). (Info unavailable)
- [x] **Sentry: org and project.** sentry.io/signup > create the organisation (slug e.g. `ryandsilva`) with data storage location **United States** (R33; cannot be changed later). **Projects > Create Project** > **Apple > macOS** > name `segue-macos` > "Alert me on every new issue" > Create. **Settings > Projects > segue-macos > Client Keys (DSN)** > copy the DSN. **-> paste to Claude** (a DSN is not secret), plus the org slug (for `.sentryclirc`). Values: [Service values](#service-values).
- [x] **Sentry: scrubbing.** In both **Settings > Security & Privacy** (organisation) and **Settings > Projects > segue-macos > Security & Privacy**: **Prevent Storing of IP Addresses** on; **Data Scrubber** on; **Use Default Scrubbers** on; **Additional Sensitive Fields** `title`, `lyrics`, `filename`, `path`, `email`; Safe Fields empty.
- [x] **Sentry: alerts.** Confirm the default "new issue" email alert exists. **Alerts > Create Alert > Issues** "A new issue is created" filtered to `issue.category:feedback` (or **Settings > Account > Notifications** > User Feedback) so every bug report emails you.
- [x] **Sentry: dSYM upload token.** **Settings > Auth Tokens** (organisation tokens) > **Create New Token** > name `segue dsym upload`. Copy it once into 1Password: vault **`Private`**, item **`Segue Sentry`**, field **`token`**. **-> 1Password only.** Tell Claude the item exists (the session tests `op read 'op://Private/Segue Sentry/token'`).
- [x] **Featurebase board.** featurebase.app > sign up > workspace `Segue` (subdomain e.g. `segue.featurebase.app`) > one board "Feature Requests" with statuses Under Review, Planned, In Progress, Shipped, Declined. **Settings > Requests > Collection > Feedback Portal > Participation**: tick the **Guest actions** boxes (post, upvote, comment without login), turn on **Request moderation** and **Comment moderation**. If either is missing on the Free plan, stop and tell Claude (fallback: Fider Cloud). **Settings > Branding**: logo (taped-setlist icon PNG), accent `#F2555A`, dark default theme if offered, name "Segue". Board URL **-> paste to Claude** (WS4 `/feedback` redirect). Value: [Service values](#service-values).
- [x] **Cloudflare account.** dash.cloudflare.com > create a free account (or sign in). Nothing else yet: the Pages project needs the GitHub push (2.4). ryan.dsilva.98@gmail.com
- [x] **Mailgun route for segue@.** Send a test email to `segue@ryandsilva.dev` from another account. If it arrives (the route may be a catch-all), done. Otherwise app.mailgun.com > **Send > Receiving** (Routes) > edit the existing route (free plan allows one) > Expression **Custom** `match_recipient("^(contact|segue)@ryandsilva\.dev$")` > Forward to your Gmail > Save; re-send and confirm (check spam).
- [x] **DMARC.** account.squarespace.com/domains > `ryandsilva.dev` > **DNS** > **Custom records** > **Add record**: Type **TXT**, Host `_dmarc`, Data `v=DMARC1; p=none` > Save. Skip if a `_dmarc` record exists. Do not touch the apex A record or the Mailgun MX/TXT records.

#### Service values

Pasted by Ryan from the steps above. None is secret: the IDs and the DSN ship inside the app binary, and the board URL is public. Sessions that wire the services (WS3, WS4) take them from here.

| Service | Item | Value | Used by |
|---|---|---|---|
| TelemetryDeck | App ID, `Segue` (App Store flavor) | `CDF7AF01-FB23-4A30-AFAB-8EAB4BF6EFB5` | WS3 ingest client |
| TelemetryDeck | App ID, `Segue Personal` | `6E38DC85-EE5E-4ECF-A8E0-E4FDFDE9B208` | WS3 ingest client |
| TelemetryDeck | Namespace (both apps) | `dev.ryandsilva` | WS3 ingest client |
| TelemetryDeck | Retention option | Unknown (Ryan: "Info unavailable") | WS4 `vendors.analytics.retention` |
| Sentry | DSN (`segue-macos`) | `https://997bf383bbb7edd32a15c839fba202b8@o4512275137691648.ingest.us.sentry.io/4512275142475776` | WS3 Sentry init |
| Sentry | Organisation slug | `ryandsilva` | `.sentryclirc`, dSYM upload |
| Featurebase | Board URL | `https://segue.featurebase.app/` | WS4 `/feedback` redirect, Request a Feature |

### 2.2 When App Store Connect is live

- [ ] **Confirm access.** appstoreconnect.apple.com signs in with the developer Apple ID and shows **Apps**. Tell Claude.
- [ ] **Agreement.** **Business > Agreements** > accept the **2026-10-13 Apple Developer Program License Agreement** (Account Holder only). Leave the Paid Apps agreement unsigned (R2: free, no banking or tax).
- [ ] **EU DSA: non-trader (R4).** **Business > Agreements > Compliance > Digital Services Act > Complete Compliance Requirements** > choose **not a trader**.
- [ ] **App record.** **Apps > "+" > New App** > platform **macOS**, Name `Segue - Setlists & Chords`, Primary Language **English (U.S.)**, Bundle ID `dev.ryandsilva.segue`, SKU `segue-macos`, User Access **Full Access** > Create. If the name is taken, stop and ask (do not pick a fallback). Then **App Information** > copy the numeric **Apple ID** **-> paste to Claude** (feeds Help > Rate Segue on the App Store in the app and `appStore.appleId` on the site).
- [ ] **Pricing and availability.** Apps > Segue > **Pricing and Availability** > Price Schedule **Free**; Availability: select all, then untick **China mainland** (A47).
- [ ] **App Store Connect API key (R13).** **Users and Access > Integrations > App Store Connect API**; click **Request Access** if shown and wait for approval. Then **Team Keys > "+"** > Name `Segue uploads`, Access **App Manager** > Generate. Note the **Issuer ID** (top of page) and **Key ID**, then **Download API Key** (only once). In 1Password create item **`Segue ASC API Key`** in vault **`Private`** (category API Credential), with text fields **`key_id`** and **`issuer_id`**, and attach the file renamed to **`AuthKey.p8`**. Move the downloaded `.p8` to the Trash and empty it. **-> 1Password only**; tell Claude it is done (and the names, if you used others: `SEGUE_ASC_OP_VAULT` / `SEGUE_ASC_OP_ITEM`). Check: `op read "op://Private/Segue ASC API Key/key_id"` prints the Key ID.
- [ ] **Campaign links for the site badge.** **Analytics > Acquisition > Campaigns > Generate Campaign Link**: create `website-hero`, `website-footer`, `press`; from the generated link copy the `pt` and `mt` values **-> paste to Claude** (`providerToken`, `mediaType`).

### 2.3 During build (agent sessions ask for these at the step)

- [ ] **R35 Shortcut probe (WS1 step 8).** In the Shortcuts app create exactly: **`Segue Probe OK`** = one action **Show Notification** with text `probe ok`; **`Segue Probe Fail`** = one action **Get Contents of URL** with URL `https://invalid.invalid`. Be at the Mac while the agent runs the probe: click **OK** on the "wants to control Shortcuts Events" prompt the first time, then report any later prompt, whether Shortcuts or anything else came to the front, whether the "probe ok" notification appeared, and how long runs took. Afterwards, in Terminal: `mkdir -p ~/segue-backups && mv ~/Library/Containers/dev.ryandsilva.segue.shortcutsprobe ~/segue-backups/`. Delete both Shortcuts if you like.
- [ ] **Approve the progress-dot before/after render (WS2b step 1)** - `design/directions/ws2b/progress-dots-before-after.png` (new `indicatorOff` token, darker `played`).
- [ ] **Approve the Welcome songs (WS2b, before step 2 ships them).** Title-search each of the four (Apple Music, Spotify, Google "<title> song"): Soundcheck at Seven, Kitaabon Wali Gali, Kettle On, Lights Low, Ferry Lights Over Calder Bay. Read the lyrics in WS2b Appendix A. Any collision -> tell the session which title to change.
- [ ] **Pick design directions (R39).** One each, or a named mix: Welcome sheet, What's New sheet, `.cho` document icon (WS2b step 3, `design/directions/ws2b/`); website home page (WS4 step 3, on the design canvas or an artifact).
- [x] **Approve the screenshot-only songs (WS5, before its step 4).** Done 2026-10-20 (R128): five titles and the setlist "JamFest Opener". The one title-search hit is replaced by "Northbound at First Light" (R129).
- [ ] **Rewrite the maker note (WS4 R-2)** in your own words, removing the `ryan-edit` markers; confirm the policy and terms effective dates (default: day of the first push). Must be done before the first push (6.2).
- [ ] **Pick the screenshot compositor direction (WS5 step 6)** - A, B or C from `.build/screenshots/directions/` (appearance mix is fixed at 5 dark / 4 light, R129).
- [ ] **Grant Screen Recording to your terminal (WS5, before the first `make preview`).** System Settings > Privacy & Security > **Screen & System Audio Recording** > "+" > your terminal app > relaunch it.
- [ ] **Approve the preview video cut (WS5 step 7)** - `.build/preview/segue-preview-en-US.mp4`.
- [ ] **VoiceOver and Voice Control walks (WS2b step 12).** The agent prepares the checklist in `docs/release/accessibility-audit.md` and fixes what you find. Labels you cannot walk stay unclaimed.
- [ ] **Read the legal text (WS4 R-9)** - privacy policy and terms with vendor values filled in, before the site goes live.

### 2.3a Phase 3 (R61-R79)

- [ ] **Unlock 1Password** (the 1Password SSH agent) whenever agent sessions run: every phase 3 commit is signed (`git commit -S`) and fails with "failed to fill whole buffer" while it is locked.
- [ ] **Supply 10-20 real pastes (R64)** into `research/phase3-eval/pastes/` (gitignored; format in its `README.md`): mostly Ultimate Guitar plus other sites you use, at least 4-5 Hinglish, a few messy ones; optional expected `.cho` per paste. They contain copyrighted lyrics: never commit them (the `.gitignore` rule covers the folder; `git status` must not list them). P3-A re-runs the scorer on them; the curated model (Qwen3-4B-2507 4-bit) is locked only if it reaches >= 90%.
- [x] **Rule on the phase 3 open questions 1-16** (done 2026-10-19: R91-R100).
- [ ] **Rule on the new phase 3 questions 21-29** (spec section 16.1: break rows on stage, break length, section-note storage, packing songs with no length, metronome details, what "paste disabled during a show" covers, essentials markers outside the card, tap tempo, what "already played" means). Each blocks only one step of P3-12, P3-13, P3-7, P3-14, P3-4, P3-10 or P3-15. Questions 17-20 (screenshots, keywords, age rating/content rights, "Apple Intelligence" wording) come with P3-9's research ticket before WS5.
- [x] **App-group profiles (P3-A).** Not needed (R100): the team-prefixed group `V6BM673U35.dev.ryandsilva.segue.models` needs no registration and the existing "Segue Mac App Store" profile exported fine.
- [ ] **App Store Connect check of the app-group entitlement** at the first real `make validate` after P3-3 lands (Terminal.app, R46). If it is rejected, the session hands you the portal steps (App Groups on the App ID, regenerate "Segue Mac App Store").
- [ ] **Lock the curated model** after P3-A reports the scorer result (a new ruling).
- [ ] **Pick design directions** for the song card (P3-10 step 0), the section band (P3-11 step 0), the set builder Pick/Arrange + break rows (P3-12 step 0), the review sheet's AI marking and batch list (P3-4 step 0), the set assistant (P3-7 step 0) and the metronome overlay (P3-14 step 0).
- [ ] **VoiceOver and Voice Control walk of the new UI (R79, P3-9 step 6)** before any accessibility label is claimed.
- [ ] **R56 walkthrough again after phase 3** (P3-9 adds the phase 3 items to `walkthrough.md`), including a real model download on the App Store build.

### 2.4 Before TestFlight

- [ ] **R40: move the old container aside, carry over shapes and bindings.** Run once WS1 step 1 (bundle-ID split) has landed, and in any case before installing any TestFlight build. Use **Terminal** (not an agent shell). If macOS asks "Terminal would like to access data from other apps", click **Allow**; if a command still fails with "Operation not permitted", grant Terminal Full Disk Access temporarily (System Settings > Privacy & Security > Full Disk Access), re-run, then remove it.
  ```sh
  # a. Quit every Segue (both flavors); never launch one just to quit it.
  osascript -e 'if application id "dev.ryandsilva.segue" is running then tell application id "dev.ryandsilva.segue" to quit'
  osascript -e 'if application id "dev.ryandsilva.segue.personal" is running then tell application id "dev.ryandsilva.segue.personal" to quit'
  pgrep -fl 'Segue.app/Contents/MacOS/Segue' || echo "no Segue running"

  # b. Launch the NEW Personal build once (from the WS1 step 1 commit), choose your library
  #    folder, quit it again (repeat a.), then check its container exists:
  ls -d ~/Library/Containers/dev.ryandsilva.segue.personal/Data

  # c. Copy shapes and bindings into the Personal container.
  old="$HOME/Library/Containers/dev.ryandsilva.segue/Data/Library/Application Support/dev.ryandsilva.segue"
  new="$HOME/Library/Containers/dev.ryandsilva.segue.personal/Data/Library/Application Support/dev.ryandsilva.segue.personal"
  mkdir -p "$new"
  for f in shape-library.json bindings.json; do
    if [ -f "$old/$f" ]; then cp -pn "$old/$f" "$new/$f" && echo "copied $f"; else echo "no $f in old container"; fi
  done
  ls -l "$new"

  # d. Move the old App Store-flavor container aside. Nothing is deleted.
  mkdir -p ~/segue-backups
  mv ~/Library/Containers/dev.ryandsilva.segue ~/segue-backups/dev.ryandsilva.segue-container-20261017
  mv ~/Library/Containers/dev.ryandsilva.segueshortcutprobe ~/segue-backups/ 2>/dev/null || true
  ls ~/Library/Containers | grep -i segue    # expect: dev.ryandsilva.segue.personal (+ uitests runner)
  ```
  Then open the Personal build: shapes and bindings are back; re-enter your Gig Mode Shortcut names in Settings > Live. Rollback: quit Segue and `mv` the backup to its original path.
- [ ] **Move any locally built `Segue.app` out of `/Applications`** (both flavors share the file name; the TestFlight install could collide).
- [ ] **Approve the push to GitHub (WS4 R-1).** Preconditions the session checks: maker note rewritten, board URL filled, `make site-check STRICT=1` green (the pre-push hook enforces it). Say "push approved" explicitly; agents never push otherwise.
- [ ] **Cloudflare Pages project (WS4 R-3).** dash.cloudflare.com > **Workers & Pages > Create application** > **Pages** tab > **Import an existing Git repository** > Get started > **Connect GitHub** > **Only select repositories** > `RyanDsilva/segue` > Install & Authorize > select `segue` > **Begin setup**: Project name `segue`, Production branch `main`, Framework preset **None**, Build command `scripts/pages-build.sh` (builds the user guide, WS6 4.4), Build output directory `website`, Root directory empty, no env vars (Node comes from `.node-version`) > **Save and Deploy**. Then **Settings > Build > Build watch paths**: include `website/*`, `guide/*`, `scripts/pages-build.sh` and `.node-version`; **Settings > Build > Branch control** > Preview branch **None**; **Metrics > Web Analytics > Enable**, then **Deployments** > latest > **...** > **Retry deployment**. If Cloudflare assigned a name other than `segue`, **-> paste to Claude**.
- [ ] **Custom domain (WS4 R-4), in this order.** Cloudflare: **Workers & Pages > segue > Custom domains > Set up a custom domain** > `segue.ryandsilva.dev` > Continue. Then Squarespace DNS > **Custom records** > Add: Type **CNAME**, Host `segue`, Data `segue.pages.dev` (or the shown target) > Save. Wait for **Active** with a certificate. Check: `curl -sI https://segue.ryandsilva.dev/privacy` is 200 and `/feedback` is 302. The site is now live with "Coming soon" (A55); it must be live before submission.
- [ ] **Unlock 1Password before every `make upload`** (API key, Sentry token, signed tag).

### 2.5 Release

- [ ] **TestFlight install (R6).** After `make upload`, wait for the "has completed processing" email. Apps > Segue > **TestFlight > Internal Testing > "+"** > group `Ryan`, add yourself > **Builds > "+"** > the build. Install the TestFlight app from the Mac App Store, accept the invite, install Segue. If any App Store-flavor build ran since 2.4, first re-run step a and `mv ~/Library/Containers/dev.ryandsilva.segue ~/segue-backups/dev.ryandsilva.segue-container-$(date +%Y%m%d-%H%M)`.
- [ ] **Clean-account pass + review walkthrough (WS5 14.2 step 5).** System Settings > Users & Groups > Add User; on that account install from TestFlight and run every "Things to try" step of the review notes (WS5 4.6) word for word; fix the notes where wrong. While doing it, record the walkthrough with QuickTime Player > File > New Screen Recording > Record Selected Portion; save to `.build/review/raw.mov` (see 6.4). The session runs `make review-video`.
- [ ] **Vendor smoke test (WS3 14.4).** Before answering consent, `nettop -p Segue -L 1` shows no TelemetryDeck/Sentry connections; Share/Send, use 5 minutes, check the `Segue` TelemetryDeck app's test mode and Sentry; send a Report a Problem; offline fallback; turn both off and confirm silence.
- [ ] **The real gig (R6, WS5 14.3).** Quit the Personal build first (never both on one library). Before: real library, real setlist, Gig Mode Shortcuts if used, full rehearsal on battery, one force-quit and relaunch. At the gig: full set, one request via quick search, one skip and reorder, End Show. After: findings to `JOURNAL.md`; any fix means a new build number and a repeat clean-account pass. Only a build that went through the gig (or that pass, for post-gig fixes) ships.
- [ ] **Store text and screenshots.** The session runs `make store-upload` (fastlane `deliver`); you confirm its HTML preview. Check Privacy Policy URL `https://segue.ryandsilva.dev/privacy`, Support URL `/support`, Marketing URL `https://segue.ryandsilva.dev` on the version page.
- [ ] **Age rating.** Apps > Segue > **App Information > Age Rating > Edit** > answers in WS5 section 5 (expect 4+).
- [ ] **App Privacy label.** Apps > Segue > **App Privacy > Get Started** (or Edit) > "Yes, we collect data" > the nine types from WS5 section 6 (= WS3 10.2; the session diffs it against WS3, `PrivacyInfo.xcprivacy` and `/privacy` first) > per type **Set Up**: purposes, linked, tracking exactly as the table > **Publish**.
- [ ] **Accessibility labels.** Apps > Segue > **App Accessibility > Add Accessibility Support > macOS** > tick only what `docs/release/accessibility-audit.md` passed (WS5 section 7) > Publish. Accessibility URL empty.
- [ ] **App Information.** Categories Music / Productivity; content rights "No, it does not contain, show, or access third-party content"; license agreement = Apple standard EULA.
- [ ] **Preview video.** Apps > Segue > macOS App > 0.5 > **App Previews and Screenshots** > drag `.build/preview/segue-preview-en-US.mp4` > Edit poster frame (~6 s).
- [ ] **App Review Information.** Contact Ryan / Dsilva, `segue@ryandsilva.dev`, your phone (typed here or via `SEGUE_REVIEW_PHONE`; **never committed**); notes from `store/`; attach `.build/review/segue-review-walkthrough.mp4`.
- [ ] **Submit.** Apps > Segue > macOS App > 0.5 (Prepare for Submission): check every field against `store/` and all 9 screenshots in order > **Build "+"** > the exact gig-tested build > Version Release **Manually release this version** > **Add for Review > Submit to App Review**. On rejection follow WS5 14.6.
- [ ] **Manual release (A51).** After approval, at a moment you choose: Apps > Segue > macOS App > 0.5 > **Release This Version**.
- [ ] **Flip the site to the badge.** The session sets `appStore.status` to `"live"`, runs `make site && make site-check STRICT=1`, commits; you approve the push. Check the badge links to the live listing.
- [ ] **After release.** Search "Segue setlists" on the US Mac App Store; check screenshots, preview, privacy and accessibility labels render. Watch Xcode Organizer and Sentry for 48 h. Weekly habit: Sentry **User Feedback**, copy anything worth keeping into GitHub by hand (reports expire after 30 days).
- [ ] **Post-launch doc fold (agent session).** After v0.5 ships, fold `research/01-09` and `open-questions.md` into `decisions.md` (the chosen option per A/B id as an appendix) and a `research/SUMMARY.md` (findings that still matter for 0.6+), repoint the spec citations, then delete the originals. See `docs/cleanup-proposal.md` section 2 while it exists.

---

### Later tasks (recorded)
- [ ] **v0.5 additions (R138):** phase 3 leftovers; phase 4 single chart + songbook PDFs with print and embedded preview (`docs/phases/4-export.md`); N1 Singer view, N4 Medleys, N8 Gig stats (specs not written yet).
- [ ] **After launch, in order (R138):** phase 6 MIDI input + mapping with MIDI learn, with the R135 Ampero II Stomp MIDI-output research ticket alongside; phase 5 LRCLIB + URL import; phase 7 iOS/iPadOS app, partner follow, personal modules on iOS, plus N5 Share by file. Phase 5 vs 7 is unranked (iOS last by default).
- [ ] **Website trim pass (R57):** in a fresh session once the app is feature-complete, cut copy and sections (Ryan: "too much text and site is too long"), then swap in real screenshots (WS5).
- [ ] **Post-launch:** fold research 01-09 and open-questions.md into decisions.md plus a short summary.

## 3. Build plan

Test budget (R58, docs/test-performance.md): per step, filtered suites only (`make quick` plus the step's targeted `make e2e-one TEST=<Class>[/<test>]`), then one signed local commit (`git commit -S`), never a push. Per assignment (workstream gate): `make quick` plus `make gate` (the smoke set and the E2E classes mapped from the changed paths). Release, and the end of each phase: `make check`, never after every small fix. Workstreams that run in parallel share a working tree: expect unrelated diffs.

WS2a, WS2b and WS3 all edit the app shell (`AppModel`, `SegueRootView`/`SegueCommands`, `SegueApp.swift`, `LaunchOptions.swift`, `Project.swift`, the Settings host), so they take the shell in turn; their file-disjoint parts run alongside.

| Phase | Work (parallel within a phase) | Gate | Blocked by Ryan |
|---|---|---|---|
| 1. Baseline | **WS1 steps 1-7** (bundle-ID split, version xcconfig + Info.plist, privacy manifest, logging, test hooks out of Release, Gig Mode default off + Focus model, library lock). **WS4 steps 1-2, then 3** (generator, tokens CSS + web fonts; WS4's `gen-tokens.swift` change lands before WS2b step 1). **WS3 steps 1-2** (envelope spike, services core). **WS2b steps 1-2** + SegueCore half of step 7 (`LibraryArchive`) | per step; WS1 step 1 also `make verify-appstore` and `lipo -archs` = `arm64` | WS4 step 3: home direction. WS2b step 1: dot render. WS2b step 2: Welcome title search. After WS1 step 1: R40 (2.4) is runnable |
| 2. Shell owner | **WS2a steps 0-11** alone on the shell (reserves `AppHooks.showWelcome`, export slot, Help slots). Alongside: **WS3 step 5** (VendorServices package; its `Project.swift` edit waits for WS2a), **WS1 steps 10-11** (release scripts, ExportOptions, verify-archive, icons), **WS4 steps 4-7**, **WS2b step 3** (design directions) | WS2a: `make check`. WS1 step 10: `make archive` (check 10 may fail until step 11), step 11: `make archive` green | WS3 step 5: TelemetryDeck IDs, Sentry DSN. WS1 step 10: certs + `Segue Mac App Store` profile. WS2b step 3: three picks |
| Between phases | **WS1 steps 8-9** (R35 probe, then the chosen confirmation path); touches `AppModel+Shows.swift`, so never during a shell phase | `make e2e-one TEST=SegueLiveE2ETests` + manual real-Shortcut check | Probe Shortcuts and Ryan at the Mac |
| 3. Services | **WS3 steps 3-4 and 6-10** (consent store + UI, event emission, Report a Problem, Request a Feature, manifest + label + verify-archive check 14, dSYM upload, Personal flavour) | WS3 step 11: `make check` | Step 9: `Segue Sentry/token` in 1Password. Featurebase URL (for WS4) |
| 4. First run and polish | **WS2b steps 4-12** (stores, Welcome sheet, Settings host, export, What's New, review prompt, TipKit, Finder + Quick Look, accessibility pass) | WS2b step 13: `make check` | Step 11: Quick Look profile `Segue Mac App Store QuickLook`. Step 12: VoiceOver/Voice Control walks |
| 5. Release gating | **WS1 step 12** `make validate`, **step 13** `make check`, **step 14** `make upload` (build 1 may go early after phase 1 + signing to prove the pipeline, B-9; the TestFlight build that gets tested is the feature-complete one after phase 4). **WS4 step 8** + final legal text after WS3 vendor facts; site live with "Coming soon" | WS1: `make check`; WS4: `make site-check STRICT=1` | ASC record + API key (2.2); 1Password unlocked; push approval, Cloudflare, domain (2.4); maker note |
| 5b. Phase 3 (R61, R80-R103) | **P3 waves** per `docs/phases/3-ai-entry-and-assistant.md` section 15: wave 1 P3-A (Part 1 done, Part 2 waits on pastes), P3-1 (done, 55d8701); wave 2 P3-2 (with the R101 converter follow-ups as step 0), P3-5 (rescoped: Time it + length field), P3-10 (song card, `{` fixes, slash menu), P3-11 (section band), P3-12 (Pick/Arrange, multi-select, break rows, changeover, missing-lengths list), P3-6; wave 3 P3-3, P3-4, P3-7, P3-13 (section notes), P3-14 (metronome), P3-15 (no repeats in a show + About A); wave 4 P3-9. Then the R56 walkthrough again (R79). `make upload` of the tested build waits for this | per workstream `make quick` + `make gate`; phase gate `make check` (P3-9) | Pastes (2.3a), questions 21-29, design picks, 1Password unlocked, accessibility walk |
| 6. Store | **WS5 steps 1-10**. Metadata, `store-check` and compositor can start any time after phase 1; screenshots and preview wait for WS2a + WS2b (UI frozen, pixel pass done); App Privacy waits for WS3; accessibility labels wait for WS2b step 12. Then the runbook (2.5) | WS5 step 10: `make check`; 14.1 gate before any upload | Step 4: screenshot titles. Steps 6-7: direction, Screen Recording, cut approval. Step 8: ASC live, DPLA, DSA, pricing, API key. Then all of 2.5 |

Dependency summary: WS1 steps 1-5 come first (everyone builds on them). WS2a needs WS1. WS3 app integration needs WS1 + WS2a. WS2b's remainder needs WS1, WS2a and WS3 step 3 (`ConsentChoiceView`). WS5 needs all four plus WS4's live URLs.

---

## 4. Documents

| Document | What it is |
|---|---|
| [decisions.md](decisions.md) | Canonical release rulings R1-R103 (kickoff, repo health R47-R51, build-out R52-R60, phase 3 in 0.5 R61-R79, metadata entry / fast set building / phase 3 answers R80-R103); specs follow it. Product rulings for phases 0-7 are in [../decisions.md](../decisions.md) |
| [open-questions.md](open-questions.md) | The resolved question sheet: A items (Ryan), B defaults, I-1..I-17 cross-spec fixes, section 5 implementation order |
| [specs/WS1-release-pipeline.md](specs/WS1-release-pipeline.md) | Signing, bundle-ID split, version, privacy manifest, readiness fixes, Gig Mode/R35, archive/validate/upload, verify-archive |
| [specs/WS2a-core-ux.md](specs/WS2a-core-ux.md) | Import, Delete + Trash, autosave, menus (File/Setlist/Help/Window), About, `?` overlay, Show in Finder, undo, state restore |
| [specs/WS2b-first-run-polish.md](specs/WS2b-first-run-polish.md) | Welcome flow + Welcome library, What's New, TipKit, review prompt, Settings panes, Finder/Quick Look, export archive, accessibility pass |
| [specs/WS3-services.md](specs/WS3-services.md) | TelemetryDeck ingest client, Sentry, consent, Report a Problem, Request a Feature, dSYMs, App Privacy source of truth (10.2) |
| [specs/WS4-website.md](specs/WS4-website.md) | segue.ryandsilva.dev on Cloudflare Pages: generator, pages and legal text, changelog pipeline, Cloudflare/DNS/Mailgun steps |
| [specs/WS5-store-listing.md](specs/WS5-store-listing.md) | Store metadata, questionnaires, screenshot and preview pipelines, fastlane `deliver`, submission runbook |
| [research/01-account-and-connect.md](research/01-account-and-connect.md) | Membership, agreements, DSA, app record, TestFlight, pricing |
| [research/02-technical-submission.md](research/02-technical-submission.md) | Signing, sandbox, privacy manifest, export and upload mechanics |
| [research/03-review-risk.md](research/03-review-risk.md) | Review-guideline risks, age rating, privacy and accessibility labels |
| [research/04-store-listing.md](research/04-store-listing.md) | Product page specs, competitors, screenshot/preview tooling |
| [research/05-landing-page.md](research/05-landing-page.md) | Website research and plan, `changelog.json` |
| [research/06-readiness-audit.md](research/06-readiness-audit.md) | Read-only audit of the App Store target (B*/R*/P* findings) |
| [research/07-services.md](research/07-services.md) | Analytics, crash, board and bug-report vendor survey |
| [research/08-polish-features.md](research/08-polish-features.md) | Polish features survey and HIG gap analysis |
| [research/09-shortcut-confirmation.md](research/09-shortcut-confirmation.md) | How to confirm a Gig Mode Shortcut ran (R35); probe results land here |
| [../phases/3-ai-entry-and-assistant.md](../phases/3-ai-entry-and-assistant.md) | Phase 3 spec (AI entry & assistant, in 0.5 per R61): scope per flavour, pipeline, routing, model download/store, song lengths, smart filters, set assistant, metadata entry and fast set building (16.0), release impact, open questions |
| [../phases/3-workstreams/](../phases/3-workstreams/) | P3-A, P3-1 to P3-7, P3-9 and P3-10 to P3-15 workstream specs (one per session) |
| [accessibility-audit.md](accessibility-audit.md) | Per-label pass/fail evidence that decides the accessibility claims (completed in WS2b step 12) |
| [../github-setup.md](../github-setup.md) | GitHub repo settings runbook: labels, security toggles, the pre-push hook that stands in for branch protection |
| [../cleanup-proposal.md](../cleanup-proposal.md) | Pre-push repo clean-up audit (approved items carried out 2026-10-17); kept until the first push |
| [../../README.md](../../README.md), [LICENSE](../../LICENSE), [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md), [SECURITY.md](../../SECURITY.md), [CONTRIBUTING.md](../../CONTRIBUTING.md) | Repo-health files (R47): overview, all-rights-reserved licence, dependency notices, security policy, contributing guide |

---

## 5. Minor defaults taken without asking

Recorded so sessions apply them; say if any is wrong.

1. The Help menu keeps **"Welcome to Segue..."** (reopens the Welcome cards in revisit mode).
2. **Reset All Settings... does not touch consent** (WS2b question 1, option b): the Privacy pane already turns each toggle off, and the confirmation says consent is kept. WS2b 4.6 still lists "Privacy decisions back to undecided" in the reset scope; the WS2b session follows this default instead.
3. **`GigModeTip` appears after the first show or rehearsal starts** (WS2b question 2), not after the first completed gig.
4. **Personal dSYMs use a manual upload target** (WS3 question 1, default): `make upload-dsyms-personal`, run after installing a new Personal build.
5. **Revoking analytics resets the anonymous ID** (WS3 question 2, default): a later re-grant counts as a new anonymous user.

---

## 6. Pending small questions (asked at the relevant step)

1. **"Segue Personal" display name** (WS1 question 1, asked at WS1 step 2). Default: both builds show as "Segue"; the alternative sets the Personal flavor's `CFBundleDisplayName = "Segue Personal"`.
2. **Maker note** (WS4 question 1, asked before the first push). Default: you rewrite it before the first push, so it blocks `STRICT=1` until then; the alternative ships the first push without the maker-note section.
3. **Screenshot-only song titles and the setlist name.** Resolved by R128: five titles, setlist "JamFest Opener"; the one title-search hit replaced by "Northbound at First Light" (R129).
4. **Review walkthrough capture** (WS5 question 2, asked before 2.5). Default: you record it with QuickTime on the clean-account TestFlight pass; the alternative is a scripted XCUITest capture on Debug-AppStore (repeatable, but skips the library step and is not the shipped binary).
5. **Profile name.** Resolved: the specs use the installed profile name "Segue Mac App Store"; nothing to rename.
