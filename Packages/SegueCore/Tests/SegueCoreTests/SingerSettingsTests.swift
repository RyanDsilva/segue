import Foundation
import Shows
import Support
import Testing

/// Singer view's settings, key and help (P9-2 sections 6.1, 6.5 and 11).
struct SingerSettingsTests {
    @Test
    func `v toggles singer view in the view group`() throws {
        #expect(InputBindingTable.defaults.command(for: .key(KeyStroke("v"))) == .toggleSingerView)
        #expect(LiveCommand.toggleSingerView.title == "Singer View")
        #expect(LiveCommand.toggleSingerView.scope == LiveCommand.toggleBassNotes.scope)
        #expect(!LiveCommand.toggleSingerView.repeatsWhenHeld)
        let view = try #require(KeyHelp.groups(.defaults).first { $0.title == "View" })
        let row = try #require(view.rows.first { $0.command == .toggleSingerView })
        #expect(row.keys == ["V"])
    }

    @Test
    func `a settings file from before singer view keeps every setting`() throws {
        let json = """
        {"minLyricSize": 26, "startShortcut": "Gig Mode On", "endShortcut": "Gig Mode Off",
         "hiddenChecklistItems": ["brightness", "focus"], "defaultColumns": 2}
        """
        let settings = try SegueJSON.decode(LiveSettings.self, from: Data(json.utf8))
        #expect(settings.minLyricSize == 26)
        #expect(settings.startShortcut == "Gig Mode On")
        #expect(settings.endShortcut == "Gig Mode Off")
        #expect(settings.hiddenChecklistItems == [.brightness, .focus])
        #expect(settings.defaultColumns == 2)
        #expect(!settings.singerView)
        #expect(settings.singerZoom == 1)
        #expect(settings.singerScreenDisplay == nil)
    }

    @Test
    func `unknown rows and odd values never reset the rest`() throws {
        let json = """
        {"minLyricSize": 30, "hiddenChecklistItems": ["charger", "somethingNew"],
         "singerView": true, "singerZoom": 9, "defaultColumns": "two"}
        """
        let settings = try SegueJSON.decode(LiveSettings.self, from: Data(json.utf8))
        #expect(settings.minLyricSize == 30)
        #expect(settings.hiddenChecklistItems == [.charger])
        #expect(settings.singerView)
        #expect(settings.singerZoom == LiveSettings.singerZoomRange.upperBound)
        #expect(settings.defaultColumns == nil)
    }

    @Test
    func `the singer checklist row is written where an older Segue never reads it`() throws {
        var settings = LiveSettings(hiddenChecklistItems: [.charger, .singerView])
        settings.singerView = true
        settings.singerZoom = 1.21
        settings.singerScreenDisplay = "LG UltraFine"
        let data = try SegueJSON.encode(settings)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        // The old key holds only rows every build knows, so a strict older decode succeeds.
        #expect(object["hiddenChecklistItems"] as? [String] == ["charger"])
        #expect(object["hiddenChecklistRows"] as? [String] == ["charger", "singerView"])
        #expect(try SegueJSON.decode(LiveSettings.self, from: data) == settings)

        struct OlderSettings: Decodable {
            enum Row: String, Decodable { case focus, charger, brightness }
            var minLyricSize: Double
            var hiddenChecklistItems: Set<Row>
        }
        let older = try SegueJSON.decode(OlderSettings.self, from: data)
        #expect(older.hiddenChecklistItems == [.charger])
    }

    @Test
    func `bindings files are version 2 and still read version 1`() throws {
        #expect(InputBindingTable.currentSchemaVersion == 2)
        let lib = try TestLibrary()
        let url = lib.url("bindings.json")
        try lib.write("""
        {"schemaVersion": 1, "bindings": [{"trigger": {"key": "z"}, "command": "toggleBassNotes"}]}
        """, to: "bindings.json")
        let loaded = try InputBindingTable.loadReporting(from: url, fileSystem: LiveFileSystem())
        #expect(loaded.newerSchema == nil)
        #expect(loaded.table.command(for: .key(KeyStroke("z"))) == .toggleBassNotes)
        try lib.write("""
        {"schemaVersion": 2, "bindings": [{"trigger": {"key": "z"}, "command": "toggleSingerView"}]}
        """, to: "bindings.json")
        let current = try InputBindingTable.loadReporting(from: url, fileSystem: LiveFileSystem())
        #expect(current.table.command(for: .key(KeyStroke("z"))) == .toggleSingerView)
    }
}
