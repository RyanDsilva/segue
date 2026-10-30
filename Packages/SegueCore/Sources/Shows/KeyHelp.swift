import Foundation

/// The stage keys as help shows them (WS2a 3.7): built from the live binding table, so a
/// `bindings.json` override shows truthfully in the `?` overlay, Help > Keyboard Shortcuts
/// and the status line. Pure: bindings in, grouped rows out.
public enum KeyHelp {
    /// One command and the keys that trigger it ("Not bound" when `keys` is empty).
    public struct Row: Sendable, Equatable {
        public var command: LiveCommand
        public var title: String
        /// Keycaps: "→", "Page Down", "⌘K", "?".
        public var keys: [String]
    }

    /// A titled group of rows.
    public struct Group: Sendable, Equatable {
        public var title: String
        public var rows: [Row]
    }

    /// The groups, in display order. Every `LiveCommand` appears exactly once.
    public static let layout: [(title: String, commands: [LiveCommand])] = [
        ("Songs", [.next, .previous, .skipCurrent, .playNextRequest]),
        ("Scrolling", [
            .pageForward, .pageBack, .scrollPageDown, .scrollPageUp, .toggleAutoScroll,
            .scrollFaster, .scrollSlower, .restartScroll,
        ]),
        ("Sections", LiveCommand.jumps + [.toggleLoop]),
        ("View", [.zoomIn, .zoomOut, .resetZoom, .cycleColumns]),
        ("Metronome", [.toggleMetronome, .toggleMetronomeClick]),
        ("Panels", [.openSearch, .toggleRequests, .toggleSidebar, .showKeys]),
        ("Show", [.endShow]),
    ]

    /// The help groups for `table`. The nine jump commands on their default digits show as
    /// one row, "Jump to Section" on "1-9"; rebound, they show one row each.
    public static func groups(_ table: InputBindingTable) -> [Group] {
        let digits = hasDefaultDigits(table)
        return layout.map { title, commands in
            Group(title: title, rows: commands.compactMap { command in
                if digits, let index = command.jumpIndex {
                    return index == 0
                        ? Row(command: command, title: "Jump to Section", keys: ["1-9"])
                        : nil
                }
                return Row(
                    command: command,
                    title: command.title,
                    keys: table.triggers(for: command).map(keycap),
                )
            })
        }
    }

    /// Whether keys 1-9 (no modifiers) jump to sections 1-9.
    public static func hasDefaultDigits(_ table: InputBindingTable) -> Bool {
        LiveCommand.jumps.enumerated().allSatisfy { index, command in
            table.command(for: .key(KeyStroke("\(index + 1)"))) == command
        }
    }

    /// The status line's key hints: the first key of each main command, as before the
    /// table existed ("← → songs  ·  A scroll  ·  1-9 sections  ·  ..."), ending with
    /// "? keys"; a rehearsal also names its loop key ("L loop").
    public static func statusHints(_ table: InputBindingTable, kind: ShowKind = .gig) -> [String] {
        func first(_ command: LiveCommand) -> String? {
            table.triggers(for: command).first.map(keycap)
        }
        var hints: [String] = []
        let songs = [first(.previous), first(.next)].compactMap(\.self)
        if !songs.isEmpty {
            hints.append(songs.joined(separator: " ") + " songs")
        }
        let main: [(LiveCommand, String)] = [
            (.toggleAutoScroll, "scroll"), (.cycleColumns, "columns"), (.openSearch, "search"),
            (.toggleSidebar, "set order"), (.toggleRequests, "requests"), (.endShow, "end"),
            (.showKeys, "keys"),
        ]
        for (command, label) in main {
            if let key = first(command) {
                hints.append("\(key) \(label)")
            }
            if command == .toggleAutoScroll {
                if hasDefaultDigits(table) {
                    hints.append("1-9 sections")
                }
                if kind == .rehearsal, let key = first(.toggleLoop) {
                    hints.append("\(key) loop")
                }
            }
        }
        return hints
    }

    /// A trigger as a keycap: modifiers as glyphs, arrows as glyphs, named keys spelled.
    public static func keycap(_ trigger: InputTrigger) -> String {
        switch trigger {
        case let .key(stroke):
            keycap(stroke)
        }
    }

    public static func keycap(_ stroke: KeyStroke) -> String {
        var text = ""
        if stroke.modifiers.contains(.control) {
            text += "⌃"
        }
        if stroke.modifiers.contains(.option) {
            text += "⌥"
        }
        if stroke.modifiers.contains(.shift) {
            text += "⇧"
        }
        if stroke.modifiers.contains(.command) {
            text += "⌘"
        }
        return text + (namedKeys[stroke.key] ?? stroke.key.uppercased())
    }

    private static let namedKeys: [String: String] = [
        KeyStroke.rightArrow: "→", KeyStroke.leftArrow: "←", KeyStroke.upArrow: "↑",
        KeyStroke.downArrow: "↓", KeyStroke.pageUp: "Page Up", KeyStroke.pageDown: "Page Down",
        KeyStroke.home: "Home", KeyStroke.end: "End", KeyStroke.space: "Space",
        KeyStroke.escape: "Esc", KeyStroke.returnKey: "Return",
    ]
}
