import Foundation
import Library
@testable import SegueUI
import Support
import Synchronization
import Testing

/// Autosave timing and its editor integration (WS2a 3.4) on a manual clock.
@MainActor
struct AutosaveTests {
    /// A scheduler on a manual clock that counts its saves.
    @MainActor
    private final class Harness {
        let clock = ManualTestClock()
        var saves = 0
        var result = true
        lazy var scheduler = AutosaveTiming(time: AutosaveTimeSource(clock))
            .scheduler { [weak self] in
                self?.saves += 1
                return self?.result ?? true
            }

        /// Moves time forward and lets the woken timers run.
        func advance(_ seconds: Double) async {
            clock.advance(by: .milliseconds(Int(seconds * 1000)))
            await settle()
        }
    }

    @Test
    func `the shipped policy is one second idle and five seconds at most, everywhere`(
    ) async throws {
        #expect(AutosavePolicy.idle == .seconds(1))
        #expect(AutosavePolicy.maxLatency == .seconds(5))
        #expect(AutosaveTiming.standard.policy == AutosavePolicy())
        let env = try TestEnvironment()
        let session = try #require(try await env.openApp().session)
        #expect(session.library.autosave.policy == AutosavePolicy())
        #expect(session.gigLog.autosave.policy == AutosavePolicy())
    }

    @Test
    func `a burst of changes saves once, one idle period after the last`() async {
        let harness = Harness()
        for _ in 0 ..< 5 {
            harness.scheduler.noteChange()
            await harness.advance(0.2)
        }
        #expect(harness.saves == 0)
        await harness.advance(0.7)
        #expect(harness.saves == 0)
        await harness.advance(0.2)
        #expect(harness.saves == 1)
        await harness.advance(5)
        #expect(harness.saves == 1)
        #expect(!harness.scheduler.isPending)
    }

    @Test
    func `continuous changes still save after the maximum latency`() async {
        let harness = Harness()
        for _ in 0 ..< 9 {
            harness.scheduler.noteChange()
            await harness.advance(0.5)
        }
        // Changes every 0.5 s never leave a 1 s pause, but 5 s after the first one it saves.
        #expect(harness.saves == 0)
        harness.scheduler.noteChange()
        await harness.advance(0.5)
        #expect(harness.saves == 1)
    }

    @Test
    func `flush saves at once and reports failure`() async {
        let harness = Harness()
        harness.scheduler.noteChange()
        #expect(await harness.scheduler.flush())
        #expect(harness.saves == 1)
        #expect(await harness.scheduler.flush())
        #expect(harness.saves == 1)

        harness.result = false
        harness.scheduler.noteChange()
        #expect(await !harness.scheduler.flush())
        #expect(harness.scheduler.isPending)
        // A failure is not retried on its own; the next flush (or change) retries.
        await harness.advance(10)
        #expect(harness.saves == 2)
        harness.result = true
        #expect(await harness.scheduler.flush())
        #expect(harness.saves == 3)
    }

    @Test
    func `changes during a save schedule exactly one more`() async {
        let clock = ManualTestClock()
        let gate = Gate()
        var saves = 0
        let scheduler = AutosaveTiming(time: AutosaveTimeSource(clock)).scheduler {
            saves += 1
            if saves == 1 {
                await gate.wait()
            }
            return true
        }
        scheduler.noteChange()
        clock.advance(by: .seconds(1))
        await settle()
        #expect(scheduler.isSaving)
        scheduler.noteChange()
        scheduler.noteChange()
        gate.open()
        await settle()
        #expect(saves == 1)
        clock.advance(by: .seconds(1))
        await settle()
        #expect(saves == 2)
        clock.advance(by: .seconds(10))
        await settle()
        #expect(saves == 2)
    }

    @Test
    func `a conflict pauses autosave and says not saved`() async {
        let clock = ManualTestClock()
        var attempts = 0
        let editor = SongEditorViewModel(
            mode: .edit(SongID(ULID(milliseconds: 1, randomness: Array(repeating: 1, count: 10)))),
            source: "{title: Shared}\n",
            autosave: AutosaveTiming(time: AutosaveTimeSource(clock)),
        ) { _ in
            attempts += 1
            throw LibraryError.conflict(
                SongID(ULID(milliseconds: 1, randomness: Array(repeating: 1, count: 10))),
                .sourceChanged,
            )
        }
        editor.sourceTextDidChange("{title: Shared}\nMine\n")
        #expect(editor.saveState == .saved)
        clock.advance(by: .seconds(1))
        await settle()
        #expect(attempts == 1)
        #expect(editor.conflict == .sourceChanged)
        #expect(editor.saveState == .notSaved)
        #expect(editor.needsFlush)

        editor.sourceTextDidChange("{title: Shared}\nMine, more\n")
        clock.advance(by: .seconds(10))
        await settle()
        #expect(await !editor.flush())
        #expect(attempts == 1)
    }

