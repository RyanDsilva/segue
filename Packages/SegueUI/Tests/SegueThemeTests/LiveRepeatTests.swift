import AppKit
import Foundation
import Library
@testable import SegueUI
import Shows
import Testing

/// R102 on stage: quick search shows where each song stands, and adding a song already in
/// the show is refused in the overlay, with Move to Next for an upcoming one.
extension StageWindowSuites {
    @MainActor
    @Suite(.serialized)
    struct LiveRepeatTests {
        @Test
        func `quick search refuses a repeat and moves an upcoming song to next`() async throws {
            _ = NSApplication.shared
            let env = try TestEnvironment()
            let app = try await env.openApp()
            let fixture = try await LiveFixture(
                app: app,
                titles: ["Alpha", "Bravo", "Charlie", "Delta"],
            )
            let songs = fixture.songs
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
            #expect(await app.startShow(fixture.setlist, kind: .gig))
            let live = try #require(app.live)
            defer { StageWindowController.shared.close() }
            live.dispatch(.next)
            _ = try await env.waitFor { live.positionText == "2 of 4" ? true : nil }

            // The badges, before acting.
            let badges = songs.map { StandingBadge.text(live.standing(of: $0.id)) }
            #expect(badges == ["Played", "Playing", "Up next", "In set"])
            #expect(StandingBadge.spoken(live.standing(of: songs[0].id)) == "Already played")

            // A played song: refused in the overlay, nothing added, Return goes back.
            live.dispatch(.openSearch)
            live.search.query = "alpha"
            _ = try await env.waitFor { live.search.results.first?.id == songs[0].id ? true : nil }
            for action: LiveSession.SearchAction in [.insertNext, .addRequest, .playNow] {
                live.searchAction(action, song: songs[0].id)
                let refusal = try #require(live.search.refusal)
                #expect(refusal.heading == "Already played tonight")
                #expect(refusal.refusal.moveToNext == nil)
                #expect(live.search.requesting == nil)
                #expect(live.overlay == .search)
                live.confirmRefusal()
                #expect(live.search.refusal == nil)
                #expect(live.overlay == .search)
            }

            // An upcoming song: "Already in the set", Esc goes back, Return moves it to next.
            live.search.query = "delta"
            _ = try await env.waitFor { live.search.results.first?.id == songs[3].id ? true : nil }
            live.searchAction(.addRequest, song: songs[3].id)
            #expect(live.search.refusal?.heading == "Already in the set")
            #expect(live.search.requesting == nil)
            live.cancelRefusal()
            #expect(live.search.refusal == nil)
            live.searchAction(.insertNext, song: songs[3].id)
            live.confirmRefusal()
            #expect(live.overlay == nil)
            _ = try await env.waitFor {
                live.state.record.items.map(\.title) == ["Alpha", "Bravo", "Delta", "Charlie"]
                    ? true : nil
            }
            #expect(live.queuedRequests.isEmpty)
            #expect(StandingBadge.text(live.standing(of: songs[3].id)) == "Up next")
            #expect(live.notice == nil)
        }
    }
}
