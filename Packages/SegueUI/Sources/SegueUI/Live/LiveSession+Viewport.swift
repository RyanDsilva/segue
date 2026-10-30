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

        /// The song in a slot as it renders there: sidecar view options with the setlist
        /// overrides applied, no diagrams.
        static func renderModel(_ song: SongRecord, overrides: SetlistOverrides) -> RenderModel {
            var options = song.sidecar.displayPrefs.displayOptions
            options.showDiagrams = false
            let (applied, capo) = overrides.applied(
                to: options,
                songCapo: song.document.metadata.capo,
            )
            return RenderModel(document: song.document, options: applied, capo: capo)
        }

        /// A slot's arrangement checked against its song as loaded (R122); nil for a slot
        /// that plays the full song.
        static func resolution(_ item: ShowItem, song: SongRecord) -> ArrangementResolution? {
            item.arrangement.map {
                ArrangementResolver.resolve($0, units: SongSections.units(of: song.document))
            }
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
            upNextModel = upNextSlot.flatMap { slot in
                slot.song.map { song in
                    Self.arranged(
                        Self.renderModel(song, overrides: slot.item.overrides),
                        Self.resolution(slot.item, song: song),
                    )
                }
            }
            guard let slot = state.current, let song = slot.song else {
                currentModel = nil
                currentArrangement = nil
                plan = nil
                scroller = nil
                laidOutItem = nil
                return
            }
            let model = Self.renderModel(song, overrides: slot.item.overrides)
            currentModel = model
            let resolution = Self.resolution(slot.item, song: song)
            currentArrangement = resolution.map { $0.isOutOfDate ? .outOfDate : .applied }
            recordArrangement(currentArrangement, for: slot.item)
            var order: [PlayedPass]?
            if case let .applied(played, _) = resolution {
                order = played
            }
            guard viewport.width > 0, viewport.height > 0 else { return }
            let prefs = prefs(for: song)
            let notes = [song.sidecar.notes, slot.item.note]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let request = LayoutRequest(
                model: model,
                viewport: viewport,
                minLyricSize: minLyricSize,
                zoom: prefs.zoom,
                collapseRepeats: prefs.collapseRepeats,
                columns: context.settings.settings.columns(for: prefs),
                cues: song.sidecar.cues,
                notes: notes,
                arrangement: order,
            )
            let newPlan = LayoutEngine.plan(request, metrics: StageTextMetrics())
            plan = newPlan
            updateScroller(newPlan, item: slot.item, song: song, prefs: prefs)
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
            let metadata = song.document.metadata
            // An arranged slot scrolls over its own length (nil = unknown: the tempo path),
            // never the full song's `{duration}` (R122); out of date plays the full song.
            let duration = item.arrangement != nil && currentArrangement == .applied
                ? item.arrangement?.length
                : metadata.duration
            return ScrollSpeedModel.speed(ScrollSpeedInput(
                overflow: plan.overflow,
                duration: duration,
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
            scroller?.offset(at: now) ?? 0
        }

        /// The scroll position 0...1 at `now` (0 when the song fits).
        func scrollFraction(at now: Date) -> Double {
            guard let plan, plan.overflow > 0 else { return 0 }
            return min(1, max(0, scrollOffset(at: now) / plan.overflow))
        }

        var isAutoScrolling: Bool {
            scroller?.phase == .running
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
            self.scroller = scroller
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

        /// Cmd +, Cmd -, Cmd 0: zoom saved per song.
        func zoom(_ direction: Int) {
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

        func toggleCollapseRepeats() {
            updatePrefs { $0.collapseRepeats.toggle() }
            if let prefs = currentPrefs {
                flash(prefs.collapseRepeats ? "Repeats collapsed" : "Repeats in full")
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
#endif
