import Foundation
@testable import SegueUI
import Services
import Testing

/// P9-5 section 3: Help opens the offline Help Book, the web guide only as its fallback,
/// nothing while a show is up, and row 14 says which route it took.
@MainActor
struct HelpBookRoutingTests {
    @Test(arguments: [
        (SegueLinks.Guide.home, "index"),
        (.keyboard, "keyboard"),
        (.checklist, "go-on-stage-checklist"),
        (.fileSync, "library-folder-file-sync"),
        (.smartFilters, "smart-filters-smart"),
    ])
    func `each guide page maps to its help anchor`(page: SegueLinks.Guide, anchor: String) {
        #expect(page.helpAnchor == anchor)
    }

    @Test
    func `every guide page has a distinct anchor that the built book carries`() {
        let anchors = SegueLinks.Guide.allCases.map(\.helpAnchor)
        #expect(Set(anchors).count == anchors.count)
        // The book's anchor list, when `make help-book` has run in this checkout.
        let list = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "../../Derived/HelpBook/anchors.txt").standardizedFileURL
        guard let text = try? String(contentsOf: list, encoding: .utf8) else { return }
        let built = Set(text.split(separator: "\n").map(String.init))
        for anchor in anchors {
            #expect(built.contains(anchor), "\(anchor) is not in Derived/HelpBook")
        }
    }

    @Test
    func `every guide page has its analytics page`() {
        let pages = SegueLinks.Guide.allCases.map(\.analyticsPage)
        #expect(!pages.contains(nil))
        #expect(Set(pages.compactMap(\.self)) == Set(HelpPage.allCases))
    }

    @Test
    func `help opens the book first and records the book route`() {
        let fixture = Fixture(bookOpens: true)
        #expect(fixture.router.openHome() == .book)
        #expect(fixture.router.open(.checklist) == .book)
        #expect(fixture.book.calls == ["home", "go-on-stage-checklist"])
        #expect(fixture.workspace.opened.isEmpty)
        #expect(fixture.events == [
            .helpOpened(.help, via: .book),
            .helpOpened(.contextHelp, via: .book, page: .checklist),
        ])
    }

    @Test
    func `without a book help opens the same page on the web`() {
        let fixture = Fixture(bookOpens: false)
        #expect(fixture.router.openHome() == .web)
        #expect(fixture.router.open(.fileSync) == .web)
        #expect(fixture.workspace.opened == [
            SegueLinks.Guide.home.url, SegueLinks.Guide.fileSync.url,
        ])
        #expect(fixture.events == [
            .helpOpened(.help, via: .web),
            .helpOpened(.contextHelp, via: .web, page: .fileSync),
        ])
    }

    @Test
    func `nothing opens while a show is up or starting`() {
        let fixture = Fixture(bookOpens: true, showUp: true)
        #expect(!fixture.router.isAvailable)
        #expect(fixture.router.openHome() == nil)
        #expect(fixture.router.open(.goOnStage) == nil)
        #expect(fixture.book.calls.isEmpty)
        #expect(fixture.workspace.opened.isEmpty)
        #expect(fixture.events.isEmpty)
    }

    @Test
    func `help buttons and learn more go through the router and wait while performing`() {
        let fixture = Fixture(bookOpens: true, showUp: true)
        let action = OpenGuideAction(
            isAvailable: { fixture.router.isAvailable },
            { fixture.router.open($0) },
        )
        #expect(!action.isAvailable)
        GuideTipAction.handle(GuideTipAction.action, page: .gigMode, openGuide: action)
        #expect(fixture.book.calls.isEmpty)

        let idle = Fixture(bookOpens: true)
        let open = OpenGuideAction(
            isAvailable: { idle.router.isAvailable },
            { idle.router.open($0) },
        )
        GuideTipAction.handle(GuideTipAction.action, page: .gigMode, openGuide: open)
        #expect(idle.book.calls == ["gig-mode"])
    }

    @Test
    func `the app model blocks help from the pre-show checklist to the end of the show`() throws {
        let env = try TestEnvironment()
        let app = AppModel(dependencies: env.dependencies(
            location: env.location(),
            override: env.libraryURL,
            remember: false,
        ))
        #expect(!app.isShowUp)
        app.isStartingShow = true
        #expect(app.isShowUp)
        #expect(!app.help.isAvailable)
        app.isStartingShow = false
        #expect(app.help.isAvailable)
    }

    /// A router over a scripted book, a spy workspace and a recorded event list.
    @MainActor
    private final class Fixture {
        let book: RecordingBook
        let workspace = SpyWorkspace()
        var events: [AnalyticsEvent] = []
        private(set) var router: HelpRouter!

        init(bookOpens: Bool, showUp: Bool = false) {
            book = RecordingBook(opens: bookOpens)
            router = HelpRouter(
                book: book,
                workspace: workspace,
                isShowUp: { showUp },
                record: { [weak self] in self?.events.append($0) },
            )
        }
    }

    @MainActor
    private final class RecordingBook: HelpBookOpening {
        let opens: Bool
        var calls: [String] = []

        init(opens: Bool) {
            self.opens = opens
        }

        func openHome() -> Bool {
            calls.append("home")
            return opens
        }

        func open(anchor: String) -> Bool {
            calls.append(anchor)
            return opens
        }
    }
}
