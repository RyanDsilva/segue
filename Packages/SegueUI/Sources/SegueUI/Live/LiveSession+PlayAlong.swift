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
        /// In a medley plan, the plan index of the starting member's first pass: the
        /// timeline's pass numbers start there (P9-3 9.8).
        var passOffset = 0
        /// The member with no tempo the medley's play-along stops before (its title).
        var stopsAt: String?
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
            // The current song's saved fills play where they apply (R168 Q4).
            playAlong?.fillProvider = { [weak self] timeline in
                self?.playAlongFills()?(timeline) ?? []
            }
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
                  let current = currentPass(at: context.scrollClock.now())
            else {
                flash("Nothing to play along with")
                return
            }
            // No tempo, no play-along (R191, R192): a song or medley member without one is
            // never played at a default tempo.
            if let title = medleyMemberWithoutTempo(at: current) {
                flash("No tempo for \(title): add one to play along")
                return
            }
            if !isInMedley, let song = playAlongSong, song.song.document.metadata.tempo == nil,
               !songHasTempo(song)
            {
                flash(PlayAlong.noTempoHint)
                return
            }
            guard startPlayAlong(from: current) else {
                flash("Nothing to play along with")
                return
            }
        }

        /// Whether `song`'s played passes carry a `{tempo}` (one written part way counts).
        private func songHasTempo(_ song: PlayAlongSong) -> Bool {
            SongTimeline.build(
                document: song.song.document,
                sections: song.model.sections,
                units: SongSections.units(of: song.song.document),
                timing: song.song.sidecar.bass.timing,
                order: song.order,
            ).chords.contains { $0.tempo != nil }
        }

        /// The current slot's song, its stage model and its played passes.
        struct PlayAlongSong {
            var song: SongRecord
            var model: RenderModel
            /// As the stage laid them out (P8-2): the slot's arrangement, else the full song.
            var order: [PlayedPass]
        }

        private var playAlongSong: PlayAlongSong? {
            guard let slot = state.current, let song = slot.song, let model = currentModel
            else { return nil }
            var order = ArrangementResolver.fullSong(SongSections.units(of: song.document))
            if case let .applied(passes, _) = StageRequest.resolution(
                slot.item.arrangement,
                song: song,
            ) {
                order = passes
            }
            return PlayAlongSong(song: song, model: model, order: order)
        }

        /// The current song's saved fills, resolved for its played passes.
        func playAlongFills() -> PlayAlongFills? {
            guard let current = playAlongSong else { return nil }
            return Self.playAlongFills(
                song: current.song,
                model: current.model,
                order: current.order,
                profile: context.instrument?.profile,
            )
        }

        /// What one press of `P` plays: the timeline, the model whose voices it uses, where
        /// its passes sit in the plan, and (a medley) its fills and where it stops early.
        struct PreparedPlayAlong {
            var timeline: PlayAlongTimeline
            var model: RenderModel
            var passOffset = 0
            /// Nil: the song's fills come from `fillProvider`.
            var fills: [PlayAlongFill]?
            var stopsAt: String?
        }

        /// The current song's played passes from shown pass `index` (or that pass alone when
        /// it loops).
        private func songPlayAlong(from index: Int, looping: Bool) -> PreparedPlayAlong? {
            guard let current = playAlongSong, current.order.indices.contains(index) else {
                return nil
            }
            return PreparedPlayAlong(
                timeline: Self.playAlongTimeline(
                    song: current.song,
                    model: current.model,
                    order: current.order,
                    range: looping ? .section(index) : .from(index),
                    profile: context.instrument?.profile,
                ),
                model: current.model,
            )
        }

        /// Plays from shown pass `index`: the looped pass over and over when it is the one
        /// looping, else to the end of the song (in a medley, on through the members, P9-3
        /// 9.8).
        @discardableResult
        func startPlayAlong(from planIndex: Int) -> Bool {
            let looping = loopPass == planIndex
            guard let playAlong,
                  let prepared = isInMedley
                  ? medleyPlayAlong(from: planIndex, looping: looping)
                  : songPlayAlong(from: planIndex, looping: looping),
                  playAlong.play(
                      prepared.timeline,
                      voices: playAlongVoices(prepared.model),
                      loops: looping,
                      fills: prepared.fills,
                  )
            else { return false }
            playAlongFollow.passOffset = prepared.passOffset
            playAlongFollow.stopsAt = prepared.stopsAt
            let model = prepared.model
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
            playAlongFollow.stopsAt = nil
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
                    let stopsAt = playAlongFollow.stopsAt
                    stopPlayAlong()
                    if let stopsAt {
                        // A medley member with no tempo: the audio ended at its header.
                        flash("No tempo for \(stopsAt): play-along stops here")
                    }
                }
                return
            }
            let now = context.scrollClock.now()
            let first = playAlong.timeline.passes.lowerBound + playAlongFollow.passOffset
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
            let context = playAlongWalkUps(song: song, model: model, profile: profile)
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
                    timing: song.sidecar.bass.timing,
                    order: order,
                ),
                range: range,
                changes: changes,
                transform: model.transform,
                placement: SoundSession.placement(for: model, profile: profile),
            )
        }

        /// The walk-ups play-along voices for the song as `model` shows it: the chart's
        /// density (none while Off, R170), its picks, and its fills (a change a saved fill
        /// covers in its pass plays the fill instead, P8-7 section 13).
        static func playAlongWalkUps(
            song: SongRecord,
            model: RenderModel,
            profile: InstrumentProfile?,
        ) -> BassLineContext {
            let units = SongSections.units(of: song.document)
            let prefs = song.sidecar.bass
            var context = BassLineContext(
                transform: model.transform,
                genre: prefs.genre ?? profile?.genre ?? .pop,
                density: profile?.walkUps ?? .off,
                timeline: SongTimeline.build(
                    document: song.document,
                    sections: model.sections,
                    units: units,
                    timing: prefs.timing,
                    order: nil,
                ),
            )
            context.apply(
                prefs,
                parts: song.sidecar.parts,
                units: units,
                sections: model.sections,
            )
            return context
        }

        /// The song's saved fills for play-along in the played `order`: resolved against the
        /// written song, played where a pass plays them (the timeline in `order` counts the
        /// plays for "Last time").
        static func playAlongFills(
            song: SongRecord,
            model: RenderModel,
            order: [PlayedPass],
            profile: InstrumentProfile?,
        ) -> PlayAlongFills {
            let units = SongSections.units(of: song.document)
            let timing = song.sidecar.bass.timing
            let written = SongTimeline.build(
                document: song.document,
                sections: model.sections,
                units: units,
                timing: timing,
                order: nil,
            )
            return PlayAlongFills(
                parts: song.sidecar.parts.isEmpty ? .empty : PartAnchors.resolve(
                    song.sidecar.parts,
                    timeline: written,
                    units: units,
                    sections: model.sections,
                ),
                song: SongTimeline.build(
                    document: song.document,
                    sections: model.sections,
                    units: units,
                    timing: timing,
                    order: order,
                ),
                transform: model.transform,
                placement: SoundSession.placement(for: model, profile: profile),
            )
        }
    }
#endif
