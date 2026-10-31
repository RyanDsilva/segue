// P8-4b (docs/phases/8-workstreams/P8-4-bass.md section 8.6, R161, R162). Walk-ups applied
// to a song in a played order: every chord change with its candidates and pick, and the
// sections with the shown run set on each departing chord. Pure.

import ChordPro
import Editing
import MusicTheory

/// What `BassLine` needs beyond the sections.
public struct BassLineContext: Sendable {
    /// Concert pitch (`concert(_:)`, the bass view's) and the song's Nashville toggle.
    public var transform: DisplayTransform
    /// The song's feel, else the profile's default.
    public var genre: BassGenre
    public var density: WalkUpDensity
    /// The song's timeline in written order (P8-7 section 5.7, R167 Q1): each departing
    /// chord's length, and the tempo and `{key}` in effect there. Annotated sections in a
    /// played order look chords up by their origin, so the written timeline serves them too.
    public var timeline: SongTimeline
    /// The song's saved picks, resolved against the written song (section 8.11).
    public var picks: ResolvedPicks
    /// The song's saved fills, resolved against the written song (P8-7 section 9.3): a fill
    /// covers the changes of its span on the plays it applies to, and wins there.
    public var parts: ResolvedParts
    /// The song's scale for passing notes (R170); nil = each key's own.
    public var mode: FillMode?
    /// The timeline in the order annotated when that is not written order (P8-2's played
    /// passes on stage: pass `i` is annotated section `i`), for drawing fills where they
    /// play (P8-7 section 14); nil = `timeline`.
    public var played: SongTimeline?

    public init(
        transform: DisplayTransform,
        genre: BassGenre,
        density: WalkUpDensity,
        timeline: SongTimeline,
        picks: ResolvedPicks = .empty,
        parts: ResolvedParts = .empty,
        mode: FillMode? = nil,
    ) {
        self.transform = transform
        self.genre = genre
        self.density = density
        self.timeline = timeline
        self.picks = picks
        self.parts = parts
        self.mode = mode
    }

    /// The song's concert key (its first `{key}`, or the detected key).
    public var key: SongKey? {
        transform.concertKey
    }

    /// The concert key in effect at a chord whose written key is `written` (a mid-song
    /// `{key}`, R168 Q2).
    func concertKey(written: SongKey?) -> SongKey? {
        written.map { $0.transposed(by: transform.concertSemitones) } ?? key
    }
}

/// One chord change in the order annotated.
public struct ChordChange: Sendable, Equatable, Identifiable {
    /// The departing chord's written position + the target's written bass.
    public var id: ChangeID
    public var from: RenderChord
    public var to: RenderChord
    /// The concert chords ("G", "C").
    public var fromName: String
    public var toName: String
    /// The departing chord's bass as written, and the target's (what a pick stores).
    public var fromBass: String
    public var toBass: String
    /// Index into the annotated sections of the departing chord's section.
    public var section: Int
    /// A ends its section and B starts a later one.
    public var intoSection: Bool
    /// [] when suppressed.
    public var candidates: [WalkUpCandidate]
    /// Which rule left no walk-up on the chart, for the Walk-ups list.
    public var suppressed: WalkUpSuppression?
    /// The user's pick when it applies here.
    public var pick: WalkUpPick?
    /// The pick rebuilt at concert pitch.
    public var pickCandidate: WalkUpCandidate?
    /// What charts show: the pick, else the top candidate; nil for hold or none, and nil on
    /// a change a fill covers in this play (R167 Q8: the fill wins, the pick is kept).
    public var shown: WalkUpCandidate?
    /// The fill covering this change in this play.
    public var coveredBy: PartID?
    /// The meter and `{tempo}` in effect at the departing chord (the audition plays in them).
    public var meter: Meter
    public var tempo: Double?
}

public enum BassLine {
    /// Every chord change of `sections` in the order given, with its candidates and pick.
    /// `origins[i]` is the index into the song's own `RenderModel.sections` that
    /// `sections[i]` came from (identity for the editor and library; P8-2's passes on stage).
    public static func changes(
        _ sections: [RenderSection],
        origins: [Int],
        context: BassLineContext,
    ) -> [ChordChange] {
        Walk(sections: sections, origins: origins, context: context).changes()
    }

