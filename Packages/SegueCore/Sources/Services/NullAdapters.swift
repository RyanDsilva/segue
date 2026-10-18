import Foundation
import Support

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

/// The factory for builds without a vendor config (Debug without `-SegueServicesLive`): a
/// grant installs Null adapters, so the consent UI behaves and nothing is ever sent.
public struct NullServicesFactory: ServicesFactory {
    public init() {}

    public func makeAnalytics() -> any AnalyticsSink {
        NullAnalyticsSink()
    }

    public func makeCrashReporter() -> any CrashReporter {
        NullCrashReporter()
    }
}

public extension ServicesHub {
    /// A hub that never sends anything: consent undecided and Null adapters only. The
    /// default for view models and in-process tests that do not observe services.
    static func inert() -> ServicesHub {
        ServicesHub(
            factory: NullServicesFactory(),
            consent: .undecided,
            // Never consulted: analytics never go live with consent undecided.
            throttle: AnalyticsThrottle(suiteName: nil, clock: InertClock()),
        )
    }
}

/// The epoch, for `ServicesHub.inert()`'s unused throttle.
private struct InertClock: Clock {
    func now() -> Date {
        Date(timeIntervalSince1970: 0)
    }
}
