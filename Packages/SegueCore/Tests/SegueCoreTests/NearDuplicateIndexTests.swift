import ChordPro
import Foundation
@testable import Library
import Support
import Testing

/// The near-duplicate score (P8-1 section 6.1, R158 Q8): tricky pure logic, so a direct
/// table over the worked values plus the blocking, tie-break and word-cap rules.
struct NearDuplicateIndexTests {
    /// `count` distinct lyric words, `prefix1`, `prefix2`, ...
    private static func words(_ prefix: String, _ count: Int) -> [String] {
        (1 ... count).map { "\(prefix)\($0)" }
    }

    /// The words four to a line.
    private static func lines(_ words: [String], perLine: Int = 4) -> String {
        stride(from: 0, to: words.count, by: perLine)
            .map { words[$0 ..< min($0 + perLine, words.count)].joined(separator: " ") }
            .joined(separator: "\n")
    }

    private static func source(title: String, artist: String?, lyrics: String) -> String {
        var text = "{title: \(title)}\n"
        if let artist {
            text += "{artist: \(artist)}\n"
        }
        return text + lyrics + "\n"
    }

    private static func song(_ source: String, id: UInt64 = 1) -> SongRecord {
        let songId = SongID(ULID(milliseconds: id, randomness: Array(repeating: 0, count: 10)))
        let (document, diagnostics) = ChordProParser.parse(source)
        return SongRecord(
            id: songId,
            relativePath: "songs/song-\(id).cho",
            source: source,
            document: document,
            diagnostics: diagnostics,
            sidecar: Sidecar(id: songId, createdAt: .distantPast, updatedAt: .distantPast),
            revision: SongRevision(
                contentHash: NearDuplicateIndex.contentHash(of: source),
                sidecarHash: nil,
            ),
        )
    }

    private static func match(
        _ index: NearDuplicateIndex,
        _ source: String,
    ) -> NearDuplicateIndex.Match? {
        let (document, _) = ChordProParser.parse(source)
        return index.match(
            title: document.metadata.title,
            artists: document.metadata.artists,
            lyrics: document.plainLyrics,
            contentHash: NearDuplicateIndex.contentHash(of: source),
        )
    }

    /// The 20 library lyric words; "the same lyrics" add two words (C = 18/20 = 0.9).
    private static let base = words("lyric", 20)
    private static let sameLyrics = lines(base + ["extra1", "extra2"], perLine: 5)
    /// Shares one shingle with `base` out of 48 (C = 0.02).
    private static let otherLyrics = lines(["lyric1", "lyric2", "lyric3"] + words("other", 24))

    struct Song: Sendable {
        let title: String
        let artist: String?
        var lyrics = ""
    }

    struct Row: Sendable, CustomTestStringConvertible {
        let name: String
        let library: Song
        let incoming: Song
        let expected: NearDuplicateIndex.Breakdown
        let warns: Bool

        var testDescription: String {
            name
        }
    }

