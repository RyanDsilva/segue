import Diagrams
import Editing
import Foundation
import Library
import Setlists
import Shows
import Support
import Testing

// The persisted-format compatibility suite (docs/architecture/data-compatibility.md).
//
// Every versioned format has a fixture per schema version under `Fixtures/compat/<format>/`
// (`v<N>.json`), one written by a newer Segue (`future.json`) and, for the library files,
// one at the current version full of keys and values this build does not know
// (`unknown-keys.json`). Each fixture goes through the real store on a real temp library:
// loaded, edited the way the app edits it, saved, and the saved bytes compared with the
// golden `<fixture>.saved.json` beside it.
//
// Goldens are written, never hand-edited: run
// `SEGUE_UPDATE_COMPAT_GOLDENS=1 swift test --filter DataCompatibility` and review the diff.
//
// The guard (`DataCompatibilityGuardTests`): bumping a `currentSchemaVersion` without adding
// that version's fixture (and so its migration test and golden) fails, and so does adding a
// new versioned format without registering it here.

/// The fixture folder in the source tree (read and, for goldens, written in place).
enum CompatFixtures {
    static let directory = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Fixtures/compat", directoryHint: .isDirectory)

    static let updating = ProcessInfo.processInfo.environment["SEGUE_UPDATE_COMPAT_GOLDENS"] == "1"

    static func url(_ format: String, _ name: String) -> URL {
        directory.appending(path: "\(format)/\(name)")
    }

    static func text(_ format: String, _ name: String) throws -> String {
        try String(contentsOf: url(format, name), encoding: .utf8)
    }

    static func exists(_ format: String, _ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(format, name).path(percentEncoded: false))
    }

    /// The fixture names of `format` to migrate: every `v<N>.json` plus `unknown-keys.json`.
    static func inputs(_ format: PersistedFormat) -> [String] {
        format.versions.map { "v\($0).json" } + (format.hasUnknownKeysFixture
            ? ["unknown-keys.json", compatibleNewer] : [])
    }

    /// A file from a newer Segue (version 999) whose `minReaderVersion` this build meets
    /// (R196): editable, saved at its own version, keeping what it added.
    static let compatibleNewer = "compatible-newer.json"

    /// The versions a save of fixture `name` of `format` must write (R196): the current
    /// version, or the newer file's own; `minReaderVersion` the format's current minimum.
    static func expectVersions(
        _ saved: String,
        _ format: PersistedFormat,
        _ name: String,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) throws {
        let object = try object(saved)
        let newer = name == compatibleNewer
        #expect(
            object["schemaVersion"] as? Int == (newer ? 999 : format.current),
            sourceLocation: sourceLocation,
        )
        #expect(
            object["minReaderVersion"] as? Int == format.current,
            sourceLocation: sourceLocation,
        )
        if newer {
            #expect(object["addedByANewerSegue"] != nil, sourceLocation: sourceLocation)
        }
    }

    /// Compares `saved` with the golden for fixture `name`, or writes it when updating.
    static func expectGolden(
        _ saved: String,
        _ format: String,
        _ name: String,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) throws {
        let golden = name.replacingOccurrences(of: ".json", with: ".saved.json")
        if updating {
            try Data(saved.utf8).write(to: url(format, golden))
            return
        }
        let expected = try text(format, golden)
        #expect(saved == expected, "\(format)/\(name)", sourceLocation: sourceLocation)
    }

    /// `text` as a JSON object.
    static func object(_ text: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    static func ulid(_ text: String) throws -> ULID {
        try #require(ULID(string: text))
    }

    static let song = "01JAAAAAAAAAAAAAAAAAAAAAAA"
    static let setlist = "01JCCCCCCCCCCCCCCCCCCCCCCC"
    static let show = "01JEEEEEEEEEEEEEEEEEEEEEEE"
    static let filter = "01JFFFFFFFFFFFFFFFFFFFFFFF"
}

