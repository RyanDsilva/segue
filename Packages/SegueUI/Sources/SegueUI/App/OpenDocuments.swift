#if os(macOS)
    import AppKit
    import Library

    // WS2b 4.7: Finder's Open With and double-click. A song already in the open library is
    // selected; a file elsewhere is copied in through the import (A31). Nothing happens on
    // stage or during the Welcome flow: requests wait and run afterwards.

    /// Hands files from the app delegate to the model, holding them until it exists.
    @MainActor
    final class OpenDocuments {
        static let shared = OpenDocuments()

        weak var app: AppModel? {
            didSet { flush() }
        }

        private var waiting: [URL] = []

        func open(_ urls: [URL]) {
            waiting.append(contentsOf: urls)
            flush()
        }

        private func flush() {
            guard let app, !waiting.isEmpty else { return }
            let urls = waiting
            waiting = []
            app.requestOpen(urls)
        }
    }

    public extension SegueAppDelegate {
        func application(_: NSApplication, open urls: [URL]) {
            MainActor.assumeIsolated {
                OpenDocuments.shared.open(urls)
            }
        }
    }

    extension AppModel {
        /// Shown for anything that is not a song file Segue reads.
        static let notASongMessage = "Segue can only open ChordPro song files."

        /// Opens `urls` now, or queues them until the library is open, the Welcome flow is
        /// over and no show is on stage or starting.
        func requestOpen(_ urls: [URL]) {
            pendingOpenURLs.append(contentsOf: urls)
            runQueuedOpenRequests()
        }

        /// Runs the queued requests when nothing is in the way (called again when the flow
        /// finishes and when a show ends).
        func runQueuedOpenRequests() {
            guard !pendingOpenURLs.isEmpty, let session, onboarding.mode != .flow,
                  !isPerforming, !isStartingShow
            else { return }
            let urls = pendingOpenURLs
            pendingOpenURLs = []
            PendingEditsGuard.shared.reopenMainWindow?()
            NSApp?.activate()
            Task { await open(urls, in: session) }
        }

        private func open(_ urls: [URL], in session: LibrarySession) async {
            let accepted = Set(SongFileTypes.importExtensions)
            let songs = urls.filter { accepted.contains($0.pathExtension.lowercased()) }
            if songs.count < urls.count {
                session.library.errorMessage = Self.notASongMessage
            }
            guard !songs.isEmpty else { return }
            let songsFolder = Self.canonicalPath(session.root.songsDirectory)
            let inside = songs.filter {
                Self.canonicalPath($0.deletingLastPathComponent()) == songsFolder
            }
            let outside = songs.filter { !inside.contains($0) }
            if let first = inside.first {
                await session.refreshFromDisk()
                let name = first.lastPathComponent
                if let record = session.library.catalog.first(where: {
                    ($0.relativePath as NSString).lastPathComponent == name
                }) {
                    session.section = .library
                    session.library.select(record.id)
                } else {
                    session.library.errorMessage = Self.notASongMessage
                }
            }
            if !outside.isEmpty {
                session.section = .library
                await session.library.importSongs(outside, method: .openWith)
            }
        }

        private static func canonicalPath(_ url: URL) -> String {
            url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
    }
#endif
