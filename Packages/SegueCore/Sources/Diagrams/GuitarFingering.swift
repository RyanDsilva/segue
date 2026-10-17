// Owner: unit B (Diagrams).

/// Finger assignment for a guitar fingering, shared by the generator, `{define}` parsing
/// (when fingers are given) and the shape editor (when they are not).
public enum GuitarFingering {
    /// Fingers and the barre for one fingering, in absolute frets.
    public struct Assignment: Sendable, Hashable {
        /// Per string: finger 1 ... 4, `nil` for muted and open strings.
        public var fingers: [Int?]
        /// A first-finger barre across `strings` at absolute fret `fret`, if one is needed.
        public var barre: Barre?
        /// Fingers in use; a barre counts once.
        public var fingerCount: Int
    }

    /// Assigns fingers 1 ... 4 to the fretted strings of `absoluteFrets` (`nil` muted, `0`
    /// open), lowest fret first and lower string first on a tie. Five or more fretted notes
    /// need a first-finger barre at the lowest fret covering every string between its outer
    /// notes. `nil` when the fingering needs more than four fingers or an impossible barre (an
    /// open or muted string under it).
    public static func assign(absoluteFrets: [Int?]) -> Assignment? {
        let fretted = absoluteFrets.enumerated()
            .compactMap { string, fret in fret.flatMap { $0 > 0 ? (string, $0) : nil } }
            .sorted { ($0.1, $0.0) < ($1.1, $1.0) }
        var fingers = [Int?](repeating: nil, count: absoluteFrets.count)
        if fretted.count <= 4 {
            for (finger, note) in fretted.enumerated() {
                fingers[note.0] = finger + 1
            }
            return Assignment(fingers: fingers, barre: nil, fingerCount: fretted.count)
        }
        guard let lowest = fretted.first?.1 else { return nil }
        let atLowest = fretted.filter { $0.1 == lowest }.map(\.0)
        guard let first = atLowest.min(), let last = atLowest.max(), first < last else {
            return nil
        }
        // Every string under the barre must be fretted at or above it.
        for string in first ... last {
            guard let fret = absoluteFrets[string], fret >= lowest else { return nil }
        }
        let rest = fretted.filter { $0.1 > lowest }
        guard rest.count <= 3 else { return nil }
        for string in atLowest {
            fingers[string] = 1
        }
        for (index, note) in rest.enumerated() {
            fingers[note.0] = index + 2
        }
        return Assignment(
            fingers: fingers,
            barre: Barre(fret: lowest, strings: first ... last, finger: 1),
            fingerCount: 1 + rest.count,
        )
    }
}

public extension GuitarShape {
    /// Frets per diagram before a shape moves off the nut: shapes whose highest fret is at
    /// most this draw from the nut (`baseFret` 1).
    static let nutFretLimit = 4

    /// A shape from absolute frets (`nil` muted, `0` open). `baseFret` is 1 when every fret
    /// fits under the nut window, otherwise the lowest fretted fret. Barres come from
    /// `fingers` (one finger on several strings at one fret) when given, otherwise from
    /// `GuitarFingering.assign`, which also supplies the fingers.
    init(absoluteFrets: [Int?], fingers: [Int?]? = nil) {
        let frettedFrets = absoluteFrets.compactMap(\.self).filter { $0 > 0 }
        let highest = frettedFrets.max() ?? 0
        let base = highest <= Self.nutFretLimit ? 1 : (frettedFrets.min() ?? 1)
        func relative(_ fret: Int) -> Int {
            fret - base + 1
        }
        let relativeFrets = absoluteFrets.map { fret in
            fret.map { $0 == 0 ? 0 : relative($0) }
        }
        let resolvedFingers: [Int?]
        let absoluteBarres: [Barre]
        if let fingers, fingers.contains(where: { $0 != nil }) {
            resolvedFingers = fingers
            absoluteBarres = Self.barres(frets: absoluteFrets, fingers: fingers)
        } else if let assignment = GuitarFingering.assign(absoluteFrets: absoluteFrets) {
            resolvedFingers = assignment.fingers
            absoluteBarres = assignment.barre.map { [$0] } ?? []
        } else {
            resolvedFingers = []
            absoluteBarres = []
        }
        self.init(
            frets: relativeFrets,
            fingers: resolvedFingers,
            baseFret: base,
            barres: absoluteBarres.map { barre in
                Barre(fret: relative(barre.fret), strings: barre.strings, finger: barre.finger)
            },
        )
    }

    /// Barres implied by explicit fingers: a finger pressing two or more strings at the same
    /// fret bars every string between them. Works on absolute or relative frets alike.
    internal static func barres(frets absoluteFrets: [Int?], fingers: [Int?]) -> [Barre] {
        var stringsByFinger: [Int: [Int]] = [:]
        for (string, finger) in fingers.enumerated() {
            guard let finger, string < absoluteFrets.count,
                  let fret = absoluteFrets[string], fret > 0
            else { continue }
            stringsByFinger[finger, default: []].append(string)
        }
        return stringsByFinger.keys.sorted().compactMap { finger in
            guard let strings = stringsByFinger[finger], strings.count >= 2,
                  let first = strings.first, let last = strings.last,
                  Set(strings.map { absoluteFrets[$0] }).count == 1,
                  let fret = absoluteFrets[first]
            else { return nil }
            return Barre(fret: fret, strings: first ... last, finger: finger)
        }
    }
}
