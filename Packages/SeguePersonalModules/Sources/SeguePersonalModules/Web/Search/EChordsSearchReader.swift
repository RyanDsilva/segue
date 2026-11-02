import Foundation
import Plugins
import SwiftSoup

/// E-Chords search (spec 6.11, bake-off 2.2): the site's own `/api/search` JSON, called from
/// inside the search page in the hidden view; the rendered `a.song-item` rows as the
/// fallback. No rating or votes, so hits with the same loose title and artist nest under one
/// song and songs keep the site's order.
enum EChordsSearchReader {
    static func searchPage(for query: String) -> URL? {
        let path = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
        return URL(string: "https://www.e-chords.com/search-all/" + path)
    }

    /// The in-page API call; every `*_take` must be 1-30 or the API answers 422.
    static func apiPath(for query: String) -> String {
        var components = URLComponents()
        components.path = "/api/search"
        components.queryItems = [URLQueryItem(name: "q", value: query)]
            + [
                "songs_take": "15",
                "lyrics_take": "1",
                "artists_take": "1",
                "albums_take": "1",
                "videos_take": "1",
                "composers_take": "1",
            ].sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.string ?? "/api/search"
    }

    static func read(json text: String) -> [SearchSong]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let hits = HTMLText.value(object, ["songs", "hits"]) as? [Any]
        else { return nil }
        return nest(hits.compactMap { hit -> SearchCandidate? in
            guard let title = HTMLText.string(hit, ["TITULO"]),
                  let artistCode = HTMLText.string(hit, ["COD_ARTISTA"]),
                  let titleCode = HTMLText.string(hit, ["COD_TITULO"]),
                  let page =
                  URL(string: "https://www.e-chords.com/chords/\(artistCode)/\(titleCode)")
            else { return nil }
            return candidate(
                id: HTMLText.string(hit, ["ID_MUSICA"]) ?? "\(artistCode)/\(titleCode)",
                title: title,
                artist: HTMLText.string(hit, ["ARTISTA"]),
                page: page,
            )
        })
    }

    /// The rendered results list, when the JSON call failed.
    static func read(html: String, url: URL) -> [SearchSong]? {
        guard let document = HTMLText.document(html, url: url),
              let rows = try? document.select("a.song-item[href^=/chords/]").array(), !rows.isEmpty
        else { return nil }
        return nest(rows.compactMap { row -> SearchCandidate? in
            guard let href = try? row.attr("href"),
                  let page = URL(string: href, relativeTo: URL(string: "https://www.e-chords.com"))?
                      .absoluteURL,
                  let title = try? row.select("strong.song").first()?.text(), !title.isEmpty
            else { return nil }
            return candidate(
                id: href,
                title: title,
                artist: try? row.select("span.artist").first()?.text(),
                page: page,
            )
        })
    }

    private static func candidate(
        id: String,
        title: String,
        artist: String?,
        page: URL,
    ) -> SearchCandidate {
        let fields = SourceCredits.fields(songName: title, artist: artist)
        return SearchCandidate(
            id: id,
            title: fields.title ?? title,
            artist: SourceCredits.credit(artist),
            album: fields.album,
            kind: .chords,
            pageURL: page,
        )
    }

    /// Hits with the same loose title and artist become one song, in the site's order.
    static func nest(_ candidates: [SearchCandidate]) -> [SearchSong] {
        var order: [String] = []
        var groups: [String: [SearchCandidate]] = [:]
        for candidate in candidates {
            let key = loose(candidate.title) + "|" + loose(candidate.artist ?? "")
            if groups[key] == nil {
                order.append(key)
            }
            var versioned = candidate
            versioned.songKey = key
            groups[key, default: []].append(versioned)
        }
        return order.compactMap { key in
            guard let versions = groups[key], let first = versions.first else { return nil }
            return SearchSong(
                key: key,
                title: first.title,
                artist: first.artist,
                album: first.album,
                versions: versions,
            )
        }
    }

    private static func loose(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }
}
