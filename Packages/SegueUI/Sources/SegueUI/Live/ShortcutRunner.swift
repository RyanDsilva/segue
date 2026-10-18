#if os(macOS)
    import AppKit
    import Foundation

    /// Runs one of the user's Shortcuts by name ("Gig Mode On"). A sandboxed app has no API
    /// to turn on Focus, so show start and end delegate to a Shortcut the user owns
    /// (decisions.md, phase 2).
    @MainActor
    public protocol ShortcutRunner: AnyObject {
        /// Asks Shortcuts to run `name` and reports what was observed. Hand-over is not
        /// completion: only `.completed` means the Shortcut was seen to finish (R18).
        func run(_ name: String) async -> ShortcutOutcome
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
    /// Shortcuts forward.
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
        /// Test-only runner (`-SegueShortcutLog <file>`, Debug builds): never opens Shortcuts;
        /// appends each name it was asked to run as one line to `log`, so the E2E suite can
        /// assert both hooks fired. A name starting with "fail" fails, one starting with
        /// "hang" is only handed over (exercising the confirmation timeout), and any other
        /// name completes.
        @MainActor
        public final class RecordingShortcutRunner: ShortcutRunner {
            public let log: URL
            public private(set) var names: [String] = []

            public init(log: URL) {
                self.log = log
            }

            public func run(_ name: String) async -> ShortcutOutcome {
                names.append(name)
                do {
                    try append(name)
                } catch {
                    return .failed("could not write the Shortcut log (\(error))")
                }
                let lowered = name.lowercased()
                if lowered.hasPrefix("fail") {
                    return .failed("simulated failure")
                }
                if lowered.hasPrefix("hang") {
                    return .handedOver
                }
                return .completed
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
