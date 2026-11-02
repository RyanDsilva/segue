import Foundation

// P9-4 spec 4.2: the value types of the web import and song search contract. Core defines
// them; only `SeguePersonalModules` (Personal build) implements the protocols that use
// them. No site or service is named in any string here: the App Store build ships this file.

/// What a source already knows about the song, from structured data on the page or the
/// record. Code-found, so it wins over anything the text parser finds (spec 5.1).
public struct SourceFields: Sendable, Hashable {
    public var title: String?
    /// One credit string; split by `ArtistNames.split` like a credit line (R172, R173).
    public var artistCredit: String?
    /// Movie / Album, written as `{album}`.
    public var album: String?
    /// A stated key, kept only when `SongKey(parsing:)` reads it.
    public var key: String?
    public var capo: Int?
    /// R194: a film song name with more than one " - " ("Brahmāstra Part One - Shiva -
    /// Kesariya") is ambiguous. `title` and `album` then hold the fallback (split at the last
    /// " - "), `titleSplits` every possible split, and `titleUncertain` is true until a model
    /// picks one of them (or the review shows the field flagged).
    public var titleSplits: [TitleSplit]
    public var titleUncertain: Bool

    public init(
        title: String? = nil,
        artistCredit: String? = nil,
        album: String? = nil,
        key: String? = nil,
        capo: Int? = nil,
        titleSplits: [TitleSplit] = [],
        titleUncertain: Bool = false,
    ) {
        self.title = title
        self.artistCredit = artistCredit
        self.album = album
        self.key = key
        self.capo = capo
        self.titleSplits = titleSplits
        self.titleUncertain = titleUncertain
    }
}

/// One way to read a "<Movie> - <Title>" name.
public struct TitleSplit: Sendable, Hashable {
    public var title: String
    public var album: String

    public init(title: String, album: String) {
        self.title = title
        self.album = album
    }
}

/// Which reader turned a page or record into text. Analytics names these techniques, never
/// the sites (R179, spec 12).
public enum ReaderKind: String, Sendable, CaseIterable {
    case tabJSON
    case chordPre
    case chordSpans
    case genericPage
    case lyricsRecord
}

/// How the page was read (spec 8.6).
public enum LoadPath: String, Sendable, CaseIterable {
    case plain
    case webKit
    case savedFile
}

/// Where an imported song came from. Shown in the review header, never stored (R179).
public struct Provenance: Sendable, Hashable {
    public var sourceURL: URL
    public var reader: ReaderKind
    /// A site parser failed its checks and the generic reader answered.
    public var fellBack: Bool
    /// Devanagari text was romanized (spec 7).
    public var romanized: Bool
    public var loadPath: LoadPath
    /// The chart was found by the content-search fallback (spec 8.4).
    public var foundByContentSearch: Bool
    /// Set by the plugin and shown in the review header, e.g. "Lyrics from <source>".
    public var attribution: String?

    public init(
        sourceURL: URL,
        reader: ReaderKind,
        fellBack: Bool = false,
        romanized: Bool = false,
        loadPath: LoadPath = .plain,
        foundByContentSearch: Bool = false,
        attribution: String? = nil,
    ) {
        self.sourceURL = sourceURL
        self.reader = reader
        self.fellBack = fellBack
        self.romanized = romanized
        self.loadPath = loadPath
        self.foundByContentSearch = foundByContentSearch
        self.attribution = attribution
    }
}

/// One page or record turned into text the ingest pipeline reads.
public struct ImportedSong: Sendable, Hashable {
    /// Chords over lyrics, inline `[C]hords`, ChordPro or bare lyrics.
    public var text: String
    public var fields: SourceFields
    public var provenance: Provenance

    public init(text: String, fields: SourceFields, provenance: Provenance) {
        self.text = text
        self.fields = fields
        self.provenance = provenance
    }
}

/// What a `SongImporter` is asked to read.
public enum ImportInput: Sendable, Hashable {
    /// An `http(s)` page address.
    case url(URL)
    /// A saved page file (`.html`, `.htm`, `.webarchive`): no network.
    case webPageFile(URL)
}

