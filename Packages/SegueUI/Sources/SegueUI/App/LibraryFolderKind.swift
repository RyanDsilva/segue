#if os(macOS)
    import Foundation

    /// Whether a library folder sits in a file-sync service's folder (P9-6 5.4). Such a
    /// service can move a song off the Mac to save space (an evicted placeholder), so the
    /// library warns, gently: it never refuses the folder.
    public enum LibraryFolderKind: Equatable, Sendable {
        /// An ordinary folder on this Mac.
        case local
        /// iCloud Drive, including Desktop and Documents in iCloud.
        case iCloudDrive
        /// A File Provider service under `~/Library/CloudStorage` (Dropbox, Google Drive,
        /// OneDrive, Box): its display name.
        case fileProvider(String)

        /// Detects the kind of `url`: iCloud Drive when the folder is a ubiquitous item;
        /// otherwise by its real path under `<home>/Library/CloudStorage/<provider>` or
        /// `<home>/Library/Mobile Documents/`. `home` is the real home folder (the sandboxed
        /// `homeDirectory` is the container); `isUbiquitous` reads the resource value
        /// (injected in tests).
        @MainActor
        public static func detect(
            _ url: URL,
            home: URL? = nil,
            isUbiquitous: (URL) -> Bool? = Self.isUbiquitousItem,
        ) -> Self {
            if isUbiquitous(url) == true {
                return .iCloudDrive
            }
            let path = realPath(url)
            let library = realPath(home ?? LibraryLocation.realHomeDirectory) + "Library/"
            let cloudStorage = library + "CloudStorage/"
            if path.hasPrefix(cloudStorage) {
                let folder = path.dropFirst(cloudStorage.count).prefix { $0 != "/" }
                return folder.isEmpty ? .local : .fileProvider(providerName(String(folder)))
            }
            if path.hasPrefix(library + "Mobile Documents/") {
                return .iCloudDrive
            }
            return .local
        }

        /// `URLResourceValues.isUbiquitousItem` of `url`; nil when it cannot be read.
        public static func isUbiquitousItem(_ url: URL) -> Bool? {
            (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem
        }

        /// The service's display name from its CloudStorage folder name, which is the
        /// provider then an account part (`Dropbox-Personal`, `GoogleDrive-name@example.com`):
        /// only the provider is kept, never the account.
        static func providerName(_ folder: String) -> String {
            let provider = String(folder.prefix { $0 != "-" })
            return knownProviders[provider] ?? provider
        }

        private static let knownProviders = [
            "GoogleDrive": "Google Drive",
            "OneDrive": "OneDrive",
            "Dropbox": "Dropbox",
            "Box": "Box",
            "pCloudDrive": "pCloud Drive",
        ]

        /// The folder's path with symlinks resolved, ending in `/`.
        private static func realPath(_ url: URL) -> String {
            let path = url.resolvingSymlinksInPath().standardizedFileURL
                .path(percentEncoded: false)
            return path.hasSuffix("/") ? path : path + "/"
        }

        /// Whether a file-sync service holds the folder.
        public var isFileSynced: Bool {
            self != .local
        }

        /// "iCloud Drive", "Dropbox", ...; nil for a local folder.
        public var serviceName: String? {
            switch self {
            case .local: nil
            case .iCloudDrive: "iCloud Drive"
            case let .fileProvider(name): name
            }
        }

        /// The warning's first sentence: "This library is in iCloud Drive."
        public var warningTitle: String? {
            serviceName.map { "This library is in \($0)." }
        }

        /// The rest of the warning (5.4).
        public static let warningDetail = "Files there can be moved off this Mac to save "
            + "space, so a song might not be here at a gig. To keep both Macs in step, use "
            + "Settings > Sync, which keeps every song on this Mac."

        /// The whole warning, for Settings > Data.
        public var warning: String? {
            warningTitle.map { "\($0) \(Self.warningDetail)" }
        }
    }
#endif
