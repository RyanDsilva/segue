import Foundation
import Plugins

/// Ultimate Guitar's search (spec 6.10): `search.php` as a plain request, the hidden view when
/// it is challenged; chord versions only, ranked per song.
struct UGSearchSource: SongSearchSource {
    let id = "dev.ryandsilva.segue.search.tab-json"
    let displayName = "Ultimate Guitar"
    let group = SearchGroup.tabJSON
    var services: WebImportServices

    func search(_ query: SongQuery) async throws(ImportFailure) -> [SearchCandidate] {
        guard let url = UGSearchReader.searchURL(for: query.text) else { throw .notAPage }
        let page = try await services.fetcher.fetch(
            PageLoadRequest(url: url, marker: .tabStore, backsOff: true), route: .plainFirst,
        )
        guard let songs = UGSearchReader.read(page.text, url: url)
        else { throw .noChart(.notFound) }
        return songs.prefix(20).flatMap(\.versions)
    }

    func song(for candidate: SearchCandidate) async throws(ImportFailure) -> ImportedSong {
        guard let page = candidate.pageURL else { throw .notFound }
        var song = try await services.importPage(page)
        song.provenance.attribution = Self.attribution(candidate)
        return song
    }

    /// The review's source line for a picked version (spec 6.10): "From Ultimate Guitar ·
    /// ver 3 · ★4.8".
    static func attribution(_ candidate: SearchCandidate) -> String {
        var parts = ["From Ultimate Guitar"]
        if let version = candidate.version {
            parts.append("ver \(version)")
        }
        if let rating = candidate.rating {
            parts.append("★" + rating.formatted(.number.precision(.fractionLength(1))))
        }
        return parts.joined(separator: " · ")
    }
}

/// E-Chords' search (spec 6.11): the search page in the hidden view, the site's own JSON API
/// called from inside it.
struct EChordsSearchSource: SongSearchSource {
    let id = "dev.ryandsilva.segue.search.chord-pre"
    let displayName = "E-Chords"
    let group = SearchGroup.chordPre
    var services: WebImportServices

    func search(_ query: SongQuery) async throws(ImportFailure) -> [SearchCandidate] {
        guard let page = EChordsSearchReader.searchPage(for: query.text) else { throw .notAPage }
        let request = PageLoadRequest(
            url: page,
            marker: .document,
            inPageFetch: EChordsSearchReader.apiPath(for: query.text),
            backsOff: true,
        )
        let loaded = try await services.fetcher.fetch(request, route: .webKitOnly)
        guard let songs = EChordsSearchReader.read(json: loaded.text) ?? EChordsSearchReader.read(
            html: loaded.text,
            url: page,
        )
        else { throw .noChart(.notFound) }
        return songs.prefix(20).flatMap(\.versions)
    }

    func song(for candidate: SearchCandidate) async throws(ImportFailure) -> ImportedSong {
        guard let page = candidate.pageURL else { throw .notFound }
        var song = try await services.importPage(page)
        song.provenance.attribution = "From E-Chords"
        return song
    }
}

/// LRCLIB lyrics search (spec 6.2-6.7): the query as typed, then up to two romanized-Hindi
/// variants when the answer is thin, merged and ranked locally; Devanagari romanized.
struct LyricsSearchSource: SongSearchSource {
    let id = "dev.ryandsilva.segue.search.lyrics-record"
    let displayName = "LRCLIB"
    let group = SearchGroup.lyricsRecord
    var services: WebImportServices
    /// Hears the variant queries that ran and each 503 retry, for the "Also searched" and
    /// "busy, retrying" lines.
    var onVariants: @Sendable ([String]) -> Void = { _ in }
    var onRetry: @Sendable (Int) -> Void = { _ in }

    func search(_ query: SongQuery) async throws(ImportFailure) -> [SearchCandidate] {
        var records = try await records(query.text)
        let variants = LyricsQueryVariants.variants(
            for: query.text,
            firstAnswerCount: records.count,
        )
        for variant in variants {
            await records += (try? self.records(variant)) ?? []
        }
        onVariants(variants)
        return LyricsRanker.rank(records, query: query.text).prefix(20)
            .compactMap { Self.candidate($0.record) }
    }

    private func records(_ text: String) async throws(ImportFailure) -> [LyricsRecord] {
        if let cached = services.lyricsCache.value(for: text) {
            return cached
        }
        let found = try await services.lyrics.search(text, onRetry: onRetry)
        services.lyricsCache.store(found, for: text)
        return found
    }

