# WS3 - Hosted services: analytics, crash reporting, bug reports, feature board

Implementation spec for one focused build session. Written 2026-10-17, finalised the same day after Ryan's rulings R30-R41. Read it standalone; everything needed is here or linked.

- Canonical rulings: `docs/release/decisions.md` **R22-R26** (bug report preview and opt-in song file; hosted vendors behind Swift protocols; Sentry-only bug reports; separate consent toggles; Sentry per-install ID kept and declared; opt-in analytics asked once, coarse country), **R32** (retention), **R33** (Sentry US region), **R34** (own minimal TelemetryDeck ingest client), **R38** (the website uses Cloudflare Web Analytics; WS4's concern, but 10.1 stays consistent with it), **R40** (Ryan's container moved aside before TestFlight). Also R28 (support email), R29 (`/feedback` redirects to the board). Follow them exactly.
- Resolved questions: every former open question of this spec is closed (`docs/release/open-questions.md` A4-A11, A61, A62, B-24, B-25, and cross-spec items I-1, I-6, I-8, I-9, I-15). Each answer is written inline where it applies, tagged *(A n)*, *(B-n)* or *(I-n)*. Section 17 lists only questions that are new in this revision.
- Research behind them: `docs/release/research/07-services.md` **"Hosted-only stack" section only** (sections 0-9 of that file are superseded), `03-review-risk.md` 5.1.1 consent and section 8 (privacy label), F11-F15.
- Project rules still in force (`docs/decisions.md`): integration-first testing, files canonical, Swift 6 strict concurrency with warnings as errors, tools via mise only.
- Sibling specs this one plugs into: `WS1-release-pipeline.md` (bundle ID split, `App/SegueAppStore.entitlements`, `network.client` on both flavours, `App/PrivacyInfo.xcprivacy`, `scripts/release.sh`, `make upload`, `verify-archive`), `WS2a-core-ux.md` (`SegueLinks`, `AppHooks.reportProblem` / `requestFeature`, `WorkspaceActions`, Help menu), `WS2b-first-run-polish.md` (Welcome flow, Settings host, Reset All Settings; it consumes the contract in section 4.4), `WS4-website.md` (privacy policy, `/feedback` redirect; takes the vendor facts in 10.1), `WS5-store-listing.md` (copies the App Privacy answers in 10.2 verbatim).

Working rules for the session: sibling agents may be editing other files in this tree at the same time; expect unrelated changes in `git status` and do not treat them as conflicts. In Bash never use plain `cat` (aliased to eza, it hangs); use `command cat` or the Read tool. No em dashes in anything you write. Commit locally, signed (`git commit -S`), one commit per step; never push.

---

## 1. Goal

1. The app talks to three hosted vendors, each behind a Swift protocol so swapping a vendor is a module change: **TelemetryDeck** (usage analytics, through our own minimal ingest client, not the TelemetryDeck SDK, R34), **Sentry** (crashes, hangs, MetricKit upload, and bug reports as Sentry User Feedback with attachments), **Featurebase** (web feature board reached by a link). Apple App Analytics stays the no-SDK baseline.
2. **Nothing leaves the Mac without consent.** Two independent opt-in toggles (analytics, crash reports), asked once on first run with equal-weight choices, changeable in Settings > Privacy. No vendor SDK is even initialised before its toggle is on. Turning a toggle off stops sending at once and explains how to request deletion.
3. Analytics answer Ryan's product questions (growth, retention, which features to invest in) through a **closed event vocabulary** that structurally cannot carry song titles, lyrics, file names or free text.
4. **Report a Problem** is a native sheet that shows exactly what will be sent before it is sent (R22), with an offline email fallback. **Request a Feature** opens the board.
5. Crash reports are symbolicated: `make upload` also uploads the dSYMs to Sentry.
6. The App Privacy label and `PrivacyInfo.xcprivacy` match what the code can actually send, and WS4 gets the vendor facts its privacy policy needs. **Section 10.2 is the single source of truth for the label** *(I-9)*: WS5 section 6 copies it, WS4's policy is written to match it.
7. Both flavours ship the services *(A61)*: the Personal build has the same consent UI and vendors, with Sentry environment `personal` and its own TelemetryDeck app so Ryan's use never mixes with product data.

Out of scope (owned elsewhere): the Welcome flow itself and the Settings host and pane structure (WS2b; contract in 4.4), Help menu items and `SegueLinks` (WS2a), the `network.client` entitlement on both flavours and the matching `verify-appstore` assertion (WS1 step 1, *I-15*), the privacy policy, the website's own analytics (Cloudflare Web Analytics, R38) and the `/feedback` redirect page (WS4), entering the label in App Store Connect as part of the store listing (WS5 does the listing; the answers come from section 10.2 here), an error-banner "Report..." button (research 08 5.5; follow-up, not 0.5).

---

## 2. Current state (code facts this spec builds on)

| Area | Today | Evidence |
|---|---|---|
| Network | No network code, no `network.client` entitlement today. WS1 step 1 adds `network.client` to `App/SegueAppStore.entitlements` and to both Personal files (`App/Segue.entitlements`, `App/Segue-Debug.entitlements`) and makes `verify-appstore` assert both flavours have it *(A61, I-15)*. WS3 edits no entitlements file. | `App/Segue.entitlements`; WS1 4.2/4.3 |
| Packages | `SegueCore` (one SPM target per folder: ChordPro, MusicTheory, Diagrams, Editing, Library, Setlists, Shows, LiveLayout, Plugins, Support; platform-neutral, no SwiftUI/AppKit), `SegueUI`, `SeguePersonalModules`. Dependencies pinned `exact:` in both the package manifest and `Tuist/Package.swift`; first-party targets listed in `Tuist/Package.swift` `targetSettings` get strict settings. | `Packages/*/Package.swift`, `Tuist/Package.swift` |
| App targets | `Segue` (Personal, links SeguePersonalModules, `SEGUE_PERSONAL`) and `SegueAppStore`. `scripts/verify-appstore.sh` proves no personal code in App Store products. | `Project.swift` |
| Composition root | `App/Sources/SegueApp.swift` builds `AppDependencies` (file system, clock, ids, location, live deps). Test doubles come from Debug-only launch options (`LaunchOptions`, e.g. `-SegueShortcutLog` -> `RecordingShortcutRunner`). Test runs use a separate defaults suite (`AppStateReset`). | `App/Sources/LaunchOptions.swift` |
| Settings | One `TabView` with a "Live" tab; `LiveSettingsStore` persists a JSON value in `UserDefaults` (`SegueJSON`). WS2b moves the TabView into a new `SegueSettingsView.swift` with panes General, Appearance, Live, Privacy, Data *(I-6, R36)*. | `UI/Settings/LiveSettingsView.swift`, `LiveSettingsStore.swift` |
| Logging | One `Logger` (`editor-perf`), made Debug-only by WS1 4.8a. No file log. `OSLogStore(scope: .currentProcessIdentifier)` only sees the current launch in the sandbox (research 07 4.3). | `UI/Editor/EditorPerformance.swift` |
| Help hooks | WS2a adds `AppHooks` (`@MainActor` closures `reportProblem`, `requestFeature`, `showWhatsNew`) in `AppDependencies`, `SegueLinks` (all URLs, lint-enforced), `WorkspaceActions` (`open(URL)`, recording double via `-SegueWorkspaceLog`). | WS2a 3.1, 3.5.6, 3.12 |
| Privacy manifest | WS1 creates `App/PrivacyInfo.xcprivacy` with an empty `NSPrivacyCollectedDataTypes` array "Filled by WS3". | WS1 4.4 |
| Release | WS1 adds `scripts/release.sh archive|validate|upload`, archives to `.build/archives/Segue-<ver>-<build>.xcarchive`, reads secrets from 1Password with `op read` into a 0600 temp dir. No Sentry anything. | WS1 4.7 |
| Search | `LibraryStore.search(query:)` runs four tiers: (1) FTS on original text, (2) `RomanNormalizer` spelling-variant forms, (3) loose forms (`dewana` = `deewana` = `diwana`), (4) edit-distance fallback only when 1-3 find nothing. Used by the library (`LibraryViewModel.search`), the stage quick search (`QuickSearchModel`) and the setlist builder. | `Core/Library/LibraryStore.swift` (`search`), `RomanNormalizer.swift` |
| Chord palette | The editor's `ChordPaletteBar` (`PaletteChip` arms a chord, `model.armedChord`), chords from `computePaletteChords()`. | `UI/Editor/EditorBars.swift`, `SongEditorViewModel+ChordInput.swift` |
| Feature touch points for events | Library: `LibraryViewModel.createSong`, `saveEditor`, search/filter. Editor: `stepTranspose`, `setCapoMode`, `setNashville`, `setShowDiagrams`, `setInstrument`, `applyTranspositionToSource`, `setEditorMode`. Setlists: `SetlistsViewModel.create/duplicate/insert/move/remove`. Shows: `AppModel.startShow(_:kind:)`, `resumePendingShow`, `finishRun`, `LiveSession.dispatch(LiveCommand)` (autoscroll, search, requests, columns, zoom, collapse repeats). Gig log: `GigLogViewModel.update`. Import and Delete Song arrive with WS2a. | `Packages/SegueUI/Sources/SegueUI/...` |

`UI/` below means `Packages/SegueUI/Sources/SegueUI/`, `Core/` means `Packages/SegueCore/Sources/`.

---

## 3. Architecture

### 3.1 Modules

```
SegueCore / Services   (new SPM target; Foundation + Synchronization + os only; no vendor code)
  ports:      AnalyticsSink, CrashReporter, FeedbackSender, DiagnosticsSource
  values:     AnalyticsEvent (closed enum) + param enums, Breadcrumb, FeedbackReport, ConsentState
  core logic: ServicesHub (consent-gated adapter switch), AnalyticsThrottle, Buckets,
              DiagnosticLog (privacy-safe rolling file logger), FeedbackReportBuilder
  adapters:   NullAnalyticsSink, NullCrashReporter, NullFeedbackSender,
              Recording* (JSON-lines file; Debug E2E seam, like RecordingShortcutRunner)

Packages/SegueVendorServices / VendorServices   (new local package; the ONLY code that knows vendor SDKs or endpoints)
  TelemetryDeckIngestSink      (our own minimal client for TelemetryDeck's Ingest API v2; URLSession only,
                                no TelemetryDeck SDK dependency; see 3.9)
  SentryCrashReporter          (sentry-cocoa, exact pin; also the MetricKit upload)
  SentryEnvelopeFeedbackSender (Sentry User Feedback over the envelope endpoint; see 3.5)
  SentryScrubber               (pure beforeSend / beforeBreadcrumb functions)
  VendorServicesFactory        (builds adapters from VendorConfig)

SegueUI / Services (new folder)
  ConsentStore (@MainActor @Observable, UserDefaults), ConsentChoiceView, ConsentSheet,
  PrivacySettingsView, ReportProblemModel, ReportProblemSheet, ReportPreviewView,
  MailComposer port (+ SharingServiceMailComposer), ReportFileSaver,
  MetricKitCollector (MXMetricManagerSubscriber keeping the latest payload locally)

App target
  App/Sources/ServicesWiring.swift: picks Null/Recording/Vendor adapters per build and launch
  options, reads VendorConfig from Info.plist, replaces AppHooks.reportProblem/requestFeature.
```

Rules that make the boundaries hold:
- `SegueCore` and `SegueUI` never import `Sentry` and never spell a vendor host. A SwiftLint `custom_rules` regex (`^\s*(@preconcurrency\s+)?import\s+(TelemetryDeck|TelemetryClient|Sentry)`) fails `make lint` anywhere outside `Packages/SegueVendorServices/` (the TelemetryDeck names stay in the rule so the SDK can never creep back in), and a second rule fails on the strings `telemetrydeck.com` and `sentry.io` outside `Packages/SegueVendorServices/` and `UI/App/SegueLinks.swift`.
- Only the app targets (App Store and Personal, *A61*) link `VendorServices`. Swapping TelemetryDeck for another vendor means a new adapter in `VendorServices` (or a new package) and one line in `ServicesWiring.swift`; the vocabulary, consent, UI and tests do not change.
- Debug configurations (`Debug-Personal`, `Debug-AppStore`) never construct vendor adapters, except with the Debug-only `-SegueServicesLive YES` flag used for the live checks in steps 5-6. Tests and E2E use Null or Recording adapters. Release-Personal and Release-AppStore construct vendor adapters (after consent).

### 3.2 Ports (in `Core/Services/Ports.swift`)

All ports are `Sendable` and synchronous fire-and-forget at the call site, so `@MainActor` view models call them without `await` and a slow vendor can never stall the UI or the stage.

```swift
public protocol AnalyticsSink: Sendable {
    func send(_ signal: AnalyticsSignal)            // already rendered: name + [String: String]
    /// Stop for good: drop anything queued in memory and on disk, send nothing more.
    func shutDown(discardingQueue: Bool) async
}

public protocol CrashReporter: Sendable {
    func addBreadcrumb(_ crumb: Breadcrumb)        // closed vocabulary only (3.6)
    func shutDown(discardingQueue: Bool) async     // close SDK, delete cached envelopes
    var installationID: String? { get }            // shown in Settings > Privacy (4.3)
}

public protocol FeedbackSender: Sendable {
    /// Sends exactly `payload` (the bytes the user previewed). Throws FeedbackError.offline,
    /// .rejected(status), .tooLarge, .notConfigured.
    func send(_ payload: FeedbackPayload) async throws(FeedbackError)
}

public protocol DiagnosticsSource: Sendable {      // what the report may attach
    func recentLogFiles() async -> [DiagnosticFile]
    func latestMetricKitPayload() async -> DiagnosticFile?
}
```

