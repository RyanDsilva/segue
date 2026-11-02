import Foundation
import Plugins

/// What a page reader made of one page, before provenance is added (spec 8.3, 8.4).
struct ParsedChart: Sendable, Hashable {
    /// Chords over lyrics, inline `[C]hords` or bare lyrics, for the ingest pipeline.
    var text: String
    var fields: SourceFields
    /// The chart was found by the content-search fallback (UG, spec 8.4).
    var foundByContentSearch = false
    /// How many chords the page marked up as chords (E-Chords' `data-chord` spans), for the
    /// sanity check that catches chords glued into words.
    var chordMarks: Int?
}

/// A reader's verdict on a page.
enum PageReading: Sendable, Hashable {
    case chart(ParsedChart)
    /// The page is readable but holds no chart Segue imports (a tab, a Pro page, a removed
    /// song): reported as is, never handed to the generic reader.
    case refused(NoChartReason)
    /// This reader found nothing it recognises: the generic reader tries next.
    case unreadable
}

/// Credits as chord sites write them (spec 5.4).
enum SourceCredits {
    /// UG's and E-Chords' placeholder artists ("Misc Soundtrack", "Misc Unsigned Bands").
    static func isPlaceholderArtist(_ artist: String) -> Bool {
        artist.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("misc ")
    }

    /// A film song's "<Movie> - <Title>" name under a placeholder artist (R194). One " - " is
    /// split by code. With more, the fields hold the fallback split at the last " - ", every
    /// possible split, and the title is flagged until the model picks one
    /// (`FilmTitleResolver`). Any other artist: the name is the title as written.
    static func fields(songName: String, artist: String?) -> SourceFields {
        let name = songName.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = name.components(separatedBy: " - ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let artist, isPlaceholderArtist(artist), parts.count >= 2,
              !parts.contains(where: \.isEmpty)
        else { return SourceFields(title: name) }
        let splits = (1 ..< parts.count).map { cut in
            TitleSplit(
                title: parts[cut...].joined(separator: " - "),
                album: parts[..<cut].joined(separator: " - "),
            )
        }
        guard let fallback = splits.last else { return SourceFields(title: name) }
        return SourceFields(
            title: fallback.title,
            album: fallback.album,
            titleSplits: splits.count > 1 ? splits : [],
            titleUncertain: splits.count > 1,
        )
    }

    /// The single-split reading (title, album), for callers that need only the pair.
    static func titleAndAlbum(
        songName: String,
        artist: String?,
    ) -> (title: String, album: String?) {
        let fields = fields(songName: songName, artist: artist)
        return (fields.title ?? songName, fields.album)
    }

    /// The artist credit to use: nil for a placeholder, else the value trimmed.
    static func credit(_ artist: String?) -> String? {
        guard let artist = artist?.trimmingCharacters(in: .whitespacesAndNewlines), !artist.isEmpty,
              !isPlaceholderArtist(artist)
        else { return nil }
        return artist
    }
}
