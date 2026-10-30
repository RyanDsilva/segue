import ChordPro
import Diagrams
import Editing
import Foundation
import Library
import LiveLayout
import MusicTheory
import Testing

/// The stage in the bass-note view (P8-4 sections 6.7, 7.3, 11.1-11.2): chord units with the
/// chord beside measured and placed as one, audited clean in full-song and arranged plans,
/// and the mini neck's chord at the reading line.
struct BassNeckChordTests {
    typealias Support = LiveLayoutSupport

    private let metrics = FixedAdvanceMetrics()

    static func model(_ source: String, chordBeside: Bool = true) -> RenderModel {
        let options = DisplayOptions().withBass(
            InstrumentProfile(bassNotes: true, chordBeside: chordBeside),
        )
        return RenderModel(document: ChordProParser.parse(source).0, options: options)
    }

    private func plan(
        _ model: RenderModel,
        passes: [PlayedPass]? = nil,
        viewport: LayoutSize = LayoutSize(width: 700, height: 400),
        columns: Int? = 1,
        minLyricSize: Double = 30,
    ) -> (LayoutPlan, LayoutRequest) {
        let request = LayoutRequest(
            model: model,
            viewport: viewport,
            minLyricSize: minLyricSize,
            columns: columns,
            passes: passes,
        )
        return (LayoutEngine.plan(request, metrics: metrics), request)
    }

    // MARK: Chord units

    @Test
    func `a chord unit is the note, a gap and the chord beside, as one`() throws {
        let model = Self.model("{key: G}\n{capo: 2}\n\n[G/B]Hello [C]world")
        let (plan, request) = plan(
            model,
            viewport: LayoutSize(width: 800, height: 600),
            columns: nil,
        )
        let row = try #require(plan.blocks.first?.allRows.first)
        let chord = plan.chordSize
        #expect(row.chords.map(\.text) == ["C#", "A/C#", "D", "D"])
        #expect(row.chords.map(\.role) == [.chord, .chordDetail, .chord, .chordDetail])
        let note = row.chords[0]
        let detail = row.chords[1]
        #expect(abs(detail.size - chord * ChordUnit.detailScale) < 1e-9)
        #expect(abs(detail.x - (note.x + note.width + ChordUnit.detailGap * chord)) < 1e-9)
        // The detail is 4 characters at 0.6 x the chord size.
        #expect(abs(detail.width - 4 * 0.5 * chord * ChordUnit.detailScale) < 1e-9)
        // The next unit starts after the whole unit, never under it.
        #expect(row.chords[2].x >= detail.x + detail.width - 1e-9)
        #expect(LayoutAudit.violations(of: plan, request: request, metrics: metrics).isEmpty)
    }

    @Test
    func `the corpus lays out clean in bass view with the chord beside`() throws {
        for name in EditingFixtures.wellFormed {
            let model = try Self.model(EditingFixtures.load(name))
            for (_, size) in Support.stages {
                let (plan, request) = Support.plan(model, viewport: size)
                let issues = LayoutAudit.violations(of: plan, request: request, metrics: metrics)
                #expect(issues.isEmpty, "\(name): \(issues.prefix(3))")
            }
        }
    }

