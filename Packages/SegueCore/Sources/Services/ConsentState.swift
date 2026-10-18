import Foundation

/// The user's two independent consent decisions (spec 4.1). Stored as JSON by
/// `ConsentStore` (SegueUI), the single writer of consent in the app.
public struct ConsentState: Codable, Sendable, Equatable {
    public enum Decision: Codable, Sendable, Equatable {
        case undecided
        case granted(Date)
        case declined(Date)

        public var isGranted: Bool {
            if case .granted = self {
                true
            } else {
                false
            }
        }

        public var isUndecided: Bool {
            self == .undecided
        }
    }

    /// Bump when what is collected changes materially: a stored lower version is treated as
    /// undecided for both toggles, which re-asks.
    public static let currentVersion = 1

    public var analytics: Decision = .undecided
    public var crashReports: Decision = .undecided
    public var version = Self.currentVersion

    public init(
        analytics: Decision = .undecided,
        crashReports: Decision = .undecided,
        version: Int = Self.currentVersion,
    ) {
        self.analytics = analytics
        self.crashReports = crashReports
        self.version = version
    }

    /// Nothing decided yet.
    public static let undecided = Self()

    /// The state that is in force: an outdated version counts as undecided for both.
    public var effective: Self {
        version < Self.currentVersion ? .undecided : self
    }

    /// Either toggle is undecided (or the stored version is outdated): the prompt must show.
    public var needsPrompt: Bool {
        let state = effective
        return state.analytics.isUndecided || state.crashReports.isUndecided
    }
}
