// Owner: unit B (Diagrams). Frozen interface: docs/phases/1-interfaces.md.

import Foundation

/// A stringed-instrument tuning.
public struct Tuning: Sendable, Hashable, Codable {
    /// Display name ("Standard", "Drop D", "DADGAD", "Open G", or a user label).
    public var name: String
    /// Open-string pitches as MIDI note numbers, lowest string first (Standard: E2 A2 D3 G3
    /// B3 E4 = 40 45 50 55 59 64). The count is the number of strings.
    public var strings: [Int]

    public init(name: String, strings: [Int]) {
        self.name = name
        self.strings = strings
    }

    public static let standard = Self(name: "Standard", strings: [40, 45, 50, 55, 59, 64])
    public static let dropD = Self(name: "Drop D", strings: [38, 45, 50, 55, 59, 64])
    public static let dadgad = Self(name: "DADGAD", strings: [38, 45, 50, 55, 57, 62])
    public static let openG = Self(name: "Open G", strings: [38, 43, 50, 55, 59, 62])

    /// Built-in tunings, in menu order.
    public static let presets: [Self] = [.standard, .dropD, .dadgad, .openG]

    // Bass tunings (P8-4, R152). A separate list, never part of `presets`: `{meta: tuning}`
    // parsing searches `presets` by name, and a second "Standard" would make it ambiguous.

    /// E1 A1 D2 G2.
    public static let bassStandard4 = Self(name: "EADG", strings: [28, 33, 38, 43])
    /// D1 A1 D2 G2.
    public static let bassDropD = Self(name: "DADG", strings: [26, 33, 38, 43])
    /// Eb1 Ab1 Db2 Gb2.
    public static let bassHalfDown4 = Self(name: "Eb Ab Db Gb", strings: [27, 32, 37, 42])
    /// B0 E1 A1 D2 G2.
    public static let bassStandard5 = Self(name: "BEADG", strings: [23, 28, 33, 38, 43])
    /// E1 A1 D2 G2 C3.
    public static let bassHighC5 = Self(name: "EADGC", strings: [28, 33, 38, 43, 48])

    /// Bass presets in menu order: 4-string, then 5-string.
    public static let bassPresets: [Self] = [
        .bassStandard4, .bassDropD, .bassHalfDown4, .bassStandard5, .bassHighC5,
    ]

    /// The string counts a bass tuning may have.
    public static let bassStringCounts: ClosedRange<Int> = 4 ... 5

    /// The standard bass tuning for `strings` strings (EADG for 4, BEADG for 5).
    public static func bassStandard(strings: Int) -> Self {
        strings == 5 ? .bassStandard5 : .bassStandard4
    }

    /// A bass tuning from note letters low to high, octaves implied ("BEADG", "DADG",
    /// "Eb Ab Db Gb"): the lowest string is the note in B0 ... A#1 (MIDI 23 ... 34), each
    /// next string the nearest occurrence strictly above the previous. Also accepts
    /// scientific pitches ("B0 E1 A1 D2 G2"). A preset's strings come back as that preset.
    /// nil unless 4 or 5 strings.
    public init?(bassLetters text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = trimmed.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" })
            .map(String.init)
        let pitched = tokens.map { ScientificPitch.midi(parsing: $0) }
        let strings: [Int]
        let name: String
        if !pitched.isEmpty, pitched.allSatisfy({ $0 != nil }) {
            strings = pitched.compactMap(\.self)
            guard zip(strings, strings.dropFirst()).allSatisfy({ $0 < $1 }) else { return nil }
            name = Self.pitchList(strings)
        } else {
            guard let notes = Self.letterNotes(tokens.joined()) else { return nil }
            var midi: [Int] = []
            for note in notes {
                if let previous = midi.last {
                    midi.append(previous + 1 + Self.wrapped(note.pitchClass - previous - 1))
                } else {
                    // B0 (23) ... A#1 (34).
                    midi.append(23 + Self.wrapped(note.pitchClass - 23))
                }
            }
            strings = midi
            let names = notes.map(\.name)
            name = names.allSatisfy { $0.count == 1 } ? names.joined()
                : names.joined(separator: " ")
        }
        guard Self.bassStringCounts.contains(strings.count) else { return nil }
        if let preset = Self.bassPresets.first(where: { $0.strings == strings }) {
            self = preset
            return
        }
        self.init(name: name, strings: strings)
    }

    /// `value` wrapped into 0 ... 11.
    private static func wrapped(_ value: Int) -> Int {
        ((value % 12) + 12) % 12
    }

