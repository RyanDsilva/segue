// Owner: unit A (MusicTheory). Frozen interface: docs/phases/1-interfaces.md.

import Tonic

/// Transposes chord tokens by a number of semitones, spelling results by the target key
/// (in-key notes) or by the author's accidental family (out-of-key notes).
///
/// Both the view transform (preview, live view) and "Apply transposition to source" use
/// this; neither re-implements spelling.
public struct Transposer: Sendable, Hashable {
    /// Net shift, any integer (normalised internally; 12 is a no-op).
    public let semitones: Int
    /// Key of the chords before transposition (declared or inferred); `nil` when unknown.
    public let sourceKey: SongKey?
    /// Key of the chords after transposition; spelling follows it. `nil` when `sourceKey` is.
    public let targetKey: SongKey?

    /// Target key derived as `sourceKey?.transposed(by: semitones)`.
    public init(semitones: Int, sourceKey: SongKey?) {
        self.semitones = semitones
        self.sourceKey = sourceKey
        targetKey = sourceKey?.transposed(by: semitones)
    }

    /// Explicit target key (e.g. to restore an original spelling); `semitones` is the
    /// distance between the two tonics.
    public init(from sourceKey: SongKey, to targetKey: SongKey) {
        self.sourceKey = sourceKey
        self.targetKey = targetKey
        semitones = sourceKey.tonic.pitchClass.semitones(to: targetKey.tonic.pitchClass)
    }

    /// Whether this transposer changes nothing (`semitones % 12 == 0`).
    public var isIdentity: Bool {
        PitchClass(semitones).rawValue == 0
    }

    /// The transposed token. `.noChord` and `.unknown` come back unchanged; an identity
    /// transposition returns the token unchanged (keeping `original`). A transposed chord's
    /// `original` is its canonical `symbol.text` (root and bass re-spelled, suffix kept).
    public func transpose(_ token: ChordToken) -> ChordToken {
        guard case let .chord(chord) = token, !isIdentity else { return token }
        return .chord(transpose(chord))
    }

    /// `transpose(.chord(chord))` for a parsed chord.
    public func transpose(_ chord: ChartChord) -> ChartChord {
        guard !isIdentity else { return chord }
        let symbol = chord.symbol
        let root = respell(symbol.root)
        let moved = ChordSymbol(
            root: root,
            suffix: symbol.suffix,
            formula: symbol.formula,
            bass: symbol.bass.map { respell(bass: $0, over: symbol.root, movedTo: root) },
        )
        return ChartChord(
            tonic: chord.tonic.map { Chord(root, type: $0.type) },
            symbol: moved,
            original: moved.text,
        )
    }

    // MARK: Spelling (phase 1 build rulings, review finding 2)

    /// A root (or a bass that is not spelled from its root):
    /// - a note of the source key's scale follows the target key signature (`KeySpelling`);
    /// - an out-of-key note written with an accidental keeps the author's accidental family
    ///   (`Ab` in C is `Bb` in D, never `A#`), as a natural when it lands on a white key;
    /// - an out-of-key natural takes its degree's usual family (`OutOfKey.family`), so a
    ///   borrowed chord comes back as written after any transposition and back.
    private func respell(_ note: NoteClass) -> NoteClass {
        let pitch = note.pitchClass.transposed(by: semitones)
        if sourceKey?.scaleContains(note.pitchClass) == true {
            return KeySpelling.spell(pitch, in: targetKey)
        }
        // Out of key (or no key at all: every accidental is the author's choice).
        guard let family = Self.family(of: note)
            ?? targetKey.map({ OutOfKey.family(of: pitch, in: $0) })
        else { return KeySpelling.spell(pitch, in: targetKey) }
        let (sharp, flat) = NoteClass.spellings(of: pitch)
        return family == .flat ? flat : sharp
    }

    /// A slash bass in the key follows the key signature. Out of the key it is spelled as
    /// its interval above the root (`E/G#` in C is `F/A` in Db and comes back as `E/G#`; a
    /// major third is two letters up), unless that needs a double accidental or
    /// `Cb Fb E# B#`; then it is spelled like a root.
    private func respell(bass: NoteClass, over root: NoteClass, movedTo newRoot: NoteClass)
        -> NoteClass
    {
        let pitch = bass.pitchClass.transposed(by: semitones)
        if sourceKey?.scaleContains(bass.pitchClass) == true {
            return KeySpelling.spell(pitch, in: targetKey)
        }
        let distance = Self.letterDistance[root.pitchClass.semitones(to: bass.pitchClass)]
        guard let letter = Letter(rawValue: (newRoot.letter.rawValue + distance) % 7) else {
            return respell(bass)
        }
        let natural = NoteClass(letter)
        let accidental: Accidental? = switch natural.pitchClass.semitones(to: pitch) {
        case 0: .natural
        case 1: .sharp
        case 11: .flat
        default: nil
        }
        guard let accidental,
              accidental == .natural || !natural.isWhiteKeyNeighbour(accidental)
        else { return respell(bass) }
        return NoteClass(letter, accidental: accidental)
    }

    /// Letters between a root and a note this many semitones above it, as intervals are
    /// usually spelled (`b2 2 b3 3 4 #4 5 b6 6 b7 7`).
    private static let letterDistance = [0, 1, 1, 2, 2, 3, 3, 4, 5, 5, 6, 6]

    private static func family(of note: NoteClass) -> KeyFlavour? {
        switch note.accidental {
        case .doubleFlat, .flat: .flat
        case .doubleSharp, .sharp: .sharp
        case .natural: nil
        }
    }
}

public extension KeySpelling {
    /// How a chart spells `pitchClass` in `key` when nothing else says: the key signature
    /// for notes of the key's scale, the degree's usual family otherwise (`Ab`, not `G#`,
    /// for the flat 6th of C). This is what transposition keeps stable.
    static func preferred(_ pitchClass: PitchClass, in key: SongKey) -> NoteClass {
        guard !key.scaleContains(pitchClass) else { return spell(pitchClass, in: key) }
        let (sharp, flat) = NoteClass.spellings(of: pitchClass)
        return OutOfKey.family(of: pitchClass, in: key) == .flat ? flat : sharp
    }
}

/// The usual accidental family of each out-of-key degree, for notes whose own spelling
/// carries none. Major: `b2 b3 #4 b6 b7` (the Nashville degree names); minor: `b2`, the
/// raised 3rd, `#4` and the raised 6th.
enum OutOfKey {
    static func family(of pitchClass: PitchClass, in key: SongKey) -> KeyFlavour {
        let degree = key.tonic.pitchClass.semitones(to: pitchClass)
        let sharps: Set = switch key.mode {
        case .major: [6]
        case .minor: [4, 6, 9]
        }
        return sharps.contains(degree) ? .sharp : .flat
    }
}
