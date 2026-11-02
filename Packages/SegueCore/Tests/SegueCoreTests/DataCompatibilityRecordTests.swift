import Diagrams
import Editing
import Foundation
import Library
import Setlists
import Shows
import Support
import Testing

// The compatibility suite, continued (`DataCompatibilityTests.swift` holds the fixtures,
// the format registry and the guard): shows, smart filters, the files the app only reads,
// and the unversioned records.

struct DataCompatibilityShowTests {
    // MARK: Show (`shows/<ulid>.show.json`, the Gig Log)

    private let path = "shows/\(CompatFixtures.show)\(LibraryRoot.showSuffix)"

    private func loadShow(_ fixture: String) async throws -> (TestLibrary, ShowStore) {
        let lib = try TestLibrary()
        try lib.write(CompatFixtures.text("show", fixture), to: path)
        let store = ShowStore(fileSystem: lib.fileSystem, clock: lib.clock, playHistory: nil)
        let issues = try await store.load(root: lib.root, state: lib.state)
        #expect(issues.isEmpty, "\(issues)")
        return (lib, store)
    }

    @Test(arguments: CompatFixtures.inputs(.named("show")))
    func `a show migrates, takes a gig log edit and saves at the current version`(
        _ fixture: String,
    ) async throws {
        let (lib, store) = try await loadShow(fixture)
        let id = try ShowID(CompatFixtures.ulid(CompatFixtures.show))
        let record = try #require(await store.all().first { $0.id == id })
        #expect(record.readOnly == nil)
        var gig = record.gig
        gig.notes = (gig.notes ?? "") + " (compat)"
        _ = try await store.updateGigDetails(gig, of: id)
        let saved = try lib.read(path)
        #expect(try CompatFixtures.object(saved)["schemaVersion"] as? Int
            == ShowRecord.currentSchemaVersion)
        try CompatFixtures.expectGolden(saved, "show", fixture)
    }

    @Test
    func `a show keeps keys, events and requests it does not know through an edit`(
    ) async throws {
        let (lib, store) = try await loadShow("unknown-keys.json")
        let id = try ShowID(CompatFixtures.ulid(CompatFixtures.show))
        let record = try #require(await store.all().first { $0.id == id })
        #expect(record.closure == nil) // "encore" is not a case here
        #expect(record.gig.rating == nil) // "five stars" is not a rating
        _ = try await store.updateGigDetails(GigDetails(venue: "Edited"), of: id)

        let saved = try CompatFixtures.object(lib.read(path))
        #expect(saved["closure"] as? String == "encore")
        #expect((saved["futureTopLevel"] as? [String: Any])?["setlistColour"] as? String == "teal")
        let gig = try #require(saved["gig"] as? [String: Any])
        #expect(gig["venue"] as? String == "Edited")
        #expect(gig["futureGig"] as? String == "soundcheck at 7")
        #expect(gig["rating"] as? String == "five stars")
        let items = try #require(saved["items"] as? [[String: Any]])
        #expect(items[0]["futureItem"] as? String == "encore")
        let events = try #require(saved["events"] as? [[String: Any]])
        #expect(events.last?["kind"] as? String == "lightsDimmed")
        let requests = try #require(saved["requests"] as? [[String: Any]])
        #expect(requests.last?["state"] as? String == "deferred")
    }

    @Test
    func `a newer show is shown read-only and never rewritten`() async throws {
        let (lib, store) = try await loadShow("future.json")
        let before = try lib.read(path)
        let id = try ShowID(CompatFixtures.ulid(CompatFixtures.show))
        let record = try #require(await store.all().first { $0.id == id })
        #expect(record.readOnly == .newerSchema(
            found: 999,
            supported: ShowRecord.currentSchemaVersion,
        ))
        await #expect(throws: ShowError.self) {
            try await store.updateGigDetails(GigDetails(venue: "x"), of: id)
        }
        #expect(try lib.read(path) == before)
    }
}

struct DataCompatibilityFilterTests {
    // MARK: Smart filter (`filters/<slug>.filter.json`)

