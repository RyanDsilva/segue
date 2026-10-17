/// Line-oriented ChordPro v0 parser (grammar in docs/phases/0-walking-skeleton.md).
///
/// Contract:
/// - Never throws or crashes on malformed input. Unclosed braces/brackets become text and
///   produce a `Diagnostic`; unbalanced sections are closed and diagnosed.
/// - `ChordProSerializer.serialize(parse(x).0) == x` byte-for-byte whenever parsing `x`
///   produced no structural diagnostics, and serialization is idempotent for any input.
/// - Parsing a 300-line song takes < 5 ms.
public enum ChordProParser {
    /// Parses ChordPro source into an AST plus diagnostics.
    public static func parse(_ source: String) -> (SongDocument, [Diagnostic]) {
        var builder = DocumentBuilder()
        let utf8 = source.utf8
        var lineStart = utf8.startIndex
        var lineNumber = 0
        while lineStart < utf8.endIndex {
            lineNumber += 1
            let newline = utf8[lineStart...].firstIndex(of: UInt8(ascii: "\n"))
            var contentEnd = newline ?? utf8.endIndex
            var ending = LineEnding.endOfFile
            if let newline {
                ending = .lf
                if newline > lineStart, utf8[utf8.index(before: newline)] == UInt8(ascii: "\r") {
                    ending = .crlf
                    contentEnd = utf8.index(before: newline)
                }
            }
            builder.consume(source[lineStart ..< contentEnd], ending: ending, line: lineNumber)
            lineStart = newline.map { utf8.index(after: $0) } ?? utf8.endIndex
        }
        return builder.finish()
    }
}

/// Assembles blocks line by line, tracking the open section.
private struct DocumentBuilder {
    private var blocks: [Block] = []
    private var openSection: Section?
    private var openSectionLine = 0
    private var diagnostics: [Diagnostic] = []

    mutating func consume(_ content: Substring, ending: LineEnding, line: Int) {
        let trivia = Trivia(source: String(content), lineEnding: ending)
        let utf8 = content.utf8
        let first = DirectiveSyntax.skipLeadingSpace(utf8)

        if first == utf8.endIndex {
            var blank = BlankLine()
            blank.trivia = trivia
            return append(.blank(blank))
        }
        if utf8[utf8.startIndex] == UInt8(ascii: "#") {
            var comment = FileComment(text: String(content[utf8.index(after: utf8.startIndex)...]))
            comment.trivia = trivia
            return append(.fileComment(comment))
        }
        if utf8[first] == DirectiveSyntax.openBrace {
            let column = Self.column(of: first, in: content)
            if let spelling = DirectiveSyntax.lex(content) {
                if !spelling.name.isEmpty {
                    return directive(spelling, trivia: trivia, line: line, column: column)
                }
                diagnose(line, column, "Directive has no name; kept as lyric text")
            } else if utf8[first...].contains(DirectiveSyntax.closeBrace) {
                diagnose(line, column, "Text after a directive's '}'; kept as lyric text")
            } else {
                diagnose(
                    line,
                    column,
                    "Unclosed '{': directive must end with '}'; kept as lyric text",
                )
            }
        }
        var lyric = lyricLine(content, line: line)
        lyric.trivia = trivia
        append(.line(lyric))
    }

    mutating func finish() -> (SongDocument, [Diagnostic]) {
        if let section = openSection {
            diagnose(
                openSectionLine,
                1,
                "Section '\(Self.startName(section.kind))' is never closed",
            )
            closeOpenSection()
        }
        return (SongDocument(blocks: blocks), diagnostics)
    }

    // MARK: - Directives

    private mutating func directive(
        _ spelling: DirectiveSpelling,
        trivia: Trivia,
        line: Int,
        column: Int,
    ) {
        let value = spelling.value.map(String.init)
        switch DirectiveSyntax.meaning(of: spelling.name) {
        case let .sectionStart(kind):
            startSection(kind, label: value, trivia: trivia, line: line, column: column)
        case let .sectionEnd(kind):
            endSection(kind, spelling: spelling, trivia: trivia, line: line, column: column)
        case .chorus:
            var ref = ChorusRef(label: value)
            ref.trivia = trivia
            append(.chorusRef(ref))
        case let .comment(style):
            var comment = CommentDirective(style: style, text: value ?? "")
            comment.trivia = trivia
            append(.commentDirective(comment))
        case let .other(name):
            if let value, let problem = Metadata.valueProblem(name: name, value: value) {
                diagnose(line, column, problem)
            }
            var directive = Directive(name: name, value: value)
            directive.trivia = trivia
            append(.directive(directive))
        }
    }

