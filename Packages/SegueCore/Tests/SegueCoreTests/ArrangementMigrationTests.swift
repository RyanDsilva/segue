import ChordPro
import Editing
import Foundation
import Library
import Setlists
import Shows
import Support
import Testing

/// The arrangement files (P8-2 section 4): the v6 codec, `migrateV5`, a v5 setlist written
/// back at 6, and a v3 show record migrated to 4.
struct ArrangementMigrationTests {
    @Test
    func `the v6 codec omits Full, reads unknown modes as Full and ignores plays`() throws {
        let units = SlotArrangementTests.units()
        let arrangement = SlotArrangement(
            passes: [
                SlotArrangementTests.pass(units, "Intro", .chordsOnly),
                SlotArrangementTests.pass(units, "Verse 1"),
            ],
            knownParts: KnownPart.all(units),
        )
        let data = try SegueJSON.encode(arrangement)
        let json = try #require(String(bytes: data, encoding: .utf8))
        #expect(json.contains("\"mode\" : \"chords\""))
        #expect(json.components(separatedBy: "\"mode\"").count == 2)
        #expect(!json.contains("plays"))
        #expect(try SegueJSON.decode(SlotArrangement.self, from: data) == arrangement)

        let odd = Data(#"""
        {"passes": [{"section": "Verse", "occurrence": 1, "mode": "loud", "plays": 3},
                    {"loose": 2, "after": "Verse", "afterOccurrence": 1, "mode": "skip"}]}
        """#.utf8)
        let decoded = try SegueJSON.decode(SlotArrangement.self, from: odd)
        #expect(decoded.passes.map(\.mode) == [.full, .skip])
        #expect(decoded.passes.count == 2)
        #expect(decoded.knownParts.isEmpty)
        // No `knownParts`: the parts the passes name.
        #expect(decoded.effectiveKnownParts.map(\.anchor) == decoded.passes.map(\.anchor))
    }

    @Test
    func `migrateV5 expands plays into passes and lists the known parts`() throws {
        var json: [String: Any] = [
            "steps": [
                ["section": "Intro", "occurrence": 1, "fp": "aa", "plays": 0],
                ["section": "Chorus", "occurrence": 1, "fp": "bb", "plays": 2],
                ["loose": 1, "fp": "cc"],
                ["section": "Chorus", "occurrence": 1, "fp": "bb", "plays": 14],
            ],
            "length": 200,
        ]
        SlotArrangement.migrateV5(&json)
        let data = try JSONSerialization.data(withJSONObject: json)
        let arrangement = try SegueJSON.decode(SlotArrangement.self, from: data)
        let intro = SectionAnchor.section(SectionRef(label: "Intro", occurrence: 1))
        let chorus = SectionAnchor.section(SectionRef(label: "Chorus", occurrence: 1))
        let leadIn = SectionAnchor.loose(after: nil, block: 1)
        #expect(arrangement.passes.map(\.anchor)
            == [intro, chorus, chorus, leadIn] + Array(repeating: chorus, count: 9))
        #expect(arrangement.passes.map(\.mode)
            == [.skip] + Array(repeating: PassMode.full, count: 12))
        #expect(arrangement.passes[1].fingerprint == "bb")
        #expect(arrangement.knownParts == [
            KnownPart(anchor: intro, fingerprint: "aa"),
            KnownPart(anchor: chorus, fingerprint: "bb"),
            KnownPart(anchor: leadIn, fingerprint: "cc"),
        ])
        #expect(json["steps"] == nil)
    }

    @Test
    func `a v5 setlist file migrates to passes and is written back at 6`() async throws {
        let lib = try TestLibrary()
        let song = SongID(ULID(milliseconds: 5, randomness: Array(repeating: 7, count: 10)))
        let item = SetlistItemID(ULID(milliseconds: 6, randomness: Array(repeating: 8, count: 10)))
        let setlistID = SetlistID(ULID(milliseconds: 4, randomness: Array(repeating: 9, count: 10)))
        let v5 = """
        {"schemaVersion": 5, "id": "\(setlistID)", "name": "Five",
         "entries": [{"itemId": "\(item)", "songId": "\(song)", "arrangement": {
           "steps": [{"section": "Verse", "occurrence": 1, "fp": "aa", "plays": 1},
                     {"section": "Bridge", "occurrence": 1, "fp": "bb", "plays": 0},
                     {"section": "Chorus", "occurrence": 1, "fp": "cc", "plays": 2},
                     {"loose": 1, "after": "Chorus", "afterOccurrence": 1, "fp": "dd"}],
           "length": 180}}]}
        """
        try lib.write(v5, to: "setlists/five.setlist.json")

        let (store, issues) = try await lib.loadSetlists()

        #expect(issues.isEmpty)
        let setlist = try #require(await store.setlist(id: setlistID))
        #expect(setlist.readOnly == nil)
        let arrangement = try #require(setlist.entries[0].arrangement)
        #expect(arrangement.passes.map(\.anchor.summaryName)
            == ["Verse", "Bridge", "Chorus", "Chorus", "After Chorus"])
        #expect(arrangement.passes.map(\.mode) == [.full, .skip, .full, .full, .full])
        #expect(arrangement.knownParts.count == 4)

        // The next save writes the current schema.
        _ = try await store.updateEntry(setlist.entries[0], in: setlistID)
        _ = try await store.rename(setlistID, to: "Five again")
        let json = try lib.read("setlists/five.setlist.json")
        #expect(json.contains("\"schemaVersion\" : 7"))
        #expect(json.contains("\"passes\""))
        #expect(!json.contains("\"steps\""))
        #expect(!json.contains("\"plays\""))
        // The old slot length key is ignored on read and dropped on this save (P8-8 7.1).
        #expect(!json.contains("\"length\""))
    }

    @Test
    func `a v3 show record migrates its items' and planned arrangements to passes`() async throws {
        let harness = try await ShowHarness()
        var (setlist, _) = try await harness.makeSet(2)
        var entry = setlist.entries[0]
        let anchor = SectionAnchor.loose(after: nil, block: 1)
        entry.arrangement = SlotArrangement(passes: [ArrangementPass(anchor: anchor)])
        setlist = try await harness.setlists.updateEntry(entry, in: setlist.id)
        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        let id = await show.state.record.id
        try await show.recordArrangementState(.applied, for: ShowItemID(entry.itemId.ulid))
        _ = try await show.perform(.next) // writes the recorded state

        // Rewrite the file as a v3 build wrote it: `steps` with `plays`.
        let path = harness.showPath(id)
        var object = try #require(try JSONSerialization.jsonObject(
            with: Data(harness.lib.read(path).utf8),
        ) as? [String: Any])
        let v5Arrangement: [String: Any] = [
            "steps": [["loose": 1, "plays": 3], ["loose": 2, "plays": 0]],
            "length": 60,
        ]
        object["schemaVersion"] = 3
        for key in ["items", "planned"] {
            var list = try #require(object[key] as? [[String: Any]])
            list[0]["arrangement"] = v5Arrangement
            object[key] = list
        }
        let data = try JSONSerialization.data(withJSONObject: object)
        try harness.lib.write(#require(String(bytes: data, encoding: .utf8)), to: path)

        let reloaded = try #require(try await harness.reloadedShow(id))
        let expected = SlotArrangement(
            passes: Array(repeating: ArrangementPass(anchor: anchor), count: 3)
                + [ArrangementPass(anchor: .loose(after: nil, block: 2), mode: .skip)],
            knownParts: [
                KnownPart(anchor: anchor),
                KnownPart(anchor: .loose(after: nil, block: 2)),
            ],
        )
        #expect(reloaded.items[0].arrangement == expected)
        #expect(reloaded.planned[0].arrangement == expected)
        #expect(reloaded.items[0].arrangementState == .applied)
        #expect(reloaded.items[1].arrangement == nil)
    }
}
