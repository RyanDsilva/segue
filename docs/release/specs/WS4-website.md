# WS4 - Landing website (segue.ryandsilva.dev)

Status: **final, implementation-ready.** All earlier open questions are resolved (section 0); the short list at the end holds only questions that came up while finalising.
Date: 2026-10-17.

**Canonical inputs** (read them first; this spec follows them and wins only where it is more specific):

- `docs/release/decisions.md`: R3 (store name, subtitle, categories), R5 (first version `0.5`), R7 (Apple standard EULA; short site terms), R10 (screenshots), R21 (help docs at `/help`), R23 (hosted vendors only: TelemetryDeck, Sentry, Featurebase, Apple App Analytics), R24 (bug reports in Sentry only, no GitHub bridge), R25 (separate consent toggles; Sentry per-install ID kept), R26 (opt-in analytics, coarse country, optional email on board posts), R27 (Cloudflare Pages, source in `website/`, CNAME at Squarespace), R28 (`segue@ryandsilva.dev`), R29 (page list, `/feedback` redirect), R30 (copyright and legal name), R31 (Washington law), R32 (retention), R33 (Sentry US region, SCCs), R34 (own minimal TelemetryDeck client), R38 (Cloudflare Web Analytics), R39 (design directions first), R41 (arm64 only), R55 (the home design and copy).
- `docs/release/open-questions.md`: every A item resolved to its **Recommend** option unless R30-R41 overrides it; every B item at its default; section 4 cross-spec resolutions applied. Section 0 below lists everything that touches WS4.
- `docs/release/specs/WS3-services.md` section 5 (event vocabulary) and section 10 (vendor facts, App Privacy label). The privacy policy here is written to match them (I-9).
- `docs/release/research/05-landing-page.md` (main research input), `04-store-listing.md` (positioning, copy drafts).
- `docs/brand.md`, `design/tokens.json`, `scripts/gen-tokens.swift`, `design/icon/`, the bundled fonts in `Packages/SegueUI/Sources/SegueUI/Theme/Fonts/`.
- Design canvas: https://claude.ai/artifact/XizqyqzA1chVfBSGThAzcQ (brand direction C "Precise"; `docs/brand.md` section 10 lists "Landing page" as a canvas deliverable).

**Rules for the implementing agent**

- Sibling agents may be editing other files in this repo at the same time. Expect a dirty `git status`; never treat their edits as conflicts and never revert them.
- In Bash never use plain `cat` (it is aliased to `eza` and hangs). Use `command cat` or the Read tool. Pass this warning on to any subagent you spawn.
- No em dashes anywhere (code, copy, comments). Use "-".
- Do not push, and do not touch Cloudflare, Squarespace, Mailgun, Featurebase, TelemetryDeck, Sentry or App Store Connect. Those are [RYAN] steps. Commit locally and signed (`git commit -S`), one commit per logical unit. If signing fails with "failed to fill whole buffer", 1Password is locked: keep the staging, ask Ryan to unlock, and wait.
- Tools come from `.mise.toml` via `mise exec --`. Python tooling runs through `uv`/`uvx`. Never install anything globally.
- "[VERIFY]" markers in this spec are instructions to you. They are never copied into HTML: either confirm the claim in the 0.5 App Store build and keep it, or delete the claim.
- If any vendor fact you re-read (section 9.4 preamble) differs from this spec, stop and ask Ryan rather than rewording the policy yourself.

---

## 0. Decisions applied (from `decisions.md` and `open-questions.md`)

