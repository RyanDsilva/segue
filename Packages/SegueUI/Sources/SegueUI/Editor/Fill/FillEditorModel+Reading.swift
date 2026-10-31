// P8-7d (docs/phases/8-workstreams/P8-7-time-model-and-fills.md sections 12.2, 12.6, 12.8,
// 15). What the fill sheet reads: row names and VoiceOver text, the notes resolved as the
// stage resolves them, the header's facts, the mini tab's notes and row 26's summary.

import Diagrams
import Editing
import Library
import MusicTheory
import Services

extension FillEditorModel {
    /// "A" ... "E", or "Saved".
    func letter(_ row: Row) -> String {
        switch row {
        case .saved: "Saved"
        case let .candidate(index): String(UnicodeScalar(UInt8(65 + index)))
        case .scratch: "New"
        }
    }

    /// The row's family name ("Pickup", "Walk"; "Hold" for no fill).
    func title(_ row: Row) -> String {
        switch row {
        case .saved: editing?.origin?.family.title ?? "Your fill"
        case let .candidate(index):
            candidates.indices.contains(index)
                ? candidates[index].family?.title ?? "Hold" : ""
        case .scratch: "From scratch"
        }
    }

    /// The row's pattern ("Chromatic line", "Slide into"): the template, since several
    /// candidates can share a rhythm family (R170).
    func subtitle(_ row: Row) -> String {
        switch row {
        case .saved: editing?.origin.map { Self.templateTitle($0.template) } ?? "Written by you"
        case let .candidate(index):
            candidates.indices.contains(index)
                ? Self.templateTitle(candidates[index].template) : ""
        case .scratch: "Empty"
        }
    }

