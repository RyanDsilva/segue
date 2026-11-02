import Foundation
import Library
import Setlists
import Support

/// A fresh library folder in a temp directory, with a frozen clock and seeded IDs, wired to
/// the real stores (real files, real GRDB index, real parser). Deleted on deinit.
final class TestLibrary: Sendable {
    let root: LibraryRoot
    let clock: ManualClock
    let ids: ULIDGenerator
    /// Real IO; trashed items go to `trash`, never the user's Trash (B-15).
    let fileSystem: LiveFileSystem
    /// The stand-in Trash folder, next to the library folder.
    let trash: URL
    /// The library state location (index, locks, `state.json`), next to the library folder
    /// as the app group's Application Support would be (P9-6 5.2).
    let stateLocation: LibraryStateLocation
    /// This library's state directory, under a fixed test library ID.
    var state: LibraryStateDirectory {
        stateLocation.directory(for: Self.libraryID)
    }

    /// The library ID the stores' state directory is keyed by in these tests.
    static let libraryID = ULID(
        milliseconds: 1_767_225_600_000,
        randomness: Array(repeating: 7, count: 10),
    )

    init(seed: UInt64 = 1) throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "SegueCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        root = LibraryRoot(url: url)
        trash = url.deletingLastPathComponent()
            .appending(path: url.lastPathComponent + "-trash", directoryHint: .isDirectory)
        fileSystem = LiveFileSystem(trash: .directory(trash))
        stateLocation = LibraryStateLocation(base: url.deletingLastPathComponent().appending(
            path: url.lastPathComponent + "-state",
            directoryHint: .isDirectory,
        ))
        clock = ManualClock()
        ids = ULIDGenerator(clock: clock, seed: seed)
    }

    deinit {
        try? FileManager.default.removeItem(at: root.url)
        try? FileManager.default.removeItem(at: trash)
        try? FileManager.default.removeItem(at: stateLocation.base)
    }

    /// File names in the stand-in Trash, sorted.
    func trashedNames() -> [String] {
        let names = try? FileManager.default
            .contentsOfDirectory(atPath: trash.path(percentEncoded: false))
        return (names ?? []).sorted()
    }

    /// A new `LibraryStore` opened on this folder (a "relaunch" when called again).
    func openStore() async throws -> LibraryStore {
        let store = LibraryStore(fileSystem: fileSystem, clock: clock, ids: ids)
        try await store.open(root: root, state: state)
        return store
    }

    /// A new `SetlistStore` loaded from this folder.
    func loadSetlists() async throws -> (SetlistStore, [SetlistLoadIssue]) {
        let store = SetlistStore(fileSystem: fileSystem, clock: clock, ids: ids)
        let issues = try await store.load(root: root)
        return (store, issues)
    }

    /// The index database in the state directory, or one of its side files (`-wal`).
    func indexFile(_ suffix: String = "") -> URL {
        URL(filePath: state.indexDatabase.path(percentEncoded: false) + suffix)
    }

    func url(_ relativePath: String) -> URL {
        root.url.appending(path: relativePath)
    }

    func write(_ text: String, to relativePath: String) throws {
        let target = url(relativePath)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data(text.utf8).write(to: target)
    }

    func read(_ relativePath: String) throws -> String {
        try String(contentsOf: url(relativePath), encoding: .utf8)
    }

    func exists(_ relativePath: String) -> Bool {
        fileSystem.fileExists(at: url(relativePath))
    }

    /// Bytes of a canonical sidecar written by this build at `date`.
    static func expectedSidecar(id: SongID, created: String, updated: String) -> String {
        // swiftlint:disable:previous function_body_length
        """
        {
          "bass" : {
            "timing" : {
              "chords" : [

              ]
            },
            "walkUps" : [

            ]
          },
          "createdAt" : "\(created)",
          "cues" : [

          ],
          "displayPrefs" : {
            "capoMode" : "shapes",
            "instrument" : "guitar",
            "nashville" : false,
            "showDiagrams" : false,
            "transpose" : 0,
            "tuning" : {
              "name" : "Standard",
              "strings" : [
                40,
                45,
                50,
                55,
                59,
                64
              ]
            }
          },
          "id" : "\(id)",
          "live" : {
            "autoStartScroll" : false,
            "scrollSpeedFactor" : 1,
            "zoom" : 1
          },
          "minReaderVersion" : \(Sidecar.currentMinReaderVersion),
          "parts" : [

          ],
          "schemaVersion" : \(Sidecar.currentSchemaVersion),
          "tags" : [

          ],
          "updatedAt" : "\(updated)"
        }

        """
    }
}

extension [SongRecord] {
    /// Titles in order, for readable expectations.
    var titles: [String] {
        map { $0.document.metadata.title ?? "<untitled>" }
    }
}
