// P8-7c (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 9.3). Resolving saved
// parts against the song as it is now, and where each one plays in an order. Pure.

import Editing
import MusicTheory

/// A part whose span still matches the written song.
public struct AppliedPart: Sendable, Hashable {
    public var part: Part
    /// The span's written positions, start ... landing (re-anchored when an edit moved them).
    public var positions: [ChordPosition]

    public init(part: Part, positions: [ChordPosition]) {
        self.part = part
        self.positions = positions
    }

    /// Whether the part covers the written change from `from` into `to`.
    public func covers(from: ChordPosition, to: ChordPosition) -> Bool {
        zip(positions, positions.dropFirst()).contains { $0 == from && $1 == to }
    }
}

/// One play of an applied part in an order.
public struct PartPlay: Sendable, Hashable {
    public var applied: AppliedPart
    /// Indices into `SongTimeline.chords`, start ... landing.
    public var chords: ClosedRange<Int>

    public init(applied: AppliedPart, chords: ClosedRange<Int>) {
        self.applied = applied
        self.chords = chords
    }

    public var part: Part {
        applied.part
    }
}

/// Saved parts resolved against a song: which apply, and which no longer match (kept in the
/// sidecar, listed with Remove, never applied, never deleted on load).
public struct ResolvedParts: Sendable, Hashable {
    public var applied: [AppliedPart]
    public var unmatched: [Part]

    public init(applied: [AppliedPart] = [], unmatched: [Part] = []) {
        self.applied = applied
        self.unmatched = unmatched
    }

    public static let empty = Self()

    /// Every play of every applied part in `timeline`'s order (written order in the editor
    /// and library, P8-2's played passes on stage): the pass plays the start chord, the
    /// landing follows in the next played chords exactly as written, and the pass passes the
    /// part's "Shows on" filter. In played order. `timeline` may be a slice of `song` (the
    /// passes a play-along loop plays): plays are counted in the whole `song`, so "Last
    /// time" is the song's last play of the section, never the loop's (R170).
    public func plays(in timeline: SongTimeline, song: SongTimeline? = nil) -> [PartPlay] {
        var result: [PartPlay] = []
        let chords = timeline.chords
        for applied in applied {
            let count = applied.positions.count
            guard count >= 2, let first = applied.positions.first else { continue }
            for index in chords.indices where index + count <= chords.count {
                let start = chords[index]
                guard !start.isSilent, start.position == first else { continue }
                let window = chords[index ..< index + count]
                guard zip(window, applied.positions).allSatisfy({ chord, position in
                    !chord.isSilent && chord.position == position
                }) else { continue }
                let plays = Self.plays(of: start, in: timeline, song: song ?? timeline)
                guard applied.part.passes.admits(occurrence: start.occurrence, of: plays)
                else { continue }
                result.append(PartPlay(applied: applied, chords: index ... index + count - 1))
            }
        }
        return result.sorted { $0.chords.lowerBound < $1.chords.lowerBound }
    }

    /// How many times the start chord's section (its pass in `timeline`) plays in `song`.
    static func plays(of chord: TimedChord, in timeline: SongTimeline, song: SongTimeline) -> Int {
        guard timeline.passes.indices.contains(chord.pass) else { return chord.occurrence }
        let content = timeline.passes[chord.pass].content
        return song.passes.filter { $0.content == content }.map(\.occurrence).max()
            ?? chord.occurrence
    }

    /// The part covering the written change `from` -> `to` on the `occurrence`-th of `plays`
    /// plays of `from`'s section (R167 Q8: the fill wins over a walk-up pick there).
    public func covering(
        from: ChordPosition,
        to: ChordPosition,
        occurrence: Int,
        plays: Int,
    ) -> PartID? {
        applied.first { applied in
            applied.covers(from: from, to: to)
                && applied.part.passes.admits(occurrence: occurrence, of: plays)
        }?.part.id
    }

    /// The applied parts sharing a chord change with `positions` (saving a part over them
    /// asks to replace them, section 9.3).
    public func overlapping(_ positions: [ChordPosition]) -> [Part] {
        let changes = Set(zip(positions, positions.dropFirst()).map { [$0, $1] })
        return applied.filter { applied in
            zip(applied.positions, applied.positions.dropFirst())
                .contains { changes.contains([$0, $1]) }
        }.map(\.part)
    }
}

public enum PartAnchors {
    /// `parts` resolved against `sections` (the song's render sections in written order),
    /// `units` (`SongSections.units(of:)`) and the song's written-order `timeline`: the start
    /// and landing re-anchor as picks do (P8-4 8.11), then the chords between must be
    /// consecutive in written order (across sections, `{chorus}` stubs written out, grid
    /// chords; never across `N.C.`) with the saved written basses, by pitch class. A part
    /// overlapping one applied before it (an older, hand-edited file) is unmatched.
    public static func resolve(
        _ parts: [Part],
        timeline: SongTimeline,
        units: [SongSectionUnit],
        sections: [RenderSection],
    ) -> ResolvedParts {
        var result = ResolvedParts()
        for part in parts {
            if let positions = positions(
                of: part,
                timeline: timeline,
                units: units,
                sections: sections,
            ),
                result.overlapping(positions).isEmpty
            {
                result.applied.append(AppliedPart(part: part, positions: positions))
            } else {
                result.unmatched.append(part)
            }
        }
        return result
    }

    /// The span's written positions now, or nil when it no longer matches.
    static func positions(
        of part: Part,
        timeline: SongTimeline,
        units: [SongSectionUnit],
        sections: [RenderSection],
    ) -> [ChordPosition]? {
        guard part.instrument == .bass,
              SpanAnchor.chordCount.contains(part.chordCount),
              let start = ChordAnchors.position(
                  of: part.span.start,
                  units: units,
                  sections: sections,
              ),
              let end = ChordAnchors.position(of: part.span.end, units: units, sections: sections)
        else { return nil }
        let basses = part.span.spanBass.map(\.bassPitch)
        let chords = timeline.chords
        let count = basses.count
        for index in chords.indices where index + count <= chords.count {
            guard chords[index].position == start, !chords[index].isSilent else { continue }
            let window = Array(chords[index ..< index + count])
            guard window.last?.position == end,
                  zip(window, basses).allSatisfy({ chord, bass in
                      !chord.isSilent && bass != nil
                          && ChordAnchors.writtenBass(chord.token)?.pitch == bass
                  })
            else { continue }
            return window.map(\.position)
        }
        return nil
    }
}
