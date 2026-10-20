import Foundation
@testable import SegueUI
import Shows
import Testing

/// The user guide's keyboard reference (WS6 4.6) is generated from the same tables as the
/// menus, the `?` overlay and Help > Keyboard Shortcuts, so the guide cannot drift from the
/// app. `make guide-keys` (SEGUE_WRITE_GUIDE_DATA=1) writes `guide/src/data/keyboard.json`;
/// otherwise this test fails when the committed file is stale.
@MainActor
struct GuideKeyboardExportTests {
    @Test
    func `the guide's keyboard reference matches the app's key tables`() throws {
        let rendered = try Self.render()
        if ProcessInfo.processInfo.environment["SEGUE_WRITE_GUIDE_DATA"] == "1" {
            try rendered.write(to: Self.output, atomically: true, encoding: .utf8)
        }
        let committed = try String(contentsOf: Self.output, encoding: .utf8)
        #expect(committed == rendered, "guide/src/data/keyboard.json is stale: run make guide-keys")
    }

    /// `{"editor": [{title, keys}], "menus": [{menu, items: [{title, keys}]}],
    /// "stage": [{group, rows: [{title, keys}]}]}`,
    /// pretty-printed with sorted keys so the output is byte-stable.
    static func render() throws -> String {
        struct Item: Encodable {
            var title: String
            var keys: [String]
        }
        struct Menu: Encodable {
            var menu: String
            var items: [Item]
        }
        struct Group: Encodable {
            var group: String
            var rows: [Item]
        }
        struct Reference: Encodable {
            var editor: [Item]
            var menus: [Menu]
            var stage: [Group]
        }
        var menus: [Menu] = []
        for shortcut in MenuShortcuts.all {
            let item = Item(title: shortcut.title, keys: [shortcut.displayText])
            if let last = menus.indices.last, menus[last].menu == shortcut.menu {
                menus[last].items.append(item)
            } else {
                menus.append(Menu(menu: shortcut.menu, items: [item]))
            }
        }
        let stage = KeyHelp.groups(.defaults).map { group in
            Group(group: group.title, rows: group.rows.map { Item(title: $0.title, keys: $0.keys) })
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let editor = EditorKeys.rows.map { Item(title: $0.title, keys: [$0.keys]) }
        let data = try encoder.encode(Reference(editor: editor, menus: menus, stage: stage))
        return try #require(String(bytes: data, encoding: .utf8)) + "\n"
    }

    /// `<repo>/guide/src/data/keyboard.json`.
    static var output: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "guide/src/data/keyboard.json")
    }
}
