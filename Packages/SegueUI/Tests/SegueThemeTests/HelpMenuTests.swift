import Foundation
@testable import SegueUI
import Testing

/// The Help menu's items and what each one opens (WS2a 3.5.6), through the same recording
/// workspace the E2E suite reads (`-SegueWorkspaceLog`). Moved down from
/// `SegueCoreUXE2ETests.testHelpMenu`, which now clicks one link to prove the menu-to-action
/// wiring (docs/test-performance.md, coverage mapping).
@MainActor
struct HelpMenuTests {
    @Test
    func `the help menu lists the canonical items in order`() {
        let titles = HelpMenu.items(hooks: AppHooks(), writeReview: nil).map(\.title)
        #expect(titles == [
            "Segue Help", "Keyboard Shortcuts", "What's New in Segue", "Report a Problem…",
            "Request a Feature…", "Privacy Policy", "Terms of Use",
        ])
    }

    @Test
    func `each help link opens its page and report a problem mails support`() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appending(path: "HelpMenuTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        var opened: [String: [String]] = [:]
        for item in HelpMenu.items(hooks: AppHooks(), writeReview: nil) {
            guard case let .workspace(open) = item.action else { continue }
            let log = scratch.appending(path: "\(opened.count).log")
            open(RecordingWorkspaceActions(log: log))
            opened[item.title] = try Self.calls(log)
        }
        // The URL table itself (scheme, host, paths) is `SegueLinksTests`.
        let page = { (url: URL) in ["open " + url.absoluteString] }
        #expect(opened["What's New in Segue"] == page(SegueLinks.changelog))
        #expect(opened["Request a Feature…"] == page(SegueLinks.feedback))
        #expect(opened["Privacy Policy"] == page(SegueLinks.privacy))
        #expect(opened["Terms of Use"] == page(SegueLinks.terms))
        let mail = try #require(opened["Report a Problem…"]?.first)
        #expect(mail.hasPrefix("open " + SegueLinks.supportEmail.absoluteString), "\(mail)")
        #expect(opened.count == 5, "\(opened.keys.sorted())")
    }

    @Test
    func `segue help opens the help book and waits with keyboard shortcuts while a show is up`() {
        let items = HelpMenu.items(hooks: AppHooks(), writeReview: nil)
        let help = items.first { $0.title == "Segue Help" }
        guard case .helpBook = help?.action else {
            Issue.record("Segue Help does not open the Help Book")
            return
        }
        let waiting = items.filter(\.disabledWhilePerforming).map(\.title)
        #expect(waiting == ["Segue Help", "Keyboard Shortcuts", "What's New in Segue"])
    }

    @Test
    func `keyboard shortcuts is the only window the menu opens`() {
        var windows: [String: String] = [:]
        for item in HelpMenu.items(hooks: AppHooks(), writeReview: nil) {
            if case let .window(id) = item.action {
                windows[item.title] = id
            }
        }
        #expect(windows == ["Keyboard Shortcuts": KeyboardShortcutsWindow.id])
    }

    @Test
    func `welcome and rate segue appear once their hook and app store id exist`() throws {
        let hooks = AppHooks(showWelcome: { _ in })
        let review = try #require(SegueLinks.writeReview(appStoreID: "1234567890"))
        let titles = HelpMenu.items(hooks: hooks, writeReview: review).map(\.title)
        #expect(titles.firstIndex(of: "Welcome to Segue…") == 2)
        #expect(titles.firstIndex(of: "Rate Segue on the App Store") == 6)
        #expect(titles.count == 9)
    }

    /// The log's lines as "<action> <first url>".
    private static func calls(_ log: URL) throws -> [String] {
        try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map { line in
            let object = try #require(
                JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
            )
            let action = try #require(object["action"] as? String)
            let urls = try #require(object["urls"] as? [String])
            return action + " " + (urls.first ?? "")
        }
    }
}
