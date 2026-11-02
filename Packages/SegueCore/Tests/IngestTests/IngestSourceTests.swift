import ChordPro
import Foundation
@testable import Ingest
import Plugins
import Testing

/// `IngestPipeline.ingest(_:origin:source:)` (P9-4 spec 5.1, 15.2): source fields win, the
/// text fills gaps, the credit splits with `artistSplits`, `{album}`, an unreadable key is
/// dropped, ChordPro passes through untouched, and the page heading line is consumed.
struct IngestSourceTests {
    static let chart = """
    Verse 1
    Fm          Db
    Hum tere bin ab reh nahi sakte
    Ab          Eb
    Tere bina kya wajood mera

    Chorus
    Fm      Db
    Tum hi ho
    Ab        Eb
    Ab tum hi ho
    """

    static func ingest(_ text: String, _ source: SourceFields) -> IngestResult {
        IngestPipeline.ingest(text, origin: .web, source: source)
    }

    @Test
    func `source fields fill an untitled chart`() {
        let fields = SourceFields(
            title: "Tum Hi Ho",
            artistCredit: "Arijit Singh",
            album: "Aashiqui 2",
            key: "Fm",
            capo: 1,
        )
        let result = Self.ingest(Self.chart, fields)
        #expect(result.origin == .web)
        #expect(result.metadata.title == "Tum Hi Ho")
        #expect(result.metadata.artists == ["Arijit Singh"])
        #expect(result.metadata.album == "Aashiqui 2")
        #expect(result.metadata.key == "Fm")
        #expect(result.metadata.capo == 1)
        #expect(result.artistSplits.isEmpty)
        let header = "{title: Tum Hi Ho}\n{artist: Arijit Singh}\n{album: Aashiqui 2}\n"
            + "{key: Fm}\n{capo: 1}\n"
        #expect(result.text.hasPrefix(header))
    }

    @Test
    func `source fields win over a text header`() {
        let text = "Tum Hi Ho (Unplugged)\nby Somebody Else\n\n" + Self.chart
        let result = Self.ingest(
            text,
            SourceFields(title: "Tum Hi Ho", artistCredit: "Arijit Singh"),
        )
        #expect(result.metadata.title == "Tum Hi Ho")
        #expect(result.metadata.artists == ["Arijit Singh"])
    }

    @Test
    func `the text fills fields the source left empty`() {
        let text = "Tum Hi Ho\nby Arijit Singh\nCapo 2\n\n" + Self.chart
        let result = Self.ingest(text, SourceFields(album: "Aashiqui 2"))
        #expect(result.metadata.title == "Tum Hi Ho")
        #expect(result.metadata.artists == ["Arijit Singh"])
        #expect(result.metadata.album == "Aashiqui 2")
    }

    @Test(arguments: [
        ("Arijit Singh, Shreya Ghoshal", ["Arijit Singh", "Shreya Ghoshal"], true),
        ("Vishal & Shekhar feat. Sunidhi", ["Vishal", "Shekhar", "Sunidhi"], true),
        ("Simon and Garfunkel", ["Simon and Garfunkel"], false),
    ])
    func `the credit splits like a credit line`(credit: String, parts: [String], didSplit: Bool) {
        let result = Self.ingest(Self.chart, SourceFields(title: "Song", artistCredit: credit))
        #expect(result.metadata.artists == parts)
        #expect(result.artistSplits.map(\.parts) == (didSplit ? [parts] : []))
    }

    @Test(arguments: ["", "   ", "Am G C D", "https://example.com"])
    func `an implausible source title is ignored`(title: String) {
        let text = "Tum Hi Ho\n\n" + Self.chart
        let result = Self.ingest(text, SourceFields(title: title))
        #expect(result.metadata.title == "Tum Hi Ho")
    }