    /// `sections` with `RenderChord.approach` set on each departing chord that shows a
    /// walk-up, and the saved fills drawn where they play (P8-7 section 14: `FillRun`s, or
    /// `.fillTab` blocks); nothing while the density is Off (fills follow it, R168 Q7).
    public static func annotate(
        _ sections: [RenderSection],
        origins: [Int],
        context: BassLineContext,
    ) -> [RenderSection] {
        guard context.density != .off else { return sections }
        let walk = Walk(sections: sections, origins: origins, context: context)
        var result = sections
        for change in walk.changes() {
            guard let shown = change.shown, let place = walk.place(of: change),
                  case var .lyrics(line) = result[place.section].items[place.item]
            else {
                continue
            }
            line.chords[place.chord].approach = run(shown, change: change, context: context)
            result[place.section].items[place.item] = .lyrics(line)
        }
        return drawFills(result, timeline: context.played ?? context.timeline, context: context)
    }

    /// The run drawn for `candidate` on `change`.
    static func run(
        _ candidate: WalkUpCandidate,
        change: ChordChange,
        context: BassLineContext,
    ) -> ApproachRun {
        let names = candidate.notes.map(\.chartName)
        let useDegrees = context.transform.options.nashville && !candidate.degrees.isEmpty
        let target = ChordSymbol(parsing: change.toName)
            .map { ($0.bass ?? $0.root).chartName } ?? change.toName
        return ApproachRun(
            change: change.id,
            notes: useDegrees ? candidate.degrees : names,
            chromatic: candidate.chromatic,
            isPick: change.pick != nil,
            accessibility: spoken(candidate, names: names, into: target),
            pitches: candidate.notes.map(\.pitchClass),
            ascending: candidate.direction == .neither ? nil : candidate.direction == .up,
        )
    }

    /// "walk up A, B into C"; a chromatic note adds "outside the key".
    public static func spoken(
        _ candidate: WalkUpCandidate,
        names: [String],
        into: String,
    ) -> String {
        let verb = switch candidate.direction {
        case .up: "walk up"
        case .down: "walk down"
        case .neither: "walk"
        }
        let notes = zip(names, candidate.chromatic).map { name, chromatic in
            spokenNote(name) + (chromatic ? " outside the key" : "")
        }
        return "\(verb) \(notes.joined(separator: ", ")) into \(spokenNote(into))"
    }

    /// "C sharp", "B flat".
    public static func spokenNote(_ name: String) -> String {
        guard name.count > 1 else { return name }
        let letter = String(name.prefix(1))
        return switch name.dropFirst() {
        case "#": letter + " sharp"
        case "b": letter + " flat"
        default: name
        }
    }
}

// MARK: - The walk

/// The chords of `sections` in played order, with chain breaks.
private struct Walk {
    struct Chord {
        /// Index into the annotated sections (the target section for a repeat stub).
        var section: Int
        var item: Int
        var index: Int
        var position: ChordPosition
        var chord: RenderChord
        var concert: ChordSymbol
        var writtenBass: (text: String, pitch: PitchClass)
        var isSectionFirst: Bool
        var isSectionLast: Bool
        /// Reached through a `{chorus}` stub: a target only, never a departure.
        var viaStub: Bool
        /// 1-based play of its section's content in this order, and how many plays it has.
        var occurrence = 1
        var plays = 1
    }

    enum Element {
        case chord(Chord)
        case chainBreak
    }

    let sections: [RenderSection]
    let context: BassLineContext
    let elements: [Element]

    init(sections: [RenderSection], origins: [Int], context: BassLineContext) {
        self.sections = sections
        self.context = context
        func chords(of index: Int) -> (list: [Chord], breaks: Bool) {
            Self.chords(of: index, sections: sections, origins: origins, context: context)
        }
        let plays = SectionPlays(sections: sections, origins: origins)
        var elements: [Element] = []
        for index in sections.indices {
            let section = sections[index]
            if section.isRepeat, section.items.isEmpty {
                // A `{chorus}` stub (previews only): the change leads into its chorus.
                if let target = SongSections.repeatTarget(of: index, in: sections),
                   var first = chords(of: target).list.first
                {
                    first.isSectionFirst = true
                    first.viaStub = true
                    elements.append(.chord(first))
                }
                elements.append(.chainBreak)
                continue
            }
            var (list, breaks) = chords(of: index)
            for offset in list.indices {
                list[offset].occurrence = plays.occurrence[index]
                list[offset].plays = plays.total[plays.content[index]] ?? 1
            }
            if breaks {
                // Walk chord by chord, inserting breaks where N.C. or unknown chords sit.
                elements += Self.withBreaks(index: index, section: section, chords: list)
            } else {
                for (offset, var chord) in list.enumerated() {
                    chord.isSectionFirst = offset == 0
                    chord.isSectionLast = offset == list.count - 1
                    elements.append(.chord(chord))
                }
            }
        }
        self.elements = elements
    }

