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

    /// A film song's "<Movie> - <Title>" name under a placeholder artist: split at the first
    /// " - " only then; otherwise the name is the title as written.
    static func titleAndAlbum(
        songName: String,
        artist: String?,
    ) -> (title: String, album: String?) {
        let name = songName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let artist, isPlaceholderArtist(artist), let dash = name.range(of: " - ") else {
            return (name, nil)
        }
        let movie = name[..<dash.lowerBound].trimmingCharacters(in: .whitespaces)
        let title = name[dash.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !movie.isEmpty, !title.isEmpty else { return (name, nil) }
        return (title, movie)
    }

    /// The artist credit to use: nil for a placeholder, else the value trimmed.
    static func credit(_ artist: String?) -> String? {
        guard let artist = artist?.trimmingCharacters(in: .whitespacesAndNewlines), !artist.isEmpty,
              !isPlaceholderArtist(artist)
        else { return nil }
        return artist
    }
}
