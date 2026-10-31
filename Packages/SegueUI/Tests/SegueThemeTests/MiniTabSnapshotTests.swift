import Diagrams
import MusicTheory
@testable import SegueUI
import SwiftUI
import Testing

/// P8-7d snapshots (section 16.3): the fill editor's mini tab on 4 and 5 strings, light and
/// dark, written to `.build/screenshots/diagrams` by `DiagramSnapshotTests`' renderer.
@MainActor
struct MiniTabSnapshotTests {
    /// E into A over a bar and the landing half bar: an accent, a slide, a ghost, a hammer-on,
    /// a staccato, then the landing root; on five strings it starts on the B string.
    static func miniTab(_ tuning: Tuning) -> MiniTabView {
        let five = tuning.strings.count == 5
        func note(
            _ tick: Int,
            _ string: Int,
            _ fret: Int,
            _ name: String,
            _ articulations: Set<Articulation> = [],
            landing: Bool = false,
        ) -> TabNote {
            TabNote(
                tick: tick,
                length: 240,
                position: FretPosition(string: string + (five ? 1 : 0), fret: fret),
                articulations: articulations,
                name: name,
                isLanding: landing,
            )
        }
        var notes = [
            note(0, 0, 0, "E", [.accent]),
            note(960, 1, 7, "E", [.slide]),
            note(1200, 1, 7, "E", [.ghost]),
            note(1440, 1, 9, "F#", [.hammer]),
            note(1680, 2, 6, "G#", [.staccato]),
            note(1920, 1, 0, "A", landing: true),
        ]
        if five {
            notes[0] = TabNote(
                tick: 0,
                length: 480,
                position: FretPosition(string: 0, fret: 5),
                articulations: [.accent],
                name: "E",
            )
        }
        return MiniTabView(
            notes: notes,
            chords: [(0, "E"), (1920, "A")],
            ticks: 0 ..< 2880,
            pulses: Array(stride(from: 0, to: 2880, by: 480)),
            bars: [0, 1920],
            tuning: tuning,
        )
    }

    @Test(arguments: DiagramSnapshotTests.schemes)
    func `the mini tab renders on four and five strings`(scheme: ColorScheme) throws {
        #expect(Theme.registerFonts())
        let four = Self.miniTab(.bassStandard4)
        let five = Self.miniTab(.bassStandard5)
        #expect(TabLayout.spoken(four.notes, tuning: four.tuning)
            == "Tab: E string accented 0, A string slide 7, ghost, hammer-on 9, "
            + "D string staccato 6, then A")
        #expect(MiniTabView.height(for: .bassStandard5) > MiniTabView.height(for: .bassStandard4))
        let stack = VStack(alignment: .leading, spacing: 20) {
            four.frame(width: 360)
            five.frame(width: 360)
        }
        try DiagramSnapshotTests().snapshot(stack, name: "mini-tab", scheme: scheme)
    }
}