    static let rows: [Row] = [
        Row(
            name: "Diwana vs Deewana, same artist, same lyrics re-wrapped",
            library: Song(title: "Deewana", artist: "Kumar Sanu"),
            incoming: Song(title: "Diwana", artist: "Kumar Sanu", lyrics: sameLyrics),
            expected: NearDuplicateIndex.Breakdown(title: 1, artist: 1, content: 0.9),
            warns: true,
        ),
        Row(
            name: "same title, no artist on the paste, same lyrics",
            library: Song(title: "Deewana", artist: "Kumar Sanu"),
            incoming: Song(title: "Deewana", artist: nil, lyrics: sameLyrics),
            expected: NearDuplicateIndex.Breakdown(title: 1, artist: 0.5, content: 0.9),
            warns: true,
        ),
        Row(
            name: "same title, same artist, chords-only paste",
            library: Song(title: "Deewana", artist: "Kumar Sanu"),
            incoming: Song(title: "Deewana", artist: "Kumar Sanu", lyrics: "[G] [C] [D]"),
            expected: NearDuplicateIndex.Breakdown(title: 1, artist: 1, content: 0.5),
            warns: true,
        ),
        Row(
            name: "Tum Hi Ho vs Tum Hi Ho (Unplugged), same artist, same lyrics",
            library: Song(title: "Tum Hi Ho", artist: "Arijit Singh"),
            incoming: Song(
                title: "Tum Hi Ho (Unplugged)",
                artist: "Arijit Singh",
                lyrics: sameLyrics,
            ),
            expected: NearDuplicateIndex.Breakdown(title: 0.75, artist: 1, content: 0.9),
            warns: true,
        ),
        Row(
            name: "same title, different artist, same lyrics (a cover)",
            library: Song(title: "Deewana", artist: "Kumar Sanu"),
            incoming: Song(title: "Deewana", artist: "Someone Else", lyrics: sameLyrics),
            expected: NearDuplicateIndex.Breakdown(title: 1, artist: 0, content: 0.9),
            warns: true,
        ),
        Row(
            name: "same title, same artist, entirely different lyrics",
            library: Song(title: "Deewana", artist: "Kumar Sanu"),
            incoming: Song(
                title: "Deewana",
                artist: "Kumar Sanu",
                lyrics: lines(words("other", 20)),
            ),
            expected: NearDuplicateIndex.Breakdown(title: 1, artist: 1, content: 0),
            warns: false,
        ),
        Row(
            name: "same title, different artist, different lyrics (another song)",
            library: Song(title: "Deewana", artist: "Kumar Sanu"),
            incoming: Song(title: "Deewana", artist: "Someone Else", lyrics: otherLyrics),
            expected: NearDuplicateIndex.Breakdown(title: 1, artist: 0, content: 0.02),
            warns: false,
        ),
    ]

    @Test(arguments: rows)
    func `the worked values score and warn as the table says`(_ row: Row) {
        let library = Self.song(Self.source(
            title: row.library.title,
            artist: row.library.artist,
            lyrics: Self.lines(Self.base),
        ))
        let index = NearDuplicateIndex([library])
        let (document, _) = ChordProParser.parse(Self.source(
            title: row.incoming.title,
            artist: row.incoming.artist,
            lyrics: row.incoming.lyrics,
        ))
        let lyrics = document.plainLyrics
        // The breakdown, whether or not it passes the threshold.
        let title = NearDuplicateIndex.titleSimilarity(
            RomanNormalizer.loose(row.incoming.title),
            Set(RomanNormalizer.loose(row.incoming.title).split(separator: " ").map(String.init)),
            RomanNormalizer.loose(row.library.title),
            Set(RomanNormalizer.loose(row.library.title).split(separator: " ").map(String.init)),
        )
        let artist = NearDuplicateIndex.artistSimilarity(
            NearDuplicateIndex.artistForms(document.metadata.artists),
            NearDuplicateIndex.artistForms(library.document.metadata.artists),
        )
        let content = NearDuplicateIndex.contentSimilarity(
            NearDuplicateIndex.shingles(lyrics),
            NearDuplicateIndex.shingles(library.document.plainLyrics),
        )
        #expect(Self.rounded(title) == row.expected.title)
        #expect(Self.rounded(artist) == row.expected.artist)
        #expect(Self.rounded(content) == row.expected.content)

        let found = index.match(
            title: document.metadata.title,
            artists: document.metadata.artists,
            lyrics: lyrics,
            contentHash: "incoming",
        )
        #expect((found != nil) == row.warns)
        if let found {
            #expect(found.songId == library.id)
            #expect(Self.rounded(found.breakdown.title) == row.expected.title)
            #expect(Self.rounded(found.breakdown.content) == row.expected.content)
        }
    }

