import Editing
import Foundation
import Library
import Observation
import Playback
import Services
import SwiftUI

/// Tap Timing (P8-7 section 7, R167 Q6): tap along to the play-along bar's range to set each
/// chord's length. With the click (one bar of count-in, then Segue's click at the range's
/// tempo; chords and bass muted unless turned on) every tap lands on the nearest beat; with no
/// click nothing sounds, the first tap starts the first chord and the tempo comes from the
/// taps. Space or Page Down starts the next chord, Tab skips one (it keeps its length), Esc
/// stops. Stopping never writes: the lane shows each change for review, and Keep saves them
/// as ordinary corrections (`source: "tap"`) in one write and one undo step. The editor and
/// the library only, never the stage; nothing while a gig runs.
@MainActor
@Observable
final class TapCapture {
    enum Phase: Equatable {
        /// The panel is open; the first Space starts.
        case ready
        /// Taps are being taken (with the click, the count-in is part of it).
        case tapping
        /// Stopped: the proposal is shown in the lane until Keep or Discard.
        case review
    }

    @ObservationIgnored private unowned let playAlong: PlayAlong
    private(set) var phase: Phase = .ready
    private(set) var events: [TapEvent] = []
    /// The chords tapped over (the range when the capture started) and their grid lengths.
    private(set) var chords: [TimedChord] = []
    private(set) var lengths: [Int] = []
    /// What stopping proposed; re-made when the review's tempo changes.
    private(set) var proposal: TapProposal?
    /// The review's tempo in no-click mode (derived, then -/+).
    private(set) var reviewTempo: Double?
    /// "Set song tempo to 96" was pressed.
    private(set) var tempoSet = false
    /// With the click: also play the chords or the bass of the range as it is now timed.
    private(set) var playChords = false
    private(set) var playBass = false
    /// The click's tempo (the range's `{tempo}` times the session's) when it started.
    private(set) var clickTempo: Double?
    @ObservationIgnored private(set) var stopwatch: TapStopwatch?
    /// The player generation the click started (anything else that plays stops it).
    @ObservationIgnored private var generation: Int?

    init(playAlong: PlayAlong) {
        self.playAlong = playAlong
    }

    // MARK: Settings (remembered in Settings > Audio's store)

    var mode: TapMode {
        playAlong.session.settings.settings.tapMode
    }

    var halfBeats: Bool {
        playAlong.session.settings.settings.tapHalfBeats
    }

    var announcesTaps: Bool {
        playAlong.session.settings.settings.tapAnnounce
    }

    func setMode(_ mode: TapMode) {
        guard phase == .ready else { return }
        playAlong.session.settings.update { $0.tapMode = mode }
    }

    func setHalfBeats(_ on: Bool) {
        playAlong.session.settings.update { $0.tapHalfBeats = on }
        requantise()
    }

    func setAnnouncesTaps(_ on: Bool) {
        playAlong.session.settings.update { $0.tapAnnounce = on }
    }

    func setPlayChords(_ on: Bool) {
        playChords = on
        restyleClick()
    }

    func setPlayBass(_ on: Bool) {
        playBass = on
        restyleClick()
    }

    // MARK: Progress

    var taps: Int {
        events.count {
            if case .tap = $0 {
                true
            } else {
                false
            }
        }
    }

    /// The chord the next tap starts (`chords.count`: the next tap ends the last one).
    var next: Int {
        min(events.count, chords.count + 1)
    }

    /// The tapped range's chords as the chart shows them.
    func title(_ index: Int) -> String {
        guard chords.indices.contains(index) else { return "" }
        let chord = chords[index]
        if chord.isSilent {
            return "N.C."
        }
        return playAlong.source?.cue(for: chord)?.text ?? chord.token
    }

    /// "Next: C, chord 3 of 12" / "Next: the end of G" / "Done".
    var waitingFor: String {
        let count = chords.count
        if next < count {
            return "Next: \(title(next)), chord \(next + 1) of \(count)"
        }
        if next == count, count > 0 {
            return "Next: the end of \(title(count - 1))"
        }
        return "Done"
    }

    /// The range's first chord, before the taps start ("Your first tap starts G").
    var firstTitle: String {
        guard let chord = playAlong.timeline.timeline.chords.first else { return "" }
        return chord.isSilent ? "N.C." : playAlong.source?.cue(for: chord)?.text ?? chord.token
    }

    /// Beats in the count-in bar.
    var countInBeats: Int {
        playAlong.timeline.startMeter.pulses
    }

    /// Seconds into the count-in still to go (with the click, before its first downbeat).
    func countInRemaining() -> Double? {
        guard phase == .tapping, mode == .click, let stopwatch else { return nil }
        let seconds = stopwatch.seconds()
        return seconds < 0 ? -seconds : nil
    }

