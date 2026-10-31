# 05 - Landing page website (research + plan)

Research date: 2026-10-17. Status: research and proposal only. Nothing is built yet.

**Already decided by Ryan** (relayed by the coordinator):

- The site lives at **`segue.ryandsilva.dev`**, a subdomain on free hosting.
- The app is **free**.
- Ryan lives in the **US**, so the privacy policy covers US (CCPA) and GDPR basics.
- The public support and privacy address is **`segue@ryandsilva.dev`**, which forwards to Ryan.
- **Scope update:** the app will collect **anonymous usage analytics** and offer **in-app bug reports** (with diagnostics) and a **feature-request board with upvotes**. A sibling agent is choosing the vendors. Vendor names below are placeholders, written as `{ANALYTICS_VENDOR}`, `{BUGREPORT_VENDOR}` and `{FEEDBACK_VENDOR}`. Sections 1.3, 1.4, 7 and 9 reflect this update and supersede any "local-only, Data Not Collected" wording elsewhere.

Facts not checked against a primary source are marked **UNVERIFIED**.

---

## 0. Current state of `ryandsilva.dev` (checked live, 2026-10-17)

| Fact | Evidence |
|---|---|
| Registrar: **Squarespace Domains II LLC** (migrated from Google Domains, registered 2019-02-28, expires **2027-02-28**) | RDAP `pubapi.registry.google/rdap/domain/ryandsilva.dev` |
| Nameservers: `ns-cloud-c{1..4}.googledomains.com`. These are the legacy Google Domains nameservers that Squarespace kept, so DNS is edited in the Squarespace Domains dashboard. | `dig NS ryandsilva.dev` (dashboard location UNVERIFIED) |
| Apex `A 104.198.14.52` (a Netlify load-balancer IP), and `ryandsilva.dev` serves `server: Netlify` (a Next.js personal site, "Ryan Dsilva") | `dig`, `curl -sI https://ryandsilva.dev` |
| Mail: `MX 10 mxa/mxb.mailgun.org`, `TXT v=spf1 include:mailgun.org ~all`, no DMARC record | `dig MX/TXT` |
| `segue.ryandsilva.dev` does not exist yet | `dig`, curl -> no host |
| The app repo `github.com/RyanDsilva/segue` is **private** | `gh repo view` |

Consequences:

