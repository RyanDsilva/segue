import Editing
import Foundation
import Library
import Setlists
import Shows
import Support
import Testing

/// The phase 2 model pieces implemented with the interface freeze (docs/phases/
/// 2-interfaces.md): setlist schema v2, overrides, sidecar v3, bindings, calendar days.
struct Phase2ModelTests {
    @Test
    func `v1 setlist gains stable derived item IDs on migration`() async throws {
        let lib = try TestLibrary()
        let id = SetlistID(lib.ids.next())
        let song = SongID(lib.ids.next())
        let v1 = """
        {"schemaVersion": 1, "id": "\(id)", "name": "Twice",
         "entries": [{"songId": "\(song)"}, {"songId": "\(song)"}]}
        """
        try lib.write(v1, to: "setlists/twice.setlist.json")

        let (store, issues) = try await lib.loadSetlists()
        let setlist = try #require(await store.setlist(id: id))
        #expect(issues.isEmpty)
        #expect(setlist.entries.map(\.itemId) == [
            SetlistItemID.migrated(setlist: id, position: 0),
            SetlistItemID.migrated(setlist: id, position: 1),
        ])
        #expect(Set(setlist.entries.map(\.itemId)).count == 2)
        #expect(try lib.read("setlists/twice.setlist.json") == v1)

        // Reloading derives the same IDs; saving writes them.
        let (again, _) = try await lib.loadSetlists()
        #expect(await again.setlist(id: id)?.entries == setlist.entries)
        try await again.addSong(SongID(lib.ids.next()), to: id)
        let saved = try lib.read("setlists/twice.setlist.json")
        #expect(saved.contains("\"itemId\" : \"\(setlist.entries[0].itemId)\""))
        #expect(saved.contains("\"schemaVersion\" : \(Setlist.currentSchemaVersion)"))
    }

    /// One overrides case: inputs and the expected render transpose/capo.
    struct OverrideCase: Sendable, CustomTestStringConvertible {
        var songCapo: Int?
        var transpose: Int?
        var capo: Int?
        var viewTranspose: Int
        var expectedTranspose: Int
        var expectedCapo: Int?

        var testDescription: String {
            "capo \(songCapo ?? 0) override t=\(transpose ?? 0) c=\(capo ?? -1)"
        }
    }

    @Test(arguments: [
        OverrideCase(viewTranspose: 2, expectedTranspose: 2),
        OverrideCase(songCapo: 2, viewTranspose: 0, expectedTranspose: 0, expectedCapo: 2),
        OverrideCase(
            songCapo: 2,
            transpose: 3,
            viewTranspose: 1,
            expectedTranspose: 3,
            expectedCapo: 2,
        ),
        OverrideCase(
            songCapo: 2,
            capo: 4,
            viewTranspose: 0,
            expectedTranspose: -2,
            expectedCapo: 4,
        ),
        OverrideCase(songCapo: 2, capo: 0, viewTranspose: 0, expectedTranspose: 2),
        OverrideCase(
            transpose: -1,
            capo: 3,
            viewTranspose: 5,
            expectedTranspose: -4,
            expectedCapo: 3,
        ),
    ])
    func `overrides keep the concert key`(_ example: OverrideCase) {
        let overrides = SetlistOverrides(transpose: example.transpose, capo: example.capo)
        let (options, renderCapo) = overrides.applied(
            to: DisplayOptions(transpose: example.viewTranspose),
            songCapo: example.songCapo,
        )
        #expect(options.transpose == example.expectedTranspose)
        #expect(renderCapo == example.expectedCapo)
        // Concert = written + capo + transpose is unchanged by the capo override.
        let concert = options.transpose + (renderCapo ?? 0)
        #expect(concert == (example.transpose ?? example.viewTranspose) + (example.songCapo ?? 0))
    }

    @Test
    func `v2 sidecar gains cues and live prefs with defaults`() async throws {
        let lib = try TestLibrary()
        let id = SongID(lib.ids.next())
        let v2 = """
        {"schemaVersion": 2, "id": "\(id)", "tags": ["slow"], "displayPrefs": {},
         "createdAt": "2025-06-01T10:00:00.000Z", "updatedAt": "2025-06-01T10:00:00.000Z"}
        """
        try lib.write("{title: Cue Me}\n[G]La\n", to: "songs/cue-me.cho")
        try lib.write(v2, to: "songs/cue-me.segue.json")

        let store = try await lib.openStore()
        let record = try #require(try await store.song(id: id))
        #expect(record.readOnly == nil)
        #expect(record.sidecar.cues.isEmpty)
        #expect(record.sidecar.live == LivePrefs())
        #expect(record.sidecar.live.collapseRepeats)
    }

    @Test
    func `live prefs and cues decode field by field`() throws {
        let json = """
        {"zoom": 1.2, "columns": "two", "collapseRepeats": false}
        """
        let prefs = try SegueJSON.decode(LivePrefs.self, from: Data(json.utf8))
        #expect(prefs == LivePrefs(zoom: 1.2, collapseRepeats: false))
    }

    @Test
    func `only continuous scroll and zoom repeat when a key is held`() {
        let repeating: Set<LiveCommand> = [
            .scrollPageDown, .scrollPageUp, .scrollFaster, .scrollSlower, .zoomIn, .zoomOut,
        ]
        for command in LiveCommand.allCases {
            #expect(command.repeatsWhenHeld == repeating.contains(command), "\(command)")
        }
    }

    @Test
    func `default bindings cover every command and round-trip through json`() throws {
        let table = InputBindingTable.defaults
        for command in LiveCommand.allCases {
            #expect(!table.triggers(for: command).isEmpty, "\(command) has no default key")
        }
        #expect(table.command(for: .key(KeyStroke("K", modifiers: .command))) == .openSearch)
        #expect(table.command(for: .key(KeyStroke(KeyStroke.space))) == .next)

        let lib = try TestLibrary()
        let file = """
        {"schemaVersion": 1, "bindings": [
          {"trigger": {"key": "pageDown"}, "command": "next"},
          {"trigger": {"key": "n", "modifiers": ["command", "shift"]}, "command": "endShow"}
        ]}
        """
        try lib.write(file, to: "bindings.json")
        let loaded = try InputBindingTable.load(
            from: lib.url("bindings.json"),
            fileSystem: LiveFileSystem(),
        )
        #expect(loaded.command(for: .key(KeyStroke(KeyStroke.pageDown))) == .next)
        #expect(loaded.command(for: .key(KeyStroke(KeyStroke.downArrow))) == .scrollPageDown)
        let stroke = KeyStroke("n", modifiers: [.command, .shift])
        #expect(loaded.command(for: .key(stroke)) == .endShow)

        let encoded = try SegueJSON.encode(InputBinding(.key(stroke), .endShow))
        let decoded = try SegueJSON.decode(InputBinding.self, from: encoded)
        #expect(decoded == InputBinding(.key(stroke), .endShow))
        #expect(String(bytes: encoded, encoding: .utf8)?.contains("\"command\",\n") == true)
    }

    @Test
    func `calendar days parse, validate and encode as dates`() throws {
        #expect(CalendarDay("2026-10-23")?.description == "2026-10-23")
        #expect(CalendarDay("2026-02-30") == nil)
        #expect(CalendarDay("26-10-23") == nil)
        let day = try #require(CalendarDay(year: 2026, month: 10, day: 23))
        let data = try SegueJSON.encode([day])
        #expect(try SegueJSON.decode([CalendarDay].self, from: data) == [day])
        #expect(try #require(CalendarDay("2026-01-31")) < day)
    }

    /// decisions.md, "Columns": the song's choice, else the global default, else auto.
    @Test(arguments: [
        // (song, global default, laid out with)
        (Int?.none, Int?.none, Int?.none),
        (nil, 2, 2),
        (nil, 3, 3),
        (1, nil, 1),
        (1, 3, 1),
        (3, 1, 3),
        (7, nil, 3),
        (nil, 0, 1),
    ])
    func `column precedence is song then global default then auto`(
        song: Int?,
        global: Int?,
        expected: Int?,
    ) {
        let settings = LiveSettings(defaultColumns: global)
        #expect(settings.columns(for: LivePrefs(columns: song)) == expected)
    }

    @Test
    func `stored live settings without a default column count decode as auto`() throws {
        let stored = Data(#"""
        {"minLyricSize": 26, "startShortcut": "Gig Mode On", "hiddenChecklistItems": []}
        """#.utf8)
        let settings = try SegueJSON.decode(LiveSettings.self, from: stored)
        #expect(settings.defaultColumns == nil)
        #expect(settings.minLyricSize == 26)
        let roundTrip = try SegueJSON.decode(
            LiveSettings.self,
            from: SegueJSON.encode(LiveSettings(defaultColumns: 2)),
        )
        #expect(roundTrip.defaultColumns == 2)
    }
}
