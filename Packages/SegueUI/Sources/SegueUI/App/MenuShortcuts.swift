#if os(macOS)
    import SwiftUI

    /// One menu item's key equivalent. The menus and Help > Keyboard Shortcuts both read
    /// `MenuShortcuts`, so the help can never drift from the menus (WS2a 3.5).
    public struct MenuShortcut: Hashable, Sendable, Identifiable {
        /// The menu it is in ("File", "Setlist", ...), for grouping in the help.
        public let menu: String
        /// The item's exact title.
        public let title: String
        public let key: KeyEquivalent
        public let modifiers: EventModifiers
        /// Provided by the system (Edit > Undo, Settings…): listed in the help, not declared
        /// by Segue's commands.
        public let isSystem: Bool

        init(
            _ menu: String,
            _ title: String,
            _ key: KeyEquivalent,
            _ modifiers: EventModifiers = .command,
            system: Bool = false,
        ) {
            self.menu = menu
            self.title = title
            self.key = key
            self.modifiers = modifiers
            isSystem = system
        }

        public var id: String {
            "\(menu).\(title)"
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        /// For `.keyboardShortcut(_:)`.
        public var shortcut: KeyboardShortcut {
            KeyboardShortcut(key, modifiers: modifiers)
        }

        /// What it looks like in a menu: "⇧⌘I", "⌘↩", "⌥⌘R".
        public var displayText: String {
            var text = ""
            if modifiers.contains(.control) {
                text += "⌃"
            }
            if modifiers.contains(.option) {
                text += "⌥"
            }
            if modifiers.contains(.shift) {
                text += "⇧"
            }
            if modifiers.contains(.command) {
                text += "⌘"
            }
            return text + Self.keyName(key)
        }

        /// The key as the menus draw it.
        static func keyName(_ key: KeyEquivalent) -> String {
            switch key {
            case .return: "↩"
            case .delete: "⌫"
            case .escape: "⎋"
            case .tab: "⇥"
            case .space: "Space"
            case .upArrow: "↑"
            case .downArrow: "↓"
            case .leftArrow: "←"
            case .rightArrow: "→"
            default: String(key.character).uppercased()
            }
        }

        /// Key and modifiers, for finding clashes.
        var chord: String {
            "\(modifiers.rawValue):\(String(key.character).lowercased())"
        }
    }

    /// Every key equivalent in Segue's menus, in menu order.
    public enum MenuShortcuts {
        /// App
        static let settings = MenuShortcut("Segue", "Settings…", ",", system: true)
        /// File
        static let newSong = MenuShortcut("File", "New Song", "n")
        /// R75: ⌥⌘V (free: no menu uses it, and Segue has no Format menu for Paste Style).
        static let newSongFromClipboard = MenuShortcut(
            "File",
            "New Song from Clipboard",
            "v",
            [.command, .option],
        )
        static let importSongs = MenuShortcut("File", "Import Songs…", "i", [.command, .shift])
        static let showInFinder = MenuShortcut("File", "Show in Finder", "r", [.command, .option])
        static let moveToTrash = MenuShortcut("File", "Move to Trash", .delete)
        static let close = MenuShortcut("File", "Close", "w")
        static let save = MenuShortcut("File", "Save", "s")
        /// P9-1 (R178): both open the in-app PDF preview; ⌘P inside it prints.
        static let exportPDF = MenuShortcut("File", "Export PDF\u{2026}", "e", [.command, .shift])
        static let print = MenuShortcut("File", "Print\u{2026}", "p")
        // Edit (system)
        static let undo = MenuShortcut("Edit", "Undo", "z", system: true)
        static let redo = MenuShortcut("Edit", "Redo", "z", [.command, .shift], system: true)
        // Library
        static let refresh = MenuShortcut("Library", "Refresh", "r")
        /// R150, R158 Q5: one song on stage, never logged. ⌥⌘↩ is also Setlist > Rehearse,
        /// which needs a shown setlist, so the two are never enabled together (the one
        /// documented exception to the clash test, `sharedChords`).
        static let rehearseSong = MenuShortcut(
            "Library",
            "Rehearse Song",
            .return,
            [.command, .option],
        )
        static let playSongLive = MenuShortcut(
            "Library",
            "Play Song Live",
            .return,
            [.command, .shift],
        )
        /// P8-6 10.3: opens or closes the editor's or library's Play along bar.
        static let playAlong = MenuShortcut("Song", "Play Along", "p", [.command, .shift])
        /// P8-7 12.1: opens the fill editor on the selected chord span.
        static let createBassFill = MenuShortcut(
            "Song",
            "Create Bass Fill\u{2026}",
            "f",
            [.command, .option],
        )
        /// P9-2 section 7: the library and editor previews show lyrics only.
        static let singerPreview = MenuShortcut("Song", "Singer Preview", "y", [.command, .shift])
        // Setlist
        static let startShow = MenuShortcut("Setlist", "Start Show", .return)
        static let rehearse = MenuShortcut("Setlist", "Rehearse", .return, [.command, .option])
        static let newSetlist = MenuShortcut("Setlist", "New Setlist…", "n", [.command, .shift])
        static let pickSongs = MenuShortcut("Setlist", "Pick Songs", "1")
        static let arrangeSet = MenuShortcut("Setlist", "Arrange Set", "2")
        static let insertBreak = MenuShortcut("Setlist", "Insert Break", "b", [.command, .shift])
        /// P8-5: focuses the set composer at the end of the set list.
        static let addSongByName = MenuShortcut("Setlist", "Add Song by Name", "l")
        /// P3-16: the selected slot's Arrange Sections sheet.
        static let arrangeSections = MenuShortcut(
            "Setlist",
            "Arrange Sections…",
            "a",
            [.command, .shift],
        )
        /// P9-3 6.3: joins Arrange's selected song rows into one medley slot.
        static let makeMedley = MenuShortcut("Setlist", "Make Medley", "m", [.command, .shift])
        /// P9-3 6.3: the selected medley's members become slots in place.
        static let ungroupMedley = MenuShortcut(
            "Setlist",
            "Ungroup Medley",
            "m",
            [.command, .option, .shift],
        )
        static let moveUp = MenuShortcut("Setlist", "Move Up", .upArrow, .option)
        static let moveDown = MenuShortcut("Setlist", "Move Down", .downArrow, .option)
        // Window
        static let mainWindow = MenuShortcut("Window", "Segue Library", "0")
        // Help
        static let help = MenuShortcut("Help", "Segue Help", "?")
        static let keyboardShortcuts = MenuShortcut("Help", "Keyboard Shortcuts", "/")

        /// Items that share a chord and are never enabled together.
        static let sharedChords: [(MenuShortcut, MenuShortcut)] = [
            (rehearseSong, rehearse),
        ]

        /// All of them, in menu order.
        public static let all: [MenuShortcut] = [
            settings, newSong, newSongFromClipboard, importSongs, showInFinder, moveToTrash, close,
            save, exportPDF, print, undo, redo,
            refresh, rehearseSong, playSongLive, playAlong, createBassFill, singerPreview,
            startShow, rehearse, newSetlist, pickSongs, arrangeSet, insertBreak,
            addSongByName,
            arrangeSections, makeMedley, ungroupMedley, moveUp, moveDown, mainWindow, help,
            keyboardShortcuts,
        ]
    }

    extension View {
        /// The key equivalent from `MenuShortcuts`.
        func keyboardShortcut(_ shortcut: MenuShortcut) -> some View {
            keyboardShortcut(shortcut.shortcut)
        }
    }
#endif
