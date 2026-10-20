import Foundation
import Library
import Setlists
import Support
import Testing

/// Integration suite for `LibraryArchive` (WS2b 4.8): a real library in a temp folder is
/// archived through the system zipper, then unzipped with `ditto` and compared byte for byte.
struct LibraryArchiveTests {
    private static let song = """
    {title: Archive Test Song}
    {artist: Test Band}
    {key: G}

    [G]One line to keep

    """

    /// 2026-03-07 13:00 UTC.
    private static let exportDate = Date(timeIntervalSince1970: 1_772_888_400)

    @Test
    func `archive holds exactly the library folders under one dated folder`() async throws {
        let lib = try TestLibrary()
        try await Self.populate(lib)
        let work = try WorkFolder()
        lib.clock.set(Self.exportDate)
        let archive = Self.archive(lib, work)
        #expect(archive.folderName == "Segue Library 2026-03-07")
        #expect(archive.defaultFileName == "Segue Library 2026-03-07.zip")

        let destination = work.url.appending(path: "out/Segue Library 2026-03-07.zip")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try archive.export(root: lib.root, to: destination)

        let zip = try Data(contentsOf: destination)
        #expect(zip.starts(with: Data("PK".utf8)))
        let unzipped = work.url.appending(path: "unzipped", directoryHint: .isDirectory)
        try Self.unzip(destination, into: unzipped)

        #expect(try Self.tree(unzipped).keys
            .allSatisfy { $0.hasPrefix("Segue Library 2026-03-07/") })
        let archived = try Self.tree(unzipped.appending(path: "Segue Library 2026-03-07"))
        var expected: [String: Data] = [:]
        for folder in LibraryArchive.includedFolders {
            for (path, data) in try Self.tree(lib.url(folder)) where !Self.isHidden(path) {
                expected["\(folder)/\(path)"] = data
            }
        }
        #expect(Set(archived.keys) == Set(expected.keys))
        #expect(archived == expected)
        // Spot checks on what the comparison above implies.
        #expect(archived["songs/archive-test-song.cho"] == Data(Self.song.utf8))
        #expect(archived.keys.contains("songs/archive-test-song.segue.json"))
        #expect(archived.keys.contains { $0.hasPrefix("setlists/") })
        #expect(archived.keys.contains("shows/01JTEST.show.json"))
        #expect(archived.keys.contains("timings/01JTEST.rehearsal.json"))
        #expect(archived.keys.contains("filters/ready-songs.filter.json"))
        #expect(!archived.keys.contains { $0.hasPrefix(".segue") || $0.contains(".DS_Store") })
        #expect(!archived.keys.contains("notes.txt"))
        #expect(!archived.keys.contains { $0.hasPrefix("My Stuff") })
        #expect(work.stagingIsEmpty)
    }

    @Test
    func `empty folders are absent and an existing destination is replaced`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        _ = try await store.createSong(source: Self.song)
        // `setlists/` exists but is empty; `shows/` and `timings/` were never created.
        let work = try WorkFolder()
        lib.clock.set(Self.exportDate)
        let destination = work.url.appending(path: "existing.zip")
        try Data("old contents".utf8).write(to: destination)

        try Self.archive(lib, work).export(root: lib.root, to: destination)

        let unzipped = work.url.appending(path: "unzipped", directoryHint: .isDirectory)
        try Self.unzip(destination, into: unzipped)
        let top = unzipped.appending(path: "Segue Library 2026-03-07")
        #expect(try Set(Self.tree(top).keys) == [
            "songs/archive-test-song.cho", "songs/archive-test-song.segue.json",
        ])
        #expect(!FileManager.default.fileExists(atPath: top.appending(path: "setlists").path))
        #expect(work.stagingIsEmpty)
    }

    @Test
    func `unwritable destination leaves no file and removes staging`() async throws {
        let lib = try TestLibrary()
        try await Self.populate(lib)
        let work = try WorkFolder()
        let locked = work.url.appending(path: "locked", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: locked.path,
            )
        }
        let destination = locked.appending(path: "out.zip")

        #expect(throws: (any Error).self) {
            try Self.archive(lib, work).export(root: lib.root, to: destination)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: locked.path).isEmpty)
        #expect(work.stagingIsEmpty)
    }

    @Test
    func `unreadable file mid-copy fails with no destination file and no staging`() async throws {
        let lib = try TestLibrary()
        try await Self.populate(lib)
        let work = try WorkFolder()
        let fileSystem = InstrumentedFileSystem()
        fileSystem.fail(.read, suffix: ".show.json")
        let archive = LibraryArchive(
            fileSystem: fileSystem,
            clock: lib.clock,
            timeZone: .gmt,
            temporaryDirectory: work.staging,
        )
        let destination = work.url.appending(path: "out.zip")

        #expect(throws: InstrumentedFileSystem.InjectedFailure.self) {
            try archive.export(root: lib.root, to: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(work.stagingIsEmpty)
    }

    @Test
    func `missing library folder is a typed error`() throws {
        let work = try WorkFolder()
        let root = LibraryRoot(url: work.url.appending(
            path: "nowhere",
            directoryHint: .isDirectory,
        ))
        let archive = LibraryArchive(
            fileSystem: LiveFileSystem(),
            clock: ManualClock(),
            temporaryDirectory: work.staging,
        )
        #expect(throws: LibraryArchiveError.libraryMissing(root.url)) {
            try archive.export(root: root, to: work.url.appending(path: "out.zip"))
        }
        #expect(work.stagingIsEmpty)
    }

    @Test
    func `folder name uses the local date of the injected time zone`() throws {
        let clock =
            ManualClock(start: Date(timeIntervalSince1970: 1_772_928_000)) // 2026-03-08 00:00Z
        let honolulu = try LibraryArchive(
            fileSystem: LiveFileSystem(),
            clock: clock,
            timeZone: #require(TimeZone(identifier: "Pacific/Honolulu")),
        )
        let tokyo = try LibraryArchive(
            fileSystem: LiveFileSystem(),
            clock: clock,
            timeZone: #require(TimeZone(identifier: "Asia/Tokyo")),
        )
        #expect(honolulu.folderName == "Segue Library 2026-03-07")
        #expect(tokyo.defaultFileName == "Segue Library 2026-03-08.zip")
    }

    // MARK: - Support

    /// A library with a song, a setlist, a show, a timing file, a nested folder, plus things
    /// the archive must leave out (`.segue/`, `.DS_Store`, stray root files and folders).
    private static func populate(_ lib: TestLibrary) async throws {
        let store = try await lib.openStore()
        let song = try await store.createSong(source: song)
        let (setlists, _) = try await lib.loadSetlists()
        let setlist = try await setlists.create(name: "Friday")
        try await setlists.addSong(song.id, to: setlist.id)
        try lib.write(#"{"schemaVersion":1}"#, to: "shows/01JTEST.show.json")
        try lib.write(#"{"schemaVersion":1}"#, to: "timings/01JTEST.rehearsal.json")
        let filters = SmartFilterStore(fileSystem: lib.fileSystem, clock: lib.clock, ids: lib.ids)
        try await filters.load(root: lib.root)
        var ready = SmartFilterConditions()
        ready.proficiencies = [.ready]
        try await filters.create(name: "Ready songs", conditions: ready)
        try lib.write("nested", to: "songs/Old Versions/draft.cho")
        try lib.writeBytes([0, 1, 2, 255], to: "songs/.DS_Store")
        try lib.write("private", to: "notes.txt")
        try lib.write("mine", to: "My Stuff/readme.txt")
        #expect(lib.exists(".segue/index.sqlite"))
    }

    private static func archive(_ lib: TestLibrary, _ work: WorkFolder) -> LibraryArchive {
        LibraryArchive(
            fileSystem: LiveFileSystem(),
            clock: lib.clock,
            timeZone: .gmt,
            temporaryDirectory: work.staging,
        )
    }

    private static func isHidden(_ relativePath: String) -> Bool {
        relativePath.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    /// Every regular file under `folder` (hidden ones included), by relative path.
    private static func tree(_ folder: URL) throws -> [String: Data] {
        let base = folder.standardizedFileURL.path(percentEncoded: false)
        let prefix = base.hasSuffix("/") ? base : base + "/"
        var result: [String: Data] = [:]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
        ) else {
            return result
        }
        for case let url as URL in enumerator {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                continue
            }
            let path = url.standardizedFileURL.path(percentEncoded: false)
            result[String(path.dropFirst(prefix.count))] = try Data(contentsOf: url)
        }
        return result
    }

    private static func unzip(_ zip: URL, into folder: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, folder.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}

/// A temp folder for one test's outputs, with its own staging directory. Deleted on deinit.
private final class WorkFolder: Sendable {
    let url: URL
    var staging: URL {
        url.appending(path: "staging", directoryHint: .isDirectory)
    }

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "SegueArchiveTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: url.appending(path: "staging"),
            withIntermediateDirectories: true,
        )
    }

    /// True when the archiver left nothing behind in its staging directory.
    var stagingIsEmpty: Bool {
        ((try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? []).isEmpty
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
