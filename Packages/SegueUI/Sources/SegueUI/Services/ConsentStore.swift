import Foundation
import Observation
import Services
import Support

/// The user's two consent decisions, persisted as one `ConsentState` JSON value under
/// `privacy.consent` (WS3 spec 4.1). It is the single store and the only writer of consent in
/// the app (I-1): the prompt, the Welcome flow's last page, Settings > Privacy, Reset All
/// Settings and the Debug launch presets all write through `set(_:for:source:)`,
/// `commitDraft(source:)` or `resetToUndecided()`.
///
/// Every change is applied to `ServicesHub` at once (a revoke swaps the Null adapter in
/// before the writing call returns) and logged to the diagnostic log as
/// booleans only.
@MainActor
@Observable
public final class ConsentStore {
    /// The UserDefaults key holding the encoded `ConsentState`.
    public static let defaultsKey = "privacy.consent"

    /// One of the two independent toggles.
    public enum Toggle: String, CaseIterable, Sendable {
        case analytics
        case crashReports
    }

    /// The prompt's answers before Continue. Held in memory only: quitting before Continue
    /// leaves both decisions undecided, so the prompt comes back next launch (4.2 step 4).
    public struct Draft: Equatable, Sendable {
        /// nil = not answered yet; true = Share / Send.
        public var analytics: Bool?
        public var crashReports: Bool?

        public init(analytics: Bool? = nil, crashReports: Bool? = nil) {
            self.analytics = analytics
            self.crashReports = crashReports
        }

        /// Both rows answered: Continue may commit.
        public var isComplete: Bool {
            analytics != nil && crashReports != nil
        }

        public subscript(toggle: Toggle) -> Bool? {
            get {
                switch toggle {
                case .analytics: analytics
                case .crashReports: crashReports
                }
            }
            set {
                switch toggle {
                case .analytics: analytics = newValue
                case .crashReports: crashReports = newValue
                }
            }
        }
    }

    /// The stored decisions (as written; `state.effective` is what is enforced).
    public private(set) var state: ConsentState
    /// The prompt's pending answers (`ConsentChoiceView` edits it).
    public var draft = Draft()
    /// Whether this build has a vendor configuration. Without one (Debug without
    /// `-SegueServicesLive`) Settings > Privacy says the services are not part of the build
    /// instead of showing toggles that do nothing.
    public let isAvailable: Bool
    /// Toggles turned off in this session: Settings > Privacy shows what stopped and how to
    /// request deletion until the toggle is turned on again.
    public private(set) var revokedThisSession: Set<Toggle> = []
    /// The Diagnostics ID captured just before crash reports were turned off (the reporter
    /// is gone afterwards), for the deletion caption. Nil when none was known.
    public private(set) var revokedDiagnosticsID: String?
    /// Crash reports were turned back on after being turned off in this session: the crash
    /// reporter cannot restart in the same process (A11), so it starts at the next launch.
    public private(set) var crashStartsAtNextLaunch = false

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let hub: ServicesHub
    @ObservationIgnored private let log: DiagnosticLog?
    @ObservationIgnored private let clock: any Clock
    @ObservationIgnored private let crashRestartsInProcess: Bool
    /// Crash reporting was live at some point in this process (the SDK starts at most once).
    @ObservationIgnored private var crashStartedThisProcess: Bool
    /// The last `hub.apply`, so changes reach the hub in the order they were made.
    @ObservationIgnored private var pending: Task<Void, Never>?

    /// - Parameters:
    ///   - defaults: where the decisions persist; nil keeps them in memory only (tests).
    ///   - hub: the gate the decisions are applied to. It must have been built with
    ///     `ConsentStore.stored(in: defaults)`, so the two agree from the first moment.
    ///   - crashRestartsInProcess: whether the crash reporter can start again after it was
    ///     shut down in the same process (false for Sentry, A11).
    public init(
        defaults: UserDefaults?,
        hub: ServicesHub,
        log: DiagnosticLog? = nil,
        clock: any Clock = SystemClock(),
        isAvailable: Bool,
        crashRestartsInProcess: Bool = false,
    ) {
        self.defaults = defaults
        self.hub = hub
        self.log = log
        self.clock = clock
        self.isAvailable = isAvailable
        self.crashRestartsInProcess = crashRestartsInProcess
        let stored = defaults.map(Self.stored(in:)) ?? .undecided
        state = stored
        crashStartedThisProcess = stored.effective.crashReports.isGranted
    }

    /// A store for in-process tests and previews: in memory, both declined (no prompt), and
    /// an inert hub.
    public static func inert() -> ConsentStore {
        let store = ConsentStore(defaults: nil, hub: .inert(), isAvailable: false)
        store.state = ConsentState(
            analytics: .declined(.distantPast),
            crashReports: .declined(.distantPast),
        )
        return store
    }

