import Foundation
import MusicTheory

/// A whitespace-separated token and the column (in `Character`s) where it starts.
struct ColumnToken: Equatable {
    var text: String
    var column: Int
}

/// What a chord-line token is.
enum ChordLineTokenKind: Equatable {
    /// Parses as a chord (strict MusicTheory) or is an explicit no-chord.
    case chord
    /// Bar lines, slashes, dots: layout only.
    case decoration
    /// `x2`, `(x2)`, `2x`.
    case repeatMark
    /// Anything else (kept, flagged by the validator).
    case unknown
}

/// Chord-line, tab-line and repeat-mark recognition (FormatDetector's line tests).
enum ChordLines {
    /// Splits `line` on spaces, keeping each token's starting column.
    static func tokens(_ line: String) -> [ColumnToken] {
        var result: [ColumnToken] = []
        var current = ""
        var start = 0
        for (column, character) in line.enumerated() {
            if character == " " {
                if !current.isEmpty {
                    result.append(ColumnToken(text: current, column: start))
                    current = ""
                }
            } else {
                if current.isEmpty {
                    start = column
                }
                current.append(character)
            }
        }
        if !current.isEmpty {
            result.append(ColumnToken(text: current, column: start))
        }
        return result
    }

    static func kind(of token: String) -> ChordLineTokenKind {
        if isRepeatMark(token) {
            return .repeatMark
        }
        if decorations.contains(token) {
            return .decoration
        }
        return isChord(token) ? .chord : .unknown
    }

    /// Whether `token` is a chord (or `N.C.`), allowing one pair of parentheses around it.
    static func isChord(_ token: String) -> Bool {
        var core = Substring(token)
        if core.count > 2, core.first == "(", core.last == ")" {
            core = core.dropFirst().dropLast()
        }
        switch ChordToken(parsing: String(core)) {
        case .chord, .noChord: return true
        case .unknown: return false
        }
    }

    /// A chord line: most tokens are chords and no stop word is used as a lyric
    /// (docs/phases/3-ai-entry-and-assistant.md section 3).
    static func isChordLine(_ line: String) -> Bool {
        if line.contains("[") || line.contains("{") {
            return false
        }
        var chords = 0
        var unknown = 0
        var usesStopWord = false
        for token in tokens(line) {
            switch kind(of: token.text) {
            case .chord:
                chords += 1
                if StopList.contains(token.text) {
                    usesStopWord = true
                }
            case .unknown:
                if StopList.contains(token.text) {
                    return false
                }
                unknown += 1
            case .decoration, .repeatMark:
                continue
            }
        }
        if usesStopWord, unknown > 0 {
            return false
        }
        return chords > 0 && chords > unknown
    }

    /// `x2`, `(x2)`, `X3`, `2x`, `(2x)`, `×2`.
    static func isRepeatMark(_ text: some StringProtocol) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.wholeMatch(of: /\(?\s*(?:[xX×]\s*\d{1,2}|\d{1,2}\s*[xX×])\s*\)?/) != nil
    }

    /// Guitar tab notation: `e|--0--3--|`, `B|-1-`, `|--3--|`.
    static func isTabLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.filter({ $0 == "-" }).count >= 4 else { return false }
        return trimmed.wholeMatch(of: /(?:[A-Ga-g][#b]?\s?)?[|:][-0-9|hpbrsxX\/\\~()*.^= \t]+/)
            != nil
    }

    /// Lyric text with inline `[chords]` (at least one bracket holds a chord).
    static func hasInlineChords(_ line: String) -> Bool {
        line.matches(of: /\[([^\[\]]+)\]/).contains { isChord(String($0.output.1)) }
    }

    /// The bracketed tokens of an inline ChordPro line, in order.
    static func inlineChords(_ line: String) -> [String] {
        line.matches(of: /\[([^\[\]]*)\]/).map { String($0.output.1) }
    }

    /// Tokens that only lay out a chord line.
    private static let decorations: Set = [
        "|", "||", "|:", ":|", "/", "//", "-", "--", ".", "..", "...", "%", "*", "~",
    ]
}
