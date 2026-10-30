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
    public var tempo: Double?
    public var time: String?
    /// The song's saved picks, resolved against the written song (section 8.11).
    public var picks: ResolvedPicks

    public init(
        transform: DisplayTransform,
        genre: BassGenre,
        density: WalkUpDensity,
        tempo: Double?,
        time: String?,
        picks: ResolvedPicks = .empty,
    ) {
        self.transform = transform
        self.genre = genre
        self.density = density
        self.tempo = tempo
        self.time = time
        self.picks = picks
    }

    /// The concert key.
    public var key: SongKey? {
        transform.concertKey
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
    /// What charts show: the pick, else the top candidate; nil for hold or none.
    public var shown: WalkUpCandidate?
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
    /// walk-up (nothing while the density is Off).
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
        return result
    }

    /// The run drawn for `candidate` on `change`.
    static func run(
        _ candidate: WalkUpCandidate,
        change: ChordChange,
        context: BassLineContext,
    ) -> ApproachRun {
        let names = candidate.notes.map(\.chartName)
        let useDegrees = context.transform.options.nashville && !candidate.degrees.isEmpty
        let target = context.transform.concert(ChordToken(parsing: change.to.original)).chord
            .map { ($0.symbol.bass ?? $0.symbol.root).chartName } ?? change.toName
        return ApproachRun(
            change: change.id,
            notes: useDegrees ? candidate.degrees : names,
            chromatic: candidate.chromatic,
            isPick: change.pick != nil,
            accessibility: spoken(candidate, names: names, into: target),
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
    }

    enum Element {
        case chord(Chord)
        case chainBreak
    }

    let sections: [RenderSection]
    let context: BassLineContext
    let elements: [Element]
    let beats: [ChordPosition: ChordBeats.Estimate]

    init(sections: [RenderSection], origins: [Int], context: BassLineContext) {
        self.sections = sections
        self.context = context
        beats = ChordBeats.estimate(sections, time: context.time)
        let transposer = Transposer(
            semitones: context.transform.concertSemitones,
            sourceKey: context.transform.key.writtenKey,
        )
        func chords(of index: Int) -> (list: [Chord], breaks: Bool) {
            Self.chords(of: index, sections: sections, origins: origins, transposer: transposer)
        }
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
            let (list, breaks) = chords(of: index)
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
        transposer: Transposer,
    ) -> (list: [Chord], breaks: Bool) {
        let section = sections[index]
        let origin = origins.indices.contains(index) ? origins[index] : index
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
        let estimate = beats[ChordPosition(section: from.section, chord: localOrdinal(from))]
        let intoSection = from.isSectionLast && to.isSectionFirst && to.section != from.section
        return WalkUpContext(
            key: context.key,
            departing: from.concert,
            arriving: to.concert,
            genre: context.genre,
            beats: estimate?.beats,
            tempo: context.tempo,
            intoSection: intoSection,
            // Energy steers direction only into a new section (research section 2).
            energyUp: intoSection ? Self.energy(of: sections[to.section]) : nil,
            writtenLine: WalkUp.isWrittenLine(
                previous: previous.map(bass),
                from: bass(from),
                to: bass(to),
                next: next.map(bass),
            ),
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
        let shown = shown(pick: pickCandidate, candidates: candidates, skipped: skipped)
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

    /// The chord's ordinal within its annotated section (what the beat estimate keys).
    private func localOrdinal(_ chord: Chord) -> Int {
        chord.position.chord
    }

    /// B's section raises the energy (chorus, bridge, pre-chorus: true), settles (verse,
    /// outro: false), else nil.
    static func energy(of section: RenderSection) -> Bool? {
        let label = (SectionNotes.label(of: section) ?? "").lowercased()
        switch section.kind {
        case .bridge, .chorus: return true
        case .verse: return false
        default:
            if label.hasPrefix("pre-chorus") || label.hasPrefix("chorus") {
                return true
            }
            if label.hasPrefix("outro") {
                return false
            }
            return nil
        }
    }
}
