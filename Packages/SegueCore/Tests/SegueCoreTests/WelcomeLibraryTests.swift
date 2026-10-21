import ChordPro
import Editing
import Foundation
import Library
import LiveLayout
import MusicTheory
import Setlists
import Support
import Testing

/// The bundled Welcome library (WS2b 4.2, Appendix A) through the real parser, the real
/// file store and the real index, plus the generic manifest seeder it shares with WS5.
struct WelcomeLibraryTests {
    /// `Packages/SegueUI/Sources/SegueUI/App/WelcomeLibrary`, the folder the app bundles.
    static let folder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // SegueCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // SegueCore
        .deletingLastPathComponent() // Packages
        .appending(path: "SegueUI/Sources/SegueUI/App/WelcomeLibrary", directoryHint: .isDirectory)

    static let files = [
        "soundcheck-at-seven.cho", "kitaabon-wali-gali.cho", "kettle-on-lights-low.cho",
        "ferry-lights-over-calder-bay.cho",
    ]

    static let titles = [
        "Soundcheck at Seven", "Kitaabon Wali Gali", "Kettle On, Lights Low",
        "Ferry Lights Over Calder Bay",
    ]

    // MARK: - Content

    @Test(arguments: files)
    func `song parses cleanly, round trips and carries its directives`(file: String) throws {
        let data = try Data(contentsOf: Self.folder.appending(path: file))
        #expect(data.allSatisfy { $0 < 0x80 }, "\(file) is not ASCII-only")
        let source = try #require(String(data: data, encoding: .utf8))
        #expect(!source.unicodeScalars.contains { (0x0900 ... 0x097F).contains($0.value) })
        #expect(source.hasSuffix("}\n"), "\(file) must end with a final newline")
        #expect(!source.contains("\r"))

        let (document, diagnostics) = ChordProParser.parse(source)
        #expect(diagnostics.isEmpty, "\(file): \(diagnostics)")
        #expect(Array(ChordProSerializer.serialize(document).utf8) == Array(data))

        let metadata = document.metadata
        #expect(metadata.title.map(Self.titles.contains) == true)
        #expect(metadata.artists == ["Segue Originals"])
        #expect(metadata.tempo != nil)
        #expect(metadata.duration != nil)
        let declared = try #require(metadata.key.flatMap(SongKey.init(parsing:)))

        let chordTexts = Self.chordTexts(document.blocks)
        #expect(!chordTexts.isEmpty)
        for text in chordTexts {
            #expect(ChordSymbol(parsing: text) != nil, "\(file): [\(text)] is not a strict chord")
        }
        let detection = try #require(KeyDetector.detect(chordTexts.compactMap {
            ChordToken(parsing: $0).chord
        }))
        #expect(detection.key == declared, "\(file): detected \(detection.key.name)")
    }

    @Test
    func `manifest lists the four songs and a setlist of exactly them`() throws {
        let manifest = try SeedManifest.load(fromFolder: Self.folder, fileSystem: LiveFileSystem())
        #expect(manifest.schema == 1)
        #expect(manifest.tag == "Welcome")
        #expect(manifest.songs.map(\.file) == Self.files)
        #expect(manifest.songs.allSatisfy { $0.tags.contains(manifest.tag) })
        let setlist = try #require(manifest.setlist)
        #expect(setlist.name == "Welcome Set")
        #expect(setlist.targetDuration == 1200)
        #expect(setlist.entries.map(\.song) == Self.files)
        let bundled = try FileManager.default.contentsOfDirectory(atPath: Self.folder.path)
        #expect(Set(bundled) == Set(Self.files + [SeedManifest.fileName]))
    }

    @Test
    func `the cue's section and occurrence exist in its song`() throws {
        let manifest = try SeedManifest.load(fromFolder: Self.folder, fileSystem: LiveFileSystem())
        for song in manifest.songs {
            let url = Self.folder.appending(path: song.file)
            let source = try String(contentsOf: url, encoding: .utf8)
            // The labels live mode pins cues to (the gutter's, as the notes editor offers).
            let labels = RenderModel(document: ChordProParser.parse(source).0, options: .init())
                .sections.compactMap(RepeatCollapser.displayLabel)
            for cue in song.cues {
                let count = labels.count { $0.caseInsensitiveCompare(cue.section) == .orderedSame }
                #expect(count >= (cue.occurrence ?? 1), "\(song.file): \(cue.section)")
            }
        }
    }

    // MARK: - Seeding

    @Test
    func `seeding an empty library creates the four songs with their metadata`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()

        let seeded = try await store.seedSongs(fromManifestFolder: Self.folder)

        #expect(seeded.map(\.file) == Self.files)
        #expect(seeded.count { $0.created } == seeded.count)
        #expect(try await store.allSongs().count == 4)
        let byFile = Dictionary(uniqueKeysWithValues: seeded.map { ($0.file, $0.record) })
        let soundcheck = try #require(byFile["soundcheck-at-seven.cho"])
        #expect(soundcheck.sidecar.tags == ["Welcome", "folk"])
        #expect(soundcheck.sidecar.proficiency == .pro)
        #expect(soundcheck.sidecar.notes?.hasPrefix("Count in 1-2-3-4.") == true)
        #expect(soundcheck.sidecar.cues.contents == ["Chorus|3|Big stop on the last line"])
        #expect(byFile["kitaabon-wali-gali.cho"]?.sidecar.proficiency == .ready)
        #expect(byFile["kettle-on-lights-low.cho"]?.sidecar.tags == ["Welcome", "waltz"])
        let ferry = try #require(byFile["ferry-lights-over-calder-bay.cho"])
        #expect(ferry.sidecar.proficiency == .learning)
        #expect(ferry.sidecar.live.columns == 2)
        #expect(soundcheck.sidecar.live.columns == nil)

        // On disk: the bundled bytes, and sidecars that carry the metadata after a relaunch.
        for file in Self.files {
            let bundled = try Data(contentsOf: Self.folder.appending(path: file))
            #expect(try lib.bytes("songs/\(file)") == bundled)
            #expect(lib.exists("songs/\(file.dropLast(4)).segue.json"))
        }
        let relaunched = try await lib.openStore()
        let reloaded = try #require(try await relaunched.song(id: ferry.id))
        #expect(reloaded.sidecar.live.columns == 2)
        #expect(try await relaunched.songs(taggedWith: "welcome").count == 4)
    }

    @Test
    func `seeding twice creates nothing new`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let first = try await store.seedSongs(fromManifestFolder: Self.folder)
        let sidecars = try Self.sidecars(lib)

        let relaunched = try await lib.openStore()
        let second = try await relaunched.seedSongs(fromManifestFolder: Self.folder)

        #expect(second.allSatisfy { !$0.created })
        #expect(second.map(\.record.id) == first.map(\.record.id))
        #expect(try await relaunched.allSongs().count == 4)
        #expect(try Self.sidecars(lib) == sidecars)
    }

    @Test
    func `edited Welcome song is not reused and shows up as edited`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let seeded = try await store.seedSongs(fromManifestFolder: Self.folder)
        let kettle = try #require(seeded.first { $0.file == "kettle-on-lights-low.cho" })
        let edited = kettle.record.source
            .replacingOccurrences(of: "Kettle on,", with: "Kettle off,")
        _ = try await store.updateSong(id: kettle.record.id, source: edited)

        let inventory = try await store.seedInventory(fromManifestFolder: Self.folder)
        #expect(inventory.unmodified.count == 3)
        #expect(inventory.edited.map(\.id) == [kettle.record.id])

        // "Add Welcome Songs" again brings the original back next to the edited copy.
        let again = try await store.seedSongs(fromManifestFolder: Self.folder)
        #expect(again.filter(\.created).map(\.file) == ["kettle-on-lights-low.cho"])
        #expect(try await store.allSongs().count == 5)
    }

    @Test
    func `seeding into a library with songs leaves them untouched`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let mine = try await store
            .createSong(source: "{title: Soundcheck at Seven}\n[G]My own words\n")
        let choBefore = try lib.bytes(mine.relativePath)
        let sidecarBefore = try lib.bytes("songs/soundcheck-at-seven.segue.json")

        let seeded = try await store.seedSongs(fromManifestFolder: Self.folder)

        #expect(seeded.count { $0.created } == seeded.count)
        #expect(try lib.bytes(mine.relativePath) == choBefore)
        #expect(try lib.bytes("songs/soundcheck-at-seven.segue.json") == sidecarBefore)
        #expect(try await store.song(id: mine.id)?.sidecar.tags.isEmpty == true)
        let welcome = try #require(seeded.first { $0.file == "soundcheck-at-seven.cho" })
        #expect(welcome.record.relativePath == "songs/soundcheck-at-seven-2.cho")
        #expect(try await store.allSongs().count == 5)
    }

    @Test
    func `the Hindi song is found by spelling variants`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let seeded = try await store.seedSongs(fromManifestFolder: Self.folder)
        let hindi = try #require(seeded.first { $0.file == "kitaabon-wali-gali.cho" }).record.id

        for query in ["kitabon", "kitaabon", "Kitaabon Wali", "muskan", "baarish", "barish"] {
            #expect(try await store.search(query: query).first?.id == hindi, "query: \(query)")
        }
    }

    @Test
    func `the demo setlist plan builds the Welcome Set at 15 10 of 20 00`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let seeded = try await store.seedSongs(fromManifestFolder: Self.folder)
        let manifest = try SeedManifest.load(fromFolder: Self.folder, fileSystem: LiveFileSystem())
        let plan = try #require(manifest.setlist)
        let ids = Dictionary(uniqueKeysWithValues: seeded.map { ($0.file, $0.record.id) })
        let (setlists, _) = try await lib.loadSetlists()

        var setlist = try await setlists.create(name: plan.name)
        let songIDs = plan.entries.compactMap { ids[$0.song] }
        setlist = try await setlists.insertSongs(songIDs, into: setlist.id)
        for (entry, planned) in zip(setlist.entries, plan.entries) {
            var updated = entry
            updated.overrides = SetlistOverrides(
                transpose: planned.overrides?.transpose,
                capo: planned.overrides?.capo,
            )
            updated.note = planned.note
            setlist = try await setlists.updateEntry(updated, in: setlist.id)
        }
        setlist = try await setlists.updateDetails(
            SetlistDetails(targetDuration: plan.targetDuration),
            of: setlist.id,
        )

        #expect(setlist.entries.count == 4)
        #expect(setlist.entries[1].overrides.transpose == -2)
        #expect(setlist.entries[2].note == "Brushes, start soft")
        #expect(setlist.entries[3].note == "Closer: big finish")
        #expect(setlist.venue == nil && setlist.date == nil)
        let lengths = Dictionary(uniqueKeysWithValues: seeded.compactMap { song in
            SetlistTiming.directiveLength(of: song.record).map { (song.record.id, $0) }
        })
        let timing = SetlistTiming(
            entries: setlist.entries,
            lengths: lengths,
            target: setlist.targetDuration,
        )
        #expect(timing.totalText == "15:10")
        #expect(timing.target.map(SetlistTiming.format) == "20:00")
    }

    @Test
    func `a second manifest with another tag seeds alongside the Welcome songs`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let welcome = try await store.seedSongs(fromManifestFolder: Self.folder)
        let welcomeSidecars = try Self.sidecars(lib)
        let other = try SeedFolder(manifest: """
        { "schema": 1, "tag": "Screenshots", "futureKey": true,
          "songs": [ { "file": "harbour-gulls.cho", "tags": ["Screenshots"] } ] }
        """, songs: ["harbour-gulls.cho": "{title: Harbour Gulls}\n[D]Gulls over [G]water\n"])

        let seeded = try await store.seedSongs(fromManifestFolder: other.url)

        #expect(seeded.map(\.file) == ["harbour-gulls.cho"])
        #expect(seeded.first?.record.sidecar.tags == ["Screenshots"])
        #expect(try await store.allSongs().count == 5)
        #expect(try await store.songs(taggedWith: "Welcome").map(\.id).sorted()
            == welcome.map(\.record.id).sorted())
        #expect(try Self.sidecars(lib) == welcomeSidecars)
        let otherManifest = try SeedManifest.load(
            fromFolder: other.url,
            fileSystem: LiveFileSystem(),
        )
        #expect(otherManifest.setlist == nil)
    }

    @Test
    func `a read-only library fails with a typed error and no partial sidecars`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        try lib.setPermissions(0o555, of: "songs")
        defer { try? lib.setPermissions(0o755, of: "songs") }

        await #expect {
            try await store.seedSongs(fromManifestFolder: Self.folder)
        } throws: { error in
            guard case let .writeFailed(file, _) = error as? SeedError else { return false }
            return file == "soundcheck-at-seven.cho"
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: lib.url("songs").path)
        for sidecar in names where sidecar.hasSuffix(".segue.json") {
            #expect(names.contains(String(sidecar.dropLast(".segue.json".count)) + ".cho"))
        }
        #expect(try await store.allSongs().isEmpty)
    }

    @Test
    func `invalid manifests are rejected with typed errors`() throws {
        let cases: [(String, SeedError)] = [
            (#"{ "schema": 2, "tag": "X", "songs": [] }"#, .unsupportedSchema(2)),
            (
                #"{ "schema": 1, "tag": "X", "songs": [ { "file": "gone.cho" } ] }"#,
                .missingFile("gone.cho"),
            ),
            (
                #"""
                { "schema": 1, "tag": "X", "songs": [],
                  "setlist": { "name": "S", "entries": [ { "song": "a.cho" } ] } }
                """#,
                .unknownSetlistSong("a.cho"),
            ),
        ]
        for (manifest, expected) in cases {
            let folder = try SeedFolder(manifest: manifest, songs: [:])
            #expect(throws: expected) {
                try SeedManifest.load(fromFolder: folder.url, fileSystem: LiveFileSystem())
            }
        }
        let broken = try SeedFolder(manifest: "{ not json", songs: [:])
        #expect {
            try SeedManifest.load(fromFolder: broken.url, fileSystem: LiveFileSystem())
        } throws: { error in
            if case .manifestUnreadable = error as? SeedError {
                return true
            }
            return false
        }
    }

    // MARK: - Support

    /// The four Welcome sidecars' bytes, in `files` order.
    private static func sidecars(_ lib: TestLibrary) throws -> [Data] {
        try files.map { try lib.bytes("songs/\($0.dropLast(4)).segue.json") }
    }

    /// Every chord text in `blocks`, in order (sections included).
    private static func chordTexts(_ blocks: [Block]) -> [String] {
        blocks.flatMap { block -> [String] in
            switch block {
            case let .line(line): line.segments.compactMap(\.chord)
            case let .section(section): chordTexts(section.items)
            default: []
            }
        }
    }
}

/// A temp seed folder with a manifest and song files. Deleted on deinit.
private final class SeedFolder: Sendable {
    let url: URL

    init(manifest: String, songs: [String: String]) throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "SegueSeed-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(manifest.utf8).write(to: url.appending(path: SeedManifest.fileName))
        for (name, text) in songs {
            try Data(text.utf8).write(to: url.appending(path: name))
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
