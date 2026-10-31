# 01 - Apple account and App Store Connect business setup

Researched 2026-10-17. Scope (narrowed by Ryan): US resident, individual membership, renewing the lapsed paid
Apple Developer Program membership on team `V6BM673U35`, app **free at launch**.
Every claim has a source in the "Sources" section (numbered `[n]`). Anything not confirmed from a primary
source is marked **UNVERIFIED**.

## Summary

1. **`V6BM673U35` is the paid team, not a Personal Team.** The repo (`Project.swift`, `JOURNAL.md`,
   `docs/decisions.md`) calls it "free Personal Team", but this Mac holds two manually created (not
   Xcode-managed) provisioning profiles on that team, "daily dev profile" and "daily prod profile"
   (TeamName "Ryan Rony Dsilva", created 2025-09-02). Free teams cannot create manual or distribution
   profiles [2], so this is the paid individual team. The "prod" profile expired 2026-09-01, which suggests
   the membership lapsed around **2026-09-01/02** (inference, not confirmed - check the Membership page).
   The other team in the keychain, `TD357Y4Q58` (Apple Account ryan.dsilva.98@gmail.com), is a separate
   account and irrelevant here. Fix the wording in the repo once renewal is done.
2. **Renewing keeps the team.** Apple: renew "any time after it expires" on the web; free apps reappear
   within 24h; no resubmission needed [3]. Via the Apple Developer app the window is "up to one year after
   your membership expiration date" [3]. Team and account data are preserved; registered devices are
   auto-removed 180 days after expiry [4]. Team ID staying identical is implied (same team, same account)
   but Apple doesn't state it in so many words - **UNVERIFIED but very likely**. Existing App IDs (e.g.
   "daily") survive [4]. Certificates keep their own expiry dates (1 year for development certs, as
   observed locally) and are not reissued by renewal, so expect to make new distribution certificates.
3. **Seller name will be "Ryan Rony Dsilva"** (the legal name on the team, shown in the cert `O=` field and
   profile TeamName). Individual accounts always show the personal legal name as seller [1][5]. A brand
   seller name ("Segue") needs an Organization membership (legal entity + D-U-N-S) [1][5].
4. **The exact name "Segue" is taken.** Two live iOS apps are titled exactly "Segue" (Planetica fleet
   tracking, since 2016; a vocabulary app, since 2025-12), and names are unique per localization across
   platforms [11][12][13]. New since `docs/decisions.md` was written: **"Segue - Music & Memory"** (Music
   category, iOS, released **2026-10-11**) and the Mac Safari extension "Timbre Segue" (Music, 2026-04).
   Neither is a setlist or chord app. "Segue - Setlists & Chords" (25 chars) does not appear in search, but
   unreleased app records also reserve names, so only creating the record proves it's free.
5. **Free app = no Paid Apps Agreement, no tax form, no bank account.** Free distribution is covered by
   the Apple Developer Program License Agreement (DPLA) [6]. A **new DPLA was published 2026-10-13**, and
   Ryan must accept it before he can create the app record [7][10].
6. **EU DSA:** for a free, no-IAP, no-ads app from an individual, "not a trader" is a defensible
   self-assessment [8]. The app stays available in the EU; EU users are told consumer-protection rights
   don't apply [8]. Adding paid or IAP later almost certainly makes him a trader, which means a public
   address (P.O. Box allowed), phone and email on the product page.
7. **Export compliance:** set `ITSAppUsesNonExemptEncryption = NO`. The App Store target uses no crypto
   APIs (grep found no CryptoKit/CommonCrypto; the only `URLSession` mention is in
   `Packages/SegueCore/Sources/Library/SongFiles.swift`). The key is missing from `Project.swift` today.
   No annual BIS self-classification report is needed for this kind of app [17][18].

## Step-by-step checklist

Tags: **[RYAN]** = manual action in a browser or app. **[AGENT]** = automatable from this repo.

### A. Membership