    private func loadFilter(_ fixture: String) throws -> (TestLibrary, SmartFilterStore) {
        let lib = try TestLibrary()
        try lib.write(CompatFixtures.text("filter", fixture), to: "filters/slow.filter.json")
        let store = SmartFilterStore(fileSystem: lib.fileSystem, clock: lib.clock, ids: lib.ids)
        return (lib, store)
    }

    @Test(arguments: CompatFixtures.inputs(.named("filter")))
    func `a smart filter migrates, takes an edit and saves at the current version`(
        _ fixture: String,
    ) async throws {
        let (lib, store) = try loadFilter(fixture)
        let issues = try await store.load(root: lib.root)
        #expect(issues.isEmpty, "\(issues)")
        let id = try SmartFilterID(CompatFixtures.ulid(CompatFixtures.filter))
        let filter = try #require(await store.filter(id: id))
        #expect(filter.readOnly == nil)
        _ = try await store.rename(id, to: filter.name + " (compat)")
        let saved = try lib.read("filters/slow.filter.json")
        try CompatFixtures.expectGolden(saved, "filter", fixture)
    }

    @Test
    func `a smart filter keeps conditions it does not know through an edit`() async throws {
        let (lib, store) = try loadFilter("unknown-keys.json")
        try await store.load(root: lib.root)
        let id = try SmartFilterID(CompatFixtures.ulid(CompatFixtures.filter))
        let filter = try #require(await store.filter(id: id))
        #expect(filter.conditions.proficiencies == [.ready])
        var conditions = SmartFilterConditions(proficiencies: [.ready, .pro])
        conditions.keys = ["D"]
        _ = try await store.update(id, conditions: conditions)

        let saved = try CompatFixtures.object(lib.read("filters/slow.filter.json"))
        #expect(saved["futureTopLevel"] as? Int == 1)
        let stored = try #require(saved["conditions"] as? [String: Any])
        #expect(stored["proficiencies"] as? [String] == ["ready", "pro", "virtuoso"])
        #expect((stored["futureCondition"] as? [String: Any])?["mood"] as? String == "sad")
        // The removed Length condition (P8-8 7.1) is dropped, not kept.
        #expect(stored["length"] == nil)
    }

    @Test
    func `a newer smart filter is usable read-only and never rewritten`() async throws {
        let (lib, store) = try loadFilter("future.json")
        try await store.load(root: lib.root)
        let before = try lib.read("filters/slow.filter.json")
        let id = try SmartFilterID(CompatFixtures.ulid(CompatFixtures.filter))
        let filter = try #require(await store.filter(id: id))
        #expect(filter.readOnly == .newerSchema(
            found: 999,
            supported: SmartFilter.currentSchemaVersion,
        ))
        #expect(filter.conditions.allTags == ["gig"])
        await #expect(throws: SmartFilterError.self) {
            try await store.rename(id, to: "x")
        }
        #expect(try lib.read("filters/slow.filter.json") == before)
    }
}

struct DataCompatibilityAppFileTests {
    // MARK: Files the app only reads

    @Test(arguments: PersistedFormat.named("bindings").versions.map { "v\($0).json" })
    func `every bindings version applies its bindings`(_ fixture: String) throws {
        let lib = try TestLibrary()
        try lib.write(CompatFixtures.text("bindings", fixture), to: "bindings.json")
        let loaded = try InputBindingTable.loadReporting(
            from: lib.url("bindings.json"),
            fileSystem: lib.fileSystem,
        )
        #expect(loaded.newerSchema == nil)
        #expect(loaded.table.command(for: .key(KeyStroke("n"))) == .next)
    }

    @Test
    func `a newer bindings file applies what it can and reports the rest`() throws {
        let lib = try TestLibrary()
        try lib.write(CompatFixtures.text("bindings", "future.json"), to: "bindings.json")
        let loaded = try InputBindingTable.loadReporting(
            from: lib.url("bindings.json"),
            fileSystem: lib.fileSystem,
        )
        #expect(loaded.newerSchema == 999)
        #expect(loaded.skipped == 2)
        #expect(loaded.table.command(for: .key(KeyStroke("n"))) == .next)
    }

