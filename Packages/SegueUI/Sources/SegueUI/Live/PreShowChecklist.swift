#if os(macOS)
    import Foundation
    import Observation
    import Shows

    /// The pre-show checklist shown on "Start show" and "Rehearse" before the stage goes up:
    /// songs that will be left out (missing from the library), "Focus on" (ticked only when
    /// the start Shortcut was handed over without error), "Charger connected" (IOKit) and
    /// "Screen brightness up" (ticked by the user). Rows can be dismissed for this show or
    /// hidden for good ("Don't show again").
    @MainActor
    @Observable
    public final class PreShowChecklist: Identifiable {
        /// The state of the "Focus on" row.
        public enum FocusStatus: Equatable {
            /// No start Shortcut is set (Settings > Live).
            case notConfigured
            /// Shortcuts are off for rehearsals.
            case notRun
            case running(String)
            case ran(String)
            case failed(String, message: String)
        }

        public let id = UUID()
        public let setlistName: String
        public let kind: ShowKind
        /// 1-based setlist positions of entries whose song is gone; they are left out.
        public let missingPositions: [Int]
        public let performableCount: Int
        public internal(set) var focus: FocusStatus
        public internal(set) var charger: Bool?
        public var brightnessConfirmed = false
        /// Rows dismissed for this show only.
        public var dismissed: Set<ChecklistItem> = []

        @ObservationIgnored private let settings: LiveSettingsStore
        @ObservationIgnored private let power: any PowerSourceReading
        @ObservationIgnored var continuation: CheckedContinuation<Bool, Never>?
        @ObservationIgnored private var powerTask: Task<Void, Never>?

        init(
            setlistName: String,
            kind: ShowKind,
            missingPositions: [Int],
            performableCount: Int,
            focus: FocusStatus,
            settings: LiveSettingsStore,
            power: any PowerSourceReading,
        ) {
            self.setlistName = setlistName
            self.kind = kind
            self.missingPositions = missingPositions
            self.performableCount = performableCount
            self.focus = focus
            self.settings = settings
            self.power = power
            charger = power.isOnCharger()
        }

        /// The rows to show, in checklist order.
        public var visibleRows: [ChecklistItem] {
            let hidden = settings.settings.hiddenChecklistItems
            return ChecklistItem.allCases.filter { !hidden.contains($0) && !dismissed.contains($0) }
        }

        /// Whether there is anything to show (rows or the missing-songs warning).
        var hasContent: Bool {
            !visibleRows.isEmpty || !missingPositions.isEmpty
        }

        public func isDone(_ item: ChecklistItem) -> Bool {
            switch item {
            case .focus:
                if case .ran = focus {
                    return true
                }
                return false
            case .charger:
                return charger == true
            case .brightness:
                return brightnessConfirmed
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
            continuation?.resume(returning: start)
            continuation = nil
        }
    }
#endif