1. **[RYAN]** Sign in at developer.apple.com/account with **contact@ryandsilva.dev**, open Membership
   details, and confirm three things: Team ID is `V6BM673U35`, entity type is Individual, and the expiry
   date. Also check whether the membership was bought on the web or in the Apple Developer app; renewal
   uses the same channel [3].
2. **[RYAN]** Renew. Web: "Renew Membership" button, 99 USD, US credit card [3][1]. App-purchased:
   resubscribe in the Apple Developer app or in Settings > Subscriptions, within 1 year of expiry [3].
   Optional: turn on Auto-renew in Membership details (US supported) [4].
3. **[RYAN]** Wait for the confirmation email (Apple says contact them if it hasn't arrived within 24h)
   [5]. Then reconfirm that the Team ID is unchanged.
4. **[RYAN]** In App Store Connect > Business > Agreements, accept the **2026-10-13 DPLA** (Account Holder
   only) [7][6]. While there, decide on Paid Apps: leave it unsigned for a free launch (see Decision D2).
5. **[RYAN]** Optional, on the first Certificates, Identifiers & Profiles sign-in of the new membership
   year: Apple offers to prune old test devices [4]. A Mac-only app can keep or remove them, it makes no
   difference.

### B. Signing identity and App ID

6. **[AGENT]** Update the `Project.swift` comment and `docs/decisions.md`/`JOURNAL.md` wording: say
   "paid individual team (renewed 2026-10)" instead of "free Personal Team". The team ID value stays the
   same. Add `ITSAppUsesNonExemptEncryption = NO` to the App Store target's Info.plist settings. (Leave
   both for the implementation session, which is out of scope for this research doc.)
7. **[AGENT or RYAN]** Register the explicit App ID `dev.ryandsilva.segue`, platform macOS (Account
   Holder/Admin) [9]. Capabilities: App Sandbox and user-selected file access are entitlements that need no
   portal capability. In-App Purchase is on by default for explicit App IDs [9]. Xcode automatic signing with `-allowProvisioningUpdates` registers it too, but doing
   it explicitly in the portal or through the API keeps it inspectable. A local check found no provisioning
   profile for `dev.ryandsilva.segue`, so the ID is probably not registered anywhere yet (if it were
   registered to another team, release takes a support request [21]).
8. **[AGENT]** Distribution certificates: let Xcode automatic or cloud-managed signing create the "Apple
   Distribution" certificate (and the "Mac Installer Distribution" one if a `.pkg` upload is used) [19].
   Only the Account Holder or an Admin can create distribution certs, and each team can have only one of
   each type [19].

### C. App Store Connect API key (for automated uploads)

9. **[RYAN]** Users and Access > Integrations > **Request Access** (Account Holder only, approved case by
   case) [14].
10. **[RYAN]** Once approved, generate a **Team key** with the App Manager role (Developer is enough for
    uploads only). Download the `.p8` file - **it can be downloaded only once** - and note the Key ID and
    Issuer ID [14]. Store it in 1Password, never in the repo.
11. **[AGENT]** Wire `xcodebuild -exportArchive` / `xcrun altool` / `notarytool`-style upload plus the
    App Store Connect API into `make` targets, using the key from the environment or keychain.

### D. Compliance

12. **[RYAN]** Business > Agreements > Compliance > Digital Services Act > Complete Compliance
    Requirements. Choose the trader status (Decision D3) [8]. Required role: Account Holder or Admin [8].
13. **[RYAN]** In the app record, answer the regulated medical device question **"No"**. It only needs a
    real declaration for Health & Fitness or Medical category apps [20].

### E. App record

14. **[RYAN or AGENT]** Create the app record under Apps > + > New App: platform macOS; Name (2-30 chars,
    unique per localization) [11][12]; Primary Language English (U.S.) (can be changed later) [12]; Bundle
    ID `dev.ryandsilva.segue` (locked once a build is uploaded) [12]; SKU e.g. `segue-macos` (letters,
    digits, `-._`; **can never be changed or reused**) [12][13]; User Access Full. Requires the Account
    Holder to have accepted the latest agreement [11]. The App Store Connect API can also create the record
    [14] - **UNVERIFIED** whether app *creation* is exposed in the API today; assume web.
