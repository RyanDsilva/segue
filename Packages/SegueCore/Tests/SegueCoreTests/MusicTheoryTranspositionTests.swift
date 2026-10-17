import MusicTheory
import Testing
import Tonic

/// Transposition property test (docs/phases/1-editor-and-music-theory.md, "Pure-logic
/// tests"): for every parseable chord and every interval, transposing there and back restores
/// the original spelling, the transposed spelling follows the target key's signature, and
/// Nashville numbers are transposition-invariant (minor keys included). Plus the pinned
/// spelling, key, Nashville and capo examples the spec names.
struct MusicTheoryTranspositionTests {
    /// The 24 keys as `SongKey.transposed(by:)` spells them.
    static let keys: [SongKey] = (0 ..< 12).flatMap { pitchClass in
        KeyMode.allCases.map { SongKey(canonical: PitchClass(pitchClass), mode: $0) }
    }

    /// Every chord quality the corpus and the spec use.
    static let suffixes = [
        "", "m", "-7", "m7", "7", "maj7", "maj9", "9", "13", "6", "m6", "6/9", "add9", "2",
        "sus2", "sus4", "7sus4", "13sus4", "7(#9)", "m7b5", "dim7", "aug", "mmaj7",
        "5", "7(b9,#11)",
    ].filter { ChordFormula.parse(suffix: $0) != nil }

    /// Chords spelled the way `key` spells them: every root, every suffix, with and without
    /// a slash bass a major third up.
    static func vocabulary(in key: SongKey) -> [ChordToken] {
        (0 ..< 12).flatMap { pitchClass -> [ChordToken] in
            let root = KeySpelling.spell(PitchClass(pitchClass), in: key).chartName
            let bass = KeySpelling.spell(PitchClass(pitchClass + 4), in: key).chartName
            return suffixes.flatMap { suffix in
                [
                    ChordToken(parsing: root + suffix),
                    ChordToken(parsing: "\(root)\(suffix)/\(bass)"),
                ]
            }
        }
    }

