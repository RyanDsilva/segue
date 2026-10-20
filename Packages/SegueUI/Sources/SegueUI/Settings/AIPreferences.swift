#if os(macOS)
    import Foundation
    import Observation

    /// Settings > AI preferences (R93): the one toggle "Use AI to refine pastes and set
    /// requests", default on. The router reads it through `AIGate.isEnabled`, which this store
    /// keeps in step. Reset All Settings clears it (R73); downloaded models are kept.
    @MainActor
    @Observable
    public final class AIPreferences {
        static let useAIKey = "ai.useAI"

        @ObservationIgnored private let defaults: UserDefaults
        @ObservationIgnored private let gate: AIGate

        /// Off: no provider is asked for pastes or set requests; the deterministic result
        /// stands.
        public var useAI: Bool {
            didSet {
                guard useAI != oldValue else { return }
                if useAI {
                    defaults.removeObject(forKey: Self.useAIKey)
                } else {
                    defaults.set(false, forKey: Self.useAIKey)
                }
                gate.isEnabled = useAI
            }
        }

        public init(defaults: UserDefaults, gate: AIGate) {
            self.defaults = defaults
            self.gate = gate
            useAI = defaults.object(forKey: Self.useAIKey) as? Bool ?? true
            gate.isEnabled = useAI
        }

        /// Reset All Settings: back to on.
        public func reset() {
            useAI = true
            defaults.removeObject(forKey: Self.useAIKey)
        }
    }
#endif