15. **[RYAN]** If "Segue - Setlists & Chords" is rejected as in use, try the fallbacks in Decision D1.
    Entering it reserves the name immediately; the name can be edited until first submission [12].

### F. TestFlight (macOS)

16. **[AGENT]** Archive the `SegueAppStore` scheme and upload with the API key; fill in the export
    compliance answer through the Info.plist key.
17. **[RYAN]** Internal testing: Ryan, as an App Store Connect user, can test right away with no review.
    Up to 100 internal testers, who must be ASC users [15]. Individual accounts can add up to 50 ASC users,
    but they don't get access to the developer portal [16].
18. **[RYAN]** External testing (optional): create an external group, add test info (feedback email,
    what to test), and submit the first build for **TestFlight App Review**. Then invite by email or a
    public link, up to 10,000 testers [22]. Builds expire after 90 days [15]. Testers install the TestFlight
    app from the Mac App Store [15].

### G. Pricing and availability

19. **[RYAN]** Pricing and Availability: price **Free**. The free tier is available without the Paid Apps
    Agreement [23]. Territories: all 175 storefronts, or a subset (see D3 for the EU) [23].
20. **[RYAN]** Optional: publish as a **pre-order**, which is allowed for free apps on all platforms
    including macOS, with release 2 to 180 days out [24].
21. **[RYAN]** Submit for review. Apple's figures: 50% reviewed within 24h, 90% within 48h [25].

## Decisions Ryan must make

### D1. App Store name (30-char limit, unique per localization)
| Option | Length | Notes |
|---|---|---|
| a. "Segue - Setlists & Chords" (current plan in decisions.md) | 25 | Not found in Search API; may still be held by an unreleased record |
| b. "Segue: Setlists & Chord Charts" | 30 | Exactly at the limit |
| c. "Segue - Live Setlists" | 21 | Stage-mode angle; weaker chord keyword |
| d. "Segue Stage" / "Segue Setlists" | 11 / 14 | Short brand-plus-noun |
| e. Research ticket: full conflict check (App Store, USPTO, domains) on a/b/c before reserving | - | Matches the naming-check preference; "Segue - Music & Memory" (2026-10-11) is a new near neighbour in Music |

Guideline 2.3.7 bans keyword stuffing in the name, and guideline 4.1 bans using another developer's product
name [26]. Use the 30-char subtitle for extra keywords [12].

### D2. Sign the Paid Apps Agreement now or later
- **Later (recommended for a free launch):** nothing to sign, no W-9, no bank account [6].
- **Now:** signing is irreversible ("can't undo") [6]. It unlocks paid pricing and IAP, and requires a
  W-9 (SSN, as a US individual) plus bank details [27][28]. Tax info can't be edited after submission
  except through support [27].
- When paid or IAP arrives, **enrol in the Small Business Program in the same session** as signing the Paid
  Apps Agreement. The 15% rate starts 15 days after the end of the fiscal month of approval, so enrolling
  late means early sales pay 30% [29][30].

### D3. EU DSA trader status (free app, individual)
Apple's factors: revenue (paid, IAP, ads), commercial practices, VAT registration, whether the app is made
"in connection with" your trade or profession, and business legal status. A hobbyist with no intent to
commercialise "may not be considered a trader" [8]. It is a self-assessment that Apple won't make for you [8].
- **a. Non-trader (recommended at free launch):** no public contact details. The app stays in all 27 EU
  storefronts. EU users see a note that consumer-protection rights don't apply [8]. Risk: Ryan is a
  professional software developer (ryandsilva.dev), which is a gray area for the "profession" factor. This
  is not legal advice - **UNVERIFIED** how strictly regulators would read it.
