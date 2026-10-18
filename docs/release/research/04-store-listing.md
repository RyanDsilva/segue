# 04 - Mac App Store product page and competitive landscape

Researched 2026-10-17. Apple specs were read from the live App Store Connect Help pages that day. Competitor data comes from the live US App Store product pages and the iTunes Search API. Anything I could not confirm at source is marked **UNVERIFIED**.

**Decided by Ryan (2026-10-17):** Segue launches **free, with no in-app purchases**. The developer account is a **US-resident individual**. The competitor pricing survey is here for context only. All recommendations assume a free app.

---

## 1. Summary

- **Fields and limits:**
  - Name: 30 characters (min 2).
  - Subtitle: 30 characters.
  - Promotional text: 170 characters.
  - Description: 4,000 characters, plain text.
  - Keywords: 100 **bytes**.
  - What's New: 4,000 characters, and it does not exist for the first version.
  - Support URL is required and must lead to real contact information.
  - Privacy policy URL is required for macOS.
  - Copyright is required.
  - Marketing URL is optional.
  - Primary category is required and must match `LSApplicationCategoryType`, which is already set to `public.app-category.music` in `Project.swift`.
- **Fields you can change without a new version:** promotional text, copyright, primary language, license agreement, price, App Review info and the privacy data types. Name, subtitle, description, keywords, screenshots, support and marketing URLs, and categories all change only with a new version.
- **Mac screenshots:**
  - 16:10 only, at 1280x800, 1440x900, 2560x1600 or **2880x1800**.
  - 1-10 per localization.
  - .png, .jpg or .jpeg, with no alpha channel.
  - Upload the 2880x1800 set and App Store Connect scales it down for the smaller sizes.
- **Mac app previews:** 1920x1080, landscape, 15-30 s, H.264 or ProRes 422 HQ, at most 30 fps, at most 500 MB, up to 3 per localization. Optional.
- **Custom product pages and product page optimization are iOS/iPadOS-only.** They are not available for a Mac product page. Localization is available (50 languages and locales).
- **Screenshot tooling:** fastlane `snapshot` does not work for macOS in practice. Recommended free pipeline:
  1. A dedicated XCUITest class takes the shots (fixed window size, light and dark).
  2. `xcrun xcresulttool export attachments` (present in Xcode 26.6 on this machine) pulls them out of the result bundle.
  3. A small Swift CoreGraphics compositor (captions in Schibsted Grotesk) produces the final images.
  4. Optionally, fastlane `deliver` (`platform: "osx"`) uploads them.
- **Competitors:**
  - **Pricing is dominated by subscriptions:** OnSong $3.99-5.99/mo, BandHelper $3-23/mo, SongSheet Pro $5.99/mo or $129.99 lifetime, Bandfix $1.99-9.99/mo.
  - **Then one-time unlocks:** SongbookPro $5.99, MobileSheets $15.99, Òrain $7.99.
  - **Then paid upfront:** forScore $24.99, LinkeSOFT SongBook $19.99, Set List Maker $19.99, Leganote $5.99.
  - **Truly free apps** are small and new: LeadSheets, SongDeck, Setlister.
  - **Most iPad competitors run on the Mac only as "Designed for iPad. Not verified for macOS".** A native, local-first, free Mac app is a real gap.
- **Name collisions:**
  - "Segue" alone is taken: two iOS apps (fleet telematics, vocabulary) and a Mac Safari extension called "Timbre Segue" (Music category).
  - The planned title **"Segue - Setlists & Chords"** is unique.
  - None of them are setlist or chord apps.

---

## 2. Product page field spec (Mac)

Source tables:

