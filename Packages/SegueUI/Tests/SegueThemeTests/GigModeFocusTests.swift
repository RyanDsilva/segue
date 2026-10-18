import Foundation
@testable import SegueUI
import Shows
import Support
import Testing

/// Gig Mode is off until set up (R18), and the checklist's Focus row ticks only on observed
/// completion or the performer's Done (R35; WS1 4.8c-d).
@MainActor
struct GigModeFocusTests {
    typealias Status = PreShowChecklist.FocusStatus

    // MARK: Settings: off by default, stored names kept (A38)

    @Test
    func `a fresh settings store has no Gig Mode Shortcuts`() throws {
        let suite = "dev.ryandsilva.segue.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = LiveSettingsStore(defaults: defaults)
        #expect(store.settings.startShortcut == nil)
        #expect(store.settings.endShortcut == nil)
    }

    @Test
    func `stored Shortcut names are kept unchanged`() throws {
        let suite = "dev.ryandsilva.segue.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let stored = Data(#"""
        {"minLyricSize": 22, "startShortcut": "Gig Mode On", "endShortcut": "Gig Mode Off",
         "hiddenChecklistItems": []}
        """#.utf8)
        defaults.set(stored, forKey: LiveSettingsStore.defaultsKey)
        let store = LiveSettingsStore(defaults: defaults)
        #expect(store.settings.startShortcut == "Gig Mode On")
        #expect(store.settings.endShortcut == "Gig Mode Off")
    }

    // MARK: Outcome to status

    @Test(arguments: [
        (ShortcutOutcome.completed, Status.ran("Go")),
        (.handedOver, .running("Go")),
        (.failed("not found"), .failed("Go", message: "not found")),
    ])
    func `each runner outcome maps to its focus status`(
        outcome: ShortcutOutcome,
        expected: Status,
    ) {
        #expect(Status(outcome, name: "Go") == expected)
    }

    // MARK: Timeout on the injected clock

    @Test
    func `a hand-over turns unknown only once the confirmation timeout has passed`() {
        let clock = ManualClock()
        let checklist = makeChecklist(focus: .running("Go"), clock: clock)
        clock.advance(by: ShortcutTiming.confirmTimeout - 1)
        checklist.checkFocusTimeout()
        #expect(checklist.focus == .running("Go"))
        clock.advance(by: 1)
        checklist.checkFocusTimeout()
        #expect(checklist.focus == .unknown("Go"))
        #expect(!checklist.isDone(.focus))
        #expect(checklist.offersFocusDone)
    }

    @Test
    func `a confirmation before the timeout ticks the row`() {
        let clock = ManualClock()
        let checklist = makeChecklist(focus: .running("Go"), clock: clock)
        clock.advance(by: ShortcutTiming.confirmTimeout - 5)
        #expect(checklist.confirmFocus())
        clock.advance(by: 10)
        checklist.checkFocusTimeout()
        #expect(checklist.focus == .ran("Go"))
        #expect(checklist.isDone(.focus))
    }

    @Test
    func `a confirmation with nothing pending changes nothing`() {
        for status in [Status.notConfigured, .notRun, .ran("Go"), .failed("Go", message: "x")] {
            let checklist = makeChecklist(focus: status, clock: ManualClock())
            #expect(!checklist.confirmFocus())
            #expect(checklist.focus == status)
        }
    }

    // MARK: isDone and row visibility

    @Test(arguments: [
        (Status.notConfigured, false, false),
        (.notRun, false, false),
        (.running("Go"), false, false),
        (.ran("Go"), true, false),
        (.unknown("Go"), false, true),
        (.failed("Go", message: "x"), false, true),
    ])
    func `the focus row ticks only on observed completion or Done`(
        status: Status,
        doneWithoutPerformer: Bool,
        offersDone: Bool,
    ) {
        let checklist = makeChecklist(focus: status, clock: ManualClock())
        #expect(checklist.isDone(.focus) == doneWithoutPerformer)
        #expect(checklist.offersFocusDone == offersDone)
        checklist.focusConfirmedByPerformer = true
        #expect(checklist.isDone(.focus))
        #expect(checklist.visibleRows.contains(.focus) == (status != .notConfigured))
    }

    private func makeChecklist(focus: Status, clock: ManualClock) -> PreShowChecklist {
        let suite = "dev.ryandsilva.segue.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        return PreShowChecklist(
            setlistName: "Friday",
            kind: .gig,
            missingPositions: [],
            performableCount: 3,
            focus: focus,
            settings: LiveSettingsStore(defaults: defaults),
            power: FixedPowerSource(onCharger: true),
            clock: clock,
        )
    }
}
