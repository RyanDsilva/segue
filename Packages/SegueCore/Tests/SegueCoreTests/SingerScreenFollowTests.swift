import ChordPro
import Editing
import Foundation
import Library
import LiveLayout
import Testing

/// Following a position from one plan of a song in another (P9-2 6.1 and 6.13): the same
/// pass at the same progress, whatever the two plans' sizes and drawings.
struct SingerScreenFollowTests {
    private let metrics = FixedAdvanceMetrics(factor: 0.45)

    /// A long one-column chart (scrolls at the minimum) and a singer plan of it at a larger
    /// display: different heights, the same passes.
    private func plans(viewport: LayoutSize = LayoutSize(width: 700, height: 500))
        -> (chart: LayoutPlan, singer: LayoutPlan)
    {
        let model = LiveLayoutSupport.model(source: LiveLayoutSupport.longSong(lines: 48))
        let chart = LayoutEngine.plan(
            LayoutRequest(model: model, viewport: viewport, minLyricSize: 22, columns: 1),
            metrics: metrics,
        )
        let singer = LayoutEngine.plan(LayoutRequest(
            model: model,
            viewport: LayoutSize(width: 1800, height: 900),
            minLyricSize: 28,
            columns: 1,
            style: .singer,
            view: .singer,
        ), metrics: metrics)
        return (chart, singer)
    }

    @Test(arguments: [(0, 0.0), (2, 0.5), (5, 0.25), (8, 0.9), (11, 1.0)])
    func `a pass at a progress maps to the same pass at the same progress`(
        pass: Int,
        progress: Double,
    ) throws {
        let (chart, singer) = plans()
        #expect(chart.needsScroll && singer.needsScroll)
        #expect(chart.passes.count == singer.passes.count)
        #expect(chart.contentHeight != singer.contentHeight)
        let offset = SingerScreenFollow.offset(pass: pass, progress: progress, in: chart)
        let (leaderPass, leaderProgress) = try #require(
            SingerScreenFollow.position(in: chart, offset: offset, pinned: nil),
        )
        let followed = SingerScreenFollow.offset(
            following: chart,
            at: offset,
            pinned: nil,
            in: singer,
        )
        let (followerPass, followerProgress) = try #require(
            SingerScreenFollow.position(in: singer, offset: followed, pinned: nil),
        )
        // Clamped at either end of the scroll, the reading line may sit just inside a pass.
        if followed > 0, followed < singer.overflow, offset > 0, offset < chart.overflow {
            #expect(followerPass == leaderPass)
            #expect(abs(followerProgress - leaderProgress) < 0.02)
        }
        #expect(followed >= 0 && followed <= singer.overflow)
    }

    @Test
    func `the top and the end of the song map to the top and the end`() {
        let (chart, singer) = plans()
        #expect(SingerScreenFollow.offset(following: chart, at: 0, pinned: nil, in: singer) == 0)
        let last = chart.passes.count - 1
        let end = SingerScreenFollow.offset(pass: last, progress: 1, in: chart)
        #expect(end == chart.overflow)
        let followed = SingerScreenFollow.offset(following: chart, at: end, pinned: nil, in: singer)
        #expect(abs(followed - singer.overflow) < 1)
    }

    @Test
    func `a pinned pass in a plan that does not scroll shows from its start`() throws {
        let model = LiveLayoutSupport.model(source: LiveLayoutSupport.longSong(lines: 12))
        let fits = LayoutEngine.plan(
            LayoutRequest(model: model, viewport: LiveLayoutSupport.external, minLyricSize: 22),
            metrics: metrics,
        )
        #expect(!fits.needsScroll)
        let (_, singer) = plans()
        let pinned = SingerScreenFollow.offset(following: fits, at: 0, pinned: 2, in: singer)
        let (pass, progress) = try #require(
            SingerScreenFollow.position(in: singer, offset: pinned, pinned: nil),
        )
        #expect(pass == 2)
        #expect(progress < 0.05)
        // Not pinned: the first pass.
        #expect(SingerScreenFollow.offset(following: fits, at: 0, pinned: nil, in: singer) == 0)
    }

    @Test
    func `a follower that fits never scrolls, and a missing pass lands on the last`() {
        let (chart, _) = plans()
        let model = LiveLayoutSupport.model(source: LiveLayoutSupport.longSong(lines: 4))
        let small = LayoutEngine.plan(
            LayoutRequest(model: model, viewport: LiveLayoutSupport.external, minLyricSize: 28),
            metrics: metrics,
        )
        let offset = SingerScreenFollow.offset(pass: 9, progress: 0.5, in: chart)
        #expect(SingerScreenFollow.offset(following: chart, at: offset, pinned: nil, in: small)
            == 0)
        #expect(SingerScreenFollow.offset(pass: 99, progress: 0.5, in: chart) == 0)
    }

    @Test
    func `a jump in the singer plan lands where the stage would land it`() throws {
        let (_, singer) = plans()
        for index in [0, 3, 7] {
            let offset = SingerScreenFollow.offset(pass: index, progress: 0, in: singer)
            let pass = try #require(
                SingerScreenFollow.position(in: singer, offset: offset, pinned: nil),
            )
            #expect(pass.pass == index || offset == 0)
        }
    }
}