/// A versioned on-disk format and the versions it must keep reading.
struct PersistedFormat: Sendable, CustomTestStringConvertible {
    /// The fixture folder name.
    let name: String
    /// The version this build writes.
    let current: Int
    /// The oldest version this build still reads (0 = pre-versioned files).
    let oldest: Int
    /// Written by the app (golden-checked after an edit), not only read.
    let writable: Bool
    /// The source file declaring `current`, relative to `Packages/<package>/Sources/`.
    let source: String

    var versions: ClosedRange<Int> {
        oldest ... current
    }

    var hasUnknownKeysFixture: Bool {
        writable
    }

    var testDescription: String {
        name
    }

    /// Every versioned format the app persists. Add a row when adding one.
    static let all: [Self] = [
        Self(
            name: "sidecar",
            current: Sidecar.currentSchemaVersion,
            oldest: 0,
            writable: true,
            source: "SegueCore/Sources/Library/Sidecar.swift",
        ),
        Self(
            name: "setlist",
            current: Setlist.currentSchemaVersion,
            oldest: 0,
            writable: true,
            source: "SegueCore/Sources/Setlists/Setlist.swift",
        ),
        Self(
            name: "show",
            current: ShowRecord.currentSchemaVersion,
            oldest: 1,
            writable: true,
            source: "SegueCore/Sources/Shows/ShowRecord.swift",
        ),
        Self(
            name: "filter",
            current: SmartFilter.currentSchemaVersion,
            oldest: 0,
            writable: true,
            source: "SegueCore/Sources/Library/SmartFilter.swift",
        ),
        Self(
            name: "bindings",
            current: InputBindingTable.currentSchemaVersion,
            oldest: 0,
            writable: false,
            source: "SegueCore/Sources/Shows/InputBindings.swift",
        ),
        Self(
            name: "shapes",
            current: UserShapeLibrary.currentSchemaVersion,
            oldest: 1,
            writable: false,
            source: "SegueCore/Sources/Diagrams/ShapeResolver.swift",
        ),
        Self(
            name: "library-identity",
            current: LibraryIdentity.currentSchema,
            oldest: 1,
            writable: false,
            source: "SegueCore/Sources/Support/LibraryIdentity.swift",
        ),
    ]

    /// Versioned values that are not user data: a version change rebuilds them.
    static let rebuildable: [String: String] = [
        "SegueCore/Sources/Library/SongIndex.swift": "the search index (rebuilt on a change)",
    ]

    static func named(_ name: String) -> Self {
        guard let format = all.first(where: { $0.name == name }) else {
            preconditionFailure("no persisted format \(name)")
        }
        return format
    }
}

// MARK: - The guard

struct DataCompatibilityGuardTests {
    /// Bumping a schema without its fixture, migration test and golden fails here.
    @Test(arguments: PersistedFormat.all)
    func `every schema version has a fixture and a golden`(_ format: PersistedFormat) {
        for version in format.versions {
            #expect(
                CompatFixtures.exists(format.name, "v\(version).json"),
                "add Fixtures/compat/\(format.name)/v\(version).json (and its migration)",
            )
            if format.writable, !CompatFixtures.updating {
                #expect(
                    CompatFixtures.exists(format.name, "v\(version).saved.json"),
                    "record the golden: SEGUE_UPDATE_COMPAT_GOLDENS=1",
                )
            }
        }
        #expect(CompatFixtures.exists(format.name, "future.json"))
        #expect(CompatFixtures.exists(format.name, CompatFixtures.compatibleNewer))
        if format.hasUnknownKeysFixture {
            #expect(CompatFixtures.exists(format.name, "unknown-keys.json"))
        }
    }

    /// `future.json` must stay newer than this build, or it tests nothing.
    @Test(arguments: PersistedFormat.all)
    func `the future fixture is newer than this build`(_ format: PersistedFormat) throws {
        let object = try CompatFixtures.object(CompatFixtures.text(format.name, "future.json"))
        let version = (object["schemaVersion"] ?? object["schema"]) as? Int
        #expect((version ?? 0) > format.current)
    }

    /// A new versioned format (a `static let currentSchemaVersion` anywhere in the packages)
    /// must be registered in `PersistedFormat.all` (or listed as rebuildable).
    @Test
    func `every versioned format is registered`() throws {
        let packages = CompatFixtures.directory
            .deletingLastPathComponent() // compat
            .deletingLastPathComponent() // Fixtures
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // SegueCore
        let pattern = /static let (currentSchemaVersion|currentSchema|schemaVersion) = \d+/
        var declaring: Set<String> = []
        let enumerator = FileManager.default.enumerator(
            at: packages,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles],
        )
        while let url = enumerator?.nextObject() as? URL {
            let path = url.path(percentEncoded: false)
            guard path.hasSuffix(".swift"), path.contains("/Sources/"),
                  !path.contains("/.build/")
            else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains(pattern) {
                let base = packages.path(percentEncoded: false)
                declaring.insert(String(path.dropFirst(base.count + (base.hasSuffix("/") ? 0 : 1))))
            }
        }
        let registered = Set(PersistedFormat.all.map(\.source))
            .union(PersistedFormat.rebuildable.keys)
        #expect(declaring == registered)
    }
}

