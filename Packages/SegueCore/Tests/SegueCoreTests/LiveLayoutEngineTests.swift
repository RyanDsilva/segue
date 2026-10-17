import ChordPro
import Editing
import Foundation
import Library
import LiveLayout
import Testing

/// Golden layouts with `FixedAdvanceMetrics` (every character 0.5 em, ascent 0.8, descent
/// 0.2): exact positions, the scroll fallback, forced columns, zoom and the fit rules.
struct LiveLayoutEngineTests {
    typealias Support = LiveLayoutSupport

    @Test
    func `chords sit above their characters and the line is one run`() throws {
        let model = Support.model(source: "[G]Hello [C]world")
        let (plan, _) = Support.plan(model, viewport: LayoutSize(width: 800, height: 600))
        // One short line: the largest size, one column.
        #expect(plan.lyricSize == 44)
        #expect(plan.columns.count == 1)
        #expect(plan.fit == .fits)
        let row = try #require(plan.blocks.first?.allRows.first)
        let size = plan.lyricSize
        let chord = plan.chordSize
        #expect(row.chords.map(\.text) == ["G", "C"])
        #expect(row.chords.map(\.x) == [0, 3 * size])
        #expect(row.chords.map(\.width) == [0.5 * chord, 0.5 * chord])
        #expect(row.text.map(\.text) == ["Hello world"])
        #expect(row.text.first?.width == 5.5 * size)
        // Bands: the chord band is the chord's ink (0.7 + 0.2) or 1.0 x the chord size,
        // descenders at its bottom; the text band is 1.25 x the lyric size, glyphs centred.
        let chordBand = chord * 1.0
        #expect(abs(row.height - (chordBand + size * 1.25)) < 1e-9)
        #expect(abs((row.chordBaseline ?? 0) - (chordBand - 0.2 * chord)) < 1e-9)
        #expect(abs(row.textBaseline - (chordBand + (size * 1.25 - size) / 2 + 0.8 * size)) < 1e-9)
    }

    @Test
    func `colliding chords push the lyric apart`() throws {
        let model = Support.model(source: "[Cmaj7]a[D]b")
        let (plan, _) = Support.plan(model, viewport: LayoutSize(width: 800, height: 600))
        let row = try #require(plan.blocks.first?.allRows.first)
        let chord = plan.chordSize
        // Cmaj7 is 2.5 chord-ems wide; D needs a 0.5 chord-em gap after it.
        let pushed = 2.5 * chord + 0.5 * chord
        #expect(row.chords.count == 2)
        #expect(row.chords.first?.x == 0)
        #expect(abs((row.chords.last?.x ?? 0) - pushed) < 1e-9)
        #expect(row.text.map(\.text) == ["a", "b"])
        #expect(abs((row.text.last?.x ?? 0) - pushed) < 1e-9)
    }

