#if os(macOS)
    import Editing
    import Foundation
    import Library
    import LiveLayout
    import Observation
    import Shows
    import Support

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
        }

        /// The process-wide pieces a session needs.
        struct Context {
            var controller: ShowController
            var library: LibraryStore
            var bindings: InputBindingTable
            var settings: LiveSettingsStore
            /// Drives auto-scroll (a time-scaled clock in the auto-scroll E2E).
            var scrollClock: any Clock
            /// The engine's clock: elapsed set time.
            var clock: any Clock
            /// Called once the performer confirmed ending the run.
            var onEnd: @MainActor (LiveSession) async -> Void
        }

        public let kind: ShowKind
        public private(set) var state: ShowState
        /// Search, requests and set-order overlays.
        public var overlay: Overlay?
        public var showsRequests = false
        public var showsDrawer = false
        public let search: QuickSearchModel
        /// A short message on the stage (an action failed); cleared by the next command.
        public var notice: String?
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
        /// The rendered model of the up-next song.
        var upNextModel: RenderModel?
        /// The item the plan was laid out for; a change resets scrolling.
        @ObservationIgnored var laidOutItem: ShowItemID?
        /// Per-song live memory changed during this run (also saved to the sidecar).
        @ObservationIgnored var prefsCache: [SongID: LivePrefs] = [:]
        /// The scroll fraction last handed to the engine.
        @ObservationIgnored var reportedFraction: Double?
        /// The fraction to restore once the first plan exists (resume).
        @ObservationIgnored var pendingFraction: Double?
        /// Whether the current item was reached by an advance (for auto-start).
        @ObservationIgnored var arrivedByAdvance = false

        @ObservationIgnored let context: Context
        @ObservationIgnored private var queue: Task<Void, Never>?
        @ObservationIgnored private var flushTask: Task<Void, Never>?
        @ObservationIgnored private var keepAwake: DisplaySleepAssertion?

        init(state: ShowState, kind: ShowKind, context: Context) {
            self.state = state
            self.kind = kind
            self.context = context
            search = QuickSearchModel(library: context.library)
            pendingFraction = state.record.scrollPosition > 0 ? state.record.scrollPosition : nil
            relayout()
        }

        public var setlistName: String {
            state.record.setlistName
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
                    try? await Task.sleep(for: .milliseconds(500))
                    await self?.flushScroll()
                }
            }
        }

        /// The stage went away: release the assertion and stop the timer.
        func stop() {
            flushTask?.cancel()
            flushTask = nil
            keepAwake?.end()
            keepAwake = nil
        }

        /// Whether the display sleep assertion is held (tests).
        var isKeepingAwake: Bool {
            keepAwake?.isHeld ?? false
        }

        // MARK: Engine actions

        /// Runs `action` on the engine after any action still in flight, so fast pedal taps
        /// apply in order.
        public func perform(_ action: ShowAction) {
            enqueue { session in
                do {
                    let before = session.state.current?.item.itemId
                    let newState = try await session.context.controller.perform(action)
                    session.arrivedByAdvance = action == .next || action == .skipCurrent
                    session.apply(newState, previousItem: before)
                } catch {
                    session.notice = UserMessage.describe(error)
                }
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
            if changed {
                laidOutItem = nil
            }
            relayout()
        }

        /// "End Show" confirmed: ends the run through the app (gig log, Shortcut, review).
        public func confirmEnd() {
            overlay = nil
            enqueue { session in
                session.isEnding = true
                await session.flushScroll()
                await session.context.onEnd(session)
            }
        }

        /// Writes the scroll position if it changed, then lets the engine flush it when due.
        func flushScroll() async {
            let fraction = scrollFraction(at: context.scrollClock.now())
            do {
                if reportedFraction.map({ abs($0 - fraction) > 0.0005 }) ?? (fraction > 0) {
                    reportedFraction = fraction
                    try await context.controller.updateScrollPosition(fraction)
                }
                try await context.controller.flushScrollPositionIfDue()
            } catch {
                notice = UserMessage.describe(error)
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
#endif