/// The fixed heading order of the search results (R182): chord sources first, lyrics last.
public enum SearchGroup: Int, Sendable, CaseIterable {
    case tabJSON
    case chordPre
    case lyricsRecord
}

/// One search as the user typed it. Nothing in it is ever rewritten by a model (spec 6.3).
public struct SongQuery: Sendable, Hashable {
    public var text: String
    public var title: String?
    public var artist: String?

    public init(text: String, title: String? = nil, artist: String? = nil) {
        self.text = text
        self.title = title
        self.artist = artist
    }
}

/// Whether a search result is a chord chart or plain lyrics. Tab-only, Pro, Official and
/// advert rows never become candidates (R182).
public enum CandidateKind: String, Sendable, CaseIterable {
    case chords
    case lyrics
}

/// One search result.
public struct SearchCandidate: Sendable, Hashable, Identifiable {
    /// The source's stable record or tab id, as text.
    public var id: String
    public var title: String
    public var artist: String?
    public var album: String?
    public var kind: CandidateKind
    /// A site's version number of this song ("ver 3").
    public var version: Int?
    /// 0-5, as the site shows it.
    public var rating: Double?
    public var votes: Int?
    /// The first two lines, romanized when needed, when the search returned them.
    public var firstLines: String?
    public var isInstrumental: Bool
    /// Full plain lyrics when the search already returned them.
    public var lyrics: String?
    /// The chart page, for Open in Safari.
    public var pageURL: URL?
    /// Groups the versions of one song (a site's song id, or a normalized title and artist).
    public var songKey: String?
    /// Devanagari in the record was romanized for display (spec 6.5).
    public var romanized: Bool

    public init(
        id: String,
        title: String,
        artist: String? = nil,
        album: String? = nil,
        kind: CandidateKind,
        version: Int? = nil,
        rating: Double? = nil,
        votes: Int? = nil,
        firstLines: String? = nil,
        isInstrumental: Bool = false,
        lyrics: String? = nil,
        pageURL: URL? = nil,
        songKey: String? = nil,
        romanized: Bool = false,
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.kind = kind
        self.version = version
        self.rating = rating
        self.votes = votes
        self.firstLines = firstLines
        self.isInstrumental = isInstrumental
        self.lyrics = lyrics
        self.pageURL = pageURL
        self.songKey = songKey
        self.romanized = romanized
    }
}

/// Every way an import or search can fail. Closed: each case has one user message (spec 8.7)
/// and one analytics outcome (spec 12).
public enum ImportFailure: Error, Sendable, Hashable {
    case offline
    case timedOut
    /// HTTP 429 or 503; `retryAfter` from the response when it gave one.
    case busy(retryAfter: Duration?)
    /// The per-site back-off after a hard block (spec 9).
    case backingOff(retryAfter: Duration)
    /// A hard block (a 403 with no challenge page): Open Here cannot clear it.
    case blocked
    /// A human check still up after the hidden loader's wait: the only case offering Open Here.
    case challenged
    case notFound
    /// Not an `http(s)` page Segue may read, or not an HTML or text response.
    case notAPage
    /// Over the 5 MB body cap.
    case tooLarge
    /// No chord chart Segue can read on the page; the reason picks the message (spec 8.4).
    case noChart(NoChartReason)
    /// Text in a script Segue does not show (spec 6.5).
    case unsupportedScript
    case server(status: Int)
    case cancelled
}

/// Why a page has no chart Segue can read (spec 8.4, 8.7).
public enum NoChartReason: String, Sendable, CaseIterable {
    /// Nothing that reads as a chord chart: "Segue couldn't find a chord chart on this page."
    case notFound
    /// A tab-only page: "This page is a tab, not a chord chart."
    case tab
    /// A Pro or Power page: "Pro pages have no chord chart Segue can read."
    case pro
    /// A copyright removal notice in place of the chart: "The site has removed this song."
    case removed
}
