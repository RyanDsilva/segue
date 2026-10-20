import AppKit
import Foundation
import Library
import LiveLayout
@testable import SegueUI
import Setlists
import Shows
import Support
import Synchronization
import Testing

/// The stage metronome (R90, R108, P3-14) through the real app: show engine, stores and
/// stage session on a temp library, the manual clock as the stage clock, and a recording
/// click output.
extension StageWindowSuites {
    @MainActor
    @Suite(.serialized)
    struct StageMetronomeTests {
        // MARK: Pulse

        @Test
        func `the pulse follows the song's tempo, M, breaks and songs without a tempo`(
        ) async throws {
            let run = try await MetronomeRun(
                songs: [
                    "{title: Waltz}\n{tempo: 90}\n{time: 3/4}\n[G]One two three\n",
                    "{title: Free}\n[G]No tempo here\n",
                    "{title: Shuffle}\n{tempo: 120}\n[G]After the break\n",
                ],
                breakBefore: 2,
            )
            run.app.liveSettings.metronomeOn = true
            let live = try await run.start(.gig)
            let metronome = live.metronome
            #expect(metronome.isOn)
            #expect(metronome.showsPulse)
            let waltz = try #require(metronome.track)
            #expect(waltz.bpm == 90)
            #expect(waltz.meter.beats == 3)
            #expect(waltz.start == run.env.clock.now())
            run.env.clock.advance(by: 1)
            #expect(waltz.beat(at: run.env.clock.now()).beatInBar == 2)

            // M hides it and brings it back on beat 1 now.
            live.dispatch(.toggleMetronome)
            #expect(!metronome.showsPulse)
            run.env.clock.advance(by: 0.4)
            live.dispatch(.toggleMetronome)
            #expect(metronome.showsPulse)
            #expect(metronome.track?.start == run.env.clock.now())

            // A song without {tempo}: nothing to show (R108).
            live.dispatch(.next)
            _ = try await run.env.waitFor { live.positionText == "2 of 3" ? true : nil }
            #expect(metronome.track == nil)
            #expect(!metronome.showsPulse)

            // The break interstitial: no pulse.
            live.dispatch(.next)
            _ = try await run.env.waitFor { live.state.record.currentBreak != nil ? true : nil }
            #expect(!metronome.showsPulse)

            // The next part's song: a new grid from beat 1.
            run.env.clock.advance(by: 5)
            live.dispatch(.next)
            _ = try await run.env.waitFor { live.state.record.currentBreak == nil ? true : nil }
            let shuffle = try #require(metronome.track)
            #expect(shuffle.bpm == 120)
            #expect(shuffle.meter == .common)
            #expect(shuffle.start == run.env.clock.now())
            #expect(metronome.showsPulse)
            try await run.end(live)
        }

        @Test
        func `the checklist's choice is remembered as the next show's default`() async throws {
            let run = try await MetronomeRun(songs: ["{title: A}\n{tempo: 100}\n[G]La\n"])
            #expect(!run.app.liveSettings.metronomeOn)
            let checklist = PreShowChecklist(
                setlistName: "Set",
                kind: .gig,
                missingPositions: [],
                performableCount: 1,
                focus: .notConfigured,
                settings: run.app.liveSettings,
                power: FixedPowerSource(onCharger: true),
                clock: run.env.clock,
            )
            #expect(!checklist.offersClick)
            checklist.metronomeOn = true
            #expect(LiveSettingsStore(defaults: run.env.defaults).metronomeOn)
            let live = try await run.start(.gig)
            #expect(live.metronome.isOn)
            // M on stage is for this show only.
            live.dispatch(.toggleMetronome)
            #expect(!live.metronome.isOn)
            #expect(run.app.liveSettings.metronomeOn)
            try await run.end(live)
        }

        // MARK: Sound

        @Test
        func `a gig never constructs the audio path, whatever the settings say`() async throws {
            let run = try await MetronomeRun(songs: ["{title: A}\n{tempo: 100}\n[G]La\n"])
            run.app.liveSettings.metronomeOn = true
            run.app.liveSettings.rehearsalClickOn = true
            let live = try await run.start(.gig)
            #expect(live.metronome.click == nil)
            #expect(!live.metronome.clicks)
            live.dispatch(.toggleMetronomeClick)
            #expect(live.metronome.click == nil)
            #expect(!live.metronome.clicks)
            run.env.clock.advance(by: 10)
            live.dispatch(.next)
            try await run.end(live)
            #expect(run.outputs.made == 0)
        }

