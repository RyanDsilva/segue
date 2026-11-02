import ChordPro
import Foundation
@testable import Ingest
import Testing

/// R198: a line of bracketed chords is a chord line, and a playing instruction under its
/// chords becomes a comment, on every paste.
struct IngestR198Tests {
    static func ingest(_ text: String) -> IngestResult {
        IngestPipeline.ingest(text, origin: .paste)
    }

    @Test
    func `a chord line with a bracketed chord stays a chord line`() {
        let text = """
        Chorus
              Em           G       Em
        Tujhe dekha to yeh jaana sanam
              (G)                D
        Pyaar hota hai deewana sanam
              Em           G       Em
        Tujhe dekha to yeh jaana sanam
              (G)                D
        Pyaar hota hai deewana sanam
        """
        let result = Self.ingest(text)
        #expect(result.text.contains("Pyaar h[G]ota hai deewana sa[D]nam"))
        #expect(!result.text.contains("[G]                D"))
    }

    @Test
    func `a bracketed chord inside a lyric still becomes an inline chord`() {
        let text = "Verse\n(Em) Hello there my friend\n(D) Hello again my friend\nC G\nLa la la"
        let result = Self.ingest(text)
        #expect(result.text.contains("[Em]"))
        #expect(result.text.contains("[D]"))
        #expect(!result.text.contains("(Em)"))
    }

    @Test(arguments: [
        "Keep repeating these 2 chords till the end.",
        "Play these chords throughout the song",
        "Strum the same pattern for the chorus",
    ])
    func `a playing instruction under its chords becomes a comment`(note: String) {
        let verse = "Verse\nC        G\nHello there my old friend\nAm       F\nI came to talk again"
        let text = verse + "\n\nOutro\nC        F\n\(note)"
        let result = Self.ingest(text)
        #expect(result.text.contains("{comment: \(note)}"))
        #expect(result.text.contains("[C]") && result.text.contains("[F]"))
    }

    @Test(arguments: [
        "Keep the fire burning till the end of time",
        "Play it once again, my love",
        "Chords of my heart are breaking",
        "You played three chords and the conductor sang",
    ])
    func `a lyric that only sounds like an instruction stays a lyric`(lyric: String) {
        let text = "Verse\nC        G\nHello there my old friend\nAm       F\n\(lyric)"
        let result = Self.ingest(text)
        #expect(!result.text.contains("{comment: \(lyric)}"))
    }
}
