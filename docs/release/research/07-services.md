# 07 - Production services: analytics, crashes, feedback board, bug reports, remote content

Research date: 2026-10-17. Scope: the network-facing "services" layer for the App Store flavor of Segue (macOS 26, SwiftUI, Swift 6 strict concurrency, sandboxed, free app, solo US developer). Constraints: free tiers only, local-first, privacy-respecting, every service behind a Swift port, proprietary only when clearly strongest and an open-source escape hatch exists.

Pricing and limits below were read from live vendor pages on 2026-10-17 unless marked otherwise. **UNVERIFIED** marks anything I could not confirm on a primary source. Vendor free tiers move (TelemetryDeck cut its free tier on 2026-07-01), so re-check before committing.

Related sibling docs: `03-review-risk.md` (guideline 5.1.1/5.1.2 findings F11/F12/F14, consent options, label draft), `05-landing-page.md` (Cloudflare Pages on `segue.ryandsilva.dev` via a CNAME at Squarespace DNS, `/feedback` redirect, `changelog.json`), `08-polish-features.md` (Help menu, feedback form UX).

**Status:** the **Hosted-only stack** section directly below is current. Sections 0 to 9 are the original analysis. They recommended running our own Cloudflare backend, and that recommendation is **superseded** by Ryan's decision of 2026-10-17. Their vendor survey tables and Apple-rule findings still apply, and the hosted section relies on them.

---

## Hosted-only stack (Ryan's decision 2026-10-17)

Ryan's decision: "Hosted trusted vendors please, I don't want to run anything - there are things purpose built for this." So there is no backend of ours: no Cloudflare Workers, Pages Functions, D1 or R2. The static site stays; it is hosting, not a backend. His other answers:

- Bug reports should become GitHub issues in a private repo if a service can do that.
- Crash and hang diagnostics: auto-upload MetricKit payloads, with consent.
- Analytics: opt-in, asked once on first run, coarse country, raw events kept about 13 months or whatever the vendor offers.
- Feature board: optional email so voters hear when their request ships.

Everything below was re-verified on live pages on 2026-10-17.

### H.1 Recommended stack

| Job | Vendor (free tier) | Runner-up |
|---|---|---|
| Usage analytics | **TelemetryDeck** | PostHog Cloud free |
| Crashes, hangs, MetricKit upload | **Sentry** Developer plan, `sentry-cocoa` with `enableMetricKit` | Apple Organizer only (no upload) |
| In-app bug report with attachments | **Sentry User Feedback** (same SDK and account as crashes) | **Make.com free** webhook: creates a GitHub issue and commits the attachments to the private repo |
| Feature board, roadmap, changelog, voter emails | **Featurebase Free**, linked from the app and site via `segue.ryandsilva.dev/feedback` (a redirect on the static site) | Fider Cloud free (email magic-link voting); UserJot free (native macOS SDK, sign-in required) |
| Baseline installs, sessions, crashes | **App Store Connect App Analytics + Xcode Organizer** (Apple, no SDK) | - |
| What's New, announcements, remote flags | **Bundled release notes + static JSON on the existing site** (section 5 unchanged; no backend involved) | - |

That makes three external vendors (TelemetryDeck, Sentry, Featurebase) plus Apple, or four if Ryan adds Make to get automatic GitHub issues.

**Direct answer on GitHub issues.** No purpose-built service on a free tier turns an in-app report with attachments into an issue in a private GitHub repo:

- Sentry's GitHub integration needs Team or higher for manual issue creation and Business or higher for automatic creation.
- Featurebase integrations start at Growth.
- Canny's GitHub integration is Pro.
- BugSnag's issue-tracker sync is a paid tier.
- Gleap, Luciq (Instabug), Marker.io and Feedbucket have no free plan.
- Shake is iOS-only.
- Userback locks feedback after 7 days on free.

Citations are in H.2. Only general automation glue can do it on free: Make.com free supports webhooks, while Zapier free does not. So the choice is between:

- **(a) Sentry User Feedback, triaged by hand into GitHub** (recommended). It is purpose-built, has the attachments, and links each report to its crash. The catch: reports **expire after 30 days**, and the GitHub issue is a manual copy.
- **(b) The app posts to a Make webhook**, which creates the GitHub issue and commits the files under `reports/<id>/` in the private repo. It is automatic and permanent, at the cost of one more vendor and generic glue.

### H.2 Bug report to GitHub issue: candidates

