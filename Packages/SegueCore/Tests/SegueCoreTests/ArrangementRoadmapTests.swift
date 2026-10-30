import ChordPro
@testable import Library
import Testing

/// The typed roadmap (P8-3 section 6.5): tokens per song, format with the counting rule,
/// parse with its errors, and `parse(format(p)) == p`.
struct ArrangementRoadmapTests {
    /// Three choruses whose words differ.
    static let differing = """
    {title: Differing}

    {start_of_intro: Intro}
    [G] [C]
    {end_of_intro}

    {start_of_verse: Verse 1}
    [G]First verse
    {end_of_verse}

    {start_of_chorus}
    [C]Harbour lights, call me back
    {end_of_chorus}

    {start_of_verse: Verse 2}
    [G]Second verse
    {end_of_verse}

    {start_of_chorus}
    [C]Harbour lights, carry me home
    {end_of_chorus}

    {start_of_bridge}
    [Em]Bridge line
    {end_of_bridge}

    {start_of_chorus}
    [C]Harbour lights, one more time
    {end_of_chorus}

    {start_of_outro: Outro}
    [G]Fade
    {end_of_outro}
    """

    /// Loose lines before the first section and after Verse 2, and an Intro / Instrumental
    /// clash.
    static let loose = """
    {title: Loose}

    [G]Count it in

    {start_of_intro: Intro}
    [G] [C]
    {end_of_intro}

    {start_of_verse: Verse 1}
    [G]First verse
    {end_of_verse}

    {start_of_verse: Verse 2}
    [G]Second verse
    {end_of_verse}

    [D]Hold this one

    {start_of_bridge: Instrumental}
    [Em] [C]
    {end_of_bridge}

    {start_of_chorus: Pre-Chorus}
    [C]Climbing up
    {end_of_chorus}

    {start_of_chorus: Chorus 2}
    [C]Top of the hill
    {end_of_chorus}
    """

    static func units(_ source: String) -> [SongSectionUnit] {
        SongSections.units(of: ChordProParser.parse(source).0)
    }

    static func pass(_ unit: SongSectionUnit, _ mode: PassMode = .full) -> ArrangementPass {
        ArrangementPass(anchor: unit.anchor, fingerprint: unit.fingerprint, mode: mode)
    }

    // MARK: Tokens

