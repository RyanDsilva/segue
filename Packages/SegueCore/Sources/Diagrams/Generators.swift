// Owner: unit B (Diagrams). Frozen interface: docs/phases/1-interfaces.md.
// Unit B may split this file; the signatures below are the frozen contract.

import MusicTheory

/// Algorithmic guitar fingerings for any tuning (phase 1 spec, "Tunings and custom shapes").
public enum GuitarShapeGenerator {
    /// Ranked playable shapes for `tones` in `tuning`, best first, at most `limit`.
    /// Every result has `tones.lowest` as its lowest sounding note and contains every
    /// essential pitch class. Empty only when no fingering exists within a 4-fret span.
    public static func shapes(for tones: ChordTones, tuning: Tuning, limit: Int = 5)
        -> [GuitarShape]
    {
        fatalError("unimplemented: unit B")
    }
}

/// Hand-checked open and barre shapes, authored by us (no licence question).
public enum CuratedShapes {
    /// The curated shape for a chord, or `nil`. Only standard tuning has curated shapes.
    public static func shape(for tones: ChordTones, tuning: Tuning) -> GuitarShape? {
        fatalError("unimplemented: unit B")
    }
}

/// Default piano voicings (phase 1 spec, "Diagram components").
public enum PianoVoicingGenerator {
    /// Root-position close voicing within C3 ... C5 (MIDI 48 ... 72) with the slash bass
    /// (or root) in the left hand; when `previous` is given, the inversion that moves the
    /// least from it.
    public static func voicing(for tones: ChordTones, after previous: PianoVoicing?)
        -> PianoVoicing
    {
        fatalError("unimplemented: unit B")
    }

    /// Voicings for a chord sequence in song order, each voice-led from the one before.
    public static func voicings(for sequence: [ChordTones]) -> [PianoVoicing] {
        fatalError("unimplemented: unit B")
    }
}