- **b. Trader:** publish an address or P.O. Box, phone and email on the product page. Each is verified by
  2FA code; a business or legal document proving the name and address is required, plus proof of
  association for a P.O. Box [8]. Privacy cost: home address public unless he rents a P.O. Box.
- **c. Exclude the EU:** distributing only outside the EU means not acting as a trader there [8]. He must
  still declare a status [8]. This loses EU users.
- **Switching later:** status can be changed per app (App Information > App Store Regulations and Permits >
  Digital Services Act) [8]. If paid or IAP is added, plan on (b) and budget for a P.O. Box.

Background: starting 2025-02-17, apps without a declared status were removed from the EU store until one
was provided [31].

### D4. Individual vs Organization (long term)
- **Stay Individual (recommended):** no extra cost, and the seller shows as "Ryan Rony Dsilva" [5].
- **Organization (e.g. an LLC):** the seller shows the entity name. Needs a legal entity (no DBAs or trade
  names), a free D-U-N-S number, a domain email and a public website, and the enroller must have binding
  authority [1][5]. Converting is done by contacting Apple support, only after renewal completes [5][4].
  LLC formation cost and time depend on the state - **UNVERIFIED**, not researched. Also makes DSA trader
  status cleaner: the D-U-N-S address is shown instead of a home address [8].

## Costs (USD)

| Item | Cost | Source |
|---|---|---|
| Apple Developer Program renewal | 99 / year | [1][5] |
| Free Apps (DPLA), app record, TestFlight, API key | 0 | [6][14][15] |
| Commission on a free app | 0 | n/a |
| If paid or IAP later | 15% with the Small Business Program (under 1M USD proceeds), else 30% | [29] |
| D-U-N-S (Organization path only) | Free in most jurisdictions | [5] |
| P.O. Box (DSA trader path only) | Varies, **UNVERIFIED** | - |

## Timelines

| Step | Expected | Source |
|---|---|---|
| Renewal active | Immediate to 24h (contact Apple if longer) | [3][5] |
| Free apps restored after renewal | Within 24h (n/a, nothing live) | [3] |
| API access request | Case by case, no SLA stated | [14] |
| Banking changes (paid path) | Processed within 24h after approval | [28] |
| TestFlight external review | First build reviewed, then quick | [15][22] |
| App Review | 50% in <24h, 90% in <48h | [25] |
| Small Business rate effective | 15 days after the end of the fiscal month of approval | [29] |
| Device list auto-purge after lapse | 180 days after expiry (around late Feb 2027 if expired around Sep 1) | [3] |
| Apple Developer app resubscribe window | 1 year after expiry | [3] |

## 2025-2026 changes worth knowing

- 2026-10-13: new DPLA. Section 3.2 has new security requirements. Schedules 2 and 3, section 3.3: Apple
  will report tax, sales and contact details to tax authorities. Must be accepted [7].
- 2026-09-09: Xcode 27 RC for submissions. macOS 27 is Apple silicon only; Apple suggests arm64-only
  builds. The April 2027 SDK minimums are listed for iOS, iPadOS, tvOS, visionOS and watchOS (macOS not
  named in that post) [10].
- 2026-03-26: regulated medical device declaration for new apps (EEA, UK, US). Answer "No" outside Health
  & Fitness and Medical [20].
- 2026-08-18: EU terms. The Core Technology Commission replaces the Core Technology Fee from 2026-10-01
  (affects paid or IAP only) [33].
- 2025-02-17: DSA trader status enforced in the EU [31].

## Sources

