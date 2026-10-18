import Foundation
import Shows
import Support
import Testing

/// The stage key help (WS2a 3.7) and the page-turner bindings (R45), from the binding table.
struct KeyHelpTests {
    @Test
    func `the default help lists every command exactly once`() {
        let rows = KeyHelp.groups(.defaults).flatMap(\.rows)
        #expect(rows.map(\.command).sorted { $0.rawValue < $1.rawValue }
            == LiveCommand.allCases.sorted { $0.rawValue < $1.rawValue })
        let byCommand = Dictionary(uniqueKeysWithValues: rows.map { ($0.command, $0.keys) })
        #expect(byCommand[.showKeys] == ["?"])
        #expect(byCommand[.next] == ["→", "Space"])
        #expect(byCommand[.pageForward] == ["Page Down"])
        #expect(byCommand[.scrollPageDown] == ["↓"])
        #expect(byCommand[.openSearch] == ["⌘K", "/"])
        #expect(byCommand[.endShow] == ["⌘."])
    }

    @Test
    func `the status line hints keep their old wording and add the help key`() {
        #expect(KeyHelp.statusHints(.defaults) == [
            "← → songs", "A scroll", "C columns", "⌘K search", "S set order", "Q requests",
            "⌘. end", "? keys",
        ])
    }

    @Test
    func `a bindings file that moves the help key moves the help with it`() throws {
        let lib = try TestLibrary()
        try lib.write("""
        {"schemaVersion": 1, "bindings": [
          {"trigger": {"key": "h"}, "command": "showKeys"},
          {"trigger": {"key": "?"}, "command": "openSearch"},
          {"trigger": {"key": "n"}, "command": "next"}
        ]}
        """, to: "bindings.json")
        let table = try InputBindingTable.load(
            from: lib.url("bindings.json"),
            fileSystem: lib.fileSystem,
        )

        let rows = Dictionary(uniqueKeysWithValues: KeyHelp.groups(table).flatMap(\.rows)
            .map { ($0.command, $0.keys) })
        #expect(rows[.showKeys] == ["H"])
        #expect(rows[.openSearch] == ["⌘K", "/", "?"])
        #expect(rows[.next] == ["→", "Space", "N"])
        #expect(KeyHelp.statusHints(table).last == "H keys")
    }

    @Test
    func `page turner keys cross songs, arrows only page`() {
        let table = InputBindingTable.defaults
        #expect(table.command(for: .key(KeyStroke(KeyStroke.pageDown))) == .pageForward)
        #expect(table.command(for: .key(KeyStroke(KeyStroke.pageUp))) == .pageBack)
        #expect(table.command(for: .key(KeyStroke(KeyStroke.downArrow))) == .scrollPageDown)
        #expect(table.command(for: .key(KeyStroke(KeyStroke.upArrow))) == .scrollPageUp)
        #expect(LiveCommand.pageForward.scope == .viewport)
        #expect(LiveCommand.showKeys.scope == .chrome)
    }
}