    /// The `.chord` chords of section `index`, and whether the section breaks the chain.
    static func chords(
        of index: Int,
        sections: [RenderSection],
        origins: [Int],
        context: BassLineContext,
    ) -> (list: [Chord], breaks: Bool) {
        let section = sections[index]
        let origin = origins.indices.contains(index) ? origins[index] : index
        let semitones = context.transform.concertSemitones
        let songKey = context.transform.key.writtenKey
        let song = Transposer(semitones: semitones, sourceKey: songKey)
        var list: [Chord] = []
        var hasLyrics = false
        var hasBreak = false
        var ordinal = 0
        for (itemIndex, item) in section.items.enumerated() {
            guard case let .lyrics(line) = item else { continue }
            hasLyrics = true
            for (chordIndex, chord) in line.chords.enumerated() {
                switch chord.kind {
                case .chord:
                    let token = ChordToken(parsing: chord.original)
                    // Spelled in the `{key}` in effect there (P8-7 section 5.3).
                    let written = context.timeline.timed(pass: origin, chord: ordinal)?.key
                    let transposer = written == nil || written == songKey ? song
                        : Transposer(semitones: semitones, sourceKey: written)
                    if let concert = transposer.transpose(token).chord?.symbol,
                       let written = ChordAnchors.writtenBass(chord.original)
                    {
                        list.append(Chord(
                            section: index,
                            item: itemIndex,
                            index: chordIndex,
                            position: ChordPosition(section: origin, chord: ordinal),
                            chord: chord,
                            concert: concert,
                            writtenBass: written,
                            isSectionFirst: false,
                            isSectionLast: false,
                            viaStub: false,
                        ))
                    }
                    ordinal += 1
                case .noChord:
                    hasBreak = true
                case .unknown:
                    if !ChordBeats.isMark(chord.original) {
                        hasBreak = true
                    }
                }
            }
        }
        // A section with lyrics and no chords between two chords breaks the chain.
        return (list, hasBreak || (hasLyrics && list.isEmpty))
    }

    /// The section's chords with a break at each `N.C.` or unknown chord (and one for a
    /// chordless lyric section).
    static func withBreaks(index: Int, section: RenderSection, chords: [Chord]) -> [Element] {
        guard !chords.isEmpty else { return [.chainBreak] }
        var result: [Element] = []
        var pending = chords[...]
        for (itemIndex, item) in section.items.enumerated() {
            guard case let .lyrics(line) = item else { continue }
            for (chordIndex, chord) in line.chords.enumerated() {
                if let next = pending.first, next.item == itemIndex, next.index == chordIndex {
                    var next = next
                    next.isSectionFirst = next.position == chords.first?.position
                    next.isSectionLast = next.position == chords.last?.position
                    result.append(.chord(next))
                    pending = pending.dropFirst()
                } else if chord.kind == .noChord
                    || (chord.kind == .unknown && !ChordBeats.isMark(chord.original))
                {
                    result.append(.chainBreak)
                }
            }
        }
        return result
    }

    /// Where a change's departing chord sits in the annotated sections.
    struct Place {
        var section: Int
        var item: Int
        var chord: Int
    }

    func place(of change: ChordChange) -> Place? {
        for element in elements {
            if case let .chord(chord) = element, !chord.viaStub,
               chord.position == change.id.from, chord.section == change.section
            {
                return Place(section: chord.section, item: chord.item, chord: chord.index)
            }
        }
        return nil
    }

    func changes() -> [ChordChange] {
        var result: [ChordChange] = []
        for index in elements.indices {
            guard case let .chord(from) = elements[index], !from.viaStub,
                  index + 1 < elements.count, case let .chord(to) = elements[index + 1]
            else { continue }
            let previous: Chord? = if index > 0, case let .chord(chord) = elements[index - 1] {
                chord
            } else {
                nil
            }
            let next: Chord? = if index + 2 < elements.count,
                                  case let .chord(chord) = elements[index + 2]
            {
                chord
            } else {
                nil
            }
            result.append(change(from: from, to: to, previous: previous, next: next))
        }
        return result
    }

