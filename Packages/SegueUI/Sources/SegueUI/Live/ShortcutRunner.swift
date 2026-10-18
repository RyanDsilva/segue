#if os(macOS)
    import AppKit
    import Foundation

    /// Runs one of the user's Shortcuts by name ("Gig Mode On"). A sandboxed app has no API
    /// to turn on Focus, so show start and end delegate to a Shortcut the user owns
    /// (decisions.md, phase 2). The app runs them through Shortcuts Events
    /// (`AppleEventShortcutRunner`, docs/release/decisions.md R59).
    @MainActor
    public protocol ShortcutRunner: AnyObject {
        /// Asks Shortcuts to run `name` and reports what was observed. Hand-over is not
        /// completion: only `.completed` means the Shortcut was seen to finish (R18). Never
        /// shows a system prompt (it runs mid-show).
        func run(_ name: String) async -> ShortcutOutcome
        /// Like `run`, but may show the one-time system permission prompt first (Settings >
        /// Live "Test", so the prompt never first appears during a show).
        func runAskingPermission(_ name: String) async -> ShortcutOutcome
    }

    public extension ShortcutRunner {
        func runAskingPermission(_ name: String) async -> ShortcutOutcome {
            await run(name)
        }
    }

    /// What a runner observed about one Shortcut run.
    public enum ShortcutOutcome: Equatable, Sendable {
        /// The Shortcut was observed to finish without error.
        case completed
        /// The request was delivered to Shortcuts; whether it finished is unknown.
        case handedOver
        /// Observed failure (not found, not permitted, the Shortcut's own error, or the
        /// request could not be delivered), with a message for the performer.
        case failed(String)
    }

    /// How long a handed-over start Shortcut may stay unconfirmed before the checklist says
    /// it could not confirm it (measured on the live clock).
    public enum ShortcutTiming {
        public static let confirmTimeout: TimeInterval = 30
    }

    /// Why a Shortcut did not run.
    public enum ShortcutRunError: Error, Equatable, LocalizedError {
        case invalidName(String)
        case openFailed(String)

        public var errorDescription: String? {
            switch self {
            case let .invalidName(name): "“\(name)” is not a valid Shortcut name."
            case let .openFailed(message): "Shortcuts could not be opened (\(message))."
            }
        }
    }

    /// The URL runner: opens `shortcuts://run-shortcut?name=...` without activating
    /// Shortcuts. It can only hand the request over, never observe completion, so it returns
    /// `.handedOver` (or `.failed` when the URL could not be opened). The caller re-asserts
    /// its own window as key afterwards (`LiveFocus`), since some macOS versions still bring
    /// Shortcuts forward. Kept as the fallback behind this protocol (R59 risk: Path AI); the
    /// app uses `AppleEventShortcutRunner`.
    @MainActor
    public final class WorkspaceShortcutRunner: ShortcutRunner {
        public init() {}

        public func run(_ name: String) async -> ShortcutOutcome {
            guard let url = Self.url(for: name) else {
                return .failed(ShortcutRunError.invalidName(name).localizedDescription)
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.addsToRecentItems = false
            do {
                _ = try await NSWorkspace.shared.open(url, configuration: configuration)
                return .handedOver
            } catch {
                return .failed(
                    ShortcutRunError.openFailed(error.localizedDescription).localizedDescription,
                )
            }
        }

        /// `shortcuts://run-shortcut?name=<name>`, percent-encoded.
        static func url(for name: String) -> URL? {
            var components = URLComponents()
            components.scheme = "shortcuts"
            components.host = "run-shortcut"
            components.queryItems = [URLQueryItem(name: "name", value: name)]
            return components.url
        }
    }

    #if DEBUG
        /// Test-only runner (`-SegueShortcutLog <file>`, Debug builds): the production
        /// `AppleEventShortcutRunner` talking to `RecordingShortcutsEvents` instead of the
        /// real Shortcuts Events, so the E2E suite exercises the real reply mapping without
        /// the user's Shortcuts or an Automation prompt.
        @MainActor
        public final class RecordingShortcutRunner: ShortcutRunner {
            public let log: URL
            private let runner: AppleEventShortcutRunner

            public init(log: URL) {
                self.log = log
                runner = AppleEventShortcutRunner(events: RecordingShortcutsEvents(log: log))
            }

            public func run(_ name: String) async -> ShortcutOutcome {
                await runner.run(name)
            }

            public func runAskingPermission(_ name: String) async -> ShortcutOutcome {
                await runner.runAskingPermission(name)
            }
        }

        /// A stand-in for Shortcuts Events that never sends an Apple event: permission is
        /// always granted, and each name it is asked to run is appended as one line to `log`
        /// (so the E2E suite can assert both hooks fired) and answered like the real one
        /// (probe results, research 09) by its prefix:
        ///
        /// - `fail…`: the Shortcut's own error (`-1753`, "simulated failure")
        /// - `missing…`: no such Shortcut (`-1728`)
        /// - `denied…`: Automation turned off (`-1743`)
        /// - `hang…`: no reply in time (`-1712`), so the run is only handed over
        /// - anything else: finished.
        public struct RecordingShortcutsEvents: ShortcutsEvents {
            public let log: URL

            public init(log: URL) {
                self.log = log
            }

            public func permission(askUserIfNeeded _: Bool) async -> OSStatus {
                OSStatus(noErr)
            }

            public func run(_ name: String) async -> ShortcutsEventsReply {
                do {
                    try append(name)
                } catch {
                    return ShortcutsEventsReply(
                        errorNumber: -1,
                        errorMessage: "could not write the Shortcut log (\(error))",
                    )
                }
                let lowered = name.lowercased()
                return if lowered.hasPrefix("fail") {
                    ShortcutsEventsReply(errorNumber: -1753, errorMessage: "simulated failure.")
                } else if lowered.hasPrefix("missing") {
                    ShortcutsEventsReply(errorNumber: -1728)
                } else if lowered.hasPrefix("denied") {
                    ShortcutsEventsReply(errorNumber: -1743)
                } else if lowered.hasPrefix("hang") {
                    ShortcutsEventsReply(errorNumber: -1712)
                } else {
                    .finished
                }
            }

            private func append(_ name: String) throws {
                let line = Data((name + "\n").utf8)
                if let handle = try? FileHandle(forWritingTo: log) {
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: line)
                } else {
                    try line.write(to: log, options: .atomic)
                }
            }
        }
    #endif
#endif
