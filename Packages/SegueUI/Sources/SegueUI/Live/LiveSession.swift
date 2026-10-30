#if os(macOS)
    import Editing
    import Foundation
    import Library
    import LiveLayout
    import Observation
    import Services
    import Shows
    import Support

    /// What a stage run covers (P8-2 section 13).
    public enum StageScope: Sendable, Hashable {
        /// A setlist (or a resumed show): logged as today.
        case setlist
        /// One song started from the library or "Rehearse this" (R150, R156): no progress
        /// dots, "End of song", never in `shows/`, the gig log or play stats.
        case song
    }

    /// One run on stage (a gig or a rehearsal): owns the `ShowController`, the current
    /// `LayoutPlan` and the `AutoScroller`, and is the single dispatcher of `LiveCommand`s.
    /// `.show` commands go to the engine, `.viewport` commands drive scroll and zoom (saved
    /// per song through `updateLivePrefs`), `.chrome` commands drive the overlays.
    @MainActor
    @Observable
    public final class LiveSession {
        /// What covers the stage body.
        public enum Overlay: Equatable {
            case search
            case endConfirm
            /// The keyboard help (`?`, WS2a 3.7): non-modal, any bound command closes it.
            case keys
        }

        /// The process-wide pieces a session needs.
        struct Context {
            var controller: ShowController
            var library: LibraryStore
            var bindings: InputBindingTable
            var settings: LiveSettingsStore
            /// Settings > Instrument (P8-4): the bass-note view and the mini neck.
            var instrument: InstrumentProfileStore?
            /// Drives auto-scroll: monotonic (`MonotonicClock`), so NTP corrections and sleep
            /// never make the song jump (a time-scaled clock in the auto-scroll E2E).
            var scrollClock: any Clock
            /// The engine's clock: elapsed set time.
            var clock: any Clock
            /// Makes the rehearsal click's audio output (only ever called in a rehearsal).
            var makeClickOutput: @MainActor () -> any MetronomeClickOutput = {
                AudioEngineClickOutput()
            }

            /// Called once the performer confirmed ending the run.
            var onEnd: @MainActor (LiveSession) async -> Void
            /// A setlist run, or one song from the library (R150, never logged).
            var scope: StageScope = .setlist
        }

        public let kind: ShowKind
        public private(set) var state: ShowState
        /// Search, requests and set-order overlays.
        public var overlay: Overlay?
        public var showsRequests = false
        public var showsDrawer = false
        public let search: QuickSearchModel
        /// The stage metronome (R90); its click exists only in a rehearsal.
        public let metronome: StageMetronome
        /// A short message on the stage ("No requests queued."); cleared by the next command.
        public var notice: String?

        /// Something that keeps failing until a later attempt succeeds.
        public enum Problem: Hashable, CaseIterable, Sendable {
            /// The show file (or a timing sample) could not be written.
            case showFile
            /// A song's live memory (zoom, columns, scroll speed) could not be saved.
            case songPrefs
        }

        /// Failures that stay on stage until they are resolved (a later write succeeds), so
        /// the performer can never miss that the show is not being saved.
        public internal(set) var problems: [Problem: String] = [:]
        /// Set when the performer asked to quit (Cmd-Q): the app quits once the run ended.
        public var quitsAfterEnding = false
        /// A brief mode indicator ("Columns: 2", "Zoom 110%"), cleared after 1.5 s.
        public internal(set) var indicator: String?
        @ObservationIgnored var indicatorTask: Task<Void, Never>?
        /// True once ending started (further commands are ignored).
        public private(set) var isEnding = false

        // Viewport state (see LiveSession+Viewport.swift).
        var viewport = LayoutSize(width: 0, height: 0)
        var plan: LayoutPlan?
        var scroller: AutoScroller?
        /// The rendered model of the current item (with its setlist overrides).
        var currentModel: RenderModel?
        /// The rendered model of the up-next song (in its arranged order).
        var upNextModel: RenderModel?
        /// What the stage does with the current item's arrangement (R122); nil = the item
        /// plays the full song as written.
        var currentArrangement: ArrangementState?
        /// Items whose arrangement state was sent to the show record.
        @ObservationIgnored var recordedArrangements: Set<ShowItemID> = []

        // Pass state (see LiveSession+Passes.swift, R147, R148).

        /// The pass a jump or a loop wrap made current; cleared by the next manual scroll,
        /// page step, Home, auto-scroll start or song change.
        var pinnedPass: Int?
        /// The pass the rehearsal loop repeats; nil when no loop is on.
        var loopPass: Int?
        /// The "Jumped to ..." confirmation and its sequence number (a repeat restarts it).
        var jumpToast: StageJumpToast.Message?
        @ObservationIgnored var jumpToastTask: Task<Void, Never>?
        /// The task waiting for the loop's next wrap on the scroll clock, and that instant.
        @ObservationIgnored var loopWrapTask: Task<Void, Never>?
        @ObservationIgnored var loopWrapInstant: Date?
        /// A section jump was recorded for analytics this session (once only).
        @ObservationIgnored var recordedJump = false
        /// The item the plan was laid out for; a change resets scrolling.
        @ObservationIgnored var laidOutItem: ShowItemID?
        /// Per-song live memory changed during this run (also saved to the sidecar).
        @ObservationIgnored var prefsCache: [SongID: LivePrefs] = [:]
        /// The scroll fraction last handed to the engine.
        @ObservationIgnored var reportedFraction: Double?
        /// The fraction to restore once the first plan exists (resume).
        @ObservationIgnored var pendingFraction: Double?
        /// The next new item opens scrolled to its bottom (Page Up across songs, R45).
        @ObservationIgnored var landsAtBottom = false
        /// Whether the current item was reached by an advance (for auto-start).
        @ObservationIgnored var arrivedByAdvance = false
        /// Navigation actions queued or running that can change the current song; page
        /// turns are ignored while any is in flight, since they would decide from the old
        /// song (R154).
        @ObservationIgnored private(set) var songChangesInFlight = 0

        /// Per-song live memory waiting to be written, latest value per song.
        @ObservationIgnored var unsavedPrefs: [SongID: LivePrefs] = [:]
        /// Live memory whose save failed; retried with the next save.
        @ObservationIgnored var failedPrefs: [SongID: LivePrefs] = [:]
        /// The writer draining `unsavedPrefs`, one save at a time.
        @ObservationIgnored var prefsWriter: Task<Void, Never>?

        @ObservationIgnored let context: Context
        /// Records analytics events (WS3 spec 5); the app hands over its hub on stage.
        @ObservationIgnored public var services: ServicesHub = .disabled {
            didSet { search.services = services }
        }

        /// `bassNeck` was recorded for this run (P8-4: once per stage session).
        @ObservationIgnored var bassNeckRecorded = false
        /// Auto-scroll was switched on during this run (`Segue.Show.ended`).
        @ObservationIgnored var autoScrollUsed = false
        @ObservationIgnored private var queue: Task<Void, Never>?
        @ObservationIgnored private var flushTask: Task<Void, Never>?
        @ObservationIgnored private var keepAwake: DisplaySleepAssertion?

        /// How often the stage flushes the scroll position and settles auto-scroll. With
        /// `ShowEnvironment.scrollWriteInterval` (0.75 s) a scroll change is on disk within
        /// a second.
        static let flushTick: Duration = .milliseconds(250)

        init(state: ShowState, kind: ShowKind, context: Context) {
            self.state = state
            self.kind = kind
            self.context = context
            search = QuickSearchModel(library: context.library)
            metronome = StageMetronome(
                kind: kind,
                isOn: context.settings.metronomeOn,
                clock: context.scrollClock,
                makeClickOutput: context.makeClickOutput,
            )
            metronome.follow(state)
            pendingFraction = state.record.scrollPosition > 0 ? state.record.scrollPosition : nil
            relayout()
        }

        public var setlistName: String {
            state.record.setlistName
        }

        /// A setlist run or a single song (R150).
        public var scope: StageScope {
            context.scope
        }

        /// The minimum lyric size in force (Settings > Live).
        var minLyricSize: Double {
            context.settings.settings.minLyricSize
        }

        // MARK: Lifecycle

        /// The stage is up: keep the display awake and flush scroll position periodically.
        func begin() {
            if keepAwake == nil {
                let label = kind == .gig ? "Performing" : "Rehearsing"
                keepAwake = DisplaySleepAssertion(reason: "\(label) \(setlistName)")
            }
            guard flushTask == nil else { return }
            flushTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.flushTick)
                    self?.settleScroll()
                    await self?.flushScroll()
                }
            }
        }

        /// The stage went away: release the assertion and stop the timer.
        func stop() {
            stopLoop()
            metronome.stop()
            flushTask?.cancel()
            flushTask = nil
            keepAwake?.end()
            keepAwake = nil
        }

        /// The stage went away without the run ending (it stays resumable): stops and lets
        /// go of the show's claim so a later resume can take it.
        func abandon() {
            stop()
            let controller = context.controller
            Task { await controller.relinquish() }
        }

        /// Whether the display sleep assertion is held (tests).
        var isKeepingAwake: Bool {
            keepAwake?.isHeld ?? false
        }

        // MARK: Engine actions

        /// Runs `action` on the engine after any action still in flight, so fast pedal taps
        /// apply in order. When the show file cannot be written the action still took effect
        /// in the engine: the stage follows it and a "not saving" problem stays up until a
        /// later write succeeds.
        public func perform(_ action: ShowAction) {
            let changesSong = action.changesSong
            if changesSong {
                songChangesInFlight += 1
            }
            enqueue { session in
                defer {
                    if changesSong {
                        session.songChangesInFlight -= 1
                    }
                }
                let controller = session.context.controller
                let before = session.state.current?.item.itemId
                do {
                    let newState = try await controller.perform(action)
                    session.arrivedByAdvance = action == .next || action == .skipCurrent
                    session.apply(newState, previousItem: before)
                    await session.noteSaved()
                } catch {
                    let newState = await controller.state
                    if newState.current?.item.itemId != before {
                        session.arrivedByAdvance = action == .next || action == .skipCurrent
                    }
                    session.apply(newState, previousItem: before)
                    session.report(error)
                }
            }
        }

        /// A write failure becomes the persistent "not saving" problem; anything else is a
        /// one-off notice.
        func report(_ error: any Error) {
            if case .writeFailed = error as? ShowError {
                problems[.showFile] = "Not saving the show: \(UserMessage.describe(error)) "
                    + "Keep playing; Segue retries with every action."
            } else {
                notice = UserMessage.describe(error)
            }
        }

        /// Clears the "not saving" problem once everything is on disk.
        func noteSaved() async {
            guard problems[.showFile] != nil else { return }
            if await !context.controller.hasUnsavedChanges {
                problems[.showFile] = nil
            }
        }

        func enqueue(_ work: @escaping @MainActor (LiveSession) async -> Void) {
            let previous = queue
            queue = Task { [weak self] in
                await previous?.value
                guard let self, !isEnding else { return }
                await work(self)
            }
        }

        /// Takes a new engine state; a new current item resets scrolling.
        func apply(_ newState: ShowState, previousItem: ShowItemID?) {
            let changed = newState.current?.item.itemId != previousItem
                || newState.current?.song != state.current?.song
            state = newState
            metronome.follow(newState)
            if changed {
                laidOutItem = nil
            }
            relayout()
        }

        /// "End Show" confirmed: ends the run through the app (gig log, Shortcut, review).
        public func confirmEnd() {
            overlay = nil
            stopLoop()
            metronome.stop()
            enqueue { session in
                session.isEnding = true
                await session.flushScroll()
                await session.context.onEnd(session)
            }
        }

        /// Writes the scroll position if it changed, then lets the engine flush it when due.
        /// The position is tagged with the item it belongs to, so a flush that lands after
        /// an advance is dropped instead of moving the new song.
        func flushScroll() async {
            let fraction = scrollFraction(at: context.scrollClock.now())
            let item = laidOutItem
            do {
                if let item,
                   reportedFraction.map({ abs($0 - fraction) > 0.0005 }) ?? (fraction > 0)
                {
                    reportedFraction = fraction
                    try await context.controller.updateScrollPosition(fraction, for: item)
                }
                try await context.controller.flushScrollPositionIfDue()
                await noteSaved()
            } catch {
                report(error)
            }
        }

        // MARK: Derived display values

        /// The current item's 1-based position and the item count: "4 of 12".
        public var positionText: String {
            let items = state.record.items
            guard !items.isEmpty else { return "" }
            guard let index = state.current?.position else { return "End of \(items.count)" }
            return "\(index + 1) of \(items.count)"
        }

        /// Queued requests, oldest first.
        public var queuedRequests: [ShowRequest] {
            state.record.queuedRequests
        }

        /// Seconds since the run started.
        func elapsed(at now: Date) -> TimeInterval {
            max(0, now.timeIntervalSince(state.record.startedAt))
        }
    }

    private extension ShowAction {
        /// Whether this navigation action can change the current song (page turns wait for it).
        var changesSong: Bool {
            switch self {
            case .jump, .next, .playNextRequest, .playNow, .previous, .skipCurrent:
                true
            default:
                false
            }
        }
    }
#endif