    @Test(arguments: [("Fm", "Fm"), ("not a key", nil), ("", nil)] as [(String, String?)])
    func `a key is kept only when it parses`(key: String, expected: String?) {
        let result = Self.ingest(Self.chart, SourceFields(title: "Song", key: key))
        #expect(result.metadata.key == expected)
    }

    @Test(arguments: [(0, nil), (1, 1), (11, 11), (12, nil)] as [(Int, Int?)])
    func `a capo is kept from 1 to 11`(capo: Int, expected: Int?) {
        let result = Self.ingest(Self.chart, SourceFields(title: "Song", capo: capo))
        #expect(result.metadata.capo == expected)
    }

    @Test
    func `a directive in the text stays as written`() {
        let text = "{title: My Own Title}\n\n" + Self.chart
        let result = Self.ingest(text, SourceFields(title: "Tum Hi Ho"))
        #expect(result.metadata.title == "My Own Title")
        #expect(!result.text.contains("Tum Hi Ho}"))
    }

    @Test
    func `already-ChordPro text passes through untouched`() {
        let text = "{title: Dilli}\n{artist: Vishal & Shekhar}\n\n[G]Koi [C]baat\n"
        let fields = SourceFields(title: "Other", artistCredit: "A, B", album: "X")
        let result = Self.ingest(text, fields)
        #expect(result.isAlreadyChordPro)
        #expect(result.text == text)
        #expect(result.metadata.title == "Dilli")
        #expect(result.artistSplits.isEmpty)
    }

    @Test(arguments: [
        "Tum Hi Ho Chords by Arijit Singh",
        "TUM HI HO CHORDS BY ARIJIT SINGH",
        "Tum Hi Ho - Arijit Singh",
    ])
    func `the page heading line is consumed`(heading: String) {
        let result = Self.ingest(heading + "\n\n" + Self.chart, SourceFields(
            title: "Tum Hi Ho", artistCredit: "Arijit Singh",
        ))
        #expect(!result.text.localizedCaseInsensitiveContains(heading))
        #expect(result.text.components(separatedBy: "{title: Tum Hi Ho}").count == 2)
    }

    @Test
    func `a lyric that sings the title is never consumed`() {
        let result = Self.ingest(Self.chart, SourceFields(title: "Tum Hi Ho"))
        let lyrics = result.text.replacing(/\[[^\]]*\]/, with: "")
        #expect(lyrics.contains("\nTum hi ho\n"))
        #expect(lyrics.contains("\nAb tum hi ho\n"))
    }

    @Test
    func `bare lyrics from a lyrics record`() {
        let lyrics = "Hum tere bin ab reh nahi sakte\nTere bina kya wajood mera\n\n"
            + "Tum hi ho\nAb tum hi ho"
        let result = IngestPipeline.ingest(lyrics, origin: .lyrics, source: SourceFields(
            title: "Tum Hi Ho", artistCredit: "Arijit Singh", album: "Aashiqui 2",
        ))
        #expect(result.origin == .lyrics)
        #expect(result.metadata.title == "Tum Hi Ho")
        #expect(result.text.contains("{album: Aashiqui 2}"))
        #expect(result.text.contains("Tere bina kya wajood mera"))
    }

    /// Spec 15.2: a model refinement on a source result never changes the source's title,
    /// artists or album (`Refinements` has no artist or album field at all, R174).
    @Test
    func `a refinement keeps the source title, artists and album`() {
        let base = Self.ingest(Self.chart, SourceFields(
            title: "Tum Hi Ho", artistCredit: "Arijit Singh, Mithoon", album: "Aashiqui 2",
        ))
        let refined = IngestPipeline.apply(Refinements(title: "Something Else"), to: base)
        #expect(refined.metadata.title == "Tum Hi Ho")
        #expect(refined.metadata.artists == ["Arijit Singh", "Mithoon"])
        #expect(refined.metadata.album == "Aashiqui 2")
        #expect(refined.artistSplits == base.artistSplits)
    }
}
