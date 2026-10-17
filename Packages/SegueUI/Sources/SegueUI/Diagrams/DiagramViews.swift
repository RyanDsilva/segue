// Owner: unit B (diagram views). Frozen interface: docs/phases/1-interfaces.md.
// Unit B may split this file; initialisers below are the frozen contract D builds against.

import Diagrams
import Editing
import MusicTheory
import SwiftUI

/// Diagram scale. All diagrams draw with `Canvas` and scale crisply; colours come from
/// `Theme.color` so they work in the light editor and on the dark stage.
enum DiagramSize: Sendable, Hashable {
    /// Editor diagram strip.
    case compact
    /// Popovers and the shape editor.
    case regular
    /// Live view strip.
    case stage
}

/// A guitar chord box: n strings from the tuning, base-fret label, barres, muted/open
/// markers, capo bar when `capoFret` is set (Shapes mode).
struct GuitarDiagramView: View {
    let name: String
    let shape: GuitarShape
    let tuning: Tuning
    var capoFret: Int?
    var size: DiagramSize = .regular

    var body: some View {
        fatalError("unimplemented: unit B")
    }
}

/// Compact one-octave keyboard with chord tones highlighted, the root marked distinctly
/// and the bass note as a separate marker/label under the keyboard.
struct PianoDiagramView: View {
    let name: String
    let voicing: PianoVoicing
    var size: DiagramSize = .regular
    /// When set, keys are tappable (custom voicing editing); called with the tapped pitch
    /// class.
    var onToggleKey: ((PitchClass) -> Void)?

    var body: some View {
        fatalError("unimplemented: unit B")
    }
}

/// All unique chords of the song, in order of first appearance, for one instrument.
/// Reads `RenderModel.diagrams`; chords without a diagram show their name only.
struct DiagramStrip: View {
    let diagrams: [RenderDiagram]
    let instrument: Instrument
    let tuning: Tuning
    var size: DiagramSize = .compact
    /// Called when the user picks a chord's diagram to customise it (editor only).
    var onCustomize: ((RenderDiagram) -> Void)?

    var body: some View {
        fatalError("unimplemented: unit B")
    }
}

/// Edits a custom shape for one chord and returns it as a `{define}`; the host (unit D)
/// writes it with `EditOperation.setDefine`.
struct ShapeEditorView: View {
    /// Chord name as written in the source (the define's name).
    let chordName: String
    let instrument: Instrument
    let tuning: Tuning
    /// Starting point: the current resolved shape / voicing, if any.
    var initialGuitar: GuitarShape?
    var initialPiano: PianoVoicing?
    var onSave: (ChordDefinition) -> Void
    var onCancel: () -> Void

    var body: some View {
        fatalError("unimplemented: unit B")
    }
}
