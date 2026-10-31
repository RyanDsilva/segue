import Editing
import Foundation
import Library
import Observation
import Playback
import Services

/// The editor's and library's play-along (P8-6 section 10.3): bass, chords and click at
/// tempo for the whole song, one section (looping by default) or a section to the end, with
/// one count-in at the start and a seamless loop (R162 Q5). Every length comes from the
/// song's `SongTimeline` (R167 Q1). Changes while playing (a timing edit, the tempo, a voice)
/// take over from the next bar. Sound goes through the one `SoundPlayer`, so it never plays
/// during a gig, and anything else that plays stops it.
/// Applies `change` to the song's saved timing as one step named `actionName`.
typealias TimingWriter = @MainActor (
    _ actionName: String,
    _ change: @escaping (inout ChordTiming) -> Void,
) -> Void

@MainActor
@Observable
final class PlayAlong {
    @ObservationIgnored let session: SoundSession
    @ObservationIgnored let context: FeatureContext
    /// Saves a change to the song's timing (applied to what is saved now); the editor makes
    /// it one undo step named `actionName`.
    @ObservationIgnored let writeTiming: TimingWriter
    /// The fills that replace the bass line in the range being played (P8-7 section 13,
    /// R168 Q4): P8-7c resolves the song's parts against the sliced timeline. Nil: none.
    @ObservationIgnored var fillProvider: (@MainActor (PlayAlongTimeline) -> [PlayAlongFill])?

    /// The song as it is now; nil before the preview has rendered.
    private(set) var source: PlayAlongSource?
    /// Whether the bar is open (closed by default; closing it stops playback).
    private(set) var isOpen = false
    private(set) var range: PlayAlongRange = .whole
    /// On by default for a section, off for the whole song.
    private(set) var loops = false
    /// The session tempo (40 ... 240); nil = the song's. Never saved, never written to
    /// `{tempo}`.
    private(set) var sessionTempo: Double?
    /// The strip's selected chord (an index into `timeline.timeline.chords`).
    var selected: Int?
    /// The other end of a shift-click span in the lane (P8-7 section 8); `span` reads it.
    var spanEnd: Int?
    /// The chord at the playhead while playing.
    private(set) var current: Int?
    /// The range voiced.
    private(set) var timeline = PlayAlongTimeline(timeline: .empty, passes: 0 ..< 0, chords: [])

    /// The phrase now sounding was built from these (the playhead reads them).
    @ObservationIgnored private var played: (timeline: PlayAlongTimeline, factor: Double)?
    /// After a change while playing, the pass that was patched: from `old` seconds into it the
    /// new phrase plays from its `new` seconds.
    @ObservationIgnored private var rebase: Rebase?
    /// The player generation this model started (observed: `isPlaying` reads it first).
    private var generation: Int?
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    static let tempoRange: ClosedRange<Double> = 40 ... 240

    /// A pass patched by a change while playing.
    private struct Rebase {
        var pass: Int
        var old: Double
        var new: Double
    }

    init(
        session: SoundSession,
        context: FeatureContext,
        writeTiming: @escaping TimingWriter,
    ) {
        self.session = session
        self.context = context
        self.writeTiming = writeTiming
    }

    // MARK: Song and range

    /// The song changed (an edit, a timing write, display options): the range is rebuilt and,
    /// while playing, takes over from the next bar.
    func update(_ source: PlayAlongSource?) {
        guard source != self.source else { return }
        self.source = source
        rebuild()
        if isPlaying {
            applyChange()
        }
    }

    /// Opens or closes the bar; closing stops playback.
    func setOpen(_ open: Bool) {
        guard open != isOpen else { return }
        isOpen = open
        if !open {
            stop()
        }
    }

    /// A new range: a section loops by default, the whole song does not. Playing restarts
    /// on it.
    func setRange(_ range: PlayAlongRange) {
        guard range != self.range else { return }
        self.range = range
        if case .section = range {
            loops = true
        } else {
            loops = false
        }
        selected = nil
        spanEnd = nil
        rebuild()
        if isPlaying {
            play()
        }
    }

