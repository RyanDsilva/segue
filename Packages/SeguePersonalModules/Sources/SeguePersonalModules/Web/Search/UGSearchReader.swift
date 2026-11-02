import Foundation
import Plugins

/// Ultimate Guitar's search results page (spec 6.10, bake-off 1.1): the results are JSON in
/// the same `js-store` element as a tab page (or `window.UGAPP.store` from the hidden view),
/// at `store.page.data.results`, mixed with marketing rows. Only chord versions are listed
/// (R182); versions of one `song_id` nest under one song, ranked by `VersionRanker`.
enum UGSearchReader {
    static let tabPrefix = "https://tabs.ultimate-guitar.com/tab/"

    static func searchURL(for query: String) -> URL? {
        var components = URLComponents(string: "https://www.ultimate-guitar.com/search.php")
        components?.queryItems = [
            URLQueryItem(name: "search_type", value: "title"),
            URLQueryItem(name: "value", value: query),
        ]
        return components?.url
    }

    /// The songs on the page, in the order of their best version's score; nil when the
    /// page holds no results store at all (a layout change or a challenge page).
    static func read(_ text: String, url: URL) -> [SearchSong]? {
        guard let store = TabJSONParser.store(in: text, url: url),
              let results = HTMLText.value(store, ["store", "page", "data", "results"]) as? [Any]
        else { return nil }
        let candidates = results.compactMap(candidate)
        var order: [String] = []
        var bySong: [String: [SearchCandidate]] = [:]
        for candidate in candidates {
            let key = candidate.songKey ?? candidate.id
            if bySong[key] == nil {
                order.append(key)
            }
            bySong[key, default: []].append(candidate)
        }
        let songs = order.compactMap { key -> (SearchSong, Double)? in
            let ranked = VersionRanker.rank(bySong[key] ?? [])
            guard let best = ranked.first else { return nil }
            let song = SearchSong(
                key: key,
                title: best.candidate.title,
                artist: best.candidate.artist,
                album: best.candidate.album,
                versions: ranked.map(\.candidate),
            )
            return (song, best.score)
        }
        return songs.enumerated()
            .sorted {
                $0.element.1 == $1.element.1 ? $0.offset < $1.offset : $0.element.1 > $1.element.1
            }
            .map(\.element.0)
    }

    /// A result row as a chord-version candidate, or nil for marketing, tab-only, Pro,
    /// Official and video rows (R182).
    static func candidate(_ row: Any) -> SearchCandidate? {
        guard let id = HTMLText.value(row, ["id"]) as? Int,
              let type = HTMLText.string(row, ["type"])?.lowercased(),
              TabJSONParser.chordTypes.contains(type),
              let link = HTMLText.string(row, ["tab_url"]), link.hasPrefix(tabPrefix),
              let pageURL = URL(string: link),
              let name = HTMLText.string(row, ["song_name"])
        else { return nil }
        let artist = HTMLText.string(row, ["artist_name"])
        var fields = SourceCredits.fields(songName: name, artist: artist)
        let singers = ((HTMLText.value(row, ["recording", "recording_artists"]) as? [Any]) ?? [])
            .compactMap { HTMLText.string($0, ["artist", "name"]) }
        fields.artistCredit = SourceCredits
            .credit(artist) ?? (singers.isEmpty ? nil : singers.joined(separator: ", "))
        return SearchCandidate(
            id: String(id),
            title: fields.title ?? name,
            artist: fields.artistCredit,
            album: fields.album,
            kind: .chords,
            version: HTMLText.int(row, ["version"]),
            rating: (HTMLText.value(row, ["rating"]) as? NSNumber)?.doubleValue,
            votes: HTMLText.int(row, ["votes"]),
            pageURL: pageURL,
            songKey: HTMLText.string(row, ["song_id"]),
        )
    }
}
