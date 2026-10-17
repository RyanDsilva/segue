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

        /// Recomputes the plan (and, for a new item, the scroller) from the current state.
        func relayout() {
            upNextModel = upNextSlot.flatMap { slot in
                slot.song.map { Self.renderModel($0, overrides: slot.item.overrides) }
            }
            guard let slot = state.current, let song = slot.song else {
                currentModel = nil
                plan = nil
                scroller = nil
                laidOutItem = nil
                return
            }
            let model = Self.renderModel(song, overrides: slot.item.overrides)
            currentModel = model
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
                columns: prefs.columns,
                cues: song.sidecar.cues,
                notes: notes,
            )
            let newPlan = LayoutEngine.plan(request, metrics: StageTextMetrics())
            plan = newPlan
            updateScroller(newPlan, item: slot.item.itemId, song: song, prefs: prefs)
        }

        /// A new item gets a fresh scroller (restoring a resumed position, auto-starting when
        /// the song asks); the same item keeps its position through a re-layout.
        private func updateScroller(
            _ newPlan: LayoutPlan,
            item: ShowItemID,
            song: SongRecord,
            prefs: LivePrefs,
        ) {
            let now = context.scrollClock.now()
            let speed = scrollSpeed(newPlan, song: song, prefs: prefs)
            if laidOutItem != item || scroller == nil {
                laidOutItem = item
                var fresh = AutoScroller(speed: speed, overflow: newPlan.overflow)
                if let fraction = pendingFraction {
                    pendingFraction = nil
                    fresh.seek(to: fraction * newPlan.overflow, at: now)
                }
                if prefs.autoStartScroll, arrivedByAdvance, newPlan.needsScroll {
                    fresh.start(at: now)
                }
                arrivedByAdvance = false
                reportedFraction = nil
                scroller = fresh
            } else if var scroller {
                scroller.setOverflow(newPlan.overflow, at: now)
                if scroller.speed != speed {
                    scroller.setSpeed(speed, at: now)
                }
                self.scroller = scroller
            }
        }

        private func scrollSpeed(_ plan: LayoutPlan, song: SongRecord, prefs: LivePrefs)
            -> ScrollSpeed
        {
            let metadata = song.document.metadata
            return ScrollSpeedModel.speed(ScrollSpeedInput(
                overflow: plan.overflow,
                duration: metadata.duration,
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
                flash(Self.columnsLabel(prefs.columns))
            }
        }

        /// "Columns: Auto", "Columns: 2".
        static func columnsLabel(_ columns: Int?) -> String {
            "Columns: " + (columns.map(String.init) ?? "Auto")
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
            let library = context.library
            Task { [weak self] in
                do {
                    _ = try await library.updateLivePrefs(id: song.id, prefs)
                } catch {
                    self?.notice = "Kept for this show only: \(UserMessage.describe(error))"
                }
            }
        }
    }
#endif
