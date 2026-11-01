// P9-3 9.8 (R178): a medley's play-along is its members' play-alongs one after another, with
// no gap and no count-in between them (one count-in at the start): each member keeps its own
// key, tempo, meter, corrections, walk-ups and fills, and the click switches tempo at the
// boundary. Pure.

import Library

public extension PlayAlongTimeline {
    /// `parts` (each made by `make` for one member, in order) as one timeline: passes and
    /// ticks run on through the parts, each part's fills move with it. `passes` starts at the
    /// first part's start and counts every part's passes.
    static func concatenating(_ parts: [Self]) -> Self {
        guard parts.count > 1 else { return parts.first ?? Self(
            timeline: .empty,
            passes: 0 ..< 0,
            chords: [],
        ) }
        let timeline = SongTimeline.concatenating(parts.map(\.timeline))
        var chords: [PlayAlongChord] = []
        var fills: [PlayAlongFill] = []
        var start = 0
        for part in parts {
            for chord in part.chords where chords.count < timeline.chords.count {
                var chord = chord
                chord.timed = timeline.chords[chords.count]
                chords.append(chord)
            }
            fills += part.fills.map { fill in
                PlayAlongFill(
                    region: fill.region.lowerBound + start ..< fill.region.upperBound + start,
                    notes: fill.notes.map { note in
                        var note = note
                        note.tick += start
                        return note
                    },
                )
            }
            start += part.timeline.totalTicks
        }
        let first = parts[0].passes.lowerBound
        return Self(
            timeline: timeline,
            passes: first ..< first + timeline.passes.count,
            chords: chords,
            fills: fills,
        )
    }
}
