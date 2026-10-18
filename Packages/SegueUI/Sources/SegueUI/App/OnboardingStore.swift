#if os(macOS)
    import Foundation
    import Observation

    /// The first-run flow's answers (WS2b section 3): whether the flow finished, the answer to
    /// the Welcome songs page and the last Welcome seed. The only writer of its keys.
    ///
    /// `onboarding.completed` has three states on purpose: absent means a pre-WS2b install
    /// (an upgrader, never shown the flow), `false` means the flow started and was not
    /// finished (resume it), `true` means done.
    @MainActor
    @Observable
    public final class OnboardingStore {
        /// The answer to "Welcome to Segue" (page 2).
        public enum WelcomeDecision: String, Sendable {
            case added
            case declined
        }

        /// What the last Welcome seed created ("Remove Welcome Songs" finds the demo setlist
        /// by its ID).
        public struct SeedRecord: Codable, Equatable, Sendable {
            public var seededAt: Date
            public var libraryPath: String
            public var songIDs: [String]
            public var setlistID: String?

            public init(
                seededAt: Date,
                libraryPath: String,
                songIDs: [String],
                setlistID: String?,
            ) {
                self.seededAt = seededAt
                self.libraryPath = libraryPath
                self.songIDs = songIDs
                self.setlistID = setlistID
            }
        }

        static let completedKey = "onboarding.completed"
        static let decisionKey = "welcome.decision"
        static let seededKey = "welcome.seeded"

        @ObservationIgnored private let defaults: UserDefaults

        /// nil: never started (an upgrader or a brand-new install before the flow begins).
        public private(set) var completed: Bool?
        public private(set) var decision: WelcomeDecision?
        public private(set) var seed: SeedRecord?

        public init(defaults: UserDefaults) {
            self.defaults = defaults
            completed = defaults.object(forKey: Self.completedKey) as? Bool
            decision = defaults.string(forKey: Self.decisionKey).flatMap(WelcomeDecision.init)
            seed = defaults.data(forKey: Self.seededKey).flatMap { data in
                try? Self.decoder.decode(SeedRecord.self, from: data)
            }
        }

        /// The flow has finished.
        public var isCompleted: Bool {
            completed == true
        }

        /// The flow started: it is resumed on the next launch until it finishes.
        func markStarted() {
            guard completed != true else { return }
            set(completed: false)
        }

        func markCompleted() {
            set(completed: true)
        }

        /// An install from before the Welcome flow existed: never shown it, never seeded.
        func markUpgrader() {
            set(completed: true)
            record(.declined)
        }

        func record(_ decision: WelcomeDecision) {
            self.decision = decision
            defaults.set(decision.rawValue, forKey: Self.decisionKey)
        }

        func recordSeed(_ record: SeedRecord) {
            seed = record
            if let data = try? Self.encoder.encode(record) {
                defaults.set(data, forKey: Self.seededKey)
            }
        }

        /// `-SegueOnboarding fresh`: forget every answer so the full flow runs again.
        func resetForTesting() {
            completed = nil
            decision = nil
            seed = nil
            for key in [Self.completedKey, Self.decisionKey, Self.seededKey] {
                defaults.removeObject(forKey: key)
            }
        }

        private func set(completed value: Bool) {
            completed = value
            defaults.set(value, forKey: Self.completedKey)
        }

        private static let encoder: JSONEncoder = {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            return encoder
        }()

        private static let decoder: JSONDecoder = {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return decoder
        }()
    }
#endif