    /// A record as a candidate, romanized. A record in a script Segue doesn't show is a
    /// greyed, unpickable row whose text in that script is never displayed (spec 6.5).
    static func candidate(_ record: LyricsRecord) -> SearchCandidate? {
        let fields = [record.trackName, record.artistName, record.albumName, record.plainLyrics]
            .compactMap(\.self).joined(separator: " ")
        guard !hasOtherScript(fields) else {
            return SearchCandidate(
                id: String(record.id),
                title: latinOnly(record.trackName) ?? "Untitled",
                artist: latinOnly(record.artistName),
                kind: .lyrics,
                isInstrumental: record.isInstrumental,
                unsupportedScript: true,
            )
        }
        let lyrics = record.plainLyrics.map(HindiRomanizer.romanize)
        return SearchCandidate(
            id: String(record.id),
            title: HindiRomanizer.romanize(record.trackName ?? ""),
            artist: record.artistName.map(HindiRomanizer.romanize),
            album: movieAlbum(record),
            kind: .lyrics,
            firstLines: lyrics.map { $0.split(separator: "\n").prefix(2).joined(separator: "\n") },
            isInstrumental: record.isInstrumental,
            lyrics: lyrics,
            pageURL: URL(string: LRCLIBClient.base + "/api/get/\(record.id)"),
            romanized: HindiRomanizer.containsDevanagari(fields),
        )
    }

    func song(for candidate: SearchCandidate) async throws(ImportFailure) -> ImportedSong {
        guard !candidate.unsupportedScript else { throw .unsupportedScript }
        guard !candidate.isInstrumental else { throw .noChart(.notFound) }
        guard let id = Int(candidate.id) else { throw .notFound }
        var record = try await services.lyrics.record(id: id)
        if record.plainLyrics == nil, let lyrics = candidate.lyrics {
            record.plainLyrics = lyrics
        }
        return try Self.song(record)
    }

    static func song(_ record: LyricsRecord) throws(ImportFailure) -> ImportedSong {
        guard let plain = record.plainLyrics, !plain.isEmpty else { throw .noChart(.notFound) }
        let source = [record.trackName, record.artistName, record.albumName, plain]
            .compactMap(\.self).joined()
        let text = LRCSections.text(
            plain: HindiRomanizer.romanize(plain),
            synced: record.syncedLyrics.map(HindiRomanizer.romanize),
        )
        let title = record.trackName.map(HindiRomanizer.romanize)
        let fields = SourceFields(
            title: title,
            artistCredit: record.artistName.map(HindiRomanizer.romanize),
            album: movieAlbum(record),
        )
        return ImportedSong(text: text, fields: fields, provenance: Provenance(
            sourceURL: URL(string: LRCLIBClient.base + "/api/get/\(record.id)") ??
                URL(filePath: "/"),
            reader: .lyricsRecord,
            romanized: HindiRomanizer.containsDevanagari(source),
            loadPath: .plain,
            attribution: "Lyrics from LRCLIB",
        ))
    }

    static func movieAlbum(_ record: LyricsRecord) -> String? {
        guard let name = record.albumName else { return nil }
        return album(album: HindiRomanizer.romanize(name), title: record.trackName)
    }

    /// `albumName` is Movie / Album unless it repeats the title or is generic (spec 5.4).
    static func album(album: String, title: String?) -> String? {
        let trimmed = album.trimmingCharacters(in: .whitespaces)
        let generic: Set = ["", "single", "unknown", "null", "-"]
        guard !generic.contains(trimmed.lowercased()),
              trimmed.lowercased() != title?.trimmingCharacters(in: .whitespaces).lowercased()
        else { return nil }
        return trimmed
    }

    /// The text when it holds only Latin letters (after romanizing Devanagari), else nil.
    static func latinOnly(_ text: String?) -> String? {
        guard let text = text.map(HindiRomanizer.romanize), !text.isEmpty,
              !text.unicodeScalars
                  .contains(where: { $0.properties.isAlphabetic && $0.value > 0x024F })
        else { return nil }
        return text
    }

    /// More than a few letters of a script other than Latin or Devanagari (spec 6.5).
    static func hasOtherScript(_ text: String) -> Bool {
        text.unicodeScalars.count { scalar in
            scalar.properties.isAlphabetic && scalar.value > 0x024F
                && !HindiRomanizer.isDevanagari(scalar)
        } > 3
    }
}
