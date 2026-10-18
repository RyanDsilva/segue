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

    // MARK: Shortcuts Events replies (Path SE, R59; probe results in research 09)

    @Test(arguments: [
        (ShortcutsEventsReply.finished, ShortcutOutcome.completed),
        (
            ShortcutsEventsReply(errorNumber: -1728),
            .failed(AppleEventShortcutRunner.Message.notFound),
        ),
        (
            ShortcutsEventsReply(errorNumber: -1743),
            .failed(AppleEventShortcutRunner.Message.notPermitted),
        ),
        (
            ShortcutsEventsReply(
                errorNumber: -1753,
                errorMessage: "A server with the specified hostname could not be found.",
            ),
            .failed("A server with the specified hostname could not be found"),
        ),
        (ShortcutsEventsReply(errorNumber: -1753), .failed("Shortcuts reported error -1753")),
        (ShortcutsEventsReply(errorNumber: -1712), .handedOver),
        (ShortcutsEventsReply(errorNumber: -10000, errorMessage: "Boom"), .failed("Boom")),
    ])
    func `each Shortcuts Events reply maps to one outcome`(
        reply: ShortcutsEventsReply,
        expected: ShortcutOutcome,
    ) async {
        let events = ScriptedShortcutsEvents(permission: 0, reply: reply)
        let runner = AppleEventShortcutRunner(events: events)
        #expect(await runner.run("Gig Mode On") == expected)
        #expect(events.calls == ["permission(ask: false)", "run(Gig Mode On)"])
    }

    @Test(arguments: [
        (-1743, AppleEventShortcutRunner.Message.notPermitted),
        (-1744, AppleEventShortcutRunner.Message.needsConsent),
        (-600, "Shortcuts Events did not start"),
        (-50, "Segue could not reach Shortcuts Events (error -50)"),
    ])
    func `a refused permission check fails without sending the event`(
        status: Int,
        message: String,
    ) async {
        let events = ScriptedShortcutsEvents(permission: OSStatus(status), reply: .finished)
        let runner = AppleEventShortcutRunner(events: events)
        #expect(await runner.run("Gig Mode On") == .failed(message))
        #expect(events.calls == ["permission(ask: false)"])
    }

    @Test
    func `only the Settings test may ask for the Automation permission`() async {
        let events = ScriptedShortcutsEvents(permission: 0, reply: .finished)
        let runner = AppleEventShortcutRunner(events: events)
        #expect(await runner.runAskingPermission("Gig Mode On") == .completed)
        #expect(events.calls == ["permission(ask: true)", "run(Gig Mode On)"])
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

/// Answers every permission check with `permission` and every run with `reply`, recording
/// the calls in order.
private final class ScriptedShortcutsEvents: ShortcutsEvents, @unchecked Sendable {
    let permission: OSStatus
    let reply: ShortcutsEventsReply
    private let lock = NSLock()
    private var recorded: [String] = []

    init(permission: OSStatus, reply: ShortcutsEventsReply) {
        self.permission = permission
        self.reply = reply
    }

    var calls: [String] {
        lock.withLock { recorded }
    }

    func permission(askUserIfNeeded: Bool) async -> OSStatus {
        lock.withLock { recorded.append("permission(ask: \(askUserIfNeeded))") }
        return permission
    }

    func run(_ name: String) async -> ShortcutsEventsReply {
        lock.withLock { recorded.append("run(\(name))") }
        return reply
    }
}
