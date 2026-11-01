#if os(macOS)
    import AppKit
    import Library
    import Services
    import Setlists
    import Shows
    import SwiftUI

    /// Rehearse or play one song straight from the library (R150), and P8-3's "Rehearse this"
    /// with a slot's arrangement (R156). The run is unsaved: no `shows/` file, no gig log
    /// entry, no plays, no timing samples, no pre-show checklist and no Gig Mode Shortcut.
    extension AppModel {
        /// Whether a single-song session can start for `song` (the Library menu, R158 Q5):
        /// a library song is focused, no setlist is shown, nothing is performing, and no show
        /// is starting or waiting to resume.
        func canStartSongSession(_ song: SongID?) -> Bool {
            guard let session, let song, session.library.song(id: song) != nil else {
                return false
            }
            return shownSetlist == nil && canStartSongSessionNow
        }

        /// Nothing is performing, starting or waiting to resume (the song buttons).
        var canStartSongSessionNow: Bool {
            session != nil && live == nil && !isStartingShow && pendingResume == nil
                && !isMainWindowBusy
        }

        /// Starts a one-song run of `song`: `slot` nil plays the full song as written (the
        /// library); P8-3 passes the slot's overrides and draft arrangement and reopens its
        /// sheet in `onEnd`, which is called last. Returns false when it did not start.
        @discardableResult
        func startSongSession(
            _ song: SongID,
            kind: ShowKind,
            slot: StageSlot? = nil,
            onEnd: (@MainActor () -> Void)? = nil,
        ) async -> Bool {
            guard let ids = session?.stores.ids else { return false }
            let entry = SetlistEntry(
                itemId: SetlistItemID(ids.next()),
                songId: song,
                overrides: slot?.overrides ?? SetlistOverrides(),
                note: slot?.note,
                arrangement: slot?.arrangement,
            )
            return await startSlotSession(entry, kind: kind, onEnd: onEnd, from: .library)
        }

        /// Starts an unsaved run of one setlist slot (P9-3 12): a song entry, or a medley
        /// entry played as one plan through its members (Rehearse Medley). Built as an
        /// in-memory one-entry setlist: no checklist, nothing logged. Returns false when it
        /// did not start.
        @discardableResult
        func startSlotSession(
            _ entry: SetlistEntry,
            kind: ShowKind,
            onEnd: (@MainActor () -> Void)? = nil,
            from context: FeatureContext = .builder,
        ) async -> Bool {
            guard let session, live == nil, !isStartingShow, pendingResume == nil else {
                return false
            }
            isStartingShow = true
            defer { isStartingShow = false }
            await session.library.flushEditor()
            await session.library.refresh()
            let records = entry.songIds.compactMap(session.library.song(id:))
            guard let record = records.first else {
                startFailure = entry.isMedley
                    ? "None of this medley's songs can be found in the library folder."
                    : "This song can no longer be found in the library folder."
                return false
            }
            let stores = session.stores
            let setlist = Setlist(
                id: SetlistID(stores.ids.next()),
                name: entry.medley?.displayTitle ?? SongSummary.title(record),
                entries: [entry],
            )
            // Members whose song is gone are left out, as at a show's start.
            let missing = Set(entry.medley?.members
                .filter { session.library.song(id: $0.songId) == nil }
                .map(\.itemId) ?? [])
            do {
                let controller = try await ShowController.start(
                    setlist: setlist,
                    kind: kind,
                    omitting: missing,
                    environment: ShowEnvironment(
                        store: nil,
                        songs: stores.library,
                        clock: stores.clock,
                        ids: stores.ids,
                    ),
                )
                if !entry.isMedley {
                    services.record(.featureUsed(
                        kind == .rehearsal ? .singleSongRehearse : .singleSongLive,
                        context,
                    ))
                }
                await presentSongStage(controller, kind: kind, session: session, onEnd: onEnd)
                return true
            } catch {
                recordError(.showStartFailed, error)
                startFailure = "The song could not start (\(UserMessage.describe(error)))."
                return false
            }
        }

        private func presentSongStage(
            _ controller: ShowController,
            kind: ShowKind,
            session: LibrarySession,
            onEnd: (@MainActor () -> Void)?,
        ) async {
            let state = await controller.state
            let live = LiveSession(state: state, kind: kind, context: LiveSession.Context(
                controller: controller,
                library: session.stores.library,
                bindings: loadBindings(session),
                settings: liveSettings,
                instrument: instrumentProfile,
                scrollClock: dependencies.live.scrollClock,
                clock: session.stores.clock,
                makeClickOutput: dependencies.live.makeClickOutput,
                onEnd: { [weak self] live in await self?.finishSongSession(live, onEnd: onEnd) },
                scope: .song,
            ))
            live.services = services
            self.live = live
            StageWindowController.shared.present(self)
        }

        /// "End this song?" confirmed: ends the unsaved run and closes the stage. Nothing is
        /// recorded (no show-ended analytics, no completed-show count, no end Shortcut, no
        /// review reload).
        func finishSongSession(_ live: LiveSession, onEnd: (@MainActor () -> Void)?) async {
            await live.prefsSaved()
            _ = try? await live.context.controller.end()
            StageWindowController.shared.close()
            services.record(LifecycleCrumb.stageExited)
            if self.live === live {
                live.stop()
                self.live = nil
            }
            runQueuedOpenRequests()
            if live.quitsAfterEnding {
                NSApp.terminate(nil)
            }
            onEnd?()
        }
    }

    /// The library's way to start a single-song session (R150), injected at the Library
    /// pane so the song header, the selected row and the song menus can start one.
    struct SongSessionAction {
        /// Whether a run can start now (nothing performing, starting or waiting to resume).
        var isEnabled: Bool
        var start: @MainActor (SongID, ShowKind) -> Void
    }

    extension EnvironmentValues {
        @Entry var songSession: SongSessionAction?
    }
#endif
