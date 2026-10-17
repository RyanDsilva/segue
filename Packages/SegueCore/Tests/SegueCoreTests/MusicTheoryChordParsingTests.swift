import MusicTheory
import Testing
import Tonic

/// Chord-symbol parsing: real-world spellings map to the right pitch content (including
/// chords Tonic cannot model), and the parser is strict enough that romanized Hindi lyric
/// words never read as chords.
struct MusicTheoryChordParsingTests {
    struct SuffixCase: Sendable, CustomTestStringConvertible {
        let suffix: String
        let intervals: [Int]
        /// Whether Tonic has a matching `ChordType`.
        let tonic: Bool

        var testDescription: String {
            "\"\(suffix)\""
        }
    }

    static let suffixes: [SuffixCase] = [
        SuffixCase(suffix: "", intervals: [0, 4, 7], tonic: true),
        SuffixCase(suffix: "m", intervals: [0, 3, 7], tonic: true),
        SuffixCase(suffix: "min", intervals: [0, 3, 7], tonic: true),
        SuffixCase(suffix: "-7", intervals: [0, 3, 7, 10], tonic: true),
        SuffixCase(suffix: "m7", intervals: [0, 3, 7, 10], tonic: true),
        SuffixCase(suffix: "7", intervals: [0, 4, 7, 10], tonic: true),
        SuffixCase(suffix: "maj7", intervals: [0, 4, 7, 11], tonic: true),
        SuffixCase(suffix: "M7", intervals: [0, 4, 7, 11], tonic: true),
        SuffixCase(suffix: "Δ7", intervals: [0, 4, 7, 11], tonic: true),
        SuffixCase(suffix: "maj9", intervals: [0, 4, 7, 11, 14], tonic: true),
        SuffixCase(suffix: "9", intervals: [0, 4, 7, 10, 14], tonic: true),
        SuffixCase(suffix: "m9", intervals: [0, 3, 7, 10, 14], tonic: true),
        SuffixCase(suffix: "11", intervals: [0, 4, 7, 10, 14, 17], tonic: true),
        SuffixCase(suffix: "13", intervals: [0, 4, 7, 10, 14, 17, 21], tonic: true),
        SuffixCase(suffix: "6", intervals: [0, 4, 7, 9], tonic: true),
        SuffixCase(suffix: "m6", intervals: [0, 3, 7, 9], tonic: true),
        SuffixCase(suffix: "6/9", intervals: [0, 4, 7, 9, 14], tonic: true),
        SuffixCase(suffix: "69", intervals: [0, 4, 7, 9, 14], tonic: true),
        SuffixCase(suffix: "add9", intervals: [0, 4, 7, 14], tonic: true),
        SuffixCase(suffix: "madd9", intervals: [0, 3, 7, 14], tonic: true),
        SuffixCase(suffix: "2", intervals: [0, 2, 4, 7], tonic: true),
        SuffixCase(suffix: "sus2", intervals: [0, 2, 7], tonic: true),
        SuffixCase(suffix: "sus4", intervals: [0, 5, 7], tonic: true),
        SuffixCase(suffix: "sus", intervals: [0, 5, 7], tonic: true),
        SuffixCase(suffix: "7sus4", intervals: [0, 5, 7, 10], tonic: true),
        SuffixCase(suffix: "13sus4", intervals: [0, 5, 7, 10, 14, 21], tonic: true),
        SuffixCase(suffix: "7(#9)", intervals: [0, 4, 7, 10, 15], tonic: true),
        SuffixCase(suffix: "7#9", intervals: [0, 4, 7, 10, 15], tonic: true),
        SuffixCase(suffix: "7(b9,#11)", intervals: [0, 4, 7, 10, 13, 18], tonic: true),
        SuffixCase(suffix: "maj7#11", intervals: [0, 4, 7, 11, 18], tonic: true),
        SuffixCase(suffix: "7b13", intervals: [0, 4, 7, 10, 20], tonic: true),
        SuffixCase(suffix: "m7b5", intervals: [0, 3, 6, 10], tonic: true),
        SuffixCase(suffix: "ø7", intervals: [0, 3, 6, 10], tonic: true),
        SuffixCase(suffix: "dim", intervals: [0, 3, 6], tonic: true),
        SuffixCase(suffix: "°7", intervals: [0, 3, 6, 9], tonic: true),
        SuffixCase(suffix: "dim7", intervals: [0, 3, 6, 9], tonic: true),
        SuffixCase(suffix: "aug", intervals: [0, 4, 8], tonic: true),
        SuffixCase(suffix: "+7", intervals: [0, 4, 8, 10], tonic: true),
        SuffixCase(suffix: "mmaj7", intervals: [0, 3, 7, 11], tonic: true),
        SuffixCase(suffix: "m(maj7)", intervals: [0, 3, 7, 11], tonic: true),
        SuffixCase(suffix: "mM7", intervals: [0, 3, 7, 11], tonic: true),
        SuffixCase(suffix: "5", intervals: [0, 7], tonic: false),
        SuffixCase(suffix: "7alt", intervals: [0, 4, 10, 13, 15, 18, 20], tonic: false),
    ]

