#if os(macOS)
    import Foundation
    import Observation
    import Shows
    import Support

    /// The pre-show checklist shown on "Start show" and "Rehearse" before the stage goes up:
    /// songs that will be left out (missing from the library), "Focus on", "Charger
    /// connected" (IOKit) and "Screen brightness up" (ticked by the user). Rows can be
    /// dismissed for this show or hidden for good ("Don't show again").
    ///
    /// "Focus on" ticks only when the start Shortcut was observed to finish or the performer
    /// pressed Done (R18, R35). A hand-over, a timeout or an error never ticks it, and the
    /// row is hidden when no start Shortcut is set (A37).
    @MainActor
    @Observable
    public final class PreShowChecklist: Identifiable {
        /// The state of the "Focus on" row.
        public enum FocusStatus: Equatable, Sendable {
            /// No start Shortcut is set (Settings > Live); the row is hidden.
            case notConfigured
            /// Shortcuts are off for rehearsals.
            case notRun
            /// The request was sent; the result is not known yet.
            case running(String)
            /// Observed completion: the Shortcut finished, or its confirmation arrived.
            case ran(String)
            /// Only a hand-over is known, or no confirmation came within
            /// `ShortcutTiming.confirmTimeout`.
            case unknown(String)
            /// Observed failure.
            case failed(String, message: String)

            /// The status right after a run of `name` reported `outcome`.
            public init(_ outcome: ShortcutOutcome, name: String) {
                switch outcome {
                case .completed: self = .ran(name)
                case .handedOver: self = .running(name)
                case let .failed(message): self = .failed(name, message: message)
                }
            }

            /// The start Shortcut's name when a start request was sent (Focus may be on).
            public var requestedName: String? {
                switch self {
                case .notConfigured, .notRun: nil
                case let .ran(name), let .running(name), let .unknown(name): name
                case let .failed(name, _): name
                }
            }
        }

        public let id = UUID()
        public let setlistName: String
        public let kind: ShowKind
        /// Setlist numbers ("2", a medley member "4b") of songs that are gone; they are left
        /// out.
        public let missingPositions: [String]
        /// Song slots whose arrangement no longer matches the song (R122, R123): "#3 Title".
        /// The stage shows them as the full song.
        public internal(set) var staleArrangements: [String] = []
        /// Edit on the stale-arrangements row: cancels the start and opens the first one's
        /// Arrange Sections; set by the app model.
        @ObservationIgnored var editStaleArrangement: (() -> Void)?
        public let performableCount: Int
        public internal(set) var focus: FocusStatus
        public internal(set) var charger: Bool?
        public var brightnessConfirmed = false
        /// The performer pressed Done on the Focus row (offered on `.unknown` and `.failed`).
        public var focusConfirmedByPerformer = false
        /// Rows dismissed for this show only.
        public var dismissed: Set<ChecklistItem> = []
        /// The metronome click for this rehearsal (R118): off at the start of every one.
        public var rehearsalClickOn = false

        @ObservationIgnored let settings: LiveSettingsStore
        @ObservationIgnored private let power: any PowerSourceReading
        @ObservationIgnored var continuation: CheckedContinuation<Bool, Never>?
        @ObservationIgnored private var powerTask: Task<Void, Never>?
        /// Measures the confirmation timeout (the live clock, scaled in E2E runs).
        @ObservationIgnored private let clock: any Clock
        /// When the pending start request was sent.
        @ObservationIgnored private var focusRequestedAt: Date?
        @ObservationIgnored private var focusTask: Task<Void, Never>?
        /// Runs the start Shortcut again (Retry); set by the app model.
        @ObservationIgnored var retryFocus: (() async -> FocusStatus)?

        init(
            setlistName: String,
            kind: ShowKind,
            missingPositions: [String],
            performableCount: Int,
            focus: FocusStatus,
            settings: LiveSettingsStore,
            power: any PowerSourceReading,
            clock: any Clock,
        ) {
            self.setlistName = setlistName
            self.kind = kind
            self.missingPositions = missingPositions
            self.performableCount = performableCount
            self.focus = focus
            self.settings = settings
            self.power = power
            self.clock = clock
            charger = power.isOnCharger()
            if case .running = focus {
                focusRequestedAt = clock.now()
            }
        }

        /// The rows to show, in checklist order. The Focus row is hidden when no start
        /// Shortcut is set (A37), so the checklist never shows a row that cannot tick.
        public var visibleRows: [ChecklistItem] {
            let hidden = settings.settings.hiddenChecklistItems
            return ChecklistItem.allCases.filter { item in
                if item == .focus, focus == .notConfigured {
                    return false
                }
                // A warning, only while singer view is on (P9-2 6.10).
                if item == .singerView, !settings.settings.singerView {
                    return false
                }
                return !hidden.contains(item) && !dismissed.contains(item)
            }
        }

        /// Whether there is anything to show (rows or the missing-songs warning).
        var hasContent: Bool {
            !visibleRows.isEmpty || !missingPositions.isEmpty || !staleArrangements.isEmpty
        }

        public func isDone(_ item: ChecklistItem) -> Bool {
            switch item {
            case .focus:
                if case .ran = focus {
                    return true
                }
                return focusConfirmedByPerformer
            case .charger:
                return charger == true
            case .brightness:
                return brightnessConfirmed
            case .singerView:
                // A warning, never ticked: Show Chords turns singer view off (and the row
                // goes).
                return false
            }
        }

        /// The singer view row's Show Chords: the stage shows chords again.
        public func showChords() {
            settings.settings.singerView = false
        }

        // MARK: Focus row

        /// Whether the Focus row offers Done (the result is unknown or a failure).
        public var offersFocusDone: Bool {
            switch focus {
            case .failed, .unknown: true
            default: false
            }
        }

        /// Whether the Focus row offers Retry (an observed failure).
        public var offersFocusRetry: Bool {
            if case .failed = focus {
                return retryFocus != nil
            }
            return false
        }

        /// Turns a pending request into `.unknown` once `ShortcutTiming.confirmTimeout` has
        /// passed on the clock without a confirmation.
        func checkFocusTimeout() {
            guard case let .running(name) = focus, let requested = focusRequestedAt else {
                return
            }
            if clock.now().timeIntervalSince(requested) >= ShortcutTiming.confirmTimeout {
                focus = .unknown(name)
                focusRequestedAt = nil
            }
        }

        /// A confirmation that the pending start Shortcut finished: ticks the row while a
        /// request is pending or unconfirmed. Returns false (and changes nothing) otherwise.
        @discardableResult
        func confirmFocus() -> Bool {
            switch focus {
            case let .running(name), let .unknown(name):
                focus = .ran(name)
                focusRequestedAt = nil
                return true
            default:
                return false
            }
        }

        /// Retry on a failed row: runs the start Shortcut again and clears a manual Done.
        public func retryFocusShortcut() {
            guard let retryFocus, let name = focus.requestedName else { return }
            focusConfirmedByPerformer = false
            setFocus(.running(name))
            Task { [weak self] in
                let status = await retryFocus()
                self?.setFocus(status)
            }
        }

        private func setFocus(_ status: FocusStatus) {
            focus = status
            if case .running = status {
                focusRequestedAt = clock.now()
                watchFocus()
            } else {
                focusRequestedAt = nil
            }
        }

        /// Polls the confirmation timeout while a request is pending.
        func watchFocus() {
            focusTask?.cancel()
            guard case .running = focus else { return }
            focusTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard let self, case .running = focus else { return }
                    checkFocusTimeout()
                }
            }
        }

        /// "Don't show again": hides `item` in every later show (Settings > Live brings it
        /// back).
        public func hideForGood(_ item: ChecklistItem) {
            settings.settings.hiddenChecklistItems.insert(item)
        }

        /// Re-reads the charger state every 2 s while the sheet is up, so plugging in ticks
        /// the row.
        func watchPower() {
            powerTask?.cancel()
            let power = power
            powerTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    self?.charger = power.isOnCharger()
                }
            }
        }

        /// The performer's answer: true starts the show.
        public func answer(_ start: Bool) {
            powerTask?.cancel()
            powerTask = nil
            focusTask?.cancel()
            focusTask = nil
            continuation?.resume(returning: start)
            continuation = nil
        }
    }
#endif
