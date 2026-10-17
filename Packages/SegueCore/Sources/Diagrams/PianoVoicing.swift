// Owner: unit B (Diagrams). Frozen interface: docs/phases/1-interfaces.md.

import MusicTheory

/// A concrete piano voicing (always concert pitch).
public struct PianoVoicing: Sendable, Hashable, Codable {
    /// Right-hand notes as MIDI note numbers, ascending.
    public var notes: [Int]
    /// Left-hand bass note (MIDI), typically the slash bass or the root; `nil` for none.
    public var bass: Int?
    /// The chord root, drawn distinctly from other chord tones.
    public var root: PitchClass

    public init(notes: [Int], bass: Int? = nil, root: PitchClass) {
        self.notes = notes
        self.bass = bass
        self.root = root
    }

    /// The right-hand notes folded into one octave for the compact diagram: unique pitch
    /// classes in display order.
    public var foldedPitchClasses: [PitchClass] {
        var seen = Set<PitchClass>()
        return notes.map(PitchClass.init(midi:)).filter { seen.insert($0).inserted }
    }
}

/// Instruments the diagram strip can show.
public enum Instrument: String, Sendable, Hashable, Codable, CaseIterable {
    case guitar
    case piano
}