        @Test
        func `a rehearsal clicks on the beat grid and stops at once`() async throws {
            let run = try await MetronomeRun(songs: [
                "{title: A}\n{tempo: 120}\n{time: 3/4}\n[G]La\n",
                "{title: B}\n{tempo: 60}\n[G]Lo\n",
            ])
            // Off by default: a rehearsal starts silent.
            #expect(!run.app.liveSettings.rehearsalClickOn)
            let live = try await run.start(.rehearsal)
            let metronome = live.metronome
            let click = try #require(metronome.click)
            #expect(!metronome.clicks)
            #expect(run.outputs.made == 0)

            // Shift-M: clicks every 0.5 s with beat 1 of each 3/4 bar accented, handed over
            // `lookahead` ahead on the stage clock.
            live.dispatch(.toggleMetronomeClick)
            #expect(metronome.clicks)
            let output = try #require(run.outputs.last)
            #expect(output.events.map(\.beat) == [0])
            for _ in 0 ..< 10 {
                run.env.clock.advance(by: 0.1)
                click.pump()
            }
            let events = output.events
            #expect(events.map(\.beat) == Array(0 ... 2))
            #expect(events.map(\.accent) == [.downbeat, .plain, .plain])
            // Each click's delay puts it on its beat: beat n at n * 0.5 s.
            let offsets = events.map { $0.at - events[0].at }
            #expect(zip(offsets, [0, 0.5, 1.0]).allSatisfy { abs($0 - $1) < 1e-6 })
            #expect(Set(events.map(\.beat)).count == events.count)

            // A song change silences the queue and restarts on beat 1 of the new song.
            live.dispatch(.next)
            _ = try await run.env.waitFor { live.positionText == "2 of 2" ? true : nil }
            #expect(output.stops >= 1)
            let after = output.events.dropFirst(events.count)
            #expect(after.first?.beat == 0)
            #expect(after.first?.accent == .downbeat)

            // Shift-M again: silent at once.
            let stops = output.stops
            live.dispatch(.toggleMetronomeClick)
            #expect(output.stops == stops + 1)
            #expect(!metronome.clicks)
            run.env.clock.advance(by: 2)
            click.pump()
            #expect(output.events.count == events.count + after.count)

            // End stops it too.
            live.dispatch(.toggleMetronomeClick)
            let beforeEnd = output.stops
            try await run.end(live)
            #expect(output.stops > beforeEnd)
            #expect(run.outputs.made == 1)
        }

        // MARK: Keys

        @Test
        func `m and Shift-M reach the metronome and a shifted letter still means the letter`(
        ) throws {
            func command(
                _ characters: String,
                keyCode: UInt16,
                shift: Bool,
            ) throws -> LiveCommand? {
                let event = try #require(NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: shift ? .shift : [],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: characters,
                    charactersIgnoringModifiers: characters,
                    isARepeat: false,
                    keyCode: keyCode,
                ))
                let stroke = try #require(LiveKeyInput.keyStroke(event))
                return InputBindingTable.defaults.command(for: .key(stroke))
            }
            #expect(try command("m", keyCode: 46, shift: false) == .toggleMetronome)
            #expect(try command("M", keyCode: 46, shift: true) == .toggleMetronomeClick)
            // Shift with any other letter still means the letter; "?" carries its Shift.
            #expect(try command("A", keyCode: 0, shift: true) == .toggleAutoScroll)
            #expect(try command("?", keyCode: 44, shift: true) == .showKeys)
            #expect(try command("K", keyCode: 40, shift: true) == nil)
            let help = KeyHelp.groups(.defaults).first { $0.title == "Metronome" }
            #expect(help?.rows.map(\.keys) == [["M"], ["⇧M"]])
        }
    }
}

/// A recording click output: what was scheduled, relative to the stage clock.
final class RecordingClickOutput: MetronomeClickOutput, @unchecked Sendable {
    struct Event: Equatable {
        var beat: Int
        var accent: MetronomeAccent
        /// The stage clock's time of the click (seconds since the reference date).
        var at: TimeInterval
    }

    private let clock: any Clock
    private let state = Mutex<(events: [Event], stops: Int)>(([], 0))

    init(clock: any Clock) {
        self.clock = clock
    }

    var events: [Event] {
        state.withLock { $0.events }
    }

    var stops: Int {
        state.withLock { $0.stops }
    }

    func schedule(_ accent: MetronomeAccent, beat: Int, in delay: TimeInterval) {
        let at = clock.now().timeIntervalSinceReferenceDate + delay
        state.withLock {
            $0.events.append(Event(beat: beat, accent: accent, at: at))
        }
    }

    func stop() {
        state.withLock { $0.stops += 1 }
    }
}

/// Every click output the app made.
@MainActor
final class ClickOutputs {
    private(set) var all: [RecordingClickOutput] = []
    var made: Int {
        all.count
    }

    var last: RecordingClickOutput? {
        all.last
    }

    func make(_ clock: any Clock) -> RecordingClickOutput {
        let output = RecordingClickOutput(clock: clock)
        all.append(output)
        return output
    }
}

/// An app on a temp library with a setlist of `songs` (and a break before `breakBefore`),
/// whose click outputs are recorded.
@MainActor
struct MetronomeRun {
    let env: TestEnvironment
    let app: AppModel
    let outputs = ClickOutputs()
    let setlist: Setlist

    init(songs: [String], breakBefore: Int? = nil) async throws {
        _ = NSApplication.shared
        env = try TestEnvironment()
        var dependencies = env.dependencies(
            location: env.location(),
            override: env.libraryURL,
            remember: false,
        )
        let outputs = outputs
        let clock = env.clock
        dependencies.live.makeClickOutput = { outputs.make(clock) }
        app = AppModel(dependencies: dependencies)
        await app.start()
        let session = try #require(app.session)
        app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
        let created = try #require(await session.setlists.create(name: "Metronome Set"))
        for source in songs {
            let song = try await session.library.createSong(source: source)
            await session.setlists.add(song.id, to: created.id)
        }
        if let breakBefore {
            _ = try await session.stores.setlists.insertBreak(into: created.id, at: breakBefore)
        }
        setlist = try #require(await session.stores.setlists.setlist(id: created.id))
    }

    func start(_ kind: ShowKind) async throws -> LiveSession {
        #expect(await app.startShow(setlist, kind: kind))
        let live = try #require(app.live)
        live.setViewport(LayoutSize(width: 1390, height: 700))
        return live
    }

    func end(_ live: LiveSession) async throws {
        live.dispatch(.endShow)
        live.confirmEnd()
        _ = try await env.waitFor { app.live == nil ? true : nil }
    }
}
