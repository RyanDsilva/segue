#if os(macOS)
    import AppKit
    import Foundation
    import ModelPort
    import Observation
    import SwiftUI
    import Synchronization

    /// The switches every routed call reads (Sendable, so the router can read them from any
    /// task): the AI toggle (R93; P3-3 stores it and sets `isEnabled`) and whether a show is
    /// running (R65, R95: no model loads during a show; the show flow sets `isShowRunning`).
    public final class AIGate: Sendable {
        private let state = Mutex((isEnabled: true, isShowRunning: false))

        public init(isEnabled: Bool = true) {
            state.withLock { $0.isEnabled = isEnabled }
        }

        public var isEnabled: Bool {
            get { state.withLock { $0.isEnabled } }
            set { state.withLock { $0.isEnabled = newValue } }
        }

        public var isShowRunning: Bool {
            get { state.withLock { $0.isShowRunning } }
            set { state.withLock { $0.isShowRunning = newValue } }
        }
    }

    /// The app's AI composition (P3-2): the providers the app target links (Foundation Models
    /// now, MLX with P3-3), the config-driven router, and each provider's availability for the
    /// R69 notes. P3-3 (Settings > AI), P3-4 (paste review sheet) and P3-7 (set assistant)
    /// consume it through `AppDependencies.ai`.
    @MainActor
    @Observable
    public final class AIServices {
        /// The bundled provider order per task (`App/AIConfig/routing.json`).
        public static let bundledPolicy: RoutingPolicy = {
            guard let url = Bundle.module.url(
                forResource: "routing", withExtension: "json", subdirectory: "AIConfig",
            ),
                let data = try? Data(contentsOf: url),
                let policy = try? RoutingPolicy.decode(data)
            else { return .standard }
            return policy
        }()

        public let gate: AIGate
        public let router: Router
        /// The last availability read per provider kind (`refreshAvailability`).
        public private(set) var availability: [ProviderKind: ProviderAvailability] = [:]
        /// Settings > AI's toggle (P3-3, R93); it sets `gate.isEnabled`.
        public let preferences: AIPreferences
        /// Settings > AI's model card (P3-3): the shared model store, if this build has one.
        public let models: LocalModelsModel
        /// Settings > AI > Advanced, supplied by the Personal build only (R62, R97).
        public var advancedSection: (@MainActor () -> AnyView)?

        public init(
            providers: [any LanguageModelProvider],
            policy: RoutingPolicy = AIServices.bundledPolicy,
            gate: AIGate = AIGate(),
            defaults: UserDefaults = .standard,
            installer: (any LocalModelInstaller)? = nil,
            physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory,
        ) {
            self.gate = gate
            preferences = AIPreferences(defaults: defaults, gate: gate)
            models = LocalModelsModel(installer: installer, physicalMemory: physicalMemory)
            router = Router(
                providers: providers,
                policy: policy,
                isEnabled: { gate.isEnabled },
                isShowRunning: { gate.isShowRunning },
            )
        }

        /// No providers: every call keeps the deterministic result (tests, previews, and the
        /// default until the app target passes its providers).
        public static func deterministicOnly() -> AIServices {
            AIServices(providers: [])
        }

        /// Re-reads every provider's availability (Settings > AI and the review sheet call it
        /// when they appear; Apple Intelligence can be switched on while the app runs).
        public func refreshAvailability() async {
            var result: [ProviderKind: ProviderAvailability] = [:]
            for provider in router.providers {
                result[provider.id.kind] = await provider.availability()
            }
            for kind in ProviderKind.allCases where result[kind] == nil {
                result[kind] = .unavailable(.notInstalled)
            }
            availability = result
            // The quiet download links read the model store too (R120).
            await models.refresh()
        }

        /// The R69 note for Foundation Models, or nil when it is available (or not read yet).
        public var foundationModelsNote: AIAvailabilityCopy.Note? {
            guard case let .unavailable(cause) = availability[.foundationModels] else { return nil }
            return AIAvailabilityCopy.note(for: cause)
        }
    }

    public extension AppModel {
        /// The app's AI composition (`AppDependencies.ai`).
        var ai: AIServices {
            dependencies.ai
        }
    }

    /// R69 copy (spec 4.2): a reason-specific inline note, never a nag prompt, with the
    /// "Open System Settings" action where it helps. Drafted here; final wording in P3-9
    /// (Apple Intelligence trademark use is a WS5-stage question, spec 16.2).
    public enum AIAvailabilityCopy {
        public struct Note: Equatable, Sendable {
            public var text: String
            /// Whether to offer "Open System Settings".
            public var opensSettings: Bool
        }

        public static let openSettingsTitle = "Open System Settings"

        /// The Apple Intelligence & Siri pane of System Settings.
        public static let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.Siri-Settings.extension",
        )

        /// The note for an unavailable Foundation Models provider; nil for causes that are not
        /// about Apple Intelligence (`notInstalled`, `duringShow`).
        public static func note(for cause: UnavailableCause) -> Note? {
            switch cause {
            case .appleIntelligenceNotEnabled:
                Note(
                    text: "Turn on Apple Intelligence in System Settings to use it for cleanup.",
                    opensSettings: true,
                )
            case .modelNotReady:
                Note(
                    text: "Apple Intelligence is still getting ready. "
                        + "Segue will use it once it is.",
                    opensSettings: true,
                )
            case .deviceNotEligible:
                Note(text: "This Mac doesn't support Apple Intelligence.", opensSettings: false)
            case .unknown:
                Note(text: "Apple Intelligence isn't available right now.", opensSettings: true)
            case .duringShow, .notInstalled:
                nil
            }
        }

        /// Opens the Apple Intelligence & Siri settings pane.
        @MainActor
        public static func openSettings(with workspace: any WorkspaceActions) {
            guard let settingsURL else { return }
            workspace.open(settingsURL)
        }
    }
#endif
