#if os(macOS)
    import Foundation
    import Observation
    import Playback
    import Services
    import Shows

    /// Rehearsal play-along (P8-6 section 10.4): bass, chords and click from the current pass
    /// of the played passes, with the slot's key and capo, or the looped pass over and over
    /// with R148's one-bar count-in at every wrap. It exists only in a rehearsal: `init`
    /// fails for a gig (the `RehearsalClick` pattern), so a gig's `LiveSession` has no path to
    /// a sound player at all (section 9). Fills play as walk-ups do (R168 Q4).
    @MainActor
    @Observable
    final class StagePlayAlong {
        @ObservationIgnored let sound: SoundSession
        /// The fills that replace the bass line in the passes played (P8-7 section 13): P8-7c
        /// resolves the song's parts against the sliced timeline. Nil: none.
        @ObservationIgnored var fillProvider: (@MainActor (PlayAlongTimeline) -> [PlayAlongFill])?

        /// What plays now (the passes from the current one, or the looped pass).
        private(set) var timeline = PlayAlongTimeline(timeline: .empty, passes: 0 ..< 0, chords: [])
        /// The looped pass repeats, each pass after its own count-in.
        private(set) var loops = false
        /// The count-in's length in seconds (before every pass of a loop, else only first).
        @ObservationIgnored private(set) var countInLength: TimeInterval = 0
        /// The player generation this started (observed: `isPlaying` reads it first).
        private var generation: Int?

        /// Nil unless `kind` is a rehearsal (and the app has sound).
        init?(kind: ShowKind, sound: SoundSession?) {
            // Exhaustive, so a new kind has to decide.
            switch kind {
            case .gig: return nil
            case .rehearsal: break
            }
            guard let sound else { return nil }
            self.sound = sound
        }

        /// Whether this play-along is sounding (anything else that plays stops it).
        var isPlaying: Bool {
            guard let generation, let player = sound.player else { return false }
            return player.isPlaying && player.generation == generation
        }

        /// Plays `timeline` with `voices` after a one-bar count-in; with `loops`, every pass
        /// is count-in plus the range, so each wrap counts in again (R148). `fills` (a medley's,
        /// already in the timeline's ticks) replace the `fillProvider`'s. Returns whether it
        /// started.
        @discardableResult
        func play(
            _ timeline: PlayAlongTimeline,
            voices: Set<VoiceToggle>,
            loops: Bool,
            fills: [PlayAlongFill]? = nil,
        ) -> Bool {
            guard sound.isAvailable, !timeline.chords.isEmpty, let player = sound.makePlayer()
            else { return false }
            var timeline = timeline
            timeline.fills = fills ?? fillProvider?(timeline) ?? []
            let settings = sound.settings.settings
            let body = PhraseBuilder.playAlong(
                timeline,
                voices: voices,
                sound: settings.chordSound,
                style: settings.chordStyle,
                countIn: false,
            )
            let countIn = PhraseBuilder.countIn(timeline)
            if loops {
                player.loop(countIn.followed(by: body))
            } else {
                player.play(body, leadIn: countIn)
            }
            self.timeline = timeline
            self.loops = loops
            countInLength = countIn.length
            generation = player.generation
            sound.settings.services.record(.featureUsed(.playAlong, .stage))
            return true
        }

        func stop() {
            if isPlaying {
                sound.player?.stop()
            }
            generation = nil
        }

        /// Which pass of the phrase sounds (a loop's wraps count up), nil when not playing.
        var pass: Int? {
            isPlaying ? sound.player?.pass : nil
        }

        /// Seconds into the range at the playhead: negative during a count-in.
        func playheadSeconds() -> Double? {
            guard isPlaying, let player = sound.player else { return nil }
            return loops ? player.bodyPosition - countInLength : player.bodyPosition
        }

        /// The tick at the playhead; nil during a count-in or when not playing.
        func playheadTick() -> Int? {
            guard let seconds = playheadSeconds(), seconds >= 0 else { return nil }
            return timeline.clock().tick(atSeconds: seconds)
        }
    }
#endif
