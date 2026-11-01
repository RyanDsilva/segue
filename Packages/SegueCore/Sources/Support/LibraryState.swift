import Foundation

/// Opening a library's out-of-folder state (P9-6 5.2): its identity, its state directory,
/// copy-versus-move detection, the lock, and the TTL backstop for state nobody opens.
public enum LibraryState {
    /// A library's identity and state directory, resolved for one open.
    public struct Resolved: Sendable, Equatable {
        public let identity: LibraryIdentity
        public let directory: LibraryStateDirectory
        /// `state.json` as it was before this open (empty for a new ID).
        public let record: LibraryStateRecord
        /// The folder was a Finder copy of another library and has just been given its own
        /// identity: show the one-time note (`copyNote`). A re-keyed copy is never joined to
        /// an iCloud zone.
        public let isCopy: Bool
    }

    /// The one-time note after a copy was re-keyed.
    public static let copyNote = "This folder is a copy of another Segue library, so it now "
        + "has its own identity."

    /// State directories not opened for this long are moved to the Trash at launch.
    public static let staleInterval: TimeInterval = 180 * 24 * 60 * 60

    /// Resolves `root`'s identity (minting it on first open) and its state directory.
    ///
    /// Copy versus move (R185): `state.json` holds the folder's file identifier and a
    /// security-scoped bookmark from its last open. When this folder's identifier differs
    /// and the bookmark still resolves to another existing folder holding the same library
    /// ID, `root` is a Finder copy, so it gets a new ID (the old `library.json` goes to the
    /// Trash). A changed identifier with the original gone is a move (across volumes too);
    /// an unchanged one is the same folder, moved or renamed on its volume.
    public static func resolve(
        root: LibraryRoot,
        location: LibraryStateLocation,
        fileSystem: any FileSystem,
        clock: any Clock,
        ids: any IDGenerator,
    ) throws -> Resolved {
        let identity = try LibraryIdentity.resolve(
            root: root,
            fileSystem: fileSystem,
            clock: clock,
            ids: ids,
        )
        let directory = location.directory(for: identity.id)
        let record = LibraryStateRecord.read(directory, fileSystem: fileSystem)
            ?? LibraryStateRecord()
        guard isCopy(root, of: identity.id, record: record, fileSystem: fileSystem) else {
            return Resolved(identity: identity, directory: directory, record: record, isCopy: false)
        }
        let fresh = try LibraryIdentity.rekey(
            root: root,
            fileSystem: fileSystem,
            clock: clock,
            ids: ids,
        )
        let freshDirectory = location.directory(for: fresh.id)
        return Resolved(
            identity: fresh,
            directory: freshDirectory,
            record: LibraryStateRecord.read(freshDirectory, fileSystem: fileSystem)
                ?? LibraryStateRecord(),
            isCopy: true,
        )
    }

    /// Resolves `root` and takes its lock with `lock`, then records the open in
    /// `state.json`. Two copies of Segue opening a folder without `library.json` at the
    /// same moment could each mint an ID and lock different files; so after locking, the ID
    /// on disk is read again, and a mismatch (the other copy's write won) drops the lock
    /// and starts over on the winning ID, whose lock the other copy holds.
    public static func open<Lock>(
        // swiftlint:disable:previous function_parameter_count
        root: LibraryRoot,
        location: LibraryStateLocation,
        fileSystem: any FileSystem,
        clock: any Clock,
        ids: any IDGenerator,
        lock: (LibraryStateDirectory) throws -> Lock,
    ) throws -> (Resolved, Lock) {
        var attempt = 0
        while true {
            attempt += 1
            let resolved = try resolve(
                root: root,
                location: location,
                fileSystem: fileSystem,
                clock: clock,
                ids: ids,
            )
            let held = try lock(resolved.directory)
            let onDisk = LibraryIdentity.read(root: root, fileSystem: fileSystem)
            guard onDisk != .valid(resolved.identity), attempt < 3 else {
                try recordOpen(resolved, root: root, fileSystem: fileSystem, clock: clock)
                return (resolved, held)
            }
        }
    }

    /// Writes `lastRoot` and `lastOpened` into the library's `state.json`, keeping the
    /// rest of the record.
    public static func recordOpen(
        _ resolved: Resolved,
        root: LibraryRoot,
        fileSystem: any FileSystem,
        clock: any Clock,
    ) throws {
        var record = resolved.record
        record.lastRoot = path(of: root)
        record.rootIdentifier = LibraryFolderReference.identifier(of: root.url)
        record.rootBookmark = LibraryFolderReference.bookmark(of: root.url)
        record.lastOpened = SegueJSON.stamp(clock.now())
        try record.write(to: resolved.directory, fileSystem: fileSystem)
    }

    /// The TTL backstop: moves to the Trash every state directory under `location` not
    /// opened for `staleInterval` (by `state.json`, else the folder's modification date)
    /// whose library lock is free. A directory whose library is open anywhere on this Mac
    /// is never touched. Returns the IDs moved. Failures are skipped: the next launch
    /// tries again.
    @discardableResult
    public static func pruneStale(
        location: LibraryStateLocation,
        fileSystem: any FileSystem,
        clock: any Clock,
    ) -> [ULID] {
        guard let entries = try? fileSystem.contentsOfDirectory(at: location.librariesDirectory)
        else { return [] }
        let now = clock.now()
        var pruned: [ULID] = []
        for entry in entries {
            guard let id = ULID(string: entry.lastPathComponent),
                  id.description == entry.lastPathComponent
            else { continue }
            let directory = location.directory(for: id)
            let lastOpened = LibraryStateRecord.read(directory, fileSystem: fileSystem)?.lastOpened
                ?? (try? fileSystem.attributes(at: directory.url))?.modificationDate
            guard let lastOpened, now.timeIntervalSince(lastOpened) >= staleInterval,
                  let lock = try? LibraryLock(state: directory) else { continue }
            if (try? fileSystem.trashItem(at: directory.url)) != nil {
                pruned.append(id)
            }
            withExtendedLifetime(lock) {}
        }
        return pruned
    }

    private static func path(of root: LibraryRoot) -> String {
        root.url.standardizedFileURL.path(percentEncoded: false)
    }

    /// Whether `root` is a copy of the folder `record` last saw (see `resolve`).
    private static func isCopy(
        _ root: LibraryRoot,
        of id: ULID,
        record: LibraryStateRecord,
        fileSystem: any FileSystem,
    ) -> Bool {
        guard let stored = record.rootIdentifier,
              let current = LibraryFolderReference.identifier(of: root.url),
              stored != current,
              let bookmark = record.rootBookmark
        else { return false }
        return LibraryFolderReference.withResolved(bookmark) { original in
            original.resolvingSymlinksInPath().path(percentEncoded: false)
                != root.url.resolvingSymlinksInPath().path(percentEncoded: false)
                && isLibrary(LibraryRoot(url: original), id, fileSystem)
        } ?? false
    }

    private static func isLibrary(_ root: LibraryRoot, _ id: ULID, _ fileSystem: any FileSystem)
        -> Bool
    {
        guard fileSystem.directoryExists(at: root.url),
              case let .valid(identity) = LibraryIdentity.read(root: root, fileSystem: fileSystem)
        else { return false }
        return identity.id == id
    }
}