    /// The Loop switch; playing restarts with it.
    func setLoops(_ loops: Bool) {
        guard loops != self.loops else { return }
        self.loops = loops
        if isPlaying {
            play()
        }
    }

    private func rebuild() {
        guard let source else {
            timeline = PlayAlongTimeline(timeline: .empty, passes: 0 ..< 0, chords: [])
            return
        }
        var built = PlayAlongTimeline.make(
            timeline: source.timeline,
            range: range,
            changes: source.changes,
            transform: source.transform,
            placement: source.placement,
        )
        built.fills = fillProvider?(built) ?? []
        timeline = built
        if let selected, !built.timeline.chords.indices.contains(selected) {
            self.selected = nil
        }
        if let spanEnd, selected == nil || !built.timeline.chords.indices.contains(spanEnd) {
            self.spanEnd = nil
        }
    }

    // MARK: Voices and tempo

    /// The toggled voices; Walk-ups follows the charts until it is set, and is never on
    /// while the chart's walk-ups are Off.
    var voices: Set<VoiceToggle> {
        let settings = session.settings.settings
        var voices: Set<VoiceToggle> = []
        if settings.playAlongBass {
            voices.insert(.bass)
        }
        if settings.playAlongChords {
            voices.insert(.chords)
        }
        if settings.playAlongClick {
            voices.insert(.click)
        }
        if source?.hasWalkUps != false,
           settings.playAlongWalkUps ?? source?.chartsShowWalkUps ?? false
        {
            voices.insert(.walkUps)
        }
        return voices
    }

    func setVoice(_ voice: VoiceToggle, _ isOn: Bool) {
        session.settings.update { settings in
            switch voice {
            case .bass: settings.playAlongBass = isOn
            case .chords: settings.playAlongChords = isOn
            case .click: settings.playAlongClick = isOn
            case .walkUps: settings.playAlongWalkUps = isOn
            }
        }
        if isPlaying {
            applyChange()
        }
    }

    /// The range's own tempo: its first `{tempo}`, else 90.
    var songTempo: Double {
        timeline.startTempo ?? PlayAlongTimeline.defaultTempo
    }

    /// What plays: the session tempo, else the song's.
    var tempo: Double {
        sessionTempo ?? songTempo
    }

    /// "No tempo in this song: playing at 90".
    var tempoHint: String? {
        guard source != nil, timeline.startTempo == nil, !timeline.chords.isEmpty else {
            return nil
        }
        return "No tempo in this song: playing at \(Int(PlayAlongTimeline.defaultTempo))"
    }

    /// Every `{tempo}` scaled by this (the tempo map keeps its shape).
    var factor: Double {
        tempo / songTempo
    }

    func setTempo(_ bpm: Double) {
        let clamped = min(
            max(bpm.rounded(), Self.tempoRange.lowerBound),
            Self.tempoRange.upperBound,
        )
        let new: Double? = clamped == songTempo ? nil : clamped
        guard new != sessionTempo else { return }
        sessionTempo = new
        if isPlaying {
            applyChange()
        }
    }

    /// 50% / 75% / 100% of the song's tempo.
    func setTempo(percent: Double) {
        setTempo(songTempo * percent)
    }

    // MARK: Transport

    /// Whether this bar's phrase is sounding (anything else that plays stops it).
    var isPlaying: Bool {
        guard let generation, let player = session.player else { return false }
        return player.isPlaying && player.generation == generation
    }

    /// Space / ⌥Space / the Play button.
    func togglePlay() {
        if isPlaying {
            stop()
        } else {
            play()
        }
    }

    /// Plays the range from its start after one bar of count-in.
    func play() {
        guard session.isAvailable, !timeline.chords.isEmpty,
              let player = session.makePlayer()
        else { return }
        let body = phrase(timeline, factor: factor)
        let countIn = PhraseBuilder.countIn(timeline, factor: factor)
        if loops {
            player.loop(body, leadIn: countIn)
        } else {
            player.play(body, leadIn: countIn)
        }
        generation = player.generation
        played = (timeline, factor)
        rebase = nil
        current = nil
        session.settings.services.record(.featureUsed(.playAlong, context))
        startTicking()
    }

