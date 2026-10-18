#if os(macOS)
    import AppKit
    import Foundation

    /// Opening links and revealing files (WS2a 3.12): the live one hands them to the system;
    /// the E2E double records them. Links always open in the default browser, never in an
    /// in-app web view.
    @MainActor
    public protocol WorkspaceActions: AnyObject {
        /// Opens `url` in its default app (browser, Mail, App Store).
        func open(_ url: URL)
        /// Shows `urls` selected in Finder.
        func reveal(_ urls: [URL])
    }

    /// `NSWorkspace`.
    @MainActor
    public final class NSWorkspaceActions: WorkspaceActions {
        public init() {}

        public func open(_ url: URL) {
            NSWorkspace.shared.open(url)
        }

        public func reveal(_ urls: [URL]) {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    #if DEBUG
        /// Test-only (`-SegueWorkspaceLog <file>`, Debug builds): opens and reveals nothing;
        /// appends one JSON line per call to `log`, e.g.
        /// `{"action":"open","urls":["https://…"]}`, so E2E can assert every link.
        @MainActor
        public final class RecordingWorkspaceActions: WorkspaceActions {
            public let log: URL

            public init(log: URL) {
                self.log = log
            }

            public func open(_ url: URL) {
                append(action: "open", urls: [url])
            }

            public func reveal(_ urls: [URL]) {
                append(action: "reveal", urls: urls)
            }

            private struct Entry: Encodable {
                var action: String
                var urls: [String]
            }

            private func append(action: String, urls: [URL]) {
                let entry = Entry(
                    action: action,
                    urls: urls.map { url in
                        url.isFileURL ? url.path(percentEncoded: false) : url.absoluteString
                    },
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                guard let json = try? encoder.encode(entry) else { return }
                let line = json + Data("\n".utf8)
                if let handle = try? FileHandle(forWritingTo: log) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: line)
                } else {
                    try? line.write(to: log, options: .atomic)
                }
            }
        }
    #endif
#endif
