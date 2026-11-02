#if DEBUG && SEGUE_PERSONAL
    import Foundation
    import SeguePersonalModules

    /// The E2E pages of P9-4 spec 15.4, shaped like the real ones (a chord site's tab and
    /// search pages with their JSON store, a lyrics search and record) but written for Segue:
    /// the song names are real, every lyric line is our own. The other chord site stays
    /// challenged, so its group shows Open Here.
    enum ImportFixtureSet {
        static let tabAddress =
            "https://tabs.ultimate-guitar.com/tab/misc-soundtrack/aashiqui-2-tum-hi-ho-chords-1234996"

        static var e2e: ImportFixtures {
            ImportFixtures(
                pages: [
                    "https://tabs.ultimate-guitar.com/tab/": .init(body: tabPage),
                    "https://www.ultimate-guitar.com/search.php": .init(body: searchPage),
                    "https://lrclib.net/api/search": .init(
                        contentType: "application/json",
                        body: "[\(lyricsRecord)]",
                    ),
                    "https://lrclib.net/api/get/": .init(
                        contentType: "application/json",
                        body: lyricsRecord,
                    ),
                ],
                challenged: ["https://www.e-chords.com"],
            )
        }

        static let chart = """
        [Intro]
        [tab][ch]Em[/ch]  [ch]C[/ch]  [ch]D[/ch]  [ch]Bm[/ch][/tab]

        [Verse 1]
        [tab][ch]Em[/ch]                 [ch]C[/ch]
        Lanterns on the water tonight[/tab]
        [tab][ch]D[/ch]                  [ch]Bm[/ch]
        Every boat is coming home[/tab]

        [Chorus]
        [tab][ch]C[/ch]          [ch]D[/ch]          [ch]Em[/ch]
        Hold the light, hold the light[/tab]
        [tab][ch]C[/ch]          [ch]D[/ch]          [ch]G[/ch]
        Bring her home tonight[/tab]
        """

        static var tabPage: String {
            let store: [String: Any] = ["store": ["page": ["data": [
                "tab": tab(id: 1_234_996, version: 2, rating: 4.84, votes: 833),
                "tab_view": [
                    "meta": ["capo": 1, "tonality": "Em"],
                    "wiki_tab": ["content": chart],
                ],
            ]]]]
            return page(store)
        }

        static var searchPage: String {
            let results: [[String: Any]] = [
                tab(id: 1_234_996, version: 2, rating: 4.84, votes: 833),
                tab(id: 1_234_997, version: 3, rating: 4.84, votes: 50),
                tab(id: 1_234_998, version: 1, rating: 4.68, votes: 39),
                [
                    "id": 2_000_001, "song_id": 777, "song_name": "Tum Hi Ho Bandhu",
                    "artist_name": "Neeraj Shridhar", "type": "Chords", "version": 1,
                    "rating": 4.5, "votes": 12,
                    "tab_url": "https://tabs.ultimate-guitar.com/tab/neeraj-shridhar/"
                        + "tum-hi-ho-bandhu-chords-2000001",
                ],
                ["marketing_type": "pro", "tab_url": "https://www.ultimate-guitar.com/pro/"],
            ]
            return page(["store": ["page": ["data": ["results": results]]]])
        }

        static func tab(id: Int, version: Int, rating: Double, votes: Int) -> [String: Any] {
            [
                "id": id, "song_id": 555, "song_name": "Aashiqui 2 - Tum Hi Ho",
                "artist_name": "Misc Soundtrack", "type": "Chords", "version": version,
                "rating": rating, "votes": votes, "tonality_name": "Em",
                "tab_url": "https://tabs.ultimate-guitar.com/tab/misc-soundtrack/"
                    + "aashiqui-2-tum-hi-ho-chords-\(id)",
                "recording": ["recording_artists": [["artist": ["name": "Arijit Singh"]]]],
            ]
        }

        /// One lyrics record whose repeated stanza the pipeline labels Chorus.
        static var lyricsRecord: String {
            let lyrics = """
            Lanterns on the water tonight
            Every boat is coming home

            Hold the light, hold the light
            Bring her home tonight

            Gulls above the breakwater
            Every window burning bright

            Hold the light, hold the light
            Bring her home tonight
            """
            let record: [String: Any] = [
                "id": 101, "trackName": "Tum Hi Ho", "artistName": "Arijit Singh",
                "albumName": "Aashiqui 2", "duration": 262, "instrumental": false,
                "plainLyrics": lyrics,
            ]
            return json(record)
        }

        private static func page(_ store: [String: Any]) -> String {
            let escaped = json(store)
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "<", with: "&lt;")
            return """
            <!doctype html><html><head><title>Fixture</title></head><body>
            <div class="js-store" data-content="\(escaped)"></div>
            </body></html>
            """
        }

        private static func json(_ object: Any) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
                ?? Data()
            return String(bytes: data, encoding: .utf8) ?? ""
        }
    }
#endif
