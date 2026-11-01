import AppKit
import Foundation
@testable import SegueUI
import SwiftUI
import Testing

/// The menus' key table (WS2a 3.5) and the About panel (3.6).
@MainActor
struct MenuShortcutsTests {
    @Test
    func `no two menu items share a key equivalent`() {
        // The one documented exception (R158 Q5): Library > Rehearse Song shares ⌥⌘↩ with
        // Setlist > Rehearse; they are never enabled together (`SingleSongSessionTests`).
        let shared = Set(MenuShortcuts.sharedChords.map(\.0.id))
        #expect(MenuShortcuts.sharedChords.allSatisfy { $0.0.chord == $0.1.chord })
        let chords = MenuShortcuts.all.filter { !shared.contains($0.id) }.map(\.chord)
        #expect(Set(chords).count == chords.count, "\(MenuShortcuts.all.map(\.displayText))")
        #expect(MenuShortcuts.playSongLive.displayText == "⇧⌘↩")
    }

    @Test
    func `the setlist and help items have their specified keys`() {
        let byTitle = Dictionary(uniqueKeysWithValues: MenuShortcuts.all.map { ($0.title, $0) })
        #expect(byTitle["Start Show"]?.displayText == "⌘↩")
        #expect(byTitle["Rehearse"]?.displayText == "⌥⌘↩")
        #expect(byTitle["New Setlist…"]?.displayText == "⇧⌘N")
        #expect(byTitle["Segue Help"]?.displayText == "⌘?")
        #expect(byTitle["Keyboard Shortcuts"]?.displayText == "⌘/")
        #expect(byTitle["Segue Library"]?.displayText == "⌘0")
        #expect(byTitle["Import Songs…"]?.displayText == "⇧⌘I")
        // R75: ⌥⌘V, free of every other menu item (the clash test above).
        #expect(byTitle["New Song from Clipboard"]?.displayText == "⌥⌘V")
        #expect(byTitle["Show in Finder"]?.displayText == "⌥⌘R")
        #expect(byTitle["Move to Trash"]?.displayText == "⌘⌫")
        // Set building (R84, R85).
        #expect(byTitle["Pick Songs"]?.displayText == "⌘1")
        #expect(byTitle["Arrange Set"]?.displayText == "⌘2")
        #expect(byTitle["Insert Break"]?.displayText == "⇧⌘B")
        #expect(byTitle["Move Up"]?.displayText == "⌥↑")
        #expect(byTitle["Move Down"]?.displayText == "⌥↓")
    }

    @Test
    func `every shortcut Segue declares is used by a command`() throws {
        let folder = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let commands = folder.appending(path: "Sources/SegueUI/App/Commands")
        let files = try FileManager.default.contentsOfDirectory(
            at: commands,
            includingPropertiesForKeys: nil,
        )
        let source = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined()
        let names = [
            "newSong", "newSongFromClipboard", "importSongs", "showInFinder", "moveToTrash",
            "close",
            "save", "exportPDF", "print",
            "refresh", "rehearseSong", "playSongLive", "playAlong", "createBassFill",
            "singerPreview",
            "startShow", "rehearse", "newSetlist", "pickSongs", "arrangeSet", "insertBreak",
            "addSongByName",
            "arrangeSections", "makeMedley", "ungroupMedley",
            "moveUp", "moveDown", "mainWindow", "help", "keyboardShortcuts",
        ]
        for name in names {
            #expect(source.contains("MenuShortcuts.\(name)"), "MenuShortcuts.\(name) is unused")
        }
        #expect(MenuShortcuts.all.count(where: { !$0.isSystem }) == names.count)
    }
}

@MainActor
struct AboutPanelTests {
    @Test
    func `version and copyright come from Info.plist`() throws {
        let bundle = try Self.bundle(info: [
            "CFBundleShortVersionString": "0.5",
            "CFBundleVersion": "12",
            "NSHumanReadableCopyright": "© 2026 Ryan Rony Dsilva",
        ])
        #expect(AboutPanel.versionText(bundle: bundle) == "Version 0.5 (12)")
        #expect(AboutPanel.copyright(bundle: bundle) == "© 2026 Ryan Rony Dsilva")
    }

    @Test
    func `the app's Info.plist carries the R30 copyright`() throws {
        let project = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Project.swift")
        let manifest = try String(contentsOf: project, encoding: .utf8)
        #expect(manifest.contains(#""NSHumanReadableCopyright": "© 2026 Ryan Rony Dsilva""#))
    }

    @Test
    func `credits link the site pages and name no third-party software`() {
        let credits = AboutPanel.credits()
        let whole = NSRange(location: 0, length: credits.length)
        var links: [URL] = []
        credits.enumerateAttribute(.link, in: whole) { value, _, _ in
            if let url = value as? URL {
                links.append(url)
            }
        }
        #expect(links == [SegueLinks.site, SegueLinks.help, SegueLinks.support, SegueLinks.privacy])
        // R103: one row, exactly these four labels, no other credits text.
        #expect(credits.string == "Website · Help · Support · Privacy\u{00A0}Policy")
        var labels: [String] = []
        credits.enumerateAttribute(.link, in: whole) { value, range, _ in
            if value != nil {
                labels.append((credits.string as NSString).substring(with: range))
            }
        }
        #expect(labels == ["Website", "Help", "Support", "Privacy\u{00A0}Policy"])
        for name in ["Schibsted", "GRDB", "Tonic", "Sentry", "open-source", "Acknowledgements"] {
            #expect(!credits.string.contains(name), "About credits mention \(name)")
        }
    }

    /// The notices are not shown in the app, but MIT and the OFL require them to accompany
    /// the binary: the licence texts ship in the SegueUI resource bundle.
    @Test(arguments: [
        ("Licenses", "GRDB"),
        ("Licenses", "Tonic"),
        ("Licenses", "Sentry"),
        ("Fonts", "OFL")
    ])
    func `every bundled licence text loads`(folder: String, name: String) {
        let url = Theme.bundle.url(forResource: name, withExtension: "txt", subdirectory: folder)
            ?? Theme.bundle.url(forResource: name, withExtension: "txt")
        let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        #expect(text.count > 200, "\(name) licence missing")
    }

    private static func bundle(info: [String: String]) throws -> Bundle {
        let folder = FileManager.default.temporaryDirectory
            .appending(
                path: "AboutPanelTests-\(UUID().uuidString).bundle",
                directoryHint: .isDirectory,
            )
        let contents = folder.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0,
        )
        try data.write(to: contents.appending(path: "Info.plist"))
        return try #require(Bundle(url: folder))
    }
}
