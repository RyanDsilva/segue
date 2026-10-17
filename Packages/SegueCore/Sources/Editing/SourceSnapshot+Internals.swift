// Owner: unit C (Editing). Tree lookups shared by the snapshot, the editor and the rewrite.

import ChordPro
import Diagrams
import MusicTheory

/// A directive line of the snapshot.
struct DirectiveEntry: Sendable {
    /// Line index (0-based).
    var line: Int
    var path: BlockPath
    var directive: Directive
}

/// A `{define}` line of the snapshot.
struct DefineLine: Sendable {
    /// Line index (0-based).
    var line: Int
    var path: BlockPath
    /// First word of the value: the defined chord name.
    var name: String?
    var definition: ChordDefinition?
}

extension SourceSnapshot {
    static func path(of role: LineRole) -> BlockPath {
        switch role {
        case let .block(path): path
        case let .sectionEnd(block), let .sectionStart(block): BlockPath(block: block)
        }
    }

    /// The block at `path` (a section for a header path).
    func block(at path: BlockPath) -> Block? {
        guard document.blocks.indices.contains(path.block) else { return nil }
        let top = document.blocks[path.block]
        guard let item = path.item else { return top }
        guard case let .section(section) = top, section.items.indices.contains(item) else {
            return nil
        }
        return section.items[item]
    }

    /// The section containing `path`, if it is a section item.
    func enclosingSection(of path: BlockPath) -> Section? {
        guard path.item != nil, document.blocks.indices.contains(path.block),
              case let .section(section) = document.blocks[path.block]
        else { return nil }
        return section
    }

    /// Whether `path` is inside a tab/grid section (verbatim, read-only).
    func isVerbatim(_ path: BlockPath) -> Bool {
        enclosingSection(of: path).map { DirectiveLine.isVerbatimSection($0.kind) } ?? false
    }

    /// The lyric layout of the `.line` at `path`; `nil` for any other block and for lines
    /// inside tab/grid sections.
    func layout(of path: BlockPath) -> LyricLayout? {
        guard case .line = block(at: path), !isVerbatim(path),
              let index = map.lineOfPath[path]
        else { return nil }
        let line = map.lines[index]
        return LyricLayout(line: line.text, start: line.start)
    }

    /// Every directive line named `name` (canonical), in source order.
    func directiveLines(named name: String) -> [DirectiveEntry] {
        var result: [DirectiveEntry] = []
        for (index, role) in map.roles.enumerated() {
            guard case let .block(path) = role, case let .directive(directive) = block(at: path),
                  directive.name == name
            else { continue }
            result.append(DirectiveEntry(line: index, path: path, directive: directive))
        }
        return result
    }

    var defineLines: [DefineLine] {
        directiveLines(named: "define").map { entry in
            let value = entry.directive.value ?? ""
            let name = value.split(whereSeparator: { $0 == " " || $0 == "\t" }).first
                .map(String.init)
            return DefineLine(
                line: entry.line,
                path: entry.path,
                name: name,
                definition: ChordDefinition(directiveValue: value),
            )
        }
    }

    /// Highlights of one source line.
    func lineHighlights(_ index: Int) -> [SyntaxHighlight] {
        let line = map.lines[index]
        let trimmed = Self.trimmed(line)
        switch map.roles[index] {
        case .sectionEnd, .sectionStart:
            return trimmed.isEmpty ? [] : [SyntaxHighlight(range: trimmed, kind: .sectionMarker)]
        case let .block(path):
            switch block(at: path) {
            case .chorusRef:
                return [SyntaxHighlight(range: trimmed, kind: .sectionMarker)]
            case .commentDirective:
                return [SyntaxHighlight(range: trimmed, kind: .commentDirective)]
            case .directive:
                return [SyntaxHighlight(range: trimmed, kind: .directive)]
            case .fileComment:
                return [SyntaxHighlight(range: line.contentRange, kind: .fileComment)]
            case .line:
                return (layout(of: path)?.chords ?? []).map(Self.highlight)
            case .blank, nil, .section:
                return []
            }
        }
    }

    private static func highlight(_ chord: LyricLayout.Chord) -> SyntaxHighlight {
        let kind: SyntaxHighlight.Kind = switch ChordToken(parsing: chord.text) {
        case .chord: .chord
        case .noChord: .noChord
        case .unknown: .unknownChord
        }
        return SyntaxHighlight(range: chord.range, kind: kind)
    }

    /// The content range without leading and trailing spaces/tabs.
    static func trimmed(_ line: SourceLine) -> Range<Int> {
        let units = Array(line.text.utf16)
        var lower = 0
        var upper = units.count
        while lower < upper, units[lower] == 0x20 || units[lower] == 0x09 {
            lower += 1
        }
        while upper > lower, units[upper - 1] == 0x20 || units[upper - 1] == 0x09 {
            upper -= 1
        }
        return line.start + lower ..< line.start + upper
    }

    /// A parser diagnostic placed in the text, classified for the editor.
    func editorDiagnostic(for diagnostic: Diagnostic) -> EditorDiagnostic? {
        let index = diagnostic.line - 1
        guard map.lines.indices.contains(index) else { return nil }
        let line = map.lines[index]
        let columnOffset = String(line.text.prefix(max(diagnostic.column - 1, 0))).utf16.count
        let start = line.start + columnOffset
        let message = diagnostic.message
        let kind: EditorDiagnostic.Kind
        let range: Range<Int>
        if message.contains("never closed") || message.contains("is not closed") {
            kind = .unclosedSection
            range = Self.trimmed(line)
        } else if message.contains("irective") || message.contains("'{'")
            || message.contains("'}'") || message.hasPrefix("Capo ")
            || message.hasPrefix("Tempo ") || message.hasPrefix("Duration ")
        {
            kind = .malformedDirective
            range = start ..< max(start, line.contentEnd)
        } else {
            kind = .syntax
            range = start ..< min(start + 1, line.contentEnd)
        }
        return EditorDiagnostic(
            range: range,
            severity: kind == .unclosedSection ? .error : .warning,
            kind: kind,
            message: message,
            line: diagnostic.line,
        )
    }
}
