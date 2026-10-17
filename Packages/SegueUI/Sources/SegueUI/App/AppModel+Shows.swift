#if os(macOS)
    import Foundation
    import Library
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
                await enqueueReviews(check.autoClosed.compactMap(\.diff))
                pendingResume = check.resumable
                if !check.autoClosed.isEmpty {
                    await session.library.reload()
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
            )
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
                await presentStage(controller, kind: kind, session: session)
                return true
            } catch {
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
                await presentStage(controller, kind: record.kind, session: session)
                return true
            } catch {
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
                await enqueueReviews(ending.diff.map { [$0] } ?? [])
                await session.library.reload()
            } catch {
                session.library.errorMessage = "The show could not be ended "
                    + "(\(UserMessage.describe(error)))."
            }
            // Gig Mode is likely still on from the interrupted show.
            await runEndShortcut(kind: record.kind)
        }

        /// Resolves the first pending review: Save writes `diff.entries(including:)` to the
        /// setlist; Discard leaves the setlist file untouched.
        func resolveReorderReview(save: Bool, including inserted: Set<ShowItemID>) async {
            guard let diff = pendingReorderReviews.first else { return }
            pendingReorderReviews.removeFirst()
            let blocked = reviewSaveBlockers[diff.setlistId] != nil
            if !pendingReorderReviews.contains(where: { $0.setlistId == diff.setlistId }) {
                reviewSaveBlockers[diff.setlistId] = nil
            }
            guard save, !blocked, let session else { return }
            do {
                _ = try await session.stores.setlists.replaceEntries(
                    diff.entries(including: inserted),
                    in: diff.setlistId,
                )
                await session.setlists.reload()
            } catch {
                session.setlists.errorMessage = "“\(diff.setlistName)” was not updated "
                    + "(\(UserMessage.describe(error))). The show is in the gig log as played."
            }
        }

        /// Queues show-end reviews, first checking each setlist can still be saved (it may
        /// have been deleted or become read-only during the show).
        func enqueueReviews(_ diffs: [ReorderDiff]) async {
            guard !diffs.isEmpty else { return }
            let setlists = session?.stores.setlists
            for diff in diffs {
                if let setlists, let blocker = await setlists.saveBlocker(for: diff.setlistId) {
                    reviewSaveBlockers[diff.setlistId] = Self.saveBlockedReason(
                        blocker,
                        name: diff.setlistName,
                    )
                }
                pendingReorderReviews.append(diff)
            }
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
        )
            async
        {
            let state = await controller.state
            let live = LiveSession(state: state, kind: kind, context: LiveSession.Context(
                controller: controller,
                library: session.stores.library,
                bindings: loadBindings(session),
                settings: liveSettings,
                scrollClock: dependencies.live.scrollClock,
                clock: session.stores.clock,
                onEnd: { [weak self] live in await self?.finishRun(live) },
            ))
            self.live = live
            StageWindowController.shared.present(self)
        }

        /// The key bindings: defaults plus `bindings.json`; a malformed file is reported and
        /// the defaults are used.
        private func loadBindings(_ session: LibrarySession) -> InputBindingTable {
            do {
                return try InputBindingTable.load(
                    from: dependencies.live.bindingsURL,
                    fileSystem: session.stores.fileSystem,
                )
            } catch {
                session.library.errorMessage = "Your key bindings file could not be read "
                    + "(\(UserMessage.describe(error))), so the default keys are used."
                return .defaults
            }
        }

        /// After "End Show": ends the run, closes the stage, runs the end Shortcut and queues
        /// the reorder review.
        func finishRun(_ live: LiveSession) async {
            var ending: ShowEnding?
            do {
                ending = try await live.context.controller.end()
            } catch {
                session?.library.errorMessage = "The show could not be closed "
                    + "(\(UserMessage.describe(error))). It will be offered again at next launch."
            }
            StageWindowController.shared.close()
            if self.live === live {
                live.stop()
                self.live = nil
            }
            await runEndShortcut(kind: live.kind)
            await enqueueReviews(ending?.diff.map { [$0] } ?? [])
            await session?.library.reload()
        }

        /// Shows the checklist (when it has anything to show) and waits for the answer. A
        /// cancelled start undoes Gig Mode.
        private func confirm(_ checklist: PreShowChecklist) async -> Bool {
            guard checklist.hasContent else { return true }
            preShow = checklist
            checklist.watchPower()
            let start = await withCheckedContinuation { continuation in
                checklist.continuation = continuation
            }
            preShow = nil
            if !start, case .ran = checklist.focus {
                await runEndShortcut(kind: checklist.kind)
            }
            return start
        }

        private func runsShortcuts(_ kind: ShowKind) -> Bool {
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

        /// Runs a Shortcut, then keeps Segue frontmost (the stage if it is up).
        func runShortcut(_ name: String?) async -> PreShowChecklist.FocusStatus {
            guard let name = LiveSettingsStore.shortcutName(name) else { return .notConfigured }
            let status: PreShowChecklist.FocusStatus
            do {
                try await dependencies.live.shortcuts.run(name)
                status = .ran(name)
            } catch {
                status = .failed(name, message: UserMessage.describe(error))
            }
            LiveFocus
                .reassert { StageWindowController.shared.stageWindow ?? LiveFocus.mainWindow() }
            return status
        }
    }
#endif
