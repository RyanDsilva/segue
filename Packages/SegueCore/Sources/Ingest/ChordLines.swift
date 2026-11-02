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
                // `Original Chords - D#, Cm, G#` lists the chords; it is not a chord line.
                if StopList.contains(token.text) || token.text.lowercased().contains("chord") {
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

    /// Chord-site sheets that write inline chords in parentheses (`(D#)Talwaron pe`, `Jo
    /// (Cm)tere`) get them as `[D#]` brackets, so they parse as inline ChordPro. Only when at
    /// least two lines carry a parenthesised chord that is not a stop word (`(Am)` alone could
    /// be a lyric); then every parenthesised chord on those lines is converted. Section headers
    /// such as `(Chorus)` are not chords and stay.
    static func bracketParenthesisedChords(_ lines: [String]) -> [String] {
        let pattern = /\(([A-G][^()\s]{0,9})\)/
        func chordGroups(_ line: String) -> [String] {
            line.matches(of: pattern).map { String($0.output.1) }.filter(isChord)
        }
        let carrying = lines.filter { line in
            chordGroups(line).contains { !StopList.contains($0) }
        }
        guard carrying.count >= 2 else { return lines }
        return lines.map { line in
            guard !chordGroups(line).isEmpty, !isRepeatMark(line) else { return line }
            // R198: on a line of chords only that mixes plain and bracketed chords
            // ("      (G)        D"), a bracketed chord is a
            // chord of that line: its brackets become spaces so the columns stay put and the
            // line still reads as a chord line, not a lyric with an inline chord.
            let tokens = line.split(separator: " ")
            let chordsOnly = tokens.contains { isChord(String($0)) && !$0.hasPrefix("(") }
                && tokens.allSatisfy { token in
                    let bare = token.hasPrefix("(") && token.hasSuffix(")")
                        ? token.dropFirst().dropLast() : token
                    return isChord(String(bare)) || isRepeatMark(String(token))
                        || decorations.contains(String(token))
                }
            return line.replacing(pattern) { match in
                guard isChord(String(match.output.1)) else { return String(match.output.0) }
                return chordsOnly ? " \(match.output.1) " : "[\(match.output.1)]"
            }
        }
    }

    /// A chord-shape legend line: a chord name, then its frets, then any note (`G 3-5-5-4-3-3`,
    /// `C: x32010`, `Em 0-2-2-0-3(3) (= Em7)`, `E- 022300`, `B-024400`), or a fingering on its
    /// own (`320033`, `x-3-2-0-1-0`) under the chord it shapes (R142).
    static func isChordLegend(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.wholeMatch(of: /[xX0-9]{6}|[xX0-9]{1,2}(?:-[xX0-9]{1,2}){5}/) != nil {
            return trimmed.contains(where: \.isNumber)
        }
        let pattern = #/
        (\S+?) (?: \s* [:\-] \s* | \s+ )
        (?: [xX0-9]{4,6} | [xX0-9]{1,2} (?: [-\s] [xX0-9]{1,2} ){3,5} )
        (?: \( \d{1,2} \) )? (?: \s .* )?
        /#
        guard let match = trimmed.wholeMatch(of: pattern) else { return false }
        return isChord(String(match.output.1))
    }

    /// A tuning line: string names joined by dashes or spaces (`E-A-D-G-B-e`, `D A D G A D`,
    /// `Eb-Ab-Db-Gb-Bb-Eb`), optionally after `Tuning:`.
    static func isTuningLine(_ line: String) -> Bool {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if let match = trimmed.wholeMatch(of: /(?i)tuning\s*:?\s*(.*)/) {
            trimmed = String(match.output.1)
        }
        return trimmed.wholeMatch(of: /[A-Ga-g][#b]?(?:[-\s]+[A-Ga-g][#b]?){3,6}/) != nil
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