- [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)
- [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
- [Required, localizable, and editable properties](https://developer.apple.com/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties)

**How to read "Editable anytime":** this column is Apple's "Editable" column, meaning editable "at any time without submitting a new version". I parsed it from the page's icon markup on 2026-10-17. "No" means the change ships with the next version submission. The editable fields listed below are the only ones Apple marks that way.

| Field | Limit / format | Required | Localizable | Editable anytime | Notes for Segue |
|---|---|---|---|---|---|
| Name | 2-30 chars | Yes | Yes | No (editable until first submission, then with a new version) | "Segue - Setlists & Chords" (25). Indexed for search. |
| Subtitle | 30 chars | No | Yes | No | Indexed for search. See candidates in section 6. |
| Promotional text | 170 chars | No | Yes | **Yes** ("without requiring an updated submission") | Not indexed for search ([product page guide](https://developer.apple.com/app-store/product-page/)). Apple's doc says it shows "for customers with devices running iOS 11 or later". Display on the Mac App Store is **UNVERIFIED**. |
| Description | 4,000 chars, plain text, no HTML | Yes | Yes | No | The first sentence matters most (it shows before "more"). Not a keyword field on iOS. Whether the Mac App Store indexes it is **UNVERIFIED**. |
| Keywords | 100 **bytes**; each term over 2 chars; comma-separated | Yes | Yes | No | Don't repeat words from the name or company name. Competitor names are not allowed. |
| What's New | 4,000 chars | Required from v2 | Yes | No | Not available for the first version. |
| Screenshots | 1-10, see section 3 | Yes | Yes (per localization) | No | |
| App preview | Up to 3 per localization | No | Yes | No | |
| Support URL | Full URL with protocol | Yes | Yes | No | Must lead to "actual contact information (legal address, email address, telephone number), as may be required by local law". Can also host an SBOM. |
| Marketing URL | Full URL with protocol | No | Yes | No | The landing page (see 05-landing-page.md). |
| Privacy Policy URL | URL | Yes (iOS and macOS) | Yes | No | |
| Privacy Choices URL | URL | No | Yes | No | Not needed (no data collected). |
| Version number | | Yes | No | No | |
| Copyright | "YYYY Name"; the symbol is added automatically | Yes | No | **Yes** | "2026 Ryan D'Silva" (individual account; confirm the exact legal name). |
| Routing App Coverage File | .geojson, one MultiPolygon | No | No | Yes | Not applicable. |
| Primary category | from the list | Yes | No | No | Must match the Xcode `LSApplicationCategoryType` for macOS apps. |
| Secondary category | from the list | No | No | No | |
| Age rating | questionnaire | Yes | No | No | |
| Content rights | declaration | Yes | No | No | |
| Primary language | | Yes | No | **Yes** | |
| License agreement | Apple EULA or custom | No | Yes | **Yes** | Keep the Apple standard EULA. |
| Bundle ID | | Yes | No | Never after the first build | `dev.ryandsilva.segue` |
| SKU | letters, digits, `-` `.` `_`; can't start with a symbol | Yes | No | Never | For example `segue-mac-001`. |
| DSA trader status (EU) | declaration | Yes | No | Yes | See section 7. |
| Price | tier | Yes | No | **Yes** | Free. |
| App privacy data types | questionnaire | Yes | No | **Yes** | "Data Not Collected". |
| Accessibility URL / support (Accessibility Nutrition Labels) | | No | Yes | No | Optional. Worth filling for VoiceOver, Dark Interface, Larger Text and Reduced Motion if they are verified. |
| App Review notes | 4,000 bytes | No | n/a | Yes (App Review info is editable anytime) | Not customer-visible. |

**Category in Xcode:** the Info.plist already has `LSApplicationCategoryType = public.app-category.music` (`Project.swift:111`). That matches a Music primary category.

---

## 3. Screenshots, previews, localization, custom pages

### 3.1 Mac screenshot spec ([Apple](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications))

| Property | Value |
|---|---|
| Aspect ratio | 16:10 |
| Accepted sizes | 1280x800, 1440x900, 2560x1600, 2880x1800 px |
| Count | min 1, max 10 |
| Format | .jpeg, .jpg, .png; **no alpha or transparency** |
| Scaling | Upload the highest resolution and App Store Connect scales it down. Per-size and per-localization overrides are optional. |
| API display type | `APP_DESKTOP` ([ScreenshotDisplayType](https://developer.apple.com/documentation/appstoreconnectapi/screenshotdisplaytype)) |

Apple's product page guidance ([link](https://developer.apple.com/app-store/product-page/)):

- The first 1-3 screenshots show in search results when there is no preview.
- Each later screenshot should carry one benefit.
- If the app supports Dark Mode, include at least one Dark Mode screenshot.
- Screenshots must show the app in use, per [App Review Guidelines 2.3](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata).

### 3.2 Mac app preview spec ([Apple](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications))

| Property | Value |
|---|---|
| Resolution | 1920x1080, 16:9, landscape only |
| Length | 15-30 s |
| Codec | H.264 (.mov/.m4v/.mp4; 10-12 Mbps; High Profile 4.0; progressive) or ProRes 422 HQ (.mov, about 220 Mbps) |
| Frame rate | at most 30 fps |
| Size | at most 500 MB |
| Audio | stereo, AAC 256 kbps (or PCM for ProRes), 44.1 or 48 kHz |
| Count | up to 3 per localization |
| Processing | up to 24 h after upload |

Recommendation: skip the preview for v1.0. Revisit when there is a stage-mode demo worth 20 seconds. It must autoplay muted, so it should read without sound.

### 3.3 Localization

- **Languages:** metadata can be localized into 50 languages and locales ([App Store localizations](https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations)). This includes Hindi and nine other Indian languages (added 2026-03-31 per [Adapty](https://adapty.io/blog/markdown/custom-product-pages-app-store.md); the current Apple list confirms them).
- **Storefront defaults that matter to Segue:**
  - **USA:** default English (US). Additional supported languages: Arabic, Chinese (Simplified/Traditional), French, Korean, Portuguese (Brazil), Russian, Spanish (Mexico), Vietnamese.
  - **India:** default **English (U.K.)**. Additional: Bangla, Gujarati, Hindi, Kannada, Malayalam, Marathi, Odia, Punjabi, Tamil, Telugu, Urdu.
- **Implication:** an **English (U.K.)** localization is what India (and the UK) see by default. It carries its own name, subtitle and 100-byte keyword set. That gives Segue a second, India-tuned keyword field for romanized Hindi and Bollywood terms without diluting the US set.
- **Cross-locale keyword indexing (UNVERIFIED):** industry sources claim that keywords from a storefront's additional languages are also indexed in that storefront. Apple does not document this, so don't rely on it.
- **No Devanagari:** do not ship a Hindi (Devanagari) localization. The app does not display Devanagari (vision doc, Language row).

### 3.4 Custom product pages and product page optimization

- **Custom product pages:** up to 70 per app, each with its own screenshots, promo text and keywords. They are "available on the App Store on iOS 15 and iPadOS 15, or later" ([Apple](https://developer.apple.com/help/app-store-connect/create-custom-product-pages/configure-multiple-product-page-versions)). They are **not available for a Mac-only app**.
- **Product page optimization (A/B tests):** "Optimize your iOS or iPadOS app's product page" ([Apple](https://developer.apple.com/help/app-store-connect/create-product-page-optimization-tests/overview-of-product-page-optimization)). Also **not available for Mac**.
- Both become relevant once the phase-7 iPad app ships.

---

## 4. Screenshot tooling plan (free, reproducible)

### 4.1 Survey

| Tool | Mac support | Cost / licence | Verdict |
|---|---|---|---|
| fastlane `snapshot` / `capture_ios_screenshots` | The action metadata lists Mac, but it "simply does not work for macOS" ([Jesse Squires, 2025](https://www.jessesquires.com/blog/2025/03/24/automate-perfect-mac-screenshots/); [Michael Tsai](https://mjtsai.com/blog/2025/04/22/automating-screenshots-for-the-mac-app-store/)) | free, MIT | Build informed by it: same idea (XCUITest + attachments), our own runner. |
| XCUITest `XCUIElement.screenshot()` + `XCTAttachment` | Yes, and already used in `UITests/SegueSetlistE2ESupport.swift` (`screenshot(_:_:)`) | free | **Adopt.** This is the capture layer. |
| `xcrun xcresulttool export attachments --path X.xcresult --output-path dir` | Yes. Verified present in Xcode 26.6 here. Writes a `manifest.json` that maps attachments to tests. | free | **Adopt.** No need for third-party `xcparse`. |
| fastlane `frameit` | Claims "iOS, macOS and Android" frames; needs ImageMagick ([docs](https://docs.fastlane.tools/actions/frameit/)) | free, MIT | Use as a reference only. Whether its Mac frame set is current is **UNVERIFIED**. ImageMagick plus Ruby is a heavy dependency just to put text on an image. |
| fastlane `deliver` | `platform: "osx"` supported; uploads localized metadata text and screenshots ([docs](https://docs.fastlane.tools/actions/deliver/)) | free, MIT | Optional adopt for upload. Install Ruby and fastlane via mise, never globally. |
| App Store Connect API (`appScreenshotSets`, `APP_DESKTOP`) | Yes | free | Alternative to `deliver`. More code. |
| ImageMagick | Yes | free (ImageMagick licence) | Workable compositor. Font and kerning control is weaker than CoreText. |
| **Swift + CoreGraphics/CoreText/ImageIO script** | Yes | free (system frameworks) | **Recommended compositor.** Pixel-exact, uses the bundled Schibsted Grotesk and the brand tokens from `design/tokens.json`, and can strip alpha. |
| `screencapture -l<windowID> -o` | Yes | free | Fallback for manual shots. `-o` drops the shadow. |
| Retrobatch, Rotato, Screenshots.pro, ButterKit, AppLaunchpad | | paid | Excluded (no paid tools). |

### 4.2 Pipeline

1. **Test class.** Add `UITests/AppStoreScreenshots.swift`, with one test per shot so a failure re-runs one shot. Run it with `make screenshots`. The Makefile target:
   - runs only that class (`-only-testing:SegueUITests/AppStoreScreenshots`);
   - sets `-resultBundlePath .build/screenshots/run.xcresult`;
   - keeps it out of `make e2e` so normal runs stay fast.
2. **Deterministic state**, set up in Debug builds only, behind the existing `UITesting.isActive` gate plus a new `-SegueScreenshotMode YES` argument:
   - Seed a **demo library**: original or public-domain songs only. That means traditional or public-domain hymns plus a few songs written for the demo, including one romanized Hindi song written for Segue. Never copyrighted lyrics: that is an IP risk under Review Guideline 5.2, and the screenshots are public.
   - Fixed window **content size 1440x900 pt**. On a Retina display the window capture comes out at 2880x1800 px when the window frame is that size; verify which frame (content vs frame incl. title bar) yields exactly 16:10.
   - Frozen clock for set timers (injectable clock already exists per the architecture principles). Hide the cursor. No request toasts mid-animation. Reduce Motion on, so captures are not mid-crossfade.
   - Appearance per shot. Pass `-AppleInterfaceStyle Dark`, or better an app-side `-SegueAppearance dark|light` that sets `NSApp.appearance`. Whether the argument-domain trick works on macOS 26 is **UNVERIFIED**; the app-side switch is deterministic.
3. **Capture.** Each test ends with `XCTAttachment(screenshot: app.windows.firstMatch.screenshot())`, named `appstore-<NN>-<slug>-<light|dark>`, with `lifetime = .keepAlways`.
4. **Export.** Run `xcrun xcresulttool export attachments --path .build/screenshots/run.xcresult --output-path .build/screenshots/raw`, then rename files from `manifest.json` into `.build/screenshots/raw/<name>.png`.
5. **Compose.** `scripts/compose-screenshots.swift` reads `design/appstore/screenshots.json` (per locale: shot name, caption, sub-caption, variant `framed|fullbleed`) and writes `.build/screenshots/final/<locale>/<NN>.png` at 2880x1800, with no alpha, in the sRGB colour space.
   - **framed:** `ground` background, caption in Schibsted Grotesk 800 (-0.035em), window image scaled to about 82% width, 24 pt-radius corner mask, 1 px `line` border, soft shadow.
   - **fullbleed:** the raw 2880x1800 capture with alpha stripped.
6. **Verify.** Run `sips -g pixelWidth -g pixelHeight -g hasAlpha` on every output and fail on anything other than 2880x1800 with `hasAlpha: no`. Then eyeball the contact sheet for pixel issues.
7. **Upload.** Either drag the files into App Store Connect, or use `fastlane deliver --platform osx --skip_binary_upload`, with metadata kept in git as `fastlane/metadata/<locale>/*.txt`. That makes the store text versioned and reviewable alongside the code.

**Open question (needs Ryan):** screenshots should come from the **App Store flavor**, so that no personal-only features are visible. Today only `Debug-Personal` has the sandbox temporary exception that lets E2E seed a library via `-SegueLibraryPath` (`Project.swift:131`). Options:

- **(a)** Grant the same exception to `Debug-AppStore` only. It is never in a release build.
- **(b)** Have the app copy a bundled demo library into its container when `-SegueScreenshotMode` is set (Debug only).
- **(c)** Shoot from `Debug-Personal`, with restricted modules hidden by a flag.

My preference is **(b)**: no entitlement drift, and it is the same mechanism a future "Try the demo library" onboarding could use.

### 4.3 Proposed shot list (8 of 10 slots, 2880x1800)

| # | Shot | Appearance | Caption (draft) |
|---|---|---|---|
| 1 | Stage mode mid-song: header, gutter labels, Up next footer, progress dots | Dark | Your chart, your set, your cue. |
| 2 | Setlist builder with running time | Light | Build tonight's set in minutes. |
| 3 | Library with quick search hit on a romanized Hindi lyric | Light | Find any song by a line you half-remember. |
| 4 | Editor: text and visual, chords over syllables | Light | Edit ChordPro, or drop chords on the syllable. |
| 5 | Transpose + capo + Nashville + chord diagrams | Light | Transpose, capo, Nashville numbers. |
| 6 | Crowd request queued mid-show | Dark | Take a request without leaving the stage. |
| 7 | Auto-fit vs min-font scroll (two-column fit) | Dark | Every song fits the screen. Or scrolls, never shrinks. |
| 8 | Show checklist / crash resume prompt | Dark | Back where you were, even after a crash. |

---

## 5. Competitor survey

Data is from US App Store pages fetched 2026-10-17. Ratings are as shown on the page; they are the iOS/iPadOS rating unless the app is Mac-only. Mac-only listings showed no rating, which suggests too few ratings to display; I did not find a Mac-only rating count for any of them. IAP lists are the top entries Apple shows (the page truncates at about 10), so they are not exhaustive. "iPad-on-Mac" means the Mac App Store lists it as "Designed for iPad" (often "Not verified for macOS") and it needs an Apple-silicon Mac.

### 5.1 Main players

| App | Platforms | Mac availability | Price model (US) | Rating | What the page emphasises |
|---|---|---|---|---|---|
| [OnSong 2026](https://apps.apple.com/us/app/id1330350343) | iPhone, iPad, Mac, Vision | Universal; macOS 11+ | Free for 30 songs, account required. Essentials $3.99/mo or $29.99/yr; Premium $5.99/mo or $59.99/yr | 4.5 (5.6K) | "Chords, Music, Setlists, MIDI+". Breadth of features, sharing sets with other users. Rated 16+. |
| [SongbookPro](https://apps.apple.com/us/app/id1475370014) | iPhone, iPad, Android, Windows; Mac desktop version off-store | iPad-on-Mac (macOS 15+, M1+). Separate desktop build sold on its own site: **UNVERIFIED** price, about $7 one-time per [AlternativeTo](https://alternativeto.net/software/songbookpro/about) | Free trial (12 songs per AlternativeTo, **UNVERIFIED**); Full Version Upgrade $5.99 one-time | 4.7 (2.7K) | "Replaces the hassle of carrying chord charts". Laptop or tablet. Cross-platform. |
| [BandHelper](https://apps.apple.com/us/app/id552012927) ([Mac](https://apps.apple.com/us/app/id1503592748)) | iPhone, iPad, Watch, Mac (separate Mac app), Android, web | Native Mac app; macOS 12.5+ | Free + subscription: Basic solo $3/mo or $18/yr; Pro solo $4/mo or $38/yr; band tiers $5-23/mo | 4.3 (113) iOS | "Organizational suite for bands". Band management, live show control, MIDI, sharing. |
| [Set List Maker](https://apps.apple.com/us/app/id410496349) ([Mac](https://apps.apple.com/us/app/id1501218437)) | iPhone, iPad, Mac | Native Mac app; macOS 12.5+ | $19.99 upfront + IAP add-ons $2.99-4.99 | 3.7 (87) | Says itself "no longer adding new features"; points to BandHelper. |
| [SongSheet Pro](https://apps.apple.com/us/app/id581094194) | iPhone, iPad | iPad-on-Mac status not shown on page (**UNVERIFIED**) | Free + sub $2.99/wk, $5.99/mo, $59.99/yr; lifetime $129.99 | 4.7 (2.7K) | "Setlist helper". Songbook, transposing, auto-scroll, pedals, lyric projection, worship. |
| [forScore](https://apps.apple.com/us/app/id363738376) (adjacent: PDF sheet music) | iPhone, iPad, Mac, Vision | Universal; macOS 15+ | $24.99 upfront + forScore Pro $14.99/yr (or $2.99 30-day pass) | 4.8 (43K) | "Turbocharge your sheet music". The category leader for PDF scores. |
| [MobileSheets](https://apps.apple.com/us/app/id1620569987) (adjacent: PDF + ChordPro) | iPad, iPhone, Android, Windows | iPad-on-Mac (macOS 15+, M1+) | $15.99 upfront; free "Lite" trial app | 4.6 (66) | Sheet music manager and viewer; cross-platform. |
| [Planning Center Music Stand](https://apps.apple.com/us/app/id368561278) | iPhone, iPad | iPad-on-Mac, "Not verified for macOS" | Free app; needs a paid Planning Center Services account | 3.5 (325) | Church worship team sheet music tied to PCO. Category: Business. |
| [SongBook Chordpro (LinkeSOFT)](https://apps.apple.com/us/app/id392888837) ([Mac](https://apps.apple.com/us/app/id534978338)) | iOS, Mac, Android, Windows | Separate native Mac app; macOS 12+ | iOS $19.99 + optional Yearly $19.99 / Monthly $1.99 IAP; Mac $19.99 upfront; Mac+iOS bundle | 4.7 (2.4K) iOS, #81 Music | "Your lyrics and chords". ChordPro, long-running (since 2010). |
| [LivePrompter 2](https://apps.apple.com/us/app/id6451310318) | iPhone, iPad (also Windows v1) | iPad-on-Mac, not verified | Free | 3.4 (5) | "A live musician's teleprompter". Auto-scroll lyrics and chords. |
| [Charts by WorshipTools](https://apps.apple.com/us/app/id1511797596) | iPhone, iPad | iPad-on-Mac, not verified | Free | 4.8 (1.6K) | Worship song chord charts, team sharing. |
| [iReal Pro](https://apps.apple.com/us/app/id409035833) (adjacent) | iOS, Mac, Android | Native Mac app | Mac $21.99 + style packs $6.99 | n/a on Mac page | Backing band plus chord-chart library. |
| [Chordify](https://apps.apple.com/us/app/id1073624757) / [Ultimate Guitar](https://apps.apple.com/us/app/id357828853) (adjacent, content) | iPhone, iPad | Not on the Mac App Store as Mac apps (none shown) | Subscriptions about $42-54/yr; UG Pro $29.99-39.99/yr | 4.7 (34K) / 4.7 (480K) | Chord discovery for existing songs. They own the "chords" keyword volume on iOS. |

### 5.2 Smaller, newer and niche apps

| App | Platforms | Mac | Price model | Rating | Positioning |
|---|---|---|---|---|---|
| [Leganote - Chord Charts](https://apps.apple.com/us/app/id6775335225) | Mac only (iOS sibling exists) | **Native Mac**; macOS 14+ | **$5.99 once, "No subscription. Ever."** | none shown | "A native Mac chord-chart app": ChordPro, MusicXML, backing tracks, source-list sidebar. Closest Mac-native peer in tone. |
| [Songbook Buddy](https://apps.apple.com/us/app/id436128125) | iPhone, iPad, Mac | Universal; macOS 12+ | Free start; Basic $6.99 permanent; Pro $24.99/yr; Pro Cloud $69.99/yr | none shown | ChordPro editor + stage layouts. Successor to [ChordPro Buddy](https://apps.apple.com/us/app/id434955766) (Mac, end of life). |
| [GigNotes](https://apps.apple.com/us/app/id1536908681) | iPhone, iPad, Mac | Universal; macOS 12+ | Free + $2.49/mo, $23.99/yr; seat packs | 4.7 (34) | "Chords, setlists & transpose". Works offline. |
| [LeadSheets](https://apps.apple.com/us/app/id6790560155) | iPhone, iPad, Mac | Universal; macOS 14.6+ | **Free**, no IAP shown | none | Band songbook: chords, lyrics, PDFs, setlists. New in 2026. |
| [SongDeck - Setlist Manager](https://apps.apple.com/us/app/id6775893589) | iPhone, iPad, Mac | Universal; macOS 14+ | **Free**, no IAP shown | 5.0 (4) | "Free, simple, minimal setlist manager". Closest free positioning to Segue. |
| [Setlister](https://apps.apple.com/us/app/id6757764995) | iPhone, iPad, Mac | Universal; macOS 15.7+ | Free | none | Band management: setlists, rehearsals, finances, merch. |
| [SUS4 Setlist](https://apps.apple.com/us/app/id6777230255) | iPhone, iPad, Mac, Watch | iPad-on-Mac (macOS 13+, M1+) | Free + $0.99/mo; $4.99 All-Access; $59.99 lifetime | none | Key, tempo and capo running order; works offline. |
| [SongBook+](https://apps.apple.com/us/app/id447755419) | iPhone, iPad, Mac | Universal; macOS 12+ | Free + $1.99/mo, $20.49/yr, $49.99 full; "sponsor" tiers | 4.4 (162) | Lyrics, scores, playback, MIDI. |
| [Òrain](https://apps.apple.com/us/app/id6808541376) | iPhone, iPad, Mac | Universal; macOS 14+ | Free for 10 songs, then **$7.99 lifetime** | none | Gaelic/Scots songbook. Chords over the syllable, offline. A good model for culturally specific positioning (compare Segue's romanized Hindi). |
| [Bandfix](https://apps.apple.com/us/app/id6499341499) | iPhone, iPad | not shown | Free + $1.99-9.99/mo, $19.99-99.99/yr; tip jar | 5.0 (71) | "The Modern Gig Binder". |
| [Songbookly](https://apps.apple.com/us/app/id6739998746) | iPhone, iPad | iPad-on-Mac | Free + $2.99/mo, $17.99-24.99/yr, $8.99/wk | 4.6 (109) | Practice tracking, songbook. |
| [QMe Teleprompter Lyrics Chords](https://apps.apple.com/us/app/id6756925805) | iPhone, iPad, Watch; "QMe Stage runs the show from your Mac" | iPad-on-Mac | Free + $2.99/mo, $29.99/yr, $149.99 lifetime, QMe Stage $49.99 | 5.0 (20) | Teleprompter positioning, Mac as stage controller. |
| [Gig Hard!](https://apps.apple.com/us/app/id646869254) | iPhone, iPad | iPad-on-Mac | Free + $6.95/mo, $59/yr, $149.99 | 4.0 (13) | "Setlist Teleprompter for Bands". |
| [Setlist Helper](https://apps.apple.com/us/app/id939098002) | iPhone, iPad | iPad-on-Mac | Free + $14.99 full version | 4.0 (9) | Lyrics into setlists. |
| [All Set](https://apps.apple.com/us/app/id1453232689) | iPhone, iPad | iPad-on-Mac | Free (20 songs) + $1.99 / $3.99 unlocks | 4.4 (104) | Setlists; last updated 2022. |
| [Songbook Pro - Mezzo](https://apps.apple.com/us/app/id1608995158) | iPhone, iPad | iPad-on-Mac | Free + $6.99/mo, $49.99/yr, $59.99-199.99 lifetime | 4.6 (69) | Band sharing, sync. |
| [ChordBook Pro](https://apps.apple.com/us/app/id6800106723) | iPhone, iPad | iPad-on-Mac | Free + Premium (7-day trial; prices not listed) | none | "Every chord sits above the syllable". |
| [GigBook Stage](https://apps.apple.com/us/app/id6762559946) | iPhone, iPad | iPad-on-Mac | Free + $2.99/mo, $29.99 lifetime | none | Songs, chords, setlists, Guitar Pro. (Confirms the earlier Gigbook name collision.) |
| [Setlist Lab](https://apps.apple.com/us/app/id6760688150) | iPhone, iPad | iPad-on-Mac | $3.99/mo, 7-day trial | none | Auto-builds sets to length. Overlaps Segue's planned set assistant. |
| [MySongbook Music Binder](https://apps.apple.com/us/app/id553792506) | Mac (+iOS) | Native Mac; macOS 10.9+ | $9.99 | none | Stale (2020). |
| [ChordProEditor [C]](https://apps.apple.com/us/app/id6749023767) | Mac | Native | $9.99/mo, $99.99/yr | none | ProPresenter worship niche. |
| [Chord Provider](https://github.com/Desbeers/Chord-Provider) | Repo now describes Linux; listed as a "native macOS" ChordPro editor on [chordpro.org links](https://chordpro.org/beta/links/) | off-store | free, GPL-3.0 | n/a | Open-source ChordPro viewer. Current Mac status **UNVERIFIED**. |

### 5.3 What the landscape tells us

- **Native Mac is thin.** Most chord and setlist apps reach the Mac only as iPad apps, often "Not verified for macOS". The Mac-native or universal ones are:
  - OnSong, forScore, BandHelper, Set List Maker (frozen), LinkeSOFT SongBook and iReal Pro;
  - plus a 2025-26 wave of indie universal apps: Leganote, Songbook Buddy, GigNotes, LeadSheets, SongDeck, Setlister, Òrain.
- **Accounts and subscriptions are the norm** at the top. OnSong needs an account and a subscription beyond 30 songs. "Free, files, no account" is a genuine differentiator, and "no subscription" is clearly a selling point (Leganote leads with it).
- **Recurring pitches:** "replace the binder", setlists, transpose, auto-scroll, pedals, offline, band sharing.
- **What nobody leads with:**
  - auto-fit stage layout with a minimum font;
  - a crash-resume guarantee;
  - Nashville numbers;
  - romanized Hindi;
  - plain ChordPro files you own.
  These are Segue's angles.
- **Free competitors exist** (LeadSheets, SongDeck, Setlister), so "free" alone is not the hook. "Free and a real Mac app built for the stage" is.

---

## 6. Recommendations (free app, no IAP)

### 6.1 Category

- **Primary: Music.** Apple's definition covers apps for "performing" music, and every direct competitor sits there. It already matches `public.app-category.music` in Xcode.
- **Secondary: Productivity.** Organising a library and sets fits "make a specific process or task more organized". The alternative is Entertainment, which fits worse. Planning Center Music Stand uses Business, which fits Segue worse still.
- Source: [Apple categories](https://developer.apple.com/app-store/categories/).

### 6.2 Pricing (context, given the decision)

| Option | Fits Segue? | Notes |
|---|---|---|
| **Free, no IAP (chosen)** | Yes | Simplest paperwork: free apps need only the Developer Program License Agreement, with no Paid Apps Agreement, banking or tax forms ([Apple](https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements)). Removes the purchase barrier against OnSong's subscription. Supports a non-trader DSA declaration (7.2). Positioning is "free, no ads, no subscription, no account". |
| Paid upfront ($5.99-19.99) | Viable later | Peers: Leganote $5.99, LinkeSOFT $19.99, forScore $24.99. Paid apps get no free trial on the Mac App Store. |
| Free + one-time unlock ($5.99-9.99) | Viable later | Peers: SongbookPro $5.99, Òrain $7.99, Songbook Buddy $6.99. Would need the Paid Apps Agreement and StoreKit. |
| Subscription | Poor fit | Local-only app with no server cost. It would contradict the "no subscription" positioning. |

Note for later: switching a free app to paid is possible (price is editable anytime). Taking features away from existing free users into an IAP is a trust cost. If monetization ever comes, a one-time "supporter" unlock for **new** features is the gentlest path.

### 6.3 Name, subtitle, keywords

- **Name:** "Segue - Setlists & Chords" (25 chars). It indexes *segue*, *setlists* and *chords*. Plain "Segue" is taken by two iOS apps, so the suffix is necessary anyway.
- **Subtitle candidates** (30 chars max; the count is shown):
  1. **"Lyrics & chords for live gigs"** (29). Adds *lyrics*, *gigs* and *live* to the index. **Recommended.**
  2. "Stage-ready lyrics and chords" (29). Adds *stage* and *lyrics*.
  3. "ChordPro songbook & stage mode" (30). Adds the niche *chordpro*, *songbook* and *stage*.
  4. "Your chart, your set, your cue" (30). The brand tagline, but it adds no search value. Put it in the promo text and the first screenshot caption instead.
  5. "Chord charts for the stage" (26).
- **Keywords for English (US)**, with subtitle 1 (100 bytes exactly, verified with Python `len(s.encode())`):
  ```
  chordpro,songbook,transpose,teleprompter,worship,band,guitar,piano,capo,nashville,stage,singer,cover
  ```
  - It leaves out words already in the name or subtitle (setlist, chords, lyrics, live, gig) and the word "app".
  - Swap candidates: *autoscroll*, *prompter* (shorter than teleprompter), *repertoire*, *chart*, *open mic*.
  - Flag: *band* and *worship* are relevant (worship and cover band leaders are named users), but Segue has no band-sharing feature. If reviews complain, drop *band*.
- **Keywords for English (U.K.)** (India and UK default; 100 bytes):
  ```
  hindi,bollywood,bhajan,chordpro,songbook,transpose,teleprompter,worship,band,guitar,piano,capo,stage
  ```
  - Use these only if the romanized Hindi support is shown in screenshots and the description, to stay inside Guideline 2.3.7 relevance.
  - *bhajan* assumes devotional Hindi songs are a real use. **Ryan to confirm.**
- Don't use competitor names (OnSong, forScore and so on). Apple forbids them.

### 6.4 Promotional text (166 / 170 chars, editable anytime)

```
Your chart, your set, your cue. Segue keeps your songs as ChordPro files, builds tonight's set, and fits every song on one screen on stage. Free, offline, no account.
```

### 6.5 Description draft (about 2,300 / 4,000 chars)

Each bullet must be checked against the App Store build before submission. Remove anything that is not shipped in the App Store flavor: Shortcuts specifics, show checklist, running time, VoiceOver claims, keep-awake. Never mention personal-only features (audio, LRCLIB, URL import).

```
Segue is a chord chart and setlist app for performing musicians, built for the Mac. Keep your songs as plain ChordPro files, build tonight's set, and play it from a stage view that fits each song on one screen.

Made for the singer with a guitar, the keys player at an open mic, the duo working a three-hour bar gig, and the worship or cover band leader who needs the chart in front of them, not a binder.

YOUR SONGS, AS FILES
- One ChordPro file per song in a folder you choose. No account, no sign-in, no cloud.
- Your library stays readable by other ChordPro tools, so your songs are never locked in.
- Fast search across titles, artists and lyrics, including romanized Hindi lyrics with loose, casual spelling.
- Tags and proficiency marks (Learning, Ready, Pro) so you know what is gig-ready.

AN EDITOR THAT KEEPS UP
- Edit the ChordPro text directly, or drop chords onto syllables in the visual editor.
- Transpose in one step, with a capo toggle that shows shapes or concert pitch.
- Nashville number view for when the singer changes key at the last minute.
- Guitar chord diagrams, including alternate tunings and custom shapes, plus piano voicings.
- Spell-check and autocorrect stay out of your lyrics.

SETLISTS IN MINUTES
- Drag songs into a set, reorder, and see the running time.
- A show checklist so nothing is forgotten before you go on.

STAGE MODE
- A dark stage view that auto-fits each song to the screen, with columns and scale chosen for you.
- Set your own minimum font size; when a song cannot fit, Segue scrolls instead of shrinking it.
- Auto-scroll that you can pause and resume.
- An "Up next" footer with the next song's key and capo.
- Quick search mid-show: a request comes in, find it, queue it, play it.
- Skip, reorder and mark songs as played without leaving the stage view.
- If Segue quits unexpectedly mid-gig, it reopens right where you were.
- Keeps the display awake while you play.

WORKS WITH YOUR MAC
- Shortcuts actions for your sets and shows.
- Native macOS design with light and dark appearance and full keyboard control.
- Works fully offline. Nothing on stage depends on a network.

PRIVATE BY DESIGN
Segue collects no data. Your songs stay on your Mac, in files you own.

Segue is free, with no ads, no subscription and no in-app purchases.
```

Writing notes:

- The first sentence carries the search-visible pitch.
- The text avoids naming competitors, avoids prices other than "free", and makes no claims about other apps.
- Apple's guide says to avoid specific prices. "Free" is a business-model statement and appears in many approved listings, but if review objects, cut the last line and keep "no subscription".

### 6.6 Other fields

| Field | Value |
|---|---|
| Copyright | `2026 Ryan D'Silva` (legal name as on the developer account; **confirm**) |
| Support URL | a page with email plus the contact details Apple requires (see 05-landing-page.md) |
| Marketing URL | the landing page |
| Privacy policy URL | required; "Segue collects no data" policy page |
| App privacy | Data Not Collected |
| Age rating | answer the questionnaire honestly. The App Store build has no web access or UGC sharing, so expect the lowest tier; see 03-review-risk.md |
| What's New | n/a for 1.0 |
| App Review notes | how to open the bundled demo library, how to enter stage mode, and that the app needs no account |

---

## 7. Decisions for Ryan

1. **Subtitle:**
   - (a) "Lyrics & chords for live gigs" (recommended)
   - (b) "Stage-ready lyrics and chords"
   - (c) "ChordPro songbook & stage mode"
   - (d) tagline "Your chart, your set, your cue"
   - (e) something else
2. **DSA trader status (EU):**
   - **Non-trader:** fits a hobby, non-commercial free app. EU users see a notice that consumer-protection rights don't apply.
   - **Trader:** your address or P.O. box, phone and email are **published** on the product page.
   - Alternatively, don't distribute in the EU.
   - Source: [Apple DSA](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements).
3. **English (U.K.) localization for India/UK** with the Hindi/Bollywood keyword set: yes or no. Is *bhajan* in or out?
4. **Keywords *band* / *worship*:** keep or swap them for *autoscroll*, *repertoire* or *open mic*?
5. **Screenshot seeding for the App Store flavor:**
   - (a) give `Debug-AppStore` the sandbox exception;
   - (b) seed a bundled demo library into the container (recommended);
   - (c) shoot from Personal with features hidden.
6. **Screenshot style:**
   - framed with captions on a brand background (recommended for shots 2-8);
   - full-bleed raw window (recommended for hero shot 1);
   - all framed or all full-bleed.
   - Per your preference, I can mock 2-3 directions on the design canvas before building the compositor.
7. **Upload path:** manual drag-and-drop or fastlane `deliver` (Ruby via mise) with metadata versioned in git.
8. **App preview video for 1.0:** skip (recommended) or make one.
9. **Secondary category:** Productivity (recommended) or Entertainment.

---

## 8. Sources

Apple (all fetched 2026-10-17):

- App information fields: https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
- Platform version information: https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information
- Required, localizable, editable properties: https://developer.apple.com/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties
- Screenshot specifications: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
- App preview specifications: https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications
- App Store localizations: https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations
- Custom product pages: https://developer.apple.com/help/app-store-connect/create-custom-product-pages/configure-multiple-product-page-versions
- Product page optimization: https://developer.apple.com/help/app-store-connect/create-product-page-optimization-tests/overview-of-product-page-optimization
- Product page guidance: https://developer.apple.com/app-store/product-page/
- Categories: https://developer.apple.com/app-store/categories/
- Agreements (free apps need no Paid Apps Agreement): https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements
- EU DSA trader requirements: https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements
- ScreenshotDisplayType (`APP_DESKTOP`): https://developer.apple.com/documentation/appstoreconnectapi/screenshotdisplaytype
- App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/

Tooling:

- Jesse Squires, "Automate perfect Mac screenshots" (2025): https://www.jessesquires.com/blog/2025/03/24/automate-perfect-mac-screenshots/
- Michael Tsai, roundup: https://mjtsai.com/blog/2025/04/22/automating-screenshots-for-the-mac-app-store/
- fastlane frameit: https://docs.fastlane.tools/actions/frameit/
- fastlane deliver: https://docs.fastlane.tools/actions/deliver/
- `xcrun xcresulttool help export attachments` (local, Xcode 26.6 build 17F113)

Competitors: the App Store URLs are linked in the tables in section 5 (US storefront, fetched 2026-10-17). Also:

- iTunes Search API: `https://itunes.apple.com/search?entity=software|macSoftware`
- ChordPro links page: https://chordpro.org/beta/links/
- Chord Provider: https://github.com/Desbeers/Chord-Provider
- SongbookPro desktop pricing: https://alternativeto.net/software/songbookpro/about (UNVERIFIED secondary source)
- MobileSheets: https://zubersoft.com/mobilesheets/buy/ipados
