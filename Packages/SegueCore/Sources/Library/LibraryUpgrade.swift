// P8-8c (docs/phases/8-workstreams/P8-8-artists-movie-and-slot-time.md sections 5.7, 5.8,
// R173). The two one-time steps of the first open with this build, both safe for a real
// library: the old `timings/` folder goes to the Trash (recoverable, never deleted), and the
// `{duration}` cleanup is offered once (charts change only when the user accepts).

import Foundation
import Support

/// What this build has already done or offered in one library, in `.segue/upgrades.json`.
public struct LibraryUpgradeState: Sendable, Equatable, Codable {
    /// The "remove the old length lines" offer was made (answered either way).
    public var durationCleanupOffered: Bool
    /// The index and locks of builds before P9-6 S0 are gone from the folder (5.3).
    public var stateMoved: Bool

    public init(durationCleanupOffered: Bool = false, stateMoved: Bool = false) {
        self.durationCleanupOffered = durationCleanupOffered
        self.stateMoved = stateMoved
    }

    /// Marks a newer Segue recorded (keys this build does not model), kept for the next save
    /// so an older build never forgets them (docs/architecture/data-compatibility.md).
    public var unknown: UnknownFields = .empty

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case durationCleanupOffered
        case stateMoved
    }

    public init(from decoder: any Decoder) throws {
        var object = try LenientObject<CodingKeys>(decoder)
        durationCleanupOffered = object.value(.durationCleanupOffered, default: false)
        stateMoved = object.value(.stateMoved, default: false)
        unknown = object.unknown
    }

    public func encode(to encoder: any Encoder) throws {
        try unknown.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(durationCleanupOffered, forKey: .durationCleanupOffered)
        try container.encode(stateMoved, forKey: .stateMoved)
    }
}

public enum LibraryUpgrade {
    /// The one-time note shown after `timings/` moved to the Trash.
    public static let timingsNote = "Rehearsal timings are no longer used. The old timings "
        + "folder was moved to the Trash."

    /// `<root>/timings`: where builds before P8-8 kept rehearsal timing samples. Never
    /// created, written or read by this build.
    public static func timingsFolder(_ root: LibraryRoot) -> URL {
        root.url.appending(path: "timings", directoryHint: .isDirectory)
    }

    static func stateURL(_ root: LibraryRoot) -> URL {
        root.appDirectory.appending(path: "upgrades.json", directoryHint: .notDirectory)
    }

    /// Moves an existing `timings/` folder to the Trash with `trash` (the whole folder,
    /// recoverable). True when it moved (show `timingsNote` once). A failed move leaves the
    /// folder exactly as it is and says nothing; the next open tries again.
    public static func moveTimingsToTrash(
        root: LibraryRoot,
        fileSystem: any FileSystem,
        trash: (URL) throws -> Void,
    ) -> Bool {
        let folder = timingsFolder(root)
        guard fileSystem.directoryExists(at: folder) else { return false }
        do {
            try trash(folder)
        } catch {
            return false
        }
        return !fileSystem.directoryExists(at: folder)
    }

    /// The library's upgrade state; an unreadable or missing file reads as nothing done.
    public static func state(root: LibraryRoot, fileSystem: any FileSystem)
        -> LibraryUpgradeState
    {
        guard let data = try? fileSystem.readData(at: stateURL(root)),
              let state = try? JSONDecoder().decode(LibraryUpgradeState.self, from: data)
        else { return LibraryUpgradeState() }
        return state
    }

    /// Records `state` in `.segue/upgrades.json`.
    public static func save(
        _ state: LibraryUpgradeState,
        root: LibraryRoot,
        fileSystem: any FileSystem,
    ) throws {
        try fileSystem.createDirectory(at: root.appDirectory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try fileSystem.writeAtomically(encoder.encode(state), to: stateURL(root))
    }

    /// `<root>/.segue/index.sqlite`: where builds before P9-6 S0 kept the index.
    static func inFolderIndex(_ root: LibraryRoot) -> URL {
        root.appDirectory.appending(path: "index.sqlite", directoryHint: .notDirectory)
    }

    /// `<root>/.segue/library.lock`: where builds before P9-6 S0 kept the library lock.
    static func inFolderLock(_ root: LibraryRoot) -> URL {
        root.appDirectory.appending(path: "library.lock", directoryHint: .notDirectory)
    }

    /// The upgrade from in-folder state (5.3), until `stateMoved` is recorded. Best effort:
    /// a failure leaves the old files for the next open and never fails this one.
    static func moveStateOutOfFolder(root: LibraryRoot, fileSystem: any FileSystem) {
        var upgrades = state(root: root, fileSystem: fileSystem)
        guard !upgrades.stateMoved,
              (try? removeInFolderState(root: root, fileSystem: fileSystem)) == true
        else { return }
        upgrades.stateMoved = true
        try? save(upgrades, root: root, fileSystem: fileSystem)
    }

    /// Removes the state builds before P9-6 S0 kept inside the folder (5.3), once the new
    /// index exists in the state directory: the old index and its `-wal` / `-shm` (a
    /// projection, not user data), then `.segue/library.lock` and every
    /// `shows/*.show.lock` that no older build holds. A held lock stays and is tried again
    /// on the next open. True when nothing is left, so `stateMoved` can be recorded.
    static func removeInFolderState(root: LibraryRoot, fileSystem: any FileSystem) throws
        -> Bool
    {
        try SongIndex.deleteFiles(at: inFolderIndex(root), fileSystem: fileSystem)
        var locks = [inFolderLock(root)]
        if fileSystem.directoryExists(at: root.showsDirectory) {
            locks += try fileSystem.contentsOfDirectory(at: root.showsDirectory)
                .filter { $0.lastPathComponent.hasSuffix(".show.lock") }
        }
        var removedAll = true
        for lock in locks where fileSystem.fileExists(at: lock) {
            removedAll = unlinkIfFree(lock) && removedAll
        }
        return removedAll
    }

    /// Unlinks the lock file at `url` while holding its `flock`, so a file an older build
    /// still holds is never removed. True when it is gone.
    private static func unlinkIfFree(_ url: URL) -> Bool {
        let path = url.path(percentEncoded: false)
        let fd = open(path, O_RDWR | O_CLOEXEC)
        guard fd >= 0 else { return errno == ENOENT }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return false }
        return unlink(path) == 0 || errno == ENOENT
    }

    /// The songs the `{duration}` cleanup would change: editable songs whose source holds a
    /// `{duration}` line (read-only songs are skipped).
    public static func songsWithDurationLines(_ records: [SongRecord]) -> [SongID] {
        records.filter { record in
            !record.isReadOnly && SourceLines.hasDirective("duration", in: record.source)
        }.map(\.id)
    }
}

/// A cheap line scan for a directive name (`{duration: 4:05}`, `{ duration }`), without a
/// full parse.
enum SourceLines {
    static func hasDirective(_ name: String, in source: String) -> Bool {
        guard source.range(of: name, options: .caseInsensitive) != nil else { return false }
        for line in source.split(whereSeparator: \.isNewline) {
            var text = line.drop { $0 == " " || $0 == "\t" }
            guard text.first == "{" else { continue }
            text = text.dropFirst().drop { $0 == " " || $0 == "\t" }
            let word = text.prefix { $0.isLetter || $0 == "_" }
            if word.lowercased() == name {
                return true
            }
        }
        return false
    }
}