    @Test
    func `chords only passes show bass notes with the chord beside`() throws {
        let model = Self.model(LiveLayoutPassTests.song)
        let (plan, request) = plan(
            model,
            passes: [
                PlayedPass(index: 0, position: 0),
                PlayedPass(index: 1, mode: .chordsOnly, position: 1),
            ],
            viewport: Support.macBook13,
            columns: nil,
            minLyricSize: 22,
        )
        let chordRow = try #require(plan.blocks.first { $0.id == 1 }?.allRows.first {
            $0.kind == .chordRow
        })
        #expect(chordRow.text.filter { $0.role == .chord }.map(\.text) == ["C", "G"])
        #expect(chordRow.text.filter { $0.role == .chordDetail }.map(\.text) == ["C", "G"])
        #expect(LayoutAudit.violations(of: plan, request: request, metrics: metrics).isEmpty)
    }

    @Test
    func `bass view off lays out exactly as before`() {
        let source = Support.longSong(lines: 12)
        let plain = RenderModel(document: ChordProParser.parse(source).0, options: DisplayOptions())
        let (before, _) = plan(plain)
        let off = RenderModel(
            document: ChordProParser.parse(source).0,
            options: DisplayOptions().withBass(InstrumentProfile(bassNotes: false)),
        )
        let (after, _) = plan(off)
        #expect(before == after)
    }

    // MARK: The neck's chord

    /// Eight 6-line verses, each line `[G]... [C]... [D]...`, laid out in one scrolling column.
    private func scrolling(_ source: String = Support.longSong(lines: 48, perSection: 6))
        -> LayoutPlan
    {
        plan(Self.model(source, chordBeside: false)).0
    }

    @Test
    func `the neck follows the reading line within the current pass`() throws {
        let plan = scrolling()
        #expect(plan.needsScroll)
        let top = try #require(StagePasses.chord(at: 0, plan: plan, pinned: nil))
        // At the top the reading line (28% down) is past the first rows of verse 1.
        let line = StagePasses.readLine(offset: 0, plan: plan)
        let chords = StagePasses.placedChords(in: plan)
        let expected = try #require(chords.last { $0.pass == 0 && $0.y <= line })
        #expect(top == expected)
        #expect(!top.dimmed)

        for offset in [plan.overflow / 2, plan.overflow] {
            let current = try #require(StagePasses.current(in: plan, offset: offset, pinned: nil))
            let chord = try #require(StagePasses.chord(at: offset, plan: plan, pinned: nil))
            #expect(chord.pass == current)
            let readLine = StagePasses.readLine(offset: offset, plan: plan)
            #expect(chord.y <= readLine)
        }
        // At the bottom it is the song's last chord.
        #expect(StagePasses.chord(at: plan.overflow, plan: plan, pinned: nil)?.text == "D")
    }

    @Test
    func `across a pass boundary the neck takes the new pass's first chord`() throws {
        let plan = scrolling()
        let second = plan.passes[1]
        // Find an offset whose reading line sits exactly on pass 2's top.
        let offset = try #require(stride(from: 0.0, through: plan.overflow, by: 0.5).first {
            StagePasses.readLine(offset: $0, plan: plan) >= second.top
        })
        let chord = try #require(StagePasses.chord(at: offset, plan: plan, pinned: nil))
        #expect(chord.pass == 1)
        #expect(chord == StagePasses.placedChords(in: plan).first { $0.pass == 1 })
    }

    @Test
    func `a fitting song and a two-column plan show the current pass's first chord`() throws {
        let fitting = plan(
            Self.model(
                "{start_of_verse}\n[A]One [B]two\n{end_of_verse}\n{start_of_chorus}\n"
                    + "[E]Three [F#m]four\n{end_of_chorus}",
                chordBeside: false,
            ),
            viewport: LayoutSize(width: 900, height: 700),
            columns: nil,
        ).0
        #expect(!fitting.needsScroll)
        #expect(StagePasses.chord(at: 0, plan: fitting, pinned: nil)?.text == "A")
        #expect(StagePasses.chord(at: 0, plan: fitting, pinned: 1)?.text == "E")

        let twoColumns = plan(
            Self.model(Support.longSong(lines: 24, perSection: 6), chordBeside: false),
            viewport: LayoutSize(width: 1400, height: 500),
            columns: 2,
            minLyricSize: 22,
        ).0
        #expect(twoColumns.columns.count == 2)
        let pass = try #require(StagePasses.current(in: twoColumns, offset: 0, pinned: 3))
        #expect(pass == 3)
        #expect(StagePasses.chord(at: 0, plan: twoColumns, pinned: 3)
            == StagePasses.placedChords(in: twoColumns).first { $0.pass == 3 })
        #expect(StagePasses.chord(at: 0, plan: twoColumns, pinned: nil)?.pass == 0)
    }

    @Test
    func `a no-chord keeps the previous chord, dimmed`() throws {
        let plan = plan(
            Self.model(
                "{start_of_verse}\n[G]One two\n[N.C.]Three four\n{end_of_verse}\n"
                    + "{start_of_chorus}\n[N.C.]Five\n[C]Six\n{end_of_chorus}",
                chordBeside: false,
            ),
            viewport: LayoutSize(width: 900, height: 700),
            columns: nil,
        ).0
        // Pass 2 opens on N.C.: the verse's G stays, dimmed.
        let chord = try #require(StagePasses.chord(at: 0, plan: plan, pinned: 1))
        #expect(chord.text == "G")
        #expect(chord.dimmed)
        #expect(chord.note == "G")
        #expect(PlacedChordRef(pass: 0, text: "5 \u{00B7} D", kind: .chord, y: 0).note == "D")
    }

    @Test
    func `the neck window for EADG home 3 is frets 2 to 6 and shifts to the suggestion`() {
        let home = 3
        #expect(BassFretboard.window(home: home, including: nil) == 2 ... 6)
        let em = BassFretboard.suggested(
            PitchClassFixture.eNote,
            home: home,
            tuning: .bassStandard4,
        )
        #expect(BassFretboard.window(home: home, including: em) == 0 ... 4)
    }
}

/// Pitch classes the tables name.
private enum PitchClassFixture {
    static let eNote = SongKey(parsing: "E")?.tonic.pitchClass ?? .init(4)
}
