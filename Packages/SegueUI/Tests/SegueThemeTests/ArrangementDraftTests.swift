import ChordPro
import Library
@testable import SegueUI
import Testing

/// The Arrange Sections lane (P8-3 section 7): chips from passes, every edit with its
/// selection and undo name, refusals, the counting rule, move semantics, pass numbers and
/// the builder texts. Pure, no app.
struct ArrangementDraftTests {
    /// Verse 1, Chorus, Verse 2, a `{chorus}` repeat, Bridge, a `{chorus}` repeat.
    static let song = """
    {title: Harbor Lights}

    {start_of_verse: Verse 1}
    [G]Lanterns on the water
    {end_of_verse}

    {start_of_chorus}
    [C]Hold on, harbor lights
    {end_of_chorus}

    {start_of_verse: Verse 2}
    [G]Salt upon my collar
    {end_of_verse}

    {chorus}

    {start_of_bridge}
    [Em]Somewhere past the breakwater
    {end_of_bridge}

    {chorus}
    """

    static let units = SongSections.units(of: ChordProParser.parse(song).0)

    static func pass(_ index: Int, _ mode: PassMode = .full) -> ArrangementPass {
        ArrangementPass(
            anchor: units[index].anchor,
            fingerprint: units[index].fingerprint,
            mode: mode,
        )
    }

    static func draft(_ passes: [ArrangementPass]?) -> ArrangementDraft {
        ArrangementDraft(
            arrangement: passes.map {
                SlotArrangement(passes: $0, knownParts: KnownPart.all(units))
            },
            units: units,
        )
    }

    /// The passes an edit saves, as part indices and modes.
    static func lane(_ result: ArrangementDraft.Result) -> String {
        result.arrangement.passes.map { pass in
            let index = units.firstIndex { $0.anchor.matches(pass.anchor) } ?? -1
            return pass.mode == .full ? "\(index)" : "\(index):\(pass.mode.rawValue)"
        }.joined(separator: " ")
    }

    static func applied(
        _ draft: ArrangementDraft,
        _ edit: ArrangementDraft.Edit,
        selection: Int = 0,
    ) throws -> ArrangementDraft.Result {
        try draft.apply(edit, selection: selection).get()
    }

    /// An edit, the selection it runs with, and the lane, selection and undo name it gives.
    struct EditCase {
        var edit: ArrangementDraft.Edit
        var selection: Int
        var lane: String
        var selected: Int
        var name: String

        init(
            _ edit: ArrangementDraft.Edit,
            _ selection: Int,
            _ lane: String,
            _ selected: Int,
            _ name: String,
        ) {
            self.edit = edit
            self.selection = selection
            self.lane = lane
            self.selected = selected
            self.name = name
        }
    }

    static func check(_ draft: ArrangementDraft, _ item: EditCase) throws {
        let result = try applied(draft, item.edit, selection: item.selection)
        #expect(lane(result) == item.lane, "\(item.edit)")
        #expect(result.selection == item.selected, "\(item.edit)")
        #expect(result.actionName == item.name, "\(item.edit)")
        #expect(result.arrangement.knownParts == KnownPart.all(units))
    }

    // MARK: Init

