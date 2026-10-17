// Owner: unit A (MusicTheory). Frozen interface: docs/phases/1-interfaces.md.

/// How chords are shown when the song has `{capo: N}` (chords as written are shapes).
public enum CapoMode: String, Sendable, Hashable, Codable, CaseIterable {
    /// Guitar view: chords as written; diagrams show the capo.
    case shapes
    /// Keys/voice view: chords transposed up by the capo (concert pitch).
    case concert
}

/// A capo position that turns a concert key into an open-friendly shape key.
public struct CapoSuggestion: Sendable, Hashable {
    /// Capo fret, 1 ... 11 (0 means "no capo", listed when the concert key is itself open).
    public var fret: Int
    /// The key the guitarist plays shapes in.
    public var shapeKey: SongKey

    public init(fret: Int, shapeKey: SongKey) {
        self.fret = fret
        self.shapeKey = shapeKey
    }
}

public enum Capo {
    /// Open-friendly shape keys: C, G, D, A, E, Am, Em.
    public static let openShapeKeys: [String] = ["C", "G", "D", "A", "E", "Am", "Em"]

    /// Semitones to add to chords as written for display: 0 in `.shapes`, `capo` in
    /// `.concert` (`capo` nil or <= 0 counts as 0).
    public static func displayOffset(capo: Int?, mode: CapoMode) -> Int {
        switch mode {
        case .shapes: 0
        case .concert: max(capo ?? 0, 0)
        }
    }

    /// Capo positions whose shape key (concert key - fret) is in `openShapeKeys`, ordered
    /// by lowest fret. Same mode as `concertKey`.
    public static func suggestions(concertKey: SongKey) -> [CapoSuggestion] {
        let open = Set(openShapeKeys.compactMap(SongKey.init(parsing:)).map(\.pitchIdentity))
        return (0 ... 11).compactMap { fret in
            let shapeKey = concertKey.transposed(by: -fret)
            guard open.contains(shapeKey.pitchIdentity) else { return nil }
            return CapoSuggestion(fret: fret, shapeKey: shapeKey)
        }
    }
}

extension SongKey {
    /// Tonic pitch class and mode, ignoring spelling (`Db` == `C#`).
    struct PitchIdentity: Hashable {
        var tonic: PitchClass
        var mode: KeyMode
    }

    var pitchIdentity: PitchIdentity {
        PitchIdentity(tonic: tonic.pitchClass, mode: mode)
    }
}
