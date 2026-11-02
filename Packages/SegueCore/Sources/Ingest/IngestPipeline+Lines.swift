import Foundation

// P9-4 spec 8.4 and 8.5: the line tests a page reader needs for its sanity checks and its
// candidate scoring, exposed so the personal package reads pages with the same rules as a
// paste. Pure.

public extension IngestPipeline {
    /// Whether `token` is a chord (or `N.C.`) by the paste pipeline's strict parsing.
    static func isChordToken(_ token: String) -> Bool {
        ChordLines.isChord(token)
    }

    /// Whether `line` is site junk the normalizer would drop (ads, print links, ratings).
    static func isJunkLine(_ line: String) -> Bool {
        JunkRules.match(line) != nil
    }

    /// The class of each line, as the paste pipeline sees them.
    static func lineClasses(_ lines: [String]) -> [LineClass] {
        FormatDetector.classify(lines)
    }
}
