import Foundation
import Plugins
import Services

/// What one search did, for row 34.
struct SearchStats {
    var started: ContinuousClock.Instant?
    var firstAnswer: ContinuousClock.Instant?
    var romanHindi = false
    var variants = 0
    var retries = 0
    var results = 0
    var failures: [ImportFailure] = []
    var cancelled = false

    mutating func answered(results count: Int) {
        firstAnswer = firstAnswer ?? .now
        results += count
    }

    mutating func failed(_ failure: ImportFailure) {
        firstAnswer = firstAnswer ?? .now
        failures.append(failure)
    }

    func outcome(results total: Int) -> SongSearchOutcome {
        if cancelled {
            return .cancelled
        }
        if total > 0 {
            return .results
        }
        if failures.contains(.offline) {
            return .offline
        }
        if failures.contains(where: {
            if case .busy = $0 {
                true
            } else {
                false
            }
        }) {
            return .busy
        }
        return failures.isEmpty ? .noResults : .failed
    }
}

/// Each group's site: its attribution, link and own search page (spec 6.4, 6.8).
enum SearchSite {
    static func home(_ group: SearchGroup) -> URL {
        let address = switch group {
        case .tabJSON: "https://www.ultimate-guitar.com"
        case .chordPre: "https://www.e-chords.com"
        case .lyricsRecord: LRCLIBClient.base
        }
        return URL(string: address) ?? URL(filePath: "/")
    }

    static func attribution(_ group: SearchGroup) -> String {
        switch group {
        case .tabJSON: "Chords from Ultimate Guitar. Check them against the recording."
        case .chordPre: "Chords from E-Chords. Check them against the recording."
        case .lyricsRecord:
            "Lyrics from LRCLIB, a free community database. Check them against the recording."
        }
    }

    static func searchURL(_ group: SearchGroup, query: String) -> URL? {
        switch group {
        case .tabJSON: UGSearchReader.searchURL(for: query)
        case .chordPre: EChordsSearchReader.searchPage(for: query)
        case .lyricsRecord: nil
        }
    }
}