1. Apple Developer Program - Enroll: https://developer.apple.com/programs/enroll/
2. Compare memberships (free vs paid capabilities): https://developer.apple.com/support/compare-memberships/
3. Program renewal (help): https://developer.apple.com/help/account/membership/renewal/
4. Renewal support page: https://developer.apple.com/support/renewal/
5. Enrollment support + help: https://developer.apple.com/support/enrollment/ and https://developer.apple.com/help/account/membership/program-enrollment/
6. Sign and update agreements: https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements/
7. Updated DPLA, 2026-10-13: https://developer.apple.com/news/?id=17mwd36z
8. Manage EU DSA trader requirements: https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/
9. Register an App ID: https://developer.apple.com/help/account/identifiers/register-an-app-id/
10. Submissions open for latest OS releases, 2026-09-09: https://developer.apple.com/news/?id=k1mtkt1k
11. Add a new app: https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/
12. App information reference: https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/
13. Remove an app (name ownership, SKU reuse): https://developer.apple.com/help/app-store-connect/create-an-app-record/remove-an-app/ ; name unique per localization regardless of platform (Apple forums, secondary): https://developer.apple.com/forums/thread/133457 ; live listings from the iTunes Search API, queried 2026-10-17: https://itunes.apple.com/search?term=segue&entity=software&country=gb , https://itunes.apple.com/lookup?id=6788616100 , https://itunes.apple.com/lookup?id=1170618443 , https://itunes.apple.com/lookup?id=6756835389 , https://itunes.apple.com/lookup?id=6762169748
14. App Store Connect API - get started: https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/
15. TestFlight overview: https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/
16. Add and edit users (individuals: up to 50 ASC users, not team members): https://developer.apple.com/help/app-store-connect/manage-your-team/add-and-edit-users/ ; roles: https://developer.apple.com/help/app-store-connect/reference/account-management/role-permissions/
17. Overview of export compliance: https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/ ; Complying with encryption export regulations: https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations
18. BIS 2021 rule removing most mass-market self-classification reports (secondary legal summaries): https://www.thompsonhine.com/publications/bis-eliminates-most-mass-market-encryption-reporting-obligations , https://www.jonesday.com/en/insights/2021/04/commerce-reduces-requirements-relating-to-massmarket-encryption-items-and-publicly-available-software . The primary BIS text was not fetched - **UNVERIFIED at primary source**, but Segue has no proprietary crypto, so `NO` is the right answer either way.
19. Certificates overview: https://developer.apple.com/help/account/certificates/certificates-overview/
20. Regulated medical device status, 2026-03-26: https://developer.apple.com/news/?id=nyqbfz1y
21. App IDs stuck on another team need support or a new bundle ID (forums, DTS answer Aug 2026): https://developer.apple.com/forums/thread/843925 , https://developer.apple.com/forums/thread/107350
22. Invite external testers: https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/
23. Set a price: https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price/
24. Publish for pre-order: https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/publish-for-pre-order/
25. App Review: https://developer.apple.com/distribute/app-review/
26. App Review Guidelines (2.3.7, 3.1.1, 3.1.3, 4.1): https://developer.apple.com/app-store/review/guidelines/
27. Provide tax information (W-9 for US-based; no edits after submission): https://developer.apple.com/help/app-store-connect/manage-tax-information/provide-tax-information/
28. Enter banking information: https://developer.apple.com/help/app-store-connect/manage-banking-information/enter-banking-information/
29. App Store Small Business Program: https://developer.apple.com/app-store/small-business-program/
30. Small Business Program enrolment news: https://developer.apple.com/news/?id=6lyxewwp
31. Apps without trader status removed from EU (2025-02-17): https://developer.apple.com/news/?id=einwn76m
32. Turn on Family Sharing for IAP: https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/turn-on-family-sharing-for-in-app-purchases/
33. Changes for apps in the EU, 2026-08-18: https://developer.apple.com/news/?id=gmws0jgp

Local evidence (read-only, 2026-10-17): `security find-identity` shows "Apple Development: Ryan Rony Dsilva"
with `OU=V6BM673U35`. The profiles in `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`
(`19db5345-...`, `b3d3d7f3-...`) are team V6BM673U35, `IsXcodeManaged=false`, created 2025-09-02, with the
"prod" profile expiring 2026-09-01.
