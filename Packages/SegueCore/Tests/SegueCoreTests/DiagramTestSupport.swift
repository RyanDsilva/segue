import Diagrams
import MusicTheory
import Tonic

/// Hand-built chord vocabulary for the diagram tests, independent of unit A's parser: the
/// interval table a chart's suffixes map to, with the tones a voicing must keep.
enum DiagramChords {
    struct Quality {
        let suffix: String
        let formula: ChordFormula

        init(_ suffix: String, _ intervals: [Int], essential: [Int]) {
            self.suffix = suffix
            formula = ChordFormula(intervals: intervals, essential: essential)
        }
    }

    static let qualities: [Quality] = [
        Quality("", [0, 4, 7], essential: [0, 4]),
        Quality("m", [0, 3, 7], essential: [0, 3]),
        Quality("5", [0, 7], essential: [0, 7]),
        Quality("7", [0, 4, 7, 10], essential: [0, 4, 10]),
        Quality("maj7", [0, 4, 7, 11], essential: [0, 4, 11]),
        Quality("m7", [0, 3, 7, 10], essential: [0, 3, 10]),
        Quality("mMaj7", [0, 3, 7, 11], essential: [0, 3, 11]),
        Quality("m7b5", [0, 3, 6, 10], essential: [0, 3, 6, 10]),
        Quality("dim", [0, 3, 6], essential: [0, 3, 6]),
        Quality("dim7", [0, 3, 6, 9], essential: [0, 3, 6, 9]),
        Quality("aug", [0, 4, 8], essential: [0, 4, 8]),
        Quality("sus2", [0, 2, 7], essential: [0, 2]),
        Quality("sus4", [0, 5, 7], essential: [0, 5]),
        Quality("7sus4", [0, 5, 7, 10], essential: [0, 5, 10]),
        Quality("6", [0, 4, 7, 9], essential: [0, 4, 9]),
        Quality("m6", [0, 3, 7, 9], essential: [0, 3, 9]),
        Quality("add9", [0, 4, 7, 14], essential: [0, 4, 14]),
        Quality("madd9", [0, 3, 7, 14], essential: [0, 3, 14]),
        Quality("9", [0, 4, 7, 10, 14], essential: [0, 4, 10, 14]),
        Quality("m9", [0, 3, 7, 10, 14], essential: [0, 3, 10, 14]),
        Quality("maj9", [0, 4, 7, 11, 14], essential: [0, 4, 11, 14]),
        Quality("6/9", [0, 4, 7, 9, 14], essential: [0, 4, 9, 14]),
        Quality("7(#9)", [0, 4, 7, 10, 15], essential: [0, 4, 10, 15]),
        Quality("7b9", [0, 4, 7, 10, 13], essential: [0, 4, 10, 13]),
        Quality("13", [0, 4, 7, 10, 14, 21], essential: [0, 4, 10, 21]),
        Quality("13sus4", [0, 5, 7, 10, 14, 21], essential: [0, 5, 10, 21]),
        Quality("m11", [0, 3, 7, 10, 14, 17], essential: [0, 3, 10, 17]),
    ]