    /// Stops at once.
    func stop() {
        if isPlaying {
            session.player?.stop()
        }
        if generation != nil {
            generation = nil
        }
        played = nil
        rebase = nil
        tickTask?.cancel()
        tickTask = nil
        if current != nil {
            current = nil
        }
    }

    private func phrase(_ timeline: PlayAlongTimeline, factor: Double) -> Phrase {
        PhraseBuilder.playAlong(
            timeline,
            voices: voices,
            sound: session.settings.settings.chordSound,
            style: session.settings.settings.chordStyle,
            factor: factor,
            countIn: false,
        )
    }

    /// A change while playing takes over from the next bar after what is already queued:
    /// that bar of the old phrase is aligned with the same bar of the new one.
    private func applyChange() {
        guard let player = session.player, let played else { return }
        let lookahead = SoundPlayer.lookahead
        let position = max(0, player.bodyPosition + lookahead)
        let oldClock = played.timeline.clock(factor: played.factor)
        let old = played.timeline.timeline
        let bar = old.barBeat(at: oldClock.tick(atSeconds: position)).bar + 1
        let oldTick = min(old.tick(of: BarBeat(bar: bar, beat: 1, tick: 0)), old.totalTicks)
        let new = timeline.timeline
        let newTick = min(new.tick(of: BarBeat(bar: bar, beat: 1, tick: 0)), new.totalTicks)
        let oldOffset = oldClock.seconds(oldTick)
        let newOffset = timeline.clock(factor: factor).seconds(newTick)
        player.replace(phrase(timeline, factor: factor), from: newOffset, aligning: oldOffset)
        rebase = Rebase(pass: player.pass, old: oldOffset, new: newOffset)
        self.played = (timeline, factor)
    }

    // MARK: Playhead

    /// Seconds into the range at the playhead (negative during the count-in); nil when not
    /// playing.
    func playheadSeconds() -> Double? {
        guard isPlaying, let player = session.player else { return nil }
        var seconds = player.bodyPosition
        if let rebase, player.pass == rebase.pass, seconds >= rebase.old {
            seconds += rebase.new - rebase.old
        }
        return seconds
    }

    /// The tick at the playhead; nil during the count-in or when not playing.
    func playheadTick() -> Int? {
        guard let seconds = playheadSeconds(), seconds >= 0, let played else { return nil }
        return played.timeline.clock(factor: played.factor).tick(atSeconds: seconds)
    }

    /// Follows the playhead: the chord under it, for the highlight and the strip. Called by
    /// the bar's ticker (and by tests on a scripted clock).
    func tick() {
        guard isPlaying else {
            if generation != nil {
                stop()
            }
            return
        }
        if let rebase, let player = session.player, player.pass > rebase.pass {
            self.rebase = nil
        }
        let chord = playheadTick().flatMap { timeline.timeline.chord(atTick: $0) }
        if chord != current {
            current = chord
        }
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                self?.tick()
            }
        }
    }

    /// The chord at the playhead in the preview.
    var cue: PlayAlongCue? {
        guard let current, timeline.timeline.chords.indices.contains(current) else { return nil }
        return source?.cue(for: timeline.timeline.chords[current])
    }

    /// The transport's spoken value: "Playing Chorus 2, bar 3 of 8" (read on focus).
    var transportValue: String {
        guard isPlaying, let source else { return "Stopped" }
        guard let current, timeline.timeline.chords.indices.contains(current) else {
            return "Counting in"
        }
        let chord = timeline.timeline.chords[current]
        let pass = timeline.passes.lowerBound + chord.pass
        let grid = timeline.timeline
        let bar = grid.barBeat(at: chord.onset).bar
        let total = max(1, grid.barBeat(at: max(0, grid.totalTicks - 1)).bar)
        return "Playing \(source.passTitle(pass)), bar \(bar) of \(total)"
    }
}
