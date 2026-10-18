import Foundation

/// Analytics with consent undecided or declined, or in builds without a vendor config:
/// drops everything.
public struct NullAnalyticsSink: AnalyticsSink {
    public init() {}

    public func send(_: AnalyticsSignal) {}

    public func shutDown(discardingQueue _: Bool) async {}
}

/// Crash reporting with consent undecided or declined: records nothing, has no identifier.
public struct NullCrashReporter: CrashReporter {
    public init() {}

    public func addBreadcrumb(_: Breadcrumb) {}

    public func shutDown(discardingQueue _: Bool) async {}

    public var installationID: String? {
        nil
    }
}

/// Bug reports in a build without a vendor config: every send fails with `.notConfigured`,
/// which offers the email / save-to-file fallback.
public struct NullFeedbackSender: FeedbackSender {
    public init() {}

    public func send(_: FeedbackPayload) async throws(FeedbackError) {
        throw .notConfigured
    }
}
