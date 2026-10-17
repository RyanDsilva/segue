// Owner: unit C (Editing). Frozen interface: docs/phases/1-interfaces.md.
//
// Addresses into a `SongDocument` tree. They are only valid for the snapshot they were
// taken from: after any edit, re-read them from the new snapshot's render model.

/// A block in the tree: a top-level block, or an item inside a top-level `.section`.
/// `item == nil` addresses the top-level block itself (for a section: its header).
public struct BlockPath: Sendable, Hashable, Comparable, CustomStringConvertible {
    /// Index into `SongDocument.blocks`.
    public var block: Int
    /// Index into that section's `items`, or `nil`.
    public var item: Int?

    public init(block: Int, item: Int? = nil) {
        self.block = block
        self.item = item
    }

    /// Source order.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.block != rhs.block {
            return lhs.block < rhs.block
        }
        return (lhs.item ?? -1) < (rhs.item ?? -1)
    }

    public var description: String {
        item.map { "\(block).\($0)" } ?? "\(block)"
    }
}

/// A position in a lyric line's lyric text (the line with its chords removed).
public struct LyricPosition: Sendable, Hashable {
    /// The `.line` block.
    public var line: BlockPath
    /// Offset in `Character`s (grapheme clusters) into the lyric text, 0 ... count. A chord
    /// "at" offset n sits above the n-th character.
    public var offset: Int

    public init(line: BlockPath, offset: Int) {
        self.line = line
        self.offset = offset
    }
}

/// One chord occurrence in a lyric line.
public struct ChordRef: Sendable, Hashable {
    /// The `.line` block.
    public var line: BlockPath
    /// Index among the line's chords in source order (0 = first `[..]` on the line).
    public var index: Int

    public init(line: BlockPath, index: Int) {
        self.line = line
        self.index = index
    }
}