    /// The walk-up facts for the move from `from` to `to` in this order.
    private func walkContext(
        from: Chord,
        to: Chord,
        previous: Chord?,
        next: Chord?,
    ) -> WalkUpContext {
        func bass(_ chord: Chord) -> PitchClass {
            (chord.concert.bass ?? chord.concert.root).pitchClass
        }
        let timed = timed(from)
        let intoSection = from.isSectionLast && to.isSectionFirst && to.section != from.section
        // R169: a walk-up into a key change is planned in the new key.
        let arriving = self.timed(to)?.key
        let written = arriving != nil && arriving != timed?.key ? arriving : timed?.key
        return WalkUpContext(
            key: context.concertKey(written: written),
            departing: from.concert,
            arriving: to.concert,
            genre: context.genre,
            // A known length (chart, grid, a correction, a tap) counts; the song's rule is an
            // estimate, so the two-note cap stays for unmarked charts (R161).
            beats: timed.flatMap { $0.isEstimated ? nil : $0.pulses },
            tempo: timed?.tempo,
            intoSection: intoSection,
            // Energy steers direction only into a new section (research section 2).
            energyUp: intoSection ? Self.energy(of: sections[to.section]) : nil,
            writtenLine: WalkUp.isWrittenLine(
                previous: previous.map(bass),
                from: bass(from),
                to: bass(to),
                next: next.map(bass),
            ),
            mode: context.mode,
        )
    }

    private func change(from: Chord, to: Chord, previous: Chord?, next: Chord?) -> ChordChange {
        func bass(_ chord: Chord) -> PitchClass {
            (chord.concert.bass ?? chord.concert.root).pitchClass
        }
        let source = bass(from)
        let target = bass(to)
        let intoSection = from.isSectionLast && to.isSectionFirst && to.section != from.section
        let walkContext = walkContext(from: from, to: to, previous: previous, next: next)
        var (candidates, suppressed) = WalkUp.evaluate(
            from: source,
            to: target,
            context: walkContext,
        )
        let id = ChangeID(from: from.position, toBass: to.writtenBass.pitch)
        let pick = context.picks.pick(from: from.position, toBass: to.writtenBass.pitch)
        let pickCandidate = pick.flatMap { pick in
            WalkUp.candidate(
                kind: pick.kind,
                offsets: pick.offsets,
                from: source,
                to: target,
                context: walkContext,
            )
        }
        let skipped = context.density == .sections && !intoSection
        if skipped, suppressed == nil {
            suppressed = .density
        }
        let coveredBy = covering(from: from, to: to)
        let shown = coveredBy == nil
            ? shown(pick: pickCandidate, candidates: candidates, skipped: skipped) : nil
        return ChordChange(
            id: id,
            from: from.chord,
            to: to.chord,
            fromName: from.concert.text,
            toName: to.concert.text,
            fromBass: from.writtenBass.text,
            toBass: to.writtenBass.text,
            section: from.section,
            intoSection: intoSection,
            candidates: candidates,
            suppressed: suppressed,
            pick: pick,
            pickCandidate: pickCandidate,
            shown: shown,
            coveredBy: coveredBy,
            meter: timed(from)?.meter ?? context.timeline.meters.initial,
            tempo: timed(from)?.tempo ?? context.timeline.tempos.initial,
        )
    }

    /// The fill covering `from` -> `to` on this play of `from`'s section (R167 Q8).
    private func covering(from: Chord, to: Chord) -> PartID? {
        context.parts.covering(
            from: from.position,
            to: to.position,
            occurrence: from.occurrence,
            plays: from.plays,
        )
    }

    /// What charts show: nothing while Off; the pick (even where the density skips, R162
    /// Q2); else the top candidate unless skipped. A hold shows nothing.
    private func shown(
        pick: WalkUpCandidate?,
        candidates: [WalkUpCandidate],
        skipped: Bool,
    ) -> WalkUpCandidate? {
        guard context.density != .off else { return nil }
        if let pick {
            return pick.kind == .hold ? nil : pick
        }
        guard !skipped else { return nil }
        return candidates.first.flatMap { $0.kind == .hold ? nil : $0 }
    }

    /// The departing chord on the timeline: its origin section and ordinal.
    private func timed(_ chord: Chord) -> TimedChord? {
        context.timeline.timed(pass: chord.position.section, chord: chord.position.chord)
    }

    /// B's section raises the energy (chorus, bridge, pre-chorus: true), settles (verse,
    /// outro: false), else nil.
    static func energy(of section: RenderSection) -> Bool? {
        BassLine.sectionEnergy(section)
    }
}
