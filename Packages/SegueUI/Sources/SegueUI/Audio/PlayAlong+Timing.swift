import Library
import Playback
import Services

/// Correcting play-along timing from the chord-length lane and the Timing menu (P8-6 7.3,
/// 7.4): per-chord corrections and the song's rule, saved in the sidecar's `bass.timing`
/// (never the `.cho`), each one write (one undo step in the editor). The lane writes whole
/// beats; P8-7b adds sub-beat lengths, pushes and tap capture to the same writes.
extension PlayAlong {
    /// Whether timing can be changed (a saved, writable song).
    var canEditTiming: Bool {
        source?.canEdit == true
    }

    /// The chord's length in pulses (fractions for a sub-beat length), on the bar grid: a
    /// push does not change it (P8-7 section 8).
    func pulses(of index: Int) -> Double {
        guard let chord = chord(index) else { return 0 }
        return Double(gridTicks(of: index)) / Double(chord.meter.ticksPerPulse)
    }

    /// The saved correction that applies to chord `index`, if any.
    func correction(of index: Int) -> ChordBeatsOverride? {
        guard let source, let chord = chord(index), !chord.isSilent else { return nil }
        return ChordAnchors.resolve(
            source.timing.chords,
            units: source.units,
            sections: source.sections,
        ).applied[chord.position]
    }

    /// Chord `index` lasts `beats` pulses (1 ... 32): a correction of whole beats, keeping
    /// any push it had. The chords after it move.
    func setBeats(_ index: Int, _ beats: Int) {
        guard canEditTiming, let source, let chord = chord(index), !chord.isSilent,
              let anchor = ChordAnchors.anchor(
                  at: chord.position,
                  units: source.units,
                  sections: source.sections,
              )
        else { return }
        let beats = min(max(beats, 1), SongTimeline.maximumPulses)
        let existing = correction(of: index)
        let override = ChordBeatsOverride(
            anchor: anchor,
            ticks: beats * chord.meter.ticksPerPulse,
            meter: chord.meter,
            push: existing?.push,
        )
        guard override != existing else { return }
        save("Change Chord Length") { timing in
            timing.chords.removeAll { $0 == existing }
            timing.chords.append(override)
        }
    }

    /// Delete / "Use the Song's Rule": chord `index` loses its correction.
    func clearCorrection(_ index: Int) {
        guard canEditTiming, let existing = correction(of: index) else { return }
        save("Use the Song's Rule") { $0.chords.removeAll { $0 == existing } }
    }

    /// The song's rule (nil and one bar per chord are the same: the default).
    var rule: TimingRule {
        source?.timing.rule ?? .each(.bar)
    }

    func setRule(_ rule: TimingRule) {
        guard canEditTiming, rule != self.rule else { return }
        save("Change Timing Rule") { $0.rule = rule == .each(.bar) ? nil : rule }
    }

    /// "Reset corrections in this section": every correction on the chords of the pass
    /// holding the selection (or the range's first pass), in every pass of that section.
    func resetCorrectionsInSection() {
        guard canEditTiming, let source, let pass = selectedPass else { return }
        let content = source.timeline.passes[pass].content
        let applied = ChordAnchors.resolve(
            source.timing.chords,
            units: source.units,
            sections: source.sections,
        ).applied
        let removing = Set(applied.filter { $0.key.section == content }.map(\.value))
        guard !removing.isEmpty else { return }
        save("Reset Corrections") { $0.chords.removeAll { removing.contains($0) } }
    }

    /// "Reset corrections in the song".
    func resetAllCorrections() {
        guard canEditTiming, source?.timing.chords.isEmpty == false else { return }
        save("Reset Corrections") { $0.chords = [] }
    }

    /// Corrections that no longer match the song (kept in the sidecar until removed).
    var unmatchedCorrections: [ChordBeatsOverride] {
        source?.timeline.unmatched ?? []
    }

    /// "1 timing change no longer matches" > Remove.
    func removeUnmatchedCorrections() {
        guard canEditTiming, !unmatchedCorrections.isEmpty else { return }
        let unmatched = Set(unmatchedCorrections)
        save("Remove Timing Changes") { $0.chords.removeAll { unmatched.contains($0) } }
    }

    /// Whether the selected pass (or the range's first) has any correction.
    var sectionHasCorrections: Bool {
        guard let source, let pass = selectedPass else { return false }
        let content = source.timeline.passes[pass].content
        return ChordAnchors.resolve(
            source.timing.chords,
            units: source.units,
            sections: source.sections,
        )
        .applied.keys.contains { $0.section == content }
    }

    /// The full timeline's pass of the selection, else the range's first pass.
    var selectedPass: Int? {
        guard let source else { return nil }
        let pass = selected.flatMap(chord).map { $0.pass + timeline.passes.lowerBound }
            ?? (timeline.passes.isEmpty ? nil : timeline.passes.lowerBound)
        return pass.flatMap { source.timeline.passes.indices.contains($0) ? $0 : nil }
    }

    func chord(_ index: Int) -> TimedChord? {
        let chords = timeline.timeline.chords
        return chords.indices.contains(index) ? chords[index] : nil
    }

    func save(_ actionName: String, _ change: @escaping (inout ChordTiming) -> Void) {
        writeTiming(actionName, change)
        session.settings.services.record(.featureUsed(.playAlongTiming, context))
    }
}