    /// A template id as words: "chromaticLine" -> "Chromatic line".
    static func templateTitle(_ id: String) -> String {
        let named: [String: String] = [
            "hold": "Roots only",
            "pickup8": "Eighth pickup",
            "sixteenRun": "Sixteenth run",
            "sixteenRunLong": "Long sixteenth run",
            "rootFiveOctave": "Root, fifth, octave",
            "quarterWalk": "Quarter walk",
            "breakStop": "Break-stop",
        ]
        if let title = named[id] {
            return title
        }
        var words: [String] = []
        var current = ""
        for character in id {
            if character.isUppercase, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        words.append(current)
        let text = words.map { $0.lowercased() }.joined(separator: " ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// The candidate a row came from.
    func candidate(_ row: Row) -> FillCandidate? {
        guard case let .candidate(index) = row, candidates.indices.contains(index) else {
            return nil
        }
        return candidates[index]
    }

    /// The span's written positions (what a draft part applies to).
    var positions: [ChordPosition] {
        song.timeline.chords[span].map(\.position)
    }

    /// `events` resolved on the song as the stage and play-along resolve them.
    func resolved(_ events: [PartEvent]) -> [ResolvedNote] {
        guard !events.isEmpty else { return [] }
        let part = Part(span: anchor, events: events)
        let play = PartPlay(
            applied: AppliedPart(part: part, positions: positions),
            chords: span,
        )
        return play.resolve(
            timeline: song.timeline,
            transform: song.transform,
            tuning: song.placement.tuning,
            home: song.placement.home,
        )
    }

    /// The row's notes as named: the draft's when it was opened, else as loaded.
    func noteNames(_ row: Row) -> [String] {
        let events = drafts[row]?.events ?? loaded(row)
        return resolved(events).filter { !$0.outside }.map(\.name)
    }

    /// The row's contour: each note's pitch, in time order (the sparkline).
    func contour(_ row: Row) -> [Int] {
        resolved(drafts[row]?.events ?? loaded(row)).filter { !$0.outside }.map(\.midi)
    }

    /// "Option B, pickup, F sharp, G sharp, A, into A, suggested".
    func spokenName(_ row: Row) -> String {
        switch row {
        case .saved: "your saved fill"
        case .scratch: "a fill from scratch"
        case .candidate: "option \(letter(row))"
        }
    }

    func spokenRow(_ row: Row) -> String {
        let notes = noteNames(row).map(BassLine.spokenNote).joined(separator: ", ")
        var parts = [
            row == .saved ? "Saved fill" : "Option \(letter(row))",
            title(row).lowercased(),
            subtitle(row).lowercased(),
            notes.isEmpty ? "no notes" : notes,
            "into \(grid.chords.last?.name ?? "")",
        ]
        if row == .candidate(0) {
            parts.append("suggested")
        }
        if isEdited(row) {
            parts.append("edited")
        }
        return parts.joined(separator: ", ")
    }

    /// The score breakdown of a candidate, largest terms first ("Template prior 1.20").
    func breakdown(_ row: Row) -> [(term: String, value: Double)] {
        guard let candidate = candidate(row) else { return [] }
        return FillTerm.allCases.compactMap { term in
            candidate.breakdown[term].map { (term.rawValue, $0) }
        }
        .filter { abs($0.1) > 1e-9 }
        .sorted { abs($0.1) > abs($1.1) }
    }

    /// "Bridge: E -> Chorus 3: A".
    var spanTitle: String {
        let first = grid.chords.first?.name ?? ""
        let start = "\(song.sectionTitle(ofChord: span.lowerBound)): \(first)"
        let end = "\(song.sectionTitle(ofChord: span.upperBound)): \(grid.chords.last?.name ?? "")"
        return "\(start) \u{2192} \(end)"
    }

    /// "G -> A" when the span crosses a key change, else "G".
    var keyTitle: String? {
        let keys = grid.chords.compactMap(\.key?.name)
        var unique: [String] = []
        for key in keys where unique.last != key {
            unique.append(key)
        }
        return unique.isEmpty ? nil : unique.joined(separator: " \u{2192} ")
    }

    var crossesKeyChange: Bool {
        Set(grid.chords.compactMap(\.key)).count > 1
    }

    /// "96 BPM" (the tempo where the span starts), nil without `{tempo}`.
    var tempoTitle: String {
        let tempo = song.timeline.chords[span.lowerBound].tempo
        guard let tempo else { return "No tempo (90 BPM)" }
        let bpm = Int((tempo * tempoFactor).rounded())
        return "\(bpm) BPM"
    }

    /// Some of the span's lengths are the song's rule.
    var isEstimated: Bool {
        song.timeline.chords[span].contains(where: \.isEstimated)
    }

    /// The default name: "Fill into Chorus 3".
    var defaultName: String {
        "Fill into \(song.sectionTitle(ofChord: span.upperBound))"
    }

    /// How many times the start chord's section plays in written order ("Only #1 ... #n").
    var plays: Int {
        let chord = song.timeline.chords[span.lowerBound]
        guard song.timeline.passes.indices.contains(chord.pass) else { return 1 }
        let content = song.timeline.passes[chord.pass].content
        return max(1, song.timeline.passes.count { $0.content == content })
    }

    /// The section the "Shows on" choices count ("Chorus").
    var playsTitle: String {
        let chord = song.timeline.chords[span.lowerBound]
        guard song.timeline.passes.indices.contains(chord.pass) else { return "Section" }
        let content = song.timeline.passes[chord.pass].content
        let sections = song.model.sections
        return sections.indices.contains(content)
            ? SectionNotes.label(of: sections[content]) ?? "Section" : "Section"
    }

    /// What the mini tab draws: the draft's notes, then the landing root in the landing bar
    /// (unless a note already starts there), exactly what the stage lays out (section 12.6).
    var tabNotes: [TabNote] {
        let notes = resolved(draft.events)
        guard let chord = grid.chords.last else {
            return notes.filter { !$0.outside }.map { TabNote($0) }
        }
        return PartPlay.tabNotes(
            notes,
            landing: chord.symbol,
            onset: chord.onset,
            region: grid.region,
            tuning: grid.tuning,
            home: grid.home,
        )
    }

    /// The chord names over the mini tab.
    var tabChords: [(tick: Int, name: String)] {
        grid.chords.map { (tick: max($0.onset, grid.region.lowerBound), name: $0.name) }
    }

    static let bassViewNote = "Fills show in the bass-note view. Turn it on with B or the Bass "
        + "button."

    /// Row 26.
    func summary(for part: Part) -> FillSavedSummary {
        let family = part.origin.flatMap { FillSavedFamily(rawValue: $0.family.rawValue) }
            ?? .scratch
        let rank = part.origin.flatMap { FillSavedRank(rawValue: $0.rank.rawValue) }
            ?? .scratch
        let view: FillSavedView = switch (
            editedIn.contains(.fretboard),
            editedIn.contains(.pianoRoll),
        ) {
        case (true, true): .both
        case (true, false): .fretboard
        case (false, true): .pianoRoll
        case (false, false): .unedited
        }
        let shows: FillSavedShows = switch part.passes {
        case .all: .all
        case .only: .only
        case .last: .last
        }
        return FillSavedSummary(
            family: family,
            rank: rank,
            edited: part.origin?.edited ?? !part.events.isEmpty,
            view: view,
            chords: SmallBucket(part.chordCount),
            keyChange: crossesKeyChange,
            genre: WalkUpFeel(rawValue: song.genre.rawValue) ?? .pop,
            shows: shows,
            estimated: isEstimated,
        )
    }
}