// MARK: - Library files through the real stores

struct DataCompatibilitySongTests {
    // MARK: Sidecar (`songs/<slug>.segue.json`)

    private func openSong(_ fixture: String) async throws -> (TestLibrary, LibraryStore) {
        let lib = try TestLibrary()
        try lib.write(CompatFixtures.text("", "song.cho"), to: "songs/harbour-lights.cho")
        try lib.write(
            CompatFixtures.text("sidecar", fixture),
            to: "songs/harbour-lights.segue.json",
        )
        return try await (lib, lib.openStore())
    }

    @Test(arguments: CompatFixtures.inputs(.named("sidecar")))
    func `a sidecar migrates, takes an edit and saves at the current version`(
        _ fixture: String,
    ) async throws {
        let (lib, store) = try await openSong(fixture)
        let id = try SongID(CompatFixtures.ulid(CompatFixtures.song))
        let record = try #require(try await store.song(id: id))
        #expect(record.readOnly == nil)
        let sidecar = record.sidecar
        _ = try await store.updateMetadata(id: id, SongMetadata(
            tags: sidecar.tags + ["compat"],
            proficiency: sidecar.proficiency,
            notes: sidecar.notes,
            cues: sidecar.cues,
        ))
        let saved = try lib.read("songs/harbour-lights.segue.json")
        try CompatFixtures.expectVersions(saved, .named("sidecar"), fixture)
        try CompatFixtures.expectGolden(saved, "sidecar", fixture)
    }

    @Test
    func `a sidecar keeps keys and values it does not know through an edit`() async throws {
        let (lib, store) = try await openSong("unknown-keys.json")
        let id = try SongID(CompatFixtures.ulid(CompatFixtures.song))
        let record = try #require(try await store.song(id: id))
        #expect(record.sidecar.proficiency == nil) // "virtuoso" is not a case here
        #expect(record.sidecar.cues.count == 2) // the sticker cue is unreadable
        #expect(record.sidecar.parts.count == 1) // so is the keys part
        _ = try await store.updateDisplayPrefs(id: id, DisplayPrefs(transpose: 5))
        _ = try await store.updateMetadata(id: id, SongMetadata(tags: ["edited"]))

        let saved = try CompatFixtures.object(lib.read("songs/harbour-lights.segue.json"))
        #expect(saved["proficiency"] as? String == "virtuoso")
        #expect((saved["futureTopLevel"] as? [String: Any])?["keep"] != nil)
        let prefs = try #require(saved["displayPrefs"] as? [String: Any])
        #expect(prefs["hologram"] as? String == "on")
        #expect(prefs["transpose"] as? Int == 5)
        #expect((saved["live"] as? [String: Any])?["futureLive"] as? Int == 3)
        #expect((saved["bass"] as? [String: Any])?["futureBass"] as? String == "yes")
        // Cues were replaced by the edit (none), so only the unreadable one is left.
        let cues = try #require(saved["cues"] as? [[String: Any]])
        #expect(cues.map { $0["kind"] as? String } == ["sticker"])
        let parts = try #require(saved["parts"] as? [[String: Any]])
        #expect(parts.map { $0["instrument"] as? String } == ["bass", "keys"])
        #expect(parts.first?["futurePart"] as? Int == 7)
    }