    /// The beat of the count-in now (1-based), for the panel's dots.
    func countInBeat() -> Int? {
        guard let remaining = countInRemaining(), let clickTempo else { return nil }
        let beats = playAlong.timeline.startMeter.pulses
        let beat = beats - Int((remaining * clickTempo / 60).rounded(.up)) + 1
        return min(max(beat, 1), beats)
    }

    /// The panel's spoken value.
    var spokenValue: String {
        switch phase {
        case .ready:
            "Press Space to start"
        case .tapping:
            "\(waitingFor), \(taps) \(taps == 1 ? "tap" : "taps")"
        case .review:
            reviewSummary
        }
    }

    /// "3 chords changed, 1 skipped".
    var reviewSummary: String {
        guard let proposal else { return "" }
        let changed = proposal.changed.count
        var text = changed == 0 ? "No lengths changed"
            : "\(changed) \(changed == 1 ? "chord" : "chords") changed"
        if proposal.skipped > 0 {
            text += ", \(proposal.skipped) skipped"
        }
        return text
    }

    // MARK: Keys

    /// Space or Page Down (`half`: ⌥ held). The first one starts: the click's count-in, or
    /// without the click, the first chord. The tap after the last chord stops.
    func tap(half: Bool = false) {
        guard playAlong.session.isAvailable else {
            cancel()
            return
        }
        switch phase {
        case .ready:
            begin()
            if mode == .free {
                record(.tap(seconds: stopwatch?.seconds() ?? 0, half: half))
            }
        case .tapping:
            if mode == .click, let generation, playAlong.session.player?.generation != generation
                || playAlong.session.player?.isPlaying != true
            {
                // Something else played over the click: stop where the taps got to.
                stop()
                return
            }
            record(.tap(seconds: stopwatch?.seconds() ?? 0, half: half))
            if next > chords.count {
                stop()
            }
        case .review:
            break
        }
    }

    /// Tab: the next chord keeps its length.
    func skip() {
        guard phase == .tapping, next < chords.count else { return }
        record(.skip)
    }

    /// Esc or Stop: to review, or closed when nothing was tapped. Never writes.
    func stop() {
        stopClick()
        guard phase == .tapping, taps > 0 else {
            cancel()
            return
        }
        phase = .review
        reviewTempo = nil
        requantise()
    }

    /// Closes the panel without writing.
    func cancel() {
        stopClick()
        playAlong.endTapCapture()
    }

    /// Discard: nothing written.
    func discard() {
        if phase == .review {
            recordCapture(.discarded, chords: 0)
        }
        cancel()
    }

    /// Keep: every changed chord as a correction with `source: "tap"`, one write and one
    /// undo step; a push it had stays.
    func keep() {
        guard phase == .review, let proposal, let source = playAlong.source else { return }
        let applied = ChordAnchors.resolve(
            source.timing.chords,
            units: source.units,
            sections: source.sections,
        ).applied
        var seen = Set<ChordPosition>()
        var writes: [(old: ChordBeatsOverride?, new: ChordBeatsOverride)] = []
        for change in proposal.changed {
            let chord = chords[change.index]
            guard !chord.isSilent, seen.insert(chord.position).inserted,
                  let anchor = ChordAnchors.anchor(
                      at: chord.position,
                      units: source.units,
                      sections: source.sections,
                  )
            else { continue }
            let existing = applied[chord.position]
            writes.append((existing, ChordBeatsOverride(
                anchor: anchor,
                ticks: change.new,
                meter: chord.meter,
                push: existing?.push,
                source: .tap,
            )))
        }
        if !writes.isEmpty, playAlong.canEditTiming {
            playAlong.writeTiming("Tap Timing") { timing in
                for write in writes {
                    timing.chords.removeAll { $0 == write.old }
                    timing.chords.append(write.new)
                }
            }
            playAlong.session.settings.services.record(.featureUsed(.timingTap, playAlong.context))
        }
        recordCapture(.kept, chords: writes.count)
        cancel()
    }

    // MARK: Internals

    /// Row 27: how a review closed.
    private func recordCapture(_ outcome: TapCaptureOutcome, chords: Int) {
        playAlong.session.settings.services.record(.timingTapCaptured(TapCapturedSummary(
            mode: mode == .click ? .click : .free,
            outcome: outcome,
            chords: SmallBucket(chords),
            skipped: SmallBucket(proposal?.skipped ?? 0),
            tempoSet: tempoSet,
        )))
    }

