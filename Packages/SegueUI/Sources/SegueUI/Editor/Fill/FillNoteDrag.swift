// P8-7d (docs/phases/8-workstreams/P8-7-time-model-and-fills.md sections 12.4, 12.5). A note
// drag shared by the step grid and the piano roll, and the articulation marks on a note.

import AppKit
import MusicTheory
import SwiftUI

/// A drag in the step grid or the piano roll: the notes moving (or one note's right edge),
/// in ticks and semitones so far.
struct FillNoteDrag: Equatable {
    var hit: HitNote?
    var ids: Set<Int>
    /// The note whose right edge is dragged.
    var resizing: Int?
    var ticks = 0
    var semitones = 0
    var copy = false
    var moved = false

    struct HitNote: Equatable {
        var id: Int
        var edge: Bool
    }

    static func begin(
        at _: CGPoint,
        hit: (id: Int, edge: Bool)?,
        selection: Set<Int>,
        extending _: Bool,
    ) -> Self {
        guard let hit else { return Self(hit: nil, ids: []) }
        let ids = selection.contains(hit.id) ? selection : [hit.id]
        return Self(
            hit: HitNote(id: hit.id, edge: hit.edge),
            ids: hit.edge ? [] : ids,
            resizing: hit.edge ? hit.id : nil,
            copy: NSEvent.modifierFlags.contains(.option),
        )
    }

    mutating func update(_ width: CGFloat, axis: FillTimeAxis, rhythm: FillRhythmSnap) {
        guard hit != nil else { return }
        let raw = Int((width / axis.scale).rounded())
        let step = rhythm.ticks
        ticks = Int((Double(raw) / Double(step)).rounded()) * step
        if abs(width) > 3 {
            moved = true
        }
    }
}

/// Articulation marks before a fret or name: slide "s", hammer "h", pull "p", ghost "x".
enum FillNoteLabels {
    static func prefix(_ articulations: Set<Articulation>) -> String {
        var text = ""
        if articulations.contains(.slide) {
            text += "s"
        }
        if articulations.contains(.hammer) {
            text += "h"
        }
        if articulations.contains(.pull) {
            text += "p"
        }
        if articulations.contains(.ghost) {
            text += "x"
        }
        if articulations.contains(.accent) {
            text += ">"
        }
        if articulations.contains(.staccato) {
            text += "."
        }
        return text
    }
}
