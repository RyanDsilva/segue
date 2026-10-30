// P8-4a (docs/phases/8-workstreams/P8-4-bass.md section 7.3): which chord the stage mini neck
// shows. Pure, from the plan and the scroll offset, on P8-2's reading line and current pass.

import Foundation

/// A chord placed in the plan, as the mini neck reads it.
public struct PlacedChordRef: Sendable, Hashable {
    /// The shown pass it belongs to (`PlanPass.index`).
    public var pass: Int
    /// The text as drawn: the bass note in the bass-note view ("B", or "3 · B").
    public var text: String
    public var kind: ChordKind
    /// Top of its row in its column.
    public var y: Double
    /// The chord at the reading line is `N.C.` or unknown: this is the last real chord before
    /// it, to be drawn dimmed.
    public var dimmed = false

    public init(pass: Int, text: String, kind: ChordKind, y: Double, dimmed: Bool = false) {
        self.pass = pass
        self.text = text
        self.kind = kind
        self.y = y
        self.dimmed = dimmed
    }

    /// The note without a Nashville prefix ("3 · B" -> "B").
    public var note: String {
        text.components(separatedBy: " \u{00B7} ").last ?? text
    }
}

public extension StagePasses {
    /// The chord at the reading line (P8-4 7.3): in a one-column plan that scrolls, the last
    /// placed chord whose row top is at or above the reading line within the current pass,
    /// else that pass's first chord; in a plan that fits or uses columns, the current pass's
    /// first chord. `N.C.` and unknown chords keep the last real chord before them, flagged
    /// `dimmed`. Nil when the plan has no chords.
    static func chord(at offset: Double, plan: LayoutPlan, pinned: Int?) -> PlacedChordRef? {
        let chords = placedChords(in: plan)
        guard !chords.isEmpty else { return nil }
        guard let current = current(in: plan, offset: offset, pinned: pinned) else {
            return realChord(before: chords.count, in: chords) ?? firstReal(in: chords)
        }
        let inPass = chords.indices.filter { chords[$0].pass == current }
        guard let first = inPass.first else {
            // A pass without chords: the last real chord before it, dimmed.
            let start = chords.firstIndex { $0.pass > current } ?? chords.count
            return realChord(before: start, in: chords) ?? firstReal(in: chords)
        }
        var picked = first
        if followsScroll(plan) {
            let line = readLine(offset: offset, plan: plan)
            picked = inPass.last { chords[$0].y <= line } ?? first
        }
        if chords[picked].kind == .chord {
            return chords[picked]
        }
        return realChord(before: picked, in: chords) ?? firstReal(in: chords)
    }

    /// Every chord the plan places, in reading order (passes, then columns, rows and x).
    static func placedChords(in plan: LayoutPlan) -> [PlacedChordRef] {
        var result: [PlacedChordRef] = []
        for column in plan.columns {
            for block in column.blocks {
                guard let pass = block.pass, case let .rows(rows) = block.content else {
                    continue
                }
                for row in rows {
                    // A Chords only row carries its chords in `text`.
                    let runs = row.kind == .chordRow ? row.text : row.chords
                    for run in runs where run.role == .chord {
                        result.append(PlacedChordRef(
                            pass: plan.passes.indices.contains(pass)
                                ? plan.passes[pass].index : pass,
                            text: run.text,
                            kind: run.chordKind ?? .chord,
                            y: block.y + row.y,
                        ))
                    }
                }
            }
        }
        // Columns hold passes in order, but a pass split across columns keeps its own order.
        return result.enumerated().sorted { lhs, rhs in
            lhs.element.pass != rhs.element.pass
                ? lhs.element.pass < rhs.element.pass : lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// The last real chord before `index`, dimmed.
    private static func realChord(before index: Int, in chords: [PlacedChordRef])
        -> PlacedChordRef?
    {
        guard var found = chords[..<index].last(where: { $0.kind == .chord }) else { return nil }
        found.dimmed = true
        return found
    }

    private static func firstReal(in chords: [PlacedChordRef]) -> PlacedChordRef? {
        chords.first { $0.kind == .chord }
    }
}
