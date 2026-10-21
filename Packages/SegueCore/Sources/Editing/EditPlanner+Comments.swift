// Owner: P3-13 (section notes). Plans the `{comment}` operations behind chart notes as
// whole-line inserts, deletes and value re-spellings: every other byte of the song stays
// exactly as written.

import ChordPro
import Foundation

extension DocumentEditor {
    /// Comment operations; `nil` for every other operation.
    static func planCommentOperation(
        _ operation: EditOperation,
        with planner: inout EditPlanner,
    ) throws(EditError) -> String? {
        switch operation {
        case let .insertComment(text, path):
            try planner.insertComment(text, at: path)
            return "Add Note"
        case let .setCommentText(path, text):
            try planner.setCommentText(path, text: text)
            return "Edit Note"
        case let .removeComment(path):
            try planner.removeComment(path)
            return "Delete Note"
        case let .editComments(edits):
            try planner.editComments(edits)
            return "Edit Notes"
        default:
            return nil
        }
    }
}

public enum CommentText {
    /// `text` as one comment value: line breaks and runs of whitespace become one space,
    /// and the ends are trimmed.
    public static func clean(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Whether `{comment: text}` reads back as exactly one comment with `text` (no `}` that
    /// would end the directive early, nothing empty).
    public static func isValid(_ text: String) -> Bool {
        guard !text.isEmpty, text == clean(text) else { return false }
        let blocks = ChordProParser.parse(DirectiveLine.canonical(name: "comment", value: text))
            .0.blocks
        guard blocks.count == 1, case let .commentDirective(comment) = blocks[0] else {
            return false
        }
        return comment.text == text
    }
}

extension EditPlanner {
    mutating func insertComment(_ text: String, at path: BlockPath) throws(EditError) {
        guard CommentText.isValid(text) else { throw .notCommentText(text) }
        guard snapshot.block(at: path) != nil,
              let index = snapshot.map.lineOfPath[path]
        else { throw .invalidPath(path) }
        let line = DirectiveLine.canonical(name: "comment", value: text)
        if path.item == nil, case .section = snapshot.block(at: path) {
            snapshot.insertLine(line, afterLine: index, into: &builder)
        } else {
            snapshot.insertLine(line, afterLine: index == 0 ? nil : index - 1, into: &builder)
        }
    }

    mutating func editComments(_ edits: [CommentEdit]) throws(EditError) {
        var touched: Set<BlockPath> = []
        for edit in edits {
            switch edit {
            case let .append(text, section):
                try appendComment(text, to: section)
            case let .setText(path, text):
                guard touched.insert(path).inserted else { throw .invalidPath(path) }
                try setCommentText(path, text: text)
            case let .remove(path):
                guard touched.insert(path).inserted else { throw .invalidPath(path) }
                try removeComment(path)
            }
        }
    }

    /// See `CommentEdit.append`.
    private mutating func appendComment(_ text: String, to section: BlockPath) throws(EditError) {
        guard CommentText.isValid(text) else { throw .notCommentText(text) }
        guard section.item == nil, case let .section(body) = snapshot.block(at: section) else {
            throw .wrongBlockKind(section)
        }
        let after = Self.lastLeadingNote(in: body).map { BlockPath(block: section.block, item: $0) }
            ?? section
        guard let index = snapshot.map.lineOfPath[after] else { throw .invalidPath(after) }
        let line = snapshot.map.lines[index]
        if caret == nil {
            let ending = snapshot.map.defaultEnding.utf16.count
            caret = line.hasEnding ? (line.end, 0) : (line.contentEnd, ending)
        }
        snapshot.insertLine(
            DirectiveLine.canonical(name: "comment", value: text),
            afterLine: index,
            into: &builder,
        )
    }

    /// The item index of the last comment in the run of comments (and blank lines) that
    /// opens `section`, or nil when its first non-blank item is not a comment.
    static func lastLeadingNote(in section: Section) -> Int? {
        var last: Int?
        for (index, item) in section.items.enumerated() {
            switch item {
            case .commentDirective: last = index
            case .blank: continue
            default: return last
            }
        }
        return last
    }

    mutating func setCommentText(_ path: BlockPath, text: String) throws(EditError) {
        guard CommentText.isValid(text) else { throw .notCommentText(text) }
        let line = try commentLine(path)
        guard let directive = DirectiveLine(line.text) else { throw .wrongBlockKind(path) }
        builder.replace(line.contentRange, with: directive.replacingValue(with: text))
    }

    mutating func removeComment(_ path: BlockPath) throws(EditError) {
        _ = try commentLine(path)
        guard let index = snapshot.map.lineOfPath[path] else { throw .invalidPath(path) }
        deleteLine(index)
    }

    private func commentLine(_ path: BlockPath) throws(EditError) -> SourceLine {
        guard let block = snapshot.block(at: path) else { throw .invalidPath(path) }
        guard case .commentDirective = block else { throw .wrongBlockKind(path) }
        return try sourceLine(path)
    }
}