    private func begin() {
        playAlong.stop()
        chords = playAlong.timeline.timeline.chords
        lengths = chords.indices.map(playAlong.gridTicks)
        events = []
        proposal = nil
        phase = .tapping
        if mode == .click {
            startClick()
        } else {
            stopwatch = TapStopwatch(clock: playAlong.session.clock)
        }
    }

    private func record(_ event: TapEvent) {
        events.append(event)
        guard announcesTaps, case .tap = event else { return }
        let index = next - 1
        let text = index < chords.count ? title(index) : "End"
        AccessibilityNotification.Announcement(text).post()
    }

    private func requantise() {
        guard phase == .review else { return }
        proposal = TapQuantiser.propose(
            events,
            chords: zip(chords, lengths).map { chord, ticks in
                TapQuantiser.Chord(ticks: ticks, ticksPerPulse: chord.meter.ticksPerPulse)
            },
            options: TapQuantiser.Options(
                mode: mode,
                tempo: mode == .click ? clickTempo : reviewTempo,
                halfBeats: halfBeats,
                hint: songTempo,
                pulsesPerBar: playAlong.timeline.startMeter.pulses,
            ),
        )
    }

    private var clickVoices: Set<VoiceToggle> {
        var voices: Set<VoiceToggle> = [.click]
        if playChords {
            voices.insert(.chords)
        }
        if playBass {
            voices.insert(.bass)
        }
        return voices
    }

    private func clickPhrase() -> Phrase {
        let settings = playAlong.session.settings.settings
        return PhraseBuilder.playAlong(
            playAlong.timeline,
            voices: clickVoices,
            sound: settings.chordSound,
            style: settings.chordStyle,
            factor: playAlong.factor,
            countIn: false,
        )
    }

    private func startClick() {
        guard let player = playAlong.session.makePlayer() else { return }
        let countIn = PhraseBuilder.countIn(playAlong.timeline, factor: playAlong.factor)
        player.loop(clickPhrase(), leadIn: countIn)
        generation = player.generation
        clickTempo = playAlong.tempo
        stopwatch = TapStopwatch(clock: playAlong.session.clock, startingIn: countIn.length)
    }

    /// A voice toggled while the click plays: the new phrase takes over where it is.
    private func restyleClick() {
        guard phase == .tapping, mode == .click, let player = playAlong.session.player,
              player.generation == generation, player.isPlaying
        else { return }
        let position = max(0, player.bodyPosition)
        player.replace(clickPhrase(), from: position, aligning: position)
    }

    private func stopClick() {
        if let generation, let player = playAlong.session.player,
           player.generation == generation, player.isPlaying
        {
            player.stop()
        }
        generation = nil
    }
}

extension TapCapture {
    // MARK: Review tempo (no click)

    /// Whether the review offers a tempo (no-click mode).
    var showsTempo: Bool {
        phase == .review && mode == .free
    }

    /// The song's `{tempo}` at the range's start.
    var songTempo: Double? {
        playAlong.timeline.startTempo
    }

    /// "Set song tempo to 96" is offered when the song has no `{tempo}` or another one.
    var offersSongTempo: Bool {
        guard showsTempo, let tempo = proposal?.tempo, playAlong.writeDirective != nil,
              playAlong.canEditTiming
        else { return false }
        return songTempo.map { abs($0 - tempo) >= 0.5 } ?? true
    }

    /// -/+ (and halve / double): re-quantises the taps at the new tempo.
    func setReviewTempo(_ bpm: Double) {
        guard showsTempo else { return }
        reviewTempo = min(
            max(bpm, TapQuantiser.tempoRange.lowerBound),
            TapQuantiser.tempoRange.upperBound,
        )
        requantise()
    }

    /// The explicit `{tempo}` write (R167 Q2): never automatic.
    func setSongTempo() {
        guard offersSongTempo, let tempo = proposal?.tempo else { return }
        playAlong.writeDirective?(.setDirective(name: "tempo", value: Self.tempoText(tempo)))
        tempoSet = true
        playAlong.session.settings.services.record(.featureUsed(.chartDirective, playAlong.context))
    }

    /// "96" or "96.5".
    static func tempoText(_ bpm: Double) -> String {
        bpm.rounded() == bpm ? "\(Int(bpm))" : String(format: "%.1f", bpm)
    }
}

extension PlayAlong {
    /// "Tap Timing" (`segue.playAlong.tap`): opens the tap panel over the bar's range.
    var canTapTiming: Bool {
        canEditTiming && session.isAvailable && !timeline.timeline.chords.isEmpty
    }

    func beginTapCapture() {
        guard canTapTiming, tap == nil else { return }
        stop()
        selected = nil
        spanEnd = nil
        tap = TapCapture(playAlong: self)
    }

    func endTapCapture() {
        tap = nil
    }
}
