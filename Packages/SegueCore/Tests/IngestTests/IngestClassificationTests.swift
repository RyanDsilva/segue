import ChordPro
import Foundation
@testable import Ingest
import MusicTheory
import Testing

/// Unit tests for the tricky pure logic only: chord-line classification (with the stop
/// list), header parsing, junk rules and column alignment. Everything else is covered by
/// `IngestFixtureTests`.
struct IngestClassificationTests {
    struct LineCase: CustomTestStringConvertible, Sendable {
        var line: String
        var isChordLine: Bool
        var testDescription: String {
            "\(line) -> \(isChordLine ? "chords" : "lyric")"
        }
    }

    static let chordLineCases: [LineCase] = [
        LineCase(line: "G  D/F#  Em  C", isChordLine: true),
        LineCase(line: "Am  F  C  G", isChordLine: true),
        LineCase(line: "A", isChordLine: true),
        LineCase(line: "E  B  C#m  A  (x2)", isChordLine: true),
        LineCase(line: "| G  | C  | G  | D  |", isChordLine: true),
        LineCase(line: "Am               F", isChordLine: true),
        LineCase(line: "N.C.        G", isChordLine: true),
        LineCase(line: "G  D  Em  C  riff", isChordLine: true),
        // Romanized Hindi and English lyrics full of chord-like words.
        LineCase(line: "Main Am bas Do pal", isChordLine: false),
        LineCase(line: "Main Am bas Do pal ruk jaaun", isChordLine: false),
        LineCase(line: "Ab Na Hai Tu Me", isChordLine: false),
        LineCase(line: "Do pal, bas do pal", isChordLine: false),
        LineCase(line: "Ab A ki baari, B ka sawaal", isChordLine: false),
        LineCase(line: "A Am Ab E Em B", isChordLine: true),
        LineCase(line: "Am I the only one", isChordLine: false),
        LineCase(line: "A day in the life", isChordLine: false),
        LineCase(line: "Do", isChordLine: false),
        LineCase(line: "G riff", isChordLine: false),
        LineCase(line: "[G]Lyrics with inline chords", isChordLine: false),
    ]

    @Test(arguments: chordLineCases)
    func `chord lines are told from lyrics`(_ testCase: LineCase) {
        #expect(ChordLines.isChordLine(testCase.line) == testCase.isChordLine)
    }

    @Test(arguments: ["Main", "Bas", "Do", "Hai", "Na", "Tu", "Me", "A", "Am", "Ab", "do,", "BAS"])
    func `stop list holds romanized Hindi and English words`(_ word: String) {
        #expect(StopList.contains(word))
    }

    @Test(arguments: ["G", "C#m", "Dm7", "Fmaj7", "Bb", "Gsus4"])
    func `stop list never holds a plain chord name that is not a word`(_ chord: String) {
        #expect(!StopList.contains(chord))
    }

    @Test
    func `every stop word that parses as a chord is still a chord in a chord line`() {
        let chordLike = StopList.words.map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .filter(ChordLines.isChord)
        #expect(!chordLike.isEmpty)
        for word in chordLike {
            #expect(ChordLines.isChordLine("\(word)  G  C"), "\(word)")
            #expect(!ChordLines.isChordLine("\(word) pal ruk jaa"), "\(word)")
        }
    }

    struct HeaderCase: CustomTestStringConvertible, Sendable {
        var line: String
        var text: String?
        var label: SectionLabel?
        var trailing: String?
        var testDescription: String {
            line
        }
    }

