#if os(macOS)
    import AppKit
    import Foundation

    /// Where the library folder lives. Persists the user's choice as a security-scoped bookmark
    /// in `UserDefaults`, resolves it on launch and keeps the folder's security scope open while
    /// the library is in use.
    @MainActor
    public final class LibraryLocation {
        /// Result of resolving the stored bookmark.
        public enum Resolution: Equatable {
            /// No library has been chosen yet (first launch).
            case notChosen
            /// The bookmark resolved and the folder is accessible.
            case resolved(URL)
            /// A bookmark exists but no longer grants access (moved, deleted, stale); the user
            /// must choose the folder again. Carries the last known location, if any.
            case lost(URL?)
        }

        static let bookmarkKey = "libraryFolderBookmark"

        /// The app's defaults (the test suite in test runs); session restore keeps its
        /// per-library state here too.
        let defaults: UserDefaults
        private let makeBookmark: @MainActor (URL) throws -> Data
        private var accessedURL: URL?

        public convenience init(defaults: UserDefaults) {
            self.init(defaults: defaults, makeBookmark: Self.securityScopedBookmark)
        }

        /// - Parameter makeBookmark: creates the bookmark data for a folder (tests inject
        ///   failures here).
        init(defaults: UserDefaults, makeBookmark: @escaping @MainActor (URL) throws -> Data) {
            self.defaults = defaults
            self.makeBookmark = makeBookmark
        }

        static func securityScopedBookmark(for url: URL) throws -> Data {
            try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil,
            )
        }

        /// The suggested library location, `~/Music/Segue` (decisions.md). Uses the real home
        /// folder, not the sandbox container.
        public static var suggestedFolder: URL {
            musicFolder.appending(path: "Segue", directoryHint: .isDirectory)
        }

        static var musicFolder: URL {
            realHomeDirectory.appending(path: "Music", directoryHint: .isDirectory)
        }

        /// The user's home folder. `FileManager.homeDirectoryForCurrentUser` points into the
        /// sandbox container, so read the password database instead.
        static var realHomeDirectory: URL {
            if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
                return URL(filePath: String(cString: directory), directoryHint: .isDirectory)
            }
            return FileManager.default.homeDirectoryForCurrentUser
        }

        /// Resolves the stored bookmark and starts accessing the folder. A stale bookmark that
        /// still grants access is refreshed in place; one that does not is reported as `.lost`
        /// so the caller re-prompts.
        public func resolveStored() -> Resolution {
            guard let data = defaults.data(forKey: Self.bookmarkKey) else { return .notChosen }
            var isStale = false
            let url: URL
            do {
                url = try URL(
                    resolvingBookmarkData: data,
                    options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale,
                )
            } catch {
                return .lost(nil)
            }
            guard let access = startAccess(url) else { return .lost(url) }
            if isStale {
                do {
                    try remember(url)
                } catch {
                    abandon(access)
                    return .lost(url)
                }
            }
            commit(access)
            return .resolved(url)
        }

        /// Persists `url` as the library folder. The caller must have access to it (it came
        /// from an open/save panel or a resolved bookmark).
        public func remember(_ url: URL) throws {
            let data = try makeBookmark(url)
            defaults.set(data, forKey: Self.bookmarkKey)
        }

        /// A folder whose security scope has been started but not yet adopted as the
        /// library. Pass it to `commit(_:)` once the library opens, or `abandon(_:)` if it
        /// does not, so the current library's scope is only released after the new one opened.
        public struct PendingAccess {
            public let url: URL
            /// Whether `startAccessingSecurityScopedResource` began a scope that must be ended.
            let startedScope: Bool
        }

        /// Starts accessing `url` without touching the current library's scope. Returns nil
        /// if the folder is not accessible.
        public func startAccess(_ url: URL) -> PendingAccess? {
            // Panel-granted URLs are accessible without a security scope, so `false` here is
            // only a failure for bookmark-resolved URLs; reachability is checked as well.
            let started = url.startAccessingSecurityScopedResource()
            guard started || FileManager.default.isReadableFile(atPath: url.path) else {
                return nil
            }
            return PendingAccess(url: url, startedScope: started)
        }

        /// Adopts `access` as the library folder's scope, then releases the previous one.
        public func commit(_ access: PendingAccess) {
            let previous = accessedURL
            accessedURL = access.startedScope ? access.url : nil
            previous?.stopAccessingSecurityScopedResource()
        }

        /// Ends a scope started by `startAccess` whose library never opened. The current
        /// library's scope is untouched.
        public func abandon(_ access: PendingAccess) {
            if access.startedScope {
                access.url.stopAccessingSecurityScopedResource()
            }
        }

        /// Stops accessing the current library folder.
        public func endAccess() {
            accessedURL?.stopAccessingSecurityScopedResource()
            accessedURL = nil
        }

        /// Shows an open panel for an existing folder. Returns nil if the user cancels.
        public func chooseExistingFolder(startingAt hint: URL?) async -> URL? {
            let panel = NSOpenPanel()
            panel.title = "Choose Library Folder"
            panel.message = "Choose the folder that holds your Segue songs and setlists."
            panel.prompt = "Use as Library"
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.directoryURL = Self.existingDirectory(hint) ?? Self.existingDirectory(
                Self.suggestedFolder,
            ) ?? Self.musicFolder
            let response = await run(panel)
            return response == .OK ? panel.url : nil
        }

        /// Shows a save panel for a new library folder, suggesting `~/Music/Segue`, and
        /// creates the folder. Returns nil if the user cancels.
        public func createFolder() async throws -> URL? {
            let panel = NSSavePanel()
            panel.title = "Create Library"
            panel.message = "Segue keeps your songs as plain ChordPro files in this folder."
            panel.prompt = "Create Library"
            panel.nameFieldLabel = "Library name:"
            panel.nameFieldStringValue = "Segue"
            panel.canCreateDirectories = true
            panel.directoryURL = Self.musicFolder
            let response = await run(panel)
            guard response == .OK, let url = panel.url else { return nil }
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        private func run(_ panel: NSSavePanel) async -> NSApplication.ModalResponse {
            await withCheckedContinuation { continuation in
                panel.begin { response in
                    continuation.resume(returning: response)
                }
            }
        }

        private static func existingDirectory(_ url: URL?) -> URL? {
            guard let url else { return nil }
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return exists && isDirectory.boolValue ? url : nil
        }
    }
#endif
