import Foundation

/// Renders blocks as ChordPro: chords over lyrics merged by column, headers as sections
/// (`{start_of_<kind>: <header text>}`), unheaded blocks as `{start_of_verse}` placeholders,
/// tab as `{start_of_tab}`, inline ChordPro and directives copied untouched.
enum Converter {
    /// What to render beyond the blocks.
    struct Context {
        /// Metadata directives to write at the top (fields not already in the source).
        var headerDirectives: [String]
        /// Lines whose metadata was used (dropped from the body).
        var consumedLines: Set<Int>
    }

    static func render(_ blocks: [IngestBlock], context: Context) -> String {
        var chunks: [[String]] = []
        if !context.headerDirectives.isEmpty {
            chunks.append(context.headerDirectives)
        }
        for block in blocks {
            let lines = render(block, context: context)
            if !lines.isEmpty {
                chunks.append(lines)
            }
        }
        return chunks.map { $0.joined(separator: "\n") }.joined(separator: "\n\n") + "\n"
    }

    // MARK: - Blocks

    private static func render(_ block: IngestBlock, context: Context) -> [String] {
        switch block.role {
        case .passthrough:
            return block.lines.map(\.text)
        case .metadata:
            return block.lines.compactMap { note($0, context: context) }
        case .content:
            if block.label == .other {
                return block.lines.compactMap { note($0, context: context) }
            }
            return section(block, context: context)
        }
    }

    /// A line of a metadata block: directives as written, used metadata dropped, anything
    /// else as a `{comment}`.
    private static func note(_ line: IngestLine, context: Context) -> String? {
        switch line.lineClass {
        case .blank:
            nil
        case .directive:
            directiveLine(line.text)
        case .metadata where context.consumedLines.contains(line.index):
            nil
        case .lyricLine where ChordLines.hasInlineChords(line.text):
            line.text
        default:
            comment(line.text)
        }
    }

    private static func section(_ block: IngestBlock, context: Context) -> [String] {
        var body = block.lines.filter { $0.lineClass != .headerLine }
        let header = block.header
        if let trailing = header?.trailingChords, let first = block.lines.first {
            body.insert(
                IngestLine(index: first.index, text: trailing, lineClass: .chordLine),
                at: 0,
            )
        }
        guard !body.isEmpty else {
            // A header with nothing under it: a chorus repeat, else a visible note.
            guard let header else { return [] }
            return header.label == .chorus
                ? ["{chorus: \(header.text)}"]
                : [comment(header.text)]
        }
        let name = block.label?.sectionName ?? "verse"
        var labelText = header?.text
        var output: [String] = []
        for run in runs(body) {
            let kind = run.isTab ? "tab" : name
            let start = labelText.map { "{start_of_\(kind): \($0)}" } ?? "{start_of_\(kind)}"
            labelText = nil
            output.append(start)
            output += lines(run.lines, context: context)
            output.append("{end_of_\(kind)}")
        }
        return output
    }

    /// Splits a body into tab and non-tab runs (a section cannot nest a tab section).
    static func runs(_ body: [IngestLine]) -> [(isTab: Bool, lines: [IngestLine])] {
        let isTab: (IngestLine) -> Bool = { $0.lineClass == .tab }
        guard body.contains(where: isTab) else { return [(false, body)] }
        // Notes such as "Standard tuning" ride along with the tab.
        if body.allSatisfy({ isTab($0) || $0.lineClass == .unknown }) {
            return [(true, body)]
        }
        var runs: [(isTab: Bool, lines: [IngestLine])] = []
        for line in body {
            if let last = runs.last, last.isTab == isTab(line) {
                runs[runs.count - 1].lines.append(line)
            } else {
                runs.append((isTab(line), [line]))
            }
        }
        return runs
    }

    private static func lines(_ body: [IngestLine], context: Context) -> [String] {
        var output: [String] = []
        var index = 0
        while index < body.count {
            let line = body[index]
            switch line.lineClass {
            case .chordLine:
                if index + 1 < body.count, body[index + 1].lineClass == .lyricLine,
                   !ChordLines.hasInlineChords(body[index + 1].text)
                {
                    output.append(ColumnAligner.merge(
                        chords: line.text,
                        lyric: body[index + 1].text,
                    ))
                    index += 2
                    continue
                }
                output.append(ColumnAligner.chordsOnly(line.text))
            case .lyricLine, .tab:
                output.append(line.text)
            case .directive:
                output.append(directiveLine(line.text))
            case .metadata where context.consumedLines.contains(line.index):
                break
            case .blank:
                break
            case .headerLine, .metadata, .unknown:
                output.append(comment(line.text))
            }
            index += 1
        }
        return output
    }

    // MARK: - Lines

    /// A directive line as written; a lone repeat mark becomes a comment.
    private static func directiveLine(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return ChordLines.isRepeatMark(trimmed) ? comment(trimmed) : trimmed
    }

    static func comment(_ text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "{", with: "(")
            .replacingOccurrences(of: "}", with: ")")
        return "{comment: \(cleaned)}"
    }
}

/// Column alignment of a chord line onto the lyric line under it.
public enum ColumnAligner {
    /// Inserts each chord before the lyric character in its column (a chord over a space
    /// attaches to the word after it); chords past the end of the lyric follow it, one space
    /// apart. Bar lines are dropped; repeat marks go to the end of the line.
    public static func merge(chords: String, lyric: String) -> String {
        let characters = Array(lyric)
        var result = ""
        var position = 0
        var repeats: [String] = []
        var pastEnd = false
        let tokens = ChordLines.tokens(chords).filter { token in
            switch ChordLines.kind(of: token.text) {
            case .decoration:
                return false
            case .repeatMark:
                repeats.append(token.text)
                return false
            case .chord, .unknown:
                return true
            }
        }
        for (offset, token) in tokens.enumerated() {
            if !pastEnd, token.column <= characters.count {
                let limit = offset + 1 < tokens.count ? tokens[offset + 1].column : characters.count
                var column = max(token.column, position)
                while column < characters.count, column + 1 < limit, characters[column] == " " {
                    column += 1
                }
                result += String(characters[position ..< column])
                position = column
                result += "[\(token.text)]"
            } else {
                if !pastEnd {
                    result += String(characters[position...])
                    position = characters.count
                    pastEnd = true
                }
                result += " [\(token.text)]"
            }
        }
        result += String(characters[position...])
        for mark in repeats {
            result += " \(mark)"
        }
        return result
    }

    /// A chord line with no lyric under it: chords bracketed in place, spacing, bar lines
    /// and repeat marks kept as text, leading indentation dropped.
    public static func chordsOnly(_ line: String) -> String {
        let characters = Array(line)
        var result = ""
        var position = 0
        for token in ChordLines.tokens(line) {
            if position > 0 || !result.isEmpty {
                result += String(characters[position ..< token.column])
            }
            switch ChordLines.kind(of: token.text) {
            case .chord, .unknown: result += "[\(token.text)]"
            case .decoration, .repeatMark: result += token.text
            }
            position = token.column + token.text.count
        }
        return result
    }
}