| Item | Ruling | Where it lands |
|---|---|---|
| R23/R24, I-8 | Vendors fixed: TelemetryDeck (analytics), Sentry (crashes, hangs, MetricKit, bug reports via User Feedback), Featurebase (board), Apple App Analytics. No GitHub bridge, no "TBD vendor" text. | `site.json` vendors (4), privacy policy (9.4) |
| R34 (A6) | TelemetryDeck receives signals from our own minimal client: only WS3 section 5 parameters plus app version, macOS version and region. No SDK default parameters. | Policy "Usage statistics" |
| A7 | Event list = WS3 section 5 plus a romanized-Hindi search-hit metric and chord-palette use. | Policy "What is sent" examples |
| A8 | Coarse Location (country, from the Mac's region setting) is declared. | Policy, label match |
| A9 | Bug-report data types are declared Linked; the report has an optional email field. | Policy "Bug reports" |
| R25, A10, I-7 | Two separate first-run questions ("Share usage analytics", "Send crash reports"), equal weight, as the last page of the Welcome flow. | Home privacy copy, policy |
| R33 (A5) | Sentry data region **US**; the policy notes US processing under Standard Contractual Clauses. | `site.json`, policy transfers |
| R32 (A4) | Retention: TelemetryDeck's default, stated plainly; bug reports and crash reports 30 days; board posts until deleted; support email at most 2 years. Ryan asks TelemetryDeck about a shorter period in parallel (R-10). | Retention table |
| R30 (A1) | `© 2026 Ryan Rony Dsilva` everywhere; "Ryan Rony Dsilva" is the controller and the "we" of the terms. | `site.json owner.legalName`, footer, policy, terms, press |
| R31 (A2) | Terms governed by the law of the State of Washington. | Terms section 12 |
| A3 | Controller contact by email only (`segue@ryandsilva.dev`); no postal address; no EU/UK representative (relying on GDPR Art. 27(2), not stated in the policy). | Policy "Who we are" |
| R38 (A54) | Website analytics: **Cloudflare Web Analytics** (cookieless, no banner), enabled in the Pages dashboard. CSP allows its beacon. | 9.3 `_headers`, 9.4 "This website", R-3, tests |
| A16, I-2, I-3, B-26 | `content/changelog.json` is the original; the generator writes `website/changelog.json`; the app **bundles that file only** (never fetches it) and shows the What's New sheet only for releases with `showInApp: true`. No separate bundled-copy output. | Section 6; policy and FAQ drop "fetch release notes" |
| I-5 | Canonical Help menu: Segue Help, Keyboard Shortcuts, Welcome to Segue..., What's New in Segue, Report a Problem..., Request a Feature..., Rate Segue on the App Store, Privacy Policy, Terms of Use, Acknowledgements. "Release Notes" is gone. | Sitemap, `/changelog` intro, support copy |
| I-6 | Settings > Privacy links the Privacy Policy and `/privacy#usage-statistics`; no Terms link. | Goal 2, sitemap |
| I-10, A24 | Import accepts `.cho`, `.chordpro`, `.chopro`, `.pro`, `.txt` (text imported as-is). | `/help/import#formats`, FAQ |
| I-16, B-32 | Section 2's URL and anchor table is the contract; `/help#trash` and `/help/library#trash` added; no accessibility page. | Section 2 |
| R41 (A59) | arm64 only: "Requires a Mac with Apple silicon and macOS 26 or later." | Home, support, press, JSON-LD |
| A34 | About panel links the web `/acknowledgements`. | Sitemap |
| A52 | One badge, in the home hero; the final call to action is a text link. | 7.1, 9.2 |
| A53 | Hero art: frameless window screenshot with the macOS shadow, stills only. | 7.2, 9.2 |
| A55 | Go live before the app with "Coming soon to the Mac App Store." and no badge. | `appStore.status: "upcoming"`, section 10 |
| A56 | Maker note included; the draft below is a placeholder Ryan rewrites in his own words. | 9.2 |
| A57 | Support reply time: "usually within a few days". | 9.6 |
| R39 (A41) | 2-3 home-page design directions as mockups, Ryan picks, then build. | Section 5.1, step 3 of section 14 |
| R55 | Home redesign, superseding R43 "Stage": C "Keynote" base and rounded tiles, B "House Lights" spotlight hero, copy as a musician's workflow (no days of the week). | 5.1, 5.2, 9.2 |
| A51 | Manual release after approval; Ryan flips the site to `live` at the same moment. | R-6 |
| B-27 | Preview deployments off for non-`main` branches. | R-3 |
| B-28 | DMARC `v=DMARC1; p=none` with no report address. | R-5 |
| B-29 | Versioned pre-push hook via `core.hooksPath` runs `make site-check STRICT=1` when `website/` or `content/` changed. | 8.3 |

---

## 1. Goal

Ship the static marketing, support and legal site for Segue at `https://segue.ryandsilva.dev`:

1. It satisfies App Store Connect: a live **Privacy Policy URL** and **Support URL** with real contact information, and a Marketing URL. It goes live before the app does (A55).
2. It is the app's web surface: the Help menu opens `/help/...`, `/privacy` and `/terms`; the What's New sheet's "All Release Notes" link opens `/changelog`; the app bundles the generated `changelog.json` at build time; "Request a Feature..." opens `/feedback` (a redirect to the Featurebase board, so the board can change without an app update); the consent step links `/privacy`; Settings > Privacy links `/privacy` and `/privacy#usage-statistics`.
3. It looks like Segue: dark-first and light-aware, Apple-native minimal (Linear and Things as references), Schibsted Grotesk, one coral cue used sparingly.
4. It costs nothing to run, ships **no JavaScript of our own and no cookies**, loads every asset from its own origin, and deploys automatically from `website/` on `main`. The only third-party code is Cloudflare Web Analytics' cookieless beacon, which Cloudflare injects at the edge in production (R38).

**Non-goals:** a blog, a newsletter, any other analytics or tracking, an Atom feed, a press zip, a `/roadmap` redirect, localisation, any server-side code (R23: no Pages Functions), a remote changelog feed for the app.

---

## 2. Sitemap and URL contract

Cloudflare Pages serves `foo.html` at `/foo` (and redirects `/foo.html` to `/foo`); it serves `foo/index.html` at `/foo/`. To keep the exact URLs from R29 (no trailing slash, no redirect hop for the URLs given to Apple), every page is a flat `.html` file.

| URL | File | Generated? | Linked from the app |
|---|---|---|---|
| `/` | `website/index.html` | slots only | Marketing URL, About panel |
| `/privacy` | `website/privacy.html` | slots only | Help > Privacy Policy, consent step, Settings > Privacy, bug-report preview, ASC Privacy Policy URL |
| `/terms` | `website/terms.html` | slots only | Help > Terms of Use |
| `/support` | `website/support.html` | slots only | ASC Support URL |
| `/help` | `website/help.html` | slots only | Help > Segue Help |
| `/help/library` | `website/help/library.html` | slots only | contextual help |
| `/help/import` | `website/help/import.html` | slots only | empty library state |
| `/help/editor` | `website/help/editor.html` | slots only | editor |
| `/help/setlists` | `website/help/setlists.html` | slots only | setlist builder |
| `/help/live` | `website/help/live.html` | slots only | stage, TipKit tips |
| `/help/shortcuts` | `website/help/shortcuts.html` | slots only | Settings > Live > Gig Mode Shortcuts |
| `/help/keyboard` | `website/help/keyboard.html` | slots only | web companion to Help > Keyboard Shortcuts (the in-app `?` overlay) |
| `/changelog` | `website/changelog.html` | **fully generated** | What's New sheet: "All Release Notes" and "and N more changes" |
| `/changelog.json` | `website/changelog.json` | **fully generated** | not fetched; the same file is bundled into the app at build time |
| `/press` | `website/press.html` | slots only | footer |
| `/acknowledgements` | `website/acknowledgements.html` | slots only | About panel (A34), footer |
| any unknown path | `website/404.html` | slots only | - |
| `/feedback` | `website/_redirects` | **fully generated** | Help > Request a Feature..., bug-report sheet link |
| `/favicon.ico` | `website/_redirects` -> `/favicon-32.png` | generated | - |
| `/sitemap.xml` | `website/sitemap.xml` | **fully generated** | - |
| `/robots.txt` | `website/robots.txt` | hand-written | - |

**Contract with the app workstreams.** The paths in this table, and these anchors, are a public contract the app links to (`SegueLinks` constants use only these). Never rename them without a redirect in `_redirects`:
`/help#trash`, `/help/library#trash`, `/help/live#requests`, `/help/live#minimum-size`, `/help/live#auto-scroll`, `/help/live#resume`, `/help/shortcuts#gig-mode`, `/help/import#formats`, `/help/keyboard#stage`, `/support#report-a-bug`, `/support#request-a-feature`, `/privacy#usage-statistics`, `/privacy#crash-reports`, `/privacy#bug-reports`, `/privacy#your-choices`.

`/help/foo` and `/help.html` coexisting: confirm in `make site-serve` that `/help` serves `help.html` and `/help/live` serves `help/live.html` (the Pages route matcher handles both; verify, since this is the one routing assumption the spec relies on). If it fails, fall back to `help/index.html` and add `/help /help/ 301` to `_redirects`.

---

## 3. File layout

```
content/                          canonical, hand-edited inputs (NOT published)
  site.json                       THE single config point: owner, vendors, App Store link, credits
  changelog.json                  canonical release notes, schema 1 (section 6)
  partials/
    header.html                   site nav (stamped into every page)
    footer.html                   site footer (stamped into every page)
    help-nav.html                 help sidebar / table of contents (stamped into help pages)
  fonts.lock.json                 source TTF hashes -> WOFF2 hashes (checked by site-check)

website/                          published as-is by Cloudflare Pages (build output dir)
  index.html privacy.html terms.html support.html help.html press.html
  acknowledgements.html 404.html
  changelog.html                  GENERATED from content/changelog.json
  changelog.json                  GENERATED (normalized, drafts removed); also the app's bundled copy
  help/{library,import,editor,setlists,live,shortcuts,keyboard}.html
  _redirects                      GENERATED from content/site.json
  _headers                        hand-written (section 9.3)
  robots.txt                      hand-written
  sitemap.xml                     GENERATED from the page list
  favicon.svg                     GENERATED copy of design/icon/icon-32.svg (hand-tuned small icon)
  favicon-32.png                  RASTER (gen-site --raster)
  apple-touch-icon.png            RASTER, 180x180, from design/icon/master.svg
  assets/
    css/tokens.css                GENERATED by scripts/gen-tokens.swift from design/tokens.json
    css/site.css                  hand-written; colours only via var(--token)
    css/screens.css               hand-written, home only: the interim app re-creations (9.2 swap points)
    fonts/schibsted-grotesk-{400,600,700,800}.woff2   derived, committed (section 8.4)
    fonts/OFL.txt                 copy of the font licence
    img/icon.svg                  GENERATED copy of design/icon/master.svg
    img/icon-1024.png             copy of design/icon/previews/icon-default-1024.png (Liquid Glass rendition)
    img/og.png                    RASTER, 1200x630
    img/wordmark-dark.png, wordmark-light.png   RASTER, for /press
    img/badge-mac-app-store-black.svg           Apple artwork, unmodified (section 7.1)
    img/screens/*.jpg             from the screenshot workstream (R10), section 8.5

scripts/
  gen-site.swift                  generator + checker (section 8)
  gen-webfonts.sh                 TTF -> subset WOFF2 via uvx fonttools (section 8.4)
  gen-tokens.swift                EXTENDED to also emit website/assets/css/tokens.css
.githooks/pre-push                runs make site-check STRICT=1 when website/ or content/ changed (B-29)
.htmlvalidate.json                html-validate config (repo root, so it is not published)
```

Add `.wrangler/` to `.gitignore` (local preview state written by `wrangler pages dev`).

The app side of the changelog contract is owned by WS2b: `Project.swift` adds `website/changelog.json` to both app targets' resources. WS4 writes no file into the app.

---

## 4. Single config point: `content/site.json`

Every vendor name, URL, location, transfer basis, retention period, legal name and App Store value lives here and nowhere else. Pages contain **slots** that `gen-site.swift` fills from this file. A value that is genuinely unknown until a [RYAN] step is written as an `{UPPER_SNAKE}` placeholder; it renders visibly in previews, and `--strict` refuses it (section 8.1).

```json
{
  "schema": 1,
  "site": {
    "origin": "https://segue.ryandsilva.dev",
    "name": "Segue",
    "tagline": "Your chart, your set, your cue."
  },
  "owner": {
    "legalName": "Ryan Rony Dsilva",
    "email": "segue@ryandsilva.dev",
    "country": "United States",
    "governingState": "Washington"
  },
  "legal": {
    "privacyEffectiveDate": "{POLICY_EFFECTIVE_DATE}",
    "termsEffectiveDate": "{TERMS_EFFECTIVE_DATE}",
    "copyrightYear": "2026"
  },
  "app": {
    "requirements": "a Mac with Apple silicon and macOS 26 or later"
  },
  "appStore": {
    "status": "upcoming",
    "appleId": "{APPLE_ID}",
    "providerToken": "{PROVIDER_TOKEN}",
    "mediaType": "{MT}",
    "campaigns": { "hero": "website-hero", "footer": "website-footer", "press": "press" }
  },
  "vendors": {
    "analytics": {
      "name": "TelemetryDeck",
      "url": "https://telemetrydeck.com",
      "privacyUrl": "https://telemetrydeck.com/privacy",
      "location": "Germany (EU), with some infrastructure in the United States",
      "transferBasis": "Standard Contractual Clauses for data reaching its U.S. infrastructure",
      "retention": "TelemetryDeck has no fixed deletion date for statistics; they may be kept in its archive for up to 10 years"
    },
    "crash": {
      "name": "Sentry",
      "url": "https://sentry.io",
      "privacyUrl": "https://sentry.io/privacy/",
      "location": "United States (Sentry's U.S. region)",
      "transferBasis": "Standard Contractual Clauses",
      "retention": "30 days"
    },
    "bugReports": {
      "name": "Sentry",
      "url": "https://sentry.io",
      "privacyUrl": "https://sentry.io/privacy/",
      "location": "United States (Sentry's U.S. region)",
      "transferBasis": "Standard Contractual Clauses",
      "retention": "30 days"
    },
    "board": {
      "name": "Featurebase",
      "boardUrl": "{BOARD_URL}",
      "privacyUrl": "https://help.featurebase.app/articles/4744036-privacy-policy",
      "termsUrl": "{BOARD_VENDOR_TERMS_URL}",
      "location": "European Union",
      "transferBasis": "Standard Contractual Clauses for any transfer outside the EU",
      "retention": "until you delete them or ask us to"
    },
    "hosting": {
      "name": "Cloudflare (Cloudflare Pages)",
      "privacyUrl": "https://www.cloudflare.com/privacypolicy/",
      "location": "United States and Cloudflare's global network",
      "transferBasis": "the EU-U.S. Data Privacy Framework and Standard Contractual Clauses"
    },
    "webAnalytics": {
      "name": "Cloudflare Web Analytics",
      "privacyUrl": "https://www.cloudflare.com/privacypolicy/",
      "location": "United States and Cloudflare's global network",
      "transferBasis": "the EU-U.S. Data Privacy Framework and Standard Contractual Clauses",
      "retention": "{WEB_ANALYTICS_RETENTION}"
    },
    "emailRouting": {
      "name": "Mailgun",
      "privacyUrl": "https://www.mailgun.com/legal/privacy-policy/",
      "location": "United States"
    },
    "inbox": {
      "name": "Google (Gmail)",
      "privacyUrl": "https://policies.google.com/privacy",
      "location": "United States",
      "retention": "as long as needed to answer you, and at most 2 years"
    }
  },
  "credits": [
    { "name": "Schibsted Grotesk", "summary": "Typeface used throughout Segue and this website.", "licence": "SIL Open Font License 1.1", "source": "https://github.com/schibsted/schibsted-grotesk", "licenceFile": "Packages/SegueUI/Sources/SegueUI/Theme/Fonts/OFL.txt" },
    { "name": "GRDB", "summary": "SQLite toolkit behind the song search index.", "licence": "MIT License", "source": "https://github.com/groue/GRDB.swift", "licenceFile": "Packages/SegueUI/Sources/SegueUI/App/Licenses/GRDB.txt" },
    { "name": "Tonic", "summary": "Music theory types for keys and chords.", "licence": "MIT License", "source": "https://github.com/AudioKit/Tonic", "licenceFile": "Packages/SegueUI/Sources/SegueUI/App/Licenses/Tonic.txt" },
    { "name": "Sentry Cocoa SDK", "summary": "Crash and hang reporting, used only if you allow crash reports.", "licence": "MIT License", "source": "https://github.com/getsentry/sentry-cocoa", "licenceFile": "{SENTRY_LICENCE_FILE}" }
  ]
}
```

Rules:

- **Filling the remaining placeholders.** `{BOARD_URL}`: from Ryan after WS3's Featurebase setup (e.g. `https://segue.featurebase.app`). `{BOARD_VENDOR_TERMS_URL}`: find Featurebase's terms page on featurebase.app; `--check-external` must reach it. `{WEB_ANALYTICS_RETENTION}`: read Cloudflare's Web Analytics docs and write how long its dashboard keeps data, in plain words. `{SENTRY_LICENCE_FILE}`: the path WS3 uses for Sentry's licence text next to the other app licences (`site-check` cross-checks credits against `AcknowledgementsView.swift`); add the credit only once WS3 has linked the SDK. TelemetryDeck gets no credit: no TelemetryDeck code ships in the app (R34). Effective dates: the day of the first push to production.
- `appStore.status` is `"upcoming"` or `"live"`. While upcoming, every App Store slot renders "Coming soon to the Mac App Store." as plain text (no badge, no link), and `appStore.*` placeholders are allowed by `--strict`.
- Campaign link, built by the generator: `https://apps.apple.com/app/apple-store/id{appleId}?pt={providerToken}&ct={campaign}&mt={mediaType}`. Copy `mt` from the link App Store Connect's campaign generator produces for this Mac app; do not hand-pick it (`05` shows the iOS value `8`; the Mac value differs).
- Sentry covers two roles (crash reports and bug reports), so its values are repeated in both objects; the policy's processor table is rendered per role and de-duplicated by `name` (one Sentry row, "crash reports and bug reports"). Cloudflare likewise appears once, "website hosting and website analytics".
- Any SDK that ships in the app must appear in `credits` and in the app's `AcknowledgementsView.swift`; `site-check` cross-checks names (section 8.1).

---

## 5. Visual design

### 5.1 Direction (R39, then R55)

R43 picked "Stage" from the first spread. R55 supersedes it with a mix of the second spread (mockups in the session scratchpad, ws4-classy): the **base layout and rounded tiles from C "Keynote"**, the **spotlight hero from B "House Lights"**, and the copy reframed from a week of the gig to a **musician's workflow** (bring songs in, make each chart yours, build the set, play the show). The design principles behind it:

1. One idea up top: the hero says one thing and shows one screen.
2. Real UI, large and frameless: product art is the app itself (A53), never a device bezel.
3. Big medium-weight headlines (600) with one heavy moment: only the hero H1 is 800.
4. Generous spacing, 5-7 sections: 160 px between sections on desktop, 96 px on phones, all on the 8 px grid.
5. One meaningful accent: coral only for the cue dot (wordmark, eyebrow) and inside the app art.
6. A calm close: the maker note, one line of call to action, the board.

Layout, top to bottom (copy in 9.2):

- **Hero, always dark in both schemes.** The header and hero share the `.scheme-stage` ground (section 5.2), so in light mode the page opens on a dark stage and turns to paper at the tiles. One soft spotlight cone falls from above the header onto the stage screenshot, with a faint pool of light under it (CSS gradients only). The beam fades in over 1.4 s, only under `prefers-reduced-motion: no-preference`.
- **Workflow tiles:** a 2 x 2 grid of rounded tiles (radius 28 px, 24 px on phones; `surface-alt` fill), one column under 860 px. Each tile: small label, 600-weight headline, one or two sentences, then one screen. The tiles share their rows through CSS subgrid, so copy and screens line up across a row. One crop rule for all four: the screen is a panel inset 40 px (24 px on phones) from the tile's sides, bleeding off the bottom only, and it shows one whole region of the window between two column boundaries, so no word is cut.
- **Stage band, always dark:** a full-bleed `.scheme-stage` band with a centred headline, one large screen and six features with line icons in three columns.
- **Details:** a 4 x 2 hairline grid (2 columns under 1000 px, 1 on phones).
- **Privacy:** centred headline and three short columns.
- **Close:** maker note, a large 600-weight headline, the App Store line, the board line, the latest-release card.

On phones, the hero and band screens become readable crops (the window at 200% / 190% width) instead of the whole window.

### 5.2 Theme

- **Dark-first:** `:root` holds the dark ("stage") values; `@media (prefers-color-scheme: light)` swaps to light ("paper") values. `color-scheme: dark light`. No theme toggle (it would need JavaScript).
- **Always-dark scope:** `tokens.css` also defines `.scheme-stage`, which pins the dark values (and `color-scheme: dark`) in both schemes, like the app's stage window. The home masthead, hero and stage band use it, and so does every stage-view re-creation.
- Tokens: every colour in the hand-written stylesheets (`site.css`, `screens.css`) is `var(--token)`, `color-mix()` of tokens, or `transparent`/`black` for shadows. No hex or `rgb()` literals (checked, section 8.1).
- `--control-border`: `var(--line)` in light, `color-mix(in srgb, var(--muted) 40%, transparent)` in dark (brand.md section 7, "Control border in dark").
- Links: `var(--ink)` text with a 1px underline at `var(--line-strong)`, hover/focus underline `var(--cue-text)`. Coral is never a button fill or a large area.
- Focus ring: `outline: 2px solid var(--cue); outline-offset: 2px` (3:1 or better on both grounds: 5.6:1 on stage, 3.4:1 on paper).
- Type (Schibsted Grotesk 400/600/700/800 only; fluid, 8 px rhythm):
  - hero H1 `clamp(48px, 7.2vw, 108px)/0.95` 800 `-0.055em` (the one heavy moment);
  - page H1 `clamp(40px, 6vw, 64px)/1.02` 600 `-0.045em` (document pages cap it at 56 px);
  - H2 `clamp(36px, 5vw, 64px)/1.04` 600 `-0.045em`; the closing H2 goes to 88 px;
  - tile headline `clamp(26px, 2.6vw, 34px)` 600 `-0.035em`;
  - H3 19/700 `-0.015em`; body 17/400, line-height 1.55; kicker and tile label 15-17/600 `muted`; small print 13.
- Layout: max content width 1120 px (1056 px of content), text measure 68ch, 16 px side gutter on phones, 32 px from 640 px; no horizontal scroll at 320 px.
- Radii: tiles 28 px; document-page panels (privacy summary, help topic cards) 20 px; tables and disclosures 16 px; screenshots 12 px (10 px in tiles).
- Motion: a 150 ms colour transition on links and the hero beam's fade-in, both inside `@media (prefers-reduced-motion: no-preference)`. Nothing moves with Reduce Motion on.

### 5.3 Wordmark and cue dot (HTML/CSS, no image)

```html
<a class="wordmark" href="/" aria-label="Segue home">Segue<span class="cue-dot" aria-hidden="true"></span></a>
```

800 weight, `-0.045em`, the dot is `0.22em` diameter `var(--cue)` circle, top-aligned with the brand offset (8/64 of the font size). Never recolour the word.

### 5.4 Mobile nav without JavaScript

Desktop: wordmark left; Features, Help, Changelog, Support right. Under 640 px: wordmark plus a `<details class="nav-menu"><summary>Menu</summary>...</details>` disclosure; the summary is a 44x44 px target.

---

## 6. Changelog: one format for the site and the app's What's New

### 6.1 Source and outputs

- **Canonical:** `content/changelog.json`, hand-edited. Never generated from git history, never `CHANGELOG.md`.
- `gen-site.swift` validates it and writes:
  1. `website/changelog.json` (drafts removed, normalized formatting). This is published, and it is **the file the app bundles**: WS2b's `Project.swift` lists `website/changelog.json` as a resource of both app targets. There is no second output and no app path in `site.json`.
  2. `website/changelog.html` (the `/changelog` page);
  3. the home page "What's new" strip (slot `latest-release`).
- **The app never fetches `/changelog.json`.** It reads only its bundled copy (A16). The public file exists for reference and for anyone who wants the notes as data.
- The What's New sheet shows a release only when its `showInApp` is `true` (the author decides per release). Help > What's New in Segue reopens the sheet regardless.
- App Store Connect "What's New" text is copied by hand from the same entry (`highlights` joined as lines starting "- ").

### 6.2 Schema 1

```json
{
  "schema": 1,
  "releases": [
    {
      "version": "0.5",
      "date": "2026-11-20",
      "title": "First beta",
      "summary": "Segue's first public release on the Mac App Store.",
      "showInApp": false,
      "draft": true,
      "highlights": [
        { "kind": "new", "text": "Stage mode that fits every song on one screen, never below your minimum size.", "help": "/help/live#minimum-size" },
        { "kind": "new", "text": "Setlists with drag and drop, per-show key and capo, and running time.", "help": "/help/setlists" },
        { "kind": "new", "text": "Import ChordPro and text files by dragging them onto the library.", "help": "/help/import" }
      ]
    }
  ]
}
```

| Field | Type | Rule |
|---|---|---|
| `schema` | int | `1`. An app that finds a `schema` greater than it knows shows no sheet and logs once. |
| `releases` | array | Newest first. Versions unique. Order is enforced, not fixed up. |
| `version` | string | `^\d+\.\d+(\.\d+)?$`, written exactly as `MARKETING_VERSION` (`0.5`, not `0.5.0`). Compared numerically by component; `0.5` == `0.5.0`. |
| `date` | string | `YYYY-MM-DD`, the release date. Non-increasing down the list. |
| `title` | string | 1-60 chars, plain text. |
| `summary` | string, optional | 1-200 chars, plain text. |
| `showInApp` | bool | Required. Whether the app's What's New sheet shows this release. `false` for 0.5 (a fresh install never sees What's New) and for bug-fix-only releases. |
| `draft` | bool, optional | `true` = kept in `content/` only; excluded from every output. Lets notes be written ahead of a release. |
| `highlights` | array | 1-8 items. |
| `highlights[].kind` | enum | `new`, `improved`, `fixed`. Rendered as "New", "Improved", "Fixed" labels (text, not colour alone), on the site and in the app. |
| `highlights[].text` | string | 1-120 chars (the app's sheet wraps to two lines), plain text: no `<`, `>`, backticks, Markdown markers, or em dashes. One sentence. |
| `highlights[].help` | string, optional | Site-relative path starting `/help`, `/support` or `/privacy`; must be a page or anchor that exists (the link checker validates it). The app turns it into `SegueLinks.site + help` and shows "Learn More". |

No other fields exist (no `minimumOS`, no absolute `learnMore` URLs). Unknown keys: the generator rejects them in the source (typo guard). The **app must ignore** unknown keys within schema 1, so the format can grow additively. Breaking changes bump `schema`. The same limits are enforced twice: by `gen-site --check` and by WS2b's `WhatsNewTests`, which decode the real `website/changelog.json`.

### 6.3 `/changelog` page

Generated from the template inside `gen-site.swift`, using the shared header/footer partials. Per release: `<section id="v0.5">` with `<h2>` "Version 0.5" + title, a `<time datetime>`, the summary, then a list grouped New / Improved / Fixed, each with an optional "Learn more" link. Intro: "What changed in each version of Segue. Segue shows the bigger updates in the app too, under Help > What's New in Segue."

---

## 7. Apple marketing rules (apply everywhere)

### 7.1 Mac App Store badge

- Artwork: the black **"Download on the Mac App Store"** badge (US English), downloaded from Apple's marketing tools (https://toolbox.marketingtools.apple.com/ ; guidelines https://developer.apple.com/app-store/marketing/guidelines/). Committed unmodified as `website/assets/img/badge-mac-app-store-black.svg`. If the implementing agent cannot download it, that becomes a [RYAN] step (R-8); do not recreate it.
- The grey border is part of the artwork; it is what makes the black badge read on the dark ground. Use the black badge in both themes.
- Height 48 px onscreen (minimum is 40 px). Clear space at least one quarter of the height (12 px) on every side; nothing inside it.
- Never modify, recolour, angle, animate, or put it in a hover effect. No localised or home-made variants.
- **Exactly one badge on the whole site: the home hero** (A52). Subordinate to the headline: below the subhead, never the largest element. The home final call to action and `/press` use text links; the footer uses a text link.
- Links: the campaign link (section 4) with `ct=website-hero` for the badge, `ct=website-footer` for the home final CTA and the footer, `ct=press` on `/press`.
- `<a href="..."><img src="/assets/img/badge-mac-app-store-black.svg" alt="Download on the Mac App Store" width="..." height="48"></a>`.

### 7.2 Wording, trademarks, product imagery

- "Download on the Mac App Store", "available on the Mac App Store". Never "at the App Store" or "downloadable".
- Say "Mac", "MacBook". Keep "macOS 26" to requirement lines in small print. No ™/® on the site (worldwide audience).
- Footer credit line (verify the exact mark list against https://www.apple.com/legal/intellectual-property/trademark/appletmlist.html at implementation time): "Apple, the Apple logo, Mac, MacBook, macOS and Shortcuts are trademarks of Apple Inc., registered in the U.S. and other countries and regions. App Store and Mac App Store are service marks of Apple Inc."
- Product imagery (A53): frameless window screenshots with the macOS window shadow, stills only. No Apple device bezels, no video loops.

---

## 8. Build and check scripts

### 8.1 `scripts/gen-site.swift`

Same style as `gen-tokens.swift`: `#!/usr/bin/env swift`, Foundation (plus AppKit/ImageIO only in `--raster`), deterministic output, repo-root-relative paths, typed errors, no dependencies.

**Slot syntax** (HTML comments, so hand-written pages stay valid HTML and preview correctly before generation):

```html
<!--slot:owner.email-->segue@ryandsilva.dev<!--/slot-->
<!--slot:vendors.analytics.name-->TelemetryDeck<!--/slot-->
<!--slot:partial:header--> ...stamped header... <!--/slot-->
```

- `slot:<config.path>`: replaced by the HTML-escaped value.
- `slot:<config.path>.link` for vendor objects: `<a href="{privacyUrl}">{name}</a>` (privacy link) and `.siteLink` (`url`).
- Computed slots: `partial:header`, `partial:footer`, `partial:help-nav` (from `content/partials/`), `appstore:hero` (badge), `appstore:footer` and `appstore:press` (text links), each rendering "Coming soon to the Mac App Store." while upcoming; `latest-release` (home strip), `vendor-table` (privacy processors table), `retention-table`, `credits` (acknowledgements, with the full licence texts read from each `licenceFile` inside `<details>`), `year`, `meta:og` (Open Graph/Twitter tags for that page from its `<title>` and `<meta name="description">`).
- The header partial gets `aria-current="page"` on the link whose `href` equals the page's own URL path; the generator adds it.
- Unknown slot names, unbalanced markers, or nested slots are errors.

**Modes**

| Command | Does |
|---|---|
| `scripts/gen-site.swift` | Validate `content/*.json`; fill all slots in `website/**/*.html` in place; write `changelog.json`, `changelog.html`, `_redirects`, `sitemap.xml`, `favicon.svg`, `assets/img/icon.svg`, `assets/img/icon-1024.png` (copy). |
| `--check` | Render everything in memory and byte-compare; also run the content checks below. Exit 1 listing each stale file or failed check. |
| `--check --strict` | Also fail on any `{UPPER_SNAKE}` placeholder in config or in any published file (except `appStore.*` while upcoming), any `ryan-edit` marker (9.2 maker note), missing raster outputs, and (when `appStore.status` is `live`) a missing badge or screenshots or an empty changelog. |
| `--raster` | Render `og.png` (1200x630), `apple-touch-icon.png` (180), `favicon-32.png`, `wordmark-dark.png`/`wordmark-light.png` (@2x) with AppKit/CoreText using the bundled TTFs, and the screenshot JPEGs (8.5). Not byte-checked (PNG/JPEG encoding is not stable across OS versions); `--check` verifies only presence and pixel dimensions via ImageIO. |
| `--check-external` | GET every external `https://` link found in published pages, report non-2xx/3xx. Network-dependent, so **not** part of `site-check`; run in the test plan. |

**Content checks run by `--check`:**

1. Internal link checker that models Pages routing: for each `href`/`src` starting with `/` (or relative), resolve `/x` to `x.html`, `x/index.html` or a static file; resolve `#fragment` against the target page's `id`s; `_redirects` sources count as valid. Every anchor in the section 2 contract list must exist, and every `highlights[].help` in `content/changelog.json` must resolve.
2. Every page: exactly one `<h1>`, `<html lang="en">`, a `<title>` (pattern "Page - Segue", home "Segue - Setlists & Chords for Mac"), a `<meta name="description">` of 50-160 chars, `<link rel="canonical">` equal to origin + path, the header/footer slots present.
3. No `<script>` element other than `type="application/ld+json"`; no `on*=` attributes; no `style=` attributes; no external `src`/`href` for scripts, styles, fonts or images (anchors to other sites are fine). Cloudflare's Web Analytics beacon is injected at the edge in production and must never appear in source.
4. No em dash (U+2014) in any file under `website/` or `content/`.
5. No hand-written stylesheet (everything in `assets/css/` except the generated `tokens.css`) contains a hex/rgb colour literal or loads a `url()` from another origin.
6. Every `<img>` has `alt`, `width`, `height`; below-the-fold images have `loading="lazy"`.
7. `content/fonts.lock.json` matches the SHA-256 of the source TTFs and the committed WOFF2 files.
8. Each `credits[].name` appears in `Packages/SegueUI/Sources/SegueUI/App/AcknowledgementsView.swift` (drift guard between site and app).
9. `_headers` exists and contains exactly the CSP line from section 9.3.
10. `content/changelog.json` follows schema 1 (6.2), including the 120-character highlight limit and the required `showInApp`.
11. The word "anonymous" appears nowhere on the site (analytics carry a hashed install identifier, so the word would overstate it).

**`_redirects` output:**

```
/feedback {boardUrl} 302
/favicon.ico /favicon-32.png 301
```

While `boardUrl` is a placeholder, the generator writes `/feedback /support#request-a-feature 302` instead, so the link never dead-ends in a preview.

### 8.2 `scripts/gen-tokens.swift` extension

Add one output, `website/assets/css/tokens.css`, to the existing `render()` list so `make tokens` writes it and `make tokens-check` guards it. Token names become kebab-case custom properties (`cueText` -> `--cue-text`). Shape:

```css
/* Generated by scripts/gen-tokens.swift from design/tokens.json - do not edit by hand. */
:root {
  color-scheme: dark light;
  --cue: #F2555A;
  --cue-text: #FF6B6F;
  --ink: #ECECEE;
  --ground: #101113;
  /* ...every token, dark values... */
  --control-border: color-mix(in srgb, var(--muted) 40%, transparent);
}
@media (prefers-color-scheme: light) {
  :root {
    --cue: #F2555A;
    --cue-text: #C42B30;
    /* ...every token, light values... */
    --control-border: var(--line);
  }
}
```

After the media query, the same dark values are emitted once more under `.scheme-stage { color-scheme: dark; ... }`, the always-dark scope (5.2).

Keep the existing catalog-cleanup logic scoped to the catalog directory only. WS2b step 1 also edits `gen-tokens.swift` (high-contrast variants); WS4's CSS output lands first and WS2b rebases onto it.

### 8.3 Makefile targets and pre-push hook

Add to `.PHONY` and to the help comments. Pin exact versions at implementation time (latest stable) in `.mise.toml` (`node`, `pnpm`) and in the Makefile variables.

```make
HTMLVALIDATE := pnpm dlx html-validate@<pinned>
WRANGLER     := pnpm dlx wrangler@<pinned>

site: ## Regenerate the website: tokens.css, changelog, slots, redirects, sitemap
	scripts/gen-tokens.swift
	scripts/gen-site.swift

site-check: ## Fail if the website is stale or invalid (STRICT=1 also refuses placeholders)
	scripts/gen-tokens.swift --check
	scripts/gen-site.swift --check $(if $(STRICT),--strict)
	$(MISE) $(HTMLVALIDATE) --config .htmlvalidate.json 'website/**/*.html'

site-serve: ## Preview the site locally with Cloudflare's Pages emulator (redirects, headers, 404)
	WRANGLER_SEND_METRICS=false $(MISE) $(WRANGLER) pages dev website --port 8788

site-raster: ## Re-render OG image, touch icon, favicon PNG, wordmark PNGs and screenshot JPEGs
	scripts/gen-site.swift --raster

site-fonts: ## Rebuild the subset WOFF2 web fonts from the bundled TTFs
	scripts/gen-webfonts.sh
```

- Add `site-check` to `check` (non-strict). `quick` stays app-only.
- `WRANGLER_SEND_METRICS=false` stops wrangler's telemetry. Wrangler needs no Cloudflare login for `pages dev`.
- `.htmlvalidate.json`: extend `html-validate:recommended`; allow the slot comments; require `alt`, unique ids, valid heading levels.
- **Pre-push hook (B-29):** `.githooks/pre-push` (POSIX sh, executable) reads the pushed ref ranges from stdin, and if any commit in them touches `website/` or `content/`, runs `make site-check STRICT=1` and blocks the push on failure. `make bootstrap` runs `git config core.hooksPath .githooks`. A push to `main` publishes, so placeholders and the maker-note marker are caught before it.

### 8.4 Web fonts (`scripts/gen-webfonts.sh`)

- Source: `Packages/SegueUI/Sources/SegueUI/Theme/Fonts/SchibstedGrotesk-{Regular,SemiBold,Bold,ExtraBold}.ttf` -> `schibsted-grotesk-{400,600,700,800}.woff2`.
- Command per weight (pin the fonttools version; `[woff]` brings brotli):
  `uvx --from 'fonttools[woff]==<pinned>' pyftsubset IN.ttf --output-file=OUT.woff2 --flavor=woff2 --layout-features='*' --no-hinting --desubroutinize --unicodes='U+0000-00FF,U+0131,U+0152-0153,U+02C6,U+02DA,U+02DC,U+2013-2014,U+2018-201E,U+2020-2022,U+2026,U+2030,U+2039-203A,U+20AC,U+2122,U+2190-2193,U+2212'`
- Writes `content/fonts.lock.json` (source and output SHA-256, fonttools version). Copy `OFL.txt` alongside. The OFL has no Reserved Font Name, so subsetting needs no rename.
- `@font-face` with `font-display: swap`; `<link rel="preload" as="font" type="font/woff2" crossorigin>` for 800 and 400 only. Budget: under 30 KB per weight.

### 8.5 Images

- Hero and section screenshots come from the R10 screenshot workstream (App Store flavor, Welcome library and screenshot-only original songs per A48; never real songs). Take the raw 2880x1800 captures, export JPEG (quality 0.85, sRGB) at 1280 and 2560 px wide with ImageIO (part of `--raster`, reading from a path set in that workstream's output). Until it exists the sections render without art, and `--strict` with `status: live` fails.
- `<img srcset="... 1280w, ... 2560w" sizes="(max-width: 1080px) 100vw, 1080px">`, explicit width/height, hero `fetchpriority="high"`, others lazy.
- Never show personal-only features (audio, LRCLIB, URL import) or real song lyrics in any image.

---

## 9. Page content

All copy below is final, with three exceptions: the maker note (Ryan rewrites it), help body text (written from the 0.5 build), and claims marked [VERIFY] (checked in the claims audit, section 12). `{PLACEHOLDER}` and `{vendors.x.y}` mean a slot filled from `content/site.json`.

### 9.1 Shared header and footer

**Header:** wordmark (link `/`); nav: Features (`/#features`), Help (`/help`), Changelog (`/changelog`), Support (`/support`). Skip link first in `<body>`: "Skip to content" -> `#main`.

**Footer** (three short columns, then the small print):

- Segue: Home, Help, Changelog, Download (the `appstore:footer` slot; "Coming soon" text while upcoming).
- Support: Support, Request a feature (`/feedback`), Press kit (`/press`), `segue@ryandsilva.dev`.
- Legal: Privacy, Terms, Acknowledgements.
- Small print: "© 2026 Ryan Rony Dsilva. Made in the U.S. for musicians everywhere." (year and name from slots) then the Apple credit line (section 7.2).

### 9.2 Home (`/`) - full copy

Design: R55 (section 5.1). Six sections, in this order; headlines are 2-6 words, tile and feature copy one or two short sentences. Every product claim must match what 0.5 ships (R14-R22, R45, R52); the claims still waiting on features being built are listed in an HTML comment at the top of `index.html` and in "Claims to verify" below.

`<title>`: Segue - Setlists & Chords for Mac
Meta description: "Segue keeps your songs as ChordPro files, builds tonight's set, and fits every song on one screen on stage. Free for Mac."

**1. Hero** (always dark, spotlit; the header sits on the same dark ground)

- Eyebrow: Segue for Mac (with the cue dot)
- H1: Your chart, your set, your cue. (the site's one 800-weight moment; breaks after "set," on wider screens)
- Subhead: Lyrics, chords and setlists for musicians who play live.
- CTA: `appstore:hero` slot (the site's only badge when live; "Coming soon to the Mac App Store." while upcoming).
- Small print: Free, with no ads and no in-app purchases. Requires a Mac with Apple silicon and macOS 26 or later.
- Art: screen `stage` (Soundcheck at Seven on stage). Caption: Built for a MacBook on a music stand.

**2. How it works** (`id="features"`; four rounded tiles, each with one screen)

- Kicker: How it works
- H2: From chord sheet to stage.

| Tile label | Headline | Body | Screen |
|---|---|---|---|
| Library | Bring your songs in. | Drag in ChordPro or text files, or start a new song. Each one stays a plain file in a folder you choose. | `library` |
| Editor | Make each chart yours. | Type ChordPro or place chords on the syllable. Transpose, add a capo, or switch to Nashville. | `editor` |
| Setlists | Build the set. | Drag songs into order and watch the running time add up. Change a key or capo for one show only. | `setlist` |
| Stage | Play the show. | Segue goes dark and full screen. Every song fits at a size you can read from a stool. | `stage-hindi` |

**3. Stage mode** (`id="stage-mode"`; always-dark band)

- Kicker: Stage mode
- H2: Built for the stage.
- Lede: One job: the right words at the right moment, and nothing in your way.
- Art: screen `stage-search` (quick search open over the song).
- Six features (icon, title, one sentence):
  1. **Never too small.** Set a minimum lyric size. If a song won't fit, Segue scrolls instead of shrinking it.
  2. **Know what's next.** The footer shows the next song with its key and capo, or the request you queued.
  3. **Take requests.** Press Cmd-K, type a title or a line you remember, and play it now, next or later.
  4. **One pedal, whole set.** Page Down scrolls, then moves on to the next song. A page-turner pedal just works.
  5. **Back where you were.** If your Mac restarts mid-show, Segue offers to pick up right where you left off.
  6. **A quiet Mac.** Run your own Shortcut as the show starts, for example to turn on a Focus.

**4. The details** (`id="details"`; hairline grid, 4 x 2)

- H2: The details, done properly.

1. **Your songs, as files.** One ChordPro file per song, in a folder you choose. No account, no lock-in.
2. **Search the way you spell.** Find any half-remembered line, romanized Hindi included.
3. **Guitar and piano.** Chord diagrams for both, with your own guitar shapes saved in the song.
4. **Learning, Ready, Pro.** Proficiency marks and tags show what's ready for the gig.
5. **Nothing to save.** Edits save as you go. Deleted songs go to the Trash.
6. **At home in Finder.** Open .cho files from Finder, preview them in Quick Look, and export your whole library.
7. **Rehearse first.** Run the set at home to time each song, without a gig log entry.
8. **Keyboard first.** Stage mode runs from the keyboard. Press ? to see every key.

**5. Privacy** (`id="privacy"`; centred, three columns)

- Kicker: Privacy
- H2: Your songs stay yours.
- **No account.** No sign-in. Your songs, setlists and gig history are files on your Mac.
- **Never uploaded.** Segue never uploads your songs. A bug report goes out only when you press Send.
- **Your choice.** Usage statistics and crash reports are two separate questions, with nothing picked for you.
- Link: Read the privacy policy

**6. The close** (`id="download"`)

- Maker note (A56; Ryan rewrites it). It stays wrapped in `<!--ryan-edit--> ... <!--/ryan-edit-->`, which `--strict` refuses:
  > I built Segue for my own gigs: a MacBook on a stand, and a set list that changes the moment someone shouts a request. If it helps you play, I'd love to hear about it.
  > Ryan
- H2: Ready when you are.
- `appstore:footer` slot: text link "Download Segue on the Mac App Store" (or "Coming soon to the Mac App Store." while upcoming). No badge (A52).
- Small print: Free. Requires a Mac with Apple silicon and macOS 26 or later.
- Board line: Shaped by the people who play it. Visit the feature board (`/feedback`)
- `latest-release` slot: "New in {version}: {title}" + up to 3 highlights + "See all changes" (`/changelog`). Hidden while the changelog has no published release.

**Claims to verify** (features still being built for 0.5; the step 8 claims audit confirms each in the App Store build or cuts the sentence that makes it, and then deletes it from the list in `index.html`):

| Claim | Where | Ruling |
|---|---|---|
| Import by dragging ChordPro or text files in | tile "Bring your songs in." | R15 |
| Autosave ("Edits save as you go") | details "Nothing to save." | R17 |
| Deletes go to the Trash | details "Nothing to save." | R15 |
| Open .cho files from Finder, Quick Look preview | details "At home in Finder." | R16 |
| Library archive export | details "At home in Finder." | R16 |
| The `?` keyboard overlay | details "Keyboard first." | R15 |
| Page Down pages into the next song (one pedal for the set) | stage "One pedal, whole set." | R45 |

Also check while auditing: the shapes saved in the song (`{define}`), the piano diagrams, and the resume offer after a quit.

**Screen swap points** (interim art until WS5). Each screen is an HTML re-creation of the real app (Welcome library songs only, labels, layout and tokens taken from `Packages/SegueUI`), styled by `website/assets/css/screens.css`. In `index.html` each sits on the single line after a `<!--screen:NAME-->` comment, inside its `.shot` frame. The swap replaces that one line with the screenshot, keeping the class `ui` so the frame's crop still applies:

```html
<img class="ui" src="/assets/img/screens/NAME-1280.jpg" srcset="/assets/img/screens/NAME-1280.jpg 1280w, /assets/img/screens/NAME-2560.jpg 2560w" sizes="(max-width: 1184px) 100vw, 1184px" width="1280" height="800" alt="(the re-creation's aria-label)" loading="lazy">
```

| NAME | Frame | Shows | Crop |
|---|---|---|---|
| `stage` | hero (`.shot-hero`) | Stage view, Soundcheck at Seven, song 1 of the Welcome Set, Kitaabon Wali Gali up next | whole window; phones: left 50% |
| `library` | tile 1 (`.crop-library`) | Main window: sidebar, song list, Soundcheck at Seven selected | x 0-640 pt (sidebar and list) |
| `editor` | tile 2 (`.crop-editor`) | Editor (Text mode) on Kettle On, Lights Low, autosaved | x 640-1440 pt (the editor pane) |
| `setlist` | tile 3 (`.crop-setlist`) | Setlist builder, Welcome Set (Kitaabon down a tone, notes on 3 and 4) | x 659-1440 pt (the set column) |
| `stage-hindi` | tile 4 (`.crop-stage`) | Stage view, Kitaabon Wali Gali transposed to Gm | x 0-720 pt (the first lyric column) |
| `stage-search` | stage band (`.shot-band`) | Stage view with quick search open ("lights"), under a 70% `ground` scrim | whole window; phones: centred on the panel |

The scrim under quick search is art direction, not app UI (the app draws quick search with no scrim; it borrows the 70% `ground` scrim the app uses for "End the show?"). A real capture has no scrim, so WS5 either dims the lyrics in post (same 70% ground) or ships the capture as is; Ryan picks when the screenshot lands.

**Weight:** until every screen is swapped, the home page is over the 40 KB HTML+CSS budget (about 50 KB of interim re-creations in `index.html` plus `screens.css`). Accepted by the coordinator for the interim; the swap brings it back under.

Rules for the swap: set `sizes` to the frame's rendered width (tiles show the window at 176% of a ~520 px tile, so they want the 2560 file on desktop); the hero image keeps `fetchpriority="high"` instead of `loading="lazy"`; the captures are 2880 x 1800 (16:10) and the frames assume 1440 x 900 pt windows, so crops line up; when the last screen is swapped, delete `screens.css` and its `<link>`, and the claims comment's art note.

**JSON-LD** (`<script type="application/ld+json">`, data only, never executed): `SoftwareApplication`, name "Segue", `applicationCategory` "MusicApplication", `operatingSystem` "macOS 26 or later", `processorRequirements` "Apple silicon (arm64)", `offers` price 0 USD, `url` origin, `downloadUrl` the campaign link only when live.

### 9.3 `_headers`

```
/*
  Content-Security-Policy: default-src 'none'; script-src https://static.cloudflareinsights.com; connect-src 'self'; img-src 'self'; style-src 'self'; font-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'; upgrade-insecure-requests
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=(), usb=()
  Cross-Origin-Opener-Policy: same-origin
  X-Frame-Options: DENY
```

**Web Analytics impact (R38).** Enabling Web Analytics on the Pages project (R-3 step 9) makes Cloudflare inject `<script defer src="https://static.cloudflareinsights.com/beacon.min.js" data-cf-beacon="...">` into every HTML response at the edge, from the next deployment on. The beacon loads from `static.cloudflareinsights.com` and, with automatic injection, reports to the site's own origin (`/cdn-cgi/rum`), so the CSP allows that script origin plus `connect-src 'self'` and nothing else (Cloudflare's Web Analytics FAQ, re-checked 2026-10-17: "For automatic injection, this will be the same domain, so ensure your `connect-src` includes `'self'`"); it needs no `'unsafe-inline'`. Our own pages stay script-free (check 3). Locally (`make site-serve`) nothing is injected, so local tests still see zero third-party requests; production tests expect exactly the beacon (section 11). Re-read Cloudflare's Web Analytics CSP guidance at implementation time; if the documented origins differ, use those and update this line.

No other custom caching: Cloudflare's own guidance is to keep its default `max-age=0, must-revalidate` + ETag on custom domains, so a deploy is never served stale. `/changelog.json` needs no special headers (the app never fetches it).

### 9.4 Privacy Policy (`/privacy`) - full text

`<title>`: Privacy Policy - Segue
Meta description: "What Segue, its website and its feedback board collect, why, who processes it, how long it is kept, and how to turn it off or delete it."

**Before filling the vendor values**, re-read each vendor's current privacy page and data-processing terms (TelemetryDeck, Sentry, Featurebase, Cloudflare including Web Analytics) for location, transfer basis, IP handling and retention, and check that the "What is sent" lists match WS3 section 5 (events), WS3 10.2 (App Privacy label) and WS3's ingest client exactly (I-9). Any difference: stop and ask Ryan.

Policy text (rendered with slot values; the published page shows the filled values, never the slot names):

---

# Privacy Policy

Effective {POLICY_EFFECTIVE_DATE}

## The short version

- Your songs, setlists and gig history are files on your Mac. Segue never uploads them, and we never see them.
- Segue has no accounts, no ads and no tracking. We don't sell or share your personal information.
- Segue sends usage statistics and crash reports only if you say yes to each one, and you can change your mind at any time in Settings > Privacy.
- A bug report is sent only when you press Send, after you've seen everything in it.
- This website sets no cookies. It counts visits with Cloudflare Web Analytics, which doesn't use cookies or track you across sites.

## Who we are

Segue is made by Ryan Rony Dsilva, an independent developer in the United States ("we", "us"). We decide how the information described here is used, which makes us the "controller" under European data protection law. You can reach us about anything in this policy at segue@ryandsilva.dev.

This policy covers the Segue app for Mac from the Mac App Store, this website (segue.ryandsilva.dev), the Segue feature board, and email you send us.

## What stays on your Mac

Your library is a folder you choose. Your songs (ChordPro files), the details Segue keeps beside them (tags, proficiency, notes), your setlists and your gig log all live in that folder. Segue's search index, settings and preferences stay on your Mac too. We have no copy of any of it, and no way to get one.

Segue also keeps a short technical log of its last four launches on your Mac, such as when a library opened, how long a show ran and which errors happened. It records only codes, counts and timings, never song titles, lyrics, file names or anything you type. It leaves your Mac only inside a bug report you choose to send.

Removing Segue does not delete your library folder. Back it up like any other folder, for example with Time Machine.

## Usage statistics (optional) {#usage-statistics}

**Off until you say yes.** The first time you open Segue, it asks whether to share usage statistics, with two equal choices and nothing picked for you. Nothing is sent before you answer, and nothing is sent if you say no. You can change your answer at any time in Settings > Privacy; turning it off takes effect immediately and deletes anything waiting to be sent.

**What is sent:**

- which features are used, from a fixed list built into the app (for example "song created", "setlist created", "show started", "transpose used", or "a search matched a romanized Hindi spelling");
- rough sizes and durations, always as ranges (for example "50 to 99 songs" or "a 60 to 90 minute show");
- the Segue version and the macOS version;
- your Mac's region setting (for example "United States"), which tells us your country. Nothing is worked out from your internet address;
- a random identifier that Segue creates on your Mac, so we can count how many people use Segue over time. Segue scrambles (hashes) it before sending and {vendors.analytics.name} scrambles it again, so neither of us can turn it back into the original. It is not your name, email address, Apple Account or any hardware identifier, and we don't link it to them.

Segue sends these through its own small piece of code that can send only the items above. No analytics software from another company runs inside Segue.

**Never sent:** song titles, lyrics, chords, notes, file or folder names, setlist names, venue names, anything you type into search, your contacts, your precise location, your internet address (it isn't stored), or any advertising identifier.

**Why:** to learn which features matter, which ones confuse people, and which versions of macOS to support.

**Who processes it:** {vendors.analytics.name}, in {vendors.analytics.location}, on our behalf. Its privacy policy: {vendors.analytics.link}.

**How long:** {vendors.analytics.retention}. Because the identifier is scrambled twice, those statistics can't be traced back to you or your Mac.

## Crash reports (optional) {#crash-reports}

macOS can give Segue technical reports when it crashes, hangs, or uses too much memory or energy. Segue asks about these separately from usage statistics. If you allow it ("Send crash reports", at first launch or later in Settings > Privacy), Segue uploads these reports automatically. Turning it off stops sending immediately and deletes any reports waiting to be sent.

**What is sent:** the kind of problem, where in Segue's code it happened (a technical stack trace), the Segue and macOS versions, the type of Mac, its processor and memory, your language setting, technical measurements such as memory and processor use at the time, and a short trail of Segue's own recent steps (codes only, like the log above). Each report also carries a random **Diagnostics ID** that Segue creates on your Mac, so reports from the same Mac can be grouped and deleted on request. You can see your Diagnostics ID in Settings > Privacy. Crash reports don't contain your songs, file names, your Mac's name, or anything you typed, and Segue strips your user name out of any file path before sending.

**Who processes it:** {vendors.crash.name}, in {vendors.crash.location}. Its privacy policy: {vendors.crash.link}.

**How long:** {vendors.crash.retention}, then deleted.

**Apple's crash reports.** Separately, if you've turned on "Share with app developers" in System Settings > Privacy & Security > Analytics & Improvements, Apple shares crash reports and usage figures for Segue with us. Apple controls that sharing under Apple's own privacy policy, and the figures we see from Apple don't identify you.

## Bug reports you send {#bug-reports}

You can send us a bug report from Segue's Help menu (Help > Report a Problem...).

**What is sent, and only when you press Send:**

- what you write;
- system information, always included and shown to you before sending: the Segue version and build, the macOS version, the Mac model and processor type, your language setting, the approximate size of your library (for example "50 to 99 songs", never titles), and your current privacy choices;
- **only if ticked** (you can untick them): Segue's technical log of its last four launches, and the latest crash or hang diagnostics macOS gave Segue;
- **only if you tick it** (it's off every time you open the form): the song that's open, meaning its ChordPro file and Segue's details file. This includes its lyrics, so leave it off if you'd rather not share them;
- **only if you enter it:** your email address, so we can reply.

Before anything is sent, Segue shows you the complete report, including the full text of every attached file. What you see is exactly what is sent.

**Who processes it:** {vendors.bugReports.name}, in {vendors.bugReports.location}. Its privacy policy: {vendors.bugReports.link}. Because a report can include your email address, we treat each report as connected to you.

If Segue can't reach the service, it offers to put the same report into an email for you to send (covered by "Email" below) or to save it as a file on your Mac. Nothing is sent later without you.

**Why:** to find and fix problems, and to answer you.

**How long:** {vendors.bugReports.retention}, then deleted, including any song you attached. A song you attached is used only to reproduce the problem. You can ask us to delete a report sooner.

## The feature board

segue.ryandsilva.dev/feedback takes you to Segue's feature board, run by {vendors.board.name}. There you can suggest features, comment, and vote. The board is a separate website; the Segue app sends it nothing.

- **What you post is public.** Please don't include personal information about yourself or anyone else.
- **Email is optional.** If you give it, it's used only to tell you about ideas you posted or voted for, for example when one ships, and you can unsubscribe from any such email. We never use it for marketing and never share it.
- {vendors.board.name} also collects technical information (such as your internet address, browser details and the cookies the board needs to work) under its own privacy policy: {vendors.board.link}. It asks before setting any optional cookies.

**How long:** posts and votes stay {vendors.board.retention}; your email stays until you unsubscribe or ask us to remove it.

## Email

When you write to segue@ryandsilva.dev, your message passes through {vendors.emailRouting.name}, which forwards it, and is stored in an inbox run by {vendors.inbox.name}. We use your email only to help you, keep it {vendors.inbox.retention}, and delete it sooner if you ask.

## This website {#this-website}

segue.ryandsilva.dev is a set of static pages hosted by {vendors.hosting.name}. It sets no cookies, and its fonts and images all come from this site. Like any web host, Cloudflare processes your internet address and request details to deliver the pages and protect the site from abuse, under its privacy policy ({vendors.hosting.link}). We don't receive logs of individual visits.

**Website analytics.** We use {vendors.webAnalytics.name} to see how many people visit and which pages they read. When a page loads, a small script from Cloudflare reports the page's address, the page you came from, your browser and operating system type, your screen size, how quickly the page loaded, and your country, which Cloudflare works out from your internet address. It sets no cookies, stores nothing on your device, doesn't build a profile of you, and doesn't follow you across other websites. We see only totals, such as "120 visits to the privacy policy this week". Cloudflare keeps these reports for {vendors.webAnalytics.retention}.

Links to the Mac App Store carry a campaign tag (for example "website-hero"). Apple uses it to tell us, in aggregate, how many people found Segue through this website. It doesn't identify you.

## Apple

You download Segue from the Mac App Store, and Apple handles that, along with any ratings and reviews you leave, under Apple's own privacy policy (https://www.apple.com/legal/privacy/). We get only aggregate figures from Apple, such as the number of downloads.

## What we never do

- We don't sell your personal information, and we don't share it for advertising.
- We don't show ads, and we don't track you across other companies' apps or websites.
- We don't build profiles of you or use data brokers.
- We don't ask for an account.
- We don't collect sensitive information such as health, financial or precise location data.
- We don't use your songs to train AI. We never receive them, except a song you choose to attach to a bug report, which is used only to fix that bug.

## Legal bases (European Economic Area, UK and Switzerland)

- Usage statistics and crash reports: your **consent**, given separately for each. You can withdraw it at any time in Settings > Privacy; withdrawing doesn't affect what was sent before.
- Bug reports: your **consent** when you press Send, and our **legitimate interest** in fixing and improving Segue.
- Feature board posts and votes: our **legitimate interest** in learning what to build; board update emails: your **consent**.
- Email: our **legitimate interest** in answering you.
- Website hosting, security and website analytics: our **legitimate interest** in delivering a working, safe website and knowing, in aggregate, how it is used.

## Who receives data

`vendor-table` slot, rendered as a table with columns **Provider | What for | Where | Privacy policy**, one row per provider, from `content/site.json`: TelemetryDeck (usage statistics), Sentry (crash reports and bug reports), Featurebase (feature board), Cloudflare (website hosting and website analytics), Mailgun (email forwarding), Google (email inbox). Below the table: "Apple handles App Store downloads, ratings, reviews and its own crash sharing as an independent controller under its own privacy policy."

Each provider processes data for us under a contract (its data processing terms) that requires it to protect the data at least as well as this policy does and to use it only to provide its service to us. We may also disclose information if the law requires it, or to protect the safety of anyone.

## International transfers

We are in the United States, and our providers process data in the United States, the European Union and other countries. When data from the European Economic Area, the UK or Switzerland is transferred to a country without an adequacy decision, it is protected as follows: usage statistics ({vendors.analytics.name}): {vendors.analytics.transferBasis}; crash reports and bug reports ({vendors.crash.name}, processed in the United States): {vendors.crash.transferBasis}; the feature board ({vendors.board.name}): {vendors.board.transferBasis}; this website ({vendors.hosting.name}): {vendors.hosting.transferBasis}.

## How long we keep data

`retention-table` slot: one row per flow, values from `content/site.json`:

| What | How long |
|---|---|
| Usage statistics | {vendors.analytics.retention}; the identifier in them is scrambled twice and can't be traced back to you |
| Crash reports | {vendors.crash.retention} |
| Bug reports, including attached songs | {vendors.bugReports.retention} |
| Feature board posts and votes | {vendors.board.retention} |
| Feature board email | until you unsubscribe or ask us to remove it |
| Email to segue@ryandsilva.dev | {vendors.inbox.retention} |
| Website analytics (totals only) | {vendors.webAnalytics.retention} |
| Website request logs | Cloudflare's standard retention; we receive no per-visit logs |

## Your choices and rights {#your-choices}

**Turn things off.** Settings > Privacy in Segue has a separate switch for usage statistics and for crash reports. Turning either off takes effect immediately.

**Ask us.** Email segue@ryandsilva.dev to see, correct, export or delete what we hold about you, or to object to how we use it. To help us find it, tell us:

- for crash reports, your Diagnostics ID (shown in Settings > Privacy, with a Copy button);
- for bug reports, the email address you entered and roughly when you sent it;
- for the feature board, a link to your post.

We'll answer within one month, and we may ask you to confirm the request from the same email address.

**Usage statistics can't be looked up by person.** The identifier in them is scrambled twice and isn't linked to your name, email or Diagnostics ID, so neither we nor TelemetryDeck can find your statistics. Turning statistics off stops all collection.

**If you're in the European Economic Area, the UK or Switzerland**, you have the right to access, correct, delete, restrict and port your data, to object to processing based on legitimate interest, and to withdraw consent at any time. You can also complain to your data protection authority (https://www.edpb.europa.eu/about-edpb/about-edpb/members_en ; in the UK, the ICO at https://ico.org.uk). We'd appreciate the chance to fix things first.

**If you're in California or another U.S. state with a privacy law**, you can ask to know what we collect, and to correct or delete it, as described above, and we won't treat you differently for asking. We don't sell or share personal information, so there is nothing to opt out of; we treat Global Privacy Control signals as an opt-out anyway. We don't use sensitive personal information. An authorized agent can make a request for you with your written permission.

## Security

Everything Segue sends travels encrypted (HTTPS). Only we can access bug reports, crash reports, statistics and email, and our providers secure the systems they run. No system is perfectly secure, so we collect as little as we can in the first place.

## Children

Segue isn't directed at children under 13, and the feature board isn't for anyone under 16 in the European Economic Area or the UK. If you think a child has sent us personal information, email us and we'll delete it.

## Changes to this policy

When this policy changes, we update the effective date above and note the change in the changelog (/changelog). If a change affects what the app sends, Segue asks you again before sending anything new.

## Contact

Ryan Rony Dsilva
segue@ryandsilva.dev

---

### 9.5 Terms of Use (`/terms`) - full text

`<title>`: Terms of Use - Segue
Meta description: "The short terms for Segue's website, feature board and bug reports. The app itself is licensed under Apple's standard EULA."

---

# Terms of Use

Effective {TERMS_EFFECTIVE_DATE}

**In short:** the Segue app is covered by Apple's standard licence. These terms only add the rules for this website, the feature board, and the bug reports and feedback you send. Be kind on the board, don't post things you don't have the right to share, and know that votes are a guide, not a promise.

## 1. What these terms cover

These terms apply to segue.ryandsilva.dev, the Segue feature board, and any bug report, question or idea you send us. "We" and "us" means Ryan Rony Dsilva, who makes Segue. By using the website or the board, or by sending us a report, you agree to these terms.

**The app itself** is licensed to you under Apple's Licensed Application End User License Agreement (https://www.apple.com/legal/internet-services/itunes/dev/stdeula/). These terms don't change that licence. If they ever seem to conflict about the app, Apple's licence wins.

## 2. Segue is free, and provided as is

Segue is free. We work hard to make it reliable on stage, but it's provided "as is", without warranties beyond those the law requires. Features may change or be removed. Your songs are ordinary files on your Mac: keep a backup.

## 3. Using this website

You may use this website for any lawful, personal or professional purpose. Please don't try to break it, overload it, or get around its security. The text, design, screenshots, the Segue name and the Segue icon on this website belong to us unless noted otherwise; see Press (/press) for how you may use them when writing about Segue.

## 4. The feature board

The board is a shared space. When you post, comment or vote:

- be respectful, and don't post anything illegal, hateful, harassing, sexual, violent, misleading, or spam or advertising;
- don't post personal information about other people;
- don't post full lyrics or chord charts of songs you don't have the right to share. A line or two to describe a problem is fine;
- one person, one vote: don't use multiple accounts or automation to vote.

We may edit, merge, hide or remove posts and votes, and restrict anyone who doesn't follow these rules, at our discretion. The board runs on {vendors.board.name}, whose own terms also apply ({vendors.board.termsUrl}).

Votes and statuses such as "planned" help us decide what to build. They're not promises about what will ship or when.

## 5. Your ideas and feedback

You keep ownership of what you post or send. By posting an idea, a comment or a bug report, you give us a worldwide, non-exclusive, royalty-free, perpetual and irrevocable licence to use, copy, modify and build on it to improve Segue, without owing you payment or credit. You confirm you have the right to share what you send. We're under no obligation to use any idea.

## 6. Bug reports

Send only content you have the right to share. If you attach a song, we use it only to find and fix the problem you reported, and it is deleted with the report after 30 days. How we handle reports is described in the Privacy Policy (/privacy).

## 7. Privacy

The Privacy Policy (/privacy) explains what we collect and how you control it.

## 8. Trademarks

"Segue", the Segue wordmark and the taped-setlist icon are ours. You may use them to refer to or write about Segue, as described on the Press page; please don't use them in a way that suggests we endorse you or your product. Apple, Mac, MacBook, macOS and Shortcuts are trademarks of Apple Inc., registered in the U.S. and other countries and regions. App Store and Mac App Store are service marks of Apple Inc.

## 9. Other services and links

The board, crash and bug reporting, our email and this website's hosting are run by other companies, and we link to websites we don't control. We're not responsible for their content or practices.

## 10. Liability

To the extent the law allows, we're not liable for indirect, incidental or consequential losses, such as a lost gig, lost data or lost profits, arising from this website, the board or a bug report, and our total liability for them is limited to US$50. Nothing in these terms limits liability that can't be limited by law, or takes away rights you have as a consumer where you live.

## 11. Changes

We may update these terms. When we do, we'll change the effective date above, and for significant changes we'll also note it in the changelog. If you keep using the website or the board after a change, the new terms apply.

## 12. Governing law

These terms are governed by the laws of the State of Washington, United States, without regard to its conflict-of-laws rules, and disputes go to the state or federal courts located in Washington. If you're a consumer in the European Union or the UK, you also keep the protection of the mandatory laws of the country where you live, and you may bring a claim there.

## 13. Contact

segue@ryandsilva.dev

---

### 9.6 Support (`/support`) - full copy

`<title>`: Support - Segue
Meta description: "Get help with Segue: contact, bug reports, feature requests, system requirements and answers to common questions."

---

# Support

**We're here to help.** Email segue@ryandsilva.dev and you'll hear back from a real person, usually within a few days.

## Report a bug {#report-a-bug}

The fastest way is from inside Segue: choose **Help > Report a Problem...**. Segue attaches the details we need to find the problem, and shows you everything before you send it. Attaching the song you're looking at is optional and off by default.

If you can't open Segue, email segue@ryandsilva.dev with:

- your Segue version (Segue > About Segue) and your macOS version;
- what you did, what you expected, and what happened instead;
- a song file (.cho) if the problem is with one particular song, and you're happy to share it.

## Request a feature {#request-a-feature}

Suggest ideas and vote for the ones you want on the feature board: **segue.ryandsilva.dev/feedback**. You can also choose **Help > Request a Feature...** in Segue.

## System requirements

- A Mac with Apple silicon and macOS 26 or later.
- About {size} MB of disk space. [VERIFY from the 0.5 archive; write the number, not a slot]
- No internet connection needed to write songs, build sets or play a show.

## Frequently asked questions

**Where are my songs stored?**
In the library folder you chose the first time you opened Segue (we suggest Music > Segue). Each song is a ChordPro file (.cho) with a small file beside it that holds Segue's extras, like tags and proficiency. Your setlists and your gig log live in the same folder.

**How do I back up my library, or move it to another Mac?**
It's a normal folder, so Time Machine and any backup tool already cover it. To move it, copy the folder to the other Mac and choose it with Library > Choose Library Folder. You can also use **File > Export Library Archive...** to make a single file. [VERIFY menu names]

**What is ChordPro?**
A plain-text format for songs with chords, used by many apps: chords go in square brackets right before the syllable they belong to, like `[G]Take me [C]home`. See the ChordPro site at https://www.chordpro.org.

**Can I import songs I already have?**
Yes. Drag ChordPro or text files (.cho, .chordpro, .chopro, .pro or .txt) onto the library, or choose **File > Import Songs...**. See Importing songs (/help/import).

**Does Segue need the internet?**
No. Everything for writing and playing works offline, and the stage view never waits on the network. Segue goes online only for the things you turn on or ask for: usage statistics and crash reports if you said yes, sending a bug report, and opening web pages such as help or the feature board.

**What does Segue collect, and how do I turn it off?**
Nothing about your songs, ever. If you agreed to share usage statistics or send crash reports, you can turn each off in Settings > Privacy. Details are in the Privacy Policy (/privacy).

**How do I keep notifications quiet during a show?**
Create a Shortcut that turns on a Focus, then pick it in Settings > Live > Gig Mode Shortcuts. See Shortcuts (/help/shortcuts#gig-mode).

**Will my page-turner pedal work?**
Pedals that send arrow keys or Page Up / Page Down work out of the box. See Stage mode (/help/live). [VERIFY]

**Is there an iPhone or iPad version?**
Not yet. It's on the list; vote for it on the feature board.

**Is Segue really free?**
Yes. No ads, no subscription and no in-app purchases.

**A song shows the wrong chord or layout.**
Please send a bug report and tick "Current song file" so we can see the exact file.

Also see: Help (/help), Changelog (/changelog), Privacy Policy (/privacy).

---

### 9.7 Help (`/help` and `/help/*`) - outline

Each help page uses `partial:help-nav` (a left column on desktop, a top list on phones), one H1, short task-oriented sections with `id`s, and at most one screenshot per section. Write the body text from the **0.5 App Store build**, opening each feature as you document it; every step and menu name must match the build exactly. If the build is not feature-complete when you reach this step, write against the current `main` App Store flavor and re-check every page in the claims audit before `status: live`. Never document personal-only features (audio, LRCLIB, URL import), AI features, PDF export or MIDI, which are not in 0.5.

- **`/help` Segue Help**
  - Intro: what Segue is in two sentences; "New here? Start with the Welcome library."
  - Getting started: choose a library folder; the Welcome library (four original demo songs by "Segue Originals" and a "Welcome Set" setlist; delete them any time, or use Settings > Data > Remove Welcome Songs, which keeps any you've edited); the two privacy questions; first show in five steps.
  - `#trash` "Deleted something by mistake?": deletes go to the Trash and can be undone; links to `/help/library#trash`.
  - Cards linking the seven topics below.
  - "Still stuck?" -> /support.
- **`/help/library` Your library**
  - `#folder` Where songs live (the folder, `.cho` + Segue details file, setlists, gig log in `shows/`); changing the library folder.
  - `#search` Searching (titles, artists, lyrics; romanized Hindi spelling variants).
  - `#tags` Tags and proficiency (Learning, Ready, Pro; shown by fill, not colour alone).
  - `#trash` Deleting songs, setlists and gigs: Move to Trash, Edit > Undo, restore from the Trash; Segue asks first only when a song is used in a setlist.
  - `#finder` Finder integration: Show in Finder, Open With, Quick Look.
  - `#backup` Backing up and exporting a library archive.
  - `#rebuild` Rebuild Index (when search looks wrong; safe, files untouched).
- **`/help/import` Importing songs**
  - `#formats` Supported files: `.cho`, `.chordpro`, `.chopro`, `.pro`, `.txt`. Text files are imported as they are (not converted); a file without a title takes its name from the file name; an identical copy of a song already in the library is skipped.
  - `#drag` Drag and drop onto the library list or the song pane (folders included); `#menu` File > Import Songs... (Shift-Cmd-I).
  - `#copy` Imports are copied into the library; originals untouched; non-UTF-8 files are converted in the copy.
  - `#open-with` Open With Segue from Finder (copies the file into the library).
  - `#problems` Files that can't be read: what Segue reports and how to fix them.
- **`/help/editor` Editing songs**
  - `#modes` Text and Visual modes.
  - `#chordpro` ChordPro basics with a 6-line example (an original snippet, never real lyrics).
  - `#visual` Placing chords on syllables in the visual editor.
  - `#transpose` Transpose, capo (shapes vs concert pitch), Nashville numbers.
  - `#diagrams` Guitar and piano diagrams; custom shapes (`{define}`) saved in the song.
  - `#autosave` Autosave: every change is saved as you type ("Saved" in the editor); Cmd-S just confirms "All changes saved"; Done closes the editor; undo; what happens when the file changes on disk.
  - `#spelling` Why spell-check and autocorrect are off in lyrics.
- **`/help/setlists` Setlists**
  - `#new` New Setlist (Shift-Cmd-N); adding (including Setlist > Add Selected Song to Setlist), reordering, removing songs.
  - `#overrides` Per-show key and capo.
  - `#running-time` Running time, and songs with unknown length (shown as unknown and flagged in the total, never guessed).
  - `#undo` Undo in the builder.
  - `#start` Start Show (Cmd-Return) and Rehearse (Opt-Cmd-Return): the difference.
- **`/help/live` Stage mode**
  - `#start` Starting a show; the pre-show checklist (the Focus row appears only once Gig Mode Shortcuts are set up).
  - `#navigate` Moving through the set; pedals.
  - `#minimum-size` Auto-fit and the minimum lyric size (Settings > Live).
  - `#auto-scroll` Auto-scroll: start, pause, speed.
  - `#requests` Quick search (Cmd-K or /): play now (Return), play next (Opt-Return), add to requests (Cmd-Return), with an optional note; playing the next request (R).
  - `#skip` Skipping and reordering mid-show.
  - `#resume` If Segue quits mid-show: resume where you were.
  - `#end` Ending a show (Cmd-., confirmation); the gig log; saving or discarding the reordered set.
  - `#zoom` Zoom in and out (Cmd-+, Cmd--, Cmd-0).
- **`/help/shortcuts` Shortcuts**
  - `#gig-mode` Gig Mode Shortcuts: off until you set them up (R18); creating "Gig Mode On"/"Gig Mode Off" in the Shortcuts app with the Set Focus action; choosing them in Settings > Live; the Test button.
  - `#checklist` The Focus row ticks only when Segue knows the Shortcut actually ran, and you can always tick it yourself with Done. Describe the exact confirmation step from the build (WS1 step 6, per R35: either automatic, or a "Tell Segue" action added as the Shortcut's last step).
  - `#focus` Why the Shortcuts app may flash briefly and Segue returns to the front.
  - `#ideas` Other ideas (brightness, Do Not Disturb, closing apps), kept to actions available in Shortcuts on macOS 26.
- **`/help/keyboard` Keyboard shortcuts**
  - `#library` Main window and menus (New Song Cmd-N, New Setlist Shift-Cmd-N, Import Songs Shift-Cmd-I, Show in Finder Opt-Cmd-R, Move to Trash Cmd-Delete, Start Show Cmd-Return, Rehearse Opt-Cmd-Return, Segue Library window Cmd-0, Settings Cmd-comma, Keyboard Shortcuts overlay ?).
  - `#stage` Stage mode, from the binding table: Right/Space next; Left previous; Down/Page Down scroll down; Up/Page Up scroll up; A auto-scroll; [ and ] slower/faster; Cmd-K or / search; R play next request; X skip; S sidebar; Cmd-+ / Cmd-- / Cmd-0 zoom; Cmd-. end show; ? all keys (any stage key also closes it); Esc close overlay.
  - Render each table with `<kbd>`. **Every row must be verified in the 0.5 build** (menus and `LiveKeyInput`/binding table); delete any row that isn't there. Later improvement (not this session): generate the stage table from the app's binding table.

### 9.8 Press (`/press`)

- H1: Press kit
- **One line:** Segue is a free Mac app for performing musicians: lyrics, chords and setlists, with a stage view that fits every song on one screen.
- **One paragraph:** Segue keeps your songs as plain ChordPro files in a folder you choose, lets you edit charts as text or by placing chords on syllables, builds setlists with per-show key and capo, and runs the gig from a dark, full-screen stage view that never shrinks lyrics below your minimum size. It handles requests mid-set, picks up where you left off if anything goes wrong, and has no account, no ads and no subscription. Search understands romanized Hindi with casual spellings.
- **Fact sheet:** Developer Ryan Rony Dsilva; Platform Mac with Apple silicon (macOS 26 or later); Price Free, no in-app purchases; Category Music; First release {date of 0.5 from changelog}; Website segue.ryandsilva.dev; Contact segue@ryandsilva.dev; `appstore:press` slot (text link, or "Coming soon").
- **Assets** (each a direct download link with dimensions): app icon PNG 1024 (`icon-1024.png`) and SVG; wordmark PNG on dark and on light; 5 screenshots at 2880x1800 from the R10 set; brand colours (`cue #F2555A`, `ink #111113`, `stage #101113`, `paper #FFFFFF`).
- **Usage:** "You may use these assets to write about Segue. Please don't alter the icon or wordmark."

### 9.9 Acknowledgements (`/acknowledgements`)

- H1: Acknowledgements
- Intro: "Segue is built with these open-source projects and fonts. Thank you to their authors."
- `credits` slot: per credit, name, summary, licence, source link, full licence text in `<details>`.
- Website note: "This website uses Schibsted Grotesk, served from this site, and no other third-party code of its own. Cloudflare adds a small script to count visits; see the Privacy Policy (/privacy#this-website)."

### 9.10 404

- H1: This page went off the set list.
- Body: The link may be old, or the page may have moved.
- Links: Home, Help, Support.
- `<meta name="robots" content="noindex">`; excluded from the sitemap.

### 9.11 Changelog

Generated (section 6.3). This session drafts the 0.5 entry in `content/changelog.json` with `"draft": true` and `"showInApp": false`; it is finalised (date, highlights checked against the build, `draft` removed) at release time.

---

## 10. [RYAN] manual steps

Ordered. Each one is something only Ryan can do. The implementing agent lists the outstanding ones at the end of its session. The site goes live early, with `appStore.status: "upcoming"` (A55), as soon as R-1 to R-5 are done; R-6 flips it to live on release day.

### R-1. Go-ahead to push

The repository's recent work is committed locally only; `origin` is `https://github.com/RyanDsilva/segue` (private). Cloudflare can deploy only what is on GitHub. **A push needs Ryan's explicit go-ahead.** Before the first push that includes `website/`: the maker note is rewritten (9.2), `{BOARD_URL}` is filled (R-2), and `make site-check STRICT=1` passes. The pre-push hook enforces the last point.

### R-2. Values only Ryan has

- The Featurebase board URL (WS3 [RYAN] Featurebase step) for `vendors.board.boardUrl`.
- The maker note in his own words (9.2), with the `ryan-edit` markers removed.
- Confirm the effective dates (default: the day of the first push).
Then `make site && make site-check STRICT=1`.

### R-3. Create the Cloudflare Pages project (Git integration)

1. Sign in at https://dash.cloudflare.com (create a free account if needed).
2. Left sidebar: **Workers & Pages** > **Create application** (button, top right). Choose the **Pages** tab (if the page defaults to Workers, use the "Looking to deploy Pages? Get started" link) > **Import an existing Git repository** > **Get started**.
3. **Connect GitHub**. In the GitHub app install screen choose **Only select repositories** > `RyanDsilva/segue` > **Install & Authorize**.
4. Back in Cloudflare select `segue` > **Begin setup**.
5. **Set up builds and deployments:**
   - Project name: `segue` (gives `segue.pages.dev`; if taken, note the name Cloudflare assigns).
   - Production branch: `main`.
   - Framework preset: **None**.
   - Build command: leave **empty**.
   - Build output directory: `website`.
   - Root directory (advanced): leave empty (repo root).
   - Environment variables: none.
6. **Save and Deploy**. The first deploy publishes `website/` at `https://segue.pages.dev`.
7. **Deploy only when `website/` changes:** project > **Settings** > **Build** > **Build watch paths** > Edit: Include paths `website/*`, Exclude paths empty > Save. (Cloudflare still builds on an empty push, or on a push with 20+ commits or 3000+ changed files.)
8. **Turn off preview deployments (B-27):** **Settings** > **Build** > **Branch control** > Preview branch: **None** > Save. Only `main` deploys.
9. **Enable Web Analytics (R38):** project > **Metrics** > **Web Analytics** > **Enable**. Cloudflare injects the beacon from the **next** deployment, so trigger one: **Deployments** > the latest production deployment > **...** > **Retry deployment**. If the label differs, Web Analytics for a Pages project lives under the project's Metrics tab; the account-level Web Analytics page also lists it.

### R-4. Custom domain (`segue.ryandsilva.dev`)

Order matters: add the domain in Cloudflare **first**, then the CNAME; a CNAME added first produces a 522 error.

1. Cloudflare: **Workers & Pages** > `segue` > **Custom domains** > **Set up a custom domain** > enter `segue.ryandsilva.dev` > **Continue**. Cloudflare shows the CNAME target (`segue.pages.dev`, or the project's actual subdomain).
2. Squarespace: https://account.squarespace.com/domains > `ryandsilva.dev` > **DNS** (DNS Settings) > **Custom records** > **Add record**:
   - Type: **CNAME**; Host: `segue`; Data / Points to: `segue.pages.dev`; TTL: default > **Save**.
   Do not touch the existing apex A record (Netlify) or the Mailgun MX/TXT records.
3. Back in Cloudflare wait until the domain shows **Active** with a certificate (usually minutes). `ryandsilva.dev` has no CAA records today (checked 2026-10-17), so certificate issuance is not blocked.
4. Check: `curl -sI https://segue.ryandsilva.dev/privacy` returns 200, and `/feedback` returns 302.

### R-5. Mailgun route and DMARC for `segue@ryandsilva.dev`

1. Send a test email to segue@ryandsilva.dev from another account. If it arrives (the existing route may be a catch-all), go to step 4.
2. Otherwise: https://app.mailgun.com > **Send** > **Receiving** (Routes) > edit the existing route (the free plan allows one) > Expression type **Custom** > `match_recipient("^(contact|segue)@ryandsilva\.dev$")` > Forward to: your Gmail address > Priority unchanged > **Save**. (Mailgun's UI labels change; if the path differs, the route is under the receiving/routes section.)
3. Re-send the test and confirm delivery (check spam).
4. **DMARC (B-28):** Squarespace DNS > **Custom records** > **Add record**: Type **TXT**, Host `_dmarc`, Data `v=DMARC1; p=none` (no report address) > **Save**. Skip if a `_dmarc` record already exists.

### R-6. App Store link values and go-live flip (A51)

1. After the app record exists: App Store Connect > Apps > Segue - Setlists & Chords > **App Information**: copy the numeric **Apple ID** into `appStore.appleId`.
2. App Store Connect > **Analytics** > Acquisition > **Campaigns** > **Generate Campaign Link**: create `website-hero`, `website-footer`, `press`; copy the `pt` and `mt` values from the generated link into `providerToken` and `mediaType`.
3. On release day, when you press the manual release in App Store Connect: set `appStore.status` to `"live"`, run `make site && make site-check STRICT=1`, commit, and push (with go-ahead). The badge appears in the home hero.

### R-7. App Store Connect URLs

In the app's version page: Privacy Policy URL `https://segue.ryandsilva.dev/privacy`, Support URL `https://segue.ryandsilva.dev/support`, Marketing URL `https://segue.ryandsilva.dev`. These must be live before submission.

### R-8. Badge artwork (only if the agent could not download it)

Download the black "Download on the Mac App Store" badge (US English, SVG) from https://toolbox.marketingtools.apple.com/ and save it unmodified as `website/assets/img/badge-mac-app-store-black.svg`.

### R-9. Read the legal text

The privacy policy and terms in this spec are plain-language drafts written from the decided data flows, not legal advice. Read them once more with the vendor values filled in; consider a lawyer's review before a wider launch.

### R-10. Ask TelemetryDeck about retention (R32)

Email TelemetryDeck support (from the account used for the Segue app) asking whether raw signals for a free-tier app can be deleted sooner than its archive default, or deleted on request. If they offer a shorter period, tell the WS4 session: only `vendors.analytics.retention` changes, then `make site`.

---

## 11. Test plan

Run in this order. Before each run, reset to a clean baseline: `make site` from committed inputs, delete `.wrangler/`, restart `make site-serve`, and use a fresh browser profile or a private window (no cached pages or fonts).

1. **Generators and static checks:** `make site-check` (non-strict) passes. Then `make site-check STRICT=1` and confirm it fails **only** on the expected items (`{BOARD_URL}`, the maker-note markers, effective dates, `{WEB_ANALYTICS_RETENTION}` or `{SENTRY_LICENCE_FILE}` if not yet filled), and passes once they are resolved.
2. **Determinism:** run `make site` twice; `git status` shows no changes from the second run.
3. **Negative checks:** in a scratch copy (not the repo) break a link, add an em dash, add a `<script src>`, add a hex colour to `site.css`, reorder two changelog releases, add an unknown key to `changelog.json`, make a highlight 121 characters long, drop `showInApp`, point a `help` field at a missing anchor, change the CSP line, and add the word "anonymous" to a page; each must make `--check` fail with a clear message. Also confirm the pre-push hook blocks a push from a scratch clone whose `website/` fails strict.
4. **HTML validation:** `html-validate` over every page, zero errors.
5. **Links:** the internal checker passes; `scripts/gen-site.swift --check-external` reports no broken external links (Apple, Cloudflare, TelemetryDeck, Sentry, Featurebase, Mailgun, Google, EDPB, ICO, ChordPro).
6. **Routing in the Pages emulator** (`make site-serve`, http://localhost:8788), checked with `curl -sI`:
   - `/`, `/privacy`, `/terms`, `/support`, `/help`, `/help/live`, `/changelog`, `/press`, `/acknowledgements` return 200;
   - `/privacy.html` redirects to `/privacy`;
   - `/feedback` returns 302 to the board URL (or `/support#request-a-feature` before it is set);
   - `/nope` returns 404 with the custom page;
   - `/changelog.json` returns 200 with `Content-Type: application/json`;
   - every response carries the CSP and the other `_headers` values.
7. **Visual check in a real browser** (Chrome via the browser tooling; if the Playwright MCP is down, use the Chrome extension, and as a last resort ask Ryan for screenshots). Every page at **375x812** (phone), **768x1024** (tablet), **1280x800** and **1440x900** (desktop), in **dark** and **light** (DevTools > Rendering > Emulate `prefers-color-scheme`). Be picky, pixel-level:
   - no horizontal scroll at 320 px and 375 px; 16 px side gutters;
   - wordmark dot position matches brand.md; headings tight, no orphaned single words in the hero H1 at common widths;
   - "Coming soon" line (and later the badge at 48 px with clear space, black in both themes, not dominant) sits correctly in the hero;
   - nav disclosure works with keyboard and touch; focus ring visible on every interactive element;
   - zoom to 200% and text-only zoom: nothing clipped or overlapping;
   - no flash of invisible text (fonts swap), no layout shift when images load;
   - the chosen design direction (R55) is what was built: hero spotlight in both schemes, tile radii, the type scale and the 160/96 px section rhythm;
   - with Reduce Motion on, the hero beam is static.
   Save screenshots of each page/size/theme to the scratchpad and review them as a contact sheet.
8. **Lighthouse** (Chrome, mobile and desktop presets) on every page, first against `make site-serve`, then against the production URL after deploy (with the beacon): `pnpm dlx lighthouse@<pinned> <url> --only-categories=performance,accessibility,best-practices,seo`. Targets below.
9. **Request audit.** Locally: DevTools Network on every page with cache disabled: every request is same-origin; zero JS requests; zero cookies (Application > Cookies empty). Production: the same, except exactly two Cloudflare Web Analytics requests per page view (`static.cloudflareinsights.com/beacon.min.js` and a POST to `/cdn-cgi/rum` on the site's own origin); zero cookies; zero CSP violations in the console; the visit appears in the Web Analytics dashboard (ask Ryan to confirm).
10. **Accessibility pass:** VoiceOver (Safari) through the home page and the privacy policy: landmarks, heading order, link names, badge alt, tables announced with headers; keyboard-only tab through each page; `prefers-reduced-motion` on.
11. **App-contract check:** every URL and anchor in the section 2 contract list, and every `help` path in `changelog.json`, resolves on the live site after deploy (`curl` plus the fragment check from step 5).
12. **Policy-label diff (I-9):** compare the privacy policy's "What is sent" lists with WS3 section 5, WS3 10.2 and WS3's ingest client field list; every data type on the label is described in the policy, and nothing the policy denies is on the label.
13. **Post-deploy (production):** repeat steps 6, 8, 9 and 11 against `https://segue.ryandsilva.dev`; confirm TLS, that no preview deployment exists for a non-`main` branch, and that a commit touching only app code does not trigger a Pages build.

**Quality targets**

| Metric | Target |
|---|---|
| Lighthouse Performance (mobile) | >= 95 on every page, locally and in production |
| Lighthouse Accessibility | 100 on every page |
| Lighthouse Best Practices | 100 |
| Lighthouse SEO | 100 (404 excluded) |
| WCAG | 2.2 AA: text contrast >= 4.5:1, non-text >= 3:1, targets >= 24x24 px (nav and badge >= 44 px) |
| JavaScript | 0 bytes of our own; in production only Cloudflare's deferred Web Analytics beacon |
| Third-party requests / cookies | 0 / 0 locally; production only the two Web Analytics requests / 0 cookies |
| Weight | HTML+CSS per page < 40 KB uncompressed; fonts < 120 KB total; home page total < 700 KB at 1x. Known misses: the home page carries about 50 KB of interim re-creations (HTML plus `screens.css`) until the WS5 swap; `/privacy` is long-form (about 26 KB HTML plus 23 KB CSS). |
| CLS / LCP (mobile, lab) | < 0.02 / < 1.8 s |

---

## 12. Acceptance criteria

1. All pages from section 2 exist at those exact URLs, with the copy from section 9 (home, privacy, terms, support verbatim apart from slot values; the maker note as Ryan rewrote it; help written from the 0.5 build).
2. `content/site.json` is the only place any vendor name, vendor URL, location, transfer basis, retention period, legal name, governing state or App Store value appears; changing a value and running `make site` updates every page.
3. `make site`, `make site-check` and `make site-serve` work from a clean clone after `make bootstrap`; `make check` includes `site-check`; `make bootstrap` installs the pre-push hook.
4. `website/assets/css/tokens.css` is generated by `gen-tokens.swift` from `design/tokens.json` and guarded by `make tokens-check`.
5. `content/changelog.json` follows schema 1 (with `showInApp` and the 120-character limit); `website/changelog.json` is generated from it and is the file the app bundles; `/changelog` renders the same releases.
6. The site sets no cookies, ships no JavaScript of its own, loads every asset from its own origin, and serves the CSP in section 9.3, which allows only Cloudflare Web Analytics' two origins. Web Analytics is enabled on the Pages project.
7. Fonts are subset WOFF2 from the bundled OFL TTFs, with `OFL.txt` alongside and the lock file matching.
8. The badge is Apple's unmodified artwork, at least 40 px tall with quarter-height clear space, only in the home hero, linked with a campaign token; while `status` is `upcoming` no badge appears anywhere.
9. Favicon (SVG + 32 px PNG), apple-touch-icon and a 1200x630 Open Graph image exist and are referenced from every page's head.
10. **Claims audit:** a table in the session's commit message or hand-off lists every product claim on home, support, press and help, each marked verified in the 0.5 App Store build or removed. No personal-only, AI, PDF-export or MIDI feature is claimed. The policy-label diff (test 12) passes.
11. Every quality target in section 11 is met locally; production Lighthouse and the request audit are run after the first deploy.
12. Before production goes live: `make site-check STRICT=1` passes (no placeholders outside `appStore.*`, no maker-note markers).
13. `/feedback` redirects with 302 and the destination comes from config.
14. Ryan picked a design direction from the step 3 mockups before the home page was built.
15. Section 10's [RYAN] steps that remain open are listed in the session hand-off.

---

## 13. Risks

| Risk | Mitigation |
|---|---|
| Pushing `main` deploys immediately, so a commit with placeholders or the draft maker note goes public. | `--strict` refuses both; the versioned pre-push hook runs it on every push that touches `website/` or `content/`. |
| The policy's vendor facts drift from the vendors' real practices or from the app (consent copy, event list, label). | Re-read vendor pages before filling (9.4 preamble, stop-and-ask on any difference); policy-label diff (test 12); R-9 legal read. |
| TelemetryDeck's long archive retention reads badly in the policy. | Stated plainly as R32 rules; R-10 asks for a shorter period; only one config value changes if they offer one. |
| Cloudflare Web Analytics' injected beacon is blocked by a CSP mismatch, silently showing no data. | CSP origins checked against Cloudflare's docs at implementation; production console and dashboard check (test 9). |
| The beacon slightly lowers production Lighthouse Performance. | It is deferred and small; production Lighthouse is a target, measured after deploy. If it misses 95, report it rather than dropping analytics. |
| App copy and site copy drift (consent step vs `/privacy`, menu names vs `/support`, shortcuts vs `/help/keyboard`). | [VERIFY] markers and the claims audit; the URL/anchor contract in section 2; credits cross-checked against `AcknowledgementsView.swift`. |
| `/help` and `/help/*` coexistence behaves differently on Pages than assumed. | Verified in the emulator (section 2); documented fallback. |
| Screenshots from the R10 workstream aren't ready when the site must go live for submission. | Ship with `status: upcoming` and no art-dependent claims; strict blocks `live` without screenshots. |
| The Mailgun free plan allows one route; editing it wrongly breaks `contact@` mail. | Test first (R-5 step 1); the regex keeps both addresses. |
| Wrangler/html-validate/lighthouse via `pnpm dlx` pull npm packages at run time. | Exact version pins; dev-only tooling, nothing ships; `WRANGLER_SEND_METRICS=false`. |
| Cloudflare's dashboard labels move. | Click paths name the stable section names; the agent re-checks Cloudflare docs if a label is missing. |
| PNG/JPEG rasters differ between macOS versions, so they can't be byte-checked. | `--raster` is separate; checks cover presence and dimensions only. |

---

## 14. Step order

One commit per step (signed). Steps 1-2 need nothing from other workstreams.

1. **Config, generator and checks.** `content/site.json`, `content/changelog.json` (0.5 draft), the three partials (unstyled), `gen-site.swift` with all modes and checks, `_redirects`/`sitemap.xml` output, `_headers`, `robots.txt`, Makefile targets, `.htmlvalidate.json`, `.githooks/pre-push` and the `make bootstrap` hook line, `.gitignore`. Pages exist as unstyled skeletons with every contract anchor, so the checks run from the start.
2. **Tokens CSS and web fonts.** `gen-tokens.swift` output, `gen-webfonts.sh`, the WOFF2 files and lock file. Land before WS2b step 1 (shared `gen-tokens.swift`).
3. **Design directions (R39). Stop here.** Build 2-3 home-page mockups as described in 5.1, publish them for Ryan, and wait for his pick. Do not write `site.css` or style any page before he answers.
4. **Home page and shared styling** in the picked direction: `site.css`, header/footer partials, `index.html` with the maker-note draft inside its markers.
5. **Legal and support pages:** re-read vendor facts (9.4 preamble), then `privacy.html`, `terms.html`, `support.html`, `press.html`, `acknowledgements.html`, `404.html`, changelog template.
6. **Help pages** from the 0.5 App Store build (or current `main`, re-checked later).
7. **Rasters and images:** `--raster` outputs; screenshot JPEGs once the R10 set exists.
8. **Tests and hand-off:** section 11 steps 1-12, claims audit, list of open [RYAN] steps. Steps 13 (production) run after Ryan's R-1 to R-5.

---

## Open questions for Ryan

Only questions that came up while finalising; everything earlier is resolved in section 0.

1. **Maker note vs going live early.** The draft maker note blocks `STRICT=1`, so the site can't go live (A55) until you've rewritten it. (a) Keep it blocking: you write the two sentences before the first push (spec default); (b) ship the first push without the maker-note section and add it later.