    @Test
    func `tokens are initials with numbers, clashes extend and loose lines follow a part`() {
        #expect(ArrangementRoadmap.tokens(Self.units(Self.differing)).map(\.text)
            == ["I", "V1", "C", "V2", "B", "O"])
        let loose = ArrangementRoadmap.tokens(Self.units(Self.loose))
        #expect(loose.map(\.text) == ["L", "I", "V1", "V2", "V2+", "IN", "PC", "C2"])
        #expect(loose.map(\.title) == [
            "Lead-in", "Intro", "Verse 1", "Verse 2", "After Verse 2", "Instrumental",
            "Pre-Chorus", "Chorus 2",
        ])
        // The {chorus} song: one token for the three choruses, the loose comment after the
        // last one is C+.
        let repeats = ArrangementRoadmap.tokens(SlotArrangementTests.units())
        #expect(repeats.map(\.text) == ["I", "V1", "C", "V2", "B", "C+"])
        #expect(repeats[2].units == [2, 4, 6])
    }

    @Test
    func `a second loose block and a non-Latin label get their own tokens`() throws {
        let verse = SectionRef(label: "Verse 2", occurrence: 1)
        func unit(_ index: Int, _ anchor: SectionAnchor, _ title: String) -> SongSectionUnit {
            SongSectionUnit(
                index: index,
                anchor: anchor,
                fingerprint: "f\(index)",
                legacyFingerprint: "f\(index)",
                title: title,
                kind: nil,
                isRepeat: false,
            )
        }
        let units = [
            unit(0, .section(verse), "Verse 2"),
            unit(1, .loose(after: verse, block: 1), "After Verse 2"),
            unit(2, .loose(after: verse, block: 2), "After Verse 2"),
            unit(3, .section(SectionRef(label: "अंतरा", occurrence: 1)), "अंतरा"),
            unit(4, .section(SectionRef(label: "अस्थायी", occurrence: 1)), "अस्थायी"),
        ]
        // A Devanagari label's first character is a whole grapheme ("अं" with its anusvara).
        #expect(ArrangementRoadmap.tokens(units).map(\.text) == ["V2", "V2+", "V2+2", "अं", "अ"])
        let passes = units.map { Self.pass($0) }
        #expect(ArrangementRoadmap.format(passes, units: units) == "V2 V2+ V2+2 अं अ")
        #expect(try ArrangementRoadmap.parse("v2 v2+2 अ", units: units).get()
            == [passes[0], passes[2], passes[4]])
    }

    // MARK: Format

    @Test
    func `the song as written formats with bare tokens; pins, modes and skips are written`() {
        let units = Self.units(Self.differing)
        let full = SlotArrangement.fullSong(units).passes
        #expect(ArrangementRoadmap.format(full, units: units) == "I V1 C V2 C B C O")
        let chorus = units.filter { $0.title == "Chorus" }
        let passes = [
            Self.pass(units[0], .chordsOnly),
            Self.pass(units[1]),
            Self.pass(chorus[2]),
            Self.pass(chorus[1]),
            Self.pass(units[5], .skip),
            Self.pass(chorus[2]),
            Self.pass(chorus[2]),
            Self.pass(units[7], .firstLine),
        ]
        #expect(ArrangementRoadmap.format(passes, units: units) == "I:CH V1 C#3 C#2 -B C C O:1")
    }

    // MARK: Parse

    @Test
    func `parse ignores case, takes commas, expands repeats and accepts :f`() throws {
        let units = Self.units(Self.differing)
        let chorus = units.filter { $0.title == "Chorus" }
        let parsed = try ArrangementRoadmap.parse("i:ch, v1 cx2  -b C×2 c#1:F o:1", units: units)
            .get()
        #expect(parsed == [
            Self.pass(units[0], .chordsOnly),
            Self.pass(units[1]),
            Self.pass(chorus[0]),
            Self.pass(chorus[0]),
            Self.pass(units[5], .skip),
            Self.pass(chorus[1]),
            Self.pass(chorus[1]),
            Self.pass(chorus[0]),
            Self.pass(units[7], .firstLine),
        ])
        // The counting rule caps at the last chorus: an extended ending.
        let ending = try ArrangementRoadmap.parse("C C C C C:CHx2", units: units).get()
        #expect(ending.map(\.anchor) == [0, 1, 2, 2, 2, 2].map { chorus[$0].anchor })
        #expect(ending.map(\.mode) == [.full, .full, .full, .full, .chordsOnly, .chordsOnly])
    }

    @Test(arguments: [
        ("I V1 Q C", "\"Q\" is not a part. Parts: I V1 C V2 B O."),
        ("C#4", "C#4: the song has 3 Choruses."),
        ("V1#2", "V1#2: the song has 1 Verse 1."),
        ("-I -V1", "At least one part plays."),
        ("C:x", "\"C:x\" - modes are :ch and :1."),
        ("Cx12", "\"Cx12\" - repeat a pass x2 to x9."),
        ("Cx9 C:1x9 Ox9 Bx9 V1x9 V2x9", "A slot can have up to 48 passes."),
    ])
    func `each error reads verbatim`(text: String, message: String) {
        let result = ArrangementRoadmap.parse(text, units: Self.units(Self.differing))
        guard case let .failure(error) = result else {
            Issue.record("\(text) parsed")
            return
        }
        #expect(error.message == message)
    }

    @Test
    func `an empty roadmap is its own error with no message`() {
        let result = ArrangementRoadmap.parse("  , ", units: Self.units(Self.differing))
        #expect(result == .failure(.empty))
        #expect(RoadmapError.empty.message.isEmpty)
    }

    @Test
    func `up to 48 passes parse`() throws {
        let units = Self.units(Self.differing)
        let text = Array(repeating: "Cx8", count: 6).joined(separator: " ")
        #expect(try ArrangementRoadmap.parse(text, units: units).get().count == 48)
    }

    // MARK: Round trip

    @Test(arguments: [differing, loose, SlotArrangementTests.song])
    func `parse(format(p)) == p for generated pass lists`(source: String) throws {
        let units = Self.units(source)
        var random = SplitMix(seed: 0x5EC0E)
        for _ in 0 ..< 300 {
            let length = Int(random.next() % 14) + 1
            var passes = (0 ..< length).map { _ in
                let unit = units[Int(random.next() % UInt64(units.count))]
                let mode = PassMode.allCases[Int(random.next() % 4)]
                return Self.pass(unit, mode)
            }
            if !passes.contains(where: \.isShown) {
                passes[0].mode = .full
            }
            let text = ArrangementRoadmap.format(passes, units: units)
            #expect(try ArrangementRoadmap.parse(text, units: units).get() == passes, "\(text)")
        }
    }
}

/// A seeded generator, so the property test is the same on every run.
private struct SplitMix {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
