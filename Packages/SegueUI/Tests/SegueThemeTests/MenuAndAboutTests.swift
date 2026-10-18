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
        let chords = MenuShortcuts.all.map(\.chord)
        #expect(Set(chords).count == chords.count, "\(MenuShortcuts.all.map(\.displayText))")
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
        #expect(byTitle["Show in Finder"]?.displayText == "⌥⌘R")
        #expect(byTitle["Move to Trash"]?.displayText == "⌘⌫")
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
            "newSong", "importSongs", "showInFinder", "moveToTrash", "close", "save", "refresh",
            "startShow", "rehearse", "newSetlist", "mainWindow", "help", "keyboardShortcuts",
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
    func `credits link the site pages and name the open-source software`() {
        let credits = AboutPanel.credits()
        let whole = NSRange(location: 0, length: credits.length)
        var links: [URL] = []
        credits.enumerateAttribute(.link, in: whole) { value, _, _ in
            if let url = value as? URL {
                links.append(url)
            }
        }
        #expect(links == [
            SegueLinks.site, SegueLinks.help, SegueLinks.support, SegueLinks.privacy,
            SegueLinks.acknowledgements,
        ])
        let plain = credits.string.replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{2028}", with: " ")
        #expect(plain.contains(
            "Schibsted Grotesk (SIL OFL 1.1), GRDB (MIT), Tonic (MIT), Sentry (MIT).",
        ))
    }

    @Test
    func `every bundled licence text loads`() {
        for credit in AcknowledgementsView.credits {
            let text = AcknowledgementsView.licenceText(credit) ?? ""
            #expect(text.count > 200, "\(credit.name) licence missing")
        }
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
