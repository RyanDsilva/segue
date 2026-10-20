import Foundation
@testable import SegueUI
import Testing
import TipKit

/// In-app links into the user guide (WS6 7): every page is a guide URL on the site (the site
/// check resolves each against the built guide), and tips' Learn More opens its page.
@MainActor
struct GuideLinksTests {
    @Test
    func `every guide link is a page of the guide on the site`() {
        for page in SegueLinks.Guide.allCases {
            let url = page.url
            #expect(url.scheme == "https")
            #expect(url.host() == SegueLinks.site.host())
            #expect(url.path() == "/guide" || url.path().hasPrefix("/guide/"), "\(page)")
            #expect(!url.path().hasSuffix(".html") && !url.path().hasSuffix("/"), "\(page)")
            #expect(!page.title.isEmpty)
        }
        #expect(SegueLinks.Guide.home.url == SegueLinks.help)
    }

    @Test
    func `learn more on a tip opens its guide page and nothing else does`() {
        var opened: [SegueLinks.Guide] = []
        let open = OpenGuideAction { opened.append($0) }
        GuideTipAction.handle(GuideTipAction.action, page: .gigMode, openGuide: open)
        GuideTipAction.handle(
            Tips.Action(id: GigModeTip.openSettingsAction, title: "Open Settings"),
            page: .gigMode,
            openGuide: open,
        )
        GuideTipAction.handle(GuideTipAction.action, page: .search, openGuide: nil)
        #expect(opened == [.gigMode])
    }

    @Test
    func `every tip offers learn more with its own page`() {
        let tips: [(actions: [Tips.Action], page: SegueLinks.Guide)] = [
            (SearchAnyLineTip().actions, SearchAnyLineTip.guidePage),
            (PasteSongTip().actions, PasteSongTip.guidePage),
            (TransposeViewTip().actions, TransposeViewTip.guidePage),
            (MoveChordTip().actions, MoveChordTip.guidePage),
            (StartShowTip().actions, StartShowTip.guidePage),
            (GigModeTip().actions, GigModeTip.guidePage),
        ]
        for tip in tips {
            #expect(tip.actions.contains { $0.id == GuideTipAction.learnMore })
        }
        #expect(Set(tips.map(\.page)).count == tips.count)
    }

    @Test
    func `the guide action opens the page through the workspace`() {
        let workspace = SpyWorkspace()
        let action = OpenGuideAction { workspace.open($0.url) }
        action(.setAssistant)
        #expect(workspace.opened == [SegueLinks.Guide.setAssistant.url])
    }
}
