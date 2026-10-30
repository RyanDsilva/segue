import AppKit
import Foundation
import Library
import LiveLayout
@testable import SegueUI
import Setlists
import Shows
import Support
import SwiftUI
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
                    "{title: Jig}\n{tempo: 120}\n{time: 6/8}\n[G]After the break\n",
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
            // 6/8 counts the dotted quarter (R118): 2 pulses per bar at the tempo.
            let jig = try #require(metronome.track)
            #expect(jig.bpm == 120)
            #expect(jig.meter.pulses == 2)
            #expect(jig.start == run.env.clock.now())
            #expect(jig.beat(at: jig.time(ofBeat: 2)).isDownbeat)
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
            #expect(!checklist.rehearsalClickOn)
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
            let live = try await run.start(.gig, checklistClick: true)
            #expect(live.metronome.click == nil)
            #expect(!live.metronome.clicks)
            // K does nothing in a show: no click, no notice.
            live.dispatch(.toggleMetronomeClick)
            #expect(live.metronome.click == nil)
            #expect(!live.metronome.clicks)
            #expect(live.notice == nil)
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
            // A rehearsal starts silent.
            let live = try await run.start(.rehearsal)
            let metronome = live.metronome
            let click = try #require(metronome.click)
            #expect(!metronome.clicks)
            #expect(run.outputs.made == 0)

            // K: clicks every 0.5 s with beat 1 of each 3/4 bar accented, handed over
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

            // K again: silent at once.
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
        func `the checklist's click switch starts that rehearsal clicking, and only that one`(
        ) async throws {
            let run = try await MetronomeRun(songs: ["{title: A}\n{tempo: 100}\n[G]La\n"])
            let live = try await run.start(.rehearsal, checklistClick: true)
            #expect(live.metronome.clicks)
            #expect(run.outputs.made == 1)
            try await run.end(live)
            // The next rehearsal starts silent again (R118).
            let next = try await run.start(.rehearsal, checklistClick: nil)
            #expect(!next.metronome.clicks)
            try await run.end(next)
        }

        // MARK: Overlay

        @Test
        func `the overlay draws only while the pulse is on and the song has a tempo`(
        ) async throws {
            let run = try await MetronomeRun(songs: [
                "{title: A}\n{tempo: 96}\n[G]La\n",
                "{title: B}\n[G]Lo\n",
            ])
            let live = try await run.start(.gig)
            func size() -> CGSize {
                let host = NSHostingView(rootView: StageMetronomeView(metronome: live.metronome))
                host.layoutSubtreeIfNeeded()
                return host.fittingSize
            }
            #expect(size().width == 0)
            live.dispatch(.toggleMetronome)
            #expect(live.indicator == "Metronome on")
            // Four 30 pt pips in 4/4 (R151), beside the tempo.
            #expect(size().width > 4 * StageMetronomeView.pip + 3 * StageMetronomeView.pipSpacing)
            #expect(StageMetronomeView.bpmText(96) == "96")
            #expect(StageMetronomeView.bpmText(92.5) == "92.5")
            #expect(StageMetronomeView.flash(0) == 1)
            #expect(StageMetronomeView.flash(0.45) == 0)
            live.dispatch(.next)
            _ = try await run.env.waitFor { live.positionText == "2 of 2" ? true : nil }
            #expect(size().width == 0)
            try await run.end(live)
        }

        @Test
        func `one pip per pulse of the bar, a numeral past eight pulses`() async throws {
            let run = try await MetronomeRun(songs: [
                "{title: Four}\n{tempo: 96}\n[G]La\n",
                "{title: Three}\n{tempo: 96}\n{time: 3/4}\n[G]La\n",
                "{title: Nine}\n{tempo: 96}\n{time: 9/4}\n[G]La\n",
            ])
            run.app.liveSettings.metronomeOn = true
            let live = try await run.start(.gig)
            func width() -> CGFloat {
                let host = NSHostingView(rootView: StageMetronomeView(metronome: live.metronome))
                host.layoutSubtreeIfNeeded()
                return host.fittingSize.width
            }
            let step = StageMetronomeView.pip + StageMetronomeView.pipSpacing
            let four = width()
            live.dispatch(.next)
            _ = try await run.env.waitFor { live.positionText == "2 of 3" ? true : nil }
            let three = width()
            #expect(abs(four - three - step) < 0.5)
            live.dispatch(.next)
            _ = try await run.env.waitFor { live.positionText == "3 of 3" ? true : nil }
            // 9 pulses: the numeral, narrower than four pips.
            #expect(live.metronome.track?.meter.pulses == 9)
            #expect(width() < three)
            try await run.end(live)
        }

        // MARK: Keys

        @Test
        func `m and K reach the metronome and the help lists them`() throws {
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "k",
                charactersIgnoringModifiers: "k",
                isARepeat: false,
                keyCode: 40,
            ))
            let stroke = try #require(LiveKeyInput.keyStroke(event))
            let table = InputBindingTable.defaults
            #expect(table.command(for: .key(stroke)) == .toggleMetronomeClick)
            #expect(table.command(for: .key(KeyStroke("m"))) == .toggleMetronome)
            #expect(table.command(for: .key(KeyStroke("k", modifiers: .command))) == .openSearch)
            let help = KeyHelp.groups(table).first { $0.title == "Metronome" }
            #expect(help?.rows.map(\.keys) == [["M"], ["K"]])
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
    /// The analytics the app recorded, when `recordsAnalytics`.
    let analytics: RecordingAnalytics?

    init(songs: [String], breakBefore: Int? = nil, recordsAnalytics: Bool = false) async throws {
        _ = NSApplication.shared
        env = try TestEnvironment()
        var dependencies = env.dependencies(
            location: env.location(),
            override: env.libraryURL,
            remember: false,
        )
        analytics = recordsAnalytics ? RecordingAnalytics(env) : nil
        if let analytics {
            dependencies.services = analytics.hub
        }
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

    /// Starts a run. `checklistClick` shows the pre-show checklist and sets its click switch
    /// before Start (nil leaves the switch as the checklist offers it).
    func start(_ kind: ShowKind, checklistClick: Bool? = false) async throws -> LiveSession {
        if checklistClick == false {
            #expect(await app.startShow(setlist, kind: kind))
        } else {
            app.liveSettings.settings.hiddenChecklistItems = []
            let started = Task { await app.startShow(setlist, kind: kind) }
            let checklist = try await env.waitFor { app.preShow }
            if let checklistClick {
                if checklist.offersClick {
                    #expect(!checklist.rehearsalClickOn)
                }
                checklist.rehearsalClickOn = checklistClick
            }
            checklist.answer(true)
            #expect(await started.value)
            app.liveSettings.settings.hiddenChecklistItems = Set(ChecklistItem.allCases)
        }
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
