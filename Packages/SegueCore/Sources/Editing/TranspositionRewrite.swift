// Owner: unit C (Editing). Frozen interface: docs/phases/1-interfaces.md.

import MusicTheory

/// A custom `{define}` that needs review after "Apply transposition to source".
public struct DefineFlag: Sendable, Hashable {
    public enum Reason: Sendable, Hashable {
        /// No chord in the rewritten song has the define's name any more.
        case unused
        /// The name still appears, but on chords that were rewritten from a different chord
        /// (the shape was drawn for the old one).
        case mismatched
    }

    /// The defined chord name.
    public var name: String
    /// 1-based line of the `{define}` in the rewritten source.
    public var line: Int
    public var reason: Reason

    public init(name: String, line: Int, reason: Reason) {
        self.name = name
        self.line = line
        self.reason = reason
    }
}

/// "Apply transposition to source" (phase 1 spec): rewrites every chord token and `{key}`,
/// keeps `{capo}`, never edits or deletes `{define}`s but flags the ones that no longer
/// match. Unknown chords and `N.C.` are left as written. When the song has no `{key}`, none
/// is added (an inferred key is not a confirmed one); spelling then uses the inferred key.
public struct TranspositionRewrite: Sendable, Hashable {
    /// One undo step ("Transpose").
    public var change: SourceChange
    /// The new `{key}` value, `nil` when the song has no `{key}`.
    public var newKey: SongKey?
    public var flaggedDefines: [DefineFlag]

    public init(change: SourceChange, newKey: SongKey?, flaggedDefines: [DefineFlag]) {
        self.change = change
        self.newKey = newKey
        self.flaggedDefines = flaggedDefines
    }

    /// Plans the rewrite of `snapshot` by `semitones` (the editor passes its current view
    /// transpose, then resets the view transpose to 0 after applying).
    public static func plan(semitones: Int, in snapshot: SourceSnapshot) -> Self {
        fatalError("unimplemented: unit C")
    }
}
