import Foundation
import Synchronization

/// The consent gate in front of every vendor (spec 3.3).
///
/// With a consent undecided or declined the hub holds the Null adapter for it and never
/// calls the factory, so no vendor code runs. Turning a consent off swaps the Null adapter in
/// under the lock first (no event can reach the old adapter after that) and only then shuts
/// the old adapter down, discarding its queue.
///
/// Nonisolated and lock-based (never an actor), so `record` stays synchronous and
/// non-blocking from `@MainActor` view models.
public final class ServicesHub: Sendable {
    private struct State {
        var consent: ConsentState
        var analytics: any AnalyticsSink
        var crashReporter: any CrashReporter
        var analyticsLive = false
        var crashLive = false
    }

    private let factory: any ServicesFactory
    private let throttle: AnalyticsThrottle
    private let state: Mutex<State>

    /// Bug reports are not consent-gated: sending a previewed report is its own explicit act.
    /// Constructing the sender opens no connection.
    public let feedback: any FeedbackSender

    /// Builds the hub for the stored consent. Vendor adapters are built here only for the
    /// consents already granted.
    public init(
        factory: any ServicesFactory,
        consent: ConsentState,
        throttle: AnalyticsThrottle,
        feedback: any FeedbackSender = NullFeedbackSender(),
    ) {
        self.factory = factory
        self.throttle = throttle
        self.feedback = feedback
        let effective = consent.effective
        var initial = State(
            consent: effective,
            analytics: NullAnalyticsSink(),
            crashReporter: NullCrashReporter(),
        )
        if effective.analytics.isGranted {
            initial.analytics = factory.makeAnalytics()
            initial.analyticsLive = true
        }
        if effective.crashReports.isGranted {
            initial.crashReporter = factory.makeCrashReporter()
            initial.crashLive = true
        }
        state = Mutex(initial)
    }

    /// The consent the hub is currently enforcing.
    public var consent: ConsentState {
        state.withLock { $0.consent }
    }

    /// The crash reporter's Diagnostics ID while crash reporting is on.
    public var installationID: String? {
        state.withLock { $0.crashReporter.installationID }
    }

    /// Records one analytics event: a breadcrumb while crash reporting is on, and a signal
    /// (subject to the throttle) while analytics are on. Never throws, never blocks on IO.
    public func record(_ event: AnalyticsEvent) {
        state.withLock { state in
            if state.crashLive {
                state.crashReporter.addBreadcrumb(Breadcrumb(event))
            }
            if state.analyticsLive, throttle.admit(event) {
                state.analytics.send(event.render())
            }
        }
    }

    /// Records an app lifecycle breadcrumb (crash reporting only; never analytics).
    public func record(_ lifecycle: LifecycleCrumb) {
        state.withLock { state in
            if state.crashLive {
                state.crashReporter.addBreadcrumb(Breadcrumb(lifecycle))
            }
        }
    }

    /// Applies a consent change. Revocations take effect before this returns its first
    /// suspension: the Null adapter is in place, then the old adapter is shut down
    /// discarding its queue. Grants build the vendor adapter.
    public func apply(_ consent: ConsentState) async {
        let target = consent.effective
        let analyticsWanted = target.analytics.isGranted
        let crashWanted = target.crashReports.isGranted

        // 1. Record the target and take down anything no longer wanted, under the lock.
        let retired = state.withLock { state -> Retired in
            state.consent = target
            var retired = Retired()
            if state.analyticsLive, !analyticsWanted {
                retired.analytics = state.analytics
                state.analytics = NullAnalyticsSink()
                state.analyticsLive = false
            }
            if state.crashLive, !crashWanted {
                retired.crashReporter = state.crashReporter
                state.crashReporter = NullCrashReporter()
                state.crashLive = false
            }
            return retired
        }
        if retired.analytics != nil {
            throttle.reset()
        }

        // 2. Build newly granted adapters outside the lock, then install them only if the
        //    consent still wants them (a concurrent revoke may have won meanwhile).
        let needsAnalytics = analyticsWanted && !state.withLock { $0.analyticsLive }
        let needsCrash = crashWanted && !state.withLock { $0.crashLive }
        var stale = Retired()
        if needsAnalytics {
            let sink = factory.makeAnalytics()
            stale.analytics = state.withLock { state -> (any AnalyticsSink)? in
                guard state.consent.analytics.isGranted, !state.analyticsLive else { return sink }
                state.analytics = sink
                state.analyticsLive = true
                return nil
            }
        }
        if needsCrash {
            let reporter = factory.makeCrashReporter()
            stale.crashReporter = state.withLock { state -> (any CrashReporter)? in
                guard state.consent.crashReports.isGranted, !state.crashLive else {
                    return reporter
                }
                state.crashReporter = reporter
                state.crashLive = true
                return nil
            }
        }

        // 3. Shut down what was retired or lost a race.
        await retired.shutDown()
        await stale.shutDown()
    }

    private struct Retired {
        var analytics: (any AnalyticsSink)?
        var crashReporter: (any CrashReporter)?

        func shutDown() async {
            await analytics?.shutDown(discardingQueue: true)
            await crashReporter?.shutDown(discardingQueue: true)
        }
    }
}
