// P8-6 (docs/phases/8-workstreams/P8-6-audio.md section 6.4): the pure half of a lookahead
// pump (`RehearsalClick.pump`), generalised to phrases that may loop. Pure.

import Foundation

/// Walks a phrase on the wall clock: each call hands out the events due within the
/// lookahead that were not handed out yet, with their delay from now. A looping phrase
/// wraps forever; a swapped phrase takes over at the next wrap that has not been handed
/// out yet, so an A/B switch never cuts a phrase short.
public struct PhraseCursor: Sendable {
    public private(set) var phrase: Phrase
    public let loop: Bool
    /// The instant the current pass of the phrase began.
    public private(set) var passStart: Date
    /// The phrase that takes over at the next wrap.
    public private(set) var pending: Phrase?
    /// How many passes have begun (1 for the first).
    public private(set) var pass = 1
    /// The next event of the current pass to hand out.
    private var next = 0
    /// Seconds into the current pass up to which events were handed out.
    public private(set) var handed: TimeInterval = 0

    public init(phrase: Phrase, start: Date, loop: Bool) {
        self.phrase = phrase
        passStart = start
        self.loop = loop && phrase.length > 0
    }

    /// Every event whose time falls at or before `now + lookahead` and was not handed out
    /// yet, in order, with its delay from `now` (0 when already late).
    public mutating func due(
        at now: Date,
        lookahead: TimeInterval,
    ) -> [(NoteEvent, delay: TimeInterval)] {
        let horizon = now.addingTimeInterval(lookahead)
        var result: [(NoteEvent, delay: TimeInterval)] = []
        defer { handed = horizon.timeIntervalSince(passStart) }
        while true {
            while next < phrase.events.count {
                let event = phrase.events[next]
                let time = passStart.addingTimeInterval(event.onset)
                guard time <= horizon else { return result }
                result.append((event, max(0, time.timeIntervalSince(now))))
                next += 1
            }
            guard loop else { return result }
            let wrap = passStart.addingTimeInterval(phrase.length)
            guard wrap <= horizon else { return result }
            if let pending {
                phrase = pending
                self.pending = nil
            }
            passStart = wrap
            next = 0
            pass += 1
            if phrase.length <= 0 {
                return result
            }
        }
    }

    /// Replaces the phrase from the next wrap not yet handed out (A/B, timing edits). With
    /// no loop, nothing wraps and the swap never takes effect.
    public mutating func swap(to phrase: Phrase) {
        pending = phrase
    }

    /// Replaces the current pass from a point not yet handed out (a play-along timing,
    /// tempo or voice change applying from the next bar): the old events before `oldOffset`
    /// still play, then `phrase`'s events from `newOffset` on, moved so that `newOffset`
    /// lands at `oldOffset`. A looping cursor plays `phrase` whole from the next wrap.
    /// `oldOffset` is raised to what was already handed out, so nothing plays twice.
    public mutating func replace(
        with phrase: Phrase,
        from newOffset: TimeInterval,
        aligning oldOffset: TimeInterval,
    ) {
        let shift = max(0, handed - oldOffset)
        let old = oldOffset + shift
        let new = newOffset + shift
        let kept = self.phrase.events.filter { $0.onset < old }
        let moved = phrase.events.filter { $0.onset >= new }.map { event in
            var event = event
            event.onset += old - new
            return event
        }
        self.phrase = Phrase(events: kept + moved, length: old + max(0, phrase.length - new))
        // Sorted, the handed-out events (all kept, all before `old`) come first.
        next = kept.count { $0.onset <= handed }
        if loop {
            pending = phrase
        }
    }

    /// Whether a non-looping phrase has played out by `now`.
    public func isFinished(at now: Date) -> Bool {
        !loop && now >= passStart.addingTimeInterval(phrase.length)
    }

    /// Seconds into the pass sounding at `now` (for a playhead).
    public func position(at now: Date) -> TimeInterval {
        let elapsed = now.timeIntervalSince(passStart)
        guard phrase.length > 0 else { return 0 }
        if elapsed < 0 {
            // `now` is still in the previous pass (the cursor ran ahead by the lookahead).
            return max(0, elapsed + phrase.length)
        }
        return min(elapsed, phrase.length)
    }
}
