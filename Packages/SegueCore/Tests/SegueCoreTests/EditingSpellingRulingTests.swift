import Editing
import Foundation
import MusicTheory
import Testing

/// Out-of-key chord spelling (docs/decisions.md, "Out-of-key chord spelling", review finding
/// 2), through "Apply transposition to source" on whole songs: in-key chords follow the key
/// signature, borrowed chords keep the author's accidental family, and transposing by any
/// interval and back restores the file byte for byte, in every key and with no key at all.
struct EditingSpellingRulingTests {
    /// The 12 major keys as charts spell them.
    static let keys = (0 ..< 12).map { SongKey(canonical: PitchClass($0), mode: .major) }

    /// Semitones above the tonic and the family an author writes them in: bII, bIII, #IV,
    /// bVI, bVII (`Db Eb F# Ab Bb` in C).
    static let borrowed: [(offset: Int, flat: Bool)] = [
        (1, true), (3, true), (6, false), (8, true), (10, true),
    ]

    static func note(_ offset: Int, in key: SongKey, flat: Bool) -> String {
        let pitch = key.tonic.pitchClass.transposed(by: offset)
        if key.scaleContains(pitch) {
            return KeySpelling.spell(pitch, in: key).chartName
        }
        return names(flat: flat)[pitch.rawValue]
    }

    static func names(flat: Bool) -> [String] {
        flat
            ? ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
            : ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    }

    /// A song in `key` (declared or not) with the I IV V vi progression, a slash chord and
    /// every borrowed chord, some with slash basses.
    static func song(in key: SongKey, declared: Bool) -> String {
        let one = note(0, in: key, flat: false)
        let four = note(5, in: key, flat: false)
        let five = note(7, in: key, flat: false)
        let six = note(9, in: key, flat: false)
        let three = note(4, in: key, flat: false)
        let borrowed = borrowed.map { note($0.offset, in: key, flat: $0.flat) }
        let header = declared ? "{title: Borrowed}\n{key: \(key.name)}\n" : "{title: Borrowed}\n"
        let fiveOverSeven = "\(five)/\(note(11, in: key, flat: false))"
        let threeOverSharpFive = "\(three)/\(note(8, in: key, flat: false))"
        let sevenOverTwo = "\(borrowed[4])/\(note(2, in: key, flat: false))"
        return header + """

        [\(one)]Dil ki [\(four)]baat, [\(fiveOverSeven)]sach [\(six)m]hai
        [\(one)]Raah [\(borrowed[0])]pe [\(borrowed[1])]chalte [\(borrowed[2])m7b5]hain
        [\(borrowed[3])]Shaam [\(borrowed[4])]dhali [\(threeOverSharpFive)]aur [\(five)7]raat
        [\(borrowed[3])maj7/\(one)]Dil [\(sevenOverTwo)]se [\(one)]dil

        """
    }

    @Test(arguments: keys)
    func `borrowed chords keep their family and every interval round-trips`(key: SongKey) {
        let original = Self.song(in: key, declared: true)
        let snapshot = SourceSnapshot(text: original)
        for semitones in (-11 ... 11).filter({ $0 != 0 }) {
            let there = TranspositionRewrite.plan(semitones: semitones, in: snapshot)
            let moved = original.applying(there.change.edits)
            let back = TranspositionRewrite.plan(
                semitones: -semitones,
                in: SourceSnapshot(text: moved),
            )
            #expect(
                moved.applying(back.change.edits) == original,
                "\(key.name) by \(semitones):\n\(moved)",
            )
            // Borrowed chords stay in the author's family (or become naturals).
            let roots = SourceSnapshot(text: moved).chords
                .compactMap { $0.token.chord?.symbol.root.chartName }
            for chord in Self.borrowed {
                let pitch = key.tonic.pitchClass.transposed(by: chord.offset + semitones)
                let expected = Self.names(flat: chord.flat)[pitch.rawValue]
                #expect(roots.contains(expected), "\(expected) by \(semitones): \(roots)")
            }
        }
    }

    @Test(arguments: keys)
    func `songs without a key round-trip apart from the added key`(key: SongKey) {
        let original = Self.song(in: key, declared: false)
        let snapshot = SourceSnapshot(text: original)
        let inferred = KeyContext(document: snapshot.document).writtenKey
        for semitones in (-11 ... 11).filter({ $0 != 0 }) {
            let there = TranspositionRewrite.plan(semitones: semitones, in: snapshot)
            let moved = original.applying(there.change.edits)
            #expect(there.newKey == inferred?.transposed(by: semitones))
            let back = TranspositionRewrite.plan(
                semitones: -semitones,
                in: SourceSnapshot(text: moved),
            )
            let restored = moved.applying(back.change.edits)
            let keyLine = "{key: \(inferred?.name ?? "")}\n"
            #expect(
                restored == original.replacingOccurrences(
                    of: "{title: Borrowed}\n",
                    with: "{title: Borrowed}\n" + keyLine,
                ),
                "\(key.name) by \(semitones):\n\(restored)",
            )
        }
    }

    @Test
    func `the reviewer's example: Ab in C comes back as Ab`() throws {
        let cMajor = try #require(SongKey(parsing: "C"))
        for semitones in -11 ... 11 {
            let there = Transposer(semitones: semitones, sourceKey: cMajor)
            let target = try #require(there.targetKey)
            let back = Transposer(semitones: -semitones, sourceKey: target)
            for chord in ["Ab", "Eb", "Bb", "Db", "F#m7b5", "E/G#", "Ab/C", "D/F#"] {
                let token = ChordToken(parsing: chord)
                #expect(back.transpose(there.transpose(token)).original == chord, "\(semitones)")
            }
        }
        #expect(Transposer(semitones: 2, sourceKey: cMajor)
            .transpose(ChordToken(parsing: "Ab")).original == "Bb")
        #expect(Transposer(semitones: 4, sourceKey: cMajor)
            .transpose(ChordToken(parsing: "Ab")).original == "C")
        // The flat 5th and sharp 4th are one degree: written `Gb`, it comes back as written
        // while it stays on black keys, and as `F#` (the degree's usual spelling) once it
        // has been a white key.
        let up = Transposer(semitones: 1, sourceKey: cMajor)
        let gFlat = up.transpose(ChordToken(parsing: "Gb"))
        #expect(gFlat.original == "G")
        #expect(Transposer(semitones: -1, sourceKey: up.targetKey).transpose(gFlat).original
            == "F#")
        let two = Transposer(semitones: 2, sourceKey: cMajor)
        #expect(Transposer(semitones: -2, sourceKey: two.targetKey)
            .transpose(two.transpose(ChordToken(parsing: "Gb"))).original == "Gb")
    }
}