- Any host has to work with **external DNS via a CNAME on a subdomain**, unless Ryan moves the nameservers.
- **GitHub Pages is out for the main repo.** Pages on private repos needs GitHub Pro or higher ([GitHub plans](https://docs.github.com/en/get-started/learning-about-github/githubs-plans): "GitHub Pages in public repositories" is listed under Free).
- Inbound mail already goes through **Mailgun**, so email forwarding has to fit around that (see section 3.4).

---

## 1. Pages an App Store app's website needs

### 1.1 What Apple actually requires

| URL | Required? | Source |
|---|---|---|
| **Privacy Policy URL** | **Required for iOS and macOS apps.** Guideline 5.1.1(i) also requires a link inside the app, "in an easily accessible manner". | [App information reference](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information); [Review Guidelines 5.1.1](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage) |
| **Support URL** | **Required.** It "must lead to actual contact information (legal address, email address, telephone number), as may be required by local law". Guideline 1.5 requires "an easy way to contact the developer". | [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information); [Guideline 1.5](https://developer.apple.com/app-store/review/guidelines/#developer-information) |
| Marketing URL | Optional | same page |
| EULA | Optional. With no custom EULA, Apple's **Licensed Application End User License Agreement (Standard EULA)** applies automatically. | [Standard EULA](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/): "subject to your prior acceptance of either this ... Standard EULA, or a custom end user license agreement" |

**EU DSA trader status.** Traders must show an address, phone number and email on the EU product page. A non-trader shows nothing, and EU users are told that consumer-protection rights don't apply ([Apple DSA](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/)). For an individual's free app with no monetisation, a non-trader declaration is likely defensible, but that is a legal judgement and **Ryan's call** (see D6). It also decides how much contact detail the Support page has to carry. An email address meets Apple's "actual contact information" in practice for most individual developers (UNVERIFIED as a formal rule).

### 1.2 Recommended page set

| Page | Why | Notes |
|---|---|---|
| `/` Home | Marketing; also serves as the Marketing URL | Section 7 |
| `/privacy` | **Required.** Linked from App Store Connect and from the app (About / Settings) | Section 1.3 |
| `/support` | **Required.** Contact, FAQ, system requirements, how to report a bug | Includes `mailto:segue@ryandsilva.dev` |
| `/changelog` (+ `/changelog.json`) | Release notes. Indie sites commonly have one (Supercharge, Tot). The app's What's New reads the JSON. | One canonical `changelog.json`; the HTML is generated from it (section 1.5) |
| `/terms` | Now needed: it covers the feedback board (user content, conduct, moderation) and the website, and points at Apple's Standard EULA for the app licence | Section 1.4 |
| `/feedback` | Entry point to the feature-request board and roadmap | A redirect, or a CNAME subdomain `feedback.segue.ryandsilva.dev` (section 1.6) |
| `/press` | Press kit: icon, screenshots, one-paragraph description, fact sheet, contact | Tot and forScore link one from the footer. A zip download is optional. |
| `/acknowledgements` | Credits for OFL Schibsted Grotesk, GRDB (MIT), Tonic (MIT) and so on | Mirrors the in-app acknowledgements. See the sibling licence doc if one exists. |
| App licence | **Keep Apple's Standard EULA** as the app licence; don't upload a custom EULA. `/terms` links to it. | A custom EULA adds legal surface for no benefit on a free app |
| `/404` | Hosts serve `404.html` | |
| `robots.txt`, `sitemap.xml`, `favicon.svg` / `apple-touch-icon.png`, Open Graph image | Polish and SEO | The OG image is 1200x630, made from the icon and wordmark |

### 1.3 What the privacy policy should say (free app with anonymous analytics, bug reports and a feedback board)

**What the policy must cover.** Apple 5.1.1(i) asks the policy to state:

- what data is collected, how, and all uses;
- any third parties that receive it, with confirmation that they protect it equally;
- retention and deletion, and how to revoke consent or request deletion.

GDPR Art. 13 adds the controller's identity and contact, purposes and legal basis, recipients, transfers outside the EU, retention, data-subject rights, and the right to complain to a supervisory authority ([Art. 13](https://gdpr-info.eu/art-13-gdpr/)).

**CCPA.** The CCPA "business" definition starts at **$26,625,000** annual gross revenue (from 2025-01-01), or at large data-trade volumes ([CPPA CPI adjustment](https://www.cppa.ca.gov/regulations/cpi_adjustment.html); [CPPA announcement](https://cppa.ca.gov/announcements/2024/20241217.html)). A free indie app is almost certainly **not** a CCPA business. The policy should still say plainly "we do not sell or share personal information".

**GDPR.** GDPR applies extraterritorially (Art. 3(2)) when someone offers goods or services to people in the EU.

**"Anonymous" analytics, the key legal point.**

- Truly anonymous aggregate data is outside GDPR.
- Most analytics SDKs use a random install or user ID. That makes the data **pseudonymous**, which is still personal data under GDPR.
- Storing or reading such an ID on the device also falls under the EU ePrivacy Directive Art. 5(3), which requires consent unless the ID is strictly necessary (legal reading, UNVERIFIED against counsel).
- Pick the vendor and its settings with this in mind:
  - IDs that rotate daily or are session-only, IP addresses not stored, and EU hosting or an SCC/DPF basis all reduce exposure;
  - **opt-in for analytics** is the safest posture;
  - an **opt-out toggle in Settings** is the minimum.
- This belongs in the sibling vendor doc; the policy only describes the result.

**Draft structure** (plain language, one screen plus a data table):

1. **Summary.**
   - "Your songs, setlists and gig logs stay in files on your Mac. We never see them."
   - "Segue sends anonymous usage statistics (you can turn this off), and only sends a bug report or feedback when you choose to."
   - "No ads, no tracking across apps, no sale of data."
2. **Data table**, one row per flow: what, when, why, who processes it, how long it is kept, and how to stop it.

   | Flow | Data | Trigger | Processor | Retention | Control |
   |---|---|---|---|---|---|
   | Usage analytics | Event names (for example "set started", "song imported"); app/OS version; Mac model class; coarse locale; a random install ID (rotating?). **No song content, titles, lyrics or file names.** | Automatic, if enabled | `{ANALYTICS_VENDOR}` | `{N}` days | Settings toggle (opt-in or opt-out per D13) |
   | Bug report | Your description; optional email; diagnostics you can review before sending (app version, OS, logs, optionally the current `.cho`) | Only when you press Send | `{BUGREPORT_VENDOR}` and email | Until resolved + `{N}` days | Don't send; ask us to delete |
   | Feedback board | Posts, comments, votes; display name/email or the vendor's login | When you use the board | `{FEEDBACK_VENDOR}` (its own privacy policy also applies) | Until you delete or ask us | Delete via the board or email |
   | Changelog fetch | The app requests `changelog.json`; the host sees your IP like any web request | On launch / What's New | Cloudflare (host) | Host log retention | None needed (no ID sent) |
   | Support email | Your address, message | You write to us | Mailgun (forwarding), Gmail | As needed to help you | Ask us to delete |
   | Website | IP and request logs; analytics per D11 | Visiting the site | Cloudflare | Host defaults | - |

3. **What we never collect.** Song content, lyrics, chords, setlists, library file names, contacts, location, advertising IDs. No cross-app tracking (ATT is not needed).
4. **On-device AI.**
   - AI runs on your Mac with Apple Foundation Models.
   - **Still to confirm:** whether the MLX fallback model download ships in the App Store build (`docs/00-vision.md` section 2). If it does, name the download host (UNVERIFIED which one).
   - Restricted modules are personal-build only and are not covered.
5. **Apple.**
   - Downloads are handled by Apple under Apple's policy.
   - Apple crash reports reach the developer only if you opted in to share with app developers.
6. **Legal basis (GDPR).**
   - Analytics: consent, or legitimate interest per D13.
   - Bug reports and feedback: your request, or legitimate interest in improving the app.
   - Support: answering you.
7. **Processors and transfers.** List the vendors with links to their policies, state that each is bound to protect the data at least as well as this policy (the Apple requirement), and give the transfer mechanism (SCCs or the EU-US Data Privacy Framework, per vendor).
8. **Retention and deletion.** Per the table. Note that anonymous analytics without an ID cannot be tied back to you, so they cannot be deleted per person; say this honestly.
9. **Your rights.**
   - Access, correction, deletion and objection via `segue@ryandsilva.dev`.
   - EU/UK residents can complain to their supervisory authority.
   - California: no sale or sharing.
10. **Children.** Not directed at children under 13 (US) / 16 (EU).
11. **Changes.** Effective date at the top; material changes are noted in the changelog.
12. **Contact and controller.** "Ryan Dsilva, `segue@ryandsilva.dev`". Postal address per D6.

**App Store Connect "App Privacy" impact.** It is **no longer "Data Not Collected"**. Likely categories, all **"Not Linked to You"** and **not used for tracking**:

- **Usage Data > Product Interaction** (analytics);
- **Diagnostics > Crash Data / Performance Data / Other Diagnostic Data** (bug reports);
- **User Content > Customer Support / Other User Content** (report text, feedback posts);
- **Contact Info > Email Address** (if the bug report or board takes an email, this one is probably "Linked").

Apple's definitions ([App privacy details](https://developer.apple.com/app-store/app-privacy-details/)) were not re-read in this session (UNVERIFIED). The sibling vendor agent should map each SDK to these categories.

### 1.4 Terms page (`/terms`)

Short, plain-language, effective date at the top.

1. **The app licence.**
   - The app is licensed under Apple's **Licensed Application End User License Agreement (Standard EULA)** ([link](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/)).
   - These terms add only the rules for the website and the feedback board.
2. **Free, as-is.** No warranty beyond what the EULA and law require. Back up your library (files are yours and stay local).
3. **Feedback board and bug reports (user content).**
   - You keep ownership of what you post.
   - You grant a non-exclusive, royalty-free licence to use the feedback to improve Segue.
   - No obligation to implement anything or to credit or pay you.
   - Upvotes and roadmap status are not promises.
4. **Conduct and moderation.** No illegal, abusive or spam content, and no copyrighted lyrics pasted wholesale. We may edit, merge or remove posts. Also follow the vendor's own terms (`{FEEDBACK_VENDOR}`).
5. **Third-party services.** The board and analytics run on third-party services; see the privacy policy.
6. **Trademarks.** "Segue" name and icon. Plus the Apple attribution.
7. **Governing law.** US state of residence (D14). Contact email.

Writing the actual text is a separate task. If the board vendor's terms already cover user-content licensing, keep section 3 minimal.

### 1.5 Changelog as HTML and JSON (`/changelog`, `/changelog.json`)

- **Single source:** `website/changelog.json`, edited by hand. Never the auto-generated `CHANGELOG.md`, if one ever exists.
- **Generation:** a small `scripts/gen-site.swift` (same style as `gen-tokens.swift`) renders `/changelog/index.html` from it. `make site-check` fails if the HTML is stale (the `--check` pattern). The App Store "What's New" text is copied from the same entry.
- **Proposed schema** (versioned so the app can reject unknown majors):

```json
{
  "schema": 1,
  "releases": [
    {
      "version": "1.1.0",
      "build": "42",
      "date": "2026-12-01",
      "minimumOS": "26.0",
      "title": "Requests, faster",
      "highlights": [
        { "kind": "new", "text": "Request queue keyboard shortcuts", "learnMore": "https://segue.ryandsilva.dev/support#requests" },
        { "kind": "improved", "text": "Auto-scroll is smoother on long songs" },
        { "kind": "fixed", "text": "Capo chip now updates after transpose" }
      ]
    }
  ]
}
```

- **App side:**
  - What's New shows entries newer than the last-seen version.
  - A copy is **bundled in the app at build time** and fetched remotely only to pick up corrections, so the first launch after an update works offline. That matters on stage.
  - The remote fetch uses no IDs or cookies.
  - It needs the `com.apple.security.network.client` sandbox entitlement. The analytics SDK likely needs it anyway.
  - Add `_headers`: `Cache-Control: max-age=300` for `/changelog.json`.
- **Optional extras:** an Atom feed `/changelog.xml` from the same JSON (cheap, nice for press and power users).

### 1.6 Feedback board entry point

- **Site side:** the `/feedback` path is a **redirect** (Cloudflare Pages `_redirects`: `/feedback  https://<vendor-board-url>  302`). The app, footer and Support page all link `/feedback`, so the vendor can be swapped without an app update. This is the "own the identity locally, the vendor is a binding" pattern.
- **Optional custom subdomain:** `feedback.segue.ryandsilva.dev`, set up as a CNAME at Squarespace pointing to the vendor. This only works if the vendor's **free tier** supports custom domains and issues TLS for them. That is required, because `.dev` is HSTS-preloaded and the browser will not load it over HTTP. Many feedback vendors gate custom domains behind paid plans (UNVERIFIED per vendor; the sibling agent should check). If the free tier lacks custom domains, keep only the redirect.
- **Roadmap:** if the vendor has a public roadmap view, link it as `/roadmap` (another redirect). Otherwise, skip the roadmap rather than hand-maintaining one.
- **App:** a Help menu with "Send Bug Report..." (in-app form, `{BUGREPORT_VENDOR}`), "Request a Feature..." (opens `/feedback`) and "What's New" (changelog).

---

## 2. Apple marketing rules

Source for everything in this section unless noted: [App Store Marketing Guidelines](https://developer.apple.com/app-store/marketing/guidelines/). Artwork comes from the [App Store Marketing Tools / toolbox](https://toolbox.marketingtools.apple.com/app-store/).

### 2.1 Badge

- **Artwork.** Use the **"Download on the Mac App Store"** badge, downloaded from Apple. "Use only the badge artwork provided."
- **Colour.**
  - The **preferred black** badge is the default. Its grey border is part of the artwork, which is exactly what makes it read on a dark (`stage #101113`) page.
  - The white badge is allowed only when it is the single badge in the layout and suits the colours.
- **Size.** Minimum **40 px** onscreen height.
  - Normal clear space is **1/4 of the badge height**.
  - In very limited layouts the minimum is 1/10 of the height.
- **No changes.** "Don't modify, angle, or animate the App Store badge." No one-colour printing.
- **Localisation.**
  - 50 localisations exist.
  - "Never translate App Store or create your own localized badge."
  - English-only site: use the English badge.
- **Placement.**
  - "Use one App Store badge per layout."
  - It must sit in a "subordinate position to the image or main message".
  - The hero and the final call to action are separate scroll sections, which is common practice (forScore repeats it), but a strict reading favours a single badge per page view (**D7**).
- **Link.** The badge links to the App Store URL in section 2.4.

### 2.2 Product names and trademarks

- **Product names.** Write "Mac" and "MacBook Pro" exactly.
  - Apple: "avoid referring to iOS, macOS ... in your marketing communications". Say "Segue for Mac" and "designed for MacBook on stage".
  - A requirements line ("Requires macOS 26 or later") is near-universal on indie pages. Keep it on Support and in small print rather than in headlines.
- **Wording.** Say "available on the App Store" or "Download on the Mac App Store". Never "at the App Store" and never "downloadable".
- **Trademark symbols.** ™/® are only for US-only communications and should not be used for material distributed outside the US. A worldwide website therefore uses **no symbols**. Add a footer attribution instead: "Apple, the Apple logo, Mac, MacBook and macOS are trademarks of Apple Inc., registered in the U.S. and other countries and regions. App Store is a service mark of Apple Inc." Hand Mirror does this. Exact wording UNVERIFIED; take it from [Apple's trademark list](https://www.apple.com/legal/intellectual-property/trademark/appletmlist.html).
- **URLs** must not start with an Apple trademark. `segue.ryandsilva.dev/mac` would be fine; `macsegue.com` would not.

### 2.3 Device frames

- Apple publishes **MacBook Air M5, MacBook Pro M5, MacBook Neo and Studio Display** bezels (Photoshop and PNG) on [Apple Design Resources](https://developer.apple.com/design/resources/#product-bezels).
- The rules ("section-products" of the marketing guidelines):
  - Use **Apple-provided bezels**, the latest-generation devices, "as is".
  - No reflections, shadows, highlights, crops, tilts, obstructions, animation or flipping.
  - Minimum device height is **200 px onscreen**.
- The download DMGs carry their own licence agreement. Its exact terms were **not read** (UNVERIFIED). Read it before use.
- **Recommendation.** Use the MacBook Pro M5 bezel for one hero shot of stage mode, untilted. Elsewhere show plain window screenshots with macOS's own window shadow: a screenshot taken with `Cmd-Shift-4`, Space, is not an Apple product image. A frameless screenshot also avoids the bezel rules and fits the Linear-style aesthetic.

### 2.4 Links and campaign analytics

- **Canonical link:** `https://apps.apple.com/app/id<APPLE_ID>`. On a Mac it opens the Mac App Store.
- **Campaign links** ([Manage campaigns](https://developer.apple.com/help/app-store-connect/view-app-analytics/manage-campaigns/)) look like `https://apps.apple.com/app/apple-store/id123456789?pt=<provider token>&ct=<campaign>&mt=8`.
  - `pt` is generated once per account.
  - `ct` is at most 30 characters.
  - Results appear in App Analytics after 24 hours, with a 5-download minimum threshold.
- **Use** `ct=website-hero`, `ct=website-footer` and `ct=press` (and `ct=reddit` and so on for posts).
- **Why it matters.** This gives website-to-download attribution **without any analytics on the website** (section 5).

---

## 3. Hosting (free) and domain

### 3.1 Options, with terms verified from primary sources on 2026-10-17

| Host | Free terms | Commercial use | Works with private repo + external DNS subdomain? | Verdict |
|---|---|---|---|---|
| **Cloudflare Pages** | 500 builds/month, 20,000 files, 25 MiB per file, 100 custom domains per project ([limits](https://developers.cloudflare.com/pages/platform/limits/)). Bandwidth is not metered on the limits page. | No restriction found in the [website terms](https://www.cloudflare.com/website-terms/). Self-serve terms not fully read (UNVERIFIED). | **Yes.** A subdomain works via CNAME at external DNS; only the apex needs Cloudflare nameservers ([custom domains](https://developers.cloudflare.com/pages/configuration/custom-domains/)). The GitHub app can be scoped to selected repos ([GitHub integration](https://developers.cloudflare.com/pages/configuration/git-integration/github-integration/)). Private-repo support is not explicit in that page (UNVERIFIED but widely used). Direct Upload via Wrangler is also supported. | **Recommended** |
| Cloudflare Workers static assets | "Requests to static assets are free and unlimited" ([billing](https://developers.cloudflare.com/workers/static-assets/billing-and-limitations/)) | as above | **No.** Custom Domains need "an active Cloudflare zone" ([docs](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/)), so it only fits if `ryandsilva.dev` moves to Cloudflare nameservers. | Only if D3 = move DNS |
| Netlify (already hosts `ryandsilva.dev`) | **New credit plans** (accounts after 2025-09-04): 300 credits/month hard limit, **15 credits per production deploy**, 20 credits/GB. When credits run out, "**all of your web projects ... are paused**" ([credit plans](https://docs.netlify.com/manage/accounts-and-billing/billing/billing-for-credit-based-plans/credit-based-pricing-plans/), [FAQ](https://docs.netlify.com/manage/accounts-and-billing/billing/billing-for-credit-based-plans/billing-faq-for-credit-based-plans/)). **Legacy Free** (accounts before 2025-09-04): 100 GB/month and 300 build minutes, hard limits ([legacy](https://docs.netlify.com/manage/accounts-and-billing/billing/billing-for-legacy-plans/legacy-pricing-plans/)). | Terms of Use have no commercial ban. AUP not read (UNVERIFIED). | Yes | Viable fallback. The risk is that a traffic spike or deploy churn pauses **both** sites, including the personal site, on a credit plan. Ryan's plan type is UNVERIFIED (D2). |
| Vercel Hobby | 100 GB transfer | **"Hobby teams are restricted to non-commercial personal use only."** Commercial includes "Advertising the sale of a product or service" ([fair use](https://vercel.com/docs/limits/fair-use-guidelines)). | Yes | **Avoid.** A free app is arguably not "sale", but this is grey and the only host with an explicit ban. |
| GitHub Pages | 1 GB site, soft 100 GB/month. Not for "online business, e-commerce ... or commercial SaaS" ([limits](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits)). | A marketing page for a free app is fine. | **No.** Private repos need Pro. It would require a separate public repo, which breaks "source inside the git repo". | Avoid |

**Domain.** `segue.ryandsilva.dev` costs nothing beyond the existing renewal (decided). A new domain such as `segue.app` or `getsegue.com` costs money, so it is ruled out. `.dev` is HSTS-preloaded, so every subdomain must be served over HTTPS. All the hosts above issue certificates automatically.

### 3.2 Recommended setup: Cloudflare Pages with Git integration, no build step

1. In Cloudflare, create a Pages project connected to `RyanDsilva/segue`.
   - Give the GitHub app access to **only** this repo.
   - Production branch `main`, root/output directory `website/`.
   - Build command: none.
   - Turn on **build watch paths** = `website/**`, so app-only commits don't redeploy. Feature name per Cloudflare docs, UNVERIFIED.
2. At Squarespace DNS, add `CNAME segue -> <project>.pages.dev`, then add the custom domain in the Pages dashboard. Cloudflare validates it and issues TLS.
3. Every push to `main` that touches `website/` deploys. Branch pushes get preview URLs.

**Alternative (D4): Direct Upload with Wrangler.** `make site-deploy` runs `npx wrangler pages deploy website/`, pinned via mise's node. This keeps Cloudflare's GitHub app off the private repo, but it adds a Node toolchain and a manual or CI step. Ryan prefers auto-deploy from day one, which favours Git integration.

### 3.3 Manual steps for Ryan

He must do these himself:

- Create the Cloudflare account and Pages project.
- Authorise the GitHub app (scoped to the repo).
- Add the CNAME at Squarespace.
- Create the App Store campaign links after the app record exists.

### 3.4 `segue@ryandsilva.dev` forwarding (free)

MX already points at **Mailgun**, and Mailgun's free plan has **one inbound route** ([costbench](https://www.costbench.com/software/email-api/mailgun/free-plan/), [usecarly](https://www.usecarly.com/blog/mailgun-pricing/); secondary sources, UNVERIFIED on mailgun.com). Ryan presumably already forwards `contact@ryandsilva.dev` this way.

| Option | Cost | Changes | Notes |
|---|---|---|---|
| **A. Reuse the Mailgun route (recommended)** | Free | First send a test to `segue@ryandsilva.dev`. If the existing route is a catch-all, nothing changes. Otherwise edit the single route's filter to `match_recipient("^(contact\|segue)@ryandsilva\.dev$")` -> `forward("<gmail>")`. | Stays within the 1-route limit. No DNS change. Replies "as" segue@ can go through Gmail "Send mail as" with Mailgun SMTP (free tier, 100/day). |
| B. Squarespace email forwarding | Free; "up to 100 email forwarding addresses" ([Squarespace](https://support.squarespace.com/hc/articles/17131164996365)) | Replaces the MX records, which breaks Mailgun inbound | Only if Mailgun inbound is not otherwise needed |
| C. Cloudflare Email Routing | Free (UNVERIFIED on the pricing page) | **Requires Cloudflare nameservers** ([docs](https://developers.cloudflare.com/email-routing/get-started/enable-email-routing/)). Move the whole zone, recreate the Netlify A and Mailgun records, and replace the MX. | Only if D3 = move DNS to Cloudflare |

Also recommended: add a `_dmarc` TXT record (`v=DMARC1; p=none; rua=mailto:...`), since none exists. Forwarded mail from strict-DMARC senders can be rejected by Gmail. Mailgun's forwarding behaviour here is UNVERIFIED.

---

## 4. Build approach

| Option | Dependencies | Fit |
|---|---|---|
| **Hand-written HTML + CSS + a small `scripts/gen-site.swift`** (recommended) | Zero runtime dependencies. Generators in Swift (already the repo's script language), run locally, with output committed. | About 8 pages that rarely change. The generator does three jobs: render `/changelog` from `changelog.json`, stamp the shared header and footer into each page, and write `sitemap.xml`. `--check` fails on stale output, like `gen-tokens.swift`. No build runs on the host. |
| Hugo | One Go binary, installable via mise | Good, zero npm. Adds a template language and a theme layer for 6 pages. |
| Eleventy | npm package plus its dependency tree | Ruled out by the minimal-dependency preference. |
| Astro | Large npm tree, frequent major versions | Overkill. It would need ongoing upgrade work. |

**Recommendation: plain HTML/CSS in `website/` plus a committed-output Swift generator**, deployed as-is. The scope update (a JSON changelog the app reads) makes a generator worthwhile; one canonical JSON beats keeping HTML and JSON in sync by hand.

Proposed layout:

```
website/
  index.html  privacy/index.html  terms/index.html  support/index.html
  changelog/index.html (GENERATED)  changelog.json (canonical)  changelog.xml (optional, GENERATED)
  press/index.html  acknowledgements/index.html  404.html
  _redirects       # /feedback, /roadmap -> vendor board (swap vendor without an app update)
  assets/
    tokens.css     # GENERATED by scripts/gen-tokens.swift from design/tokens.json
    site.css       # hand-written; uses only var(--token)
    fonts/SchibstedGrotesk-{400,600,800}.woff2 + OFL.txt
    img/ (icon.svg from design/icon/master.svg, screenshots @2x WebP/PNG, og.png)
    badge/ (Apple's Mac App Store badge SVG, unmodified)
  robots.txt  sitemap.xml  _headers  (Cloudflare: cache + security headers)
```

**Tokens.**
- Extend `scripts/gen-tokens.swift` to also write `website/assets/tokens.css`.
  - Light values go under `:root`.
  - Dark values go under `@media (prefers-color-scheme: dark)`.
  - The page is **dark-first**: set `color-scheme: dark light`, and decide in D8 whether light mode is offered at all.
- `make tokens-check` already fails on stale output, so it also guards the CSS.
- One source of truth stays `design/tokens.json`. This touches a script, so it is a build task, not part of this research.

**Fonts.**
- Schibsted Grotesk is OFL 1.1. The repo's `OFL.txt` header names **no Reserved Font Name** (only "Copyright 2023 The Schibsted-Grotesk Project Authors"), so converting and subsetting to WOFF2 needs no renaming.
- The OFL FAQ explicitly endorses `@font-face` webfonts. The licence text isn't required alongside webfonts, but shipping `OFL.txt` and crediting the font on `/acknowledgements` is best practice ([OFL FAQ](https://openfontlicense.org/ofl-faq/)).
- Convert the bundled TTFs (`Packages/SegueUI/Sources/SegueUI/Theme/Fonts/`) with `uvx --from 'fonttools[woff]' pyftsubset ... --flavor=woff2 --layout-features='*' --unicodes=U+0000-00FF,U+2010-2027`. Commit the output; it is about 20-30 KB per weight, so this is a small derived asset (D9).
- Use `font-display: swap` and preload the 800 weight for the hero.

**Quality gates (CI or `make site-check`):**
- An HTML validator (`vnu`, UNVERIFIED in mise) or `htmltest` for links.
- A Lighthouse run (Node) is optional.
- **Recommended minimum:** an internal link checker plus `tokens-check`.

---

## 5. Website analytics

This section is about the **website** only. App analytics (decided: anonymous usage analytics) come from the sibling vendor doc, and the privacy policy covers both.

| Option | Cost | Cookies / personal data | Privacy-policy impact |
|---|---|---|---|
| **None + App Store campaign tokens** (recommended) | Free | None on the site | Simplest policy. App Analytics still shows page views of the App Store listing and downloads per `ct`. |
| Cloudflare Web Analytics | Free. "does not use any client-side state, such as cookies or localStorage ... We also don't 'fingerprint'" ([Cloudflare](https://www.cloudflare.com/web-analytics/)). On Pages it can be turned on in the dashboard. | No cookies | Policy names Cloudflare as processor. No consent banner needed under ePrivacy, since nothing is stored on the device (UNVERIFIED legal reading). |
| GoatCounter (hosted) | "free for reasonable public usage". Small businesses are fine ([goatcounter.com](https://www.goatcounter.com/)). | No cookies, no persistent personal data | Names GoatCounter. Adds a third-party script and a separate account. |

If Ryan wants on-site numbers (referrers, which pages), choose Cloudflare Web Analytics. The host already sees the traffic, so it adds no new third party.

---

## 6. Prior art: indie and Apple-ecosystem app sites

| Site | Structure | Polish worth taking |
|---|---|---|
| [Rogue Amoeba Farrago](https://rogueamoeba.com/farrago/) (soundboard, theatre and live use) | Hero (headline, subhead, Download/Purchase, 90 s video) -> use-case trio (Podcast / Theatre / Chats) -> 12-feature grid -> **annotated interface tour** (4 stops) -> press and user quotes -> big footer directory | Use-case framing for live performers. The annotated screenshot tour. |
| [Mela](https://mela.recipes/) | One-sentence hero + platform downloads -> award -> feature sections, one screenshot each (Cook mode is its "stage mode") -> privacy note (no data, iCloud only) | Cook mode is the analogue of stage mode. Short, plain privacy statement. |
| [Things](https://culturedcode.com/things/) | Hero + intro video -> "Simply Powerful" -> per-platform cards (requirements, price, badge) -> press quotes and awards -> newsletter -> deep footer | Restraint, generous whitespace, high-quality video poster |
| [Supercharge (Sindre Sorhus)](https://sindresorhus.com/supercharge) | Icon + tagline + requirements -> CTAs -> quick features -> screenshots -> exhaustive feature list -> FAQ -> footer (Privacy, Terms, **Release Notes**) | FAQ and release notes on the product page. A one-person-dev model. |
| [Hand Mirror](https://handmirror.app/) | Tagline + requirement + App Store link -> press -> "What is this?" / "Yeah but why?" -> features -> creator intro -> **Apple trademark disclaimer** footer | Conversational problem/solution copy. A personal maker note. |
| [forScore](https://forscore.co/) (sheet music, a direct neighbour) | Tagline + badge -> 8 feature cards (Gorgeous, Powerful, Fast...) -> Pencil spotlight -> per-platform sections -> ratings and press -> compatibility matrix -> categorised footer (privacy, press, support) | Musician audience. Hands-free (MIDI/pedal) callout. Compatibility matrix. |
| [OnSong](https://www.onsongapp.com/) (chord charts, a direct competitor) | Hero -> stats -> "50+ features" -> audience segments (singers, worship, entertainers) -> testimonials -> CTA "ditch the binder" | Audience segments. "Ditch the binder" framing (paper replacement). Busier than we want. |
| [Tot (Iconfactory)](https://tot.rocks/) | Tagline + three platform downloads -> 8 short features -> quotes -> **What's New** with link to version history -> pricing line -> footer (Privacy, Terms, **Press Kit**) | A "What's New" strip on home. Small footer legal set. |
| [Klack](https://tryklack.com/) | One-line hero + buy -> social proof -> **interactive** sound picker -> 9 benefits -> CTA | One interactive demo makes the product tangible |
| [Ice](https://icemenubar.app/) | Logo + tagline + Download / GitHub / Donate -> features with GIF/video loops -> copyright | Minimal, single page. Short loops instead of static shots. |
| [Linear](https://linear.app/) (visual reference) | Sticky nav, huge tight headline, dark product shots in-flow, alternating text/visual blocks, categorised footer | Dark-first type scale, product UI as the hero art |

**Patterns to adopt:**

- A one-sentence hero with **real product UI as the art**: stage mode on a MacBook.
- A **"day in the life"** narrative (Monday paste, Thursday set, Friday gig) instead of a feature dump. It mirrors the vision's worked example and the Farrago/OnSong use-case framing.
- 6-9 short feature cards.
- Short muted video loops. Respect `prefers-reduced-motion`, consistent with brand motion rules.
- A privacy statement on the home page (Mela).
- FAQ on Support.
- What's New linked from the footer.
- Trademark disclaimer.
- A personal maker note.

**What makes these sites feel polished:**

- One accent colour used sparingly (our coral cue).
- Big tight headlines (800 / -0.045em).
- Real screenshots at 2x, never mock UI.
- Generous section spacing on an 8 px rhythm.
- Fast loads: no JavaScript framework, preloaded fonts, sized images (no layout shift).
- Consistent footers.
- Accessible contrast. The brand table already lists the AA-passing pairs.

---

## 7. Proposed sitemap and content outline for Segue

```
segue.ryandsilva.dev/
  /                 Home
  /support          Support + FAQ + contact
  /privacy          Privacy policy (app analytics, bug reports, feedback board, website, email)
  /terms            Terms (website + feedback board; app licence = Apple Standard EULA)
  /changelog        Release notes (HTML, generated)
  /changelog.json   Machine-readable changelog read by the app's What's New
  /feedback         -> 302 to {FEEDBACK_VENDOR} board (or CNAME feedback.segue.ryandsilva.dev)
  /roadmap          -> 302 to vendor roadmap view, only if the vendor has one
  /press            Press kit
  /acknowledgements Open-source and font credits
  /404
```

### Home (`/`), dark-first, single column, max width about 1080 px

1. **Nav (sticky, slim).**
   - Wordmark "Segue" with the cue dot.
   - Links: Features, Changelog, Feedback, Support.
   - A small "Download" text link. The badge proper lives in the hero, per the one-badge rule.
2. **Hero.**
   - Eyebrow: "For Mac".
   - H1: tagline **"Your chart, your set, your cue."**
   - Subhead: "Setlists, lyrics and chords for solo and duo gigs. Built for a MacBook on a stand."
   - Mac App Store badge (black, at least 40 px, `ct=website-hero`).
   - Small print: "Free. Requires macOS 26 or later." (Placement per section 2.2.)
   - Art: stage-mode screenshot in the MacBook Pro M5 bezel, or frameless (D10).
3. **The week of a gig** (three steps, each with a screenshot):
   - *Monday: get songs in.* Paste a messy chord sheet and on-device AI makes a clean chart; the visual chord editor.
   - *Thursday: build the set.* Drag-and-drop setlists, plus the "45 minutes, upbeat start" assistant.
   - *Friday: play.* Stage mode: dark, whole song at a glance, next-song footer, requests, gig log.
4. **Stage-mode spotlight.**
   - Large dark screenshot with 3-4 callouts: progress dots, the cue for the current song, key/capo/BPM, Up next.
   - Copy on the brand rules: readable at stage distance, never below your minimum size, no sleep or notifications.
5. **Feature grid (6-8 cards):**
   - ChordPro files you own (plain files in a folder you choose).
   - Transpose and capo.
   - Tags and proficiency.
   - Fast search, including romanized Hindi spelling variants.
   - Requests queue.
   - Hands-free MIDI control with MIDI learn and key learn (only once phase 6 has shipped).
   - PDF export (only once phase 4 has shipped).
   - Light and dark.
   - **Only list features in the App Store build.** No LRCLIB or URL import.
6. **Private by design.** "No account. Your songs never leave your Mac. AI runs on-device. Only anonymous usage stats, and you can switch them off." Link to `/privacy`. Wording must match the final analytics design exactly; never claim "no tracking" or "no data collected" once analytics ship.
6b. **Shaped by players.** "Vote on what's next": link to `/feedback`, plus a "What's new" strip with the latest `changelog.json` entry (Tot pattern). The strip is rendered by the generator; no client-side JavaScript fetch is needed.
7. **Maker note (optional).** Two lines from Ryan: built by a gigging musician for his own sets (Hand Mirror style).
8. **Final CTA.** Repeat the tagline with a badge (`ct=website-footer`), or a text link if D7 says one badge only.
9. **Footer:**
   - Support, Feedback, Changelog, Press kit, Privacy, Terms, Acknowledgements.
   - `segue@ryandsilva.dev`.
   - "© 2026 Ryan Dsilva".
   - Apple trademark attribution.

### `/support`

- Contact: `segue@ryandsilva.dev`, with a typical reply time.
- **Report a bug:** use Help > Send Bug Report... in the app, which attaches diagnostics you can review first. Email is the fallback; list what to include (macOS version, app version, steps, optionally a `.cho` file).
- **Request a feature:** link to `/feedback` (the upvote board).
- System requirements.
- **FAQ:**
  - Where are my songs stored?
  - How do I back up or move the library?
  - What's ChordPro?
  - Does it need the internet? (No for core use; analytics, the What's New refresh and feedback use it.)
  - What does analytics collect, and how do I turn it off?
  - Is AI on-device?
  - Which Macs support Apple Intelligence features? (the fallback behaviour)
  - MIDI and key learn.
  - Is it free?
  - How do I request a feature?
- Links to Changelog and Privacy.

### `/privacy`

Section 1.3 structure, with an effective date at the top.

### `/terms`

Section 1.4 structure.

### `/changelog` and `/changelog.json`

- Section 1.5. Version, date, title and 3-8 tagged highlights per release, newest first, with an anchor per version (`#1.1.0`).
- The same text goes into App Store "What's New".
- The JSON is canonical and hand-edited; the HTML is generated.

### `/feedback` (and optional `/roadmap`)

- Section 1.6. Redirects only. No board content lives in this repo.

### `/press`

- One-line and one-paragraph descriptions.
- Fact sheet: developer, price (free), platform, release date, website, contact.
- Icon PNGs (1024, 512).
- 5 screenshots at 2x.
- Wordmark SVG on dark and light.
- Brand colours (from tokens).
- Mac App Store link.

### `/acknowledgements`

- Schibsted Grotesk (OFL 1.1, with a link to the OFL text).
- GRDB.swift (MIT).
- Tonic (MIT).
- Any others in the App Store build. Generate the list from the same source as the in-app list if one exists.

---

## 8. Deploy pipeline sketch

```
edit website/** (or design/tokens.json -> make tokens; website/changelog.json -> make site)
  -> make site-check   (tokens-check + gen-site --check + changelog.json schema check + link check)
  -> signed commit on main (repo convention), git push
  -> Cloudflare Pages Git integration: watch path website/** -> publish website/ as-is
  -> https://segue.ryandsilva.dev  (CNAME at Squarespace DNS -> <project>.pages.dev, auto TLS)
Preview: any non-main branch push -> <branch>.<project>.pages.dev
```

Notes:

- No build step runs on the host. The generated `tokens.css` and the fonts are committed, and `tokens-check` keeps them honest.
- **Before App Store submission:** `/privacy`, `/terms` and `/support` must be live, because App Store Connect requires the privacy and support URLs. `/changelog.json` must be live too, because the app reads it. Keep a bundled copy in the app so a missing site never breaks What's New.
- **Release checklist line:** add the new entry to `changelog.json`, run `make site`, then push. That publishes the site entry before or with the App Store release.
- Wire the privacy link into the app's About / Settings (guideline 5.1.1(i)).
- Add `_headers` for long cache on `/assets/*` with a fingerprinted filename or a query version, plus basic security headers (`X-Content-Type-Options`, `Referrer-Policy`, a CSP with `default-src 'self'` and no third-party scripts).

---

## 9. Decisions for Ryan

1. **D1 Build:**
   - (a) plain HTML/CSS plus `gen-site.swift` (changelog render, header/footer, sitemap; committed output) (recommended now that the JSON changelog exists);
   - (b) plain HTML with headers copied per page and the changelog HTML hand-kept in sync (not recommended);
   - (c) Hugo via mise, which reads the JSON as a data file.
2. **D2 Host:**
   - (a) Cloudflare Pages (recommended: unmetered static, no commercial clause, subdomain CNAME works);
   - (b) Netlify, which the account already has. First check whether it is legacy Free or credit-based; on credits, exhaustion pauses `ryandsilva.dev` too.
3. **D3 DNS:**
   - (a) keep Squarespace DNS and add one CNAME (recommended, smallest change);
   - (b) move `ryandsilva.dev` nameservers to Cloudflare (free). This unlocks Workers and Email Routing, but means migrating the Netlify and Mailgun records.
4. **D4 Deploy trigger:**
   - (a) Cloudflare Git integration scoped to this repo, with auto-deploy (recommended);
   - (b) Wrangler Direct Upload from `make site-deploy` or GitHub Actions, which keeps Cloudflare's app off the private repo but adds Node.
5. **D5 Email:**
   - (a) reuse the Mailgun route: test first, then widen the regex if needed (recommended);
   - (b) Squarespace forwarding (drops Mailgun inbound);
   - (c) Cloudflare Email Routing (needs D3b).
   - Also: add DMARC? yes/no.
6. **D6 EU DSA status and contact detail:**
   - (a) declare non-trader and show email only (likely, for a free individual app; legal judgement);
   - (b) trader, which means a public address or P.O. box and phone number on the App Store and the Support page.
7. **D7 Badge count:**
   - (a) hero badge only, with a text link in the final CTA (strict reading);
   - (b) badge in both the hero and the final CTA (common practice).
8. **D8 Theme:**
   - (a) dark-only site;
   - (b) dark-first with a `prefers-color-scheme: light` variant from the same tokens.
9. **D9 Fonts:** commit subset WOFF2 files (recommended, about 100 KB total), or generate them at deploy time. The second needs a host build step.
10. **D10 Hero art:**
    - (a) Apple MacBook Pro M5 bezel, after reading its DMG licence;
    - (b) frameless window screenshot.
    - Separately: a video loop or stills?
11. **D11 Analytics:**
    - (a) none, plus App Store campaign tokens (recommended);
    - (b) Cloudflare Web Analytics;
    - (c) GoatCounter.
12. **D12 App Store build networking:** confirm whether the MLX on-demand model download ships in the App Store build. This decides one paragraph of the privacy policy.
13. **D13 App analytics consent:**
    - (a) opt-in at first launch (safest for EU ePrivacy);
    - (b) on by default with an opt-out toggle in Settings (common; relies on truly anonymous, ID-free data to be defensible);
    - (c) opt-out in the US and opt-in in the EU (more code).
    - Coordinate with the sibling vendor doc.
14. **D14 Terms governing law:** which US state.
15. **D15 Feedback URL:**
    - (a) `/feedback` redirect only (recommended; works on any vendor tier);
    - (b) also a `feedback.segue.ryandsilva.dev` CNAME, only if the chosen vendor's free tier supports custom domains with TLS.
16. **D16 What's New source:**
    - (a) bundled `changelog.json` plus a remote refresh (recommended; works offline);
    - (b) remote only.

Per the brand doc, "Landing page" is a canvas deliverable. Present 2-3 visual directions before building.
