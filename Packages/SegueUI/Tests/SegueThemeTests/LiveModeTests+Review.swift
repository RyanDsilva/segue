import AppKit
import Foundation
@testable import SegueUI
import Setlists
import Shows
import Testing

/// The end-of-show reorder review answered twice at once (R154): a double click on Save
/// writes once and never drops or traps on the next review.
extension StageWindowSuites.LiveModeTests {
    /// Runs a gig of `setlist` with its last song moved up, then ends it (one review).
    private static func endReorderedGig(
        _ setlist: Setlist,
        app: AppModel,
        env: TestEnvironment,
    ) async throws {
        #expect(await app.startShow(setlist, kind: .gig))
        let live = try #require(app.live)
        live.perform(.move(fromOffsets: [2], toOffset: 1))
        _ = try await env.waitFor {
            live.state.record.items.map(\.title) == ["Alpha", "Charlie", "Bravo"] ? true : nil
        }
        live.dispatch(.endShow)
        live.confirmEnd()
        _ = try await env.waitFor { app.live == nil ? true : nil }
        StageWindowController.shared.close()
    }

    @Test
    func `a double save answers the review once and keeps the next one`() async throws {
        _ = NSApplication.shared
        let env = try TestEnvironment()
        let app = try await env.openApp()
        let session = try #require(app.session)
        let fixture = try await LiveFixture(app: app, titles: ["Alpha", "Bravo", "Charlie"])
        let second = try #require(await session.setlists.create(name: "Second Set"))
        for song in fixture.songs {
            await session.setlists.add(song.id, to: second.id)
        }
        let secondSet = try #require(session.setlists.setlist(second.id))
        app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
        try await Self.endReorderedGig(fixture.setlist, app: app, env: env)
        try await Self.endReorderedGig(secondSet, app: app, env: env)
        _ = try await env.waitFor { app.pendingReorderReviews.count == 2 ? true : nil }
        let first = try #require(app.pendingReorderReviews.first)
        let next = try #require(app.pendingReorderReviews.last)

        async let one: Void = app.resolveReorderReview(save: true, including: [])
        async let two: Void = app.resolveReorderReview(save: true, including: [])
        _ = await (one, two)

        #expect(!app.isResolvingReview)
        #expect(app.pendingReorderReviews == [next])
        let shows = session.stores.shows
        let firstId = try #require(first.showId)
        let nextId = try #require(next.showId)
        let answered = try #require(await shows.reloaded(firstId))
        let waiting = try #require(await shows.reloaded(nextId))
        #expect(answered.reorderReview == .saved)
        #expect(waiting.reorderReview == .pending)
    }

    @Test
    func `a double answer to the only review does not trap`() async throws {
        _ = NSApplication.shared
        let env = try TestEnvironment()
        let app = try await env.openApp()
        let fixture = try await LiveFixture(app: app, titles: ["Alpha", "Bravo", "Charlie"])
        app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
        try await Self.endReorderedGig(fixture.setlist, app: app, env: env)
        _ = try await env.waitFor { app.pendingReorderReviews.count == 1 ? true : nil }

        async let one: Void = app.resolveReorderReview(save: false, including: [])
        async let two: Void = app.resolveReorderReview(save: false, including: [])
        _ = await (one, two)

        #expect(app.pendingReorderReviews.isEmpty)
    }
}
