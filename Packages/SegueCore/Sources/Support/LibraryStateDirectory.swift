import Foundation

/// Where per-library machine state lives (P9-6 5.2): the Application Support folder of the
/// app group both flavours share, so the library lock still keeps the Personal and App Store
/// builds off one library at once.
///
/// ```
/// <base>/Libraries/<libraryID>/   one LibraryStateDirectory per library
/// ```
///
/// The app uses `appGroup(bundleID:)`; tests and E2E runs (`-SegueStatePath`) pass a folder
/// of their own, so every run starts from a clean state.
public struct LibraryStateLocation: Sendable, Hashable {
    /// The team-prefixed app group both flavours share (R67, R100): the same group as the
    /// model store (`ModelStoreLocation.appGroupID`). It is already in every entitlements
    /// file and needs no portal registration.
    public static let appGroupID = "V6BM673U35.dev.ryandsilva.segue.models"

    /// The folder that holds `Libraries/`.
    public let base: URL
    /// Whether both flavours see this location. False for the fallback (the group container
    /// was unreachable): the cross-flavour library lock is then lost, and Settings > Data
    /// says so.
    public let isShared: Bool

    public init(base: URL, isShared: Bool = true) {
        self.base = base.standardizedFileURL
        self.isShared = isShared
    }

    /// `<group container>/Library/Application Support`, or, when the group container is
    /// unreachable (a build without the entitlement, command-line tools), this flavour's own
    /// `Application Support/<bundle id>` with `isShared` false.
    public static func appGroup(
        bundleID: String,
        fileManager: FileManager = .default,
    ) -> Self {
        if let group = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID,
        ) {
            let base = group.appending(
                path: "Library/Application Support",
                directoryHint: .isDirectory,
            )
            // macOS returns a URL even when the sandbox will refuse it: prove it is usable.
            let libraries = base.appending(path: librariesName, directoryHint: .isDirectory)
            if (try? fileManager.createDirectory(at: libraries, withIntermediateDirectories: true))
                != nil
            {
                return Self(base: base)
            }
        }
        return Self(
            base: URL.applicationSupportDirectory.appending(
                path: bundleID,
                directoryHint: .isDirectory,
            ),
            isShared: false,
        )
    }

    static let librariesName = "Libraries"

    /// `<base>/Libraries`: one folder per library ID.
    public var librariesDirectory: URL {
        base.appending(path: Self.librariesName, directoryHint: .isDirectory)
    }

    /// The state directory of library `id`.
    public func directory(for id: ULID) -> LibraryStateDirectory {
        LibraryStateDirectory(base: base, libraryID: id)
    }
}

/// One library's machine state, outside the library folder (P9-6 5.2):
///
/// ```
/// <base>/Libraries/<libraryID>/
///   index.sqlite (+ -wal, -shm)   the SongIndex (rebuildable)
///   library.lock                  LibraryLock's flock
///   shows/<showULID>.show.lock    ShowClaim's flock
///   state.json                    LibraryStateRecord
/// ```
///
/// Nothing here is user data: the folder can be deleted at any time while the library is
/// closed (the TTL backstop does, `LibraryState.pruneStale`).
public struct LibraryStateDirectory: Sendable, Hashable {
    public let libraryID: ULID
    /// `<base>/Libraries/<libraryID>`.
    public let url: URL

    public init(base: URL, libraryID: ULID) {
        self.libraryID = libraryID
        url = base.standardizedFileURL
            .appending(path: LibraryStateLocation.librariesName, directoryHint: .isDirectory)
            .appending(path: libraryID.description, directoryHint: .isDirectory)
    }

    /// The rebuildable GRDB index. Safe to delete.
    public var indexDatabase: URL {
        url.appending(path: "index.sqlite", directoryHint: .notDirectory)
    }

    /// Held with `flock` by the copy of Segue that has the library open (`LibraryLock`).
    public var lockURL: URL {
        url.appending(path: "library.lock", directoryHint: .notDirectory)
    }

    /// The show claims' folder.
    public var showsDirectory: URL {
        url.appending(path: "shows", directoryHint: .isDirectory)
    }

    /// Show `id`'s claim file (`ShowClaim`).
    public func showLockURL(_ id: ULID) -> URL {
        showsDirectory.appending(path: id.description + ".show.lock", directoryHint: .notDirectory)
    }

    /// `state.json`: `LibraryStateRecord`.
    public var stateFile: URL {
        url.appending(path: "state.json", directoryHint: .notDirectory)
    }
}

/// `state.json` in a library's state directory.
public struct LibraryStateRecord: Sendable, Equatable, Codable {
    /// The library folder's path at its last open (for diagnosis; detection uses the two
    /// fields below).
    public var lastRoot: String?
    /// The folder's file identifier (its inode) at its last open (R185, 5.2).
    public var rootIdentifier: UInt64?
    /// A security-scoped bookmark to the folder at its last open: it follows a move and
    /// finds the original when this folder turns out to be a copy (R185, 5.2).
    public var rootBookmark: Data?
    /// When the library was last opened (the TTL backstop).
    public var lastOpened: Date?
    /// "Don't Show Again" on the file-sync folder warning (5.4).
    public var fileSyncWarningDismissed: Bool
    /// Keys this build does not model, kept for the next save
    /// (docs/architecture/data-compatibility.md).
    public var unknown: UnknownFields = .empty

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case lastRoot
        case rootIdentifier
        case rootBookmark
        case lastOpened
        case fileSyncWarningDismissed
    }

    public init(
        lastRoot: String? = nil,
        lastOpened: Date? = nil,
        fileSyncWarningDismissed: Bool = false,
    ) {
        self.lastRoot = lastRoot
        self.lastOpened = lastOpened
        self.fileSyncWarningDismissed = fileSyncWarningDismissed
    }

    /// Lenient per field: an unreadable value reads as absent (and is kept raw).
    public init(from decoder: any Decoder) throws {
        var object = try LenientObject<CodingKeys>(decoder)
        lastRoot = object.value(.lastRoot)
        rootIdentifier = object.value(.rootIdentifier)
        rootBookmark = object.value(.rootBookmark)
        lastOpened = object.value(.lastOpened)
        fileSyncWarningDismissed = object.value(.fileSyncWarningDismissed, default: false)
        unknown = object.unknown
    }

    public func encode(to encoder: any Encoder) throws {
        try unknown.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(lastRoot, forKey: .lastRoot)
        try container.encodeIfPresent(rootIdentifier, forKey: .rootIdentifier)
        try container.encodeIfPresent(rootBookmark, forKey: .rootBookmark)
        try container.encodeIfPresent(lastOpened, forKey: .lastOpened)
        try container.encode(fileSyncWarningDismissed, forKey: .fileSyncWarningDismissed)
    }

    /// The record in `directory`; an unreadable or missing file reads as empty.
    public static func read(_ directory: LibraryStateDirectory, fileSystem: any FileSystem)
        -> Self?
    {
        guard let data = try? fileSystem.readData(at: directory.stateFile) else { return nil }
        return try? SegueJSON.decode(Self.self, from: data)
    }

    /// Writes the record into `directory` (creating it).
    public func write(to directory: LibraryStateDirectory, fileSystem: any FileSystem) throws {
        try fileSystem.createDirectory(at: directory.url)
        try fileSystem.writeAtomically(SegueJSON.encode(self), to: directory.stateFile)
    }
}
