import ChordPro
import Foundation

/// The guard's verdict.
public enum LyricGuardVerdict: Sendable, Equatable, Hashable {
    case identical
    /// The lyric unit (top-level section, or run of loose lines) of the original that holds
    /// the first differing word.
    case differs(unit: Int)
}

/// Lyric preservation backstop (docs/decisions.md Language, safeguard 1): compares the lyric
/// token sequence of two documents. Tokens are compared exactly (case, accents and
/// punctuation included), so any respelling is caught; chords, directives, comments, tab
/// sections, bar lines and repeat marks are not lyrics.
///
/// The comparison is over the flat word sequence (R124): how words group into sections is not
/// a lyric. A relabel can turn adjacent sections into one run of loose lines (inline-chord
/// lines of an `other` block), which regroups the same words without changing any of them.
public enum LyricGuard {
    /// Compares `refined` against `original` word by word.
    public static func check(original: SongDocument, refined: SongDocument) -> LyricGuardVerdict {
        let units = units(of: original)
        let lhs = units.flatMap(\.self)
        let rhs = tokens(of: refined)
        guard lhs != rhs else { return .identical }
        let common = zip(lhs, rhs).prefix { $0 == $1 }.count
        // The unit of `original` that holds the first differing word (or the last unit when
        // `refined` only adds words at the end).
        var end = 0
        for (unit, words) in units.enumerated() {
            end += words.count
            if common < end {
                return .differs(unit: unit)
            }
        }
        return .differs(unit: max(units.count - 1, 0))
    }

    /// Lyric words per unit: each top-level section is a unit, and so is each run of
    /// top-level lines between sections. Units without words are skipped.
    public static func units(of document: SongDocument) -> [[String]] {
        var units: [[String]] = []
        var loose: [String] = []
        for block in document.blocks {
            switch block {
            case let .line(line):
                loose += tokens(of: line)
            case let .section(section) where section.kind != .tab:
                if !loose.isEmpty {
                    units.append(loose)
                    loose = []
                }
                let words = section.items.flatMap { item -> [String] in
                    if case let .line(line) = item {
                        return tokens(of: line)
                    }
                    return []
                }
                if !words.isEmpty {
                    units.append(words)
                }
            default:
                continue
            }
        }
        if !loose.isEmpty {
            units.append(loose)
        }
        return units
    }

    /// Every lyric word of `document`, in order.
    public static func tokens(of document: SongDocument) -> [String] {
        units(of: document).flatMap(\.self)
    }

    /// The lyric words of a parsed line (chord text excluded).
    public static func tokens(of line: Line) -> [String] {
        words(line.segments.map(\.text).joined())
    }

    /// The lyric words of a raw source line (inline `[chords]` removed).
    public static func tokens(ofSourceLine text: String) -> [String] {
        words(text.replacing(/\[[^\[\]]*\]/, with: ""))
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { word in
                word.contains { $0.isLetter || $0.isNumber } && !ChordLines.isRepeatMark(word)
            }
    }
}