    /// The decisions stored in `defaults` (undecided when none or unreadable).
    public static func stored(in defaults: UserDefaults) -> ConsentState {
        guard let data = defaults.data(forKey: defaultsKey),
              let state = try? SegueJSON.decode(ConsentState.self, from: data)
        else {
            return .undecided
        }
        return state
    }

    // MARK: Reading

    /// Either toggle is undecided (or the stored version is outdated): the consent prompt
    /// must be shown (WS2b's resume logic reads this too).
    public var needsPrompt: Bool {
        state.needsPrompt
    }

    /// Whether `toggle` is granted (undecided shows as off).
    public func isGranted(_ toggle: Toggle) -> Bool {
        decision(toggle).isGranted
    }

    /// Whether `toggle` has been answered (granted or declined).
    public func isDecided(_ toggle: Toggle) -> Bool {
        !decision(toggle).isUndecided
    }

    private func decision(_ toggle: Toggle) -> ConsentState.Decision {
        let effective = state.effective
        return switch toggle {
        case .analytics: effective.analytics
        case .crashReports: effective.crashReports
        }
    }

    // MARK: Writing

    /// Records one decision. `source` is where it was made; a grant of analytics sends
    /// `Segue.Privacy.analyticsEnabled` with it. Launch presets pass nil (nothing recorded).
    public func set(_ granted: Bool, for toggle: Toggle, source: ConsentSource?) {
        let current = decision(toggle)
        if !current.isUndecided, current.isGranted == granted {
            return
        }
        var next = state.effective
        let now = clock.now()
        let chosen: ConsentState.Decision = granted ? .granted(now) : .declined(now)
        switch toggle {
        case .analytics: next.analytics = chosen
        case .crashReports: next.crashReports = chosen
        }
        next.version = ConsentState.currentVersion
        commit(next, source: source)
    }

    /// Commits the prompt's answers (Continue in `ConsentSheet` or WS2b's Welcome flow).
    /// Does nothing until both rows are answered.
    public func commitDraft(source: ConsentSource) {
        guard let analytics = draft.analytics, let crashReports = draft.crashReports else {
            return
        }
        let now = clock.now()
        let next = ConsentState(
            analytics: analytics ? .granted(now) : .declined(now),
            crashReports: crashReports ? .granted(now) : .declined(now),
        )
        draft = Draft()
        commit(next, source: source)
    }

    /// Both decisions back to undecided (Settings > Data > Reset All Settings): shuts both
    /// vendors down and the prompt comes back at the next launch.
    public func resetToUndecided() {
        draft = Draft()
        commit(.undecided, source: nil)
        revokedThisSession = []
    }

    /// Waits until every change made so far has been applied to the hub (tests, and the
    /// app's termination path).
    public func settle() async {
        await pending?.value
    }

    private func commit(_ next: ConsentState, source: ConsentSource?) {
        let before = state.effective
        guard next != state else { return }
        let analyticsGranted = !before.analytics.isGranted && next.analytics.isGranted
        noteCrashTransition(from: before.crashReports, to: next.crashReports)
        if before.analytics.isGranted, !next.analytics.isGranted {
            revokedThisSession.insert(.analytics)
        } else if next.analytics.isGranted {
            revokedThisSession.remove(.analytics)
        }
        state = next
        persist()
        log?.notice(.consent, "changed", [
            "analytics": .bool(next.analytics.isGranted),
            "crashReports": .bool(next.crashReports.isGranted),
        ])

        // Revocations take effect here, before this method returns; grants complete in order.
        let application = hub.beginApply(next)
        let hub = hub
        let previous = pending
        pending = Task {
            await previous?.value
            await application.complete()
            if analyticsGranted, let source {
                hub.record(.analyticsEnabled(source))
            }
        }
    }

    /// Captions and the next-launch rule for the crash toggle (4.3, A11).
    private func noteCrashTransition(
        from before: ConsentState.Decision,
        to after: ConsentState.Decision,
    ) {
        if before.isGranted, !after.isGranted {
            revokedDiagnosticsID = hub.installationID ?? revokedDiagnosticsID
            revokedThisSession.insert(.crashReports)
            crashStartsAtNextLaunch = false
        } else if !before.isGranted, after.isGranted {
            revokedThisSession.remove(.crashReports)
            crashStartsAtNextLaunch = crashStartedThisProcess && !crashRestartsInProcess
            crashStartedThisProcess = true
        }
    }

    private func persist() {
        guard let defaults else { return }
        if let data = try? SegueJSON.encode(state) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
