// Owner: unit C (Editing). Frozen interface: docs/phases/1-interfaces.md.

import Foundation

/// One replacement in ChordPro source text.
///
/// Ranges are UTF-16 offsets (the `NSString` / `NSRange` / TextKit unit) into the text the
/// edit was planned against, so the editor can apply them to `NSTextStorage` directly.
public struct TextEdit: Sendable, Hashable {
    public var range: Range<Int>
    public var replacement: String

    public init(range: Range<Int>, replacement: String) {
        self.range = range
        self.replacement = replacement
    }

    public var nsRange: NSRange {
        NSRange(location: range.lowerBound, length: range.count)
    }
}

/// The minimal text edits for one user action. Applied as one undo group, so text-mode
/// typing and visual-mode tree operations share a single undo stack.
public struct SourceChange: Sendable, Hashable {
    /// Non-overlapping, ascending by `range.lowerBound`, all relative to the pre-edit text.
    /// Each touches only the text the action changed (never whole-document replacement).
    public var edits: [TextEdit]
    /// Undo menu name ("Add Chord", "Move Chord", "Transpose").
    public var actionName: String
    /// Suggested selection after applying, UTF-16 range in the post-edit text.
    public var selectionAfter: Range<Int>?

    public init(edits: [TextEdit], actionName: String, selectionAfter: Range<Int>? = nil) {
        self.edits = edits
        self.actionName = actionName
        self.selectionAfter = selectionAfter
    }

    /// True when applying changes nothing.
    public var isEmpty: Bool {
        edits.isEmpty
    }
}

public extension String {
    /// `self` with `edits` applied (ranges relative to `self`, non-overlapping). Reference
    /// implementation of what the text view does; tests use it to check edit minimality.
    func applying(_ edits: [TextEdit]) -> String {
        let text = NSMutableString(string: self)
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            text.replaceCharacters(in: edit.nsRange, with: edit.replacement)
        }
        return text as String
    }
}
