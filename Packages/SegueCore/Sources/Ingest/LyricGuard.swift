import ChordPro
import Foundation

/// The guard's verdict.
public enum LyricGuardVerdict: Sendable, Equatable, Hashable {
    case identical
    /// The first lyric unit (top-level section, or run of loose lines) whose words differ.
    case differs(unit: Int)
}

/// Lyric preservation backstop (docs/decisions.md Language, safeguard 1): compares the lyric
/// token sequence of two documents. Tokens are compared exactly (case, accents and
/// punctuation included), so any respelling is caught; chords, directives, comments, tab
/// sections, bar lines and repeat marks are not lyrics.
public enum LyricGuard {
    /// Compares `refined` against `original`, unit by unit.
    public static func check(original: SongDocument, refined: SongDocument) -> LyricGuardVerdict {
        let lhs = units(of: original)
        let rhs = units(of: refined)
        for unit in 0 ..< max(lhs.count, rhs.count) {
            let left = unit < lhs.count ? lhs[unit] : []
            let right = unit < rhs.count ? rhs[unit] : []
            if left != right {
                return .differs(unit: unit)
            }
        }
        return .identical
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
