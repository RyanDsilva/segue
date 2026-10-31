import Editing
import Foundation
import Library
import MusicTheory
import Support
import Testing

/// Sidecar schema 6 (P8-7 section 9.5): `parts`, its migration from v5 and its lenient
/// decoding. Real files, real index.
struct PartsSidecarTests {
    /// The section 9.5 example.
    static let example = """
    {"id": "01JD7Q3W5N8K2M4R6T0V9X1Y3Z", "instrument": "bass", "name": "Into last chorus",
     "start": {"section": "Bridge", "occurrence": 1, "fp": "9f8e7d6c", "chord": 3, "from": "E"},
     "end":   {"section": "Chorus", "occurrence": 3, "fp": "1a2b3c4d", "chord": 0, "from": "A"},
     "span": ["E", "A"], "passes": "all", "show": "names",
     "origin": {"family": "pickup", "template": "pickup8", "rank": "b", "edited": true},
     "events": [
       {"chord": 0, "at": 960,  "len": 240, "deg": 0,  "oct": 0},
       {"chord": 0, "at": 1200, "len": 240, "deg": 2,  "oct": 0, "string": "A1"},
       {"chord": 0, "at": 1440, "len": 240, "deg": 4,  "oct": 0, "art": ["slide"]},
       {"chord": 1, "at": 0,    "len": 480, "deg": 0,  "oct": 0, "vel": 110}
     ]}
    """

    static func decode(_ json: String) throws -> Part {
        try JSONDecoder().decode(Part.self, from: Data(json.utf8))
    }

