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
        // R124: page controls, widgets, share bars and post dates.
        JunkCase(line: "Transpose", rule: "site control"),
        JunkCase(line: "Transpose 0", rule: "toolbar"),
        JunkCase(line: "Transpose Up Transpose Down", rule: "site control"),
        JunkCase(line: "-+Reset", rule: "site control"),
        JunkCase(line: "Font Size", rule: "site control"),
        JunkCase(line: "Text size", rule: "site control"),
        JunkCase(line: "1 Column", rule: "site control"),
        JunkCase(line: "Change Key", rule: "site control"),
        JunkCase(
            line: "Display Settings Guitar tuner Show all chords diagrams",
            rule: "site control",
        ),
        JunkCase(line: "Guitar Chord Diagrams", rule: "site control"),
        JunkCase(line: "Auto Scroll", rule: "toolbar"),
        JunkCase(line: "Stop Scroll", rule: "site control"),
        JunkCase(line: "Chords (4)", rule: "site control"),
        JunkCase(line: "Add to favorites", rule: "site control"),
        JunkCase(line: "Newer Post Older Post", rule: "site control"),
        JunkCase(line: "Pinterest", rule: "site control"),
        JunkCase(line: "Google+", rule: "site control"),
        JunkCase(line: "Rating", rule: "site control"),
        JunkCase(line: "100%", rule: "site control"),
        JunkCase(line: "Submit Rating", rule: "site control"),
        JunkCase(line: "Share this:", rule: "share"),
        JunkCase(line: "15,376,054 views, added to favorites 368,221 times", rule: "views"),
        JunkCase(line: "\u{1F3A7} 50,902 views", rule: "views"),
        JunkCase(line: "157 258 Views", rule: "views"),
        JunkCase(line: "4.8", rule: "rating widget"),
        JunkCase(line: "12,628 rates", rule: "rating widget"),
        JunkCase(line: "Average rating 4.8 / 5. Vote count: 30", rule: "rating widget"),
        JunkCase(line: "Click on a star to rate it!", rule: "rating widget"),
        JunkCase(line: "How useful was this post?", rule: "rating widget"),
        JunkCase(line: "Simplify chords by removing barre", rule: "simplify chords"),
        JunkCase(
            line: "For easier playing, use our Simplify Chords feature to remove barre.",
            rule: "simplify chords",
        ),
        JunkCase(line: "Friday, December 05, 2008", rule: "page date"),
        JunkCase(line: "By Utkatsh / August 9, 2025", rule: "page date"),
        JunkCase(line: "Published on June 4, 2022 by harborchordslyrics", rule: "page date"),
        JunkCase(line: "16 Nov 2000, by SuN", rule: "page date"),
        JunkCase(line: "Last update: Feb 19, 2021", rule: "page date"),
        JunkCase(line: "Author tomo999 [a] 71. Last edit on Feb 19, 2021", rule: "page date"),
        JunkCase(line: "chordsver. 1", rule: "version tabs"),
        JunkCase(line: "tabs ver. 1 6", rule: "version tabs"),
        JunkCase(line: "Categories: Hindi Songs", rule: "site field"),
        JunkCase(line: "Tuning:", rule: "site field"),
        JunkCase(line: "You like ? Help us ! Subscribe to our YouTube Channel !", rule: "promo"),
        JunkCase(line: "How to read a Tab", rule: "promo"),
        JunkCase(line: "Collection of strumming patterns", rule: "promo"),
        // R142: a transpose or key widget's value on its own line.
        JunkCase(line: "0", rule: "site control"),
        // Not junk: credits we keep, and lyrics that brush against the rules.
        JunkCase(line: "Singer: Ananya Rao | Music: Vikram Das | Lyrics: Neel Kapoor"),
        JunkCase(line: "Paper Lanterns Chords by The Hollow Pines"),
        JunkCase(line: "Share this night with me"),
        JunkCase(line: "Five stars in the sky tonight"),
        JunkCase(line: "Print my name upon your heart"),
        // Lyrics made of control words plus one that is not, dates without a day, numbers.
        JunkCase(line: "Transpose my heart"),
        JunkCase(line: "Transpose me into a minor key"),
        JunkCase(line: "Font of all my sorrow"),
        JunkCase(line: "Reset the clocks and start again"),
        JunkCase(line: "Change the key, I'm singing low"),
        JunkCase(line: "Scroll down the years with me"),
        JunkCase(line: "Facebook friends and Twitter lies"),
        JunkCase(line: "Rating every kiss a ten"),
        JunkCase(line: "Chords of a broken guitar"),
        JunkCase(line: "December, 1963"),
        JunkCase(line: "Born on a Friday, December night"),
        JunkCase(line: "Ninety-nine views from the window"),
        JunkCase(line: "She shares my dreams, I hope that someday I'll share her home"),
        JunkCase(line: "Tuning: E A D G B E"),
        JunkCase(line: "Key: G"),
        JunkCase(line: "Home"),
        JunkCase(line: "10"),
        JunkCase(line: "0 to 60 in a heartbeat"),
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

