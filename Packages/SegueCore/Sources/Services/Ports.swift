import Foundation

// The four seams between Segue and its hosted vendors (spec 3.2). Vendor adapters live in
// the VendorServices package; this module only has the Null and Recording adapters.
//
// Every port is `Sendable` and fire-and-forget at the call site, so `@MainActor` view models
// call it without `await` and a slow vendor can never stall the UI or the stage.

/// Usage analytics. Receives only signals rendered from the closed `AnalyticsEvent`
/// vocabulary (`AnalyticsSignal` has no public initialiser).
public protocol AnalyticsSink: Sendable {
    /// Queues one signal for sending.
    func send(_ signal: AnalyticsSignal)
    /// Stop for good: drop anything queued in memory and on disk, send nothing more.
    func shutDown(discardingQueue: Bool) async
}

/// Crash, hang and MetricKit reporting.
public protocol CrashReporter: Sendable {
    /// Records a breadcrumb (closed vocabulary only, spec 3.6).
    func addBreadcrumb(_ crumb: Breadcrumb)
    /// Closes the SDK and deletes its cached envelopes.
    func shutDown(discardingQueue: Bool) async
    /// The per-install Diagnostics ID shown in Settings > Privacy, when known.
    var installationID: String? { get }
}

/// Sends a previewed bug report.
public protocol FeedbackSender: Sendable {
    /// Sends exactly `payload` (the bytes the user previewed).
    func send(_ payload: FeedbackPayload) async throws(FeedbackError)
}

/// What a bug report may attach.
public protocol DiagnosticsSource: Sendable {
    /// The diagnostic log files of the last launches, newest first.
    func recentLogFiles() async -> [DiagnosticFile]
    /// The newest MetricKit diagnostic payload kept on this Mac, if any.
    func latestMetricKitPayload() async -> DiagnosticFile?
}
