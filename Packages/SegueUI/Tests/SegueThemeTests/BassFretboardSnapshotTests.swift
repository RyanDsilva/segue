import ChordPro
import Diagrams
import Editing
import Library
import MusicTheory
@testable import SegueUI
import SwiftUI
import Testing

/// P8-4b snapshots (section 11.3): bass fretboard cells, a preview line with a walk-up run
/// and the walk-up popover, light and dark, written to `.build/screenshots/diagrams`.
extension DiagramSnapshotTests {
    static let bassSong = """
    {key: G}
    {start_of_verse}
    [G]Hello there [G/B]my friend [C]and [D]so
    {end_of_verse}
    {start_of_chorus}
    [Em]Sing it [Bdim]loud
    {end_of_chorus}

    """

    @MainActor
    static func bassModel(strings: Int) -> (RenderModel, SongDocument) {
        let (document, _) = ChordProParser.parse(bassSong)
        var profile = InstrumentProfile(playsBass: true, bassNotes: true, walkUps: .everyChange)
        profile.setStrings(strings)
        let options = DisplayOptions().withBass(profile)
        let model = RenderModel(document: document, options: options)
        return (BassLine.annotated(model, document: document, prefs: BassPrefs()), document)
    }

    @Test(arguments: schemes)
    @MainActor
    func `bass fretboard cells, a walk-up run and the picker render`(
        scheme: ColorScheme,
    ) throws {
        #expect(Theme.registerFonts())
        let (four, document) = Self.bassModel(strings: 4)
        let (five, _) = Self.bassModel(strings: 5)
        #expect(four.diagrams.allSatisfy { $0.bass != nil })
        #expect(four.diagrams.map { $0.bass?.note } == ["G", "B", "C", "D", "E", "B"])
        let strips = VStack(alignment: .leading, spacing: 16) {
            DiagramStripContent(
                diagrams: four.diagrams,
                instrument: .guitar,
                tuning: four.tuning,
                size: .compact,
                onCustomize: nil,
            )
            DiagramStripContent(
                diagrams: five.diagrams,
                instrument: .guitar,
                tuning: five.tuning,
                size: .regular,
                onCustomize: nil,
            )
            SongSheetView(sections: four.sections, style: .preview)
                .frame(width: 520)
        }
        try snapshot(strips, name: "bass-strip", scheme: scheme)

        let changes = BassLine.changes(four, document: document, prefs: BassPrefs())
        let first = try #require(changes.first)
        let picking = WalkUpPicking(
            isEnabled: true,
            details: { _ in WalkUpDetails(change: first, section: "Verse", feel: "Pop") },
            choose: { _, _ in },
            reset: { _ in },
        )
        let popover = WalkUpPopover(id: first.id, picking: picking) {}
            .background(Theme.color.surfaceAlt)
        try snapshot(popover, name: "walkup-popover", scheme: scheme)
    }

    /// The Walk-ups list with a saved walk-up that no longer matches (its rows sit in a scroll
    /// view, which the snapshot renderer leaves blank).
    @Test(arguments: schemes)
    @MainActor
    func `the walk-ups list renders`(scheme: ColorScheme) throws {
        #expect(Theme.registerFonts())
        let (four, document) = Self.bassModel(strings: 4)
        let changes = BassLine.changes(four, document: document, prefs: BassPrefs())
        let first = try #require(changes.first)
        let picking = WalkUpPicking(
            isEnabled: true,
            details: { _ in WalkUpDetails(change: first, section: "Verse", feel: "Pop") },
            choose: { _, _ in },
            reset: { _ in },
        )
        let stale = try #require(ChordAnchors.anchor(
            at: first.id.from,
            units: SongSections.units(of: document),
            sections: four.sections,
        ))
        let sections = four.sections
        let list = WalkUpsSheet(source: {
            WalkUpsSource(
                title: "Harbour Lights",
                changes: changes,
                sectionLabel: { SectionNotes.label(of: sections[$0]) ?? "Verse" },
                unmatched: [(
                    WalkUpPick(anchor: stale, to: "A", kind: .chromBelow, offsets: [-1]),
                    "Verse: G \u{2192} A, G#",
                )],
                feel: .rock,
                defaultFeel: .pop,
                scale: nil,
                defaultScale: .major,
                scales: FillMode.choices(for: SongKey(parsing: "G")),
                density: .off,
                readOnlyHelp: nil,
                picking: picking,
                setFeel: { _ in },
                setScale: { _ in },
                remove: { _ in },
            )
        })
        try snapshot(list, name: "walkups-sheet", scheme: scheme)
    }
}