    @Test(arguments: suffixes)
    func `suffix maps to intervals`(_ testCase: SuffixCase) throws {
        let token = ChordToken(parsing: "C" + testCase.suffix)
        let chord = try #require(token.chord, "C\(testCase.suffix) should parse")
        #expect(chord.symbol.formula.intervals == testCase.intervals)
        #expect(Set(chord.symbol.formula.essential).isSubset(of: chord.symbol.formula.intervals))
        #expect(chord.symbol.formula.essential.contains(0))
        #expect((chord.tonic != nil) == testCase.tonic)
        if let tonic = chord.tonic {
            let tonicPitches = Set(tonic.type.intervals.map { $0.semitones % 12 } + [0])
            #expect(tonicPitches == Set(testCase.intervals.map { $0 % 12 }))
        }
    }

    @Test
    func `symbols split root suffix and bass`() throws {
        // Chord text -> [root, suffix, bass].
        let cases: [(String, [String?])] = [
            ("F#m7b5", ["F#", "m7b5", nil]),
            ("Bbmaj9", ["Bb", "maj9", nil]),
            ("G/B", ["G", "", "B"]),
            ("C6/9", ["C", "6/9", nil]),
            ("Am7/G", ["A", "m7", "G"]),
            ("Bb/D", ["Bb", "", "D"]),
            ("F♯m", ["F#", "m", nil]),
            ("Cb", ["Cb", "", nil]),
        ]
        for (text, parts) in cases {
            let symbol = try #require(ChordToken(parsing: text).chord?.symbol, "\(text)")
            #expect([symbol.root.chartName, symbol.suffix, symbol.bass?.chartName] == parts)
        }
        let slash = try #require(ChordToken(parsing: "G/B").chord)
        #expect(slash.tones.bass == PitchClass(11))
        #expect(slash.tones.lowest == PitchClass(11))
        #expect(ChordToken(parsing: "C/C").chord?.tones.bass == nil)
    }

    @Test
    func `tokens keep their original text`() {
        #expect(ChordToken(parsing: " G ").original == " G ")
        #expect(ChordToken(parsing: " G ").chord?.symbol.text == "G")
        for noChord in ["N.C.", "NC", "N.C", "n.c.", "N/C"] {
            #expect(ChordToken(parsing: noChord) == .noChord(original: noChord))
        }
        for unknown in ["", " ", "H", "Cx", "C7/9", "Gmaj7maj7", "x", "C##", "Bbb", "c"] {
            #expect(ChordToken(parsing: unknown) == .unknown(UnknownChord(original: unknown)))
        }
    }

    /// Lyric words are never parsed as chords: only bracket contents reach `ChordToken`, and
    /// even there the parser is strict. These romanized Hindi words (from the fixture songs
    /// and common lyrics) must not read as chords; the chord-shaped ones ("Am", "Dm", "Ab")
    /// are real chord symbols and only ever become chords inside brackets.
    @Test(arguments: [
        "Bas", "Do", "Dil", "Ek", "Aaj", "Dard", "Gaana", "Chal", "Bhi", "Ga", "Badal", "Dekho",
        "Aao", "Baat", "Fir", "Geet", "Ek", "De", "Bin", "Atke", "Bhoole", "Galiyaan", "Aansu",
        "Daaman", "Gm", "Em",
    ])
    func `hindi lyric words are not chords`(_ word: String) {
        let isChordSymbol = ["Gm", "Em"].contains(word)
        #expect((ChordToken(parsing: word).chord != nil) == isChordSymbol)
    }

    /// Every bracketed chord in the fixture corpus parses (empty `[]` and `N.C.` aside), so
    /// nothing in the corpus falls back to an unknown chord.
    @Test(arguments: CorpusFixture.all)
    func `corpus chords parse`(_ fixture: CorpusFixture) {
        for token in fixture.tokens where !token.isEmpty {
            switch ChordToken(parsing: token) {
            case .chord, .noChord: break
            case .unknown: Issue.record("\(fixture.name): [\(token)] did not parse")
            }
        }
    }
}
