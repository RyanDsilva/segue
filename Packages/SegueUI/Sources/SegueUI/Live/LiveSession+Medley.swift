#if os(macOS)
    import Foundation
    import Library
    import LiveLayout
    import Shows

    /// A medley on stage (P9-3 9.1-9.6, R178): one plan through every member, the current
    /// member following the reading line (committed after a 1 s settle, at once on a key),
    /// and the keys that move member by member. The plan and the scroller are kept while the
    /// current item moves inside the medley.
    extension LiveSession {
        /// Whether the current item is a medley member.
        var isInMedley: Bool {
            !state.medley.isEmpty
        }

        /// The medley's first member with a song: its live memory (zoom, columns, scroll speed)
        /// is the medley's. Nil outside a medley.
        var medleyOpener: SongRecord? {
            guard isInMedley else { return nil }
            return state.medley.first { $0.song != nil }?.song
        }

        /// The current item's index among the plan's segments (members whose song loaded).
        var currentSegment: Int? {
            guard let item = state.current?.item.itemId else { return nil }
            return medleySegments.firstIndex(of: item)
        }

        /// "Medley 2 of 3" for the header chip; nil outside a medley.
        var medleyChipText: String? {
            guard let ref = state.current?.item.medley else { return nil }
            return "Medley \(ref.index + 1) of \(ref.count)"
        }

        /// The chip's VoiceOver label: "Love medley, song 2 of 3".
        var medleyChipLabel: String? {
            guard let ref = state.current?.item.medley else { return nil }
            return "\(ref.displayTitle), song \(ref.index + 1) of \(ref.count)"
        }

        /// The member titles by segment, for the map's groups; empty outside a medley.
        var mapMembers: [String] {
            guard isInMedley else { return [] }
            return medleySegments.compactMap { id in
                state.medley.first { $0.item.itemId == id }
                    .map { $0.song.map(SongSummary.title) ?? $0.item.title }
            }
        }

        /// The member the stage shows at `now`: the one the reading line (or a pinned pass)
        /// is in, else the committed one.
        func shownMember(at now: Date) -> Int? {
            guard isInMedley, let plan else { return nil }
            return MedleyFollow.member(in: plan, offset: scrollOffset(at: now), pinned: pinnedPass)
                ?? currentSegment
        }

        // MARK: Layout

        /// From `relayout()`: lays out the current medley as one plan and returns true, or
        /// forgets the medley layout and returns false outside one.
        func relayoutMedleyIfNeeded(singer: Bool) -> Bool {
            guard isInMedley, let slot = state.current, let song = slot.song else {
                medleySegments = []
                medleyTimelines = []
                return false
            }
            relayoutMedley(slot, song: song, singer: singer)
            return true
        }

        /// Lays out the current medley as one plan.
        func relayoutMedley(_ slot: ShowSlot, song: SongRecord, singer: Bool) {
            let prefs = prefs(for: medleyOpener ?? song)
            let medley = StageRequest.make(
                medley: state.medley,
                prefs: prefs,
                settings: context.settings.settings,
                minLyricSize: minLyricSize,
                viewport: viewport,
                bass: bassView,
                singer: singer,
            )
            planView = medley.request.view
            if singer {
                singerViewUsed = true
            }
            noteMedleyMembers()
            let model = StageRequest.renderModel(
                song,
                overrides: slot.item.overrides,
                bass: bassView,
            )
            currentModel = model
            currentTimeline = SongTimeline.build(
                document: song.document,
                sections: model.sections,
                units: SongSections.units(of: song.document),
                timing: song.sidecar.bass.timing,
                order: nil,
            )
            recordArrangements(medley.resolutions, current: slot.item.itemId)
            guard viewport.width > 0, viewport.height > 0 else { return }
            let newPlan = LayoutEngine.plan(medley.request, metrics: StageTextMetrics())
            plan = newPlan
            updateScroller(
                newPlan,
                item: slot.item,
                song: song,
                prefs: prefs,
                speed: medleySpeed(newPlan, prefs: prefs),
            )
            rescheduleLoopWrap()
            recordBassNeckShown()
            if !medleyRecorded {
                // Once per run that shows a medley (the hub is set before the first layout
                // with a viewport).
                medleyRecorded = true
                services.record(.featureUsed(.medley, .stage))
            }
            noteCurrentPass(currentPass(at: context.scrollClock.now()))
        }

        /// The plan's segments: each member with a song, and its timeline in written order
        /// (what a pass in that member has in effect).
        private func noteMedleyMembers() {
            let members = state.medley.filter { $0.song != nil }
            medleySegments = members.map(\.item.itemId)
            medleyTimelines = members.compactMap { member in
                member.song.map { song in
                    SongTimeline.build(
                        document: song.document,
                        sections: StageRequest.renderModel(
                            song,
                            overrides: member.item.overrides,
                            bass: bassView,
                        ).sections,
                        units: SongSections.units(of: song.document),
                        timing: song.sidecar.bass.timing,
                        order: nil,
                    )
                }
            }
        }

        /// Records each member's arrangement state once (the gig log says what was played)
        /// and the current member's for the header.
        private func recordArrangements(
            _ resolutions: [ShowItemID: ArrangementResolution],
            current: ShowItemID,
        ) {
            for member in state.medley {
                let arrangement: ArrangementState? = resolutions[member.item.itemId]
                    .map { $0.isOutOfDate ? .outOfDate : .applied }
                if member.item.itemId == current {
                    currentArrangement = arrangement
                }
                recordArrangement(arrangement, for: member.item)
            }
        }

        /// Each member's own speed (P9-3 9.7): its stretch of the plan, from its header at the
        /// reading line to the next member's, over its slot time; a member with no time at
        /// the average known speed, none known at the default speed with the add-a-tempo
        /// hint. A plan that does not follow the scroll (it fits or uses columns) moves at one
        /// speed over the medley's time, an unknown member counted at the average.
        private func medleySpeed(_ plan: LayoutPlan, prefs: LivePrefs) -> ScrollSpeed {
            let times = medleySegments.map { id -> TimeInterval? in
                guard let member = state.medley.first(where: { $0.item.itemId == id }),
                      let song = member.song
                else { return nil }
                let applied = StageRequest.resolution(member.item.arrangement, song: song)?
                    .isOutOfDate == false
                return SlotTimes.slot(song, arrangement: applied ? member.item.arrangement : nil)
                    .seconds
            }
            // Nothing known: the default speed and the add-a-tempo hint (R173).
            currentPlayedTime = times.contains { $0 != nil } ? nil : .unknown(.noTempo)
            playedTimeKey = nil
            let members: [MedleyScrollMember]
            if StagePasses.followsScroll(plan) {
                members = times.indices.map { segment in
                    let top = MedleyFollow.headerTop(of: segment, in: plan)
                        ?? plan.passes.first { $0.segment == segment }?.top ?? 0
                    return MedleyScrollMember(
                        fromOffset: StagePasses.offset(readingAt: top, in: plan) ?? 0,
                        seconds: times[segment],
                    )
                }
            } else {
                let known = times.compactMap(\.self)
                let total = known.isEmpty ? nil
                    : known.reduce(0, +) / Double(known.count) * Double(times.count)
                members = [MedleyScrollMember(fromOffset: 0, seconds: total)]
            }
            return ScrollSpeedModel.medley(
                members,
                overflow: plan.overflow,
                factor: prefs.scrollSpeedFactor,
            )
        }

        // MARK: Follow

        /// The flush tick: commits the member the reading line has stayed in for 1 s, or at
        /// once when a jump pinned a pass in another member.
        func followMedley() {
            guard isInMedley, songChangesInFlight == 0, let committed = currentSegment,
                  let shown = shownMember(at: context.scrollClock.now())
            else {
                medleyDwell.reset()
                return
            }
            if pinnedPass != nil, shown != committed {
                medleyDwell.reset()
                commitMember(shown, from: committed)
                return
            }
            if let member = medleyDwell.observe(
                shown: shown,
                committed: committed,
                at: context.scrollClock.now(),
            ) {
                commitMember(member, from: committed)
            }
        }

        /// Moves the show's current item to segment `member`: one forward is Next (the one
        /// left is played), anything else a jump.
        private func commitMember(_ member: Int, from committed: Int) {
            guard medleySegments.indices.contains(member) else { return }
            reportedFraction = nil
            if member == committed + 1 {
                perform(.next)
            } else {
                perform(.jump(medleySegments[member]))
            }
        }

        // MARK: Keys

        /// → / ← / x inside a medley (P9-3 9.5): member by member, seeking to the member's
        /// header; on the first or last member they fall through to today's song moves.
        /// Returns whether the action was handled here.
        func navigateMedley(_ action: ShowAction) -> Bool {
            guard isInMedley, songChangesInFlight == 0, let plan,
                  let index = currentSegment
            else { return false }
            let last = medleySegments.count - 1
            switch action {
            case .next where index < last:
                seekToMember(index + 1, in: plan)
                perform(.next)
            case .skipCurrent where index < last:
                seekToMember(index + 1, in: plan)
                perform(.skipCurrent)
            case .previous:
                let now = context.scrollClock.now()
                let line = StagePasses.readLine(offset: scrollOffset(at: now), plan: plan)
                let top = MedleyFollow.headerTop(of: index, in: plan) ?? 0
                if StagePasses.followsScroll(plan), line > top + StagePasses.jumpMargin + 1 {
                    seekToMember(index, in: plan)
                } else if index > 0 {
                    seekToMember(index - 1, in: plan)
                    perform(.jump(medleySegments[index - 1]))
                } else {
                    return false
                }
            default:
                return false
            }
            medleyDwell.reset()
            return true
        }

        private func seekToMember(_ member: Int, in plan: LayoutPlan) {
            guard let offset = MedleyFollow.seekOffset(to: member, in: plan) else { return }
            let now = context.scrollClock.now()
            scroller?.seek(to: offset, at: now)
            clearPinnedPass()
            rescheduleLoopWrap()
        }

        /// Page Down at the bottom of a medley: every member left is marked played and the
        /// next slot comes up (the follow model may not have committed the last one yet).
        func advancePastMedley() {
            guard isInMedley, let index = currentSegment else {
                perform(.next)
                return
            }
            for _ in index ..< medleySegments.count {
                perform(.next)
            }
        }

        /// "Plays after the medley" (P9-3 8.2): a song inserted, played now or requested
        /// during a medley waits until it ends.
        func noteQueuedAfterMedley(_ action: ShowAction) {
            guard isInMedley else { return }
            let queued = switch action {
            case let .playNow(song):
                !state.medley.contains { $0.item.songId == song && $0.item.state == .pending }
                    && state.current?.item.songId != song
            case .insertNext, .playNextRequest, .playRequest:
                true
            default:
                false
            }
            if queued {
                flash("Plays after the medley")
            }
        }

        // MARK: Footer

        /// The footer inside a medley before its last member: "Next in medley" with the
        /// next member's title, key line and the transition's first line. Nil otherwise.
        var nextInMedley: (slot: ShowSlot, transition: String?)? {
            guard case let .item(next) = state.upNext,
                  let slot = state.current?.item.medley?.slot,
                  next.item.medley?.slot == slot
            else { return nil }
            let transition = next.item.medley?.transition?
                .components(separatedBy: .newlines).first
            return (next, transition)
        }

        /// When the next slot is a medley (not the current one): its title and "Kesariya + 2
        /// more".
        var upNextMedley: (title: String, members: String)? {
            guard case let .item(next) = state.upNext, let ref = next.item.medley,
                  ref.slot != state.current?.item.medley?.slot
            else { return nil }
            let first = next.song.map(SongSummary.title) ?? next.item.title
            let more = ref.count - 1
            return (ref.displayTitle, more > 0 ? "\(first) + \(more) more" : first)
        }

        /// Whether the up-next song is a reprise of a medley member (P9-3 9.10): it is
        /// named "Kesariya (reprise)" so the band is never surprised.
        var upNextIsReprise: Bool {
            guard case let .item(next) = state.upNext, next.item.medley == nil else {
                return false
            }
            return state.record.items.contains { item in
                item.songId == next.item.songId && item.medley != nil
                    && item.itemId != next.item.itemId
            }
        }
    }
#endif