`AnalyticsSignal` is produced only by `AnalyticsEvent.render()` (internal init), so an adapter cannot be handed a hand-built signal from outside the module.

### 3.3 ServicesHub (consent gate)

`public final class ServicesHub: Sendable` in `Core/Services/ServicesHub.swift`. Holds the current adapters in `Synchronization.Mutex<State>` (macOS 15+ API, fine on 26), so any isolation can call it.

- `init(factory: any ServicesFactory, consent: ConsentState, throttle: AnalyticsThrottle)`. The factory has `makeAnalytics() -> any AnalyticsSink`, `makeCrashReporter() -> any CrashReporter`. **The factory is only called when the matching consent is `.granted`.** With consent undecided or declined the hub holds `NullAnalyticsSink` / `NullCrashReporter`, and no vendor code is ever touched (no `TelemetryDeckIngestSink` constructed, no queue file read, no `SentrySDK.start`). This is the structural guarantee behind "no SDK before consent", and the integration tests assert it with a counting factory.
- `record(_ event: AnalyticsEvent)`: throttle check (3.4), render, forward to the current sink; also adds the matching breadcrumb to the crash reporter (3.6). Never throws, never blocks.
- `apply(_ consent: ConsentState) async`: on a transition to granted, build and install the adapter; on a transition away from granted, swap the Null adapter in **first** (under the lock, so no event can reach the old adapter after this line), then `await old.shutDown(discardingQueue: true)`.
- Feedback is not consent-gated (sending a previewed report is its own explicit act, research 07 4.4 and R22); the hub exposes `feedback: any FeedbackSender` built once at launch. Constructing `SentryEnvelopeFeedbackSender` opens no connection; it only posts when the user presses Send.

### 3.4 Throttling and the event budget

TelemetryDeck's free tier is 50,000 signals/month for accounts created after 2026-07-01 (https://telemetrydeck.com/blog/pricing-update-2026/); at the cap collection pauses. The cap is per organisation, so the Personal app *(A61)* shares it; Ryan's own use is a few hundred signals a month at most. Budget target: under 170 signals per active user per month.
- `AnalyticsThrottle` (UserDefaults-backed, injected `Clock`): events marked *daily* in section 5 are sent at most once per local calendar day per (event, dedup key). Events marked *once* are sent once per install (milestones). Others are per occurrence but are rare by nature (show start/end, import, report).
- The throttle state is local only and is cleared when analytics consent is revoked.

### 3.5 Why bug reports bypass the Sentry SDK *(B-24: decided)*

R22 requires the preview to show **everything** the report sends. `SentrySDK.capture(feedback:)` attaches the SDK scope to the feedback event (contexts, tags, breadcrumbs, user/installation id, release, device data), which the preview would not show, and it needs a started SDK, which crash consent may have declined. Its delivery is also fire-and-forget through the SDK's disk cache, so the form could not tell "sent" from "queued", and the offline fallback would never trigger.

So `SentryEnvelopeFeedbackSender` posts the report itself to the project's envelope endpoint derived from the DSN (`https://<host>/api/<project-id>/envelope/`, header `X-Sentry-Auth: Sentry sentry_version=7, sentry_key=<public key>, sentry_client=segue-feedback/<version>`), with one `feedback` item and one `attachment` item per attached file. It is still Sentry User Feedback (R23/R24): reports land in Sentry's User Feedback view with attachments. The envelope bytes are built by `FeedbackReportBuilder` from the same `FeedbackReport` value the preview renders, and the preview lists every field and every attachment byte-for-byte. Step 1 of the session verifies the current feedback item shape against Sentry's protocol docs (https://develop.sentry.dev/sdk/data-model/envelope-items/ and the sentry-cocoa source of `SentryFeedback.serialize()`) before writing the builder; if the endpoint rejects it, stop and ask (do not silently fall back to the SDK path).

Consequence: bug reports work with crash reports declined, need no SDK, get a real HTTP status (2xx = sent; offline/5xx = fallback offered), and nothing the user did not see is sent.

### 3.6 Breadcrumbs

Sentry automatic breadcrumbs are turned off (6.2). The only breadcrumbs are `Breadcrumb` values the hub derives from `AnalyticsEvent` (category `segue`, message = the event name, data = the same allowlisted params) plus app lifecycle crumbs (`app.launched`, `app.willTerminate`, `show.stage.entered`, `show.stage.exited`). They are recorded only while crash consent is granted, independent of analytics consent (they never leave the Mac unless a crash report is sent). `SentryScrubber.beforeBreadcrumb` drops any breadcrumb whose category is not `segue` (defence in depth if an SDK update adds an automatic source).

### 3.7 Vendor configuration (not secret)

