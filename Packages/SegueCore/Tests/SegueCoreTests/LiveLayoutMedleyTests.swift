import ChordPro
import Editing
import Foundation
import Library
import LiveLayout
import Setlists
import Support
import Testing

/// One stage plan per medley (P9-3 9.1-9.3, 9.6, 9.9): segments in order, member headers,
/// pass naming per member, one lyric size, keys across members, the follow model and
/// singer view per segment.
struct LiveLayoutMedleyTests {
    private let metrics = FixedAdvanceMetrics()

    static func source(_ title: String, key: String, chorus: Int = 2) -> String {
        var parts = ["{title: \(title)}", "{key: \(key)}", "{tempo: 96}", ""]
        parts += [
            "{start_of_verse: Verse 1}",
            "[\(key)]Walking down the [D]road",
            "{end_of_verse}",
            "",
        ]
        parts += ["{start_of_chorus}", "[\(key)]Sing it [D]loud", "{end_of_chorus}", ""]
        parts += Array(repeating: "{chorus}", count: chorus - 1)
        return parts.joined(separator: "\n")
    }

    static func segments(transition: String? = "Hold the D, drums fill") -> [LayoutSegment] {
        let songs = [("Kesariya", "G"), ("Tum Hi Ho", "A"), ("Channa Mereya", "D")]
        return songs.enumerated().map { index, song in
            LayoutSegment(
                model: LiveLayoutSupport.model(source: source(song.0, key: song.1)),
                notes: index == 1 ? ["Last chorus twice"] : [],
                header: MemberHeader(
                    title: song.0,
                    keyLine: "\(song.1), 96",
                    index: index,
                    count: 3,
                    transition: index == 1 ? transition : nil,
                    changes: index == 0 ? [] : [MemberChange(.capo, "no capo \u{2192} capo 2")],
                ),
            )
        }
    }

    private func plan(
        _ segments: [LayoutSegment],
        viewport: LayoutSize = LayoutSize(width: 700, height: 500),
        view: StageView = .chart,
    ) -> LayoutPlan {
        LayoutEngine.plan(
            LayoutRequest(segments: segments, viewport: viewport, minLyricSize: 24, view: view),
            metrics: metrics,
        )
    }

    @Test
    func `segments lay out in order with a header on each first pass`() {
        let plan = plan(Self.segments())
        #expect(plan.passes.map(\.segment) == [0, 0, 0, 1, 1, 1, 2, 2, 2])
        #expect(plan.passes.map(\.index) == Array(0 ..< 9))
        let blocks = plan.columns.flatMap(\.blocks)
        let headers = blocks.compactMap(\.memberHeader)
        #expect(headers.map(\.header.title) == ["Kesariya", "Tum Hi Ho", "Channa Mereya"])
        #expect(headers.map(\.hasRule) == [false, true, true])
        #expect(headers[0].callout == nil)
        #expect(headers[1].callout?.lines.isEmpty == false)
        #expect(headers[1].changesBaseline != nil)
        // A later member's notes sit in its header, not at the top.
        #expect(headers[1].notes.map(\.text.text).joined(separator: " ") == "Last chorus twice")
        // The header pushes the pass's rows down: its first row starts below it.
        let second = blocks.first { $0.memberHeader?.header.index == 1 }
        if let second, case let .rows(rows) = second.content, let first = rows.first {
            #expect(first.y >= second.memberHeaderTop + headers[1].height)
        } else {
            Issue.record("the second member's first block has rows")
        }
    }

    @Test
    func `passes are named per member and one lyric size covers the plan`() {
        let plan = plan(Self.segments())
        let names = plan.passes.map(\.name.chipText)
        #expect(names.filter { $0.hasPrefix("Chorus") }.count == 6)
        #expect(plan.passes[1].name.chipText == plan.passes[4].name.chipText)
        let alone = LayoutEngine.plan(
            LayoutRequest(
                model: LiveLayoutSupport.model(source: Self.source("Kesariya", key: "G")),
                viewport: LayoutSize(width: 700, height: 500),
                minLyricSize: 24,
            ),
            metrics: metrics,
        )
        #expect(plan.lyricSize <= alone.lyricSize)
    }

    @Test
    func `a single song request is unchanged by segments`() {
        let model = LiveLayoutSupport.model(source: Self.source("Kesariya", key: "G"))
        let viewport = LayoutSize(width: 700, height: 500)
        let plain = LayoutEngine.plan(
            LayoutRequest(model: model, viewport: viewport, minLyricSize: 24),
            metrics: metrics,
        )
        let one = LayoutEngine.plan(
            LayoutRequest(
                segments: [LayoutSegment(model: model)],
                viewport: viewport,
                minLyricSize: 24,
            ),
            metrics: metrics,
        )
        #expect(plain == one)
        #expect(plain.columns.flatMap(\.blocks).allSatisfy { $0.memberHeader == nil })
    }

