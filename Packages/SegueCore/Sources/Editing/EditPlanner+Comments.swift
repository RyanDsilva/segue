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