    private mutating func startSection(
        _ kind: SectionKind,
        label: String?,
        trivia: Trivia,
        line: Int,
        column: Int,
    ) {
        if let open = openSection {
            let openName = Self.startName(open.kind)
            diagnose(
                line,
                column,
                "Section '\(openName)' is not closed before a new section starts",
            )
            closeOpenSection()
        }
        var section = Section(kind: kind, label: label)
        section.startTrivia = trivia
        openSection = section
        openSectionLine = line
    }

    private mutating func endSection(
        _ kind: SectionKind,
        spelling: DirectiveSpelling,
        trivia: Trivia,
        line: Int,
        column: Int,
    ) {
        guard let open = openSection else {
            diagnose(line, column, "'\(spelling.name)' has no matching section start")
            var stray = Directive(
                name: DirectiveSyntax.canonicalName(spelling.name),
                value: spelling.value.map(String.init),
            )
            stray.trivia = trivia
            return append(.directive(stray))
        }
        if DirectiveSyntax.kindName(open.kind).lowercased()
            != DirectiveSyntax.kindName(kind).lowercased()
        {
            diagnose(
                line,
                column,
                "'\(spelling.name)' does not match the open '\(Self.startName(open.kind))'",
            )
        }
        openSection?.endTrivia = trivia
        closeOpenSection()
    }

    private mutating func append(_ block: Block) {
        if openSection != nil {
            openSection?.items.append(block)
        } else {
            blocks.append(block)
        }
    }

    private mutating func closeOpenSection() {
        guard let section = openSection else { return }
        openSection = nil
        blocks.append(.section(section))
    }

    // MARK: - Lyric lines

    private mutating func lyricLine(_ content: Substring, line: Int) -> Line {
        let utf8 = content.utf8
        let openBracket = UInt8(ascii: "[")
        let closeBracket = UInt8(ascii: "]")
        var segments: [Segment] = []
        var chord: String?
        var textStart = utf8.startIndex
        var index = utf8.startIndex
        while index < utf8.endIndex {
            let byte = utf8[index]
            if byte == openBracket {
                var scan = utf8.index(after: index)
                while scan < utf8.endIndex, utf8[scan] != closeBracket, utf8[scan] != openBracket {
                    scan = utf8.index(after: scan)
                }
                if scan < utf8.endIndex, utf8[scan] == closeBracket {
                    if chord != nil || textStart < index {
                        segments.append(Segment(
                            chord: chord,
                            text: String(content[textStart ..< index]),
                        ))
                    }
                    chord = String(content[utf8.index(after: index) ..< scan])
                    index = utf8.index(after: scan)
                    textStart = index
                    continue
                }
                diagnose(
                    line,
                    Self.column(of: index, in: content),
                    "Unclosed '['; kept as lyric text",
                )
            } else if byte == closeBracket {
                diagnose(line, Self.column(of: index, in: content), "']' without a matching '['")
            }
            index = utf8.index(after: index)
        }
        if chord != nil || textStart < utf8.endIndex || segments.isEmpty {
            segments.append(Segment(chord: chord, text: String(content[textStart...])))
        }
        return Line(segments: segments)
    }

    // MARK: - Helpers

    private mutating func diagnose(_ line: Int, _ column: Int, _ message: String) {
        diagnostics.append(Diagnostic(line: line, column: column, message: message))
    }

    private static func column(of index: Substring.Index, in content: Substring) -> Int {
        content[content.startIndex ..< index].count + 1
    }

    private static func startName(_ kind: SectionKind) -> String {
        DirectiveSyntax.startPrefix + DirectiveSyntax.kindName(kind)
    }
}
