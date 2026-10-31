// P8-7d (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 12.3). The fill
// editor's audition: a fill's resolved notes heard against its chords as play-along voices
// them, from one bar before the fill's first note through the landing chord's first bar.
// Pure.

import Editing
import Foundation
import Library
import MusicTheory

/// A fill audition phrase and where it sits on the song's timeline, for the editor's
/// playhead.
public struct FillAuditionPhrase: Sendable {
    public var phrase: Phrase
    /// Ticks of the song's written-order timeline the phrase plays.
    public var ticks: Range<Int>
    private let clock: TickClock
    private let start: TimeInterval

    init(phrase: Phrase, ticks: Range<Int>, clock: TickClock, start: TimeInterval) {
        self.phrase = phrase
        self.ticks = ticks
        self.clock = clock
        self.start = start
    }

    /// The timeline tick `seconds` into the phrase (the playhead), clamped to `ticks`.
    public func tick(atSeconds seconds: TimeInterval) -> Int {
        let tick = clock.tick(atSeconds: start + max(0, seconds))
        return min(max(tick, ticks.lowerBound), max(ticks.lowerBound, ticks.upperBound - 1))
    }
}

public extension PhraseBuilder {
    /// The ticks a fill audition plays on `timeline` for the span `chords` (indices into
    /// `timeline.chords`, start ... landing): from the bar before the first of `notes` (never
    /// before the span's start) through the end of the landing chord's first bar.
    static func fillWindow(
        timeline: SongTimeline,
        chords: ClosedRange<Int>,
        notes: [ResolvedNote],
    ) -> Range<Int> {
        guard timeline.chords.indices.contains(chords.lowerBound),
              timeline.chords.indices.contains(chords.upperBound)
        else { return 0 ..< 0 }
        let start = timeline.chords[chords.lowerBound].onset
        let first = notes.filter { !$0.outside }.map(\.tick).min() ?? start
        let bar = timeline.barBeat(at: max(0, first)).bar
        let before = timeline.tick(of: BarBeat(bar: max(1, bar - 1), beat: 1, tick: 0))
        let from = max(start, min(before, first))
        let landing = timeline.chords[chords.upperBound]
        let downbeat = landing.onset + (landing.push?.ticks ?? 0)
        let landingBar = timeline.barBeat(at: max(0, downbeat)).bar
        var through = timeline.tick(of: BarBeat(bar: landingBar + 1, beat: 1, tick: 0))
        through = min(max(through, landing.onset + 1), max(timeline.totalTicks, landing.onset + 1))
        return from ..< max(from + 1, through)
    }

    /// A fill heard against its chords (section 12.3): the chords as play-along voices them,
    /// the bass on play-along's roots until the fill's first note, then the fill (articulations
    /// set the velocity and length played; a note past its chord's end is skipped), then the
    /// landing root. No walk-ups; the click only with `click`. `timeline` is the song in
    /// written order and `notes` were resolved on it; tempo from its tempo map times `factor`.
    static func fill(
        // swiftlint:disable:previous function_parameter_count
        span timeline: SongTimeline,
        chords: ClosedRange<Int>,
        notes: [ResolvedNote],
        voices: PlaybackVoices,
        transform: DisplayTransform,
        click: Bool,
        factor: Double = 1,
    ) -> FillAuditionPhrase {
        let window = fillWindow(timeline: timeline, chords: chords, notes: notes)
        var whole = PlayAlongTimeline.make(
            timeline: timeline,
            range: .whole,
            changes: [],
            transform: transform,
            placement: voices.placement,
        )
        whole.fills = fillRegion(notes).map { [$0] } ?? []
        var toggles: Set<VoiceToggle> = [.bass, .chords]
        if click {
            toggles.insert(.click)
        }
        let all = playAlong(
            whole,
            voices: toggles,
            sound: voices.sound,
            style: voices.style,
            factor: factor,
            countIn: false,
        )
        let clock = whole.clock(factor: factor)
        let start = clock.seconds(window.lowerBound)
        let stop = clock.seconds(window.upperBound)
        let events = all.events.compactMap { event -> NoteEvent? in
            guard event.onset >= start - 1e-9, event.onset < stop - 1e-9 else { return nil }
            var event = event
            event.onset -= start
            event.duration = min(event.duration, stop - start - event.onset)
            return event
        }
        return FillAuditionPhrase(
            phrase: Phrase(events: events, length: stop - start),
            ticks: window,
            clock: clock,
            start: start,
        )
    }

    /// `notes` (those inside their chords) as one fill over the bass line.
    private static func fillRegion(_ notes: [ResolvedNote]) -> PlayAlongFill? {
        let played = notes.filter { !$0.outside }
        guard let first = played.first,
              let end = played.map({ $0.tick + $0.playedLength }).max()
        else { return nil }
        return PlayAlongFill(
            region: first.tick ..< max(first.tick + 1, end),
            notes: played.map { note in
                PlayAlongFill.Note(
                    tick: note.tick,
                    length: note.playedLength,
                    midi: UInt8(clamping: note.midi),
                    velocity: note.playedVelocity,
                )
            },
        )
    }
}
