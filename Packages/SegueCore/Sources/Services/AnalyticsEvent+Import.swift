import Foundation

// P9-4 spec 12: web import and song search analytics, rows 33-35 of the closed vocabulary
// (the spec's rows 31-32 went to P9-1 and P9-3 first). Personal build only: only the personal
// package emits them, so only its own TelemetryDeck app receives them. These cases ship in
// both binaries, so no raw value names a site or a service (R179): readers and search groups
// are named by technique. Never the URL, host, query, title, artist, lyrics, record id or an
// HTTP status code.

// MARK: - Row 33: Segue.Import.pageRead

/// One Import action on a page address or a saved page file.
public struct PageReadSummary: Sendable, Hashable {
    public var reader: ImportReader
    /// A site reader failed its checks and the general page reader answered.
    public var fellBack: Bool
    /// The chart was found by the content-search fallback.
    public var contentSearch: Bool
    public var outcome: WebImportOutcome
    public var latency: LatencyBucket
    public var entry: WebImportEntryPoint
    public var loadPath: ImportLoadPath
    /// The hidden WebKit load still met a check.
    public var webKitBlocked: Bool
    public var challenge: ImportChallenge
    /// The owner completed a check with Open Here.
    public var openedHere: Bool
    /// A cold cookie store loaded the site's home page first.
    public var warmUp: Bool

    public init(
        reader: ImportReader,
        fellBack: Bool,
        contentSearch: Bool,
        outcome: WebImportOutcome,
        latency: LatencyBucket,
        entry: WebImportEntryPoint,
        loadPath: ImportLoadPath,
        webKitBlocked: Bool,
        challenge: ImportChallenge,
        openedHere: Bool,
        warmUp: Bool,
    ) {
        self.reader = reader
        self.fellBack = fellBack
        self.contentSearch = contentSearch
        self.outcome = outcome
        self.latency = latency
        self.entry = entry
        self.loadPath = loadPath
        self.webKitBlocked = webKitBlocked
        self.challenge = challenge
        self.openedHere = openedHere
        self.warmUp = warmUp
    }

    var params: [String: String] {
        [
            "segue.reader": reader.rawValue,
            "segue.fellBack": String(fellBack),
            "segue.contentSearch": String(contentSearch),
            "segue.outcome": outcome.rawValue,
            "segue.latency": latency.rawValue,
            "segue.entry": entry.rawValue,
            "segue.loadPath": loadPath.rawValue,
            "segue.webKitBlocked": String(webKitBlocked),
            "segue.challenge": challenge.rawValue,
            "segue.openedHere": String(openedHere),
            "segue.warmUp": String(warmUp),
        ]
    }
}

// MARK: - Row 34: Segue.Import.searched

/// One Find Lyrics search (one Return).
public struct SongSearchedSummary: Sendable, Hashable {
    public var results: SmallBucket
    /// Groups that returned at least one result (0-3).
    public var groupsWithResults: SmallBucket
    public var groupsFailed: SmallBucket
    /// Lyrics-record 503 retries this search needed.
    public var lyricsRetries: SmallBucket
    /// Romanized-Hindi variant queries that ran (0-2).
    public var variants: SmallBucket
    public var outcome: SongSearchOutcome
    public var romanHindiQuery: Bool
    /// To the first group's answer.
    public var latency: LatencyBucket

    public init(
        results: SmallBucket,
        groupsWithResults: SmallBucket,
        groupsFailed: SmallBucket,
        lyricsRetries: SmallBucket,
        variants: SmallBucket,
        outcome: SongSearchOutcome,
        romanHindiQuery: Bool,
        latency: LatencyBucket,
    ) {
        self.results = results
        self.groupsWithResults = groupsWithResults
        self.groupsFailed = groupsFailed
        self.lyricsRetries = lyricsRetries
        self.variants = variants
        self.outcome = outcome
        self.romanHindiQuery = romanHindiQuery
        self.latency = latency
    }

    var params: [String: String] {
        [
            "segue.results": results.rawValue,
            "segue.groupsWithResults": groupsWithResults.rawValue,
            "segue.groupsFailed": groupsFailed.rawValue,
            "segue.lyricsRetries": lyricsRetries.rawValue,
            "segue.variants": variants.rawValue,
            "segue.outcome": outcome.rawValue,
            "segue.romanHindiQuery": String(romanHindiQuery),
            "segue.latency": latency.rawValue,
        ]
    }
}

// MARK: - Row 35: Segue.Import.searchPicked

/// A search result opened in the review (daily per group and rank bucket).
public struct SearchPickedSummary: Sendable, Hashable {
    public var group: ImportSearchGroup
    /// The song's rank in its group.
    public var rank: SmallBucket
    /// The version's rank under its song (0 for single-version groups).
    public var versionRank: SmallBucket
    /// Previews opened before the pick.
    public var previews: SmallBucket
    /// The result came from a variant query only.
    public var fromVariant: Bool
    public var romanized: Bool
    public var inLibrary: Bool

    public init(
        group: ImportSearchGroup,
        rank: SmallBucket,
        versionRank: SmallBucket,
        previews: SmallBucket,
        fromVariant: Bool,
        romanized: Bool,
        inLibrary: Bool,
    ) {
        self.group = group
        self.rank = rank
        self.versionRank = versionRank
        self.previews = previews
        self.fromVariant = fromVariant
        self.romanized = romanized
        self.inLibrary = inLibrary
    }

    var params: [String: String] {
        [
            "segue.group": group.rawValue,
            "segue.rank": rank.rawValue,
            "segue.versionRank": versionRank.rawValue,
            "segue.previews": previews.rawValue,
            "segue.fromVariant": String(fromVariant),
            "segue.romanized": String(romanized),
            "segue.inLibrary": String(inLibrary),
        ]
    }
}

// MARK: - Parameter values

/// Which reader turned the page into text, by technique (mirrors `Plugins.ReaderKind`).
public enum ImportReader: String, Sendable, CaseIterable {
    case tabJSON
    case chordPre
    case chordSpans
    case genericPage
    case lyricsRecord
}

/// How the page was read (mirrors `Plugins.LoadPath`).
public enum ImportLoadPath: String, Sendable, CaseIterable {
    case plain
    case webKit
    case savedFile
}

/// A search results group, by technique (mirrors `Plugins.SearchGroup`).
public enum ImportSearchGroup: String, Sendable, CaseIterable {
    case tabJSON
    case chordPre
    case lyricsRecord
}

/// The human-check type the hidden loader read (`cType`), or none.
public enum ImportChallenge: String, Sendable, CaseIterable {
    case noChallenge = "none"
    case nonInteractive
    case managed
    case interactive
    case unknown
}

public enum WebImportOutcome: String, Sendable, CaseIterable {
    case reviewed
    case noChart
    case blocked
    case challenged
    case backingOff
    case notFound
    case offline
    case busy
    case failed
    case cancelled
}

/// Where an Import from a web page started.
public enum WebImportEntryPoint: String, Sendable, CaseIterable {
    case menu
    case emptyState
    case sheetField
    case pastedURL
    case droppedLink
    case savedFile
}

public enum SongSearchOutcome: String, Sendable, CaseIterable {
    case results
    case noResults = "none"
    case busy
    case offline
    case failed
    case cancelled
}

extension AnalyticsEvent {
    var importParams: [String: String] {
        switch self {
        case let .importPageRead(summary): summary.params
        case let .importSearched(summary): summary.params
        case let .importSearchPicked(summary): summary.params
        default: [:]
        }
    }
}