    @Test
    func `a clean editor follows an external edit, an edited one keeps its text`() async throws {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        let song = try await library.createSong(source: "{title: Shared}\nOriginal\n")
        library.beginEditing(song)
        let editor = try #require(library.editor)

        try env.write("{title: Shared}\nFrom another app\n", to: song.relativePath)
        await library.refresh()

        #expect(library.editor === editor)
        #expect(editor.source == "{title: Shared}\nFrom another app\n")
        #expect(!editor.hasUnsavedChanges)
        #expect(editor.saveState == .saved)
        // And saving from there is not a conflict.
        editor.sourceTextDidChange("{title: Shared}\nFrom another app, and me\n")
        #expect(await library.flushEditor())
        #expect(try env.read(song.relativePath) == "{title: Shared}\nFrom another app, and me\n")

        // With an unsaved edit the file is not reloaded into the editor.
        editor.sourceTextDidChange("{title: Shared}\nUnsaved\n")
        try env.write("{title: Shared}\nTheirs\n", to: song.relativePath)
        await library.refresh()
        #expect(editor.source == "{title: Shared}\nUnsaved\n")
    }

    @Test
    func `a new song is created on its first save and follows its title until done`() async throws {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        library.beginNewSong()
        let editor = try #require(library.editor)

        editor.sourceTextDidChange("{title: Ha}\n")
        #expect(await library.flushEditor())
        let id = try #require(library.selection)
        #expect(editor.mode == .edit(id))
        #expect(library.editor === editor)
        #expect(env.exists("songs/ha.cho"))

        editor.sourceTextDidChange("{title: Harbour}\n")
        #expect(await library.flushEditor())
        await library.finishEditing()

        #expect(!env.exists("songs/ha.cho"))
        #expect(try env.read("songs/harbour.cho") == "{title: Harbour}\n")
        #expect(library.song(id: id)?.relativePath == "songs/harbour.cho")
        #expect(library.editor == nil)
    }

    @Test
    func `blank text on done creates nothing`() async throws {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        library.beginNewSong()
        library.editor?.sourceTextDidChange("  \n")
        await library.finishEditing()
        #expect(library.catalog.isEmpty)
        #expect(library.editor == nil)
    }
}

/// Lets woken tasks (timers, saves) run to their next suspension.
@MainActor
func settle() async {
    for _ in 0 ..< 40 {
        await Task.yield()
    }
}

/// A one-shot latch a save can wait on.
@MainActor
final class Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

/// A `Clock` that only moves when told to.
final class ManualTestClock: _Concurrency.Clock, Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Self {
            Self(offset: offset + duration)
        }

        func duration(to other: Self) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private struct Sleeper {
        var deadline: Instant
        var continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var nextID = 0
        var sleepers: [Int: Sleeper] = [:]
        var cancelled: Set<Int> = []
    }

    private let state = Mutex(State())

    var now: Instant {
        state.withLock { $0.now }
    }

    var minimumResolution: Duration {
        .zero
    }

    func sleep(until deadline: Instant, tolerance _: Duration?) async throws {
        let id = state.withLock { state in
            state.nextID += 1
            return state.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let resume: Result<Void, any Error>? = state.withLock { state in
                    if state.cancelled.contains(id) {
                        return .failure(CancellationError())
                    }
                    if deadline <= state.now {
                        return .success(())
                    }
                    state.sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                    return nil
                }
                if let resume {
                    continuation.resume(with: resume)
                }
            }
        } onCancel: {
            let sleeper = state.withLock { state in
                state.cancelled.insert(id)
                return state.sleepers.removeValue(forKey: id)
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    func advance(by duration: Duration) {
        let due = state.withLock { state in
            state.now = state.now.advanced(by: duration)
            let now = state.now
            let due = state.sleepers.filter { $0.value.deadline <= now }
            for id in due.keys {
                state.sleepers[id] = nil
            }
            return due.values.map(\.continuation)
        }
        due.forEach { $0.resume() }
    }
}
