import Foundation

/// When edits save themselves (WS2a 3.4, R17, B-13): one second after the last change, and
/// at most five seconds after the first unsaved change while changes keep coming. The song
/// editor and gig details both use it.
public struct AutosavePolicy: Sendable, Equatable {
    /// The shipped idle debounce.
    public static let idle: Duration = .seconds(1)
    /// The shipped maximum latency during continuous changes.
    public static let maxLatency: Duration = .seconds(5)

    /// Time after the last change before a save runs.
    public var idle: Duration
    /// Time after the first unsaved change before a save runs, however busy the typing.
    public var maxLatency: Duration

    public init(idle: Duration = Self.idle, maxLatency: Duration = Self.maxLatency) {
        self.idle = idle
        self.maxLatency = maxLatency
    }
}

/// A clock reduced to what autosave needs: time elapsed since it was made, and sleeping
/// until a later point. Built from any `Clock` (the continuous clock in the app, a manual
/// one in tests).
public struct AutosaveTimeSource: Sendable {
    let elapsed: @Sendable () -> Duration
    let sleepUntil: @Sendable (Duration) async throws -> Void

    public init<C: Clock>(_ clock: C) where C.Duration == Duration {
        let origin = clock.now
        elapsed = { origin.duration(to: clock.now) }
        sleepUntil = { offset in
            try await clock.sleep(until: origin.advanced(by: offset), tolerance: nil)
        }
    }
}

/// An `AutosavePolicy` with the clock its timers run on.
public struct AutosaveTiming: Sendable {
    public var policy: AutosavePolicy
    public var time: AutosaveTimeSource

    public init(
        policy: AutosavePolicy = AutosavePolicy(),
        time: AutosaveTimeSource = AutosaveTimeSource(ContinuousClock()),
    ) {
        self.policy = policy
        self.time = time
    }

    /// The shipped timing on the continuous clock.
    public static var standard: Self {
        Self()
    }

    /// A scheduler running `save` on this timing.
    @MainActor
    public func scheduler(save: @escaping AutosaveScheduler.Save = { true }) -> AutosaveScheduler {
        AutosaveScheduler(policy: policy, time: time, save: save)
    }
}

/// Runs a save after changes stop (`AutosavePolicy.idle`) or have gone unsaved for too long
/// (`maxLatency`), or at once on `flush()`. One save runs at a time; a change made while it
/// runs schedules exactly one more. A failed save is retried on the next change or flush,
/// never in a loop; `pause()` stops saving altogether (a conflict waits for the user).
@MainActor
public final class AutosaveScheduler {
    /// Writes the pending changes; returns whether they are now on disk.
    public typealias Save = @MainActor () async -> Bool

    public let policy: AutosavePolicy
    /// The save step (settable so an owner can capture itself after init).
    public var save: Save

    /// Changes not saved yet (including a failed save's).
    public private(set) var isPending = false
    /// A save is running.
    public private(set) var isSaving = false
    /// Saving is paused (`pause()`): timers do not fire and `flush()` reports failure.
    public private(set) var isPaused = false

    private let elapsed: @Sendable () -> Duration
    private let sleepUntil: @Sendable (Duration) async throws -> Void
    private var firstChange: Duration?
    private var lastChange: Duration?
    private var timer: Task<Void, Never>?
    private var inFlight: Task<Bool, Never>?

    public init(policy: AutosavePolicy, time: AutosaveTimeSource, save: @escaping Save) {
        self.policy = policy
        self.save = save
        elapsed = time.elapsed
        sleepUntil = time.sleepUntil
    }

    /// When the next save fires, as time since the scheduler was made; nil when none is due.
    public var deadline: Duration? {
        guard isPending, !isPaused, let firstChange, let lastChange else { return nil }
        return min(lastChange + policy.idle, firstChange + policy.maxLatency)
    }

    /// Records a change and (re)arms the timer.
    public func noteChange() {
        let now = elapsed()
        if firstChange == nil {
            firstChange = now
        }
        lastChange = now
        isPending = true
        arm()
    }

    /// Saves now (after any save in flight). Returns whether nothing is left unsaved: false
    /// when a save failed or saving is paused.
    @discardableResult
    public func flush() async -> Bool {
        timer?.cancel()
        timer = nil
        if let inFlight {
            _ = await inFlight.value
        }
        while isPending {
            guard !isPaused, await runSave() else { return false }
        }
        return true
    }

    /// Stops saving until `resume()` (a conflict the user has to settle).
    public func pause() {
        isPaused = true
        timer?.cancel()
        timer = nil
    }

    /// Saves again from the next change on (and now, if changes are pending).
    public func resume() {
        isPaused = false
        if isPending, firstChange == nil {
            firstChange = elapsed()
            lastChange = firstChange
        }
        arm()
    }

    /// Forgets pending changes (the edits were discarded or saved another way).
    public func discard() {
        timer?.cancel()
        timer = nil
        isPending = false
        firstChange = nil
        lastChange = nil
    }

    private func arm() {
        timer?.cancel()
        guard let deadline else {
            timer = nil
            return
        }
        let sleepUntil = sleepUntil
        timer = Task { [weak self] in
            do {
                try await sleepUntil(deadline)
            } catch {
                return
            }
            guard !Task.isCancelled, let self, !isPaused else { return }
            timer = nil
            await runSave()
        }
    }

    /// One save of what is pending now. Changes arriving meanwhile stay pending (and are
    /// re-armed); a failure leaves the changes pending without re-arming.
    @discardableResult
    private func runSave() async -> Bool {
        if let inFlight {
            _ = await inFlight.value
        }
        guard isPending, !isPaused else { return !isPending }
        isPending = false
        firstChange = nil
        lastChange = nil
        isSaving = true
        let save = save
        let task = Task { await save() }
        inFlight = task
        let saved = await task.value
        inFlight = nil
        isSaving = false
        if !saved {
            isPending = true
        } else if isPending {
            arm()
        }
        return saved
    }
}
