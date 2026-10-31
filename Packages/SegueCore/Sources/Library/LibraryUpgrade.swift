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

    public init(durationCleanupOffered: Bool = false) {
        self.durationCleanupOffered = durationCleanupOffered
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        durationCleanupOffered = try container
            .decodeIfPresent(Bool.self, forKey: .durationCleanupOffered) ?? false
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
