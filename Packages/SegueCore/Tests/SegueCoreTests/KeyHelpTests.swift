import Foundation
import Shows
import Support
import Testing

/// The stage key help (WS2a 3.7) and the page-turner bindings (R45), from the binding table.
struct KeyHelpTests {
    @Test
    func `the default help lists every command exactly once`() {
        let laid = KeyHelp.layout.flatMap(\.commands)
        #expect(laid.sorted { $0.rawValue < $1.rawValue }
            == LiveCommand.allCases.sorted { $0.rawValue < $1.rawValue })
        let rows = KeyHelp.groups(.defaults).flatMap(\.rows)
        // The nine jumps on their default digits are one row.
        #expect(rows.count == LiveCommand.allCases.count - 8)
        let byCommand = Dictionary(uniqueKeysWithValues: rows.map { ($0.command, $0.keys) })
        #expect(byCommand[.showKeys] == ["?"])
        #expect(byCommand[.next] == ["→", "Space"])
        #expect(byCommand[.pageForward] == ["Page Down"])
        #expect(byCommand[.scrollPageDown] == ["↓"])
        #expect(byCommand[.openSearch] == ["⌘K", "/"])
        #expect(byCommand[.endShow] == ["⌘."])
        // Titles say what a command does, never a key name a keycap beside it repeats.
        #expect(Set(rows.map(\.title)).count == rows.count)
        #expect(LiveCommand.pageForward.title == "Page, Then Next Song")
        #expect(LiveCommand.scrollPageDown.title == "Scroll Down a Page")
    }

    @Test
    func `the sections group shows the jumps as 1-9 and the loop, after scrolling`() throws {
        let groups = KeyHelp.groups(.defaults)
        let titles = groups.map(\.title)
        let sections = try #require(groups.first { $0.title == "Sections" })
        #expect(titles.firstIndex(of: "Sections") == titles.firstIndex(of: "Scrolling")
            .map { $0 + 1 })
        #expect(sections.rows.map(\.title) == [
            "Jump to Section", "Loop Section (Rehearsal)", "Play Along (Rehearsal)",
        ])
        #expect(sections.rows.map(\.keys) == [["1-9"], ["L"], ["P"]])
        #expect(LiveCommand.togglePlayAlong.scope == .viewport)
        #expect(!LiveCommand.togglePlayAlong.repeatsWhenHeld)
        #expect(!groups.flatMap(\.rows).contains { $0.title == "Collapse Repeats" })
        #expect(LiveCommand.jumpToPass4.title == "Jump to Section 4")
        #expect(LiveCommand.jumpToPass4.jumpIndex == 3)
        #expect(LiveCommand.jumps.allSatisfy { $0.scope == .viewport && !$0.repeatsWhenHeld })
        #expect(LiveCommand.toggleLoop.scope == .viewport)
        #expect(!LiveCommand.toggleLoop.repeatsWhenHeld)
        #expect(InputBindingTable.defaults.command(for: .key(KeyStroke("o"))) == nil)

        // Rebound digits show one row each.
        let rebound = InputBindingTable.defaults.merged(with: [
            InputBinding(.key(KeyStroke("3")), .next),
        ])
        let rows = try #require(KeyHelp.groups(rebound).first { $0.title == "Sections" }).rows
        #expect(rows.count == 11)
        #expect(rows[2].keys.isEmpty)
        #expect(!KeyHelp.statusHints(rebound).contains("1-9 sections"))
    }

    @Test
    func `the status line hints keep their old wording and add the help key`() {
        #expect(KeyHelp.statusHints(.defaults) == [
            "← → songs", "A scroll", "1-9 sections", "C columns", "⌘K search", "S set order",
            "Q requests", "⌘. end", "? keys",
        ])
        // A rehearsal names its loop and play-along keys.
        #expect(KeyHelp.statusHints(.defaults, kind: .rehearsal).prefix(5) == [
            "← → songs", "A scroll", "1-9 sections", "L loop", "P play along",
        ])
        // A song with a saved fill names `T` (P8-7 14.2), in a gig and a rehearsal.
        #expect(KeyHelp.statusHints(.defaults, hasFills: true).prefix(4) == [
            "← → songs", "A scroll", "1-9 sections", "T fills as tab",
        ])
        #expect(KeyHelp.statusHints(.defaults, kind: .rehearsal, hasFills: true)[5]
            == "T fills as tab")
    }

    @Test
    func `t flips fills to tab in the bass group, display only`() throws {
        let bass = try #require(KeyHelp.groups(.defaults).first { $0.title == "Bass" })
        #expect(bass.rows.map(\.title) == ["Bass Notes", "Fills as Tab"])
        #expect(bass.rows.map(\.keys) == [["B"], ["T"]])
        #expect(InputBindingTable.defaults.command(for: .key(KeyStroke("t"))) == .toggleFillTab)
        #expect(LiveCommand.toggleFillTab.scope == .viewport)
        #expect(!LiveCommand.toggleFillTab.repeatsWhenHeld)
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