- `Project.swift` gets constants filled after [RYAN] steps 1-2: `let sentryDSN = "..."` (one Sentry project for both flavours; the environment tells them apart), `let telemetryDeckAppIDAppStore = "..."`, `let telemetryDeckAppIDPersonal = "..."` (the separate `Segue Personal` app, *A61*), `let telemetryDeckNamespace = ""` (empty unless the TelemetryDeck dashboard shows an organisation namespace, see 3.9). They become per-target build settings `SEGUE_SENTRY_DSN`, `SEGUE_TELEMETRYDECK_APP_ID` (the App Store target gets the App Store ID, the Personal target the Personal ID) and `SEGUE_TELEMETRYDECK_NAMESPACE` (in `Project.swift`, not an xcconfig: xcconfig treats `//` in the DSN as a comment).
- WS1's explicit Info.plist dictionary gains `SegueSentryDSN = $(SEGUE_SENTRY_DSN)`, `SegueTelemetryDeckAppID = $(SEGUE_TELEMETRYDECK_APP_ID)` and `SegueTelemetryDeckNamespace = $(SEGUE_TELEMETRYDECK_NAMESPACE)`.
- `VendorConfig.load(from: Bundle.main)` returns nil for an empty or malformed DSN or App ID; `ServicesWiring` then uses Null adapters and the Privacy pane shows "Analytics and crash reporting are not part of this build" instead of toggles that do nothing (keep status truthful). With the A61 ruling this only happens in Debug builds without `-SegueServicesLive`.
- A DSN and a TelemetryDeck App ID are designed to ship in client binaries (Sentry: "DSNs are safe to keep public", https://docs.sentry.io/concepts/key-terms/dsn-explainer/; TelemetryDeck's ingest API takes the App ID in the request body with no other credential, 3.9). Nothing secret is in the repo; the Sentry auth token for dSYM upload lives only in 1Password (6.5).
- WS1 `verify-archive` gains check 14: the archived app's Info.plist has a non-empty `SegueSentryDSN` matching `^https://[0-9a-f]+@[a-z0-9.-]+/[0-9]+$` with a host ending in `.sentry.io` and not containing `.de.` (US region, R33), a `SegueTelemetryDeckAppID` in UUID form equal to `telemetryDeckAppIDAppStore`; `nm` on the binary shows `SentrySDK` and `TelemetryDeckIngestSink` symbols and no `TelemetryDeck.TelemetryDeck` / `TelemetryClient` module symbols (the SDK must not be linked, R34).

### 3.8 Swift 6 strict concurrency

- Ports, `AnalyticsSignal`, `Breadcrumb`, `FeedbackReport`, `FeedbackPayload`, `ConsentState` are `Sendable` value types or `final class: Sendable` with `let`s / `Mutex`.
- `ServicesHub` is nonisolated and lock-based (`Mutex`), never an actor, so `record` stays synchronous from `@MainActor` code.
- `VendorServices` compiles in Swift 6 language mode with complete checking and warnings as errors (add `VendorServices` to `Tuist/Package.swift` `targetSettings` like the other first-party targets). Import Sentry with `@preconcurrency import Sentry` only if the compiler demands it, with a comment saying which diagnostic it silences. Never use `nonisolated(unsafe)` on our own state.
- `TelemetryDeckIngestSink` is `final class: AnalyticsSink, Sendable`; its mutable state (queue, backoff, session ID, in-flight task) lives in a private `actor IngestQueue`. `send(_:)` is nonisolated and synchronous: it hands the signal to the actor through an `AsyncStream` continuation, like `DiagnosticLog`.
- `SentryOptions` is a non-Sendable ObjC class: configure it only inside the `SentrySDK.start { options in }` closure; never store it.
- `beforeSend` / `beforeBreadcrumb` run on whatever thread captured the event (https://docs.sentry.io/platforms/apple/configuration/filtering/). They call `SentryScrubber` static functions that are pure (no captured state, no actor hops, no locks beyond the hub's `Mutex` read of the "revoked" flag).
- `SentrySDK.start` is called on the main actor (`ServicesHub.apply` hops to `MainActor.run` for that call only).
- `MetricKitCollector` is `final class: NSObject, MXMetricManagerSubscriber, Sendable` with only `let` properties; its `didReceive(_:)` (called on a MetricKit background queue) hands the JSON to an actor `DiagnosticStore`.
- `DiagnosticLog` is an `actor` with a nonisolated synchronous `log(...)` entry point that enqueues into an `AsyncStream` continuation, so call sites never `await`.

### 3.9 TelemetryDeck ingest client *(A6, R34)*

Why our own client: the TelemetryDeck SwiftSDK attaches ~40 default parameters to every signal (time zone, screen resolution, colour scheme, accessibility settings, model name and more; `DefaultSignalPayload.parameters` in `Sources/TelemetryDeck/Signals/Signal.swift`, SwiftSDK 2.14.2) with no API to remove them. A ~200-line client keeps "closed vocabulary" and "coarse country" literally true and removes a dependency.

Verified 2026-10-17 against the current docs and the SwiftSDK 2.14.2 source (the reference implementation we mirror):
- API docs: https://telemetrydeck.com/docs/ingest/v2 (endpoint, body), https://telemetrydeck.com/docs/ingest/default-parameters/ (parameter names, reserved parameters). v1 is deprecated (https://telemetrydeck.com/docs/ingest/v1/); do not use it.
- SDK source: https://github.com/TelemetryDeck/SwiftSDK/blob/2.14.2/Sources/TelemetryDeck/Signals/SignalManager.swift (`getServiceUrl`, `send`, response disposition, backoff), `.../Helpers/CryptoHashing.swift` (user hash), `.../TelemetryClient.swift` (`transmitInterval` 10 s, `maxBackoffInterval` 300 s, `TelemetryDeck.Session.started`), `.../Signals/SignalCache.swift` (at most 100 signals per request).

**Request.**
- `POST https://nom.telemetrydeck.com/v2/` (or `https://nom.telemetrydeck.com/v2/namespace/<namespace>/` when `SegueTelemetryDeckNamespace` is non-empty; the docs show the namespace form, the SDK uses the bare `/v2/` when no namespace is configured; [RYAN] 1.3 records which applies).
- Headers: `Content-Type: application/json; charset=utf-8`. No auth header and no signing: the API identifies the app by `appID` in the body only. Requests go through an ephemeral `URLSession` (`URLSessionConfiguration.ephemeral`, no cookies, no URL cache, `httpAdditionalHeaders` empty, 15 s timeout).
- Body: a JSON **array** of signal objects, at most 100 per request. Each object has exactly these keys, nothing else:

| Key | Value |
|---|---|
| `appID` | `VendorConfig.telemetryDeckAppID` (App Store or Personal app) |
| `clientUser` | lowercase hex SHA-256 of `installID + salt` (same construction as SDK `CryptoHashing.sha256(string:salt:)`). `installID` is a random UUID created when analytics consent is granted and stored under `UserDefaults` key `analytics.installID`; `salt` is a fixed 64-character random string committed as `TelemetryDeckIngest.salt`. TelemetryDeck salts and hashes it again on the server. |
| `sessionID` | one random UUID per launch (macOS SDK behaviour: a new session per launch), created when the sink is constructed |
| `type` | the rendered signal name (`Segue.<Area>.<event>`, section 5) or `TelemetryDeck.Session.started` |
| `isTestMode` | `true` for TestFlight builds (`AppTransaction` environment sandbox) and `-SegueServicesLive` Debug runs *(B-25)*, else `false` (Personal uses its own app, so it is real data there) |
| `payload` | flat JSON object of strings: the event's `segue.*` params plus exactly the five allowed context keys below |

Allowed context keys (names from the default-parameters page; every value passes the section 5 value regex):
- `TelemetryDeck.Device.operatingSystem` = `macOS`
- `TelemetryDeck.Device.systemMajorMinorVersion` = e.g. `26.6`
- `TelemetryDeck.AppInfo.version` = `CFBundleShortVersionString` (e.g. `0.5`)
- `TelemetryDeck.AppInfo.buildNumber` = `CFBundleVersion`
- `TelemetryDeck.UserPreference.region` = `Locale.current.region?.identifier` (two-letter country, e.g. `US`; omitted when nil). This is the "coarse country" of R26; TelemetryDeck derives nothing from the IP for app signals.

Not sent, ever: `floatValue`, `receivedAt` (server-assigned), model name, architecture, time zone, screen data, language, locale, colour scheme, accessibility settings, run context, SDK name. The payload is built by one function, `IngestBody.make(signal:context:)`, whose output keys are checked against the allowlist in a test (14.2-9).

**Sessions.** On construction (that is, at launch when consent is already granted, or right after a grant) the sink enqueues one `TelemetryDeck.Session.started` signal carrying only the five context keys, mirroring the SDK (`TelemetryClient.swift` sends it at each new session), so TelemetryDeck's built-in user, session and retention insights work. It counts toward the budget (about 30/month for a daily user).

**Batching and timing.** Signals go into the actor's in-memory queue. A send is attempted 10 s after the first signal of an empty queue arrives, then every 10 s while signals remain, each request popping up to 100. On `NSApplication.willTerminateNotification` the queue is written to disk (no last-second network call). On launch with consent granted, the disk queue is loaded and sent with the first batch.

**Responses** (same disposition as SDK `SignalManager`): 2xx = done; 400, 401, 403, 404, 413, 422, 501, 505 = drop the batch (log `analytics.dropped status=<code>` to `DiagnosticLog`, never retry a request the server rejected); anything else, a transport error or `NWPathMonitor` offline = put the batch back and retry with exponential backoff `min(10 s x 2^failures, 300 s)`.

**Offline queue.** `Application Support/<bundle id>/Analytics/queue.json` (JSON array of the exact request objects, written atomically). Cap 1,000 signals, oldest dropped first (several weeks of normal use); signals older than 30 days are dropped on load. The file only exists while analytics consent is granted.

**Shut down** (`shutDown(discardingQueue: true)`, on revoke): cancel the in-flight `URLSessionTask`, invalidate the session, clear the in-memory queue, delete `queue.json`, delete `analytics.installID` (a later re-grant starts a fresh, unlinkable identity). No final flush.

---

## 4. Consent model

### 4.1 State

```swift
public struct ConsentState: Codable, Sendable, Equatable {
    public enum Decision: Codable, Sendable, Equatable { case undecided, granted(Date), declined(Date) }
    public var analytics: Decision = .undecided
    public var crashReports: Decision = .undecided
    public var version = 1   // bump when what is collected changes materially -> re-ask
}
```

- Stored by `ConsentStore` (`@MainActor @Observable`, same pattern as `LiveSettingsStore`) as JSON under `UserDefaults` key `privacy.consent` in the app's own container. Test runs use the test defaults suite, so `-SegueResetState YES` resets consent too.
- **`ConsentStore` is the single store and the only writer of consent in the app** *(I-1)*. WS2b has no `PrivacySettingsStore`, no `privacy.analytics` / `privacy.crashReports` keys, no Privacy view and no upgrader consent flow of its own; it embeds WS3's views and calls WS3's API (4.4). Every write, including tests and launch presets, goes through `ConsentStore.set(_:for:source:)` or `ConsentStore.resetToUndecided()`.
- Stored `version` lower than the app's current version is treated as undecided for both toggles (the prompt reappears); that is the only way a decision is ever re-asked.
- Every change calls `ServicesHub.apply(_:)` and logs `consent.changed` to `DiagnosticLog` (booleans only).

### 4.2 What happens at launch and on first run

1. `SegueApp.init` builds `ServicesHub` with the stored consent. Undecided or declined: Null adapters; zero vendor code runs; zero network.
2. If either toggle is undecided, the consent prompt must be shown once the main window is up, the library state has settled (not `.starting`), no show is on stage or starting, and no crash-resume prompt is pending. Who shows it is defined in 4.4.
3. The prompt offers, for each toggle separately, two equal-weight choices (same button style and size, neither default, neither preselected, neither in accent colour): "Share usage analytics": **Don't Share** / **Share**; "Send crash reports": **Don't Send** / **Send**. Each row has one plain sentence of what it sends and a "What's sent" disclosure listing the section 5 events or the section 6 crash data. A "Privacy Policy" link (`SegueLinks.privacy`) sits at the bottom. **Continue** enables when both rows are answered. There is no close button; Esc does nothing.
4. If the app quits before Continue, both stay undecided (nothing sent) and the prompt reappears next launch. "Asked once" (R26) means once until answered.
5. The first analytics signals after a grant are `TelemetryDeck.Session.started` (3.9) and `Segue.Privacy.analyticsEnabled` (source = `welcome`, `prompt` or `settings`); nothing is back-filled from before the grant.
6. Placement *(A10)*: on a new install the choice is the **last page of WS2b's Welcome flow** (after the library is chosen and the Welcome library seeded), so a reviewer sees the library first. Upgrading installs (any build from before WS3, including TestFlight builds, and a Personal container that already finished onboarding) start undecided and get WS3's standalone `ConsentSheet` on next launch, never the Welcome flow. Ryan's old `dev.ryandsilva.segue` container is moved aside before the TestFlight install (R40), so that run is a true new install.

Copy (final; WS4's home and privacy copy say Segue asks two separate questions, *I-7*):
- Title (sheet only): "Help improve Segue". Intro: "Two separate choices. Segue works the same either way, and you can change them any time in Settings > Privacy."
- Row 1 "Share usage analytics": "Anonymous counts of which features you use, your app and macOS version and your country. Never your songs, lyrics, titles, setlists or file names." Buttons **Don't Share** / **Share**.
- Row 2 "Send crash reports": "If Segue crashes or freezes, send the technical report (code locations, Mac model, macOS version) to help fix it. Never your songs or files." Buttons **Don't Send** / **Send**.
- Footer: "Bug reports are separate: they are sent only when you press Send, after you see everything." plus the "Privacy Policy" link.

### 4.3 Settings > Privacy (revocation)

`PrivacySettingsView` (WS3 owns its content, *I-1, I-6*). WS2b's Settings host (`SegueSettingsView.swift`, panes General, Appearance, Live, Privacy, Data) shows it unchanged as the Privacy pane; WS3 adds its tab to whichever host exists when WS3 lands (today's `TabView` beside "Live", or WS2b's host).
- Two toggles bound to `ConsentStore`, labelled exactly "Share usage analytics" and "Send crash reports" (undecided shows as off; the first change from undecided records a decision with source `settings`). Each has its "What's sent" disclosure.
- Turning a toggle **off** takes effect immediately: the hub swaps in the Null adapter before the toggle animation ends, then shuts the vendor down discarding its queue (TelemetryDeck: in-flight request cancelled, `queue.json` and `analytics.installID` deleted, 3.9; Sentry: drop flag set so `beforeSend` returns nil, the SDK's cached envelopes deleted, `SentrySDK.close()`, see 6.4). A caption then reads:
  - Analytics *(A4, R32)*: "Segue has stopped sending usage analytics and deleted anything waiting to be sent. Analytics already sent are anonymous and TelemetryDeck keeps them with no fixed deletion date. The install identifier is hashed on this Mac and again by TelemetryDeck, so they cannot be traced back to you or singled out for deletion. Questions: segue@ryandsilva.dev."
  - Crash reports: "Segue has stopped sending crash reports and deleted any waiting to be sent. Reports already sent are kept by Sentry for 30 days. To have them deleted sooner, email segue@ryandsilva.dev with your Diagnostics ID: `<installationID>` [Copy]." Ryan deletes them by searching `user.id:<id>` in Sentry (section 11).
- Turning crash reports back **on** in the same session, when the pinned SDK cannot restart after `close()` (6.4), shows the caption *(A11)*: "Crash reporting starts the next time you open Segue." Analytics re-enable immediately (a new sink, a new install identifier).
- Links: "Privacy Policy" (`SegueLinks.privacy`) and "What Segue collects" (`SegueLinks.privacy` + `#usage-statistics`). No Terms link (R7 scopes the terms to the website, *I-6*). A one-line note: "Bug reports are sent only when you press Send, and you see everything first."
- If `VendorConfig` is missing (Debug without `-SegueServicesLive`), the pane shows "Analytics and crash reporting are not part of this build" and no toggles. Both Release flavours have a config *(A61)*.

### 4.4 Contract with WS2b's Welcome sheet

WS3 provides, WS2b consumes *(A10, I-1, B-22)*:
- `ConsentChoiceView(store: ConsentStore, source: .welcome)`: the self-contained two-row choice from 4.2 step 3 with the 4.2 copy (no window chrome, no Continue button) plus `var isComplete: Bool` for WS2b's Continue gating.
- `ConsentStore.needsPrompt: Bool` (either toggle undecided or version outdated); WS2b's resume logic uses it.
- `ConsentStore.resetToUndecided()`: used by WS2b's Settings > Data > "Reset All Settings..." (it sets both decisions back to undecided, which also shuts both vendors down through `ServicesHub.apply`, and the prompt reappears at next launch through `ConsentSheet`).
- `ConsentSheet`: the same view wrapped with title "Help improve Segue", Continue, sized 480 pt wide; used for upgraders and whenever the Welcome flow does not run.
- `PrivacySettingsView`: the whole Privacy pane (4.3).
- The `source` values double as the `segue.source` parameter of `Segue.Privacy.analyticsEnabled` (WS2b's old `via` field maps here: onboarding = `welcome`).
- Launch preset `-SegueConsent <undecided|granted|declined|analyticsOnly|crashOnly>` (Debug only): WS5's composite `-SegueScreenshotLibrary YES` applies `-SegueConsent declined` *(I-4)*.

WS2b must:
1. Include `ConsentChoiceView` as the **last page** of the first-run Welcome flow, after the library is created and the Welcome library seeded, and not let the flow finish while `isComplete == false`.
2. Never show it on stage, during a show start, or over a crash-resume prompt (same rules as 4.2 step 2).
3. Expose `isPresentingWelcome: Bool` on whatever model drives the Welcome flow.
4. Write no consent state of its own.

WS3 itself:
- `SegueRootView` presents `ConsentSheet` when `consent.needsPrompt && !welcome.isPresentingWelcome && !app.isPerforming && app.state is .ready or .needsLibrary` and no other sheet is up. Until WS2b lands, `isPresentingWelcome` is a constant `false`, so the standalone sheet covers first run too (the only difference after WS2b: on a brand-new install the choice appears inside the Welcome flow instead of as a separate sheet).
- Every combination is covered by E2E (14.3).

---

## 5. Event vocabulary (closed)

Rules enforced by code and tests:
- `AnalyticsEvent` is an enum; every associated value is an enum, a `Bool`, or a bucket type. There is **no `String` associated value anywhere**, so titles, lyrics, artist names, file or folder names, setlist names, venues, Shortcut names, search queries and error messages cannot be expressed. Errors are reported as `ErrorCode` enum cases only.
- Signal names: `Segue.<Area>.<event>`; parameter keys: `segue.<camelCase>`; every rendered value matches `^[A-Za-z0-9+<>._-]{1,24}$` (test 14.2-3).
- Counts are sent only as buckets:
  - `SongBucket`: `0`, `1-9`, `10-49`, `50-99`, `100-249`, `250-499`, `500-999`, `1000+`
  - `SmallBucket` (setlists, gigs, files in an import, songs in a show): `0`, `1`, `2-4`, `5-9`, `10-19`, `20-49`, `50+`
  - `DurationBucket` (shows): `<15m`, `15-30m`, `30-60m`, `60-90m`, `90-120m`, `120m+`
  - `DaysBucket` (since first launch): `0`, `1`, `2-6`, `7-13`, `14-29`, `30-89`, `90+`
- Context: every signal also carries exactly five context keys added by our ingest client (3.9): OS name, OS major.minor version, app version, build number and region. Nothing else: no time zone, screen data, model, language or accessibility settings *(A6)*.
- Country: TelemetryDeck derives **no** country from IP for app signals and never stores IPs (https://telemetrydeck.com/docs/guides/privacy-faq). The coarse country is `TelemetryDeck.UserPreference.region`, which our client fills from the Mac's region setting (two-letter code). It is declared as Coarse Location on the label anyway *(A8, 10.2)*.
- Session signals: our client sends one `TelemetryDeck.Session.started` per launch (3.9), carrying only the context keys. It is row 0 and powers DAU/WAU/MAU, sessions and retention in the TelemetryDeck dashboard.

| # | Signal | Params | When | Throttle | Answers |
|---|---|---|---|---|---|
| 0 | `TelemetryDeck.Session.started` | context keys only | launch (or grant) | once per launch | Growth: DAU/WAU/MAU, sessions; Retention: TelemetryDeck retention insight over the hashed user |
| 1 | `Segue.Privacy.analyticsEnabled` | `segue.source`: `prompt`, `welcome`, `settings` | right after the grant | per occurrence | Opt-in volume by entry point (opt-outs are invisible by design) |
| 2 | `Segue.App.launched` | `segue.daysSinceFirstLaunch` (DaysBucket), `segue.flavor` (`appStore`, `personal`; Personal also goes to its own TelemetryDeck app, *A61*), `segue.libraryState` (`open`, `chooser`, `accessLost`) | launch, after library resolves | daily | Retention cohorts on our own day buckets; how often access is lost |
| 3 | `Segue.Library.snapshot` | `segue.songs` (SongBucket), `segue.setlists` (SmallBucket), `segue.gigs` (SmallBucket), `segue.welcomeSongsLeft` (`none`, `some`, `all`), `segue.customShapes` (Bool), `segue.noTempo` (SongBucket: songs without a `{tempo}`, P8-8) | after the library opens | daily | Library size distribution; whether people keep or delete the Welcome library; diagram customisation |
| 4 | `Segue.Library.created` | `segue.location` (`suggestedMusicFolder`, `otherFolder`, `existingLibrary`) | library chosen | per occurrence | Onboarding path |
| 5 | `Segue.Song.created` | `segue.source` (`newSong`, `import`), `segue.nearDuplicate` (Bool: a created song carried the "looks like a song in your library" warning, from a paste or an import, R163) | each new song | daily per source and flag | Writing vs importing; how often pastes repeat library songs |
| 6 | `Segue.Song.imported` | `segue.method` (`dragDrop`, `fileMenu`, `openWith`), `segue.files` (SmallBucket), `segue.outcome` (`all`, `partial`, `none`), `segue.nonUTF8` (Bool), `segue.nearDuplicate` (Bool: at least one imported song carried the "looks like a song in your library" warning, P8-1) | each import operation | per occurrence | Import usage and failure rate; encoding problems; how often imports repeat library songs |
| 7 | `Segue.Song.deleted` | `segue.count` (SmallBucket) | each Delete Song | daily | Churn of content |
| 8 | `Segue.Feature.used` | `segue.feature` (see list below), `segue.context` (`library`, `editor`, `stage`, `builder`, `settings`) | first use of that feature in that context each day | daily per (feature, context) | **Which features to focus on**: daily users per feature |
| 9 | `Segue.Editor.opened` | `segue.mode` (`visual`, `text`) | editor opened | daily per mode | Visual vs text editor adoption |
| 10 | `Segue.Setlist.created` | `segue.source` (`new`, `duplicate`, `welcome`) | each | daily per source | Setlist adoption |
| 11 | `Segue.Show.started` | `segue.kind` (`gig`, `rehearsal`), `segue.songs` (SmallBucket), `segue.resumed` (Bool), `segue.shortcutsOn` (Bool) | stage entered | per occurrence | **Live mode usage**; gig vs rehearsal; Gig Mode Shortcut adoption |
| 12 | `Segue.Show.ended` | `segue.kind`, `segue.duration` (DurationBucket), `segue.played` (SmallBucket), `segue.skipped` (SmallBucket), `segue.requestsUsed` (Bool), `segue.autoScrollUsed` (Bool), `segue.reordered` (Bool), `segue.endedBy` (`endShow`, `quit`, `closedOnRelaunch`) | show finished | per occurrence | Real gig length and set size; which stage aids are used |
| 13 | `Segue.Milestone.reached` | `segue.milestone` (`firstSong`, `firstImport`, `firstSetlist`, `firstRehearsal`, `firstGig`, `firstCompletedGig`, `tenSongs`, `fiftySongs`), `segue.daysSinceFirstLaunch` (DaysBucket) | first time only | once | **Activation funnel**: install -> song -> setlist -> gig |
| 14 | `Segue.Help.opened` | `segue.item` (`help`, `keyboardShortcuts`, `whatsNew`, `reportProblem`, `requestFeature`, `privacyPolicy`, `terms`) | menu item chosen | daily per item | Help demand; board traffic |
| 15 | `Segue.Feedback.sent` | `segue.transport` (`sentry`, `email`, `file`), `segue.logs` (Bool), `segue.metricKit` (Bool), `segue.song` (Bool), `segue.email` (Bool) | report sent | per occurrence | Bug report volume and fallback rate |
| 16 | `Segue.Error.occurred` | `segue.code` (`ErrorCode`: `libraryAccessLost`, `libraryOpenFailed`, `indexRebuildFailed`, `saveConflict`, `saveFailed`, `importFailed`, `showStartFailed`, `showResumeFailed`, `shapeLibraryUnreadable`, `bindingsUnreadable`, `sectionNoteGone` (P3-17), `soundBankLoad` (P8-6: the bundled sound bank failed to load and a fallback played, once per launch), `other`) | an error surfaced as a `UserMessage` / alert | daily per code | Error rates without crash consent |
| 17 | `Segue.Search.performed` *(A7)* | `segue.context` (`library`, `stage`, `builder`), `segue.matchTier` (`exact`, `spellingVariant`, `looseVariant`, `fuzzy`, `none`), `segue.results` (SmallBucket) | a search's results are shown (after the as-you-type debounce settles) | daily per (context, matchTier) | **Romanized-Hindi search hits**: how often a search finds songs only through spelling-variant normalization (`spellingVariant` / `looseVariant`) versus exact text; how often nothing is found |
| 18 | `Segue.Editor.chordPalette` *(A7)* | `segue.action` (`armed`, `placed`), `segue.chords` (SmallBucket, palette size when shown) | a palette chip is armed, and when an armed chord is placed into the song | daily per action | **Chord palette use**: daily users who arm a chord, and how many actually place one |
| 19 | `Segue.AI.pasteFinished` (phase 3, R74, R98; `docs/phases/3-ai-entry-and-assistant.md` section 11) | `segue.source` (`clipboard`, `newSong`, `emptyState`, `listPaste`, `fileTxt`, `fileCrd`, `fileCho`: an already-ChordPro file reviewed because it looks like a library song, P8-1), `segue.provider` (`mlx`, `fm`, `none`), `segue.fallback` (`none`, `aiOff`, `notInstalled`, `fmOff`, `fmNotReady`, `fmIneligible`, `unsupportedLang`, `guardrail`, `decoding`, `overBudget`, `busy`, `timeout`, `other`), `segue.latency` (`none`, `<1s`, `1-3s`, `3-10s`, `10-30s`, `30s+`), `segue.outcome` (`accepted`, `cancelled`, `unticked`: a batch file left out), `segue.correction` (`none`, `small`, `medium`, `large`: AI-touched labels and metadata changed between proposal and Accept), `segue.romanHindi` (Bool: the converter's romanized-Hindi detection fired) | a paste or reviewed file is accepted, cancelled or left out | per occurrence | AI paste quality: provider mix, fallback reasons, latency, how much people correct |
| 20 | `Segue.AI.modelDownload` | `segue.result` (`completed`, `cancelled`, `network`, `checksum`, `disk`, `other`), `segue.kind` (`curated`, `custom`), `segue.duration` (`<1m`, `1-5m`, `5-15m`, `15-60m`, `60m+`), `segue.ramUnder16` (Bool) | a model download finishes or stops | per occurrence | Download success rate and time; low-RAM Macs |
| 21 | `Segue.AI.assistantUsed` | `segue.context` (`builder`, `library`, `stage`), `segue.lexiconChips`, `segue.suggestedShown`, `segue.suggestedAccepted` (SmallBucket each: chips from the lexicon, model-suggested chips shown and accepted), `segue.provider` (`mlx`, `fm`, `none`), `segue.rebuilt` (Bool: the set was rebuilt from the same request), P8-8's `segue.artistChips` and `segue.albumChips` (Bools: the request held an artist chip, "by arijit", or a Movie / Album chip, "from kalank", included or excluded) and `segue.leftOut` (SmallBucket: songs the build left out under a length target because they have no time, R172) | a set is built or rebuilt from a request | per occurrence | Set assistant use; model help vs the lexicon; how often a length target drops songs for missing tempos |
| 22 | `Segue.AI.smartFilterUsed` | `segue.action` (`created`, `applied`, `assistantInput`), `segue.conditions` (SmallBucket) | a smart filter is created, applied, or fed to the assistant | daily per action | Smart filter adoption and complexity |
| 23 | `Segue.Notes.edited` (P3-17) | `segue.action` (`add`, `move`, `toggle`, `delete`), `segue.kind` (`chart`, `stage`, after the edit), `segue.placement` (`single`, `every`, `instance`, `repeat`), `segue.entry` (`bandMenu`, `badge`, `sheet`, `slash`, `library`), `segue.repeatHint` (Bool) | a section note added, moved between instances, toggled between chart and stage, or deleted | daily per (action, kind, placement) | **Per-instance notes**: whether people place notes per instance at all, how often the `{chorus}` repeat limit bites (`repeat` + `repeatHint`), which entry point is used |
| 24 | `Segue.Setlist.composed` and `Segue.Setlist.composerSession` (P8-5, two signals) | `composed`: `segue.action` (`song`, `break`, `alreadyInSet`, `noMatch`), `segue.tier` (`exactTitle`, `titlePrefix`, `titleWords`, `fuzzyTitle`, `firstLine`, `artist`: the line named an artist (P8-8), `none`), `segue.form` (`original`, `normalized`, `loose`, `none`), `segue.alternative` (Bool: a non-first candidate was accepted), `segue.key` (Bool: a key token was applied), `segue.entry` (`shortcut`: focused by ⌘L, `click`), `segue.artistWords` (Bool: trailing words naming the song's artist qualified the title, P8-8). `composerSession`: `segue.songs` (SmallBucket, songs added while focused), `segue.cycles` (SmallBucket, alternative presses) | `composed`: a Return in the set composer (one per outcome). `composerSession`: the composer loses focus after at least one Return | `composed`: daily per (action, tier, alternative). `composerSession`: per occurrence (only sessions that added a row) | **Set composer**: is it used, and for whole sets or one-off adds; how often romanized Hindi variants (`normalized` / `loose`), fuzzy and first-line matches carry it; how often the first guess is wrong (`alternative`); how often the duplicate block and no-match bite; is the key token used |
| 25 | `Segue.Bass.walkUpPicked` (P8-4b; row 24 is the set composer's) | `segue.kind` (`hold`, `scaleWalk`, `scaleChrom`, `diatonicNeighbour`, `chromBelow`, `chromAbove`, `fifth`, `doubleChromAbove`, `octavePickup`), `segue.rank` (`top`: the suggestion, `alternate`: another option, `nothing`: "Nothing here", `reset`: back to the suggestion, with the suggestion's kind), `segue.genre` (the song's feel: `pop`, `rock`, `worship`, `country`, `bollywood`) | a choice in the walk-up picker (editor or library) | daily per (kind, rank, genre) | **Walk-ups**: which kinds musicians keep, replace or reject per feel (research section 7.5), so the ranking weights can be tuned |
| 26 | `Segue.Bass.fillSaved` (P8-7d) | `segue.family` (`walk`, `pickup`, `run`, `triplet`, `octave`, `push`, `scratch`), `segue.rank` (`a`, `b`, `c`, `d`, `more`, `scratch`), `segue.edited` (Bool: changed from the candidate or saved fill it started from), `segue.view` (`fretboard`, `pianoRoll`, `both`, `none`: where notes were edited), `segue.chords` (SmallBucket: the span, landing included), `segue.keyChange` (Bool: the span crosses a key change), `segue.genre` (the song's feel: `pop`, `rock`, `worship`, `country`, `bollywood`), `segue.shows` (`all`, `only`, `last`), `segue.estimated` (Bool: saved over chord lengths that are the song's rule) | a fill saved in the fill editor (editor or library) | daily per (family, rank, edited) | **Fills**: whether people keep the generated fills or edit them, which families and ranks win per feel (so `FillWeights` can be tuned), whether the piano roll is used, whether key-change fills matter, and whether the chord-length lane is used before fills |
| 27 | `Segue.Timing.tapCaptured` (P8-7) | `segue.mode` (`click`, `free`), `segue.outcome` (`kept`, `discarded`), `segue.chords` (SmallBucket: chords changed), `segue.skipped` (SmallBucket), `segue.tempoSet` (Bool: "Set Song Tempo" pressed) | a Tap Timing review closed with Keep or Discard (editor or library) | per occurrence | **Tap Timing**: whether tapped timings are kept, with or without the click, and how often the derived tempo is written to the song |
| 28 | `Segue.Timing.keyChange` (P8-7) | `segue.action` (`confirmed`: the chip's Insert, `dismissed`: the chip's x, `inserted`: a `{key}` from Insert Key Change Here), `segue.interval` (`halfUp`, `wholeUp`, `other`: from the key in effect) | a key change confirmed, dismissed or inserted (editor) | daily per (action, interval) | **Key-change chip**: a dismissal-heavy rate means the chip fires too often and its margin needs raising |
| 29 | `Segue.Song.artistSplit` (P8-8) | `segue.source` (`paste`, `import`), `segue.parts` (SmallBucket: artists the split made), `segue.separator` (`comma`, `ampersand`, `feat`: "feat.", "ft." or "featuring", `mixed`: more than one), `segue.outcome` (`kept`, `merged`: Keep as one, `edited`: the artists edited by hand) | review Accept, per accepted song whose artist the paste or import split | daily per (source, separator, outcome) | **Artist split**: are R172's splits right, and which separator misfires (a high `merged` rate for `ampersand` means duos and bands) |
| 30 | `Segue.Setlist.timed` (P8-8) | `segue.songs`, `segue.noTempo`, `segue.noChords`, `segue.arranged` (SmallBucket each: song slots, slots with no tempo, with no chords, with an arrangement), `segue.estimatedOnly` (Bool: every known slot time rests on default chord lengths), `segue.target` (`none`, `under`, `within`: inside the assistant's tolerance, `over`) | the builder leaves a setlist with 1+ songs | daily per target (count only, no id) | **Set time**: does timeline time (tempo x played bars) cover real sets, how many songs lack a tempo, do arrangements and chord corrections matter |

`segue.matchTier` is the tier of `LibraryStore.search` (section 2) that produced the **first** result: tier 1 = `exact`, tier 2 = `spellingVariant`, tier 3 = `looseVariant`, tier 4 = `fuzzy`, no results = `none`. To report it without changing callers, `LibraryStore` gains `searchWithTier(query:) -> SearchOutcome` (`records: [SongRecord]`, `firstTier: SearchTier?`; `SearchTier` is a `SegueCore` enum, no strings) and the existing `search(query:)` returns its `.records`, so there is one implementation. The view models that show search results (`LibraryViewModel`, `QuickSearchModel`, the builder's library column) call `searchWithTier` and record row 17. The query itself is never recorded.

`segue.feature` values (`FeatureKey`): `transpose`, `capo`, `nashville`, `diagrams`, `instrumentPiano`, `tuningChange`, `applyTransposeToSource`, `editorModeSwitch`, `search`, `filterChips`, `setlistEdit`, `setlistTarget`, `autoScroll`, `stageSearch`, `playNow`, `requests`, `columnsCycle`, `stageZoom`, `gigLogEdit`, `liveSettings`, `shapeEditor`, `showInFinder`, `undoInBuilder`, `metronome` (the stage metronome switched on, R90, P3-14), P8-8's `songArtists` (a song's artist list changed in the chip field, editor or library), `songAlbum` (a song's Movie / Album set), `artistSplit` (a combined artist chip split with Split) and `tempoFromSet` (a tempo written from the set's no-time list, the assistant's left-out list or Arrange Sections, builder context), P8-2's `sectionJump` (a stage section jump by key or map chip, once per stage session), `sectionLoop` (the rehearsal section loop switched on) and `singleSongRehearse` / `singleSongLive` (a single-song Rehearse or Live session started from the library, one key per kind, R163; they replace P8-2's `singleSongSession`, and `collapseRepeats` was retired with the collapse toggle, R147), and P8-4's `bassProfile` ("I play bass" turned on), `bassNotes` (the bass-note view toggled in the editor or on stage) and `bassNeck` (the stage mini neck shown, once per session), P8-4b's `walkUps` (walk-ups on charts turned on in Settings), `walkUpPick` (a walk-up pick or "Nothing here" saved, editor or library), `songFeel` (a song's walk-up feel set) and R170's `songScale` (a song's scale set, editor or library), with `bassChart` to come with the phase 4 export's "Bass chart" option, P8-6's `hearChord` (a chord heard in the editor or library preview), `walkUpAudition` (a walk-up candidate played in the picker), `playAlong` (play-along started; `stage` only from a rehearsal), `playAlongTiming` (a play-along timing rule or chord length changed), `audioOutput` (a non-default audio output chosen in Settings, never its name) and `chordSoundGuitar` (the chord sound set to clean guitar), P8-7's `timingTap` (a Tap Timing capture kept, editor or library), `chartDirective` (a `{key}`, `{time}` or `{tempo}` inserted from the editor's Insert ... Change Here or the tap review's "Set Song Tempo"), `keyChangeChip` (the "Looks like a key change" chip confirmed, editor), `fillEditor` (the fill editor opened from a span or a saved fill, editor or library), `fillAudition` (a fill candidate or the draft played in it), `fillPianoRoll` (its piano roll used, once per sheet) and `fillTab` ("Fills as tab" turned on: stage `t`, the editor's Bass menu or Settings), and P8-3's `arrangementMode` (a pass's show mode set in Arrange Sections), `arrangementRoadmap` (a typed roadmap committed) and `arrangementRehearse` ("Rehearse this" started from the sheet), all in the `builder` context (chord palette use is row 18, not a feature key, so it is not counted twice). Extending any list is a code change reviewed against these rules; WS2b adds its own (What's New shown, tip shown, review prompt requested) to the same enum under the same rules.

Expected volume for an active gigging user: ~30 daily-throttled feature signals + ~30 launch/snapshot + ~8-10 show signals + ~10-20 search and palette signals + ~30 session signals, roughly 110-170 per month, so the free tier covers about 300-450 monthly opted-in users. Check the TelemetryDeck usage page after the first month.

Emission points: one call per row at the view-model entry points listed in section 2 (`app.services.record(.featureUsed(.transpose, .editor))`), never in views. `AppModel` gets a `services: ServicesHub` reference through `AppDependencies`.

---

## 6. Sentry configuration

### 6.1 Package and pins

- `Packages/SegueVendorServices/Package.swift` (swift-tools 6.2, macOS 26): depends on `../SegueCore` (product `SegueCore`), `https://github.com/getsentry/sentry-cocoa` **exact** (pin the latest stable at implementation time; research 07 saw 9.30.2 on 2026-10-14, a later research pass saw 9.28.0 listed as stable: check `gh release list -R getsentry/sentry-cocoa` and pin the newest non-prerelease). Same exact pin in `Tuist/Package.swift`. **No TelemetryDeck package** (R34; 3.9 is our own code).
- Sentry product: `SentrySPM` (source build, Sentry's recommended SwiftPM product, https://docs.sentry.io/platforms/apple/install/swift-package-manager). If it fails to build under Tuist with the active Xcode, fall back to the prebuilt static `Sentry` product and note it in the commit. Not `SentrySwiftUI` (deprecated).
- Record the Release-AppStore app size before and after (step 5) in the commit message; see risk R1.

### 6.2 `SentrySDK.start` options (`SentryCrashReporter.start(config:)`)

| Option | Value | Why |
|---|---|---|
| `dsn` | from `VendorConfig` | 3.7 |
| `releaseName` | `<CFBundleIdentifier>@<CFBundleShortVersionString>+<CFBundleVersion>` (`dev.ryandsilva.segue@...` or `dev.ryandsilva.segue.personal@...`) | matches dSYM upload; flavours never share a release |
| `environment` | `production` (App Store), `testflight` (App Store build whose `AppTransaction` environment is sandbox), `personal` (Release-Personal, *A61*), `debug` (`-SegueServicesLive`) | filter test noise; Ryan's own crashes stay out of production views |
| `sendDefaultPii` | `false` (default) | no IP, no user data |
| `enableCrashHandler` | `true` | the point |
| `enableMetricKit` | `true` | R25; default is false (https://docs.sentry.io/platforms/apple/guides/macos/configuration/metric-kit/) |
| `enableMetricKitRawPayload` | `false` | raw JSON is attached only to bug reports, on request (8.3) |
| `enableAppHangTracking` | `true` while the SDK version still recommends it; if the pinned version deprecates it in favour of MetricKit, `false` | hangs on stage matter |
| `enableAutoSessionTracking` | `false` | sessions duplicate TelemetryDeck and would send without analytics consent |
| `enableAutoBreadcrumbTracking` | `false` | auto breadcrumbs record UI/system events we have not vetted (3.6) |
| `enableNetworkBreadcrumbs`, `enableNetworkTracking`, `enableCaptureFailedRequests` | `false` | URLs and headers of our own vendor calls |
| `enableSwizzling` | `false` | nothing left that needs it once the above are off; less surprise |
| `enableFileIOTracing`, `enableUserInteractionTracing`, `enableCoreDataTracing` | `false` | file I/O spans would name library files |
| `tracesSampleRate` / profiling | unset (no tracing) | not needed; quota |
| `enableLogs` | `false` | logs travel only inside bug reports |
| `attachStacktrace` | `true` | stacks have no user content |
| `enableUncaughtNSExceptionReporting` | `true` (macOS: uncaught NSExceptions are otherwise lost) | crash coverage |
| `swiftAsyncStacktraces` | `true` | useful async stacks |
| `maxBreadcrumbs` | `50` | only our own crumbs |
| `beforeBreadcrumb` | `SentryScrubber.breadcrumb(_:)` | drop non-`segue` categories; drop all when revoked |
| `beforeSend` | `SentryScrubber.event(_:)` | 6.3 |
| `maxAttachmentSize` / attachments | no scope attachments on crash events | the only attachments are in user-sent bug reports |

The exact option names are checked against the pinned SDK's `Options.swift` in step 5; an option that no longer exists is dropped and noted, never replaced by a guess.

### 6.3 Scrubbing (`SentryScrubber`, pure, unit-tested as tricky logic)

`event(_:)`:
1. Returns nil when the hub's revoked flag is set (covers anything captured between toggle-off and close).
2. `user`: keep only `id` (the SDK's per-install `installationId`, kept per R25; https://docs.sentry.io/platforms/apple/enriching-events/identify-user/). Clear `ipAddress`, `email`, `username`, `name`, `data`. Never call `SentrySDK.setUser`.
3. Remove `serverName` and the device context `name` key (a Mac's name is often "Ryan's MacBook Pro"); keep model, OS, arch, memory, locale.
4. Replace home-directory paths in every string field we can reach (exception values, messages, frame `filename`/`absPath`, `contexts` values, tags): regex `/Users/[^/\s]+` -> `/Users/<user>`; any path under the library root or `~/Music` -> `<library>/<file>`; anything ending in `.cho` or `.segue.json` -> `<song file>`.
5. Exception `value` strings longer than 200 characters are truncated (NSException reasons can embed data).
6. Drop `request`, `extra` and any `breadcrumbs` entry failing `beforeBreadcrumb`.
7. Drop low-value MetricKit events (CPU exception / disk-write diagnostics with fewer than 3 frames) to save quota (research 07 H.3).

Server-side backstops ([RYAN] step 2): "Prevent Storing of IP Addresses" on, data scrubber on with default scrubbers, plus sensitive fields `title`, `lyrics`, `filename`, `path`, `email`.

### 6.4 Start, stop, restart

- Start only from `ServicesHub.apply` on a transition to crash consent granted. At most once per process.
- Revoke: set revoked flag -> delete the SDK's cached envelope files (locate the cache directory from the pinned SDK's `SentryFileManager` source, inside the app container's `Library/Caches`; keep the `installation.id` file so the Diagnostics ID stays stable per R25) -> `SentrySDK.close()`. Sentry's `close()` otherwise flushes pending events for up to `shutdownTimeInterval` (https://docs.sentry.io/platforms/apple/configuration/draining), which is why the flag and the deletion come first.
- Re-grant in the same process *(A11: decided)*: restarting after `close()` is not documented as supported. Show "Crash reporting starts the next time you open Segue." and start at next launch. Test it in step 5; if restart works cleanly with the pinned version, start immediately instead and drop the caption.

### 6.5 dSYM upload in `make upload`

- Tool: add sentry-cli to `.mise.toml` with an exact version, via mise's GitHub backend: `"github:getsentry/sentry-cli" = "<exact>"` (confirm with `mise ls-remote github:getsentry/sentry-cli`; if the github backend cannot install it, try `aqua:getsentry/sentry-cli`; never Homebrew or npm global). Latest seen: 3.8.0 (https://docs.sentry.io/cli/installation/).
- `.sentryclirc` (tracked, no secrets): `[defaults] org=<org slug> project=segue-macos url=https://sentry.io` (US region, R33).
- `scripts/upload-dsyms.sh <xcarchive>`: `op whoami` (fail fast with "Unlock 1Password, then re-run `make upload-dsyms ARCHIVE=...`"), `export SENTRY_AUTH_TOKEN="$(op read 'op://Private/Segue Sentry/token')"` (env var only, never a file, never echoed), then `mise exec -- sentry-cli debug-files upload --include-sources --wait "<xcarchive>/dSYMs"` (command form per https://docs.sentry.io/platforms/apple/guides/macos/dsym/). `--include-sources` is kept *(A62)*: it sends Segue's own source files for stack context to Ryan's own Sentry account; the App Store archive contains no personal-module code (verify-archive check 2). The script takes any `.xcarchive` or a bare dSYM folder (`DSYMS=<dir>`), so a Release-Personal build can be uploaded the same way (personal-module sources then go to Ryan's own account too, which A61 accepts); how that gets triggered is section 17 question 1. Then `sentry-cli debug-files check` on the app dSYM UUID and print it.
- `scripts/release.sh upload`: after `altool --upload-package` succeeds (and after WS1's local tag), run `scripts/upload-dsyms.sh`. A dSYM failure does not undo the App Store upload: print the retry command and exit 1.
- `Makefile`: `upload-dsyms: ## Upload an archive's dSYMs to Sentry (ARCHIVE=path or DSYMS=dir)`.
- `make check` does not run it (release step only).

---

## 7. Privacy-safe diagnostic log

`Core/Services/DiagnosticLog.swift`. Purpose: give bug reports the previous launches' logs, which `OSLogStore` cannot read in the sandbox (research 07 4.3), without ever writing user content.

- API takes only `StaticString` messages and typed fields:
  ```swift
  log.notice(.library, "opened", ["songs": .bucket(SongBucket(count)), "ms": .int(elapsedMS)])
  enum LogValue: Sendable { case int(Int), bool(Bool), double(Double), token(StaticString),
                            bucket(any LogBucket), error(LoggedError), duration(Duration) }
  ```
  There is no `String` case. `LoggedError(error)` records only `NSError` domain (kept only if it matches `^[A-Za-z0-9_.]{1,64}$`, else `other`) and code, or a `LoggableError.logCode: StaticString` for our own error enums. Never `localizedDescription` (it embeds file names).
- Files: `Application Support/<bundle id>/Logs/segue-0.log` (this launch) ... `segue-3.log` (three launches back). On launch rotate 2->3, 1->2, 0->1, start a new 0. Each file capped at 512 KB; at the cap one `log.truncated` line is written and further lines dropped. Max on disk 2 MB.
- Line format: `2026-10-17T21:03:11.402Z notice library opened songs=50-99 ms=212`. UTC, no host name, no user name.
- Writes go through an `AsyncStream` into the actor, which appends with a `FileHandle` and `synchronize()`s at most every 2 s and on `applicationWillTerminate`. Never on the stage's critical path; a write failure disables the file log for the launch and never surfaces.
- Mirrored to `os.Logger` (subsystem `dev.ryandsilva.segue`, category = log category) with `privacy: .public`, which is safe because only typed values exist.
- Call sites added in WS3 (keep it small): launch (version, build, flavor, OS major), library open/close (bucket, ms), index rebuild (ms, result), show start/end (kind, buckets), every `ErrorCode` surfaced, consent change, report sent (transport), MetricKit payload received (types present).
- Logs exist whatever the consent (they stay on the Mac; they leave only inside a previewed bug report).

---

## 8. Report a Problem and Request a Feature

### 8.1 Hooks

`ServicesWiring` replaces WS2a's defaults:
- `AppHooks.reportProblem` -> `ReportProblemPresenter.present()` (an `@Observable @MainActor` object in `AppDependencies`); `SegueRootView` observes it, brings the main window forward (`openWindow(id: "segue.main")`) and presents `ReportProblemSheet` on it. Never while performing (menus are hidden on stage anyway; the presenter also checks `app.isPerforming` and refuses).
- `AppHooks.requestFeature` -> `WorkspaceActions.open(SegueLinks.feedback)` (`https://segue.ryandsilva.dev/feedback`, which WS4 redirects to the Featurebase board) plus `record(.helpOpened(.requestFeature))`. No web view (research 03 F16). Adapt to WS2a's final `AppHooks` shape if it differs.
- Add `SegueLinks.supportAddress = "segue@ryandsilva.dev"` (WS2a only has the `mailto:` URL) inside `SegueLinks.swift`, the one file allowed to spell the domain.

### 8.2 Sheet layout (native SwiftUI `Form`, 560 pt wide, brand tokens, both appearances)

1. Title "Report a Problem". Subtitle: "Tell us what happened. You will see everything before it is sent."
2. **What happened?** multi-line `TextEditor`, required (Send disabled while empty after trimming), 5,000 character cap with a counter. Autocorrect and spell-check off (romanized Hindi, `docs/decisions.md` Language).
3. **Email (optional)** `TextField`, `.textContentType(.emailAddress)`, validated loosely (`x@y.z`); caption "Only if you want a reply." The field stays *(A9)*; because of it the bug-report data types are declared Linked (10.2).
4. **Attach** (checkboxes):
   - "Recent Segue logs (last 4 launches)" - **on** by default; disabled with "No logs yet" if none.
   - "Latest crash or hang diagnostics (MetricKit)" - **on** by default when a payload exists; otherwise disabled with "None recorded".
   - "Current song file" - **off** by default and reset to off every time the sheet opens (R22). Label shows "(includes lyrics)". Disabled when no song is selected. Attaches the song's `.cho` and its `.segue.json` sidecar, read through the library's file system (security-scoped).
5. Always-included system info (not optional, shown in the preview): app version and build, flavor, macOS version, Mac model identifier (`hw.model`, e.g. `Mac15,3`), CPU architecture, preferred language, library size buckets (songs, setlists, gigs), consent states, `DiagnosticLog` file sizes. No serial numbers, no host name, no user name, no paths.
6. Buttons: **Preview...** (secondary), **Cancel**, **Send** (default; Send opens the preview first if the user has not previewed this exact content, so nothing is ever sent unseen). Link: "Have an idea instead? Request a Feature" (same action as 8.1).

### 8.3 Preview (`ReportPreviewView`, pushed in the same sheet)

- Shows the `FeedbackReport` exactly as `FeedbackReportBuilder` will serialise it: the description, email, every system-info field as label/value rows, then one disclosure group per attachment with its file name, byte size and **full text content** in a monospaced, selectable, scrollable view (logs, MetricKit JSON pretty-printed, song file and sidecar). Nothing is summarised or elided.
- A footer states the destination: "Sent to Sentry (sentry.io, United States), Segue's crash and bug-report service. Kept for 30 days." plus Privacy Policy link.
- The payload is frozen when the preview opens (`FeedbackPayload` value); if the user goes back and changes anything, a new preview is required before Send. The bytes sent are those of the frozen payload (test 14.3-4 compares them).
- Size cap 5 MB total; if over, the log attachments are trimmed to their newest lines and the preview says so.

### 8.4 Sending and fallback

- Send -> `FeedbackSender.send(payload)` with a 20 s timeout and a spinner. Success: sheet shows "Thanks - report sent." with the Sentry event id (copyable) and closes on OK; analytics `Feedback.sent(transport: .sentry)` if analytics consent is granted.
- Failure (`NWPathMonitor` says offline, timeout, non-2xx, or `.notConfigured` in builds without a DSN): the sheet stays, keeps the content, and shows "Couldn't send right now." with:
  - **Email Instead** -> `MailComposer.compose(to: SegueLinks.supportAddress, subject: "Segue <version> (<build>) problem", body: <description + system info as text>, attachments: <the same files written to a temp folder in the container>)` via `NSSharingService(named: .composeEmail)` with `recipients` and `subject` set. Shown only if `canPerform(withItems:)` is true.
  - **Save Report...** -> `NSSavePanel` writes a folder `Segue Report <date>` with `report.txt` and the attachments (works with webmail users and no mail account).
  - **Try Again**.
- "Email Instead" is also always available as a secondary button on the main form (people who prefer email).
- Temp files for email are deleted on next launch (they must outlive the compose window).
- Nothing is queued for later automatic sending: an unsent report only leaves the Mac when the user acts again.

### 8.5 Latest MetricKit payload (local)

`MetricKitCollector` subscribes to `MXMetricManager.shared` at launch regardless of consent (MetricKit delivery is local; storing it is not collection). It keeps only the newest `MXDiagnosticPayload.jsonRepresentation()` at `Application Support/<bundle id>/Diagnostics/latest-diagnostic.json` (overwritten; one file). It leaves the Mac only inside a previewed bug report, or via Sentry's own MetricKit integration when crash consent is on. Sentry and our collector are separate subscribers; MetricKit supports several.

---

## 9. Entitlements and flavours

- Entitlements: WS1 step 1 puts `com.apple.security.network.client` in `App/SegueAppStore.entitlements`, `App/Segue.entitlements` (Release-Personal) and `App/Segue-Debug.entitlements` (Debug-Personal, for `-SegueServicesLive`), and inverts its `verify-appstore` assertion so both flavours must have it *(A61, I-15)*. WS3 depends on that and edits neither the entitlements files nor that assertion. Never `network.server`. WS1's verify-archive check 4 already allows exactly that set.
- **Personal flavour** *(A61: decided)*: links `VendorServices`, same consent UI and flow, Sentry `environment = personal` and `releaseName` with the Personal bundle ID, and the **separate TelemetryDeck app `Segue Personal`** (its own App ID via the per-target build setting, 3.7) so Ryan's own use never mixes with product analytics. Reason: Ryan's daily build exercises the real vendors, crash path and consent flow every day before any TestFlight build, and the personal modules (ML) are where the riskiest code lives. Personal stack traces with personal-module frames go to Ryan's own Sentry account; nothing licence-encumbered is distributed.
- `verify-appstore.sh`: no WS3 changes (the entitlement assertion and personal-module checks are WS1's). WS3's binary checks live in `verify-archive` check 14 (3.7).

---

## 10. Privacy label and data-flow facts

### 10.1 Vendor data handling (verified 2026-10-17 on vendor pages)

This table is the source of WS4's `site.json` vendor values and retention table and of WS5's vendor parameters *(I-8)*. There is no GitHub bridge of any kind (R24).

| Vendor | What it receives from Segue | Identifier | IP | Location | Hosting | Retention | Deletion | Sources |
|---|---|---|---|---|---|---|---|---|
| TelemetryDeck (app analytics, opt-in) | Only section 5 signals with their closed `segue.*` params, plus OS name, OS major.minor version, app version, build number and region (two-letter country), sent by our own ingest client (3.9, R34). No SDK, no other default parameters. | Random per-install ID (new on every grant), SHA-256 hashed with a salt on the Mac and hashed again with TelemetryDeck's salt on the server; "Neither TelemetryDeck nor you can reconstruct the original" | Never stored ("neither in the database nor in log files") | No IP geolocation for app signals; country only from the region parameter | Company in Augsburg, Germany; infrastructure Microsoft (Dublin, EU), Hetzner (Germany), AWS (Seattle, US) per its privacy policy | **TelemetryDeck's default: no fixed deletion date; anonymous data may sit in cold storage for 7-10 years** (privacy FAQ). Stated plainly in the policy (R32). Ryan has asked TelemetryDeck about a shorter period ([RYAN] 1.4); tighten the wording if they offer one. | Not possible per user (the hash cannot be traced back); GDPR questions to datenschutz@telemetrydeck.com | https://telemetrydeck.com/docs/guides/privacy-faq , https://telemetrydeck.com/docs/articles/anonymization-how-it-works/ , https://telemetrydeck.com/docs/ingest/v2 , https://telemetrydeck.com/docs/ingest/default-parameters/ , https://telemetrydeck.com/privacy |
| Sentry (crashes, hangs, MetricKit; opt-in) | Crash/hang/MetricKit events: stack traces, OS, device model, arch, memory, locale, app version, our breadcrumbs | `installationId`, random per install, used as `user.id` (kept, R25) | SDK does not send it by default; project setting "Prevent Storing of IP Addresses" also on | None | **United States** (`sentry.io` US region, chosen at org creation, R33). The policy notes US processing under the EU standard contractual clauses in Sentry's DPA. | 30 days (Developer plan lookback) | Ryan deletes by `user.id:` search on request (email with the Diagnostics ID) | https://docs.sentry.io/platforms/apple/data-management/data-collected/ , https://docs.sentry.io/platforms/apple/enriching-events/identify-user/ , https://docs.sentry.io/security-legal-pii/scrubbing/server-side-scrubbing/ , https://docs.sentry.io/organization/data-storage-location/ , https://sentry.io/pricing/ , https://sentry.io/privacy , https://sentry.io/legal/dpa/ , https://sentry.io/legal/subprocessors/ , https://docs.sentry.io/platforms/apple/data-management/apple-privacy-manifest/ |
| Sentry (bug reports; only on Send) | Exactly the previewed report: description, optional email, system info, chosen attachments (logs, MetricKit JSON, song file) | none (our envelope carries no installation id) | not stored (project setting) | None | United States, as above | 30 days (User Feedback, R24) | Ryan deletes on request (by date and email address) | https://docs.sentry.io/platforms/apple/guides/macos/user-feedback/ , https://sentry.io/pricing/ |
| Featurebase (feature board website) | Nothing from the app: the board is a website opened in the browser. On the site: email of people who sign up or post, IP, browser/device data, cookies (analytics/marketing cookies require consent) | Featurebase account if the visitor signs up | Collected by Featurebase | Featurebase's own | EU primary storage, SCCs for transfers | Board posts kept until deleted by the poster or on request (R32) | Via Featurebase / Ryan as board owner | https://help.featurebase.app/articles/4744036-privacy-policy , https://help.featurebase.app/articles/7608294-billing-and-plans |
| Support email (`segue@ryandsilva.dev`) | Whatever the sender writes, including "Email Instead" bug reports | Sender's address | - | - | Ryan's mailbox | As long as needed to answer, at most 2 years (R32) | On request | - |
| Apple App Analytics / Organizer | Apple-collected; nothing to declare | - | - | - | Apple | Apple | - | https://developer.apple.com/app-store/app-privacy-details/ |
| Cloudflare Web Analytics (website only, R38; WS4 owns it) | **Nothing from the app.** The app never contacts Cloudflare analytics; it only opens site pages in the browser. On the website: cookieless page-view analytics | none | WS4's policy paragraph | - | Cloudflare | WS4 | - | WS4 spec |

WS4's privacy policy must (5.1.1(i), text at https://developer.apple.com/app-store/review/guidelines/): name TelemetryDeck, Sentry and Featurebase as processors offering equal protection; say what each receives (table above, in plain words: for analytics, "which features are used, app and macOS version, and your country", nothing else); say consent is opt-in per toggle, asked as two separate questions, and how to withdraw (Settings > Privacy); state retention per R32 (analytics: TelemetryDeck's default, no fixed deletion date, anonymous; crash and bug reports: 30 days; board posts: until deleted; support email: at most 2 years); say Sentry processes reports in the United States under standard contractual clauses (R33); explain how to request deletion (email with the Diagnostics ID for crash reports; bug reports by date and email address); state that bug reports are sent only on Send after a full preview; say the board is a separate website with its own policy. The website's own Cloudflare Web Analytics paragraph (R38) is about the site, not the app, and must not say the app sends anything to Cloudflare.

### 10.2 App Privacy answers (App Store Connect) - the single source of truth

**This table is canonical** *(I-9)*. WS5 section 6 copies it verbatim (no edits there), `App/PrivacyInfo.xcprivacy` mirrors it (10.3), and WS4's policy is written to match. If anything changes, change it here first, then diff all three before publishing. All rows below are final (A8, A9 decided). Both flavours send the same data types, so the table holds for Personal too.

Apple's rules: SDK-collected data must be declared, and consent does not remove a declaration (https://developer.apple.com/support/app-privacy-on-the-app-store/ ; definitions at https://developer.apple.com/app-store/app-privacy-details/). The bug report fails the optional-disclosure criteria (no account name shown in the form), so it is declared (research 03 8.3).

"Do you or your third-party partners collect data from this app?" **Yes.** Tracking: **No** for every type (no data combined with third-party data for ads; no data brokers; no ATT prompt).

| Data type | Collected by | Purposes | Linked to user | Tracking |
|---|---|---|---|---|
| Usage Data > Product Interaction | TelemetryDeck (our ingest client) | Analytics | No | No |
| Identifiers > Device ID | TelemetryDeck hashed per-install ID; Sentry installation ID (R25) | Analytics; App Functionality | No | No |
| Location > Coarse Location | TelemetryDeck region parameter (country-level, from the Mac's region setting) *(A8: declared, conservative)* | Analytics | No | No |
| Diagnostics > Crash Data | Sentry crashes; MetricKit crash diagnostics in bug reports | App Functionality | **Yes** *(A9)* | No |
| Diagnostics > Performance Data | Sentry hangs / MetricKit; hang diagnostics in bug reports | App Functionality | **Yes** *(A9)* | No |
| Diagnostics > Other Diagnostic Data | System info and logs in bug reports | App Functionality | **Yes** *(A9)* | No |
| User Content > Customer Support | Bug report description | App Functionality | **Yes** *(A9)* | No |
| User Content > Other User Content | Optional attached song file | App Functionality | **Yes** *(A9)* | No |
| Contact Info > Email Address | Optional reply-to email in the bug report | App Functionality | **Yes** | No |

Nine data types. Purposes are exactly as listed: Crash Data is App Functionality only (not Analytics). Device ID is Not Linked (R25).

Why "Linked: Yes" for the bug-report types *(A9: decided; the in-app email field stays)*: a report can carry an email address in the same submission, and Apple counts data as linked when it is connected to identifying details. The automatic Sentry crash path alone would be "Not linked", but Apple asks once per data type, so the linked flow sets the answer.

### 10.3 `App/PrivacyInfo.xcprivacy` entries (WS3 fills WS1's empty array)

One `NSPrivacyCollectedDataTypes` dict per row of 10.2 with the same linked/tracking/purpose values (`NSPrivacyCollectedDataTypeProductInteraction`, `...DeviceID`, `...CoarseLocation`, `...CrashData`, `...PerformanceData`, `...OtherDiagnosticData`, `...CustomerSupport`, `...OtherUserContent`, `...EmailAddress`; purposes `NSPrivacyCollectedDataTypePurposeAnalytics` / `...AppFunctionality`). Our ingest client uses only `UserDefaults` (already declared by WS1 as `CA92.1`) and adds no required-reason API. Accessed-API entries *(B-4)*: add `SystemBootTime` (`35F9.1`) only if Sentry needs it and does not ship its own manifest in the bundle (Sentry's manifest guidance lists UserDefaults, SystemBootTime and FileTimestamp; a statically linked SDK's manifest is not processed automatically, https://docs.sentry.io/platforms/apple/data-management/apple-privacy-manifest/). WS1's verify-archive check 9 then has to pass with the vendor symbols present.

---

## 11. [RYAN] manual setup

Do these before step 5 (Sentry/TelemetryDeck values) and before the TestFlight smoke test. Never paste tokens into the repo or a chat.

1. **TelemetryDeck**
   1. Go to https://dashboard.telemetrydeck.com, sign up with segue@ryandsilva.dev (or your usual address). New accounts get the 50k signals/month free tier.
   2. Top-left app dropdown > **Create New App** > name `Segue`. Then create a second app `Segue Personal` (A61).
   3. For each app: left sidebar > **Settings > Set Up App** > scroll to the bottom > click the App ID to copy. Paste both to Claude, labelled (an App ID is not secret) for `Project.swift`. Also tell Claude whether the organisation settings show a **namespace**; if so, paste it (3.9 then posts to `/v2/namespace/<namespace>/`).
   4. Retention (R32): look in the app's and the organisation's settings for any data-retention or deletion option and tell Claude what exists. Contact TelemetryDeck support (the dashboard's support/contact link) asking whether raw signals for this app can be deleted after a shorter period, e.g. 13 months. This runs in parallel and blocks nothing; if they offer a shorter period, tell the WS4 session so the policy wording tightens.
2. **Sentry**
   1. https://sentry.io/signup/ > create the organisation (slug e.g. `ryandsilva`); choose data storage location **United States** (R33). It cannot be changed later (https://docs.sentry.io/organization/data-storage-location/).
   2. **Projects > Create Project** > platform **Apple > macOS** > name `segue-macos` > alert setting "Alert me on every new issue" > Create.
   3. **Settings > Projects > segue-macos > Client Keys (DSN)** > copy the DSN; give it to Claude (not secret).
   4. **Settings > Security & Privacy** (organisation) and **Settings > Projects > segue-macos > Security & Privacy**: turn on **Prevent Storing of IP Addresses**; **Data Scrubber** on; **Use Default Scrubbers** on; **Additional Sensitive Fields**: `title`, `lyrics`, `filename`, `path`, `email`; leave Safe Fields empty.
   5. **Settings > Auth Tokens** (organisation tokens) > **Create New Token** > name `segue dsym upload` (org tokens carry the `org:ci` scope used by sentry-cli uploads). Copy it once into 1Password: vault **Private**, item **`Segue Sentry`**, field **`token`**. Then tell Claude the item exists so step 6 can test `op read 'op://Private/Segue Sentry/token'`.
   6. **Alerts**: confirm the default "new issue" email alert exists; **Alerts > Create Alert > Issues** "A new issue is created" filtered to `issue.category:feedback` (or the User Feedback notification under **Settings > Account > Notifications > Issue alerts / User Feedback**) so every bug report emails you. Free plan alerts are email only.
   7. Weekly habit (R24): open **User Feedback**, copy anything worth keeping into GitHub by hand; reports expire after 30 days.
3. **Featurebase**
   1. https://www.featurebase.app > sign up > create the workspace `Segue` (subdomain e.g. `segue.featurebase.app`); one board "Feature Requests"; statuses: Under Review, Planned, In Progress, Shipped, Declined.
   2. **Settings > Requests > Collection > Feedback Portal > Participation**: tick the **Guest actions** boxes (posting, upvoting, commenting without login) and turn on **Request moderation** and **Comment moderation**. Both are UNVERIFIED on the Free plan; if either is missing, stop and tell Claude (research 07 fallback: Fider Cloud).
   3. **Settings > Branding**: logo (the taped-setlist icon PNG), accent `#F2555A`, dark default theme if offered, workspace name "Segue".
   4. Send the board URL to the WS4 session for the `/feedback` redirect.
4. **App Store Connect privacy questionnaire** (after WS3 lands, before submission; WS5 runs this from its copy of 10.2): **App Store Connect > Apps > Segue - Setlists & Chords > App Privacy > Get Started** (or **Edit**) > "Yes, we collect data" > tick the nine data types in 10.2 > for each, **Set Up** > choose purposes, linked, tracking exactly as the table > **Publish**. Privacy Policy URL `https://segue.ryandsilva.dev/privacy` in the same page.
5. **1Password** must be unlocked whenever `make upload` / `make upload-dsyms` runs.

---

## 12. File-level changes

New:
- `Packages/SegueCore/Sources/Services/`: `Ports.swift`, `AnalyticsEvent.swift` (+ `FeatureKey`, `ErrorCode`, param enums), `Buckets.swift`, `AnalyticsThrottle.swift`, `ServicesHub.swift`, `ServicesFactory.swift`, `ConsentState.swift`, `Breadcrumb.swift`, `FeedbackReport.swift`, `FeedbackReportBuilder.swift` (envelope bytes + preview model from one value), `DiagnosticLog.swift`, `DiagnosticStore.swift`, `NullAdapters.swift`, `RecordingAdapters.swift`.
- `Packages/SegueCore/Tests/ServicesTests/` (or inside `SegueCoreTests`): see 14.2.
- `Packages/SegueVendorServices/Package.swift`, `Sources/VendorServices/{TelemetryDeckIngestSink,IngestBody,IngestQueue,SentryCrashReporter,SentryEnvelopeFeedbackSender,SentryScrubber,VendorConfig,VendorServicesFactory}.swift`, `Tests/VendorServicesTests/{TelemetryDeckIngestTests,SentryScrubberTests,FeedbackEnvelopeTests}.swift`.
- `UI/Services/`: `ConsentStore.swift`, `ConsentChoiceView.swift`, `ConsentSheet.swift`, `PrivacySettingsView.swift`, `ReportProblemPresenter.swift`, `ReportProblemModel.swift`, `ReportProblemSheet.swift`, `ReportPreviewView.swift`, `MailComposer.swift` (port + `SharingServiceMailComposer` + recording double), `ReportFileSaver.swift`, `MetricKitCollector.swift`, `SystemInfo.swift`.
- `App/Sources/ServicesWiring.swift`.
- `scripts/upload-dsyms.sh`, `.sentryclirc`.
- `UITests/SegueServicesE2ETests.swift`, `UITests/SegueReportProblemE2ETests.swift`.

Changed:
- `Packages/SegueCore/Package.swift`: target `Services` (deps `Support`), add to the product and the test target.
- `Core/Library/LibraryStore.swift`: `searchWithTier(query:) -> SearchOutcome`, `SearchTier` enum; `search(query:)` delegates (section 5 row 17).
- `Tuist/Package.swift`: sentry-cocoa exact pin (no TelemetryDeck package); `../Packages/SegueVendorServices`; `Services`, `VendorServices` in `targetSettings`.
- `Project.swift`: vendor constants and per-target build settings (3.7); Info.plist keys; `.external(name: "VendorServices")` on both the App Store and Personal targets (A61).
- `App/Sources/SegueApp.swift`: build `ServicesHub`, `ConsentStore`, `DiagnosticLog`, `MetricKitCollector`; pass via `AppDependencies`; `Settings` gets the Privacy tab.
- `App/Sources/LaunchOptions.swift`: Debug-only flags `-SegueServicesLog <file>` (Recording adapters), `-SegueFeedbackResult <ok|offline|rejected>` (recording sender outcome), `-SegueMailLog <file>` (recording `MailComposer`), `-SegueServicesLive YES` (real vendors, Sentry environment `debug`, TelemetryDeck `isTestMode: true`), `-SegueConsent <undecided|granted|declined|analyticsOnly|crashOnly>` (preset). Add to `flags`, `isTestRun`, doc comment.
- `UI/App/AppModel.swift` (`AppDependencies.services`, `consent`, `reportPresenter`, `diagnostics`), the view models in section 2 (one `record` call each, including search in `LibraryViewModel` / `QuickSearchModel` / builder and the chord palette in `SongEditorViewModel+ChordInput.swift`), `UI/SegueRootView.swift` (consent sheet + report sheet presentation), the Settings host that exists when WS3 lands (`UI/Settings/LiveSettingsView.swift` today, WS2b's `SegueSettingsView.swift` later; Privacy tab), `UI/App/SegueLinks.swift` (`supportAddress`), `UI/AccessibilityID+Services.swift` (new IDs for every control in sections 4 and 8).
- `App/PrivacyInfo.xcprivacy` (10.3). No entitlements files (WS1 owns `network.client` on both flavours, I-15).
- `.mise.toml` (sentry-cli), `Makefile` (`upload-dsyms`), `scripts/release.sh` (call upload-dsyms), `scripts/verify-archive.sh` (check 14), `.swiftlint.yml` (vendor-import and vendor-host rules).
- `docs/decisions.md`: a "WS3 services (2026-10-xx)" entry pointing at release R32-R34, A6-A11, A61, A62 and recording the section 17 answers.

---

## 13. Step order

Each step: `make quick`, then the targeted E2E named, then a signed local commit.

1. **Spike the feedback envelope** (B-24: our own envelope post). Verify the feedback item shape (3.5) against the protocol docs and sentry-cocoa source; write it down in a comment in `FeedbackReportBuilder`. No network yet.
2. **Services core**: ports, vocabulary, buckets, throttle, hub, consent value, Null/Recording adapters, `DiagnosticLog`. Integration tests 14.2-1..5. `make quick`.
3. **Consent UI and wiring**: `ConsentStore`, `ConsentChoiceView`, `ConsentSheet`, Privacy tab, launch flags, `ServicesWiring` with Null/Recording only. `make e2e-one TEST=SegueServicesE2ETests`.
4. **Event emission**: one `record` call per row of section 5 at the view-model entry points, including `LibraryStore.searchWithTier` for row 17 and the chord palette for row 18; diagnostic-log call sites. SegueUI leak test 14.2-6. `make e2e-one TEST=SegueServicesE2ETests/testNoUserContentInSignals`.
5. **VendorServices package** (needs [RYAN] 1-2 values): Sentry pin, `TelemetryDeckIngestSink` (3.9; tests 14.2-9/10 first), Sentry reporter + scrubber, factory, `VendorConfig`, Info.plist keys, lint rules. Before writing the ingest client, re-read https://telemetrydeck.com/docs/ingest/v2 and the pinned-version SwiftSDK `SignalManager.swift`; if the endpoint, body shape or status handling differs from 3.9, stop and ask. Record app size before/after. Live check with `-SegueServicesLive YES` on Debug-AppStore and Debug-Personal: grant analytics -> `TelemetryDeck.Session.started` and one `Segue.*` signal visible in the right TelemetryDeck app's test-mode view, with only the 3.9 payload keys; grant crash -> `SentrySDK.capture(message:)` from a Debug-only menu item appears in Sentry env `debug`; revoke -> no further connections (`nettop -p Segue`), `queue.json` gone. `make quick`, `make verify-appstore`.
6. **Report a Problem**: model, sheet, preview, envelope sender, mail composer, file saver, MetricKit collector. `make e2e-one TEST=SegueReportProblemE2ETests`. Live: send one real report from Debug-AppStore with `-SegueServicesLive YES`, confirm it in Sentry User Feedback with attachments.
7. **Request a Feature hook** and `SegueLinks.supportAddress`. `make e2e-one TEST=SegueServicesE2ETests/testRequestFeatureOpensBoard`.
8. **Privacy manifest + label** (10.3), verify-archive check 14 (if WS1's script exists; otherwise leave a note in WS1's file list for its owner, do not edit WS1's spec).
9. **dSYM upload** (needs [RYAN] 2.5): mise tool, `.sentryclirc`, `upload-dsyms.sh`, release.sh hook, Make target. Test `make upload-dsyms ARCHIVE=<a make archive output>` once (uploads dSYMs only; harmless).
10. **Personal flavour** (A61): confirm WS1 step 1 has landed `network.client` on both Personal entitlements files (if not, stop and ask; do not edit WS1's files); link `VendorServices` into the Personal target with the `Segue Personal` App ID; Sentry environment `personal`. Build Release-Personal, launch it, grant both, and check a signal in the `Segue Personal` TelemetryDeck app and nothing new in `Segue`.
11. **Final gate**: one `make check`. Then hand Ryan the TestFlight smoke checklist (14.4).

---

## 14. Test plan

Tiered per the repo budget: `make quick` after each small change, `make e2e-one TEST=...` for the touched UI, **one** `make check` at the end. Integration over unit; unit tests only for the scrubber, buckets and envelope builder (tricky pure logic).

### 14.1 Fakes
`RecordingAnalyticsSink`, `RecordingCrashReporter`, `RecordingFeedbackSender`, `RecordingMailComposer` append one JSON line per call (`{"kind":"signal","name":...,"params":{...}}`, `{"kind":"crash.start"}`, `{"kind":"breadcrumb",...}`, `{"kind":"feedback","sha256":...,"bytes":...}`) to the `-SegueServicesLog` file. In package tests the same types write to a temp file. A `CountingFactory` records how many vendor adapters were constructed.

### 14.2 Integration tests (`swift test`, real files on temp dirs)
1. **Nothing before consent:** hub with undecided consent; drive 200 random events; assert the Recording sink saw 0 signals, the crash reporter 0 breadcrumbs, and `CountingFactory` constructed 0 adapters. Same for declined.
2. **Independence:** analytics granted + crash declined (and the reverse): only the granted side receives anything; the other factory count stays 0.
3. **Revocation is immediate:** grant, send, revoke; any `record` after `apply(revoked)` returns reaches nothing (assert with an event sent concurrently from another task during revoke: count after the swap is 0); `shutDown(discardingQueue: true)` called exactly once; throttle state cleared.
4. **Closed vocabulary:** iterate every `AnalyticsEvent` case with every param enum value (`CaseIterable`) and bucket boundary; every name matches `^Segue\.[A-Z][A-Za-z]+\.[a-z][A-Za-z]+$`, every key `^segue\.[a-z][A-Za-z]+$`, every value the 5-section allowlist regex; a reflection check asserts no associated value is `String`.
5. **DiagnosticLog:** rotation across 5 simulated launches keeps 4 files; 512 KB cap writes one truncated line; logging an error carrying a URL (`CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "/Users/x/Music/Segue/songs/secret-title.cho"])`) writes only domain and code.
6. **No user content leaks (SegueUI, real components):** open the fixture library (`Packages/SegueCore/Tests/Fixtures`, real parser, store and index) through `AppModel` with Recording adapters and both consents granted; run create song, transpose, Nashville, apply-to-source, create setlist, start and end a rehearsal via the view models. Collect every token of every fixture song's title, artist, lyrics and file name (length >= 4), every setlist name, and the temp library path; assert none appears in the recorded signals, breadcrumbs or the diagnostic log files.
7. **Scrubber (VendorServices tests):** build `Sentry.Event`s with a home path in an exception value, a device name, a user email, an IP, a `.cho` file name, a non-`segue` breadcrumb; assert each is removed or replaced; with the revoked flag set, `event(_:)` returns nil.
8. **Envelope builder:** the bytes for a report equal the preview model's rendering (same fields, same attachment bytes); parsing the envelope back yields exactly the allowlisted keys and nothing else (no installation id, no breadcrumbs, no contexts beyond the previewed system info); song file absent unless ticked.
9. **Ingest body allowlist (VendorServices tests, real `URLSession` with a `URLProtocol` stub capturing requests):** grant, send every `AnalyticsEvent` case; every captured request is `POST` to the configured `/v2/` (or namespace) URL with `Content-Type: application/json; charset=utf-8` and no other custom header; the body is a JSON array of at most 100 objects; each object's keys are a subset of `{appID, clientUser, sessionID, type, isTestMode, payload}`; each payload key is either `segue.*` or one of the five 3.9 context keys; `clientUser` is 64 lowercase hex chars and differs from the stored `analytics.installID`; the first signal of a session is `TelemetryDeck.Session.started`.
10. **Ingest queue behaviour:** stub returns 503 then 200: the batch is retried with backoff and sent once; stub returns 400: the batch is dropped, not retried; stub offline, 150 signals, simulated terminate: `queue.json` holds 150, a new sink sends them as two requests (100 + 50); `shutDown(discardingQueue: true)` cancels the in-flight request and deletes `queue.json` and `analytics.installID`; a re-grant produces a different `clientUser`.

### 14.3 E2E (`UITests`, Personal Debug build, reset state, Recording adapters)
All launch with `-SegueResetState YES -SegueServicesLog <tmp>/services.jsonl` plus the fixture library.
1. `testConsentFirstRunAsksBothEqually`: fresh launch shows the consent sheet (before WS2b lands; afterwards WS2b's Welcome E2E covers the in-flow page and this test runs with `-SegueOnboarding done` to cover the upgrader sheet); the four choice buttons ("Don't Share", "Share", "Don't Send", "Send") exist with equal frames (width/height equal within 1 pt); Continue disabled; Esc does nothing; choose Share + Don't Send; Continue; the log has exactly one `Segue.Privacy.analyticsEnabled` and no `crash.start`; relaunch without reset: no sheet.
2. `testNothingSentBeforeConsent`: fresh launch, do not answer; create a song, transpose, start and end a rehearsal (sheet deferred while on stage, reappears after); the log file is empty or absent.
3. `testRevokeStopsSending`: preset `-SegueConsent granted`; transpose (signal logged); Settings > Privacy, turn analytics off; the 4.3 caption shown; transpose again; no new signal lines; crash toggle off shows the Diagnostics ID row with Copy; crash toggle back on shows "Crash reporting starts the next time you open Segue." (unless step 5 found in-process restart works).
4. `testReportPreviewMatchesSent`: Help > Report a Problem; Send disabled until text typed; song file unchecked by default; Preview shows logs and system info and no song text; go back, tick song file, preview shows the fixture song's lyrics; Send; the recorded feedback `sha256` equals the hash exposed by the preview (UITesting-only accessibility value).
5. `testReportOfflineFallback`: `-SegueFeedbackResult offline -SegueMailLog <tmp>`; Send; "Couldn't send" shows Email Instead / Save Report / Try Again; Email Instead records recipient `segue@ryandsilva.dev`, subject with version, and the attachment names.
6. `testRequestFeatureOpensBoard`: with WS2a's `-SegueWorkspaceLog`, Help > Request a Feature records `https://segue.ryandsilva.dev/feedback`.
7. `testNoUserContentInSignals`: E2E twin of 14.2-6 through the real UI (import the fixture songs, edit, use the chord palette, search the library with a romanized-Hindi spelling variant of a fixture title, build a setlist, play a gig), then grep the log for fixture titles, lyric words and the search query; assert one `Segue.Search.performed` with `segue.matchTier` `spellingVariant` or `looseVariant` and one `Segue.Editor.chordPalette`.

Screenshots of the consent sheet, Privacy pane, report form, preview and fallback in both appearances are attached to the test results for the pixel pass.

### 14.4 Manual smoke test against real vendors (TestFlight build, after `make upload`)
1. Before installing, quit Segue; the `~/Library/Containers/dev.ryandsilva.segue` container has been moved aside and the shapes and bindings copied to the Personal container (R40, WS1), so this is a clean first run.
2. Install from TestFlight. Walk the Welcome flow; the consent choice is its last page. Before answering it run `nettop -p Segue -L 1` (or Little Snitch): **no connections** to `nom.telemetrydeck.com` or any `sentry.io` host.
3. Answer Share / Send. Use the app 5 minutes (song, transpose, chord palette, a romanized search, setlist, rehearsal). Within ~10 minutes: the `Segue` TelemetryDeck app's **test mode** view shows the signals (TestFlight is test data, B-25) with only the 3.9 payload keys and no titles; Sentry shows no issues (nothing crashed) and no sessions.
4. Help > Report a Problem with logs + MetricKit (song unticked); Sentry User Feedback shows the report, attachments open and match the preview.
5. Turn Wi-Fi off, send another: the fallback appears; Email Instead opens Mail with the attachments.
6. Settings > Privacy: turn both off; `nettop` shows no further vendor connections over 10 minutes of use; captions shown; Diagnostics ID copyable.
7. Sentry > Settings > Debug Files lists the build's dSYM UUID (`make upload-dsyms` output).
8. Any later hang or crash from real use appears symbolicated in Sentry within a day (MetricKit delivery).

---

## 15. Acceptance criteria

1. With consent undecided or declined, no vendor SDK is initialised and the app opens no connection to any vendor (14.2-1, 14.3-2, 14.4-2).
2. Two independent toggles, asked once on first run with equal-weight choices, changeable in Settings > Privacy; revoking stops sending at once, deletes queued data, and shows the deletion instructions (14.2-2/3, 14.3-1/3).
3. The WS2b contract (4.4) is implemented on the WS3 side and the standalone sheet covers first run until WS2b lands.
4. Every analytics signal is one of section 5's rows; the vocabulary has no `String` payloads; no fixture title, lyric, file name, setlist name or path appears in signals, breadcrumbs or logs (14.2-4/6, 14.3-7).
5. Sentry starts only with crash consent, with the 6.2 options; events are scrubbed per 6.3; IP storage is off in the project; the installation ID is the only identifier.
6. Report a Problem previews everything, sends exactly the previewed bytes to Sentry User Feedback, keeps the song file off by default, and falls back to email or a saved folder offline (14.3-4/5).
7. Request a Feature opens `https://segue.ryandsilva.dev/feedback` in the browser.
8. `make upload` uploads the dSYMs with a token read from 1Password at run time only; `sentry-cli` comes from mise.
9. `PrivacyInfo.xcprivacy` lists the 10.2 types; the 10.2 table is final and canonical (WS5 copies it); vendor facts for WS4 are in 10.1.
10. Both flavours link `VendorServices` (Sentry SDK plus our ingest client; no TelemetryDeck SDK anywhere); Personal reports to Sentry environment `personal` and the `Segue Personal` TelemetryDeck app; `verify-appstore` and `verify-archive` pass.
11. TelemetryDeck requests carry only the 3.9 keys (14.2-9), queue and retry as specified (14.2-10), and leave nothing on disk after revoke.
12. `make check` green, zero warnings, no new SwiftLint suppressions.

---

## 16. Risks

| # | Risk | Impact | Mitigation |
|---|---|---|---|
| R1 | **SDK size.** sentry-cocoa is the only SDK added (several MB; no official figure); the ingest client is our own small code. | Bigger download, slower launch | Measure Release-AppStore size before/after in step 5; disable unused integrations (6.2); if Sentry adds more than ~8 MB, try the prebuilt static product and tell Ryan |
| R2 | **SDK phoning home before init.** Sentry does not document network I/O before `start` (UNVERIFIED), but it *does* resend cached envelopes from disk at start, and `close()` flushes pending events. Our ingest client has no code path to the network before construction. | A consent violation even with gated init | Gated construction (3.3) so no vendor API is touched before consent; delete Sentry's envelope cache on revoke before `close()` (6.4); ingest queue deleted on revoke (3.9); verified by `nettop` in 14.4-2/6 |
| R3 | **Ingest API drift.** Our client depends on TelemetryDeck's v2 ingest contract (3.9), not on an SDK they maintain | Signals silently rejected, dashboards empty | Disposition logged to `DiagnosticLog`; live check in step 5 and 14.4-3; re-read the v2 docs before coding; check the dashboard monthly with the usage page; TelemetryDeck-reserved parameter names are avoided except the five documented context keys and the documented session signal |
| R4 | **TelemetryDeck retention**: no deletion schedule, 7-10 years cold storage, vs R26's ~13-month target | Policy wording | Decided by R32: TelemetryDeck's default, stated plainly; Ryan asks for a shorter period in parallel ([RYAN] 1.4) |
| R5 | Free-tier caps: TelemetryDeck 50k/month pauses collection at the cap; Sentry 5k errors/month (whether MetricKit diagnostics count against it is reported both ways, UNVERIFIED) | Silent data loss | Throttling (3.4); MetricKit filtering in `beforeSend`; check usage pages after month 1 |
| R6 | Sentry envelope API for feedback changes or rejects our item shape | Bug reports fail | Step 1 spike; live check in step 6; the email/file fallback always works |
| R7 | Swift 6 / warnings-as-errors with vendor headers under Xcode 27 | Build breaks | `@preconcurrency import` only where required; external targets keep Tuist's warning suppression; pin exact |
| R8 | Re-start after `SentrySDK.close()` in one process not supported | Toggle on after off does nothing until relaunch | A11: the caption says so, start next launch (6.4) |
| R9 | Featurebase guest voting / moderation not on Free (UNVERIFIED) | Board needs sign-in or is unmoderated | [RYAN] 3.2 checks first; fallback Fider Cloud (research 07 H.5); app only knows `/feedback`, so swapping needs no app update |
| R10 | Sentry bug reports expire after 30 days (R24) | Lost reports | Weekly manual copy habit; email alert per report |
| R11 | Consent prompt at launch collides with WS2b Welcome, WS2a What's New or crash-resume prompts | Stacked sheets, reviewer confusion | 4.4 rules: one sheet at a time, never on stage; E2E 14.3-2 covers the stage deferral |
| R12 | App Review reads the label as over-declared ("Linked", Coarse Location) | Product page looks less private | Accepted (A8, A9): over-disclosure is not a rejection reason, under-disclosure is |
| R13 | Our log or report accidentally carries user content through a new call site later | Privacy breach | Typed `DiagnosticLog` API with no `String`; vocabulary enum; leak tests run in `make check` |

---

## 17. Open questions for Ryan (new in this revision)

All earlier questions are closed (see the header). These two came up while applying the answers; each has a default the session builds unless Ryan says otherwise.

1. **Symbolicating Personal crashes.** With A61, Release-Personal reports to Sentry, but only `make upload` (App Store archives) uploads dSYMs, so Personal crashes would show unsymbolicated frames. How do you install your daily Personal build? Default: `scripts/upload-dsyms.sh` also accepts `DSYMS=<dir>`, Release-Personal keeps `DEBUG_INFORMATION_FORMAT = dwarf-with-dsym`, and a `make upload-dsyms-personal` target uploads the newest Release-Personal dSYMs from DerivedData; you run it after installing a new Personal build. Alternatives: (b) a post-build script phase on Release-Personal that uploads automatically (needs 1Password unlocked at every Release-Personal build); (c) leave Personal crashes unsymbolicated.
2. **Analytics identity after revoke and re-grant.** Default (built in 3.9): revoking analytics deletes the per-install ID, so a later re-grant counts as a new anonymous user (more private; slightly inflates "new users" in TelemetryDeck for people who toggle). Alternative: keep the ID across revoke and re-grant (retention charts stay continuous for that install).

## Implementation notes (orchestrator rulings during build)
- Bug-report description: the form caps at **4,096 characters** with a visible counter (Sentry's message limit), replacing the spec's 5,000. The builder keeps refusing anything oversized; it never truncates silently.
- CryptoKit is allowed in the Services target for the SHA-256 (an Apple system framework, no new dependency).
- Diagnostic keys may contain digits (`segue.nonUTF8`); the key regex in 14.2-4 is widened to allow them.
- `ServicesHub.init(feedback:)` defaults to the Null sender; it is fine as built.
