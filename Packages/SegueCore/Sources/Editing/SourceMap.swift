// Owner: unit C (Editing). Line table and tree <-> text mapping behind `SourceSnapshot`.

import ChordPro

/// One physical source line, in UTF-16 offsets.
struct SourceLine: Sendable, Hashable {
    /// First UTF-16 offset of the line.
    var start: Int
    /// End of the content (before `\n`, `\r\n` or a lone `\r`).
    var contentEnd: Int
    /// End including the line ending (start of the next line).
    var end: Int
    /// The content, without the line ending.
    var text: String

    /// The line ending as written (`""` for a last line without one).
    var ending: String

    var contentRange: Range<Int> {
        start ..< contentEnd
    }

    var hasEnding: Bool {
        !ending.isEmpty
    }
}

/// What a source line is in the tree.
enum LineRole: Sendable, Hashable {
    /// A non-section block, or an item inside a section.
    case block(BlockPath)
    /// The `{start_of_...}` line of the section at this top-level index.
    case sectionStart(Int)
    /// The `{end_of_...}` line of the section at this top-level index.
    case sectionEnd(Int)
}

/// The line table of a snapshot and which tree node each line is.
struct SourceMap: Sendable {
    let lines: [SourceLine]
    let roles: [LineRole]
    /// Line index of each block path (section paths map to their start line).
    let lineOfPath: [BlockPath: Int]
    /// The document's default line ending (first recorded one, else `\n`).
    let defaultEnding: String
    /// Total UTF-16 length.
    let length: Int

    /// Builds the line table from the parser's own trivia (every node records its exact
    /// source line and line ending), so line splitting can never disagree with the parser.
    init(text: String, document: SongDocument) {
        var lines: [SourceLine] = []
        var roles: [LineRole] = []
        var lineOfPath: [BlockPath: Int] = [:]
        var offset = 0
        func add(_ trivia: Trivia, _ role: LineRole) {
            let content = trivia.source ?? ""
            let ending = trivia.lineEnding?.rawValue ?? ""
            let contentEnd = offset + content.utf16.count
            let end = contentEnd + ending.utf16.count
            lines.append(SourceLine(
                start: offset,
                contentEnd: contentEnd,
                end: end,
                text: content,
                ending: ending,
            ))
            roles.append(role)
            offset = end
        }
        for (index, block) in document.blocks.enumerated() {
            let path = BlockPath(block: index)
            if case let .section(section) = block {
                lineOfPath[path] = lines.count
                add(section.startTrivia, .sectionStart(index))
                for (item, inner) in section.items.enumerated() {
                    let itemPath = BlockPath(block: index, item: item)
                    lineOfPath[itemPath] = lines.count
                    add(Self.trivia(of: inner), .block(itemPath))
                }
                if section.endTrivia.source != nil {
                    add(section.endTrivia, .sectionEnd(index))
                }
            } else {
                lineOfPath[path] = lines.count
                add(Self.trivia(of: block), .block(path))
            }
        }
        self.lines = lines
        self.roles = roles
        self.lineOfPath = lineOfPath
        length = text.utf16.count
        defaultEnding = lines.first { $0.hasEnding }.map(\.ending) ?? "\n"
    }

    private static func trivia(of block: Block) -> Trivia {
        switch block {
        case let .blank(blank): blank.trivia
        case let .chorusRef(ref): ref.trivia
        case let .commentDirective(comment): comment.trivia
        case let .directive(directive): directive.trivia
        case let .fileComment(comment): comment.trivia
        case let .line(line): line.trivia
        case let .section(section): section.startTrivia
        }
    }

    /// Index of the line containing `offset`: `start <= offset <= end` with the line ending
    /// counted in; `offset == length` belongs to the last line only if it has no ending.
    func lineIndex(containing offset: Int) -> Int? {
        guard offset >= 0, offset <= length, !lines.isEmpty else { return nil }
        var low = 0
        var high = lines.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lines[mid].start <= offset {
                low = mid
            } else {
                high = mid - 1
            }
        }
        let line = lines[low]
        if offset == line.end, line.hasEnding {
            return nil // just past a final newline: an empty, unmapped last line
        }
        return low
    }

    /// The first line whose range ends after `offset` (for range queries).
    func firstLine(endingAfter offset: Int) -> Int {
        var low = 0
        var high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].end <= offset {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}
