import ChordPro
import Editing
import Foundation
import Library
import LiveLayout
import Testing

/// decisions.md, "Auto-fit wrapping (revised)": when lyric lines may wrap, and widow
/// avoidance when they do (fixed advance metrics).
struct LiveLayoutWrapTests {
    typealias Support = LiveLayoutSupport

    /// decisions.md, "Auto-fit wrapping (revised)": no lyric line wraps when a layout
    /// without wrapping reaches max(28pt, 1.25 x the minimum); only a song whose no-wrap
    /// layout stays below that wraps (when wrapping is larger).
    @Test(arguments: [
        // Height, characters in the long line, whether the chosen layout wraps it.
        (360.0, 40, false),
        // No-wrap tops out at 30pt (>= 28pt): never wraps, however much larger wrapping is.
        (900.0, 40, false),
        // No-wrap tops out at 24pt (< 28pt): wrapping wins.
        (900.0, 50, true),
    ])
    func `no lyric line wraps when a no-wrap layout reaches a comfortable size`(
        height: Double,
        characters: Int,
        wraps: Bool,
    ) {
        // `characters` at 0.5 em in a 676pt viewport (64pt gutter + 12pt gap + 600pt): the
        // long line fits unwrapped up to 1200 / characters pt.
        let words = (characters - 5) / 5
        let long = "[G]" + String(repeating: "abcd ", count: words) + "abc[C]ef"
        #expect(long.count - 6 == characters)
        let model = Support.model(source: "\(long)\n[D]one\n[G]two\n[C]three")
        let viewport = LayoutSize(width: 676, height: height)
        let (plan, request) = Support.plan(model, viewport: viewport)
        let rows = plan.blocks.flatMap(\.allRows).filter { $0.kind == .lyric }
        let noWrap = 1200 / Double(characters)
        #expect(plan.fit == .fits)
        #expect((rows.count > 4) == wraps, "\(plan.lyricSize)pt, \(rows.count) rows")
        if wraps {
            #expect(noWrap < 28)
            #expect(plan.lyricSize > noWrap)
        } else {
            #expect(plan.lyricSize <= noWrap)
            #expect(plan.lyricSize >= min(29, noWrap - 1))
        }
        #expect(LayoutAudit.violations(of: plan, request: request, metrics: FixedAdvanceMetrics())
            .isEmpty)
    }

    /// The comfortable size follows a raised minimum: at a 26pt minimum it is 32.5pt, so a
    /// song whose no-wrap layout tops out at 30pt may wrap.
    @Test
    func `the comfortable size is 1.25 x a raised minimum`() {
        let long = "[G]" + String(repeating: "abcd ", count: 7) + "abc[C]ef"
        let model = Support.model(source: "\(long)\n[D]one\n[G]two\n[C]three")
        let request = LayoutRequest(
            model: model,
            viewport: LayoutSize(width: 676, height: 900),
            minLyricSize: 26,
        )
        let plan = LayoutEngine.plan(request, metrics: FixedAdvanceMetrics())
        let rows = plan.blocks.flatMap(\.allRows).filter { $0.kind == .lyric }
        #expect(rows.count > 4, "\(plan.lyricSize)pt")
        #expect(plan.lyricSize > 30)
    }

    /// Widow avoidance: a wrapped line never leaves one word alone on its last row when the
    /// words can be spread so it does not.
    @Test
    func `a wrapped line does not end on a single word`() throws {
        // Too short to fit, so it scrolls at the 22pt minimum: at 0.5 em that is 11pt per
        // character, and the lyric width (600 - 76) holds 47 characters, so first-fit
        // breaking would leave "end" alone on the second row.
        let line = String(repeating: "word ", count: 9) + "end"
        let model = Support.model(source: "[G]\(line)")
        let request = LayoutRequest(
            model: model,
            viewport: LayoutSize(width: 600, height: 10),
            minLyricSize: 22,
            zoom: 1,
            columns: 1,
        )
        let plan = LayoutEngine.plan(request, metrics: FixedAdvanceMetrics())
        let rows = plan.blocks.flatMap(\.allRows).filter { $0.kind == .lyric }
        try #require(rows.count == 2, "\(plan.lyricSize)pt: \(rows.map(\.text))")
        let words = rows.map { row in
            row.text.map(\.text).joined().split(separator: " ").count
        }
        #expect(words.allSatisfy { $0 > 1 }, "\(words)")
        #expect(words.reduce(0, +) == 10)
        #expect(LayoutAudit.violations(of: plan, request: request, metrics: FixedAdvanceMetrics())
            .isEmpty)
    }
}
