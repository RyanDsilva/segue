import Foundation
import Library
import Support
import Testing

/// In-app import (WS2a 3.2) on a real library folder, fed from `Tests/Fixtures/import/`.
/// Every case checks the files on disk, the sidecar, the index (search) and the summary.
struct SongImportTests {
    private static let fixtures: URL = {
        guard let url = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            fatalError("Fixtures missing from the test bundle")
        }
        return url.appending(path: "import", directoryHint: .isDirectory)
    }()

    private static func fixture(_ name: String) -> URL {
        fixtures.appending(path: name)
    }

    @Test
    func `every accepted extension imports, crd included (R76)`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let names = [
            "harbour-lights.cho", "river-song.chopro", "night-drive.chordpro", "old-hymn.pro",
        ]

        let summary = try await store.importSongs(names.map(Self.fixture))

        #expect(summary.imported.map(\.relativePath) == [
            "songs/harbour-lights.cho", "songs/river-song.cho", "songs/night-drive.cho",
            "songs/old-hymn.cho",
        ])
        #expect(summary.skipped.isEmpty)
        // A `.crd` is read like a `.txt`; the app sends it through the review sheet (P3-4).
        let (crd, crdSkips) = try await store.prepareImport([Self.fixture("legacy.crd")])
        #expect(crd.map(\.fileName) == ["legacy.crd"])
        #expect(crdSkips.isEmpty)
        #expect(try lib.bytes("songs/river-song.cho") == Data(contentsOf: Self.fixture(
            "river-song.chopro",
        )))
        #expect(try await store.search(query: "headlights").map(\.relativePath)
            == ["songs/night-drive.cho"])
        // Fresh sidecars with new IDs.
        let sidecar = try lib.read("songs/old-hymn.segue.json")
        #expect(sidecar.contains("\"id\" : \"\(summary.imported[3].id)\""))
        #expect(Set(summary.imported.map(\.id)).count == 4)
    }

    @Test
    func `text without a title keeps its bytes and takes its slug from the file name`(
    ) async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()

        let summary = try await store.importSongs([
            Self.fixture("chords-over-lyrics.txt"), Self.fixture("untitled-tune.cho"),
        ])

        #expect(summary.imported.map(\.relativePath)
            == ["songs/chords-over-lyrics.cho", "songs/untitled-tune.cho"])
        #expect(try lib.bytes("songs/chords-over-lyrics.cho")
            == Data(contentsOf: Self.fixture("chords-over-lyrics.txt")))
        // No {title} is injected.
        #expect(try !lib.read("songs/untitled-tune.cho").contains("{title"))
        #expect(try await store.search(query: "carry").count == 1)
    }

    @Test
    func `title collisions get suffixes within the library and the batch`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        _ = try await store.createSong(source: "{title: Harbour Lights}\nMine\n")

        let summary = try await store.importSongs([
            Self.fixture("harbour-lights.cho"),
            Self.fixture("same-title-a.cho"), Self.fixture("same-title-b.cho"),
        ])

        #expect(summary.imported.map(\.relativePath) == [
            "songs/harbour-lights-2.cho", "songs/same-name.cho", "songs/same-name-2.cho",
        ])
        #expect(try lib.read("songs/same-name-2.cho") == "{title: Same Name}\nSecond version\n")
    }

    @Test
    func `byte-identical duplicates and the library's own files are skipped`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let first = try await store.importSongs([Self.fixture("harbour-lights.cho")])
        #expect(first.imported.count == 1)

        let again = try await store.importSongs([
            Self.fixture("harbour-lights.cho"),
            lib.url("songs/harbour-lights.cho"),
            Self.fixture("river-song.chopro"), Self.fixture("river-song.chopro"),
        ])

        #expect(again.imported.map(\.relativePath) == ["songs/river-song.cho"])
        #expect(again.skipped == [
            ImportSkip(
                fileName: "harbour-lights.cho",
                reason: "Already in your library as “Harbour Lights”",
            ),
            ImportSkip(
                fileName: "harbour-lights.cho",
                reason: "Already in your library as “Harbour Lights”",
            ),
            ImportSkip(
                fileName: "river-song.chopro",
                reason: "Already in your library as “River Song”",
            ),
        ])
        #expect(try await store.allSongs().count == 2)
    }

    @Test
    func `line endings are kept, a UTF-8 BOM is dropped, Windows Latin 1 is converted`(
    ) async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()

        let summary = try await store.importSongs([
            Self.fixture("crlf-no-final-newline.cho"), Self.fixture("bom.cho"),
            Self.fixture("cp1252.cho"),
        ])

        #expect(summary.imported.map(\.relativePath)
            == ["songs/carriage-return.cho", "songs/byte-order.cho", "songs/cafe-song.cho"])
        #expect(try lib.bytes("songs/carriage-return.cho")
            == Data(contentsOf: Self.fixture("crlf-no-final-newline.cho")))
        #expect(try lib
            .bytes("songs/byte-order.cho") == Data("{title: Byte Order}\n[G]Marked\n".utf8))
        #expect(try lib.read("songs/cafe-song.cho") == "{title: Café Song}\n[G]It’s a café tune\n")
        #expect(summary.converted == ["cp1252.cho: converted from Windows Latin 1"])
        #expect(try await store.song(id: summary.imported[2].id)?.isReadOnly == false)
        // The source file is never modified.
        #expect(try Data(contentsOf: Self.fixture("cp1252.cho")).contains(0xE9))
    }

    @Test
    func `files too large or not text are skipped with reasons`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        try lib.write(String(repeating: "la la la\n", count: 220_000), to: "src/huge.cho")

        let summary = try await store.importSongs([
            lib.url("src/huge.cho"), Self.fixture("picture.cho"), lib.url("src/missing.cho"),
        ])

        #expect(summary.imported.isEmpty)
        #expect(summary.skipped.map(\.reason).prefix(2)
            == ["Too large to be a song", "Not a text file"])
        #expect(summary.skipped[2].fileName == "missing.cho")
        #expect(summary.skipped[2].reason.hasPrefix("Could not be read: "))
        #expect(try await store.allSongs().isEmpty)
    }

    @Test
    func `folders import recursively without hidden files`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let folder = lib.url("src/folder")
        try FileManager.default.createDirectory(
            at: lib.url("src"),
            withIntermediateDirectories: true,
        )
        try FileManager.default.copyItem(at: Self.fixture("folder"), to: folder)
        try lib.write("{title: Hidden}\nNo\n", to: "src/folder/.hidden.cho")

        let summary = try await store.importSongs([folder])

        #expect(summary.imported.map(\.relativePath).sorted()
            == ["songs/deep-down.cho", "songs/top-level.cho"])
        #expect(summary.skipped.isEmpty)
    }

    @Test
    func `a neighbour sidecar lends its metadata but never its ID`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()

        let summary = try await store.importSongs([Self.fixture("with-sidecar.cho")])

        let song = try #require(summary.imported.first)
        #expect(song.id.description != "01J0000000000000000000000A")
        #expect(song.sidecar.tags == ["opener", "upbeat"])
        #expect(song.sidecar.proficiency == .ready)
        #expect(song.sidecar.notes == "Watch the bridge")
        #expect(song.sidecar.cues == [SongCue(section: "Chorus", text: "Big")])
        #expect(song.sidecar.createdAt == SegueJSON.stamp(lib.clock.now()))
        #expect(try await store.search(query: "opener").map(\.id) == [song.id])
        // Only the song is listed: the sidecar is not reported as skipped either.
        let other = try TestLibrary()
        let both = try await other.openStore().importSongs([
            Self.fixture("with-sidecar.cho"), Self.fixture("with-sidecar.segue.json"),
        ])
        #expect(both.skipped.isEmpty)
    }

    @Test
    func `a romanized Hindi title gets an ASCII slug and spelling-tolerant search`(
    ) async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()

        let summary = try await store.importSongs([Self.fixture("pyaar-ki-raah.cho")])

        #expect(summary.imported.map(\.relativePath) == ["songs/pyaar-ki-raah.cho"])
        #expect(try await store.search(query: "pyar").map(\.relativePath)
            == ["songs/pyaar-ki-raah.cho"])
    }

    @Test
    func `a write failure skips that file and keeps the rest`() async throws {
        let lib = try TestLibrary()
        let fileSystem = InstrumentedFileSystem()
        let store = try await lib.openStore(fileSystem: fileSystem)
        let (candidates, _) = try await store.prepareImport([
            Self.fixture("harbour-lights.cho"), Self.fixture("river-song.chopro"),
        ])
        fileSystem.fail(.write, suffix: "river-song.cho")

        let summary = try await store.commitImport(candidates)

        #expect(summary.imported.map(\.relativePath) == ["songs/harbour-lights.cho"])
        #expect(summary.skipped.map(\.fileName) == ["river-song.chopro"])
    }

    @Test
    func `the extension lists live in one place`() {
        #expect(SongFileTypes.importExtensions == [
            "cho", "chopro", "chordpro", "pro", "txt", "crd",
        ])
        #expect(SongFileTypes.claimedExtensions == ["cho", "chordpro", "chopro"])
        #expect(SongFileTypes.isImportable(URL(filePath: "/a/B.CHO")))
        #expect(SongFileTypes.isImportable(URL(filePath: "/a/b.CRD")))
        #expect(!SongFileTypes.isImportable(URL(filePath: "/a/b.pdf")))
    }
}