| Candidate | Free tier | In-app report + attachments (log, MetricKit JSON, song file) | GitHub issue on free | macOS | Verdict |
|---|---|---|---|---|---|
| **Sentry User Feedback** | Developer plan: User Feedback on all plans, 1 GB attachments, **30-day lookback**, 1 user; "Third-party integrations: No" on Developer (https://sentry.io/pricing/) | Yes: `SentrySDK.capture(feedback: SentryFeedback(message:name:email:source:associatedEventId:attachments:))` takes `[Attachment]`. Build our own SwiftUI form on macOS (https://docs.sentry.io/platforms/apple/guides/macos/user-feedback/). | **No.** "Manual issue management is available to organizations on Team, Business, or Enterprise plans"; "Automatic issue management is available to organizations on Business or Enterprise plans" (https://docs.sentry.io/organization/integrations/source-code-mgmt/github/). Developer plan alerts are email only. | Yes | **Adopt (recommended).** |
| **Make.com** | Free: 1,000 credits/month, 2 active scenarios, instant webhook triggers, 5 MB file limit (third-party summaries of https://www.make.com/en/pricing, which does not print free limits: **UNVERIFIED** on the live page) | Yes: the app POSTs JSON + files to the webhook | **Yes:** GitHub "Create an issue" plus "Create a file" for the attachments (contents API), 3-5 credits per report, so roughly 200-300 reports/month | n/a (HTTP) | **Runner-up / optional bridge.** The webhook URL ships inside the app binary; treat it as public and keep the GitHub connection scoped to one private repo. |
| Zapier | Free: 100 tasks/month, two-step Zaps, **no webhooks**, 15-minute polling (https://zapier.com/pricing) | Only via email triggers | Yes but clumsy | n/a | Reject. |
| Featurebase | Free: integrations and "API, MCP, Webhooks" are **Growth ($29/seat/month)** (pricing page text, https://www.featurebase.app/pricing) | Web messenger/feedback widgets; no native macOS SDK found | No | Web only | Reject for bug reports. |
| Canny | Free: 25 tracked users; GitHub is Pro (https://canny.io/pricing) | Board posts, public | No | Web | Reject. |
| Sleekplan | Help page says GitHub "is available on every Sleekplan plan" and can "create a new issue straight from a post" (manual) (https://sleekplan.com/help/integrations/github), but the pricing table lists "Standard integrations (Intercom, GitHub, Slack, Zapier, Jira...)" from Starter (https://sleekplan.com/pricing): **conflicting, UNVERIFIED** | Posts are public; no diagnostic attachments | Manual at best | Web | Reject (a public board is the wrong place for diagnostics). |
| BugSnag | Free: 7.5k events, 7-day retention, 1 user; "Two-way issue tracker sync" only on Select/Preferred (https://www.bugsnag.com/pricing/) | No user-feedback API with file attachments | Paid | Yes | Reject. |
| Luciq (ex-Instabug) | No free plan (Capterra listing, https://www.capterra.com/p/166279/Instabug/pricing/) | Yes | Paid | Mobile-first | Reject. |
| Shake | Free: 20 bug reports/month, 1-month retention, "limited integrations" (https://www.shakebugs.com/pricing/) | Yes | **UNVERIFIED** | **No:** `shakebugs/shake-ios` Package.swift declares iOS only | Reject. |
| Gleap (gleap.ai) | No free plan; 7-day trial; GitHub on Team and above (https://www.gleap.ai/pricing) | Yes | Paid | **UNVERIFIED** | Reject. |
| Userback | Free: 2 sites, 2 seats, feedback "locked" after 7 days; Mobile SDK only on Business Plus ($159/month) (https://userback.io/pricing/) | Web | Not listed | No | Reject. |
| Marker.io | No free plan (from $39/month) (https://marker.io/pricing) | Web only | Paid | No | Reject. |
| Feedbucket | No free plan (from $49/month); website annotation tool (https://www.feedbucket.app/pricing/) | Web only | Paid | No | Reject. |

Email (`NSSharingService` compose with attachments to `segue@ryandsilva.dev`) stays as the offline / no-consent fallback (section 4.2).

### H.3 Crash, hang and MetricKit upload: Sentry

- **macOS + MetricKit:** `sentry-cocoa` defines `SENTRY_HAS_METRIC_KIT` for iOS, macOS and visionOS. `enableMetricKit` sends `MXHangDiagnostic`, `MXCPUExceptionDiagnostic` and `MXDiskWriteExceptionDiagnostic` events on macOS 12+, where MetricKit delivers immediately. `enableMetricKitRawPayload` attaches the raw `MXDiagnosticPayload` JSON (SDK 8.29.0+) (https://docs.sentry.io/platforms/apple/guides/macos/configuration/metric-kit/; source `Sources/Swift/Options.swift`). In SDK 9.x `enableMetricKit` defaults to `false`, so set it to `true`; the in-source v10 notes switch the default to `true` and deprecate Sentry's own app-hang tracker in favour of MetricKit. Crashes themselves come from Sentry's in-process handler, and the MetricKit crash path is gated separately (`enabledDiagnostics`).
- **Swift 6 / SwiftPM:** MIT; `Package.swift` uses swift-tools 6.0 with `Package@swift-6.1.swift` / `6.2` variants. Its own sources compile in Swift 5 language mode, which is fine to consume from a Swift 6 app target. The changelog has Swift 6 fixes ("Concurrency crash with Swift 6", Sendable `SentryId`). macOS 12+. Latest 9.30.2 (2026-10-14). https://github.com/getsentry/sentry-cocoa
- **Free tier:** 5k errors/month, 30-day lookback, 1 user, 1 GB attachments, email alerts only (https://sentry.io/pricing/). MetricKit hang and CPU events count as errors; drop low-value ones in `beforeSend` (Sentry's own docs note some MetricKit stacks have "only ... a couple of frames").
- **Consent:** start the SDK only after opt-in (or `SentrySDK.close()` on withdrawal). Use the same first-run consent as analytics, or a separate "Send crash reports" toggle (decision H.7-3).
- **Identifier:** SDK 9.x sets `user.id` to a per-install `installationId` when no user is set (`TelemetryScopeApplier.swift`). Either declare Device ID (not linked) or set a constant placeholder user so no per-install ID is sent. Also turn on the project setting that prevents storing IP addresses, and keep `sendDefaultPii = false`.
- **dSYMs:** upload with `sentry-cli debug-files upload` after archiving. The Sentry auth token lives in Ryan's keychain or a CI secret, never in the repo.
- Escape hatch if Sentry changes terms: the same SDK can point at GlitchTip (hosted free tier 1,000 events/month) by changing the DSN.

### H.4 Analytics: TelemetryDeck vs Aptabase Cloud vs PostHog Cloud

| | TelemetryDeck | Aptabase Cloud | PostHog Cloud |
|---|---|---|---|
| Free volume | **50k events/month** for accounts created after 2026-07-01 (https://telemetrydeck.com/blog/pricing-update-2026/) | 20k events/month (https://aptabase.com/pricing) | **1M events/month**, 1 project (posthog.com/pricing) |
| Retention / cohorts / funnels | Retention queries, funnels, cohorts (TQL `retention`; https://telemetrydeck.com/docs/tql/query) | **No retention:** the daily-rotating hash means no cross-day users (https://aptabase.com/docs/apple-app-privacy) | Retention, funnels, cohorts; needs the persisted anonymous `distinct_id` |
| Country | From the first three IP octets, IP never stored; documented for the web SDK, **UNVERIFIED** for the Swift SDK (which also sends the device's region setting) (https://telemetrydeck.com/docs/guides/web-setup/) | From IP, IP not stored | GeoIP from IP (can be disabled) |
| Raw-event retention vs Ryan's 13 months | **UNVERIFIED** (not published; pricing is in the JS dashboard) | Up to 5 years | **1 year on free**: a 1-month shortfall against 13 |
| Swift SDK | MIT, swift-tools 5.9 with `StrictConcurrency` enabled, macOS 10.13+, 2.14.2 (2026-08-01) | MIT, swift-tools 5.7, `actor` dispatcher, 0.3.12 (2026-10-01) after a two-year gap | swift-tools 5.3, macOS 10.15+, bundles a PLCrashReporter fork, very active |
| Label | Product Interaction + Device ID (its `PrivacyInfo.xcprivacy`); plus Coarse Location if country is used. Not linked, not tracking. | Product Interaction + Coarse Location | Product Interaction + Device ID + Coarse Location |
| Hosting | EU, proprietary | EU or US; AGPL self-host escape hatch | US or EU; MIT self-host |

**Pick: TelemetryDeck.** It is the purpose-built, Apple-first, privacy-first option. It is the only one of the three whose Swift SDK compiles with strict concurrency checking enabled, it covers retention and funnels, and it documents the App Store label. **Mismatches to accept:**

1. The free cap is 50k events/month. With a lean event set (about 10-15 events per user per month), that is roughly 3k-5k opted-in monthly users.
2. Free-tier data retention is not published (**UNVERIFIED** against Ryan's 13 months).
3. App-side country derivation is **UNVERIFIED**.

The SDK sends about 40 default parameters per signal (time zone, screen size, locale, accessibility settings). Review them against the minimization rule and the privacy policy.

**Runner-up: PostHog Cloud free.** It has 20 times the volume and confirmed GeoIP, but 1-year retention, a heavier SDK, and a person/ID model that is more than Segue needs.

The `TelemetrySink` port and the closed event enum from section 1.3 stay; only the adapter changes.

### H.5 Feature board: free hosted tiers ranked

| Rank | Tool | Free tier | No-account voting | Moderation | Roadmap / changelog | Voter email on status change | GitHub on free | Widget / SDK | Custom domain on free |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **Featurebase Free** | 1 seat, 1 board, 1 roadmap, unlimited posts, 100 changelog emails/month (https://www.featurebase.app/pricing; https://formbricks.com/blog/featurebase-pricing) | Yes: "No log-in posting, upvoting, and commenting" settings; guests "will not be notified about anything" (https://help.featurebase.app/articles/0480699-no-log-in-posting-upvoting-and-commenting). Free-plan availability **UNVERIFIED**. | Post/comment approval queue (https://help.featurebase.app/articles/6982593-post-and-comment-moderation); free-plan availability **UNVERIFIED** | Both | Yes, for signed-in voters (email sign-up is the optional-email path) | No (Growth) | Web widgets; no native macOS SDK; open via link | No; branding removal is a $69/month add-on |
| 2 | **Fider Cloud** | 250 feedback items; Pro $25 adds moderation (https://www.fider.io/pricing) | No; but sign-in is an **email magic link** (low friction) | No (Pro) | Statuses only; changelog **UNVERIFIED** | Yes (subscribers) | **UNVERIFIED** | Web link | **UNVERIFIED** |
| 3 | **UserJot Free** | Unlimited users and posts, 2 boards, roadmap + changelog (https://userjot.com/pricing) | **No:** guest posting from Starter ($29) | No (Starter) | Both | **UNVERIFIED** | Not listed | **Native SDK** `UserJot/userjot-ios` (MIT, swift-tools 6.1, macOS 12+, 2 stars) | No (Starter) |
| 4 | **Sleekplan Indie** | Unlimited feedback and subscribers, single admin (https://sleekplan.com/pricing) | Anonymous toggle exists (https://sleekplan.com/help/portal-widget/access-privacy); plan **UNVERIFIED** | No (Business) | Changelog yes; roadmap row conflicting | Subscribers notified (**UNVERIFIED** detail) | Conflicting (see H.2) | JS widget | No (Business $38) |
| 5 | Canny Free | 25 tracked users; past that, auto-upgrade or tracking of new users stops (https://canny.io/pricing) | No | Basic | Roadmap; changelog Pro | **UNVERIFIED** | No (Pro) | Widget | No |
| - | Nolt, Frill ($25), Upvoty ($15), FeedBear (Lite $19), Feedbucket ($49, website annotation, not a board) | **No free plan** (https://frill.co/pricing, https://upvoty.com/pricing/, https://www.feedbear.com/pricing, https://www.feedbucket.app/pricing/; Nolt from third-party sources) | | | | | | | |

Also found:

- **Features.Vote** has a native SwiftUI SDK for macOS 13+ and anonymous voting, but no free plan (Lite $9/month, https://features.vote/pricing).
- **AvdLee/Roadmap** (MIT, swift-tools 6.0, macOS 14+, 982 stars) is a native in-app roadmap with anonymous votes, backed by the free Sidetrack Roadmap service. It is curated items only (users vote but cannot submit). Sidetrack's limits and operator are **UNVERIFIED**. It is a possible in-app complement, not the board.
- **Quackback Cloud** free is capped at 50 posts.

**Recommendation: Featurebase Free**, reached at `segue.ryandsilva.dev/feedback` (a redirect on the static site) from the Help menu and the site:

- **Voting:** anonymous voting on. People who want "it shipped" emails sign up with an email, which covers Ryan's optional-email requirement.
- **Moderation:** turn on the approval queue.
- **GitHub:** none on free. Ryan moves a request to Shipped by hand, which emails the signed-in voters.
- **Before committing:** sign up and confirm that guest voting and moderation are on the Free plan (**UNVERIFIED**). If either is missing, fall back to Fider Cloud.

### H.6 Final stack: free limits, label impact, manual setup

| Vendor | Free limits that matter | Privacy-label data types it adds (all Not Linked, not Tracking) |
|---|---|---|
| Apple App Analytics / Organizer | Opt-in users only; rows under 5 users omitted | None (Apple-collected) |
| TelemetryDeck | 50k events/month; retention **UNVERIFIED** | Usage Data > Product Interaction; Identifiers > Device ID; Location > Coarse Location (country) |
| Sentry (crashes + MetricKit + user feedback) | 5k errors/month, 30-day lookback, 1 user, 1 GB attachments, email alerts only | Diagnostics > Crash Data, Performance Data, Other Diagnostic Data; User Content > Customer Support (report text); Other User Content (attached song file); Contact Info > Email Address if a reply-to is given; Identifiers > Device ID unless the default `installationId` user is suppressed |
| Featurebase (web link, browser) | 1 board, 1 seat, 100 changelog emails/month | **None for the app**: the board is a website opened in the browser, not collected through the app. Cover it in the privacy policy and on `/terms`. |
| Make (only if chosen) | 1,000 credits/month, 2 scenarios | Same types as the bug report (it receives the same payload) |

Net delta against the self-hosted plan in section 6: **adds Identifiers > Device ID** (TelemetryDeck; Sentry unless suppressed) and **Coarse Location** (country, which Ryan now wants). It drops the voter-token question, because the board is now a website. "Data Not Linked to You" and "not used for tracking" still hold. The privacy policy must name TelemetryDeck, Sentry and Featurebase (plus Make if used) as processors that give equal protection (5.1.1(i)).

**What Ryan sets up by hand:**

1. **TelemetryDeck:** create an account and an app; copy the App ID (not secret) into the build config.
2. **Sentry:** create an organization (choose EU or US region) and a macOS project; copy the DSN; turn on "Prevent Storing of IP Addresses"; create an auth token for `sentry-cli` dSYM uploads and keep it in the keychain or CI secrets; set email alert rules for new issues and new feedback.
3. **Featurebase:** create the workspace and one board; turn on guest upvoting/posting and post moderation (confirm both work on Free); set the statuses; add the `/feedback` redirect to the site.
4. **GitHub:** create the private `segue-reports` repo. If Make is chosen: create a Make account, a webhook scenario and a GitHub connection scoped to that one repo.
5. **App Store Connect:** fill in the privacy questionnaire per H.6; keep "Include symbols" on at upload.
6. **App:** add `com.apple.security.network.client` (F14 in `03`).

### H.7 Decisions still open

1. **Bug reports:** (a) Sentry User Feedback, with a weekly manual copy into GitHub; reports expire after 30 days (recommended); (b) add the Make bridge for automatic, permanent GitHub issues; (c) both: send to Sentry and also to Make.
2. **Analytics vendor:** (a) TelemetryDeck (recommended); (b) PostHog Cloud (1M events, 1-year retention); (c) research ticket: open a TelemetryDeck account and confirm free retention and app-side country first.
3. **Crash consent:** (a) one first-run consent covering analytics and crash/hang upload; (b) two toggles, asked once on one screen (recommended: crash reports are more valuable and some users will grant only those).
4. **Sentry install ID:** (a) suppress it with a constant user, no Device ID from Sentry (recommended); (b) keep it to count affected users, and declare Device ID.
5. **Board:** (a) Featurebase Free (recommended, after the sign-up check); (b) Fider Cloud; (c) UserJot with its native SDK (accepts sign-in to vote).

---

## 0. Summary (superseded 2026-10-17: see "Hosted-only stack" above)

| Area | Recommendation | Runner-up |
|---|---|---|
| Usage analytics | **Build our own ID-less telemetry** on Cloudflare Pages Functions + D1 (same origin as the landing site), with client-side cohort fields instead of a user ID. Opt-in. Plus Apple App Analytics (free, no SDK) as a baseline. | **TelemetryDeck** (adopt its MIT SDK as an adapter behind the same port) if Ryan wants dashboards on day one and accepts a Device ID label entry plus a proprietary EU processor. |
| Crash / error reporting | **Xcode Organizer + MetricKit** (free, Apple; MetricKit payloads kept locally and attached to bug reports, optionally uploaded under the same consent). No third-party crash SDK in v1. | **Sentry** Developer plan (5k errors/month, 30-day lookback, 1 user); GlitchTip/Bugsink as its open-source escape hatches. |
| Feature request board | **Build a tiny board** on the same Pages Functions + D1 backend: anonymous voting (no account), Turnstile on the web, moderation queue, native SwiftUI list in the app, web page at `segue.ryandsilva.dev/feedback`. | **Featurebase Free** or **Sleekplan Indie** (hosted, vendor subdomain, vendor branding) reached via the `/feedback` redirect. GitHub Discussions only if Ryan accepts the GitHub-login barrier. |
| In-app bug report | **POST to a Pages Function** that files an issue in a private GitHub repo (via a GitHub App) and stores attachments in R2; **fall back to `NSSharingService` email compose** when offline or the endpoint fails. User previews the payload; song file opt-in per report. | Email-only (`NSSharingService.composeEmail` with attachments; `mailto:` cannot attach). |
| What's New / remote config / announcements | **Yes, static JSON is enough.** Bundle release notes in the app for What's New (offline); fetch `changelog.json` / `announcements.json` / `config.json` from the static site with ETag, at most daily, never during a show. No vendor. | - |

The four recommendations share **one backend**: a Cloudflare Pages project (already chosen for the site in `05-landing-page.md`) whose Pages Functions bind one D1 database and one R2 bucket. Pages Functions run on the Pages custom domain, so no nameserver move to Cloudflare is needed (Workers custom domains and Email Routing would need one).

---

## 1. Usage analytics

### 1.1 What Ryan wants to learn, and what that implies technically

Active users (DAU/WAU/MAU), retention, feature usage (show started, song created, setlist created, transpose used, editor mode), app version and OS adoption, and funnels (install -> first song -> first setlist -> first show).

The load-bearing question is **retention**. Retention needs some way to know that today's activity came from an install that started in week W. There are two ways:

1. **A persistent pseudonymous install ID** sent with every event (TelemetryDeck, PostHog, Mixpanel, Amplitude, Firebase, Countly). The server computes cohorts. Cost: Apple label must declare an identifier (TelemetryDeck's own manifest declares `DeviceID`, not linked, not tracking), and under GDPR a persistent ID is pseudonymous personal data, not anonymous.
2. **No ID; the client computes the cohort fields itself.** Each event carries coarse, non-unique attributes the app derives locally: `installWeek` (ISO week of first launch), `daysSinceInstallBucket`, `appVersion`, `osMajor`. The app sends at most one `active.day` ping per local day, one `active.week`, one `active.month`, and once-per-install milestone events (`milestone.firstSong`, `milestone.firstSetlist`, `milestone.firstShow`). The server then counts: DAU = count of `active.day` for a date; retention for cohort W on day N = `active.day` pings with `installWeek = W` on that day / `install` pings for W; the activation funnel = milestone counts per cohort. No identifier ever leaves the device, so no cross-event linking is possible even by the operator.

**Aptabase is the cautionary example**: it has no persistent ID at all and rotates a server-side hash daily (`SHA(IP + UA + daily salt)`), which by design "makes it impossible ... to correlate sessions that happen throughout different days" (https://aptabase.com/docs/apple-app-privacy). So Aptabase cannot show retention. Option 2 above keeps Aptabase's privacy property and still yields cohort retention and funnels, because the client, not the server, does the joining.

Option 2 cannot do per-user path analysis (arbitrary funnels defined after the fact, "what did users who churned do"). For a solo app the fixed milestone funnel covers the stated goals.

### 1.2 Vendor survey

| Vendor | Free tier (verified 2026-10-17) | Swift / macOS SDK | Privacy model | Self-host | Export | Verdict |
|---|---|---|---|---|---|---|
| **TelemetryDeck** | New accounts: **50,000 events/month**; accounts created before 2026-07-01 keep 100,000 (https://telemetrydeck.com/blog/pricing-update-2026/). Paid from EUR 19/month (1.5M). Data retention on free: **UNVERIFIED** (pricing lives in a JS dashboard, https://dashboard.telemetrydeck.com/pricing-calculator). Behaviour at the free cap: **UNVERIFIED**. | `TelemetryDeck/SwiftSDK`, MIT, macOS 10.13+, swift-tools 5.9 with `StrictConcurrency` enabled; latest stable 2.14.2 (2026-08-01, fixed session-manager data races), 3.0.0-beta.5 (2026-08-31). Presets for errors, navigation, purchases, "pirate metrics". https://github.com/TelemetryDeck/SwiftSDK | Per-install UUID persisted in UserDefaults on macOS, SHA-256 hashed client-side (optional custom salt), re-salted and hashed server-side. Sends ~40 default parameters per signal (model, OS, locale, region, time zone, screen resolution, accessibility settings, calendar fields). Manifest declares Product Interaction + Device ID, not linked, not tracking. Claims no GDPR consent needed. | No (proprietary, EU) | TQL query API (async), JSON export of insights (https://telemetrydeck.com/docs/api/api-run-query/) | **Runner-up: adopt behind the port** if dashboards are wanted now. |
| **Aptabase** | Cloud **20,000 events/month**, unlimited apps; paid from $10/month (200k) (https://aptabase.com/pricing). Retention up to 5 years; EU (Germany) or US region; CSV export (https://aptabase.com/docs). | `aptabase/aptabase-swift`, MIT, swift-tools 5.7, `actor`-based dispatcher; 0.3.12 (2026-10-01) after a two-year gap since 0.3.11. Sends locale, OS version, device model; session ID = epoch seconds + random. | No device ID; server-side daily-rotating hash; label: Product Interaction + Coarse Location (country from IP), not linked (https://aptabase.com/docs/apple-app-privacy). | Yes, AGPL-3.0 server (Postgres + ClickHouse) | CSV | **Build informed by it** (no retention by design). Technique: daily-rotating salted hash for uniques, IP discarded after geolocation. |
| **PostHog** | **1M events/month**, 100k exceptions, 5k recordings, 1M flag requests, 1,500 survey responses; free plan is **1 project, 1-year retention**; card only above free (posthog.com/pricing, read 2026-10-17). | `PostHog/posthog-ios`, swift-tools 5.3, macOS 10.15+, bundles a PLCrashReporter fork for macOS crash capture; error tracking is behind `@_spi(Experimental)` (https://posthog.com/docs/error-tracking/installation/ios). Very active (3.92.0, 2026-10-10). | Anonymous distinct ID persisted; person profiles optional; GeoIP. Label: Product Interaction, Device ID, Coarse Location, Crash Data if used. | Yes (MIT core, "hobby" Docker deploy; heavy: ClickHouse, Kafka) | Batch exports, API | **Build informed by it.** Strongest free feature set, but a large US-cloud SDK and person model is more than Segue needs. Technique: per-product billing caps; `identified_only` person profiles so anonymous events stay cheap. |
| **Firebase / Google Analytics for Firebase** | Free (Spark). Analytics supports macOS since 8.9.0 (https://firebase.google.com/docs/ios/learn-more). | Closed-source `GoogleAppMeasurement` binary for Analytics; Crashlytics open source. | App instance ID, coarse location from masked IP, Google data-sharing settings; label: Device ID, Product Interaction, Coarse Location (https://support.google.com/analytics/answer/10285841). | No | BigQuery export | **Reject.** Poor fit: Google as processor contradicts the privacy pitch, closed binary in a "no third-party SDK" app, ad-ecosystem defaults to turn off, no escape hatch with the same semantics. Technique: none worth keeping beyond "Remote Config with conditions", which a static JSON covers. |
| **Countly** | No free cloud: Flex from $175/month, 14-day trial (https://countly.com/pricing). "Countly Lite" self-host free. | `countly-sdk-ios` MIT, macOS 10.14+, active (26.1.4). | Device ID based. | Yes (Lite; server licence shows as custom on GitHub, **UNVERIFIED** exact terms) | Yes | **Reject** (no free hosting; self-host needs a server). |
| **OpenPanel** | **No free cloud tier** (30-day trial; from $2.50/month for 5k events) (https://openpanel.dev/pricing). | Swift SDK `Openpanel-dev/swift-sdk` is **AGPL-3.0**, 5 stars. AGPL code inside a closed App Store binary is a licence problem. | Cookieless web-style. | Yes, AGPL, free unlimited | Yes | **Build informed by it.** Technique: one product for web + app events. |
| **Amplitude** | Starter **2M events/month**, free forever, **1-year data**, no behavioral cohorts (https://amplitude.com/pricing). | Amplitude-Swift supports macOS (**UNVERIFIED** Swift 6 status). | Device ID + IP geolocation; marketing/ad-adjacent product. | No | Export API on free **UNVERIFIED** | **Reject.** Free is generous but the privacy posture and label (Device ID, Coarse Location) are worse than needed. |
| **Mixpanel** | **1M events/month**, funnels + retention, 5 saved reports per seat (https://mixpanel.com/pricing/). | mixpanel-swift supports macOS (**UNVERIFIED** Swift 6 status). | Distinct ID + IP geolocation. | No | Raw export API on free **UNVERIFIED** | **Reject** (same reasons as Amplitude). |
| **Apple App Analytics** (App Store Connect) | Free, no SDK. Sessions, installations/deletions, crashes, opt-in rate; rows under 5 users/devices omitted; noise added; complete after 2 days (https://developer.apple.com/help/app-store-connect-analytics/overview/analytics-reports-api). Analytics Reports API exports `.txt.gz`. | None needed. | Only users who opted in to "Share with App Developers"; Apple-collected, so **no label impact** ("You are not responsible for disclosing data collected by Apple", https://developer.apple.com/app-store/app-privacy-details/). | n/a | Analytics Reports API | **Adopt** as the free baseline (downloads, sessions, crashes, version mix). No custom events, so it cannot answer feature-usage questions. Retention cohorts for macOS apps: **UNVERIFIED**. |
| **Plausible** (web) | No free cloud; from $9/month, 30-day trial; Community Edition self-host AGPL (third-party summaries; plausible.io did not resolve from this machine, **UNVERIFIED** on the live page). | Web only. | Cookieless. | Yes | Yes | **Reject** for the app; site analytics are `05-landing-page.md`'s call. |
| **Umami** (web) | Cloud Hobby **free: 100k events/month, 1 site, 6-month retention** (https://umami.is/pricing). MIT. | Web only (has an HTTP API an app could call). | Cookieless. | Yes (MIT) | Yes | **Reject for the app**; viable for the site if `05` wants web analytics. |
| Cloudflare Web Analytics / GoatCounter (web) | Both free; Cloudflare's works by JS beacon without proxying (https://developers.cloudflare.com/web-analytics/); GoatCounter free for "reasonable public usage" (https://www.goatcounter.com/). | Web only. | Cookieless. | GoatCounter yes | - | Site-only options; defer to `05`. |
| Matomo, Swetrix | Matomo iOS SDK MIT (v7.8.0, 2025-12-12), self-host only; Swetrix AGPL, web-first. | - | - | Yes | Yes | **Reject** (self-host server needed). |
| **Own: Cloudflare Pages Functions + D1** | Workers Free: **100,000 requests/day** shared by Workers and Pages Functions, 10 ms CPU per invocation (https://developers.cloudflare.com/workers/platform/pricing/, https://developers.cloudflare.com/pages/functions/pricing/). D1 Free: **5M rows read/day, 100k rows written/day, 5 GB** (https://developers.cloudflare.com/d1/platform/pricing/). Analytics Engine: 100k data points/day, 10k queries/day, **3-month retention**, currently not billed (https://developers.cloudflare.com/analytics/analytics-engine/pricing/, .../limits/). | Our own ~200-line Swift client (actor, Sendable value types, URLSession). | Whatever we design: ID-less (section 1.1 option 2). | It is self-hosted | SQL; D1 export | **Recommended: build from scratch, informed by Aptabase (no ID) and TelemetryDeck (event naming, presets).** |

### 1.3 Recommended design (own endpoint) - superseded

- **Endpoint:** `POST https://segue.ryandsilva.dev/api/v1/events` (Pages Function, same origin as the site, so no CORS and no extra DNS).
- **Batching:** the client queues events in memory and on disk (Application Support), flushes on app deactivate/quit and at most every 15 minutes; one request per flush. 100k requests/day therefore supports tens of thousands of daily sessions. Never flush during an active show (vision: "the live view never blocks on network").
- **Storage:** D1 table of **daily rollups**, not raw events: `(day, event, appVersion, osMajor, installWeek, value) -> count`, written with an UPSERT. One row write per distinct key per batch keeps well under 100k writes/day. D1 rather than Analytics Engine because AE keeps only 3 months and growth trends need years.
- **Event vocabulary is a closed Swift enum** (e.g. `case showStarted`, `case songCreated(source: SongSource)`, `case transposeUsed`), so free strings (titles, lyrics, paths) cannot be sent at all. This enforces finding F12 of `03-review-risk.md` by removing the capability rather than by review.
- **No identifier, no IP storage:** the function reads only the body; Cloudflare's request logs are not retained by us. Country (from `request.cf.country`) is optional; recommend **omitting it** so the label stays at Product Interaction only.
- **Dashboard, local-first:** a `make stats` script runs SQL via `wrangler d1 execute --remote` and renders a static local HTML report (DAU/WAU/MAU, cohort retention grid, funnel, version/OS adoption). No hosted admin surface to secure.
- **Port:** `protocol TelemetrySink: Sendable { func record(_ event: TelemetryEvent) async; func flush() async; func discardQueued() async }`. Adapters: `CloudflareTelemetrySink` (default), `TelemetryDeckSink` (runner-up, uses the MIT SDK or TelemetryDeck's ingest API v2, https://telemetrydeck.com/docs/ingest/v2), `NoopTelemetrySink` (consent off, tests). A `ConsentStore` gates construction: with consent off the app holds a `Noop` sink, so "no events before consent" holds structurally.

Cost of this choice: the dashboard and SQL are ours to write (a build session), and Ryan becomes the operator of a tiny endpoint. Benefit: free with no cap that a vendor can cut, no third-party processor to name in the privacy policy beyond Cloudflare (already the site host), and the smallest possible label.

### 1.4 App Store privacy label impact

| Choice | Data types to declare | Linked to you | Tracking |
|---|---|---|---|
| Apple App Analytics / Organizer only | Nothing ("Data Not Collected" still possible) | - | - |
| Own ID-less endpoint (recommended) | Usage Data > **Product Interaction** (purpose: Analytics). If country is kept: Location > **Coarse Location**. | No ("Data Not Linked to You") | No |
| TelemetryDeck (default SDK) | Usage Data > Product Interaction; Identifiers > **Device ID** (its own `PrivacyInfo.xcprivacy` declares both). TelemetryDeck's guide also lists Identifiers + Usage Data (https://telemetrydeck.com/docs/articles/apple-app-privacy/). | No | No |
| Aptabase | Product Interaction; Coarse Location (country) | No | No |
| PostHog / Mixpanel / Amplitude / Firebase | Product Interaction, Device ID, Coarse Location (+ Crash Data / Performance Data if their error products are on) | No by default; Yes if `identify()` is used | No (unless ad features are enabled) |

Consent does not remove a declaration: the label describes what the app can collect (see `03-review-risk.md` section 8.3). Once analytics ship, "Data Not Collected" is gone.

### 1.5 Opt-in or opt-out

- **Apple 5.1.1(ii)** (live text): "Apps that collect user or usage data must secure user consent for the collection, even if such data is considered to be anonymous at the time of or immediately following collection." It also requires an easy way to withdraw (https://developer.apple.com/app-store/review/guidelines/). This is the decisive constraint: anonymity is explicitly not an exemption.
- **Apple 5.1.2(i)** concerns personal data sharing and ATT for tracking; none of the recommended options track, so ATT is not needed.
- **GDPR**: a persistent hashed install ID (TelemetryDeck and every ID-based tool) is pseudonymous, which is still personal data; vendor claims that "no consent is needed" rely on an anonymity argument that regulators do not generally accept for persistent IDs. Separately, **ePrivacy Art. 5(3)** covers storing or reading information on the user's device, independent of whether it is personal data (EDPB Guidelines 2/2023 v2.0, adopted 2024-10-07, https://www.edpb.europa.eu/documents/guideline/guidelines-22023-on-technical-scope-of-art-53-of-eprivacy-directive_en); a persisted analytics UUID falls in it. France's CNIL allows an opt-out regime for strictly first-party audience measurement under conditions (inform, allow objection, single publisher, IP truncation, identifier lifetime at most 13 months) (https://www.cnil.fr/en/sheet-ndeg16-use-analytics-your-websites-and-applications), but that is one regulator's exemption and does not answer Apple's 5.1.1(ii).
- **Is anonymous telemetry without consent defensible?** Legally, an ID-less design like 1.3 is about as defensible as it gets under GDPR. Under Apple's rules it is not: the guideline text names anonymous data. A reviewer can cite it.

**Recommendation: opt-in.** A first-run choice with two equal buttons ("Share anonymous usage" / "Don't share"), the same toggle in Settings > Privacy, effective immediately and dropping the queue on withdrawal; nothing sent before the choice. This matches `03-review-risk.md` F11. Expect a reduced sample (opt-in rates are **UNVERIFIED**; plan for well under half), which is another reason to keep Apple App Analytics as the unbiased baseline for installs and sessions.

---

## 2. Crash and error reporting

| Option | Free tier (verified) | macOS / Swift | Label | Verdict |
|---|---|---|---|---|
| **Xcode Organizer** (App Store crash reports) | Free | Mac App Store apps; only users who share analytics with developers (https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs). Symbolicated by Apple when the build is uploaded with symbols. | None (Apple-collected) | **Adopt.** |
| **MetricKit** (`MXDiagnosticPayload`: crash, hang, CPU exception, disk-write, launch diagnostics) | Free | macOS 12+ for diagnostics (https://developer.apple.com/documentation/metrickit/mxdiagnosticpayload). Delivered to the app itself. Whether delivery depends on the user's "Share with App Developers" setting is disputed: an Apple forums thread says it does not (https://developer.apple.com/forums/thread/733806) - **UNVERIFIED**. | None while payloads stay on device; **Crash Data / Performance Data / Other Diagnostic Data** if the app uploads them ("If you collect data about your app from Apple frameworks ... you should indicate what data you collect") | **Adopt:** persist the last N payloads locally; attach to bug reports; optional automatic upload under the analytics consent. |
| **Sentry** | Developer: **5k errors/month, 1 user, 30-day lookback**, 5M spans, 50 replays, 1 GB attachments, unlimited projects (https://sentry.io/pricing/). No non-commercial clause found. | `sentry-cocoa` MIT, swift-tools 6.0 (language mode 5), macOS 12+, v9.30.2 (2026-10-14). Needs `network.client`. Server is FSL-1.1 (Apache-2.0 future licence); self-hosted is heavy. | Crash Data, Performance Data, Other Diagnostic Data; plus Device ID if the install ID is sent | **Runner-up** (adopt only if MetricKit proves too thin). |
| **GlitchTip** | Hosted free **1,000 events/month** (https://glitchtip.com/pricing); open source, Sentry-protocol compatible | Uses the Sentry SDK | Same as Sentry | **Fork or vendor (escape hatch)** for a Sentry adapter: same SDK, self-hostable. |
| **Bugsink** | Self-host only (repo `bugsink/bugsink`, custom licence, 2.1k stars, active) | Sentry SDK compatible | Same | Escape hatch; build informed by it (single-process Sentry-compatible ingest). |
| **BugSnag** (SmartBear) | Free: **7.5k events/month, 1M spans, 1 user, 7-day retention** (https://www.bugsnag.com/pricing/) | `bugsnag-cocoa` MIT, active (v6.38.1) | Crash Data etc. | **Reject** (7-day retention; no reason over Sentry). |
| **Embrace** | Free: **1M sessions/year, 3-day event retention, 5 users** (https://embrace.io/pricing/) | `embrace-apple-sdk` Apache-2.0, macOS 13+, OpenTelemetry-based, 7.0.0 (2026-10-16) | Crash Data, Performance, Device ID | **Build informed by it.** Technique: OpenTelemetry as the wire format, so the backend is swappable. 3-day retention rules it out. |
| **TelemetryDeck errors preset** | Counts toward event quota | `TelemetryDeck+Errors.swift` (error category + ID as signals) | Product Interaction / Other Diagnostic Data | **Build informed by it.** Technique: report *handled* errors as typed, ID'd events (`IdentifiableError`) without stack traces, so error rates show up in normal analytics. Our closed event enum can carry `errorOccurred(ErrorCode)`. |
| PostHog error tracking | 100k exceptions/month | Experimental SPI; PLCrashReporter fork | Crash Data | Reject for crashes (experimental). |
| KSCrash / PLCrashReporter | Free, MIT | KSCrash 2.6.0 (2026-08-08), very active; PLCrashReporter 1.12.2 (2025-11-12) | If uploaded: Crash Data | **Build informed by it** only if MetricKit is insufficient: in-process crash capture written to the container, sent next launch. |

### 2.1 Symbols (dSYM)

- **Organizer:** keep "Include symbols" on when uploading to App Store Connect; Apple then symbolicates Organizer crash reports. Keep the `.xcarchive` per release.
- **MetricKit:** call stacks arrive unsymbolicated (binary UUID + offsets). Keep each release's dSYMs (archive them per version, e.g. as an asset on a private GitHub release, free) and symbolicate with `atos` in a small script. Store the build UUID in each bug report so the right dSYM is found.
- **Sentry (if adopted):** upload dSYMs with `sentry-cli` in a post-archive step; the auth token lives on the host, never in the repo or an agent sandbox.

### 2.2 Recommendation

Organizer + MetricKit, with a `CrashDiagnosticsSource` port (`MetricKitDiagnosticsSource` adapter; a `SentryDiagnosticsSource` adapter later if needed). The "Report a Bug" form attaches the most recent MetricKit diagnostics, which closes the main gap (Organizer only sees opt-in users and lags by days). Handled errors go through the analytics enum as typed codes.

---

## 3. Feature request board with upvotes

### 3.1 Requirements

Free; custom domain or same-origin page under `segue.ryandsilva.dev`; voting **without an account** (musicians, not developers); spam control; roadmap/status view; changelog link; data export; embeddable in the site and reachable from the app.

### 3.2 Survey

| Tool | Free tier (verified 2026-10-17) | Custom domain on free | Voter auth | Branding | Roadmap / changelog | Moderation / spam | Export | Verdict |
|---|---|---|---|---|---|---|---|---|
| **Canny** | Free: **25 tracked users**, unlimited boards; changelog, private boards, branding removal excluded (https://canny.io/pricing) | No | Account / SSO | Canny branding | Roadmap yes, changelog paid | Basic | **UNVERIFIED** on free | **Build informed by it.** 25 tracked users is unusable. Technique: merge duplicates while carrying votes over; notify voters on status change. |
| **Featurebase** | Free: 1 seat, 1 feedback board, 1 roadmap, 50 help articles; no custom domain, no integrations (https://www.featurebase.app/pricing; free-plan details via https://formbricks.com/blog/featurebase-pricing, partially **UNVERIFIED**) | No (Growth plan) | Account; guest voting on free **UNVERIFIED** | Featurebase branding | Roadmap yes; changelog on free **UNVERIFIED** | **UNVERIFIED** | **UNVERIFIED** | **Hosted runner-up.** |
| **Nolt** | No free plan; from ~$25-29/month (third-party sources; nolt.io returned 403, **UNVERIFIED**) | Paid | - | - | - | - | - | Reject. |
| **UserJot** | Free: unlimited users and posts, **2 boards**, public roadmap and changelog; no custom domain; **no guest posting** (https://userjot.com/pricing) | No | Sign-in required on free | UserJot branding | Both | **UNVERIFIED** | **UNVERIFIED** | Reject (sign-in barrier). |
| **Fider** (OSS) | Cloud free: **250 feedback items** fair use; content moderation is Pro ($25/month) (https://www.fider.io/pricing). Self-host: AGPL-3.0, Go + Postgres, v0.38.2 (2026-10-05) | Free-plan custom domain **UNVERIFIED** | Sign-in by **email magic link** or OAuth (Google, GitHub, Facebook, custom) (https://fider.io/blog/version-0.6.0, https://docs.fider.io/configuring-oauth); anonymous voting not offered (**UNVERIFIED**) | Fider branding on cloud | Statuses as roadmap | Moderation paid on cloud | Self-host: yes | **Build informed by it.** Technique: email magic-link as the optional, low-friction identity for people who want status notifications. Self-hosting needs a server with Postgres, which no free host gives reliably. |
| **LogChimp** (OSS) | Self-host; v0.9.2 (2026-09-05), pre-1.0; licence is custom with an `ee/` directory under a separate licence (https://github.com/logchimp/logchimp) | n/a | Accounts | - | Roadmap | Roles | Yes | Reject (pre-1.0, open-core, needs Postgres host). |
| **Astuto** (OSS) | **Archived on GitHub (2026-01-09)** (https://github.com/astuto/astuto) | - | - | - | - | - | - | Reject (dead). Keep as reference: Rails app with optional anonymous feedback behind approval (**UNVERIFIED**). |
| **Quackback** (OSS, new: repo created 2025-12-02) | Cloud free: 1 seat, **1 board, 50 posts**, roadmap + changelog; no custom domain, no API/export on free (https://quackback.io/pricing). Self-host: AGPL-3.0, every feature, Docker with Postgres + S3 (https://github.com/QuackbackIO/quackback). Has an iOS SDK (`QuackbackIO/quackback-ios`, 2 stars). | No | **UNVERIFIED** | Branding removal paid ($59/month add-on) | Both | **UNVERIFIED** | Self-host only | **Build informed by it.** Technique: one widget for feedback + changelog + help, with a native mobile SDK. Too young and its free cloud is capped at 50 posts. |
| **ClearFlask** (OSS) | Self-host open-source tier Apache-2.0 with a **100-post** limit; cloud $29/month (https://clearflask.com/pricing) | Paid | **UNVERIFIED** | - | Roadmap | - | - | Reject. Technique: "credits" voting (users spend a budget of votes), which counters vote inflation. |
| **Frill** | No free plan; Startup $25/month, 50 ideas (https://frill.co/pricing) | Paid | Anonymous auth exists (tier **UNVERIFIED**) | - | - | - | - | Reject. |
| **Upvoty** | No free plan; Power $15/month (https://upvoty.com/pricing/) | Paid | **UNVERIFIED** | - | - | - | - | Reject. |
| **Sleekplan** | Indie **free**: unlimited feedback and subscribers, board, changelog, single admin; custom domain and branding removal from Business $38/month; roadmap tier conflicting between sources (**UNVERIFIED**) (https://sleekplan.com/pricing) | No | **Anonymous vote/post/comment toggle exists** ("Let people vote, post, and comment without giving an email address at all", https://sleekplan.com/help/portal-widget/access-privacy); which plan has it: **UNVERIFIED** | Sleekplan branding | Changelog yes | **UNVERIFIED** | **UNVERIFIED** | **Hosted runner-up (tie with Featurebase)** if anonymous voting is confirmed on Indie. |
| **Productboard portal** | No free plan; Business/Enterprise by demo only (https://www.productboard.com/pricing/) | - | - | - | - | - | - | Reject. |
| **FeatureOS** (ex-Hellonext) | No free plan; from $60/month, 30-day trial (https://featureos.com/pricing) | - | - | - | - | - | - | Reject. |
| **GitHub Discussions** (separate public `segue-feedback` repo) | Free | n/a (github.com URL) | **GitHub account required** to post or upvote | GitHub | Upvote + "sort by top", Announcements and Polls categories (https://docs.github.com/en/discussions) | GitHub moderation tools, lock, hide, block | GraphQL API | **Build informed by it.** Zero-ops and permanent, but the GitHub login is a real barrier for musicians. Viable only as a stopgap. |
| **GitHub Issues + reactions** | Free | n/a | GitHub account | GitHub | Labels / Projects | Good | API | Reject (worse UX than Discussions for voting). |
| **Own board on Pages Functions + D1** | Shares the 100k req/day and D1 quotas above; Turnstile free, unlimited challenges, up to 20 widgets (https://developers.cloudflare.com/turnstile/plans/) | **Same origin**: `segue.ryandsilva.dev/feedback`; no CNAME, no TLS question | Anonymous: Turnstile + per-browser voter token on web; per-install random voter token in the app (stored in the app container, used only for voting); optional email for "notify me" | Ours | Status field drives a roadmap view; shipped items link to `changelog.json` entries | New posts held for approval; rate limits per IP hash per day in D1; vote dedupe by voter token | SQL / JSON | **Recommended: build from scratch, informed by Canny (merge + notify), Fider (magic link), Sleekplan (anonymous toggle), ClearFlask (vote budget).** |

No hosted free tier meets "custom domain + anonymous voting + no vendor branding" together. The hosted options all leave a vendor subdomain, vendor branding, and (except possibly Sleekplan) an account requirement.

### 3.3 Recommended design (own board) - superseded

- **Data:** `posts(id ULID, title, body, status [pending|open|planned|in_progress|shipped|declined|merged], mergedInto, createdAt, voteCount)`, `votes(postId, voterHash, createdAt)` with a unique key. `voterHash` = SHA-256 of the client's random voter token with a server-side pepper; the raw token is never stored.
- **Web:** static HTML/JS page in the site that calls `/api/v1/board`; Turnstile on post and vote.
- **App:** a native SwiftUI list (top requests, vote button, "Suggest a feature" form) calling the same JSON API, rather than a `WKWebView`. That gives the native feel the brand asks for, works with the sandbox's `network.client` entitlement, and needs no web view. Turnstile cannot run natively; the in-app path relies on rate limits and moderation instead (App Attest is not available on macOS: `DCAppAttestService.isSupported` returns false on Macs, https://developer.apple.com/forums/thread/682488).
- **Moderation:** everything new is `pending` until Ryan approves it; admin actions via a local script (`make board-admin`, using `wrangler d1 execute`) or a bearer-token admin route. No public admin page to secure.
- **Ports:** the app only needs a `FeedbackBoardClient` port if the in-app native list is built. If the app only opens a URL, **no port**, just a configured URL (`/feedback`), which per `05-landing-page.md` can redirect to any vendor. That keeps a vendor swap app-update-free.
- **Label impact:** posts are user-typed content sent deliberately. Apple's optional-disclosure rule covers "optional feedback forms or customer service requests that are unrelated to the primary purpose of the app" only when all criteria hold, including that "the user's name or account name is prominently displayed in the submission form" (https://developer.apple.com/app-store/app-privacy-details/). An anonymous board form does not display a name, so declare **User Content > Other User Content** (and **Contact Info > Email Address** if the optional notify-me email is collected), not linked, not tracking. The voter token is a per-app random value used only for dedupe; declaring **Identifiers > Device ID** for it is the conservative reading (**UNVERIFIED** whether Apple treats it as one).

---

## 4. In-app bug report flow

### 4.1 Payload

- Category (Problem / Idea / Question, per `08-polish-features.md`), free-text description, optional reply-to email.
- Auto diagnostics, **shown to the user before sending**: app version and build, build UUID, flavor (App Store), macOS version, hardware model identifier (`hw.model`), CPU architecture, locale, free disk bucket, library size bucket (song count bucket, never names), current screen.
- Logs: see 4.3.
- Recent MetricKit diagnostics (crash/hang) if any.
- **Optional, unchecked by default:** the current song's `.cho` + sidecar (contains lyrics, so it is user content and opt-in per report).

### 4.2 Transport options

| Option | Works offline? | Attachments | Sandbox | Label | Verdict |
|---|---|---|---|---|---|
| (a1) `mailto:` URL | Queues in the mail client | **No attachments** (body only, length-limited) | No entitlement needed | Arguably none (user sends from their own mail client; Apple's "collect" means transmitting off device so the developer can access it, which email does, so declare Customer Support to be safe) | Fallback only. |
| (a2) `NSSharingService(named: .composeEmail)` with `recipients` and attachments | Yes (Mail outbox) | Yes (files) | No entitlement needed | As (a1) | **Fallback** when the endpoint fails or the user prefers email. Requires a configured mail app; users of webmail get nothing, so detect `canPerform(withItems:)` and offer "Copy report" + "Save report as file" as the last resort. |
| (b) POST to a Pages Function -> GitHub issue in a private repo + R2 for attachments | No (queue and retry) | Yes | Needs `com.apple.security.network.client` (F14 in `03`) | Customer Support; Crash Data / Other Diagnostic Data for the attached diagnostics; Other User Content if the song file is attached; Email Address if a reply-to is given. Not linked, not tracking. | **Recommended.** |
| (c) Feedback-vendor API | No | Vendor dependent | network.client | Vendor becomes a processor of diagnostics | Reject: couples bug reports to the board vendor, and most free tiers lack API access (Sleekplan API from Starter, Quackback API from Pro). |

### 4.3 Logs in the sandbox

- `OSLogStore(scope: .currentProcessIdentifier)` works in a sandboxed app but returns **only the current process's entries, i.e. the current launch**. `OSLogStore.local()` / system scope need admin plus the `com.apple.logging.local-store` entitlement, which third-party sandboxed apps cannot get (https://developer.apple.com/forums/thread/744806, https://mjtsai.com/blog/2021/12/10/oslogstore-on-monterey). So after a crash, the previous launch's unified logs are unreachable.
- **Technique:** a small `DiagnosticLog` that mirrors Segue's own `Logger` categories into a rolling file in the app container (for example 3 files x 512 KB, last three launches), written off the main actor. The bug report attaches this plus the current-launch `OSLogStore` entries filtered to subsystem `dev.ryandsilva.segue`. Log statements must never include lyrics, titles or paths (use `privacy: .private` and avoid them in the mirror).
- `~/Library/Logs/DiagnosticReports` is outside the container; MetricKit is the sandbox-safe crash source.

### 4.4 Endpoint design (option b) - superseded

- `POST /api/v1/reports` (multipart: JSON + up to N files, size-capped, e.g. 5 MB total). The function writes attachments to a private **R2** bucket (free: 10 GB-month, 1M Class A ops, 10M Class B ops, free egress, https://developers.cloudflare.com/r2/pricing/), then creates an issue via `POST /repos/{owner}/{repo}/issues` (https://docs.github.com/en/rest/issues/issues#create-an-issue) in a private `segue-reports` repo. Ryan gets GitHub's normal email/mobile notification.
- **Identity:** a dedicated **GitHub App** installed on that one repo, minting installation tokens in the function from the App's private key (a Pages secret). This avoids a personal token that expires and gives the automation its own identity.
- **Email alternative:** Cloudflare's `send_email` binding can send to verified addresses free, but it needs Email Routing on a Cloudflare zone (`ryandsilva.dev` DNS is at Squarespace) and Pages Functions' binding list does not include it (https://developers.cloudflare.com/pages/functions/bindings/). GitHub issues avoid both problems.
- **Abuse:** per-IP-hash daily caps in D1, payload size caps, `pending` triage label. No App Attest on macOS (section 3.3).
- **Ports:** `BugReportTransport` (`HTTPReportTransport`, `MailComposeTransport`, `FileExportTransport`), `DiagnosticsCollector` (assembles a `DiagnosticsBundle` value the user previews). The form tries HTTP, then offers email/file.
- Consent: a bug report is sent only when the user presses Send on a previewed payload, so it needs no separate analytics consent; the form states what is sent and links the privacy policy.

---

## 5. What's New, remote config, announcements

**A hosted JSON on the static site is enough.** No remote-config vendor (Firebase Remote Config, PostHog flags) is warranted.

- **What's New:** ship the release notes **inside the app bundle** (generated from the same canonical changelog source that produces `changelog.json` in `05-landing-page.md`), and show the sheet on the first launch of a new version. Works offline, no request needed, nothing to declare.
- **`changelog.json`:** fetched only when the user opens "Release Notes" (or never; the bundle copy is authoritative for installed versions).
- **`announcements.json`:** `[{id, minAppVersion, maxAppVersion, startsAt, endsAt, severity, title, body, url}]`. Fetched at most once a day on launch with `If-None-Match` (ETag), cached, dismissals stored locally, **never fetched or shown during a show**.
- **`config.json`:** a few kill switches and thresholds for code that already ships (e.g. disable the bug-report endpoint and fall back to email, telemetry flush interval). Remote flags may only toggle shipped code paths; downloading behaviour would conflict with 2.5.2. Include `schemaVersion`; unknown versions are ignored.
- **Port:** `RemoteContentSource` (`StaticSiteContentSource`, `BundledContentSource` for tests and offline).
- **Label:** fetching a static file sends no user data beyond the IP to the host, which we do not retain; the privacy policy already lists the host (`05-landing-page.md` section 1.3). No label entry.

---

## 6. Combined privacy-label outcome (recommended set)

| Data type | Source | Linked | Tracking | Purpose |
|---|---|---|---|---|
| Usage Data > Product Interaction | Opt-in telemetry | No | No | Analytics |
| Diagnostics > Crash Data, Performance Data, Other Diagnostic Data | Bug reports (MetricKit payloads, logs, hardware/OS info); also opt-in automatic MetricKit upload if enabled | No | No | App Functionality / Analytics |
| User Content > Customer Support | Bug report text | No | No | App Functionality |
| User Content > Other User Content | Attached song file; board posts from the app | No | No | App Functionality |
| Contact Info > Email Address | Optional reply-to / notify-me email | No (it is used only to reply; Apple may consider an email inherently identifying, so **Linked** is the conservative answer, **UNVERIFIED**) | No | App Functionality |
| Identifiers > Device ID | Only if the runner-up TelemetryDeck is used, or if the board voter token is counted as one | No | No | Analytics / App Functionality |

Privacy policy (5.1.1(i)) must list each of these, Cloudflare as host/processor, GitHub as the store for bug reports, retention periods (propose: telemetry rollups kept indefinitely since they contain no per-install data; bug reports and attachments deleted 12 months after the issue closes; board posts kept until deleted on request), and how to withdraw consent (Settings toggle) and request deletion (email `segue@ryandsilva.dev`).

---

## 7. Four-outcome verdicts (all vendors)

| Vendor | Verdict | Technique worth keeping |
|---|---|---|
| TelemetryDeck | Adopt (runner-up adapter) | Client-side hash plus server-side salt; typed error presets; "pirate metrics" funnel naming |
| Aptabase | Build informed by it | No device ID, daily-rotating salted hash, IP dropped after geolocation; EU/US region choice |
| PostHog | Build informed by it | Per-product billing caps; anonymous events without person profiles |
| Firebase | Build from scratch (reject) | - |
| Countly | Build from scratch (reject) | - |
| OpenPanel | Build informed by it | One pipeline for web and app events; note its AGPL Swift SDK |
| Amplitude / Mixpanel | Build from scratch (reject) | Funnel and retention report shapes to copy in the local dashboard |
| Apple App Analytics | Adopt | Thresholds and noise for small counts; reuse "omit rows under 5" in our own reports |
| Plausible / Umami / GoatCounter / Cloudflare Web Analytics | Site-only, defer to `05` | Cookieless counting |
| Matomo / Swetrix | Reject | - |
| Own Cloudflare telemetry | **Build from scratch (recommended)** | Client-computed cohort fields instead of an ID |
| Xcode Organizer / MetricKit | Adopt | - |
| Sentry | Adopt later if needed (runner-up) | dSYM upload as a post-archive host step |
| GlitchTip / Bugsink | Fork or vendor (escape hatch for Sentry protocol) | Sentry-compatible ingest so the SDK stays and the backend swaps |
| BugSnag | Reject | - |
| Embrace | Build informed by it | OpenTelemetry wire format |
| KSCrash / PLCrashReporter | Build informed by it (only if MetricKit falls short) | Write crash report to disk in-process, send on next launch |
| Canny | Build informed by it | Merge duplicates with vote carry-over; voter notification on status change |
| Featurebase | Hosted runner-up | Board + roadmap + changelog in one free workspace |
| Sleekplan | Hosted runner-up | Per-board anonymous posting toggle |
| UserJot, Nolt, Frill, Upvoty, FeatureOS, Productboard | Reject | - |
| Fider | Build informed by it | Email magic-link sign-in |
| LogChimp | Reject | Seven-level role model (overkill here) |
| Astuto | Reject (archived) | Anonymous feedback held for approval |
| Quackback | Build informed by it | Single widget for feedback, changelog and help with native mobile SDKs |
| ClearFlask | Build informed by it | Vote budgets ("credits") against vote inflation |
| GitHub Discussions | Build informed by it (stopgap option) | Upvote + "sort by top" + Announcements category as a free changelog channel |
| GitHub Issues | Reject | - |

---

## 8. Decisions for Ryan (superseded by H.7)

1. **Analytics backend.** (a) Own ID-less telemetry on Pages Functions + D1 with a local `make stats` report (recommended); (b) TelemetryDeck free tier (50k events/month for a new account; dashboards on day one; Device ID on the label; proprietary EU processor; free tier was already cut once); (c) both: TelemetryDeck now, own endpoint later behind the same port; (d) make it a research ticket (spike: build the rollup schema + stats report and compare against a week of TelemetryDeck data).
2. **Consent model.** (a) Opt-in first-run choice + Settings toggle (recommended; matches 5.1.1(ii) text and `03` F11); (b) opt-out with a first-run notice (CNIL-style; review risk); (c) no telemetry in v1.
3. **Country in telemetry.** (a) Omit, label stays at Product Interaction (recommended); (b) keep country from `request.cf.country` and add Coarse Location.
4. **Crash reporting.** (a) Organizer + MetricKit only, MetricKit attached to bug reports (recommended); (b) also auto-upload MetricKit payloads under the analytics consent; (c) add Sentry free tier now.
5. **Feature board.** (a) Build our own on the shared backend with a native in-app list (recommended); (b) own board, web page only, app opens `/feedback`; (c) hosted Featurebase or Sleekplan behind the `/feedback` redirect (after confirming anonymous voting on the free plan); (d) GitHub Discussions in a public `segue-feedback` repo; (e) research ticket (confirm Sleekplan/Featurebase free-plan voting rules by signing up).
6. **Bug report transport.** (a) HTTP -> GitHub issue (GitHub App) + R2, with email/file fallback (recommended); (b) email only (`NSSharingService` + file fallback), no backend; (c) HTTP -> email via Mailgun (already handles inbound mail per `05`; free-tier sending limits **UNVERIFIED**).
7. **Board identity for "notify me".** (a) Optional email, verified by magic link (recommended); (b) no email at all, purely anonymous.
8. **Backend scope.** Vision section 5 lists "cloud backend" out of scope (that was about user data and accounts). Accept a small Cloudflare backend for telemetry, reports and the board? (a) Yes, one Pages project, one D1, one R2 (recommended); (b) No: TelemetryDeck + email reports + hosted board, zero code we operate.
9. **Retention periods** for bug reports and attachments (propose 12 months after close) and for board posts.

## 9. Things Ryan must do himself (superseded by H.6)

- Create a Cloudflare account (free) and connect the Pages project (already in `05`); create the D1 database and R2 bucket; add secrets (GitHub App private key, voter pepper).
- Create the GitHub App, install it on a new private `segue-reports` repo.
- If TelemetryDeck is chosen: create the account (new accounts get 50k/month).
- In App Store Connect: complete the privacy questionnaire per section 6 once the set is chosen; keep "Include symbols" on at upload.
- Add `com.apple.security.network.client` to `App/Segue.entitlements` (both flavors; F14 in `03`).
