/// Serializes a `SongDocument` back to ChordPro source.
///
/// Nodes that still carry their parsed `Trivia` and whose meaning is unchanged are written
/// exactly as they were read (alias, separator, whitespace, line ending). Edited nodes keep
/// whatever spelling still applies (e.g. `{t: ...}` stays `t` when only the value changed);
/// nodes built in code are written canonically (`{title: Value}`, `[G]lyric`). Lines with no
/// recorded ending use the document's first recorded ending, else `\n`.
public enum ChordProSerializer {
    /// Renders `document` as ChordPro text.
    public static func serialize(_ document: SongDocument) -> String {
        var writer = LineWriter(defaultEnding: defaultEnding(of: document.blocks) ?? .lf)
        for block in document.blocks {
            write(block, to: &writer)
        }
        return writer.text
    }

    private static func write(_ block: Block, to writer: inout LineWriter) {
        switch block {
        case let .blank(blank):
            let source = blank.trivia.source ?? ""
            let utf8 = source[...].utf8
            let isBlank = DirectiveSyntax.skipLeadingSpace(utf8) == utf8.endIndex
            writer.emit(isBlank ? source : "", blank.trivia)
        case let .chorusRef(ref):
            let text = directiveText(name: "chorus", value: ref.label, trivia: ref.trivia) {
                $0.map(String.init) == ref.label
            }
            writer.emit(text, ref.trivia)
        case let .commentDirective(comment):
            let name = DirectiveSyntax.commentName(comment.style)
            let value = comment.text.isEmpty ? nil : comment.text
            let text = directiveText(name: name, value: value, trivia: comment.trivia) {
                String($0 ?? "") == comment.text
            }
            writer.emit(text, comment.trivia)
        case let .directive(directive):
            let text = directiveText(
                name: directive.name, value: directive.value, trivia: directive.trivia,
            ) { $0.map(String.init) == directive.value }
            writer.emit(text, directive.trivia)
        case let .fileComment(comment):
            writer.emit("#" + comment.text, comment.trivia)
        case let .line(line):
            writer.emit(render(line), line.trivia)
        case let .section(section):
            write(section, to: &writer)
        }
    }

    private static func write(_ section: Section, to writer: inout LineWriter) {
        let kind = DirectiveSyntax.kindName(section.kind)
        let start = directiveText(
            name: DirectiveSyntax.startPrefix + kind, value: section.label,
            trivia: section.startTrivia,
        ) { $0.map(String.init) == section.label }
        writer.emit(start, section.startTrivia)
        for item in section.items {
            write(item, to: &writer)
        }
        let end = directiveText(
            name: DirectiveSyntax.endPrefix + kind, value: nil, trivia: section.endTrivia,
        ) { _ in true }
        writer.emit(end, section.endTrivia)
    }

    /// Canonical lyric line: `[chord]text` per segment.
    static func render(_ line: Line) -> String {
        var text = ""
        for segment in line.segments {
            if let chord = segment.chord {
                text += "[" + chord + "]"
            }
            text += segment.text
        }
        return text
    }

    /// Writes a directive, reusing as much of the recorded spelling as still applies.
    /// `valueMatches` says whether the spelled value still means the node's current value.
    private static func directiveText(
        name: String,
        value: String?,
        trivia: Trivia,
        valueMatches: (Substring?) -> Bool,
    ) -> String {
        guard let source = trivia.source,
              let spelling = DirectiveSyntax.lex(source[...]),
              !spelling.name.isEmpty
        else {
            return value.map { "{\(name): \($0)}" } ?? "{\(name)}"
        }
        let sameName = DirectiveSyntax.canonicalName(spelling.name) == name.lowercased()
        if sameName, valueMatches(spelling.value) {
            return source
        }
        var text = String(spelling.leading) + "{" + spelling.innerLeading
        text += sameName ? String(spelling.name) : name
        if let value {
            text += (spelling.separator.isEmpty ? ": " : String(spelling.separator)) + value
        }
        return text + spelling.innerTrailing + "}" + spelling.trailing
    }

    private static func defaultEnding(of blocks: [Block]) -> LineEnding? {
        for block in blocks {
            let trivia: Trivia
            switch block {
            case let .blank(blank): trivia = blank.trivia
            case let .chorusRef(ref): trivia = ref.trivia
            case let .commentDirective(comment): trivia = comment.trivia
            case let .directive(directive): trivia = directive.trivia
            case let .fileComment(comment): trivia = comment.trivia
            case let .line(line): trivia = line.trivia
            case let .section(section):
                if let ending = section.startTrivia.lineEnding, ending != .none {
                    return ending
                }
                if let ending = defaultEnding(of: section.items) {
                    return ending
                }
                trivia = section.endTrivia
            }
            if let ending = trivia.lineEnding, ending != .none {
                return ending
            }
        }
        return nil
    }
}

/// Joins lines, honouring each recorded ending. A line recorded without an ending (it was
/// the last line of its file) gets the default one if anything follows it.
private struct LineWriter {
    let defaultEnding: LineEnding
    private(set) var text = ""
    private var owesEnding = false

    init(defaultEnding: LineEnding) {
        self.defaultEnding = defaultEnding
    }

    mutating func emit(_ line: String, _ trivia: Trivia) {
        if owesEnding {
            text += defaultEnding.rawValue
            owesEnding = false
        }
        text += line
        let ending = trivia.lineEnding ?? defaultEnding
        if ending == .none {
            owesEnding = true
        } else {
            text += ending.rawValue
        }
    }
}