    static let headerCases: [HeaderCase] = [
        HeaderCase(line: "[Verse 1]", text: "Verse 1", label: .verse),
        HeaderCase(line: "Chorus:", text: "Chorus", label: .chorus),
        HeaderCase(line: "Chorus: (x2)", text: "Chorus (x2)", label: .chorus),
        HeaderCase(line: "(Chorus)", text: "Chorus", label: .chorus),
        HeaderCase(line: "V1", text: "V1", label: .verse),
        HeaderCase(line: "CH x2", text: "CH x2", label: .chorus),
        HeaderCase(line: "BR", text: "BR", label: .bridge),
        HeaderCase(line: "Verse 1:", text: "Verse 1", label: .verse),
        HeaderCase(line: "Mukhda:", text: "Mukhda", label: .chorus),
        HeaderCase(line: "Antara 2:", text: "Antara 2", label: .verse),
        HeaderCase(line: "Pre-Chorus:", text: "Pre-Chorus", label: .prechorus),
        HeaderCase(line: "Intro riff:", text: "Intro riff", label: .intro),
        HeaderCase(line: "Solo:", text: "Solo", label: .instrumental),
        HeaderCase(line: "Final Chorus x2", text: "Final Chorus x2", label: .chorus),
        HeaderCase(line: "[Rap]", text: "Rap", label: nil),
        HeaderCase(line: "Intro: C G Am F", text: "Intro", label: .intro, trailing: "C G Am F"),
        HeaderCase(line: "Key: G"),
        HeaderCase(line: "[G]"),
        HeaderCase(line: "(x2)"),
        HeaderCase(line: "Sing the chorus"),
        HeaderCase(line: "Chorus girls are dancing"),
        HeaderCase(line: "(Ooh, yeah)"),
        HeaderCase(line: "Strumming: D DU UDU"),
    ]

    @Test(arguments: headerCases)
    func `headers are recognised`(_ testCase: HeaderCase) {
        let header = HeaderParser.parse(testCase.line)
        #expect(header?.text == testCase.text)
        #expect(header?.label == testCase.label)
        #expect(header?.trailingChords == testCase.trailing)
    }

    struct JunkCase: CustomTestStringConvertible, Sendable {
        var line: String
        var rule: String?
        var testDescription: String {
            line
        }
    }

    static let junkCases: [JunkCase] = [
        JunkCase(line: "Tabbed by: jmk_44", rule: "credit"),
        JunkCase(line: "Ultimate Tabs app - download now for offline chords!", rule: "app ad"),
        JunkCase(line: "Download our app for more chords!!", rule: "app ad"),
        JunkCase(line: "Home | Songs | Artists | Login", rule: "navigation"),
        JunkCase(line: "Share on WhatsApp | Facebook | Twitter", rule: "navigation"),
        JunkCase(line: "Print   Share   Transpose: -1 +1   Autoscroll", rule: "toolbar"),
        JunkCase(line: "\u{2605}\u{2605}\u{2605}\u{2605}\u{2606} Rate this tab", rule: "rating"),
        JunkCase(line: "4.5 / 5 (120 ratings)", rule: "rating"),
        JunkCase(line: "Difficulty: intermediate", rule: "site field"),
        JunkCase(line: "Tags: hindi songs chords", rule: "site field"),
        JunkCase(line: "Share via email", rule: "share"),
        JunkCase(line: "Advertisement", rule: "advert"),
        JunkCase(line: "Comments (12)", rule: "comment section"),
        JunkCase(line: "Report bad tab", rule: "report"),
        // Not junk: credits we keep, and lyrics that brush against the rules.
        JunkCase(line: "Singer: Ananya Rao | Music: Vikram Das | Lyrics: Neel Kapoor"),
        JunkCase(line: "Paper Lanterns Chords by The Hollow Pines"),
        JunkCase(line: "Share this night with me"),
        JunkCase(line: "Five stars in the sky tonight"),
        JunkCase(line: "Print my name upon your heart"),
    ]

    @Test(arguments: junkCases)
    func `junk rules drop site noise and keep lyrics`(_ testCase: JunkCase) {
        #expect(JunkRules.match(testCase.line)?.name == testCase.rule)
    }

    @Test
    func `a junk-looking line under a chord line is a lyric`() {
        let output = Normalizer.normalize("G        D\nShare on WhatsApp | Facebook | Twitter\n")
        #expect(output.removed.isEmpty)
    }

    struct AlignCase: CustomTestStringConvertible, Sendable {
        var chords: String
        var lyric: String
        var expected: String
        var testDescription: String {
            expected
        }
    }