    @Test
    func `the section 9.5 example round-trips`() throws {
        let part = try Self.decode(Self.example)
        #expect(part.name == "Into last chorus")
        #expect(part.span.spanBass == ["E", "A"])
        #expect(part.span.start.chord == 3)
        #expect(part.origin == PartOrigin(
            family: .pickup,
            template: "pickup8",
            rank: .b,
            edited: true,
        ))
        #expect(part.events.count == 4)
        #expect(part.events[1].string == "A1")
        #expect(part.events[2].articulations == [.slide])
        #expect(part.events[3].velocity == 110)
        let again = try JSONDecoder().decode(Part.self, from: JSONEncoder().encode(part))
        #expect(again == part)
    }

    @Test(arguments: [
        ("\"last\"", PassFilter.last),
        ("[3]", .only([3])),
        ("[1, 3]", .only([1, 3])),
    ])
    func `shows on round-trips`(json: String, filter: PassFilter) throws {
        let part = try Self.decode(Self.example.replacingOccurrences(of: "\"all\"", with: json))
        #expect(part.passes == filter)
        #expect(try JSONDecoder().decode(Part.self, from: JSONEncoder().encode(part))
            .passes == filter)
    }

    @Test(arguments: [
        #"{"chord": 0, "at": 0, "len": 240, "deg": 12}"#,
        #"{"chord": 0, "at": 0, "len": 240, "deg": 0, "oct": 3}"#,
        #"{"chord": 0, "at": 0, "len": 0, "deg": 0}"#,
        #"{"chord": 0, "at": -1, "len": 240, "deg": 0}"#,
        #"{"chord": 2, "at": 0, "len": 240, "deg": 0}"#,
        #"{"chord": 0, "at": 0, "len": 240, "deg": 0, "art": ["bend"]}"#,
        #"{"chord": 0, "at": 0, "len": 240, "deg": 0, "string": "low"}"#,
    ])
    func `a bad event is dropped and the part survives`(event: String) throws {
        let json = Self.example.replacingOccurrences(
            of: #"{"chord": 0, "at": 960,  "len": 240, "deg": 0,  "oct": 0},"#,
            with: event + ",",
        )
        #expect(try Self.decode(json).events.count == 3)
    }

    @Test(arguments: [
        ("\"bass\"", "\"cello\""),
        ("\"span\": [\"E\", \"A\"]", "\"span\": [\"E\"]"),
        (
            "\"span\": [\"E\", \"A\"]",
            "\"span\": [\"E\", \"A\", \"B\", \"C\", \"D\", \"E\", \"F\", \"G\", \"A\", \"B\"]",
        ),
        ("\"from\": \"E\"", "\"from\": \"Hm\""),
    ])
    func `a part with a bad instrument, span or anchor is dropped`(from: String, to: String) {
        #expect(throws: (any Error).self) {
            try Self.decode(Self.example.replacingOccurrences(of: from, with: to))
        }
    }

    @Test
    func `a part with no valid event is dropped`() {
        let json = Self.example.replacingOccurrences(of: "\"deg\": ", with: "\"deg\": 40 + ")
        #expect(throws: (any Error).self) { try Self.decode(json) }
    }

    @Test
    func `a v5 sidecar migrates to 6 with empty parts and keeps its bass`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let song = try await store.createSong(source: "{title: Old}\n[G]Hello [C]there\n")
        let old = """
        {"id": "\(song.id)", "schemaVersion": 5, "tags": ["gig"],
         "bass": {"genre": "rock", "walkUps": []},
         "createdAt": "2026-01-01T00:00:00Z", "updatedAt": "2026-01-01T00:00:00Z"}
        """
        try lib.write(old, to: "songs/old.segue.json")
        try await store.refresh()
        let record = try #require(try await store.song(id: song.id))
        #expect(record.readOnly == nil)
        #expect(record.sidecar.parts.isEmpty)
        #expect(record.sidecar.bass.genre == .rock)
        // Opening never rewrites it; the next save writes schema 6 with `parts`.
        #expect(try lib.read("songs/old.segue.json") == old)
        let part = try Self.decode(Self.example)
        _ = try await store.updateParts(id: song.id, [part])
        let written = try lib.read("songs/old.segue.json")
        #expect(written.contains("\"schemaVersion\" : 6"))
        #expect(written.contains("\"parts\""))
        #expect(written.contains("\"genre\" : \"rock\""))
        let reopened = try #require(try await lib.openStore().song(id: song.id))
        #expect(reopened.sidecar.parts == [part])
    }

    @Test
    func `parts decode one by one in a sidecar`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let song = try await store.createSong(source: "{title: Mixed}\n[G]Hello\n")
        let mixed = Self.example.replacingOccurrences(of: "\"bass\"", with: "\"tuba\"")
        try lib.write(
            """
            {"id": "\(song.id)", "schemaVersion": 6, "parts": [\(Self.example), \(mixed), 7]}
            """,
            to: "songs/mixed.segue.json",
        )
        try await store.refresh()
        let record = try #require(try await store.song(id: song.id))
        #expect(record.readOnly == nil)
        #expect(record.sidecar.parts.count == 1)
    }

    @Test
    func `a v7 sidecar opens read-only and is never rewritten`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let song = try await store.createSong(source: "{title: New}\n[G]Hello\n")
        let newer = """
        {"id": "\(song.id)", "schemaVersion": 7, "parts": [\(Self.example)]}
        """
        try lib.write(newer, to: "songs/new.segue.json")
        try await store.refresh()
        let record = try #require(try await store.song(id: song.id))
        #expect(record.readOnly != nil)
        #expect(record.sidecar.parts.count == 1)
        await #expect(throws: (any Error).self) {
            try await store.updateParts(id: song.id, [])
        }
        #expect(try lib.read("songs/new.segue.json") == newer)
    }

    @Test
    func `updateParts writes the sidecar only`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let song = try await store.createSong(source: "{title: Only}\n{key: G}\n[G]Hello\n")
        let cho = try lib.read("songs/only.cho")
        let path = lib.url("songs/only.cho").path
        let choDate = try FileManager.default
            .attributesOfItem(atPath: path)[.modificationDate] as? Date
        let part = try Self.decode(Self.example)
        let saved = try await store.updateParts(id: song.id, [part])
        #expect(saved.sidecar.parts == [part])
        #expect(saved.document == song.document)
        #expect(try lib.read("songs/only.cho") == cho)
        let after = try FileManager.default
            .attributesOfItem(atPath: path)[.modificationDate] as? Date
        #expect(after == choDate)
        let summary = try #require(try await store.song(id: song.id))
        #expect(summary.document.metadata.title == "Only")
        #expect(summary.document.metadata.key == "G")
    }
}