    @Test(arguments: keys)
    func `round trip restores spelling and nashville is invariant`(_ key: SongKey) {
        let chords = Self.vocabulary(in: key)
        for semitones in -12 ... 12 {
            let there = Transposer(semitones: semitones, sourceKey: key)
            let target = there.targetKey ?? key
            let back = Transposer(semitones: -semitones, sourceKey: target)
            #expect(back.targetKey == key)
            for token in chords {
                let moved = there.transpose(token)
                let restored = back.transpose(moved)
                #expect(
                    restored.original == token.original,
                    "\(token.original) in \(key.name) by \(semitones): \(moved.original)",
                )
                #expect(
                    Nashville.number(for: moved, in: target) == Nashville.number(
                        for: token,
                        in: key,
                    ),
                )
                if let chord = moved.chord {
                    Self.expectSignatureSpelling(chord, in: target)
                }
            }
        }
    }

    /// The corpus chords themselves, in their declared keys, survive every round trip
    /// byte-for-byte.
    @Test(arguments: CorpusFixture.all.filter { $0.declaredKey != nil })
    func `corpus chords round trip`(_ fixture: CorpusFixture) throws {
        let key = try #require(fixture.declaredKey.flatMap(SongKey.init(parsing:)))
        for semitones in -12 ... 12 {
            let there = Transposer(semitones: semitones, sourceKey: key)
            let back = Transposer(semitones: -semitones, sourceKey: there.targetKey)
            for text in fixture.tokens {
                let token = ChordToken(parsing: text)
                #expect(back.transpose(there.transpose(token)).original == text)
            }
        }
    }

    /// Independent restatement of the key-signature rules (not via `KeySpelling`).
    static func expectSignatureSpelling(_ chord: ChartChord, in key: SongKey) {
        let flatKeys: Set = [
            "F",
            "Bb",
            "Eb",
            "Ab",
            "Db",
            "Gb",
            "Dm",
            "Gm",
            "Cm",
            "Fm",
            "Bbm",
            "Ebm",
        ]
        let allowedFlats: [String: Set<String>] = [
            "C": ["Eb", "Bb"],
            "Am": ["Eb", "Bb"],
            "G": ["Bb"],
            "Em": ["Bb"],
        ]
        let leadingTone = KeySpelling.spell(key.tonic.pitchClass.transposed(by: 11), in: key)
        let notes = [chord.symbol.root] + (chord.symbol.bass.map { [$0] } ?? [])
        for note in notes {
            let name = note.chartName
            #expect(!["Cb", "Fb", "E#", "B#"].contains(name), "\(name) in \(key.name)")
            #expect(note.accidental != .doubleFlat && note.accidental != .doubleSharp)
            if flatKeys.contains(key.name) {
                let isLeadingTone = key.mode == .minor && note == leadingTone
                #expect(note.accidental != .sharp || isLeadingTone, "\(name) in \(key.name)")
            } else if note.accidental == .flat {
                #expect(allowedFlats[key.name]?.contains(name) == true, "\(name) in \(key.name)")
            }
        }
    }

    @Test
    func `spelling follows key signature rules`() throws {
        func spelled(_ pitchClasses: [Int], in key: String?) throws -> [String] {
            let songKey = try key.map { try #require(SongKey(parsing: $0)) }
            return pitchClasses.map { KeySpelling.spell(PitchClass($0), in: songKey).chartName }
        }
        let black = [1, 3, 6, 8, 10]
        #expect(try spelled(black, in: "C") == ["C#", "Eb", "F#", "G#", "Bb"])
        #expect(try spelled(black, in: nil) == ["C#", "Eb", "F#", "G#", "Bb"])
        #expect(try spelled(black, in: "Am") == ["C#", "Eb", "F#", "G#", "Bb"])
        #expect(try spelled(black, in: "G") == ["C#", "D#", "F#", "G#", "Bb"])
        #expect(try spelled(black, in: "E") == ["C#", "D#", "F#", "G#", "A#"])
        #expect(try spelled(black, in: "F") == ["Db", "Eb", "Gb", "Ab", "Bb"])
        #expect(try spelled(black, in: "Eb") == ["Db", "Eb", "Gb", "Ab", "Bb"])
        // Minor-key leading tones stay sharp in flat keys.
        #expect(try spelled(black, in: "Dm") == ["C#", "Eb", "Gb", "Ab", "Bb"])
        #expect(try spelled(black, in: "Gm") == ["Db", "Eb", "F#", "Ab", "Bb"])
        // White keys are always naturals.
        #expect(try spelled([5, 11], in: "F#") == ["F", "B"])
        #expect(try spelled([11, 4], in: "Gb") == ["B", "E"])
    }

    @Test
    func `keys transpose to conventional spellings`() throws {
        let cMajor = try #require(SongKey(parsing: "C"))
        let aMinor = try #require(SongKey(parsing: "Am"))
        #expect((0 ..< 12).map { cMajor.transposed(by: $0).name } == [
            "C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B",
        ])
        #expect((0 ..< 12).map { aMinor.transposed(by: $0).name } == [
            "Am", "Bbm", "Bm", "Cm", "C#m", "Dm", "D#m", "Em", "Fm", "F#m", "Gm", "G#m",
        ])
        // Identity keeps the author's spelling.
        let gFlat = try #require(SongKey(parsing: "Gb"))
        #expect(gFlat.transposed(by: 12) == gFlat)
        #expect(gFlat.transposed(by: 1).name == "G")
    }

    @Test
    func `keys parse and describe themselves`() throws {
        let parsed: [(String, String?)] = [
            ("G", "G"), ("F#m", "F#m"), ("Bbm", "Bbm"), ("Ebmin", "Ebm"), ("C minor", "Cm"),
            ("Am", "Am"), (" A major ", "A"), ("Db", "Db"), ("CM", "C"), ("H", nil), ("", nil),
            ("am", nil), ("G dorian", nil),
        ]
        for (text, name) in parsed {
            #expect(SongKey(parsing: text)?.name == name, "\(text)")
        }
        let relatives = ["Am": "C", "F#m": "A", "D#m": "F#", "Ebm": "Gb", "Abm": "B", "G": "G"]
        for (minor, major) in relatives {
            #expect(SongKey(parsing: minor)?.relativeMajor.name == major, "\(minor)")
        }
        let gMajor = try #require(SongKey(parsing: "G"))
        #expect(gMajor.diatonicChordSymbols == [
            "G", "Am", "Bm", "C", "D", "Em", "F#dim",
            "Gmaj7", "Am7", "Bm7", "Cmaj7", "D7", "Em7", "F#m7b5",
        ])
        let am = try #require(SongKey(parsing: "Am"))
        #expect(am.diatonicChordSymbols == [
            "Am", "Bdim", "C", "Dm", "Em", "F", "G",
            "Am7", "Bm7b5", "Cmaj7", "Dm7", "Em7", "Fmaj7", "G7", "E", "E7",
        ])
        #expect(am.tonicKey == Key(root: NoteClass(.A), scale: .minor))
    }

    @Test
    func `transposer keeps untouched tokens and respells moved ones`() throws {
        let key = try #require(SongKey(parsing: "G"))
        let padded = ChordToken(parsing: " G/B ")
        #expect(Transposer(semitones: 0, sourceKey: key).transpose(padded) == padded)
        #expect(Transposer(semitones: -24, sourceKey: key).transpose(padded) == padded)
        let up = Transposer(semitones: 3, sourceKey: key)
        #expect(up.targetKey?.name == "Bb")
        #expect(up.transpose(padded).original == "Bb/D")
        #expect(up.transpose(ChordToken(parsing: "C7(#9)")).original == "Eb7(#9)")
        #expect(up.transpose(ChordToken(parsing: "F#m7b5")).chord?.tonic?.type == .halfDim7)
        for passThrough in ["N.C.", "Bas", ""] {
            let token = ChordToken(parsing: passThrough)
            #expect(up.transpose(token) == token)
        }
        // An explicit target restores an author's non-default spelling.
        let fSharp = try #require(SongKey(parsing: "F#"))
        let gFlat = try #require(SongKey(parsing: "Gb"))
        let restore = Transposer(from: fSharp, to: gFlat)
        #expect(restore.semitones == 0)
        #expect(try Transposer(from: #require(SongKey(parsing: "E")), to: gFlat)
            .transpose(ChordToken(parsing: "B7")).original == "Db7")
    }

    @Test
    func `nashville numbers major minor borrowed and slash`() throws {
        let cMajor = try #require(SongKey(parsing: "C"))
        let numbers: [(String, String)] = [
            ("C", "1"), ("Dm7", "2m7"), ("G7/B", "5(7)/7"), ("C/E", "1/3"), ("Bb", "b7"),
            ("F#m7b5", "#4m7b5"), ("Ab", "b6"), ("Eb", "b3"), ("Am", "6m"), ("Fmaj7", "4maj7"),
            ("C6/9", "1(6/9)"), ("Gsus4", "5sus4"), ("N.C.", "N.C."), ("Bas", "Bas"),
        ]
        func number(_ chord: String, in key: SongKey) -> String {
            Nashville.number(for: ChordToken(parsing: chord), in: key)
        }
        for (chord, expected) in numbers {
            #expect(number(chord, in: cMajor) == expected, "\(chord)")
        }
        // Minor keys number from the relative major: Am F G E7 in A minor reads 6m 4 5 3(7).
        let am = try #require(SongKey(parsing: "Am"))
        let progression = ["Am", "F", "G", "E7"].map { number($0, in: am) }
        #expect(progression == ["6m", "4", "5", "3(7)"])
        #expect(Nashville.header(for: am) == "Am (rel. C)")
        #expect(Nashville.header(for: cMajor) == "C")
        #expect(try Nashville.header(for: #require(SongKey(parsing: "F#m"))) == "F#m (rel. A)")
    }

    @Test
    func `capo suggestions reach open shape keys`() throws {
        let bFlat = try #require(SongKey(parsing: "Bb"))
        let suggestions = Capo.suggestions(concertKey: bFlat)
            .map { "\($0.fret):\($0.shapeKey.name)" }
        #expect(suggestions == ["1:A", "3:G", "6:E", "8:D", "10:C"])
        let am = try #require(SongKey(parsing: "Am"))
        #expect(Capo.suggestions(concertKey: am).map { "\($0.fret):\($0.shapeKey.name)" } == [
            "0:Am",
            "5:Em",
        ])
        #expect(Capo.displayOffset(capo: 3, mode: .concert) == 3)
        #expect(Capo.displayOffset(capo: 3, mode: .shapes) == 0)
    }
}