    @Test
    func `long lines wrap at words and take their chords along`() throws {
        let source = "[G]one two three [C]four five six [D]seven eight nine"
        let model = Support.model(source: source)
        // Lyric area: 360 - 64 - 12 = 284pt; at 22pt a character is 11pt (25 per row).
        let (plan, request) = Support.plan(
            model,
            viewport: LayoutSize(width: 360, height: 60),
            minLyricSize: 22,
        )
        #expect(plan.fit == .scrollsAtMinimum)
        #expect(plan.lyricSize == 22)
        let rows = try #require(plan.blocks.first?.allRows)
        #expect(rows.map { $0.text.map(\.text).joined() } == [
            "one two three four five", "six seven eight nine",
        ])
        #expect(rows.map { $0.chords.map(\.text) } == [["G", "C"], ["D"]])
        #expect(abs((rows[1].chords.first?.x ?? 0) - 4 * 11) < 1e-9)
        #expect(LayoutAudit.violations(of: plan, request: request, metrics: FixedAdvanceMetrics())
            .isEmpty)
    }

    @Test
    func `a word wider than the column breaks between characters`() throws {
        let model = Support.model(source: "[G]" + String(repeating: "a", count: 60))
        let (plan, request) = Support.plan(model, viewport: LayoutSize(width: 400, height: 900))
        let rows = try #require(plan.blocks.first?.allRows)
        #expect(rows.count > 1)
        #expect(rows.first?.chords.map(\.text) == ["G"])
        #expect(rows.map { $0.text.map(\.text).joined() }.joined() == String(
            repeating: "a",
            count: 60,
        ))
        #expect(LayoutAudit.violations(of: plan, request: request, metrics: FixedAdvanceMetrics())
            .isEmpty)
    }

    @Test
    func `the largest size wins and ties go to fewer columns`() {
        // Two short sections: every column count reaches the maximum; one column is chosen.
        let model = Support.model(source: """
        {start_of_verse}
        [G]Short line
        {end_of_verse}
        {start_of_chorus}
        [C]Another
        {end_of_chorus}
        """)
        let (plan, _) = Support.plan(model)
        #expect(plan.lyricSize == LayoutStyle.stage.maxLyricSize)
        #expect(plan.columns.count == 1)
    }

    @Test
    func `more columns win when they allow a larger size`() {
        let model = Support.model(source: Support.longSong(lines: 24))
        let (plan, request) = Support.plan(model)
        #expect(plan.fit == .fits)
        #expect(plan.columns.count > 1)
        // No single column count could do better: one more step does not fit anywhere.
        for columns in 1 ... 3 {
            let (bigger, _) = Support.plan(
                model,
                minLyricSize: plan.lyricSize + 0.5,
                columns: columns,
            )
            #expect(bigger.fit != .fits, "\(columns) columns fit above \(plan.lyricSize)")
        }
        #expect(LayoutAudit.violations(of: plan, request: request, metrics: FixedAdvanceMetrics())
            .isEmpty)
    }

    @Test
    func `columns break between sections when a layout allows it`() {
        let model = Support.model(source: Support.longSong(lines: 36))
        let (plan, _) = Support.plan(model)
        #expect(plan.fit == .fits)
        #expect(plan.blocks.allSatisfy { $0.part == 0 })
        let ids = plan.blocks.map(\.id)
        #expect(ids == ids.sorted())
        #expect(Set(ids).count == ids.count)
    }

    @Test
    func `one huge section is split between columns only when nothing else fits`() {
        // 30 loose lines form one section: too tall for one column at the minimum.
        let model = Support.model(source: Support.longSong(lines: 30, perSection: 0))
        #expect(model.sections.count == 1)
        let (plan, request) = Support.plan(model)
        #expect(plan.fit == .fits)
        #expect(plan.columns.count > 1)
        #expect(plan.blocks.map(\.part) == Array(0 ..< plan.blocks.count))
        #expect(plan.blocks.dropFirst().allSatisfy { $0.label == nil && $0.labelLines.isEmpty })
        #expect(LayoutAudit.violations(of: plan, request: request, metrics: FixedAdvanceMetrics())
            .isEmpty)
    }

    @Test
    func `nothing fits at the minimum so it scrolls in one column at the minimum`() {
        let model = Support.model(source: Support.longSong(lines: 160))
        let (plan, request) = Support.plan(model, minLyricSize: 30)
        #expect(plan.fit == .scrollsAtMinimum)
        #expect(plan.lyricSize == 30)
        #expect(plan.columns.count == 1)
        #expect(plan.needsScroll)
        #expect(plan.pageStops.first == 0)
        #expect(plan.pageStops.last == plan.overflow)
        #expect(zip(plan.pageStops, plan.pageStops.dropFirst()).allSatisfy { $0 < $1 })
        // Each page overlaps the previous one (a line repeats), never skips content.
        #expect(zip(plan.pageStops, plan.pageStops.dropFirst())
            .allSatisfy { $1 - $0 < plan.viewport.height })
        #expect(plan.lineCount == 160)
        #expect(LayoutAudit.violations(of: plan, request: request, metrics: FixedAdvanceMetrics())
            .isEmpty)
    }

    @Test
    func `a raised minimum turns a fitting song into a scrolling one`() throws {
        let model = try Support.model("live-forty-lines.cho")
        let metrics = Support.schibstedLike
        let (atDefault, _) = Support.plan(model, metrics: metrics)
        #expect(atDefault.fit == .fits)
        #expect(atDefault.lyricSize >= 22)
        let (atThirty, request) = Support.plan(model, minLyricSize: 30, metrics: metrics)
        #expect(atThirty.fit == .scrollsAtMinimum)
        #expect(atThirty.lyricSize == 30)
        #expect(LayoutAudit.violations(of: atThirty, request: request, metrics: metrics).isEmpty)
    }

    @Test
    func `forced columns are used even below the minimum column width`() {
        let model = Support.model(source: Support.longSong(lines: 24))
        let (plan, _) = Support.plan(
            model,
            viewport: LayoutSize(width: 900, height: 700),
            columns: 3,
        )
        #expect(plan.columns.count <= 3)
        let width = (900 - 2 * 48) / 3.0
        #expect(plan.columns.allSatisfy { $0.width == width })
        #expect(plan.columns.enumerated().allSatisfy { $1.x == Double($0) * (width + 48) })
    }

    @Test
    func `zoom scales the fitted size but never below the minimum`() throws {
        let model = try Support.model("basic-verse-chorus.cho")
        let (base, _) = Support.plan(model)
        #expect(base.fit == .fits)
        let (smaller, _) = Support.plan(model, zoom: 0.8)
        #expect(abs(smaller.lyricSize - max(22, base.lyricSize * 0.8)) < 1e-9)
        #expect(smaller.fit == .fits)
        let (tiny, _) = Support.plan(model, zoom: 0.25)
        #expect(tiny.lyricSize == 22)
        let (bigger, request) = Support.plan(model, zoom: 1.6)
        #expect(abs(bigger.lyricSize - base.lyricSize * 1.6) < 1e-9)
        #expect(bigger.fit == .scrollsZoomed)
        #expect(LayoutAudit.violations(of: bigger, request: request, metrics: FixedAdvanceMetrics())
            .isEmpty)
        // Zooming out a scrolled song stays at the minimum.
        let long = Support.model(source: Support.longSong(lines: 160))
        let (clamped, _) = Support.plan(long, zoom: 0.5)
        #expect(clamped.lyricSize == 22)
        #expect(clamped.fit == .scrollsAtMinimum)
    }

    @Test
    func `notes and unmatched cues come first and cues sit at their sections`() throws {
        let model = try Support.model("basic-verse-chorus.cho")
        let (plan, request) = Support.plan(
            model,
            cues: [
                SongCue(section: "chorus", occurrence: 1, text: "Watch Ravi for the stop"),
                SongCue(section: "Verse 2", text: "Half time"),
                SongCue(section: "Coda", text: "Ring out"),
            ],
            notes: ["Start soft", "Capo 2 on the Martin"],
        )
        let notes = try #require(plan.columns.first?.blocks.first)
        #expect(notes.id == -1)
        guard case let .notes(rows) = notes.content else {
            Issue.record("first block is not the notes block")
            return
        }
        #expect(rows.flatMap(\.text).map(\.text) == [
            "Start soft", "Capo 2 on the Martin", "Coda: Ring out",
        ])
        #expect(plan.block(id: 1)?.cues.map(\.text) == ["Watch Ravi for the stop"])
        #expect(plan.block(id: 2)?.cues.map(\.text) == ["Half time"])
        #expect(plan.block(id: 3)?.cues.isEmpty == true)
        #expect(LayoutAudit.violations(of: plan, request: request, metrics: FixedAdvanceMetrics())
            .isEmpty)
    }

    @Test
    func `plans are deterministic`() throws {
        let model = try Support.model("hindi-dil-kabhie.cho")
        let first = Support.plan(model).0
        let second = Support.plan(model).0
        #expect(first == second)
    }

    @Test
    func `an empty song plans to nothing`() throws {
        let (plan, _) = try Support.plan(Support.model("empty.cho"))
        #expect(plan.blocks.isEmpty)
        #expect(plan.fit == .fits)
        #expect(plan.pageStops == [0])
    }
}