    @Test
    func `the shape library reads its version and refuses a newer one untouched`() throws {
        let lib = try TestLibrary()
        try lib.write(CompatFixtures.text("shapes", "v1.json"), to: "shapes.json")
        #expect(try UserShapeLibrary.load(from: lib.url("shapes.json"), fileSystem: lib.fileSystem)
            == .empty)
        try lib.write(CompatFixtures.text("shapes", "future.json"), to: "future.json")
        #expect(throws: UserShapeLibraryError.self) {
            try UserShapeLibrary.load(from: lib.url("future.json"), fileSystem: lib.fileSystem)
        }
    }

    @Test
    func `the library identity is read at every version and never re-minted`() throws {
        for fixture in ["v1.json", "future.json"] {
            let lib = try TestLibrary()
            let text = try CompatFixtures.text("library-identity", fixture)
            try lib.write(text, to: ".segue/library.json")
            let identity = try LibraryIdentity.resolve(
                root: lib.root,
                fileSystem: lib.fileSystem,
                clock: lib.clock,
                ids: lib.ids,
            )
            #expect(identity.id.description == "01JKKKKKKKKKKKKKKKKKKKKKKK")
            #expect(try lib.read(".segue/library.json") == text)
        }
    }

    // MARK: Unversioned records (state, upgrade marks, settings)

    @Test
    func `state and upgrade records keep keys they do not know`() throws {
        let lib = try TestLibrary()
        let state = lib.state
        try FileManager.default.createDirectory(at: state.url, withIntermediateDirectories: true)
        try Data(#"{"lastRoot": "/old", "syncDevice": "01JDEVICE0000000000000000A"}"#.utf8)
            .write(to: state.stateFile)
        var record = try #require(LibraryStateRecord.read(state, fileSystem: lib.fileSystem))
        record.fileSyncWarningDismissed = true
        try record.write(to: state, fileSystem: lib.fileSystem)
        let saved = try CompatFixtures.object(String(contentsOf: state.stateFile, encoding: .utf8))
        #expect(saved["syncDevice"] as? String == "01JDEVICE0000000000000000A")
        #expect(saved["fileSyncWarningDismissed"] as? Bool == true)

        try lib.write(#"{"stateMoved": true, "historyMoved": true}"#, to: ".segue/upgrades.json")
        var upgrades = LibraryUpgrade.state(root: lib.root, fileSystem: lib.fileSystem)
        #expect(upgrades.stateMoved)
        upgrades.durationCleanupOffered = true
        try LibraryUpgrade.save(upgrades, root: lib.root, fileSystem: lib.fileSystem)
        let marks = try CompatFixtures.object(lib.read(".segue/upgrades.json"))
        #expect(marks["historyMoved"] as? Bool == true)
        #expect(marks["durationCleanupOffered"] as? Bool == true)
    }

    @Test
    func `settings values keep keys they do not know and read unknown cases as defaults`(
    ) throws {
        let live = try SegueJSON.decode(LiveSettings.self, from: Data(#"""
        {"minLyricSize": 30, "hiddenChecklistRows": ["focus", "lasers"], "stageLights": "dim"}
        """#.utf8))
        #expect(live.minLyricSize == 30)
        #expect(live.hiddenChecklistItems == [.focus])
        let liveSaved = try CompatFixtures.object(#require(String(
            bytes: SegueJSON.encode(live),
            encoding: .utf8,
        )))
        #expect(liveSaved["stageLights"] as? String == "dim")

        let profile = try SegueJSON.decode(InstrumentProfile.self, from: Data(#"""
        {"playsBass": true, "genre": "polka", "pedalBoard": {"loops": 2}}
        """#.utf8))
        #expect(profile.playsBass)
        #expect(profile.genre == InstrumentProfile().genre)
        let profileSaved = try CompatFixtures.object(
            #require(String(bytes: SegueJSON.encode(profile), encoding: .utf8)),
        )
        #expect((profileSaved["pedalBoard"] as? [String: Any])?["loops"] as? Int == 2)
    }
}