    @Test
    func `a full-song slot is every part once; saved passes, missing and new parts`() {
        let full = Self.draft(nil)
        #expect(!full.isCustom)
        #expect(full.chips.map(\.unit.index) == [0, 1, 2, 3, 4, 5])
        #expect(full.chips.map(\.title) == [
            "Verse 1", "Chorus", "Verse 2", "Chorus", "Bridge", "Chorus",
        ])
        #expect(full.roadmap == "V1 C V2 C B C")
        #expect(full.groups.map(\.title) == ["Verse 1", "Chorus", "Verse 2", "Bridge"])

        // A pass for a part that is gone is missing; a part the arrangement never knew is new.
        let gone = ArrangementPass(
            anchor: .section(SectionRef(label: "Verse 3", occurrence: 1)),
            fingerprint: "00000000",
        )
        let saved = SlotArrangement(
            passes: [Self.pass(0), gone, Self.pass(1, .chordsOnly)],
            knownParts: KnownPart.all(Array(Self.units.prefix(4))),
        )
        let draft = ArrangementDraft(arrangement: saved, units: Self.units)
        #expect(draft.isCustom)
        #expect(draft.isOutOfDate)
        #expect(draft.chips.map(\.unit.index) == [0, 1])
        #expect(draft.chips.map(\.mode) == [.full, .chordsOnly])
        #expect(draft.missing == [gone])
        #expect(draft.missingNames == "Verse 3")
        #expect(draft.newParts.map(\.name) == ["Bridge", "Chorus 3rd"])
        #expect(draft.groups.map(\.isNew) == [false, true, false, true])
    }

    // MARK: Edits

    @Test
    func `every edit returns the lane, the selection and its undo name`() throws {
        let draft = Self.draft(nil)
        let cases = [
            EditCase(.insert(unit: 4, at: 2), 0, "0 1 4 2 3 4 5", 2, "Add Pass"),
            EditCase(.insertGroup(1, after: 5), 0, "0 1 2 3 4 5 5", 6, "Add Pass"),
            EditCase(.duplicate(1), 1, "0 1 1 2 3 4 5", 2, "Duplicate Pass"),
            EditCase(.copy(0, to: 6), 0, "0 1 2 3 4 5 0", 6, "Duplicate Pass"),
            EditCase(.playAgainAtEnd(3), 3, "0 1 2 3 4 5 3", 6, "Play Again at End"),
            EditCase(.remove(4), 4, "0 1 2 3 5", 4, "Remove Pass"),
            EditCase(.remove(5), 5, "0 1 2 3 4", 4, "Remove Pass"),
            EditCase(.move(from: 0, to: 6), 0, "1 2 3 4 5 0", 5, "Move Pass"),
            EditCase(.move(from: 5, to: 0), 5, "5 0 1 2 3 4", 0, "Move Pass"),
            EditCase(.setMode(0, .chordsOnly), 0, "0:chords 1 2 3 4 5", 0, "Show Chords Only"),
            EditCase(.setMode(5, .firstLine), 5, "0 1 2 3 4 5:first", 5, "Show First Line"),
            EditCase(.toggleSkip(4), 4, "0 1 2 3 4:skip 5", 4, "Skip Pass"),
            EditCase(.replace([Self.pass(4), Self.pass(1)]), 3, "4 1", 1, "Edit Roadmap"),
            EditCase(.update, 0, "0 1 2 3 4 5", 0, "Update Arrangement"),
            EditCase(.setLength(160), 0, "0 1 2 3 4 5", 0, "Set Slot Length"),
        ]
        for item in cases {
            try Self.check(draft, item)
        }
        // Skipped back to Full is "Play Pass"; a playing copy at the end of a skipped pass.
        let skipped = Self.draft([Self.pass(0), Self.pass(4, .skip)])
        #expect(try Self.applied(skipped, .toggleSkip(1)).actionName == "Play Pass")
        #expect(try Self.lane(Self.applied(skipped, .playAgainAtEnd(1))) == "0 4:skip 4")
        #expect(try Self.lane(Self.applied(skipped, .duplicate(1))) == "0 4:skip 4:skip")
        #expect(try Self.applied(draft, .setLength(95)).arrangement.length == 95)
    }

    @Test
    func `the last playing pass and the pass limit are refused, no-ops change nothing`() {
        let lone = Self.draft([Self.pass(0), Self.pass(4, .skip)])
        #expect(lone.apply(.remove(0), selection: 0) == .failure(.lastPlayingPass))
        #expect(lone.apply(.toggleSkip(0), selection: 0) == .failure(.lastPlayingPass))
        #expect(lone.apply(.setMode(0, .skip), selection: 0) == .failure(.lastPlayingPass))
        #expect(lone.apply(.replace([Self.pass(0, .skip)]), selection: 0)
            == .failure(.lastPlayingPass))
        // The skipped pass can go.
        #expect((try? lone.apply(.remove(1), selection: 1).get()) != nil)

        let full = Self.draft(Array(repeating: Self.pass(1), count: SlotArrangement.maxPasses))
        for edit: ArrangementDraft.Edit in [
            .insert(unit: 0, at: 0), .insertGroup(0, after: 0), .duplicate(0), .copy(0, to: 3),
            .playAgainAtEnd(0),
            .replace(Array(repeating: Self.pass(0), count: SlotArrangement.maxPasses + 1)),
        ] {
            #expect(full.apply(edit, selection: 0) == .failure(.tooManyPasses), "\(edit)")
        }
        #expect(ArrangementDraft.Refusal.tooManyPasses.message
            == "A slot can have up to 48 passes")

        let draft = Self.draft(nil)
        #expect(draft.apply(.setMode(0, .full), selection: 0) == .failure(.nothingChanged))
        #expect(draft.apply(.move(from: 2, to: 2), selection: 2) == .failure(.nothingChanged))
        #expect(draft.apply(.move(from: 2, to: 3), selection: 2) == .failure(.nothingChanged))
        #expect(draft.apply(.replace(draft.passes), selection: 0) == .failure(.nothingChanged))
        #expect(draft.apply(.remove(9), selection: 0) == .failure(.nothingChanged))
    }

    @Test
    func `the counting rule picks the chorus after the nearest earlier one`() throws {
        let draft = Self.draft(nil)
        let chorus = 1
        // Between Verse 2 (lane 2) and the Bridge: the chorus after Chorus 1st is the 2nd.
        let between = Self.draft([Self.pass(0), Self.pass(1), Self.pass(2), Self.pass(4)])
        #expect(between.occurrence(of: chorus, after: 2)?.name == "Chorus 2nd")
        // After the last chorus: the last again.
        #expect(draft.occurrence(of: chorus, after: 5)?.name == "Chorus 3rd")
        // No earlier chorus: the first.
        #expect(draft.occurrence(of: chorus, after: 0)?.name == "Chorus 1st")
        #expect(try Self.lane(Self.applied(between, .insertGroup(chorus, after: 2)))
            == "0 1 2 3 4")
    }

    @Test
    func `moves follow the splice rule for every drop index`() throws {
        let draft = Self.draft([Self.pass(0), Self.pass(1), Self.pass(2)])
        // Drop index d is "before the pass at d"; d == count is the end.
        #expect(try Self.lane(Self.applied(draft, .move(from: 0, to: 2))) == "1 0 2")
        #expect(try Self.lane(Self.applied(draft, .move(from: 0, to: 3))) == "1 2 0")
        #expect(try Self.lane(Self.applied(draft, .move(from: 2, to: 1))) == "0 2 1")
        #expect(draft.apply(.move(from: 1, to: 1), selection: 1) == .failure(.nothingChanged))
        #expect(draft.apply(.move(from: 1, to: 2), selection: 1) == .failure(.nothingChanged))
    }

    // MARK: Numbers and texts

    @Test
    func `chip numbers are the stage's pass numbers; ordinals only when content differs`() {
        let passes = [Self.pass(1), Self.pass(1, .skip), Self.pass(3), Self.pass(5, .chordsOnly)]
        let draft = Self.draft(passes)
        let stage = PassNaming.names(passes, units: Self.units)
        #expect(draft.chips.map(\.name) == stage)
        #expect(draft.chips.map(\.number) == ["1 of 3", nil, "2 of 3", "3 of 3"])
        // The repeats write out the same chorus: no ordinal.
        #expect(draft.chips.allSatisfy { !$0.showsOrdinal })

        let differing = SongSections.units(of: ChordProParser.parse("""
        {start_of_chorus}
        [C]First words
        {end_of_chorus}
        {start_of_chorus}
        [C]Other words
        {end_of_chorus}
        """).0)
        let other = ArrangementDraft(arrangement: nil, units: differing)
        #expect(other.chips.map(\.title) == ["Chorus 1st", "Chorus 2nd"])
    }

    @Test
    func `the mark, the popover row and the footer say what the slot plays`() {
        let passes = [
            Self.pass(0, .chordsOnly), Self.pass(1), Self.pass(2), Self.pass(3),
            Self.pass(4, .skip), Self.pass(5), Self.pass(5, .firstLine),
        ]
        let arrangement = SlotArrangement(passes: passes)
        #expect(ArrangementDraft.markText(arrangement, units: Self.units)
            == "Custom · V1:CH C V2 C -B C C:1")
        #expect(ArrangementDraft.countsText(arrangement) == "7 passes, 1 skipped")
        #expect(ArrangementDraft.popoverText(arrangement, units: Self.units)
            == "Custom: 7 passes, 1 skipped…")
        #expect(ArrangementDraft.popoverText(nil, units: Self.units) == "Full song…")
        #expect(ArrangementDraft.popoverText(arrangement, units: nil) == "Custom…")
        let gone = SlotArrangement(passes: [ArrangementPass(
            anchor: .section(SectionRef(label: "Coda", occurrence: 1)),
        )])
        #expect(ArrangementDraft.popoverText(gone, units: Self.units) == "Out of date: full song…")
        #expect(Self.draft(passes).footerCounts == "6 passes play · 1 skipped")
        #expect(Self.draft([Self.pass(0)]).footerCounts == "1 pass plays")
        #expect(ArrangementDraft.countsText(SlotArrangement(passes: [Self.pass(0)])) == "1 pass")
    }
}