/// R142: the paste converter gaps closed in v0.5.
extension IngestClassificationTests {
    /// R142: chord-site fields written with an en or em dash or after an emoji read like the
    /// colon form; a dash field whose value has site words is not a credit.
    @Test
    func `dash and emoji fields are metadata`() {
        let cases: [(String, [MetadataField]?)] = [
            ("Capo \u{2013} 3rd Fret", [.capo(3)]),
            ("Capo \u{2014} 2", [.capo(2)]),
            ("Key/Scale \u{2013} Eb", [.key("Eb")]),
            ("Original Scale \u{2013} Cm", [.key("Cm")]),
            ("Tempo \u{2013} 96 bpm", [.tempo(96)]),
            ("Singer \u{2013} Raghav Sen", [.artist("Raghav Sen")]),
            ("\u{1F3B6} Song: Chaand Ki Galiyan", [.title("Chaand Ki Galiyan")]),
            ("\u{1F3A4} Singer: Raghav Sen", [.artist("Raghav Sen")]),
            ("\u{1F3BC} Album: Neeli Raat (2021)", [.album("Neeli Raat (2021)")]),
            ("Song \u{2013} Chaand Ki Galiyan Chords", nil),
            ("Tempo \u{2013} 4/4", nil),
            ("Capo \u{2013} N/A", nil),
            ("\u{1F319} Chaand bhi kehta hai: tu aaja", nil),
        ]
        for (line, fields) in cases {
            #expect(MetadataExtractor.keyValueFields(line) == fields, "\(line)")
        }
    }

    /// R142: site notes become `{comment}` lines; lyrics with a dash, a colon or a leading
    /// emoji (romanized Hindi included) stay lyrics, word for word.
    @Test(arguments: [
        ("*    Some folks prefer G rather than Em", true),
        ("**   Song is in key of F#m", true),
        ("\u{1F4C5} Release Date: 2003", true),
        ("\u{1F4D6} Storyline: A song about rain \u{1F327}\u{FE0F} and longing.", true),
        ("Strumming \u{2013} DDU UDU", true),
        ("Guitar Tuning \u{2014} Standard (E A D G B E)", true),
        ("Original Chords \u{2013} D#, Cm, G#", true),
        ("Tempo \u{2013} 4/4", true),
        ("Strumming Pattern \u{2013} DD UU DUD", true),
        ("Tu hi meri \u{2013} manzil hai", false),
        ("Bheegi Raatein Chords \u{2013} Tara, Neel Kapoor", false),
        ("Neeli Raat Lyrics \u{2013} Raghav Sen", false),
        ("Turn the key \u{2013} and go", false),
        ("Love \u{2013} it's all we need", false),
        ("\u{1F319} Chaand bhi kehta hai: tu aaja", false),
        ("\u{1F3B5} Dil: ab tu hi bata", false),
        ("Release Date: 2003", false),
        ("*sigh* not again tonight", false),
        ("Orignal Chords \u{2013} [Cm] [A#] [G#]", false),
    ])
    func `site notes are told from lyrics`(line: String, isNote: Bool) {
        #expect(MetadataExtractor.isNoteLine(line) == isNote)
        #expect(FormatDetector
            .classify(line, underChordLine: false) == (isNote ? .unknown : .lyricLine)
            || ChordLines.hasInlineChords(line))
    }

    /// R142: fingering lines, with or without the chord name, are chord legends (`{comment}`),
    /// even directly under the chord they shape.
    @Test(arguments: [
        ("E- 022300", true), ("B-024400", true), ("A- 002200 (Technically an Asus2)", true),
        ("C#m- 046600", true), ("320033", true), ("x-3-2-0-1-0", true),
        ("Em7     0-2-2-0-3-3", true), ("G     3-x-0-0-3(3)", true),
        ("1998", false), ("Saal 2024 mein", false), ("Main 1-2-3 ginta hoon", false),
        ("xxxxxx", false),
    ])
    func `fingering lines are chord legends`(line: String, isLegend: Bool) {
        #expect(ChordLines.isChordLegend(line) == isLegend)
        #expect((FormatDetector.classify(line, underChordLine: true) == .unknown) == isLegend)
    }
}

private enum ChordTokenHelper {
    static func chord(_ text: String) -> ChartChord? {
        ChordToken(parsing: text).chord
    }
}
