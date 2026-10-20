import ChordPro
import Foundation
import MusicTheory

/// `{key}` validation for the editor (R81). It lives here rather than in the parser's
/// `valueProblem` because key parsing belongs to MusicTheory, which ChordPro does not
/// depend on. Every `{key}` line is checked (a song may change key mid-way).
extension SourceSnapshot {
    var keyDiagnostics: [EditorDiagnostic] {
        directiveLines(named: "key").compactMap { entry in
            guard let value = entry.directive.value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let line = map.lines[entry.line]
            let parsed = SongKey(parsing: trimmed)
            let repaired = KeyValueRepair.suggestion(for: trimmed)
            if parsed != nil, repaired == nil {
                return nil
            }
            let message = if parsed != nil, let repaired {
                "Key '\(trimmed)' is usually written \(repaired)"
            } else if let repaired {
                "Key '\(trimmed)' is not a key; did you mean \(repaired)?"
            } else {
                "Key '\(trimmed)' is not a key like G, Bb or F#m"
            }
            let lineRange = line.start ..< max(line.start, line.contentEnd)
            let fix = repaired.flatMap { replacement in
                valueRange(of: trimmed, in: line.text, lineStart: line.start).map { range in
                    DiagnosticFix(
                        title: "Change to \(replacement)",
                        change: SourceChange(
                            edits: [TextEdit(range: range, replacement: replacement)],
                            actionName: "Fix Key",
                        ),
                    )
                }
            }
            return EditorDiagnostic(
                range: lineRange,
                severity: .warning,
                kind: .malformedDirective,
                message: message,
                line: entry.line + 1,
                fix: fix,
            )
        }
    }

    /// UTF-16 range of the directive value inside `{name: value}` on a line.
    private func valueRange(of value: String, in text: String, lineStart: Int) -> Range<Int>? {
        let end = text.range(of: "}", options: .backwards)?.lowerBound ?? text.endIndex
        guard let found = text.range(of: value, options: .backwards, range: text.startIndex ..< end)
        else { return nil }
        let lower = lineStart + text[..<found.lowerBound].utf16.count
        return lower ..< lower + value.utf16.count
    }
}

/// The repair offered for a `{key}` value, when one is clear.
public enum KeyValueRepair {
    /// The canonical spelling to offer for `value`, or `nil` when it is already canonical
    /// or no repair is clear. Handles German `H` (`Hm` -> `Bm`), a lower-case tonic
    /// (`am` -> `Am`) and a spelled-out mode (`G major` -> `G`, `A minor` -> `Am`). The
    /// Unicode accidentals `♯` and `♭` count as canonical spellings of `#` and `b`.
    public static func suggestion(for value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let key = SongKey(parsing: trimmed) {
            let ascii = trimmed.replacingOccurrences(of: "♯", with: "#")
                .replacingOccurrences(of: "♭", with: "b")
            return key.name == ascii ? nil : key.name
        }
        guard let first = trimmed.first else { return nil }
        let rest = trimmed.dropFirst()
        let candidates = switch first {
        case "h", "H": ["B" + rest]
        default: [first.uppercased() + rest]
        }
        for candidate in candidates where candidate != trimmed {
            if let key = SongKey(parsing: candidate) {
                return key.name
            }
        }
        return nil
    }
}
