#if os(macOS)
    import Foundation
    import StoreKit
    import SwiftUI

    // WS2b 4.5 (R20, A12): the review prompt after the 1st completed gig, once per app
    // version, never at launch, never from a button, never while performing.

    /// Completed gigs and the version last asked in (`review.*`). The only writer of its keys.
    @MainActor
    public final class ReviewPromptStore {
        static let completedGigsKey = "review.completedGigs"
        static let lastRequestedKey = "review.lastRequestedVersion"

        private let defaults: UserDefaults

        public init(defaults: UserDefaults) {
            self.defaults = defaults
        }

        /// Gigs ended in-session or from the resume prompt (rehearsals and stale gigs never).
        public var completedGigs: Int {
            defaults.integer(forKey: Self.completedGigsKey)
        }

        public var lastRequestedVersion: String? {
            defaults.string(forKey: Self.lastRequestedKey)
        }

        func recordCompletedGig() {
            defaults.set(completedGigs + 1, forKey: Self.completedGigsKey)
        }

        func markRequested(version: String) {
            defaults.set(version, forKey: Self.lastRequestedKey)
        }

        /// `-SegueCompletedGigs <n>` (Debug test runs).
        func presetCompletedGigs(_ count: Int) {
            defaults.set(count, forKey: Self.completedGigsKey)
        }
    }

    /// The rules, pure, so `ReviewPromptPolicyTests` covers them as a table.
    public enum ReviewPromptPolicy {
        /// The 1st completed gig is enough (A12); the OS caps prompts at 3 a year.
        public static let gigsNeeded = 1
        /// The main window must have been key this long before the prompt fires.
        public static let keyWindowDelay: Duration = .seconds(3)

        /// Whether a gig that just ended arms the prompt.
        public static func arms(
            completedGigs: Int,
            lastRequestedVersion: String?,
            currentVersion: String,
            quitsAfterEnding: Bool,
        ) -> Bool {
            guard completedGigs >= gigsNeeded, !quitsAfterEnding else { return false }
            guard let last = lastRequestedVersion else { return true }
            guard let lastVersion = AppVersion(last), let current = AppVersion(currentVersion)
            else { return last != currentVersion }
            return lastVersion != current
        }

        /// What the main window sees when it considers firing an armed prompt.
        public struct Moment: Sendable, Equatable {
            public var isPerforming = false
            public var stageWindowOpen = false
            public var isStartingShow = false
            public var resumePending = false
            public var checklistUp = false
            public var reorderReviewsPending = false
            /// Any other sheet or alert over the main window (Welcome, consent, What's New,
            /// a confirmation, Report a Problem, the start-failure alert).
            public var otherPresentation = false
            public var errorBannerShown = false
            /// The main window has been key without a break for this long.
            public var keyFor: Duration = .zero

            public init() {}
        }

        /// Whether an armed prompt may fire now: the end-of-show flow is done, the stage is
        /// closed and nothing else is up.
        public static func mayFire(_ moment: Moment) -> Bool {
            !moment.isPerforming && !moment.stageWindowOpen && !moment.isStartingShow
                && !moment.resumePending && !moment.checklistUp && !moment.reorderReviewsPending
                && !moment.otherPresentation && !moment.errorBannerShown
                && moment.keyFor >= keyWindowDelay
        }
    }

    /// Asks the system for a review. The real one calls SwiftUI's `requestReview` action
    /// (which may show nothing: the OS rate-limits it and TestFlight never shows it).
    @MainActor
    public protocol ReviewRequester {
        func requestReview(using action: RequestReviewAction)
    }

    /// The system prompt.
    public struct SystemReviewRequester: ReviewRequester {
        public init() {}

        public func requestReview(using action: RequestReviewAction) {
            action()
        }
    }

    /// Never asks (Debug test runs that did not ask for the review log).
    public struct SilentReviewRequester: ReviewRequester {
        public init() {}

        public func requestReview(using _: RequestReviewAction) {}
    }

    /// `-SegueReviewLog <file>`: appends one line per request instead of asking the system,
    /// so the E2E suite can count requests.
    public struct LogReviewRequester: ReviewRequester {
        let log: URL

        public init(log: URL) {
            self.log = log
        }

        public func requestReview(using _: RequestReviewAction) {
            let line = Data("requestReview \(Date().ISO8601Format())\n".utf8)
            if let handle = try? FileHandle(forWritingTo: log) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: line)
            } else {
                try? line.write(to: log)
            }
        }
    }
#endif
