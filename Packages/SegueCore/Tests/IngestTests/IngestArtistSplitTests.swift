import ChordPro
import Foundation
@testable import Ingest
import Testing

/// The paste and convert-import artist split (P8-8 section 3.7, R172, R173): credit lines
/// and headers split; `{artist}` directives and ChordPro passthrough stay whole; the parts
/// keep the sheet's spelling.
struct IngestArtistSplitTests {
    static func ingest(_ text: String) -> IngestResult {
        IngestPipeline.ingest(text, origin: .paste)
    }

    static let verse = "\n\nVerse 1\nG        C\nKoi baat hai dil mein\nD        G\nWoh kehna hai\n"

    @Test
    func `the H06 credit line splits`() throws {
        let result = try PasteFixtures.ingest("H06-scale-capo-tab.txt")
        #expect(result.metadata.artists == ["Zoya", "The Village Band"])
        #expect(result.artistSplits == [ArtistSplit(
            original: "Zoya & The Village Band",
            parts: ["Zoya", "The Village Band"],
            separators: [.ampersand],
        )])
        #expect(result.text.contains("{artist: Zoya}\n{artist: The Village Band}\n"))
    }

    @Test
    func `the H08 header splits`() throws {
        let result = try PasteFixtures.ingest("H08-codemixed.txt")
        #expect(result.metadata.title == "Late Night Dilli")
        #expect(result.metadata.artists == ["DJ Saahil", "Rhea"])
        #expect(result.artistSplits.map(\.separators) == [[.feat]])
    }

    @Test
    func `an artist directive in a paste stays whole`() throws {
        let result = try PasteFixtures.ingest("E03-inline-chordpro.txt")
        #expect(result.metadata.artists == ["June & the Lighthouse"])
        #expect(result.artistSplits.isEmpty)
    }

    @Test
    func `already-ChordPro text is never split`() {
        let text = "{title: Dilli}\n{artist: Vishal & Shekhar}\n\n[G]Koi [C]baat\n"
        let result = IngestPipeline.ingest(text, origin: .file(extension: "cho"))
        #expect(result.isAlreadyChordPro)
        #expect(result.text == text)
        #expect(result.metadata.artists == ["Vishal & Shekhar"])
        #expect(result.artistSplits.isEmpty)
    }

    @Test(arguments: [
        (
            "Singers: Arijit Singh, Shreya Ghoshal & Mithoon",
            ["Arijit Singh", "Shreya Ghoshal", "Mithoon"],
        ),
        ("Artist: arijit singh, Arijit Singh", ["arijit singh"]),
        ("Artist: Simon and Garfunkel", ["Simon and Garfunkel"]),
        ("Vocals: Salim-Sulaiman", ["Salim-Sulaiman"]),
        ("Singer: Atif Aslam (feat. Shreya Goshal)", ["Atif Aslam", "Shreya Goshal"]),
        ("Singer: Sonu Nigaam featuring Alka Yagnik", ["Sonu Nigaam", "Alka Yagnik"]),
    ])
    func `credit lines split and keep the sheet's spelling`(line: String, artists: [String]) {
        let result = Self.ingest("Mere Sapno Ki Rani\n\(line)" + Self.verse)
        #expect(result.metadata.artists == artists)
        #expect(result.artistSplits.count == (artists.count > 1 ? 1 : 0))
        #expect(ChordProParser.parse(result.text).0.metadata.artists == artists)
    }

    @Test
    func `the splits survive a refinement re-render`() throws {
        let base = try PasteFixtures.ingest("H06-scale-capo-tab.txt")
        let refined = IngestPipeline.apply(Refinements(labels: [:]), to: base)
        #expect(refined.artistSplits == base.artistSplits)
        let relabelled = base.reassembled(labels: [:])
        #expect(relabelled.artistSplits == base.artistSplits)
    }
}