    static let rootNames = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]

    static func quality(_ suffix: String) -> Quality {
        qualities.first { $0.suffix == suffix } ?? qualities[0]
    }

    /// `tones("G", "", bass: "B")` for `G/B`.
    static func tones(_ root: String, _ suffix: String = "", bass: String? = nil) -> ChordTones {
        let rootClass = pitchClass(root)
        let bassClass = bass.map(pitchClass)
        return ChordTones(
            root: rootClass,
            bass: bassClass == rootClass ? nil : bassClass,
            formula: quality(suffix).formula,
        )
    }

    static func pitchClass(_ name: String) -> PitchClass {
        let aliases = ["Db": 1, "D#": 3, "Gb": 6, "G#": 8, "A#": 10, "Cb": 11, "E#": 5, "Fb": 4]
        if let index = rootNames.firstIndex(of: name) {
            return PitchClass(index)
        }
        return PitchClass(aliases[name] ?? 0)
    }

    /// A named chord for the broad generator sweep.
    struct Named: CustomStringConvertible {
        let name: String
        let tones: ChordTones
        var description: String {
            name
        }
    }

    /// Every root with every quality, plus common slash chords (3rd, 5th and b7 in the
    /// bass, and a non-chord-tone bass like `C/D`).
    static let broadList: [Named] = {
        var list: [Named] = []
        for root in rootNames {
            for quality in qualities {
                list.append(Named(name: root + quality.suffix, tones: tones(root, quality.suffix)))
            }
            let rootClass = pitchClass(root)
            for (suffix, interval) in [("", 4), ("", 7), ("m", 10), ("", 10), ("", 2), ("m", 3)] {
                let bass = rootNames[rootClass.transposed(by: interval).rawValue]
                list.append(Named(
                    name: "\(root)\(suffix)/\(bass)",
                    tones: tones(root, suffix, bass: bass),
                ))
            }
        }
        return list
    }()

    /// A chart chord for hand-built `tones`, spelled with sharps except Eb, Ab and Bb.
    static func chart(_ original: String, tones: ChordTones) -> ChartChord {
        let spellings: [NoteClass] = [.C, .Cs, .D, .Eb, .E, .F, .Fs, .G, .Ab, .A, .Bb, .B]
        return ChartChord(
            tonic: nil,
            symbol: ChordSymbol(
                root: spellings[tones.root.rawValue],
                suffix: "",
                formula: tones.formula,
                bass: tones.bass.map { spellings[$0.rawValue] },
            ),
            original: original,
        )
    }

    /// A parsed chart chord built by hand (unit A's parser is not needed).
    static func chart(
        _ original: String,
        root: NoteClass,
        _ suffix: String = "",
        bass: NoteClass? = nil,
    )
        -> ChartChord
    {
        ChartChord(
            tonic: nil,
            symbol: ChordSymbol(
                root: root,
                suffix: suffix,
                formula: quality(suffix).formula,
                bass: bass,
            ),
            original: original,
        )
    }
}

/// Independent playability check, so the tests do not trust the generator's own rules.
enum ShapeCheck {
    /// Problems with `shape` as a fingering of `tones` in `tuning`; empty when playable.
    static func problems(_ shape: GuitarShape, tones: ChordTones, tuning: Tuning) -> [String] {
        var problems: [String] = []
        guard shape.frets.count == tuning.strings.count else {
            return ["\(shape.frets.count) frets for \(tuning.strings.count) strings"]
        }
        let pitches = shape.pitches(in: tuning)
        let classes = Set(pitches.map(PitchClass.init(midi:)))
        if pitches.count < 3 {
            problems.append("only \(pitches.count) strings sound")
        }
        if let bass = pitches.min(), PitchClass(midi: bass) != tones.lowest {
            problems.append("lowest note \(PitchClass(midi: bass)) is not \(tones.lowest)")
        }
        let missing = Set(tones.essentialPitchClasses).subtracting(classes)
        if !missing.isEmpty {
            problems.append("missing essential \(missing.sorted())")
        }
        let foreign = classes.subtracting(tones.pitchClasses)
        if !foreign.isEmpty {
            problems.append("non-chord tones \(foreign.sorted())")
        }
        let fretted = shape.absoluteFrets.compactMap(\.self).filter { $0 > 0 }
        if let low = fretted.min(), let high = fretted.max(), high - low > 3 {
            problems.append("span \(low)...\(high) exceeds 4 frets")
        }
        problems += fingerProblems(shape)
        return problems
    }

    /// Fingers: at most four distinct fingers; a barre's strings must not be open or muted.
    private static func fingerProblems(_ shape: GuitarShape) -> [String] {
        var problems: [String] = []
        let barreStrings = Set(shape.barres.flatMap { Array($0.strings) })
        let unbarred = shape.frets.indices.filter { string in
            guard let fret = shape.frets[string], fret > 0 else { return false }
            return !shape.barres.contains { $0.strings.contains(string) && $0.fret == fret }
        }
        if unbarred.count + shape.barres.count > 4 {
            problems.append("needs \(unbarred.count + shape.barres.count) fingers")
        }
        for string in barreStrings {
            guard let fret = shape.frets[string], fret > 0 else {
                problems.append("barre over open or muted string \(string)")
                continue
            }
        }
        return problems
    }

    /// `x32010`-style text for absolute frets (`(10)` for two-digit frets).
    static func text(_ shape: GuitarShape) -> String {
        shape.absoluteFrets.map { fret in
            guard let fret else { return "x" }
            return fret < 10 ? String(fret) : "(\(fret))"
        }.joined()
    }
}
