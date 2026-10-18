#if os(macOS)
    import AppKit
    import Foundation

    /// Runs one of the user's Shortcuts by name ("Gig Mode On"). A sandboxed app has no API
    /// to turn on Focus, so show start and end delegate to a Shortcut the user owns
    /// (decisions.md, phase 2).
    @MainActor
    public protocol ShortcutRunner: AnyObject {
        /// Asks Shortcuts to run `name`. Throws when the request could not be handed over
        /// (no Shortcuts app, the URL was refused). Success means the request was delivered,
        /// not that the Shortcut finished.
        func run(_ name: String) async throws
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

    /// The real runner: opens `shortcuts://run-shortcut?name=...` without activating
    /// Shortcuts. The caller re-asserts its own window as key afterwards (`LiveFocus`), since
    /// some macOS versions still bring Shortcuts forward.
    @MainActor
    public final class WorkspaceShortcutRunner: ShortcutRunner {
        public init() {}

        public func run(_ name: String) async throws {
            guard let url = Self.url(for: name) else { throw ShortcutRunError.invalidName(name) }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.addsToRecentItems = false
            do {
                _ = try await NSWorkspace.shared.open(url, configuration: configuration)
            } catch {
                throw ShortcutRunError.openFailed(error.localizedDescription)
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
        /// assert both hooks fired. A name starting with "fail" throws, to exercise the
        /// unticked "Focus on" row.
        @MainActor
        public final class RecordingShortcutRunner: ShortcutRunner {
            public let log: URL
            public private(set) var names: [String] = []

            public init(log: URL) {
                self.log = log
            }

            public func run(_ name: String) async throws {
                names.append(name)
                let line = Data((name + "\n").utf8)
                if let handle = try? FileHandle(forWritingTo: log) {
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: line)
                } else {
                    try line.write(to: log, options: .atomic)
                }
                if name.lowercased().hasPrefix("fail") {
                    throw ShortcutRunError.openFailed("test failure")
                }
            }
        }
    #endif
#endif