    @Test
    func `pen and pin are never compared but score 0.67 by title`() {
        let library = Self.song(Self.source(title: "Pen", artist: "A", lyrics: "la"))
        let index = NearDuplicateIndex([library])
        #expect(index.candidates(for: "Pin").isEmpty)
        #expect(Self.rounded(NearDuplicateIndex.titleSimilarity("pin", ["pin"], "pen", ["pen"]))
            == 0.67)
        #expect(Self.match(index, Self.source(title: "Pin", artist: "A", lyrics: "la")) == nil)
    }

    @Test
    func `blocking compares only titles that share a key`() {
        let index = NearDuplicateIndex([
            Self.song(Self.source(title: "Kesariya", artist: nil, lyrics: "la"), id: 1),
            Self.song(Self.source(title: "Tum Hi Ho", artist: nil, lyrics: "la"), id: 2),
            Self.song(Self.source(title: "Ho", artist: nil, lyrics: "la"), id: 3),
        ])
        #expect(index.candidates(for: "Kesriya") == [0])
        #expect(index.candidates(for: "Tum Hi Ho (Unplugged)") == [1])
        #expect(index.candidates(for: "Ho") == [2])
        #expect(index.candidates(for: "Something Else").isEmpty)
    }

    @Test
    func `identical bytes are found by identical and never by match`() {
        let source = Self.source(
            title: "Deewana",
            artist: "Kumar Sanu",
            lyrics: Self.lines(Self.base),
        )
        let library = Self.song(source)
        let index = NearDuplicateIndex([library])
        #expect(Self.match(index, source) == nil)
        #expect(index.identical(contentHash: NearDuplicateIndex.contentHash(of: source))?.songId
            == library.id)
        #expect(index.identical(contentHash: "other") == nil)
    }

    @Test
    func `re-wrapped lyrics keep the content score`() {
        let original = NearDuplicateIndex.shingles(Self.lines(Self.base, perLine: 4))
        let rewrapped = NearDuplicateIndex.shingles(Self.lines(Self.base, perLine: 7))
        let library = NearDuplicateIndex.shingles(Self.lines(Self.base + ["coda"], perLine: 3))
        let score = NearDuplicateIndex.contentSimilarity(original, library)
        let wrapped = NearDuplicateIndex.contentSimilarity(rewrapped, library)
        #expect(abs(score - wrapped) <= 0.05)
        #expect(NearDuplicateIndex.contentSimilarity([], library) == 0.5)
    }

    @Test
    func `equal scores break ties by shorter title, then title, then ID`() {
        let lyrics = Self.lines(Self.base)
        let index = NearDuplicateIndex([
            Self.song(Self.source(title: "Deewana Hai", artist: "A", lyrics: lyrics), id: 5),
            Self.song(Self.source(title: "Deewana Ho", artist: "A", lyrics: lyrics), id: 4),
            Self.song(Self.source(title: "Deewana Hu", artist: "A", lyrics: lyrics), id: 3),
            Self.song(Self.source(title: "Deewana Hu", artist: "A", lyrics: lyrics + "\n"), id: 2),
        ])
        let incoming = Self.source(title: "Deewana", artist: "A", lyrics: lyrics + "\nmore")
        for _ in 0 ..< 3 {
            let found = Self.match(index, incoming)
            #expect(found?.title == "Deewana Ho")
        }
        let tied = NearDuplicateIndex([
            Self.song(Self.source(title: "Deewana Hu", artist: "A", lyrics: lyrics), id: 3),
            Self.song(Self.source(title: "Deewana Hu", artist: "A", lyrics: lyrics + "\n"), id: 2),
        ])
        let first = SongID(ULID(milliseconds: 2, randomness: Array(repeating: 0, count: 10)))
        #expect(Self.match(tied, incoming)?.songId == first)
    }

    @Test
    func `only the first 400 lyric words count`() {
        let long = Self.words("lyric", 5000)
        let full = NearDuplicateIndex.shingles(Self.lines(long))
        let capped = NearDuplicateIndex.shingles(Self.lines(Array(long.prefix(400))))
        #expect(full == capped)
        #expect(full.count == 398)
    }

    /// P8-8 section 3.5: a legacy combined artist meets its split form.
    @Test
    func `a combined library artist meets a split paste`() throws {
        #expect(NearDuplicateIndex.artistSimilarity(
            NearDuplicateIndex.artistForms(["Vishal", "Shekhar"]),
            NearDuplicateIndex.artistForms(["Vishal & Shekhar"]),
        ) == 1)
        let library = Self.song(Self.source(
            title: "Dilli Nights",
            artist: "Vishal & Shekhar",
            lyrics: Self.lines(Self.base),
        ))
        let index = NearDuplicateIndex([library])
        let incoming = "{title: Dilli Nights}\n{artist: Vishal}\n{artist: Shekhar}\n"
            + Self.sameLyrics + "\n"
        let match = try #require(Self.match(index, incoming))
        #expect(match.breakdown.artist == 1)
        #expect(match.songId == library.id)
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
