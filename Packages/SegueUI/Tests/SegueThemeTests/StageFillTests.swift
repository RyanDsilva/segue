import AppKit
import ChordPro
import Diagrams
import Editing
import Library
import LiveLayout
import MusicTheory
@testable import SegueUI
import Shows
import Testing

/// Saved fills on a real stage (P8-7 section 14, R167 Q12, R168 Q8): names by default, a tab
/// fill as a block, `T` flips every fill to tab and back as a remembered user setting, in a
/// gig with no sound, the neck numbers the fill's path, and the status line names `T`.
extension StageWindowSuites {
    @MainActor
    @Suite(.serialized)
    struct StageFillTests {
        static let song = """
        {title: Fills}
        {key: G}
        {start_of_verse}
        [G]Hello there [C]my friend [D]and so
        {end_of_verse}
        {start_of_chorus}
        [C]Sing it [D]loud and [G]clear
        {end_of_chorus}

        """

        /// The verse's G -> C -> D as names (G A over G, D E over C) and the chorus's C -> D
        /// as tab (D over C).
        static func parts(_ song: SongRecord) throws -> [Part] {
            let sections = SongSummary.renderModel(song).sections
            let units = SongSections.units(of: song.document)
            func anchor(_ section: Int, _ chord: Int) throws -> ChordAnchor {
                try #require(ChordAnchors.anchor(
                    at: ChordPosition(section: section, chord: chord),
                    units: units,
                    sections: sections,
                ))
            }
            return try [
                Part(
                    span: SpanAnchor(start: anchor(0, 0), end: anchor(0, 2), spanBass: [
                        "G", "C", "D",
                    ]),
                    events: [
                        PartEvent(chord: 0, at: 960, len: 480, deg: 0),
                        PartEvent(chord: 0, at: 1440, len: 480, deg: 2),
                        PartEvent(chord: 1, at: 960, len: 480, deg: 2),
                        PartEvent(chord: 1, at: 1440, len: 480, deg: 4),
                    ],
                ),
                Part(
                    span: SpanAnchor(start: anchor(1, 0), end: anchor(1, 1), spanBass: ["C", "D"]),
                    show: .tab,
                    events: [PartEvent(chord: 0, at: 1440, len: 480, deg: 2)],
                ),
            ]
        }

        /// A run whose first song carries the two fills, with the bass-note view and
        /// walk-ups on.
        static func run() async throws -> MetronomeRun {
            let run = try await MetronomeRun(
                songs: [song, "{title: Two}\n[G]La [C]la\n"],
                recordsAnalytics: true,
            )
            let session = try #require(run.app.session)
            guard case let .song(id) = try #require(run.setlist.entries.first).kind else {
                Issue.record("the first entry is a song")
                return run
            }
            let record = try #require(try await session.library.store.song(id: id))
            _ = try await session.library.store.updateParts(id: id, parts(record))
            run.app.instrumentProfile.update {
                $0.bassNotes = true
                $0.walkUps = .everyChange
            }
            return run
        }

        static func rows(_ plan: LayoutPlan?) -> [LayoutRow] {
            let blocks: [LayoutBlock] = (plan?.columns ?? []).flatMap(\.blocks)
            return blocks.flatMap(\.allRows)
        }

        static func fillRuns(_ plan: LayoutPlan?) -> [String] {
            let runs: [PlacedText] = rows(plan).flatMap(\.chords)
            return runs.filter { $0.role == .approach && $0.fill != nil }.map(\.text)
        }

        static func tabs(_ plan: LayoutPlan?) -> [PlacedFillTab] {
            rows(plan).compactMap(\.fillTab)
        }

        @Test
        func `names by default, a tab fill as a block, and t flips all in a silent gig`(
        ) async throws {
            let run = try await Self.run()
            let live = try await run.start(.gig)
            let store = run.app.instrumentProfile
            #expect(Self.fillRuns(live.plan) == ["G A", "D E \u{203A}"])
            #expect(Self.tabs(live.plan).count == 1)
            #expect(Self.tabs(live.plan).first?.block.notes.map(\.name) == ["D", "D"])
            #expect(KeyHelp.statusHints(
                live.context.bindings,
                kind: live.kind,
                hasFills: live.currentSongHasFills,
            ).contains("T fills as tab"))

            live.dispatch(.toggleFillTab)
            #expect(store.profile.fillsAsTab)
            #expect(live.indicator == "Fills as tab")
            #expect(Self.fillRuns(live.plan).isEmpty)
            #expect(Self.tabs(live.plan).count == 2)
            // Remembered like `b`: the stored profile carries it.
            #expect(InstrumentProfileStore.load(from: run.env.defaults).fillsAsTab)
            #expect(run.analytics?.features.contains("fillTab") == true)

            live.dispatch(.toggleFillTab)
            #expect(!store.profile.fillsAsTab)
            #expect(live.indicator == "Fills as names")
            #expect(Self.fillRuns(live.plan) == ["G A", "D E \u{203A}"])
            // Display only: nothing was ever made to sound.
            #expect(run.sounds.made == 0)
            #expect(run.app.dependencies.audio.isBlocked)

            // A song without fills only flashes.
            live.dispatch(.next)
            _ = try await run.env.waitFor { live.positionText == "2 of 2" ? true : nil }
            #expect(!live.currentSongHasFills)
            live.dispatch(.toggleFillTab)
            #expect(live.indicator == "No fills in this song")
            #expect(!store.profile.fillsAsTab)
            #expect(!KeyHelp.statusHints(live.context.bindings, kind: live.kind).contains {
                $0.hasSuffix("fills as tab")
            })
            try await run.end(live)
        }

        @Test
        func `t works in a rehearsal and the neck shows the fill path`() async throws {
            let run = try await Self.run()
            let live = try await run.start(.rehearsal)
            // The verse's G is at the reading line: its fill notes G A are 1 and 2 of 4.
            let neck = try #require(live.bassNeck(at: run.env.clock.now()))
            #expect(neck.note == "G")
            #expect(neck.walkUp.map(\.number) == [1, 2])
            #expect(neck.fillTotal == 4)
            #expect(neck.accessibilityValue.hasSuffix("fill: 4 notes"))
            live.dispatch(.toggleFillTab)
            #expect(run.app.instrumentProfile.profile.fillsAsTab)
            #expect(Self.tabs(live.plan).count == 2)
            // As a tab the chord draws no names, but the neck still shows the fill's path.
            #expect(live.bassNeck(at: run.env.clock.now())?.walkUp.map(\.number) == [1, 2])
            try await run.end(live)
        }
    }
}
