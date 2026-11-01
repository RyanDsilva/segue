// P9-3 9.1 (R178): the walk-up at a medley member boundary, from the member's last chord
// into the next member's first chord, planned in the next member's key (the R169 rule) and
// drawn like any walk-up. Fills stay within a member (they are saved per song), and a
// pick is per song, so neither applies here. Pure.

import ChordPro
import Editing
import MusicTheory

/// A medley member's passes in played order, as `BassLine.changes` takes them: the sections,
/// their origins in the member's own sections, and the member's walk-up context.
public struct MemberPasses: Sendable {
    public var sections: [RenderSection]
    public var origins: [Int]
    public var context: BassLineContext

    public init(sections: [RenderSection], origins: [Int], context: BassLineContext) {
        self.sections = sections
        self.origins = origins
        self.context = context
    }

    var walk: Walk {
        Walk(sections: sections, origins: origins, context: context)
    }
}

public extension BassLine {
    /// The change from `member`'s last chord into `next`'s first chord. Nil when either end
    /// is not a chord (`N.C.`, a chordless lyric section).
    static func boundary(from member: MemberPasses, into next: MemberPasses) -> ChordChange? {
        Boundary(walk: member.walk, next: next.walk)?.change()
    }

    /// `member`'s sections with the boundary walk-up into `next` drawn on the last chord
    /// (none while the density is Off).
    static func annotateBoundary(_ member: MemberPasses, into next: MemberPasses)
        -> [RenderSection]
    {
        let sections = member.sections
        guard member.context.density != .off else { return sections }
        let walk = member.walk
        guard let change = Boundary(walk: walk, next: next.walk)?.change(),
              let shown = change.shown, let place = walk.place(of: change),
              case var .lyrics(line) = sections[place.section].items[place.item]
        else { return sections }
        var result = sections
        line.chords[place.chord].approach = run(shown, change: change, context: member.context)
        result[place.section].items[place.item] = .lyrics(line)
        return result
    }
}

/// The two ends of a member boundary.
private struct Boundary {
    let walk: Walk
    let next: Walk
    let from: Walk.Chord
    let to: Walk.Chord

    init?(walk: Walk, next: Walk) {
        guard case let .chord(from)? = walk.elements.last, !from.viaStub,
              case let .chord(to)? = next.elements.first
        else { return nil }
        self.walk = walk
        self.next = next
        self.from = from
        self.to = to
    }

    private static func bass(_ chord: Walk.Chord) -> PitchClass {
        (chord.concert.bass ?? chord.concert.root).pitchClass
    }

    /// The departing chord on its member's timeline.
    private var timed: TimedChord? {
        walk.context.timeline.timed(pass: from.position.section, chord: from.position.chord)
    }

    /// The walk-up facts: the next member's key and scale (R169), a new section.
    private func walkContext() -> WalkUpContext {
        let bass = Self.bass
        let timed = timed
        let arriving = next.context.timeline.timed(
            pass: to.position.section,
            chord: to.position.chord,
        )
        return WalkUpContext(
            // R169: planned in the next member's key, with its scale.
            key: next.context.concertKey(written: arriving?.key),
            departing: from.concert,
            arriving: to.concert,
            genre: walk.context.genre,
            beats: timed.flatMap { $0.isEstimated ? nil : $0.pulses },
            tempo: timed?.tempo,
            intoSection: true,
            energyUp: Walk.energy(of: next.sections[to.section]),
            writtenLine: WalkUp.isWrittenLine(
                previous: chord(walk.elements.dropLast().last).map(bass),
                from: bass(from),
                to: bass(to),
                next: chord(next.elements.dropFirst().first).map(bass),
            ),
            mode: next.context.mode,
        )
    }

    func change() -> ChordChange {
        let bass = Self.bass
        let context = walk.context
        let timed = timed
        let walkContext = walkContext()
        let (candidates, suppressed) = WalkUp.evaluate(
            from: bass(from),
            to: bass(to),
            context: walkContext,
        )
        let top = candidates.first.flatMap { $0.kind == .hold ? nil : $0 }
        return ChordChange(
            id: ChangeID(from: from.position, toBass: to.writtenBass.pitch),
            from: from.chord,
            to: to.chord,
            fromName: from.concert.text,
            toName: to.concert.text,
            fromBass: from.writtenBass.text,
            toBass: to.writtenBass.text,
            section: from.section,
            intoSection: true,
            candidates: candidates,
            suppressed: suppressed,
            pick: nil,
            pickCandidate: nil,
            shown: context.density == .off ? nil : top,
            coveredBy: nil,
            meter: timed?.meter ?? context.timeline.meters.initial,
            tempo: timed?.tempo ?? context.timeline.tempos.initial,
        )
    }

    private func chord(_ element: Walk.Element?) -> Walk.Chord? {
        if case let .chord(chord)? = element {
            return chord
        }
        return nil
    }
}
