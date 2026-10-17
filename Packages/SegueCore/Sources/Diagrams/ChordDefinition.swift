// Owner: unit B (Diagrams). Frozen interface: docs/phases/1-interfaces.md.

/// A custom chord shape from a ChordPro `{define}` directive:
/// `{define: Gadd9 base-fret 1 frets 3 2 0 2 0 3 fingers 2 1 0 3 0 4}` (guitar) or
/// `{define: Cmaj7 keys 0 4 7 11}` (ChordPro 6 piano define).
public struct ChordDefinition: Sendable, Hashable {
    public enum Shape: Sendable, Hashable {
        case guitar(GuitarShape)
        /// Piano keys as ChordPro writes them: semitones relative to the chord root.
        case piano(keys: [Int])
    }

    /// The chord name being defined, verbatim (`Gadd9`). Matched against chord tokens'
    /// `original` text.
    public var name: String
    public var shape: Shape

    public init(name: String, shape: Shape) {
        self.name = name
        self.shape = shape
    }

    /// Parses the value of a `{define}` directive (everything after `define:`). `nil` when
    /// malformed; the editor reports it as a malformed directive.
    ///
    /// Keywords are case-insensitive. Muted strings are `x`, `X`, `N` or `-1`; unfingered
    /// strings in `fingers` are `0`, `-`, `x`, `X` or `N`. `base-fret` defaults to 1. A
    /// finger on several strings at one fret is read as a barre. Display-only keywords
    /// (`display`, `format`, `diagram`, `copy`, `copyall`) are not understood, so a define
    /// using them is `nil` rather than silently half-read.
    public init?(directiveValue: String) {
        let tokens = directiveValue.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let name = tokens.first, let fields = Fields(tokens: tokens.dropFirst()) else {
            return nil
        }
        switch (fields.frets, fields.keys) {
        case let (frets?, nil):
            if let fingers = fields.fingers, fingers.count != frets.count {
                return nil
            }
            let shape = Self.shape(frets: frets, fingers: fields.fingers, baseFret: fields.baseFret)
            self.init(name: name, shape: .guitar(shape))
        case let (nil, keys?):
            guard fields.fingers == nil else { return nil }
            self.init(name: name, shape: .piano(keys: keys))
        default:
            return nil
        }
    }

    /// The keyword fields of a define, each read once from the tokens after the name.
    private struct Fields {
        var baseFret = 1
        var frets: [Int?]?
        var fingers: [Int?]?
        var keys: [Int]?

        /// `nil` when a keyword is unknown or its values are malformed.
        init?(tokens: ArraySlice<String>) {
            var remaining = tokens
            while let keyword = remaining.popFirst()?.lowercased() {
                let arguments = Array(remaining
                    .prefix { !ChordDefinition.keywords.contains($0.lowercased()) })
                remaining = remaining.dropFirst(arguments.count)
                guard read(keyword: keyword, arguments: arguments) else { return nil }
            }
        }

        private mutating func read(keyword: String, arguments: [String]) -> Bool {
            switch keyword {
            case "base-fret":
                guard arguments.count == 1, let value = Int(arguments[0]), value >= 1 else {
                    return false
                }
                baseFret = value
            case "frets":
                frets = Self.all(arguments.map(ChordDefinition.fret(_:)))
                return frets != nil
            case "fingers":
                fingers = Self.all(arguments.map(ChordDefinition.finger(_:)))
                return fingers != nil
            case "keys":
                let parsed = arguments.compactMap { Int($0) }
                guard !parsed.isEmpty, parsed.count == arguments.count else { return false }
                keys = parsed
            default:
                return false
            }
            return true
        }

        /// The values when every one parsed (and there is at least one), else `nil`.
        private static func all(_ parsed: [Int??]) -> [Int?]? {
            guard !parsed.isEmpty, parsed.allSatisfy({ $0 != nil }) else { return nil }
            return parsed.compactMap(\.self)
        }
    }

    /// Canonical directive value (without `{define: ` and `}`), parseable by
    /// `init?(directiveValue:)`; fingers and barres are omitted when unspecified.
    public var directiveValue: String {
        switch shape {
        case let .guitar(shape):
            var parts = [name, "base-fret", String(shape.baseFret), "frets"]
            parts += shape.frets.map { $0.map(String.init) ?? "x" }
            if shape.fingers.contains(where: { $0 != nil }) {
                parts.append("fingers")
                parts += shape.frets.indices.map { string in
                    let finger = string < shape.fingers.count ? shape.fingers[string] : nil
                    return finger.map(String.init) ?? "0"
                }
            }
            return parts.joined(separator: " ")
        case let .piano(keys):
            return ([name, "keys"] + keys.map(String.init)).joined(separator: " ")
        }
    }

    private static let keywords: Set = [
        "base-fret", "frets", "fingers", "keys", "display", "format", "diagram", "copy",
        "copyall",
    ]

    /// A fret value: `.some(nil)` for muted, `.some(n)` for a fret, `nil` when malformed.
    private static func fret(_ text: String) -> Int?? {
        switch text {
        case "-1", "N", "x", "X": return .some(nil)
        default:
            guard let value = Int(text), value >= 0 else { return nil }
            return .some(value)
        }
    }

    /// A finger value: `.some(nil)` for none, `.some(n)` for finger 1 ... 4 (5 for the
    /// thumb in some charts), `nil` when malformed.
    private static func finger(_ text: String) -> Int?? {
        switch text {
        case "-", "0", "N", "x", "X": return .some(nil)
        default:
            guard let value = Int(text), (1 ... 5).contains(value) else { return nil }
            return .some(value)
        }
    }

    /// The guitar shape for parsed `frets` (relative to `baseFret`). Barres come from the
    /// fingers when given; without fingers a needed barre is inferred for display while
    /// `fingers` stays empty, so the define re-serialises as written.
    private static func shape(frets: [Int?], fingers: [Int?]?, baseFret: Int) -> GuitarShape {
        let barres: [Barre] = if let fingers, fingers.contains(where: { $0 != nil }) {
            GuitarShape.barres(frets: frets, fingers: fingers)
        } else {
            GuitarFingering.assign(absoluteFrets: frets)?.barre.map { [$0] } ?? []
        }
        return GuitarShape(frets: frets, fingers: fingers ?? [], baseFret: baseFret, barres: barres)
    }
}