    @Test
    func `singer view applies to every segment and keeps the headers`() {
        let plan = plan(Self.segments(), view: .singer)
        let blocks = plan.columns.flatMap(\.blocks)
        #expect(blocks.compactMap(\.memberHeader).count == 3)
        let chords = blocks.flatMap(\.allRows).flatMap(\.chords)
        #expect(chords.isEmpty)
    }

    @Test
    func `the follow model finds the member at the reading line and the seek offsets`() {
        let plan = plan(Self.segments(), viewport: LayoutSize(width: 400, height: 300))
        #expect(StagePasses.followsScroll(plan))
        #expect(MedleyFollow.memberCount(in: plan) == 3)
        #expect(MedleyFollow.member(in: plan, offset: 0, pinned: nil) == 0)
        let second = MedleyFollow.seekOffset(to: 1, in: plan)
        let top = MedleyFollow.headerTop(of: 1, in: plan) ?? 0
        #expect(second == max(0, top - StagePasses.jumpMargin))
        let line = top + 1
        #expect(MedleyFollow.member(at: line, plan: plan) == 1)
        #expect(MedleyFollow.member(in: plan, offset: 0, pinned: 7) == 2)
        #expect(MedleyFollow.member(in: plan, offset: plan.overflow, pinned: nil) == 2)
    }
}

/// The member header text (P9-3 9.2, 13 item 2): key line, transition and change line.
struct MemberHeaderTests {
    private static func item(_ byte: UInt8) -> SetlistItemID {
        SetlistItemID(ULID(milliseconds: 1, randomness: Array(repeating: byte, count: 10)))
    }

    /// Kesariya (G, 92) then Tum Hi Ho (A, 120) with capo 2 and a transition.
    private static func headers(singer: Bool) throws
        -> (first: MemberHeader, second: MemberHeader)
    {
        let first = try SlotTimeTests.record("{title: Kesariya}\n{key: G}\n{tempo: 92}\n[G]Hai\n")
        let second = try SlotTimeTests
            .record("{title: Tum Hi Ho}\n{key: A}\n{tempo: 120}\n[A]Hum\n")
        let opener = MedleyMember(itemId: item(1), songId: first.id)
        let member = MedleyMember(
            itemId: item(2),
            songId: second.id,
            overrides: SetlistOverrides(capo: 2),
            transition: "  Hold the D  ",
        )
        return (
            MemberHeader.make(
                member: opener,
                previous: nil,
                record: first,
                previousRecord: nil,
                index: 0,
                count: 3,
                title: "Kesariya",
                singer: singer,
            ),
            MemberHeader.make(
                member: member,
                previous: opener,
                record: second,
                previousRecord: first,
                index: 1,
                count: 3,
                title: "Tum Hi Ho",
                singer: singer,
            ),
        )
    }

    @Test
    func `make derives the key line and only what changes`() throws {
        let (top, header) = try Self.headers(singer: false)
        #expect(header.keyLine == "G, capo 2, 120")
        #expect(header.transition == "Hold the D")
        #expect(header.positionText == "2 of 3")
        #expect(header.changes.map(\.kind) == [.capo, .tempo])
        #expect(header.changeLine == "no capo \u{2192} capo 2 \u{00B7} 92 \u{2192} 120 BPM")
        #expect(top.transition == nil)
        #expect(top.changes.isEmpty)
    }

    @Test
    func `singer view reads the sounding key and drops the capo`() throws {
        let (_, header) = try Self.headers(singer: true)
        #expect(header.keyLine == "Key A, 120")
        #expect(!header.changes.contains { $0.kind == .capo })
    }
}

/// The 1 s dwell before a member change is committed (P9-3 9.6).
struct MedleyFollowTests {
    @Test
    func `a member is committed after the dwell, never on a quick pass`() {
        var dwell = MedleyFollow.Dwell()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        #expect(dwell.observe(shown: 0, committed: 0, at: start) == nil)
        #expect(dwell.observe(shown: 1, committed: 0, at: start) == nil)
        #expect(dwell.observe(shown: 1, committed: 0, at: start + 0.5) == nil)
        // Scrolled back before the second: nothing logged.
        #expect(dwell.observe(shown: 0, committed: 0, at: start + 0.7) == nil)
        #expect(dwell.observe(shown: 1, committed: 0, at: start + 0.8) == nil)
        #expect(dwell.observe(shown: 1, committed: 0, at: start + 1.7) == nil)
        #expect(dwell.observe(shown: 1, committed: 0, at: start + 1.8) == 1)
        #expect(dwell.candidate == nil)
    }
}
