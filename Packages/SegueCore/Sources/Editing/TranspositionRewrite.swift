// Owner: unit C (Editing). Frozen interface: docs/phases/1-interfaces.md.

import ChordPro
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
/// match. Unknown chords and `N.C.` are left as written. When the song has no `{key}` at all,
/// the detected key (inferred or ambiguous), transposed, is added as a `{key}` after the
/// leading metadata directives (phase 1 build rulings); spelling uses that key.
public struct TranspositionRewrite: Sendable, Hashable {
    /// One undo step ("Transpose").
    public var change: SourceChange
    /// The new `{key}` value: the first declared key moved, or the added detected key;
    /// `nil` when the song has neither (no parseable `{key}` and no chords to detect from).
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
        let keyContext = KeyContext(document: snapshot.document)
        let transposer = Transposer(semitones: semitones, sourceKey: keyContext.writtenKey)
        var builder = EditBuilder(text: snapshot.text)

        // Chords: (old text, new text) per occurrence, rewritten in place.
        var rewritten: [(old: String, new: String)] = []
        for occurrence in snapshot.chords {
            let new = transposer.transpose(occurrence.token).original
            rewritten.append((occurrence.token.original, new))
            if new != occurrence.token.original,
               let range = snapshot.sourceRange(of: occurrence.ref)
            {
                builder.replace(range.lowerBound + 1 ..< range.upperBound - 1, with: new)
            }
        }

        // {key}: every parseable one moves by the same interval (a mid-song key change
        // stays a key change); unparseable values are left alone.
        var newKey: SongKey?
        for entry in snapshot.directiveLines(named: "key") {
            guard let value = entry.directive.value, let key = SongKey(parsing: value) else {
                continue
            }
            let moved = transposer.isIdentity ? key : key.transposed(by: semitones)
            if newKey == nil, keyContext.declared != nil {
                newKey = moved
            }
            let line = snapshot.map.lines[entry.line]
            if moved != key, let directive = DirectiveLine(line.text) {
                builder.replace(line.contentRange, with: directive.replacingValue(with: moved.name))
            }
        }

        // 0-based line of an added `{key}` in the rewritten source.
        var addedLine: Int?
        if keyContext.declared == nil {
            newKey = nil
            // No `{key}` line at all (an unparseable one is left alone): write down the
            // detected key, moved with the chords, so the rewritten song states its key.
            if !transposer.isIdentity, snapshot.directiveLines(named: "key").isEmpty,
               let detected = keyContext.detection?.key
            {
                let added = detected.transposed(by: semitones)
                let after = snapshot.leadingMetadataEnd
                snapshot.insertLine(
                    DirectiveLine.canonical(name: "key", value: added.name),
                    afterLine: after,
                    into: &builder,
                )
                addedLine = (after ?? -1) + 1
                newKey = added
            }
        }

        let change = SourceChange(edits: builder.edits(), actionName: "Transpose")
        return Self(
            change: change,
            newKey: newKey,
            flaggedDefines: flags(snapshot.defineLines, rewritten: rewritten, addedLine: addedLine),
        )
    }

    /// Defines whose name no chord carries any more (`unused`), or whose name now sits on
    /// chords rewritten from a different chord (`mismatched`). `{define}` lines are never
    /// edited; only an added `{key}` line (`addedLine`, 0-based) moves the ones below it.
    private static func flags(
        _ defines: [DefineLine],
        rewritten: [(old: String, new: String)],
        addedLine: Int?,
    ) -> [DefineFlag] {
        defines.compactMap { define in
            guard let name = define.name else { return nil }
            let shift = addedLine.map { define.line >= $0 ? 1 : 0 } ?? 0
            let line = define.line + shift + 1
            let carriers = rewritten.filter { $0.new == name }
            if carriers.isEmpty {
                return DefineFlag(name: name, line: line, reason: .unused)
            }
            if carriers.contains(where: { $0.old != name }) {
                return DefineFlag(name: name, line: line, reason: .mismatched)
            }
            return nil
        }
    }
}
