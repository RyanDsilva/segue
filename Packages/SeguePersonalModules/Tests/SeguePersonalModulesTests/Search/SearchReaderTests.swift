import Foundation
import Plugins
@testable import SeguePersonalModules
import Testing

/// Spec 6.10, 6.11 and 15.1: the search readers over the committed redacted results pages,
/// and the per-song version prior (R183).
struct SearchReaderTests {
    static let ugURL = web("https://www.ultimate-guitar.com/search.php?search_type=title&value=x")

    static func candidate(_ version: Int, votes: Int, rating: Double) -> SearchCandidate {
        SearchCandidate(
            id: "\(version)",
            title: "Song",
            kind: .chords,
            version: version,
            rating: rating,
            votes: votes,
            songKey: "1",
        )
    }

    @Test
    func `the spec's tum hi ho versions rank v2, v3, v1, v4, v5`() {
        let versions = [
            Self.candidate(1, votes: 39, rating: 4.68), Self.candidate(2, votes: 833, rating: 4.84),
            Self.candidate(3, votes: 50, rating: 4.84), Self.candidate(4, votes: 14, rating: 4.79),
            Self.candidate(5, votes: 23, rating: 4.52),
        ]
        #expect(VersionRanker.weight(votes: versions.compactMap(\.votes)) == 39)
        let ranked = VersionRanker.rank(versions)
        #expect(ranked.map(\.candidate.version) == [2, 3, 1, 4, 5])
        #expect(abs(ranked[0].score - 4.80) < 0.01)
        #expect(abs(ranked[4].score - 4.19) < 0.01)
        for item in ranked {
            #expect(abs(item.fromRating + item.fromPrior - item.score) < 1e-12)
        }
    }

    @Test(arguments: [([0, 1, 2], 3.0), ([500, 900, 1200], 50.0), ([10, 20], 15.0), ([], 3.0)]
        as [([Int], Double)])
    func `the prior's weight is the median, clamped to 3 to 50`(votes: [Int], weight: Double) {
        #expect(VersionRanker.weight(votes: votes) == weight)
    }

    @Test
    func `a few-vote song still ranks by its own ratings`() {
        let ranked = VersionRanker.rank([
            Self.candidate(1, votes: 2, rating: 4.1), Self.candidate(2, votes: 3, rating: 4.9),
        ])
        #expect(ranked.map(\.candidate.version) == [2, 1])
    }

    @Test
    func `equal scores keep the site's order`() {
        let ranked = VersionRanker.rank([
            Self.candidate(1, votes: 0, rating: 0),
            Self.candidate(2, votes: 0, rating: 0),
        ])
        #expect(ranked.map(\.candidate.version) == [1, 2])
    }

    @Test
    func `UG results list chord versions only, nested by song`() throws {
        let html = try FixturePages.text("search/ug-tum-hi-ho.html")
        let songs = try #require(UGSearchReader.read(html, url: Self.ugURL))
        let store = try #require(TabJSONParser.store(in: html, url: Self.ugURL))
        let rows = try #require(HTMLText.value(store, [
            "store",
            "page",
            "data",
            "results",
        ]) as? [Any])
        let chordRows = rows.filter { row in
            HTMLText.value(row, ["id"]) is Int
                && ["chords", "ukulele chords"]
                .contains(HTMLText.string(row, ["type"])?.lowercased() ?? "")
                && (HTMLText.string(row, ["tab_url"]) ?? "").hasPrefix(UGSearchReader.tabPrefix)
        }
        #expect(rows.count > chordRows.count)
        #expect(songs.flatMap(\.versions).count == chordRows.count)
        #expect(songs.allSatisfy { song in song.versions.allSatisfy { $0.songKey == song.key } })
        // The film's chord versions (five Chords and one Ukulele Chords) lead the page.
        let film = try #require(songs.first)
        #expect(film.versions.count == 6)
        #expect(film.versions.first?.votes == 833)
        let scores = VersionRanker.rank(film.versions).map(\.score)
        #expect(scores == scores.sorted(by: >))
        #expect(film.album != nil)
        #expect(film.versions.allSatisfy { $0.kind == .chords && $0.pageURL != nil })
    }

    @Test
    func `a page with no results store reads as nothing`() {
        #expect(UGSearchReader
            .read("<html><body>Just a moment...</body></html>", url: Self.ugURL) == nil)
    }

    @Test
    func `EChords hits nest by title and artist and keep the site's order`() throws {
        let songs = try #require(EChordsSearchReader
            .read(json: FixturePages.text("search/echords-tum-hi-ho.json")))
        #expect(!songs.isEmpty)
        #expect(songs.flatMap(\.versions).allSatisfy {
            $0.pageURL?.absoluteString.hasPrefix("https://www.e-chords.com/chords/") == true
        })
        #expect(Set(songs.map(\.key)).count == songs.count)
        let single = try #require(EChordsSearchReader
            .read(json: FixturePages.text("search/echords-kesariya.json")))
        #expect(single.count == 1)
        #expect(single[0].album != nil)
        #expect(single[0].artist == nil)
    }

    @Test
    func `the EChords API path keeps every take in range`() {
        let path = EChordsSearchReader.apiPath(for: "tum hi ho")
        #expect(path.hasPrefix("/api/search?"))
        #expect(path.contains("q=tum%20hi%20ho"))
        #expect(path.contains("songs_take=15") && path.contains("videos_take=1"))
    }

    @Test
    func `the rendered EChords list is the fallback`() throws {
        let html = """
        <a class="song-item" href="/chords/artist-a/song-one">
        <strong class="song">Song One</strong><span class="artist">Artist A</span></a>
        <a class="song-item" href="/chords/artist-a/song-one-2">
        <strong class="song">Song One</strong><span class="artist">Artist A</span></a>
        """
        let songs = try #require(EChordsSearchReader.read(
            html: html,
            url: web("https://www.e-chords.com/search-all/x"),
        ))
        #expect(songs.count == 1)
        #expect(songs[0].versions.count == 2)
    }
}
