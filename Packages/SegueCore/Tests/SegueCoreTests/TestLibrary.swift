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
    let fileSystem = LiveFileSystem()

    init(seed: UInt64 = 1) throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "SegueCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        root = LibraryRoot(url: url)
        clock = ManualClock()
        ids = ULIDGenerator(clock: clock, seed: seed)
    }

    deinit {
        try? FileManager.default.removeItem(at: root.url)
    }

    /// A new `LibraryStore` opened on this folder (a "relaunch" when called again).
    func openStore() async throws -> LibraryStore {
        let store = LibraryStore(fileSystem: fileSystem, clock: clock, ids: ids)
        try await store.open(root: root)
        return store
    }

    /// A new `SetlistStore` loaded from this folder.
    func loadSetlists() async throws -> (SetlistStore, [SetlistLoadIssue]) {
        let store = SetlistStore(fileSystem: fileSystem, clock: clock, ids: ids)
        let issues = try await store.load(root: root)
        return (store, issues)
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
        """
        {
          "createdAt" : "\(created)",
          "displayPrefs" : {

          },
          "id" : "\(id)",
          "schemaVersion" : 1,
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
