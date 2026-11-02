import Foundation
import Plugins
@testable import SeguePersonalModules
import Testing

/// Spec 6.2-6.7 and 15.1: the LRCLIB client over saved response shapes (lyrics invented),
/// query variants, the ranker, stanza splitting and the lyrics search source.
struct LyricsSearchTests {
    static let searchURL = web("https://lrclib.net/api/search?q=tum%20hi%20ho")

    static func record(
        _ id: Int,
        _ title: String,
        _ artist: String,
        album: String? = nil,
        plain: String? = "Saans ki dor\nKhwaab ke ghar",
        synced: String? = nil,
        instrumental: Bool = false,
    ) -> [String: Any] {
        var row: [String: Any] = [
            "id": id,
            "trackName": title,
            "artistName": artist,
            "instrumental": instrumental,
            "duration": 260.0,
            "hasWordSync": false,
        ]
        row["albumName"] = album ?? NSNull()
        row["plainLyrics"] = plain ?? NSNull()
        row["syncedLyrics"] = synced ?? NSNull()
        return row
    }

    static func json(_ rows: [[String: Any]]) -> Data {
        (try? JSONSerialization.data(withJSONObject: rows)) ?? Data()
    }

    static func client(_ responses: [URL: [HTTPResponse]]) -> (LRCLIBClient, FixtureTransport) {
        let transport = FixtureTransport(responses)
        let pacer = RequestPacer(clock: TestWebClock(), random: { 0 })
        return (
            LRCLIBClient(transport: transport, pacer: pacer, userAgent: "Segue/test"),
            transport,
        )
    }

    @Test
    func `a search decodes tolerantly`() async throws {
        let body = Self.json([
            Self.record(1, "Tum Hi Ho", "Arijit Singh", album: "Aashiqui 2"),
            Self.record(
                2,
                "Tum Hi Ho",
                "Someone",
                plain: nil,
                instrumental: true,
            ),
        ])
        let response = HTTPResponse(
            url: Self.searchURL,
            status: 200,
            headers: ["Content-Type": "application/json"],
            body: body,
        )
        let (client, transport) = Self.client([Self.searchURL: [response]])
        let records = try await client.search("tum hi ho")
        #expect(records.map(\.id) == [1, 2])
        #expect(records[1].isInstrumental && records[1].plainLyrics == nil)
        #expect(transport.requests.first?.headers["Lrclib-Client"] == "Segue/test")
    }

    @Test(arguments: [502, 503, 200, 404])
    func `edge and server answers fail cleanly`(status: Int) async {
        let type = status == 502 || status == 200 ? "text/html" : "application/json"
        let failure: ImportFailure = status == 404 ? .notFound : .server(status: status)
        let response = HTTPResponse(
            url: Self.searchURL,
            status: status,
            headers: ["Content-Type": type, "Retry-After": "1"],
            body: Data("<html>Bad gateway</html>".utf8),
        )
        let (client, _) = Self.client([Self.searchURL: [response]])
        await #expect(throws: failure) { try await client.search("tum hi ho") }
    }

    @Test
    func `a 429 is busy, held, and not retried`() async {
        let (client, transport) = Self.client([Self.searchURL: [HTTPResponse(
            url: Self.searchURL, status: 429, headers: ["Retry-After": "30"],
        )]])
        await #expect(throws: ImportFailure.busy(retryAfter: .seconds(30))) {
            try await client.search("tum hi ho")
        }
        #expect(transport.requests.count == 1)
    }

    @Test
    func `variants for thin romanized Hindi answers`() {
        #expect(LyricsQueryVariants.variants(for: "tuj mai rab dikta hai", firstAnswerCount: 0)
            == ["tujh mein rab dikhta hai", "tujh main rab dikhta hai"])
        #expect(LyricsQueryVariants.variants(for: "wonderwall oasis", firstAnswerCount: 0).isEmpty)
        #expect(LyricsQueryVariants.variants(for: "tum hi ho", firstAnswerCount: 12).isEmpty)
        #expect(LyricsQueryVariants.variants(for: "tum hi ho", firstAnswerCount: 2).isEmpty)
    }

    @Test
    func `the ranker prefers title, then artist, keeps instrumentals last, dedups`() throws {
        let records = try JSONDecoder().decode([LyricsRecord].self, from: Self.json([
            Self.record(1, "Tum Hi Ho Bandhu", "Other"),
            Self.record(2, "Tum Hi Ho", "Piano Band", plain: nil, instrumental: true),
            Self.record(3, "Tum Hi Ho", "Arijit Singh"),
            Self.record(3, "Tum Hi Ho", "Arijit Singh"),
            Self.record(4, "Tum Hi Ho", "Arijit Singh"),
        ]))
        let ranked = LyricsRanker.rank(records, query: "tum hi ho arijit")
        #expect(ranked.map(\.record.id) == [3, 1, 2])
        for item in ranked {
            #expect(abs(item.title + item.artist + item.lyricStart + item.hasLyrics - item.score) <
                1e-12)
        }
    }

    @Test
    func `stanzas split at synced gaps of five seconds`() {
        let plain = "Line one\nLine two\nLine three"
        let synced = "[00:10.00] Line one\n[00:13.50] Line two\n[00:19.00] Line three"
        #expect(LRCSections
            .text(plain: plain, synced: synced) == "Line one\nLine two\n\nLine three")
        #expect(LRCSections.text(plain: "A\n\nB", synced: synced) == "A\n\nB")
        #expect(LRCSections.text(plain: plain, synced: nil) == plain)
        #expect(LRCSections.text(plain: plain, synced: "[00:01.00] Other words") == plain)
    }

    @Test
    func `a Devanagari record arrives romanized with its fields`() throws {
        let data = Self.json([Self.record(
            7,
            "तुम ही हो",
            "Arijit Singh",
            album: "Aashiqui 2",
            plain: "तुम ही हो\nदिल",
        )])
        let record = try #require(try JSONDecoder().decode([LyricsRecord].self, from: data).first)
        let candidate = try #require(LyricsSearchSource.candidate(record))
        #expect(candidate.title == "tum hi ho")
        #expect(candidate.firstLines == "tum hi ho\ndil")
        let song = try LyricsSearchSource.song(record)
        #expect(song.provenance.romanized && song.provenance.reader == .lyricsRecord)
        #expect(song.fields.album == "Aashiqui 2")
        #expect(!HindiRomanizer.containsDevanagari(song.text))
    }

    @Test
    func `other scripts are greyed rows and generic albums are left out`() throws {
        let urdu = try JSONDecoder().decode(LyricsRecord.self, from: JSONSerialization.data(
            withJSONObject: Self.record(9, "تم ہی ہو", "Someone", plain: "تم ہی ہو تم ہی ہو"),
        ))
        let row = try #require(LyricsSearchSource.candidate(urdu))
        #expect(row.unsupportedScript && !row.isPickable)
        #expect(row.title == "Untitled")
        #expect(row.artist == "Someone")
        #expect(row.lyrics == nil && row.firstLines == nil)
        #expect(LyricsSearchSource.album(album: "Single", title: "X") == nil)
        #expect(LyricsSearchSource.album(album: "Tum Hi Ho", title: "Tum Hi Ho") == nil)
        #expect(LyricsSearchSource.album(album: "Aashiqui 2", title: "Tum Hi Ho") == "Aashiqui 2")
    }
}