    static let alignCases: [AlignCase] = [
        AlignCase(chords: "G         D", lyric: "Paper lanterns", expected: "[G]Paper lant[D]erns"),
        AlignCase(chords: "    G", lyric: "Hold on", expected: "Hold [G]on"),
        AlignCase(
            chords: "Am      C",
            lyric: "Iron on the stove",
            expected: "[Am]Iron on [C]the stove",
        ),
        AlignCase(chords: "C       G", lyric: "Go home", expected: "[C]Go home [G]"),
        AlignCase(chords: "C      G", lyric: "Go home", expected: "[C]Go home[G]"),
        AlignCase(chords: "D          A    E", lyric: "Short", expected: "[D]Short [A] [E]"),
        AlignCase(chords: "G   |   C", lyric: "Bar lines go", expected: "[G]Bar line[C]s go"),
        AlignCase(
            chords: "Am     F  (x2)",
            lyric: "Tum ho toh",
            expected: "[Am]Tum ho [F]toh (x2)",
        ),
        AlignCase(chords: "  Em", lyric: "Dil", expected: "Di[Em]l"),
        AlignCase(chords: "G   D", lyric: "Mañana", expected: "[G]Maña[D]na"),
        AlignCase(chords: "G", lyric: "", expected: "[G]"),
    ]

    @Test(arguments: alignCases)
    func `chords land on their lyric column`(_ testCase: AlignCase) {
        #expect(ColumnAligner.merge(chords: testCase.chords, lyric: testCase.lyric) == testCase
            .expected)
    }

    @Test
    func `chord-only lines keep their spacing and bar lines`() {
        #expect(ColumnAligner.chordsOnly("  G  D/F#  Em  C") == "[G]  [D/F#]  [Em]  [C]")
        #expect(ColumnAligner.chordsOnly("| G  | C  |") == "| [G]  | [C]  |")
        #expect(ColumnAligner.chordsOnly("E  B  (x2)") == "[E]  [B]  (x2)")
    }

    @Test
    func `tabs expand to eight-column stops so chords stay over their words`() {
        #expect(Normalizer.expandTabs("G\tD") == "G       D")
        #expect(Normalizer.expandTabs("Bb\t\tF") == "Bb              F")
    }

    @Test
    func `the lyric guard catches a respelled word and names its unit`() {
        let original = ChordProParser.parse("{start_of_verse}\n[G]Pyaar hai\n{end_of_verse}\n\n"
            + "{start_of_chorus}\n[C]Tum ho\n{end_of_chorus}\n").0
        let relabelled = ChordProParser.parse("{start_of_chorus}\n[G]Pyaar hai\n{end_of_chorus}\n\n"
            + "{start_of_chorus}\n[C]Tum ho\n{end_of_chorus}\n").0
        let respelled = ChordProParser.parse("{start_of_verse}\n[G]Pyaar hai\n{end_of_verse}\n\n"
            + "{start_of_chorus}\n[C]Tum hoo\n{end_of_chorus}\n").0
        // R124: the same words regrouped (two sections become one run of loose lines).
        let regrouped = ChordProParser.parse("[G]Pyaar hai\n[C]Tum ho\n").0
        #expect(LyricGuard.check(original: original, refined: relabelled) == .identical)
        #expect(LyricGuard.check(original: original, refined: regrouped) == .identical)
        #expect(LyricGuard.check(original: original, refined: respelled) == .differs(unit: 1))
    }

    @Test
    func `a stated key wins and a detected key exposes its runner-up`() {
        let chords = ["G", "C", "G", "C"].compactMap { ChordTokenHelper.chord($0) }
        let stated = KeyInference(stated: "D", chords: chords)
        #expect(stated.source == .stated)
        #expect(!stated.isAmbiguous)
        let detected = KeyInference(stated: nil, chords: chords)
        #expect(detected.source == .detected)
        #expect(detected.isAmbiguous)
        #expect(detected.topTwo.count == 2)
        #expect(detected.accepts(modelKey: detected.topTwo[1]))
    }
}

private enum ChordTokenHelper {
    static func chord(_ text: String) -> ChartChord? {
        ChordToken(parsing: text).chord
    }
}