    @Test
    func `a newer sidecar opens read-only and is never rewritten`() async throws {
        let (lib, store) = try await openSong("future.json")
        let before = try lib.read("songs/harbour-lights.segue.json")
        let id = try SongID(CompatFixtures.ulid(CompatFixtures.song))
        let record = try #require(try await store.song(id: id))
        #expect(record.readOnly == .newerSchema(
            found: 999,
            supported: Sidecar.currentSchemaVersion,
        ))
        #expect(record.sidecar.tags == ["wedding"])
        await #expect(throws: LibraryError.self) {
            try await store.updateMetadata(id: id, SongMetadata(tags: ["x"]))
        }
        #expect(try lib.read("songs/harbour-lights.segue.json") == before)
    }
}

struct DataCompatibilitySetlistTests {
    // MARK: Setlist (`setlists/<slug>.setlist.json`)

    private func loadSetlist(_ fixture: String) async throws -> (TestLibrary, SetlistStore) {
        let lib = try TestLibrary()
        try lib.write(CompatFixtures.text("setlist", fixture), to: "setlists/friday.setlist.json")
        let (store, issues) = try await lib.loadSetlists()
        #expect(issues.isEmpty, "\(issues)")
        return (lib, store)
    }

    @Test(arguments: CompatFixtures.inputs(.named("setlist")))
    func `a setlist migrates, takes an edit and saves at the current version`(
        _ fixture: String,
    ) async throws {
        let (lib, store) = try await loadSetlist(fixture)
        let id = try SetlistID(CompatFixtures.ulid(CompatFixtures.setlist))
        let setlist = try #require(await store.setlist(id: id))
        #expect(setlist.readOnly == nil)
        _ = try await store.rename(id, to: setlist.name + " (compat)")
        let saved = try lib.read("setlists/friday.setlist.json")
        try CompatFixtures.expectVersions(saved, .named("setlist"), fixture)
        try CompatFixtures.expectGolden(saved, "setlist", fixture)
    }

    @Test
    func `a setlist keeps keys and members it does not know through an edit`() async throws {
        let (lib, store) = try await loadSetlist("unknown-keys.json")
        let id = try SetlistID(CompatFixtures.ulid(CompatFixtures.setlist))
        let setlist = try #require(await store.setlist(id: id))
        #expect(setlist.entries.last?.medley?.members.count == 2)
        _ = try await store.updateEntry(setlist.entries[0], in: id)
        _ = try await store.rename(id, to: "Edited")

        let saved = try CompatFixtures.object(lib.read("setlists/friday.setlist.json"))
        #expect((saved["futureTopLevel"] as? [String: Any])?["lighting"] as? String == "warm")
        let entries = try #require(saved["entries"] as? [[String: Any]])
        #expect(entries[0]["futureSlot"] as? String == "encore")
        let medley = try #require(entries.last?["medley"] as? [String: Any])
        #expect(medley["futureMedley"] as? Int == 1)
        let members = try #require(medley["members"] as? [[String: Any]])
        #expect(members.count == 3)
        #expect(members[0]["futureMember"] as? Bool == true)
        #expect(members[2]["hologram"] as? Bool == true)
    }

    @Test
    func `a newer setlist loads read-only and is never rewritten`() async throws {
        let (lib, store) = try await loadSetlist("future.json")
        let before = try lib.read("setlists/friday.setlist.json")
        let id = try SetlistID(CompatFixtures.ulid(CompatFixtures.setlist))
        let setlist = try #require(await store.setlist(id: id))
        #expect(setlist.readOnly == .newerSchema(
            found: 999,
            supported: Setlist.currentSchemaVersion,
        ))
        #expect(setlist.songIds.count == 2)
        await #expect(throws: SetlistError.self) {
            try await store.rename(id, to: "x")
        }
        #expect(try lib.read("setlists/friday.setlist.json") == before)
    }
}
