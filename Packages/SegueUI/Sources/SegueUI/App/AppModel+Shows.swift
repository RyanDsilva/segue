#if os(macOS)
    import AppKit
    import Foundation
    import Library
    import Services
    import Setlists
    import Shows
    import Support

    /// The phase 2 show lifecycle (frozen in docs/phases/2-interfaces.md, unit C): the launch
    /// check, start (pre-show checklist, Shortcuts), resume, end and the reorder review.
    public extension AppModel {
        /// After a library opens: loads its shows, auto-closes stale ones into the gig log
        /// (queuing their reviews) and sets `pendingResume`.
        func runShowLaunchCheck() async {
            guard let session else { return }
            let shows = session.stores.shows
            do {
                let issues = try await shows.load(root: session.root)
                if let first = issues.first {
                    session.library.errorMessage = issues.count == 1
                        ? "Segue could not read the show “\(first.relativePath)” "
                        + "(\(first.message))."
                        : "Segue could not read \(issues.count) show files, e.g. "
                        + "“\(first.relativePath)” (\(first.message))."
                }
                let check = try await shows.launchCheck()
                for ending in check.autoClosed {
                    recordShowEnded(
                        ending.record,
                        autoScrollUsed: false,
                        endedBy: .closedOnRelaunch,
                    )
                }
                await reloadPendingReviews()
                pendingResume = check.resumable
                if !check.autoClosed.isEmpty {
                    await session.library.reload()
                    // Gig Mode was likely left on by the run that never ended.
                    if let kind = check.autoClosed.map(\.record.kind).first(where: runsShortcuts) {
                        await runEndShortcut(kind: kind)
                    }
                }
            } catch {
                session.library.errorMessage = "Segue could not read the shows in this library "
                    + "(\(UserMessage.describe(error)))."
            }
        }

        /// "Start show" / "Rehearse" in the setlist builder: refreshes the library, leaves out
        /// entries whose song is gone (listed in the pre-show checklist), runs the start
        /// Shortcut (gig, or a rehearsal when Settings allows), shows the checklist, then
        /// presents the stage. Returns false when it did not start.
        @discardableResult
        func startShow(_ setlist: Setlist, kind: ShowKind) async -> Bool {
            guard let session, live == nil, !isStartingShow, pendingResume == nil else {
                return false
            }
            isStartingShow = true
            defer { isStartingShow = false }
            // The stage reads the files: save the open editor first. If that fails the
            // show still starts with the last saved version; the editor keeps its bar.
            await session.library.flushEditor()
            await session.library.refresh()
            let missing = setlist.entries.enumerated().filter { _, entry in
                session.library.song(id: entry.songId) == nil
            }
            guard missing.count < setlist.entries.count else {
                startFailure = setlist.entries.isEmpty
                    ? "“\(setlist.name)” has no songs yet."
                    : "None of the songs in “\(setlist.name)” can be found in the library folder."
                return false
            }
            let checklist = await PreShowChecklist(
                setlistName: setlist.name,
                kind: kind,
                missingPositions: missing.map { $0.offset + 1 },
                performableCount: setlist.entries.count - missing.count,
                focus: runStartShortcut(kind: kind),
                settings: liveSettings,
                power: dependencies.live.power,
                clock: dependencies.live.scrollClock,
            )
            checklist.retryFocus = { [weak self] in
                await self?.runStartShortcut(kind: kind) ?? .notRun
            }
            guard await confirm(checklist) else { return false }
            let omitting = Set(missing.map(\.element.itemId))
            do {
                let controller = try await ShowController.start(
                    setlist: setlist,
                    kind: kind,
                    omitting: omitting,
                    environment: showEnvironment(
                        session,
                        kind: kind,
                        runId: session.stores.ids.next(),
                        setlistName: setlist.name,
                    ),
                )
                await presentStage(controller, kind: kind, session: session, resumed: false)
                return true
            } catch {
                recordError(.showStartFailed, error)
                startFailure = "The show could not start (\(UserMessage.describe(error)))."
                return false
            }
        }

        /// "Resume" in the resume prompt: back on stage at the same song and scroll position.
        @discardableResult
        func resumePendingShow() async -> Bool {
            guard let record = pendingResume, let session, live == nil, !isStartingShow else {
                return false
            }
            isStartingShow = true
            defer { isStartingShow = false }
            pendingResume = nil
            do {
                let controller = try await ShowController.resume(
                    record,
                    environment: showEnvironment(
                        session,
                        kind: record.kind,
                        runId: record.id.ulid,
                        setlistName: record.setlistName,
                    ),
                )
                // Gig Mode may have ended with the crash; the start Shortcut is idempotent.
                _ = await runStartShortcut(kind: record.kind)
                await presentStage(controller, kind: record.kind, session: session, resumed: true)
                return true
            } catch {
                recordError(.showResumeFailed, error)
                startFailure = "The show could not be resumed (\(UserMessage.describe(error))). "
                    + "It stays in the shows folder and closes into the gig log after 12 hours."
                return false
            }
        }

        /// "End Show" in the resume prompt: closes it into the gig log now (its review is
        /// queued). Nothing is discarded.
        func endPendingShow() async {
            guard let record = pendingResume, let session else { return }
            pendingResume = nil
            do {
                let controller = try await ShowController.resume(
                    record,
                    environment: showEnvironment(
                        session,
                        kind: record.kind,
                        runId: record.id.ulid,
                        setlistName: record.setlistName,
                    ),
                )
                let ending = try await controller.end()
                recordShowEnded(ending.record, autoScrollUsed: false, endedBy: .closedOnRelaunch)
                countCompletedShow(kind: record.kind, quitsAfterEnding: false)
                await reloadPendingReviews()
                await session.library.reload()
            } catch {
                session.library.errorMessage = "The show could not be ended "
                    + "(\(UserMessage.describe(error)))."
            }
            // Gig Mode is likely still on from the interrupted show.
            await runEndShortcut(kind: record.kind)
        }

        /// Resolves the first pending review. Save merges the played order into the setlist
        /// as it is now (`ReorderDiff.entries(mergingInto:including:)`), so edits made
        /// during the show are kept; Discard leaves the setlist file untouched. The answer
        /// is stored on the show, so the review is offered until it is answered (a failed
        /// save keeps it pending, with the reason in the sheet).
        func resolveReorderReview(save: Bool, including inserted: Set<ShowItemID>) async {
            guard let diff = pendingReorderReviews.first, let session else { return }
            let blocked = reviewSaveBlockers[diff.setlistId] != nil
            if save, !blocked {
                do {
                    let current = await session.stores.setlists.setlist(id: diff.setlistId)
                    // Undoable in the main window afterwards ("Save Show Order").
                    try await session.setlists.saveShowOrder(
                        diff.entries(
                            mergingInto: current?.entries ?? diff.planned,
                            including: inserted,
                        ),
                        in: diff.setlistId,
                    )
                } catch {
                    reviewSaveFailure = "“\(diff.setlistName)” was not updated "
                        + "(\(UserMessage.describe(error))). Try again, or Discard to keep the "
                        + "setlist as it is."
                    return
                }
            }
            reviewSaveFailure = nil
            if let showId = diff.showId {
                do {
                    try await session.stores.shows.resolveReview(
                        of: showId,
                        saved: save && !blocked,
                    )
                } catch {
                    session.library.errorMessage = "Segue could not record your answer to the "
                        + "review of “\(diff.setlistName)” (\(UserMessage.describe(error))). "
                        + "It may be offered again."
                }
            }
            pendingReorderReviews.removeFirst()
            if !pendingReorderReviews.contains(where: { $0.setlistId == diff.setlistId }) {
                reviewSaveBlockers[diff.setlistId] = nil
            }
        }

        /// Whether the review's setlist was edited after the show started (the sheet warns
        /// that Save merges into the edited setlist).
        func setlistChangedSinceShow(_ diff: ReorderDiff) -> Bool {
            guard let current = session?.setlists.setlist(diff.setlistId) else { return false }
            return diff.setlistChanged(current: current.entries)
        }

        /// Offers every stored review still unanswered (show end, auto-closed shows, and
        /// reviews left open when Segue quit), first checking each setlist can still be saved
        /// (it may have been deleted or become read-only during the show).
        func reloadPendingReviews() async {
            guard let session else { return }
            let diffs = await session.stores.shows.pendingReviews()
            var blockers: [SetlistID: String] = [:]
            for diff in diffs where blockers[diff.setlistId] == nil {
                if let blocker = await session.stores.setlists.saveBlocker(for: diff.setlistId) {
                    blockers[diff.setlistId] = Self.saveBlockedReason(
                        blocker,
                        name: diff.setlistName,
                    )
                }
            }
            reviewSaveBlockers = blockers
            pendingReorderReviews = diffs
        }

        /// The review's explanation when Save is disabled.
        static func saveBlockedReason(_ blocker: SetlistError, name: String) -> String {
            let reason = switch blocker {
            case .readOnly:
                "“\(name)” is read-only now (it was saved by a newer version of Segue)"
            case .invalidOffsets, .notLoaded, .setlistNotFound:
                "“\(name)” was deleted during the show"
            }
            return reason + ", so the played order cannot be saved to it. The show is in the "
                + "gig log as played; Discard closes this."
        }

        /// Closes the "could not start" alert.
        func dismissStartFailure() {
            startFailure = nil
        }
    }

    // MARK: - Internals

    extension AppModel {
        func resetShowState() {
            pendingResume = nil
            pendingReorderReviews = []
            reviewSaveBlockers = [:]
            reviewSaveFailure = nil
            preShow?.answer(false)
            preShow = nil
            startFailure = nil
        }

        func showEnvironment(
            _ session: LibrarySession,
            kind: ShowKind,
            runId: ULID,
            setlistName: String,
        ) -> ShowEnvironment {
            let stores = session.stores
            let durations: (any DurationSampleSink)? = kind == .rehearsal
                ? RehearsalTimingStore(
                    fileSystem: stores.fileSystem,
                    root: session.root,
                    runId: runId,
                    setlistName: setlistName,
                )
                : nil
            return ShowEnvironment(
                store: stores.shows,
                songs: stores.library,
                clock: stores.clock,
                ids: stores.ids,
                durations: durations,
            )
        }

        /// Builds the stage session for a started or resumed run and presents it.
        private func presentStage(
            _ controller: ShowController,
            kind: ShowKind,
            session: LibrarySession,
            resumed: Bool,
        )
            async
        {
            SegueTips.donate(SegueTips.showStarted)
            let state = await controller.state
            recordShowStarted(state, kind: kind, resumed: resumed)
            let live = LiveSession(state: state, kind: kind, context: LiveSession.Context(
                controller: controller,
                library: session.stores.library,
                bindings: loadBindings(session),
                settings: liveSettings,
                scrollClock: dependencies.live.scrollClock,
                clock: session.stores.clock,
                onEnd: { [weak self] live in await self?.finishRun(live) },
            ))
            live.services = services
            self.live = live
            StageWindowController.shared.present(self)
        }

        /// The key bindings: defaults plus `bindings.json`; a malformed file is reported and
        /// the defaults are used, and a file from a newer Segue is applied as far as this
        /// version understands it (reported).
        private func loadBindings(_ session: LibrarySession) -> InputBindingTable {
            do {
                let loaded = try InputBindingTable.loadReporting(
                    from: dependencies.live.bindingsURL,
                    fileSystem: session.stores.fileSystem,
                )
                if loaded.newerSchema != nil, loaded.skipped > 0 {
                    session.library.errorMessage = "Your key bindings file was saved by a newer "
                        + "version of Segue: \(loaded.skipped) of its bindings are not available "
                        + "in this version, so those keys keep their defaults."
                }
                return loaded.table
            } catch {
                session.library.errorMessage = "Your key bindings file could not be read "
                    + "(\(UserMessage.describe(error))), so the default keys are used."
                return .defaults
            }
        }

        /// After "End Show": ends the run, closes the stage, runs the end Shortcut and queues
        /// the reorder review.
        func finishRun(_ live: LiveSession) async {
            await live.prefsSaved()
            do {
                let ending = try await live.context.controller.end()
                recordShowEnded(
                    ending.record,
                    autoScrollUsed: live.autoScrollUsed,
                    endedBy: live.quitsAfterEnding ? .quit : .endShow,
                )
                countCompletedShow(kind: live.kind, quitsAfterEnding: live.quitsAfterEnding)
            } catch {
                session?.library.errorMessage = "The show could not be closed "
                    + "(\(UserMessage.describe(error))). It will be offered again at next launch."
                await live.context.controller.relinquish()
            }
            StageWindowController.shared.close()
            services.record(LifecycleCrumb.stageExited)
            if self.live === live {
                live.stop()
                self.live = nil
            }
            await runEndShortcut(kind: live.kind)
            await reloadPendingReviews()
            await session?.library.reload()
            runQueuedOpenRequests()
            if live.quitsAfterEnding {
                NSApp.terminate(nil)
            }
        }

        /// Shows the checklist (when it has anything to show) and waits for the answer. A
        /// cancelled start undoes Gig Mode whenever a start request was sent, since Focus
        /// may be on even when its completion was never observed.
        private func confirm(_ checklist: PreShowChecklist) async -> Bool {
            guard checklist.hasContent else { return true }
            preShow = checklist
            checklist.watchPower()
            checklist.watchFocus()
            let start = await withCheckedContinuation { continuation in
                checklist.continuation = continuation
            }
            preShow = nil
            if !start, checklist.focus.requestedName != nil {
                await runEndShortcut(kind: checklist.kind)
            }
            return start
        }

        func runsShortcuts(_ kind: ShowKind) -> Bool {
            kind == .gig || liveSettings.runsShortcutsForRehearsals
        }

        func runStartShortcut(kind: ShowKind) async -> PreShowChecklist.FocusStatus {
            guard runsShortcuts(kind) else { return .notRun }
            return await runShortcut(liveSettings.settings.startShortcut)
        }

        func runEndShortcut(kind: ShowKind) async {
            guard runsShortcuts(kind) else { return }
            _ = await runShortcut(liveSettings.settings.endShortcut)
        }

        /// Runs a Shortcut, then keeps Segue frontmost (the stage if it is up). Observed
        /// completion maps to `.ran`, a failure to `.failed`, and a hand-over to `.running`
        /// (which becomes `.unknown` after `ShortcutTiming.confirmTimeout` unless a
        /// confirmation arrives first). A hand-over is never completion (R18).
        func runShortcut(_ name: String?) async -> PreShowChecklist.FocusStatus {
            guard let name = LiveSettingsStore.shortcutName(name) else { return .notConfigured }
            let outcome = await dependencies.live.shortcuts.run(name)
            let status = PreShowChecklist.FocusStatus(outcome, name: name)
            LiveFocus
                .reassert { StageWindowController.shared.stageWindow ?? LiveFocus.mainWindow() }
            return status
        }
    }
#endif
