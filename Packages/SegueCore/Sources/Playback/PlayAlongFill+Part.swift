// P8-7c (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 13, R167 Q8, R168
// Q4). Saved fills as play-along plays them: each applied fill's resolved notes replace the
// bass voice's roots and walk-up over its region, on every play it applies to. Pure.

import Editing
import Library

public extension PlayAlongFill {
    /// The fills of `parts` (resolved against the written song) in `playAlong`'s slice, in
    /// its ticks: each play whose start and landing the slice plays, its notes resolved at
    /// `placement` (the bass voice's tuning and hand position) through `transform`. A note
    /// past its chord's end after a timing edit is skipped; articulations set the velocity
    /// and length played. The region runs from the first note to the end of the last.
    ///
    /// "Shows on: Last time" counts the plays inside the slice.
    static func fills(
        _ parts: ResolvedParts,
        in playAlong: PlayAlongTimeline,
        transform: DisplayTransform,
        placement: BassPlacement,
    ) -> [Self] {
        parts.plays(in: playAlong.timeline).compactMap { play in
            let notes = play.resolve(
                timeline: playAlong.timeline,
                transform: transform,
                tuning: placement.tuning,
                home: placement.home,
            ).filter { !$0.outside }
            guard let first = notes.first,
                  let end = notes.map({ $0.tick + $0.playedLength }).max()
            else { return nil }
            return Self(
                region: first.tick ..< max(first.tick + 1, end),
                notes: notes.map { note in
                    Note(
                        tick: note.tick,
                        length: note.playedLength,
                        midi: UInt8(clamping: note.midi),
                        velocity: note.playedVelocity,
                    )
                },
            )
        }
    }
}
