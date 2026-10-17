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
