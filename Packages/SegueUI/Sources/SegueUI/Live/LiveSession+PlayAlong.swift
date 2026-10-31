#if os(macOS)
    import AppKit
    import Editing
    import Foundation
    import Library
    import LiveLayout
    import Playback
    import Shows

    /// What Rehearsal play-along needs to follow the audio (P8-6 10.4).
    struct PlayAlongFollow {
        /// Auto-scroll ran when play-along started: it runs again when it stops.
        var resumesScroll = false
        /// The phrase pass last seen (a loop's wrap counts it up).
        var pass = 0
        /// Where the follow scroll last aimed, and the ease towards it.
        var target: Double?
        var ease: Ease?
        /// Polls the playhead while playing.
        var task: Task<Void, Never>?
        /// Ends the ease's per-frame redraw.
        var easeTask: Task<Void, Never>?

        /// A 0.25 s ease of the scroll from `from` to wherever the scroller now is.
        struct Ease {
            var from: Double
            var start: Date
        }

        static let easeDuration: TimeInterval = 0.25
        static let tick: Duration = .milliseconds(50)
    }

    /// Rehearsal play-along on stage (P8-6 10.4, R162 Q4, R168 Q4): `P` plays the current
    /// song's played passes from the current pass (or loops the looped pass), with the slot's
    /// key and capo. The audio is the clock while it plays: auto-scroll pauses, the stage
    /// keeps the line at the playhead on the reading line, a loop wraps on the phrase end
    /// with the one-bar count-in, the metronome restarts on its grid and the `K` click stays
    /// silent while play-along clicks.
    extension LiveSession {
        /// The app hands its sound over as the stage starts: a rehearsal gets play-along, a
        /// gig cannot (`StagePlayAlong.init` fails for one).
        func attachSound(_ sound: SoundSession) {
            guard playAlong == nil else { return }
            playAlong = StagePlayAlong(kind: kind, sound: sound)
        }

        /// Whether play-along is sounding (the header pill).
        var isPlayingAlong: Bool {
            playAlong?.isPlaying == true
        }

        /// `P`: starts or stops play-along. A gig only flashes (no audio path exists there).
        func togglePlayAlong() {
            guard let playAlong else {
                flash(kind == .rehearsal ? "Sound is unavailable" :
                    "Play-along works in rehearsals")
                return
            }
            if playAlong.isPlaying {
                stopPlayAlong()
                flash("Play-along off")
                return
            }
            guard state.record.currentBreak == nil,
                  let current = currentPass(at: context.scrollClock.now()),
                  startPlayAlong(from: current)
            else {
                flash("Nothing to play along with")
                return
            }
        }

        /// Plays from shown pass `index`: the looped pass over and over when it is the one
        /// looping, else to the end of the song.
        @discardableResult
        func startPlayAlong(from index: Int) -> Bool {
            guard let playAlong, let slot = state.current, let song = slot.song,
                  let model = currentModel
            else { return false }
            // The played passes, as the stage laid them out (P8-2): the slot's arrangement,
            // else the full song.
            var order = ArrangementResolver.fullSong(SongSections.units(of: song.document))
            if case let .applied(passes, _) = StageRequest.resolution(
                slot.item.arrangement,
                song: song,
            ) {
                order = passes
            }
            guard order.indices.contains(index) else { return false }
            let looping = loopPass == index
            let timeline = Self.playAlongTimeline(
                song: song,
                model: model,
                order: order,
                range: looping ? .section(index) : .from(index),
                profile: context.instrument?.profile,
            )
            guard playAlong.play(timeline, voices: playAlongVoices(model), loops: looping) else {
                return false
            }
            let now = context.scrollClock.now()
            if !playAlongFollow.resumesScroll, var scroller, scroller.phase(at: now) == .running {
                scroller.pause(at: now)
                self.scroller = scroller
                playAlongFollow.resumesScroll = true
            }
            // The scroll waits for the audio: no wrap from the scroll clock meanwhile.
            loopWrapTask?.cancel()
            loopWrapTask = nil
            loopWrapInstant = nil
            playAlongFollow.pass = 0
            playAlongFollow.target = nil
            metronome.muted = playAlongVoices(model).contains(.click)
            followPlayAlong()
            playAlongFollow.task?.cancel()
            playAlongFollow.task = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: PlayAlongFollow.tick)
                    self?.followPlayAlong()
                }
            }
            return true
        }

        /// Stops play-along (`P` again, a song change, a break, End, `L` off while looping);
        /// auto-scroll returns to how it was.
        func stopPlayAlong() {
            guard let playAlong else { return }
            let wasFollowing = playAlongFollow.task != nil
            playAlong.stop()
            playAlongFollow.task?.cancel()
            playAlongFollow.task = nil
            playAlongFollow.ease = nil
            playAlongFollow.easeTask?.cancel()
            isEasingFollow = false
            playAlongFollow.target = nil
            metronome.muted = false
            guard wasFollowing else { return }
            if playAlongFollow.resumesScroll, var scroller {
                scroller.start(at: context.scrollClock.now())
                self.scroller = scroller
            }
            playAlongFollow.resumesScroll = false
            rescheduleLoopWrap()
        }

        /// One step of following the audio: a loop's wrap counts in again and goes back to
        /// the pass's top; otherwise the line at the playhead is brought to the reading line.
        /// The follow task calls it every 50 ms (tests call it on a scripted clock).
        func followPlayAlong() {
            guard let playAlong, let plan else { return }
            guard playAlong.isPlaying else {
                if playAlongFollow.task != nil {
                    stopPlayAlong()
                }
                return
            }
            let now = context.scrollClock.now()
            let first = playAlong.timeline.passes.lowerBound
            if let pass = playAlong.pass, pass != playAlongFollow.pass {
                // A new pass of the phrase: its count-in bar shows on the pips (R148).
                playAlongFollow.pass = pass
                if pass > 1 || playAlong.countInLength > 0 {
                    metronome.countIn(at: now)
                }
            }
            var shown = first
            var target = StagePasses.jumpOffset(to: first, in: plan)
            if let tick = playAlong.playheadTick(),
               let index = playAlong.timeline.timeline.chord(atTick: tick)
            {
                let chord = playAlong.timeline.timeline.chords[index]
                shown = first + chord.pass
                if let top = StagePasses.lineTop(chord.line, pass: shown, in: plan) {
                    target = StagePasses.offset(readingAt: top, in: plan)
                } else {
                    target = StagePasses.jumpOffset(to: shown, in: plan)
                }
            }
            if pinnedPass != shown {
                pinnedPass = shown
                noteCurrentPass(shown)
            }
            guard let target, abs(target - (playAlongFollow.target ?? -1)) > 0.5,
                  var scroller
            else { return }
            let from = scrollOffset(at: now)
            playAlongFollow.target = target
            scroller.seek(to: target, at: now)
            self.scroller = scroller
            startFollowEase(from: from, at: now)
        }

        /// Eases the scroll from `from` to where the scroller now is over 0.25 s (none with
        /// Reduce Motion).
        private func startFollowEase(from: Double, at now: Date) {
            guard !Self.reducesMotion else { return }
            playAlongFollow.ease = PlayAlongFollow.Ease(from: from, start: now)
            // Frames only for the ease, not for as long as play-along plays.
            isEasingFollow = true
            playAlongFollow.easeTask?.cancel()
            playAlongFollow.easeTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(PlayAlongFollow.easeDuration))
                guard !Task.isCancelled else { return }
                self?.isEasingFollow = false
            }
        }

        /// The scroll at `now` with the follow ease applied (instant with Reduce Motion).
        func followEased(_ offset: Double, at now: Date) -> Double {
            guard let ease = playAlongFollow.ease else { return offset }
            let progress = now.timeIntervalSince(ease.start) / PlayAlongFollow.easeDuration
            guard progress < 1 else { return offset }
            let eased = progress <= 0 ? 0 : progress * progress * (3 - 2 * progress)
            return ease.from + (offset - ease.from) * eased
        }

        private static var reducesMotion: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }

        /// Settings' voices; Walk-ups follows the charts (the bass-note view with walk-ups
        /// on) until it is set.
        func playAlongVoices(_ model: RenderModel) -> Set<VoiceToggle> {
            guard let settings = playAlong?.sound.settings.settings else { return [] }
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
            let charts = model.transform.options.bass?.notes == true
                && context.instrument?.profile.walkUps != .off
            if settings.playAlongWalkUps ?? charts {
                voices.insert(.walkUps)
            }
            return voices
        }

        /// `range` of the song's played passes as play-along voices it: the slot's key and
        /// capo (the stage model's transform), each pass's walk-up into what follows it.
        static func playAlongTimeline(
            song: SongRecord,
            model: RenderModel,
            order: [PlayedPass],
            range: PlayAlongRange,
            profile: InstrumentProfile?,
        ) -> PlayAlongTimeline {
            let units = SongSections.units(of: song.document)
            let prefs = song.sidecar.bass
            let written = SongTimeline.build(
                document: song.document,
                sections: model.sections,
                units: units,
                timing: prefs.timing,
                order: nil,
            )
            // Walk-ups follow the chart's density: none while Off (R170).
            var context = BassLineContext(
                transform: model.transform,
                genre: prefs.genre ?? profile?.genre ?? .pop,
                density: profile?.walkUps ?? .off,
                timeline: written,
            )
            context.apply(prefs, parts: [], units: units, sections: model.sections)
            let arranged = ArrangedSections.build(model.sections, order: order)
            let changes = BassLine.changes(
                arranged.map(\.section),
                origins: arranged.map(\.source),
                context: context,
            )
            return PlayAlongTimeline.make(
                timeline: SongTimeline.build(
                    document: song.document,
                    sections: model.sections,
                    units: units,
                    timing: prefs.timing,
                    order: order,
                ),
                range: range,
                changes: changes,
                transform: model.transform,
                placement: SoundSession.placement(for: model, profile: profile),
            )
        }
    }
#endif
