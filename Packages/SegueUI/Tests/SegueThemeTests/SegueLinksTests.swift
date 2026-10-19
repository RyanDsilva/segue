import Foundation
@testable import SegueUI
import Testing

/// The one URL table (WS2a 3.1) and the menu hook fallbacks (B-14).
@MainActor
struct SegueLinksTests {
    @Test
    func `site links are https pages on the site and the support address is mail`() {
        let pages: [(URL, String)] = [
            (SegueLinks.site, ""), (SegueLinks.help, "/help"), (SegueLinks.privacy, "/privacy"),
            (SegueLinks.terms, "/terms"), (SegueLinks.support, "/support"),
            (SegueLinks.changelog, "/changelog"), (SegueLinks.feedback, "/feedback"),
        ]
        for (url, path) in pages {
            #expect(url.scheme == "https")
            #expect(url.host() == SegueLinks.site.host())
            #expect(url.path() == path)
        }
        #expect(SegueLinks.supportEmail.scheme == "mailto")
        #expect(SegueLinks.helpPage("keyboard") == SegueLinks.help.appending(path: "keyboard"))
        #expect(SegueLinks.helpPage("keyboard").path() == "/help/keyboard")
    }

    @Test
    func `rate segue appears only once the app store id is known`() {
        #expect(SegueLinks.appStoreID == nil)
        #expect(SegueLinks.writeReview == nil)
        #expect(SegueLinks.writeReview(appStoreID: "") == nil)
        let url = SegueLinks.writeReview(appStoreID: "1234567890")
        #expect(url?.scheme == "macappstore")
        #expect(url?.absoluteString.hasSuffix("/app/id1234567890?action=write-review") == true)
    }

    @Test
    func `release notes are never fetched from a feed`() throws {
        // What's New reads only the bundled changelog (A16, I-3): no URL here may name it.
        let source = try String(contentsOf: Self.linksSource, encoding: .utf8)
        #expect(!source.contains("changelog.json"))
    }

    @Test
    func `hook fallbacks open the web and a support mail with the version`() {
        let workspace = SpyWorkspace()
        let hooks = AppHooks()
        #expect(hooks.showWelcome == nil)
        #expect(hooks.exportArchive == nil)
        hooks.showWhatsNew(workspace)
        hooks.requestFeature(workspace)
        #expect(workspace.opened == [SegueLinks.changelog, SegueLinks.feedback])
        let mail = AppHooks.problemMail(bundle: Bundle(for: SpyWorkspace.self))
        #expect(mail.scheme == "mailto")
        #expect(mail.absoluteString.contains("subject=Segue%20"))
        #expect(mail.absoluteString.hasSuffix("problem"))
    }

    private static var linksSource: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/SegueUI/App/SegueLinks.swift")
    }
}

/// Records what the app would open or reveal.
@MainActor
final class SpyWorkspace: WorkspaceActions {
    var opened: [URL] = []
    var revealed: [[URL]] = []

    func open(_ url: URL) {
        opened.append(url)
    }

    func reveal(_ urls: [URL]) {
        revealed.append(urls)
    }
}
