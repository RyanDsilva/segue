#if os(macOS)
    import Editing
    import Foundation
    import Library
    import LiveLayout
    import Setlists
    import Shows

    /// Layout, scroll and zoom of the current song.
    extension LiveSession {
        /// The zoom range Cmd +/- steps through (the engine never goes below the minimum
        /// lyric size whatever the zoom).
        static let zoomRange = 0.5 ... 3.0
        static let zoomStep = 1.1

        /// The body area changed size (window, screen change).
        func setViewport(_ size: LayoutSize) {
            guard size != viewport else { return }
            viewport = size
            relayout()
        }

        /// The current song's live memory: this run's changes, else its sidecar.
        func prefs(for song: SongRecord) -> LivePrefs {
            prefsCache[song.id] ?? song.sidecar.live
        }

        var currentPrefs: LivePrefs? {
            state.current?.song.map(prefs(for:))
        }

        /// `model` with its sections in the arranged order (the up-next line reads the first
        /// line actually played); the full song when there is no applicable arrangement.
        static func arranged(_ model: RenderModel, _ resolution: ArrangementResolution?)
            -> RenderModel
        {
            guard case let .applied(order, _) = resolution else { return model }
            var arranged = model
            arranged.sections = ArrangedSections.build(model.sections, order: order).map(\.section)
            return arranged
        }

        /// Recomputes the plan (and, for a new item, the scroller) from the current state.
        func relayout() {
            let singer = singerView
            upNextModel = upNextRenderModel(singer: singer)
            guard let slot = state.current, let song = slot.song else {
                currentModel = nil
                currentTimeline = nil
                currentPlayedTime = nil
                shownPass = nil
                currentArrangement = nil
                plan = nil
                scroller = nil
                laidOutItem = nil
                return
            }
            let prefs = prefs(for: song)
            let (request, resolution) = StageRequest.make(
                song: song,
                slot: StageSlot(slot.item),
                prefs: prefs,
                settings: context.settings.settings,
                minLyricSize: minLyricSize,
                viewport: viewport,
                bass: bassView,
                singer: singer,
            )
            planView = request.view
            if request.view == .singer {
                singerViewUsed = true
            }
            currentModel = request.model
            currentTimeline = SongTimeline.build(
                document: song.document,
                sections: request.model.sections,
                units: SongSections.units(of: song.document),
                timing: song.sidecar.bass.timing,
                order: nil,
            )
            currentArrangement = resolution.map { $0.isOutOfDate ? .outOfDate : .applied }
            recordArrangement(currentArrangement, for: slot.item)
            guard viewport.width > 0, viewport.height > 0 else { return }
            let newPlan = LayoutEngine.plan(request, metrics: StageTextMetrics())
            plan = newPlan
            updateScroller(newPlan, item: slot.item, song: song, prefs: prefs)
            rescheduleLoopWrap()
            recordBassNeckShown()
            noteCurrentPass(currentPass(at: context.scrollClock.now()))
        }

        /// The item's time from its played passes (the arrangement only when it applies, else
        /// the full song, R122), built once per song version and arrangement, not per layout.
        private func notePlayedTime(_ song: SongRecord, item: ShowItem) {
            let arrangement = currentArrangement == .applied ? item.arrangement : nil
            let key = PlayedTimeKey(
                item: item.itemId,
                source: song.source,
                arrangement: arrangement,
            )
            if playedTimeKey != key || currentPlayedTime == nil {
                playedTimeKey = key
                currentPlayedTime = SlotTimes.slot(song, arrangement: arrangement)
            }
        }

        /// Records once per item what the stage did with its arrangement (the gig log says
        /// what was played). A failed write is retried with the next action's write.
        private func recordArrangement(_ state: ArrangementState?, for item: ShowItem) {
            guard let state, item.arrangementState == nil,
                  recordedArrangements.insert(item.itemId).inserted
            else { return }
            let controller = context.controller
            Task { try? await controller.recordArrangementState(state, for: item.itemId) }
        }

        /// A new item gets a fresh scroller (restoring a resumed position, auto-starting when
        /// the song asks); the same item keeps its position through a re-layout.
        private func updateScroller(
            _ newPlan: LayoutPlan,
            item slot: ShowItem,
            song: SongRecord,
            prefs: LivePrefs,
        ) {
            let item = slot.itemId
            let now = context.scrollClock.now()
            let speed = scrollSpeed(newPlan, song: song, item: slot, prefs: prefs)
            if laidOutItem != item || scroller == nil {
                laidOutItem = item
                // A new song: the current pass follows its scroll and any loop (and Rehearsal
                // play-along) ends.
                stopPlayAlong()
                clearPinnedPass()
                stopLoop()
                var fresh = AutoScroller(speed: speed, overflow: newPlan.overflow)
                if let fraction = pendingFraction {
                    pendingFraction = nil
                    fresh.seek(to: fraction * newPlan.overflow, at: now)
                }
                if landsAtBottom {
                    // Page Up from the top of a song: its predecessor opens at the bottom.
                    fresh.seek(to: newPlan.overflow, at: now)
                }
                landsAtBottom = false
                if prefs.autoStartScroll, arrivedByAdvance, newPlan.needsScroll {
                    fresh.start(at: now)
                }
                arrivedByAdvance = false
                reportedFraction = nil
                scroller = fresh
            } else if var scroller {
                // No new item (Page Up on the first song): nothing to land on.
                landsAtBottom = false
                scroller.setOverflow(newPlan.overflow, at: now)
                if scroller.speed != speed {
                    scroller.setSpeed(speed, at: now)
                }
                self.scroller = scroller
            }
        }

        private func scrollSpeed(
            _ plan: LayoutPlan,
            song: SongRecord,
            item: ShowItem,
            prefs: LivePrefs,
        ) -> ScrollSpeed {
            notePlayedTime(song, item: item)
            let metadata = song.document.metadata
            // The item's time from its played passes (P8-8 5.6, R173): tempo x played bars;
            // without one, a chordless song with a tempo uses the per-line estimate and a
            // song with no tempo starts at the default speed ([ and ] adjust it).
            return ScrollSpeedModel.speed(ScrollSpeedInput(
                overflow: plan.overflow,
                playedTime: currentPlayedTime?.seconds,
                tempo: metadata.tempo,
                time: metadata.time,
                lineCount: plan.lineCount,
                factor: prefs.scrollSpeedFactor,
            ))
        }

        /// The item the footer names (the engine's up-next item; a queued request wins).
        var upNextSlot: ShowSlot? {
            if case let .item(slot) = state.upNext {
                return slot
            }
            return nil
        }

        // MARK: Scroll

        /// The scroll offset in points at `now`.
        func scrollOffset(at now: Date) -> Double {
            followEased(scroller?.offset(at: now) ?? 0, at: now)
        }

        /// The scroll position 0...1 at `now` (0 when the song fits).
        func scrollFraction(at now: Date) -> Double {
            guard let plan, plan.overflow > 0 else { return 0 }
            return min(1, max(0, scrollOffset(at: now) / plan.overflow))
        }

        /// Whether the stage scroll moves by itself (auto-scroll, or Rehearsal play-along's
        /// short follow ease), so the views redraw every frame.
        var isAutoScrolling: Bool {
            scroller?.phase == .running || isEasingFollow
        }

        /// The footer's auto-scroll state; nil when the song fits (nothing to scroll).
        func scrollStatus(at now: Date) -> String? {
            guard let plan, plan.needsScroll, let scroller else { return nil }
            return switch scroller.phase {
            case .idle: "Scroll ready (A)"
            case .running:
                scroller.offset(at: now) >= plan.overflow - 0.5 ? "Scroll at end" : "Scrolling"
            case .paused: "Scroll paused"
            case .finished: "Scroll at end"
            }
        }

        func pageDown() {
            if pageWrapsLoop() {
                return
            }
            guard let plan, plan.needsScroll else { return }
            let now = context.scrollClock.now()
            let offset = scrollOffset(at: now)
            // Open question 3: at the bottom, PgDn does nothing (never advances).
            guard let stop = plan.pageStops.first(where: { $0 > offset + 0.5 }) else { return }
            seek(min(stop, plan.overflow), at: now)
        }

        func pageUp() {
            guard let plan, plan.needsScroll else { return }
            let now = context.scrollClock.now()
            let offset = scrollOffset(at: now)
            let stop = plan.pageStops.last { $0 < offset - 0.5 } ?? 0
            seek(stop, at: now)
        }

        /// Page-turner Page Down (R45): pages down, and at the song's bottom (or when it
        /// fits) moves to the next song, at its top. Ignored while a song change is in
        /// flight (a double tap never skips a song), and at the bottom of the last song it
        /// stays put with a "Last song" hint: only an explicit Next ends the chart (R154).
        func pageForward() {
            guard songChangesInFlight == 0 else { return }
            // A loop on (rehearsal): a step past the looped pass wraps instead (R148).
            if pageWrapsLoop() {
                return
            }
            let now = context.scrollClock.now()
            if let plan, plan.needsScroll {
                let offset = scrollOffset(at: now)
                if offset < plan.overflow - 0.5 {
                    let stop = plan.pageStops.first { $0 > offset + 0.5 } ?? plan.overflow
                    seek(min(stop, plan.overflow), at: now)
                    return
                }
            }
            if state.current != nil, state.record.breakId == nil, !state.record.hasNextItem {
                flash("Last song")
                return
            }
            perform(.next)
        }

        /// Page-turner Page Up (R45): pages up, and at the song's top moves to the previous
        /// song, at its bottom. Ignored while a song change is in flight (R158 Q1).
        func pageBack() {
            guard songChangesInFlight == 0 else { return }
            let now = context.scrollClock.now()
            if let plan, plan.needsScroll, scrollOffset(at: now) > 0.5 {
                pageUp()
                return
            }
            landsAtBottom = true
            perform(.previous)
        }

        private func seek(_ offset: Double, at now: Date) {
            scroller?.seek(to: offset, at: now)
            clearPinnedPass()
            rescheduleLoopWrap()
            Task { await flushScroll() }
        }

        func toggleAutoScroll() {
            guard let plan, plan.needsScroll, var scroller else {
                notice = "This song fits on screen; there is nothing to scroll."
                return
            }
            let now = context.scrollClock.now()
            // A scroll that reached the bottom is finished, so one press starts it over.
            scroller.settle(at: now)
            switch scroller.phase {
            case .running:
                scroller.pause(at: now)
            case .finished:
                scroller.restart(at: now)
                scroller.start(at: now)
            case .idle, .paused:
                scroller.start(at: now)
            }
            if scroller.phase == .running {
                clearPinnedPass()
            }
            self.scroller = scroller
            rescheduleLoopWrap()
        }

        /// Records a running scroll that reached the bottom as finished, so the display
        /// stops ticking (called on the flush tick).
        func settleScroll() {
            guard var settled = scroller else { return }
            settled.settle(at: context.scrollClock.now())
            if settled != scroller {
                scroller = settled
            }
        }

        func restartScroll() {
            scroller?.restart(at: context.scrollClock.now())
            clearPinnedPass()
            rescheduleLoopWrap()
            Task { await flushScroll() }
        }

        // MARK: Per-song memory

        /// `[` / `]`: scroll speed factor, saved per song.
        func nudgeScrollSpeed(faster: Bool) {
            updatePrefs { prefs in
                let step = ScrollSpeedModel.nudgeStep
                let factor = faster ? prefs.scrollSpeedFactor * step
                    : prefs.scrollSpeedFactor / step
                prefs.scrollSpeedFactor = min(4, max(0.25, (factor * 1000).rounded() / 1000))
            }
        }

        /// Cmd +, Cmd -, Cmd 0: zoom saved per song; in singer view the one singer zoom.
        func zoom(_ direction: Int) {
            if singerView {
                zoomSinger(direction)
                return
            }
            updatePrefs { prefs in
                let zoom = switch direction {
                case 0: 1.0
                case let step where step > 0: prefs.zoom * Self.zoomStep
                default: prefs.zoom / Self.zoomStep
                }
                let clamped = min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, zoom))
                prefs.zoom = (clamped * 100).rounded() / 100
            }
            if let prefs = currentPrefs {
                flash("Zoom \(Int((prefs.zoom * 100).rounded()))%")
            }
        }

        /// C: Auto -> 1 -> 2 -> 3 -> Auto for the current song, saved to its sidecar.
        func cycleColumns() {
            updatePrefs { prefs in
                prefs.columns = switch prefs.columns {
                case nil: 1
                case let count? where count < 3: count + 1
                default: nil
                }
            }
            if let prefs = currentPrefs {
                flash(Self.columnsLabel(
                    prefs.columns,
                    default: context.settings.settings.defaultColumns,
                ))
            }
        }

        /// "Columns: Auto", "Columns: 2", or "Columns: default (2)" when the song follows a
        /// fixed Settings > Live default.
        static func columnsLabel(_ columns: Int?, default fallback: Int? = nil) -> String {
            if let columns {
                return "Columns: \(columns)"
            }
            return fallback.map { "Columns: default (\($0))" } ?? "Columns: Auto"
        }

        /// Shows `text` in the stage's mode indicator for 1.5 s.
        func flash(_ text: String) {
            indicator = text
            indicatorTask?.cancel()
            indicatorTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1500))
                guard !Task.isCancelled else { return }
                self?.indicator = nil
            }
        }

        /// Changes the current song's live memory, re-lays out and saves it to the sidecar.
        /// A read-only song keeps the change for this run only.
        private func updatePrefs(_ change: (inout LivePrefs) -> Void) {
            guard let song = state.current?.song else { return }
            var prefs = prefs(for: song)
            let before = prefs
            change(&prefs)
            guard prefs != before else { return }
            prefsCache[song.id] = prefs
            relayout()
            savePrefs(prefs, of: song.id)
        }

        /// Queues `prefs` for the sidecar. Saves run one at a time and always write the
        /// latest value, so quick presses can never land out of order.
        func savePrefs(_ prefs: LivePrefs, of song: SongID) {
            // Saves that failed earlier go again with this one.
            unsavedPrefs.merge(failedPrefs) { queued, _ in queued }
            failedPrefs = [:]
            unsavedPrefs[song] = prefs
            guard prefsWriter == nil else { return }
            prefsWriter = Task { [weak self] in
                await self?.drainPrefs()
            }
        }

        /// Writes queued live memory until none is left.
        private func drainPrefs() async {
            defer { prefsWriter = nil }
            let library = context.library
            while let (song, prefs) = unsavedPrefs.first {
                unsavedPrefs[song] = nil
                do {
                    _ = try await library.updateLivePrefs(id: song, prefs)
                    problems[.songPrefs] = nil
                } catch LibraryError.readOnly, LibraryError.songNotFound {
                    notice = "Kept for this show only: this song cannot be changed."
                } catch {
                    failedPrefs[song] = prefs
                    let reason = UserMessage.describe(error)
                    problems[.songPrefs] = "Song settings not saved (\(reason)). "
                        + "They apply for this show; Segue saves them with your next change."
                }
            }
        }

        /// Waits until queued live memory is written (tests, show end).
        func prefsSaved() async {
            while let writer = prefsWriter {
                await writer.value
            }
        }
    }

    /// The item, song version and applied arrangement a played time was computed for.
    struct PlayedTimeKey: Equatable {
        var item: ShowItemID
        var source: String
        var arrangement: SlotArrangement?
    }
#endif
