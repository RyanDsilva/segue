import ChordPro
import Editing
import Foundation
import Library
import Testing

/// Pass names and the gig log summary (P8-2 section 4.6 and 5.5): "Chorus 2/3" on the map
/// and the editor's chips, "2 of 3" in the gutter.
struct PassNamingTests {
    @Test
    func `the gig log summary merges runs and names the modes`() {
        let units = SlotArrangementTests.units()
        let arrangement = SlotArrangement(passes: [
            SlotArrangementTests.pass(units, "Intro", .chordsOnly),
            SlotArrangementTests.pass(units, "Verse 1"),
            SlotArrangementTests.pass(units, "Chorus 1st"),
            SlotArrangementTests.pass(units, "Bridge", .skip),
            SlotArrangementTests.pass(units, "Chorus 3rd"),
            SlotArrangementTests.pass(units, "Chorus 3rd"),
            SlotArrangementTests.pass(units, "After Chorus", .firstLine),
        ])
        #expect(arrangement.playedSummary
            == "Intro (chords), Verse 1, Chorus, Chorus 3rd x2, After Chorus (first line)")
    }

    @Test
    func `pass names number shown passes per label, written choruses and repeats alike`() {
        let units = SlotArrangementTests.units()
        let arrangement = SlotArrangement(passes: [
            SlotArrangementTests.pass(units, "Intro"),
            SlotArrangementTests.pass(units, "Chorus 1st"),
            SlotArrangementTests.pass(units, "Verse 2"),
            SlotArrangementTests.pass(units, "Chorus 2nd"),
            SlotArrangementTests.pass(units, "Bridge", .skip),
            SlotArrangementTests.pass(units, "Chorus 3rd", .chordsOnly),
            ArrangementPass(anchor: .section(SectionRef(label: "Coda", occurrence: 1))),
        ])
        let names = PassNaming.names(arrangement.passes, units: units)
        #expect(names.map { $0?.chipText } == [
            "Intro", "Chorus 1/3", "Verse 2", "Chorus 2/3", "Bridge", "Chorus 3/3", nil,
        ])
        #expect(names.map { $0?.badgeText } == [nil, "1 of 3", nil, "2 of 3", nil, "3 of 3", nil])
        // A skipped pass is named but neither numbered nor counted.
        #expect(names[4] == PassName(title: "Bridge", short: "B", number: nil, total: 0))
        // Labels group case-insensitively.
        let grouped = PassNaming.names(titles: ["Chorus", "chorus ", "Verse 1"], shown: [
            true, true, true,
        ])
        #expect(grouped.map(\.number) == [1, 2, nil])
        #expect(grouped.map(\.total) == [2, 2, 1])
    }

    @Test(arguments: [
        ("Verse 2", "V2"), ("Chorus", "C"), ("Bridge", "B"), ("Intro", "I"), ("Outro", "O"),
        ("Pre Chorus", "PC"), ("Pre-Chorus", "PC"), ("Lead-in", "Lead"),
        ("After Verse 2", "+V2"), ("Instrumental Break 3", "IB3"), ("Tag", "T"),
    ])
    func `short pass names`(title: String, short: String) {
        #expect(PassNaming.short(title) == short)
    }
}