    /// The notes of a run of letters with optional accidentals ("BbEbAb"), each with its
    /// pitch class and its name as typed (upper-case letter, `#` or `b`); nil on anything
    /// else.
    private static func letterNotes(_ text: String) -> [(pitchClass: Int, name: String)]? {
        let letters: [Character: Int] = [
            "C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11,
        ]
        var result: [(pitchClass: Int, name: String)] = []
        var rest = Substring(text)
        while let first = rest.first {
            let letter = Character(first.uppercased())
            guard let base = letters[letter] else { return nil }
            rest = rest.dropFirst()
            var value = base
            var name = String(letter)
            switch rest.first {
            case "\u{266F}", "#":
                value += 1
                name += "#"
                rest = rest.dropFirst()
            case "\u{266D}", "b":
                value -= 1
                name += "b"
                rest = rest.dropFirst()
            default:
                break
            }
            result.append((wrapped(value), name))
        }
        return result.isEmpty ? nil : result
    }

    /// The open-string letter of `string` (0 = lowest), sharps for black keys ("E", "A#").
    public func openStringName(_ string: Int) -> String {
        guard strings.indices.contains(string) else { return "" }
        return ScientificPitch.name(midi: strings[string]).filter { !$0.isNumber && $0 != "-" }
    }

    /// Parses a `{meta: tuning ...}` value: a preset name (case-insensitive, e.g. "DADGAD",
    /// "drop d") or scientific pitches low to high ("D2 A2 D3 G3 A3 D4"). `nil` if neither.
    public init?(metaValue: String) {
        let trimmed = metaValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = Self.presetKey(trimmed)
        if let preset = Self.presets.first(where: { Self.presetKey($0.name) == key }) {
            self = preset
            return
        }
        let tokens = trimmed.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" })
        let pitches = tokens.map { ScientificPitch.midi(parsing: String($0)) }
        guard (Self.stringCountRange).contains(pitches.count) else { return nil }
        let strings = pitches.compactMap(\.self)
        guard strings.count == pitches.count else { return nil }
        if let preset = Self.presets.first(where: { $0.strings == strings }) {
            self = preset
            return
        }
        self.init(name: Self.pitchList(strings), strings: strings)
    }

    /// The value written to `{meta: tuning ...}`: the preset name for a preset, otherwise
    /// scientific pitches low to high. `Tuning(metaValue: t.metaValue) == t` for presets
    /// and for named-by-pitches tunings.
    public var metaValue: String {
        if let preset = Self.presets.first(where: { $0.strings == strings }) {
            return preset.name
        }
        return Self.pitchList(strings)
    }

    /// String counts a parsed tuning may have (bass to extended-range guitars).
    static let stringCountRange = 3 ... 12

    /// Scientific pitch names low to high, sharps for black keys ("D2 A2 D3 G3 A3 D4").
    static func pitchList(_ strings: [Int]) -> String {
        strings.map(ScientificPitch.name(midi:)).joined(separator: " ")
    }

    /// Preset names compared case-, space- and hyphen-insensitively ("drop d" = "Drop-D").
    private static func presetKey(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

/// Scientific pitch notation (`E2`, `F#3`, `Bb1`) <-> MIDI note numbers (C4 = 60).
enum ScientificPitch {
    private static let letters: [Character: Int] = [
        "C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11,
    ]
    private static let sharpNames = [
        "C",
        "C#",
        "D",
        "D#",
        "E",
        "F",
        "F#",
        "G",
        "G#",
        "A",
        "A#",
        "B",
    ]

    /// MIDI number for `text`, or `nil` when it is not a letter, optional accidentals and
    /// an octave number (-1 ... 9).
    static func midi(parsing text: String) -> Int? {
        guard let first = text.first, let base = letters[Character(first.uppercased())] else {
            return nil
        }
        var rest = text.dropFirst()
        var offset = 0
        while let accidental = rest.first, let step = accidentalStep(accidental) {
            offset += step
            rest = rest.dropFirst()
        }
        guard let octave = Int(rest), (-1 ... 9).contains(octave) else { return nil }
        let midi = (octave + 1) * 12 + base + offset
        return (0 ... 127).contains(midi) ? midi : nil
    }

    /// `E2` for 40; black keys are spelled with sharps.
    static func name(midi: Int) -> String {
        let octave = Int((Double(midi) / 12).rounded(.down)) - 1
        let pitchClass = ((midi % 12) + 12) % 12
        return sharpNames[pitchClass] + String(octave)
    }

    private static func accidentalStep(_ character: Character) -> Int? {
        switch character {
        case "\u{266F}", "#": 1
        case "\u{266D}", "b": -1
        default: nil
        }
    }
}
