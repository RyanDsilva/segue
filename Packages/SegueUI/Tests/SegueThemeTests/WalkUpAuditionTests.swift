import Editing
import Foundation
import Library
import MusicTheory
import Playback
@testable import SegueUI
import Testing

/// Auditioning walk-ups in the picker (P8-6 10.2, 15.2) through the real editor: each
/// option plays its own two bars, a new option stops the last, a loop switches options at
/// the next phrase start on the scripted clock, and a pick stops the sound and writes the
/// sidecar only.
@MainActor
@Suite(.serialized)
struct WalkUpAuditionTests {
    static let song = "{title: Harbour}\n{key: G}\n{tempo: 90}\n\n[G]Hello there [C]my friend\n"

    struct Opened {
        var env: TestEnvironment
        var rig: SoundRig
        var editor: SongEditorViewModel
        var song: SongRecord
        var change: ChordChange
        var options: [WalkUpCandidate]
        var listening: WalkUpListening
        var recorder: RecordingAnalytics
    }

    private func open() async throws -> Opened {
        let env = try TestEnvironment()
        let recorder = RecordingAnalytics(env)
        let rig = SoundRig(env, services: recorder.hub)
        rig.session.settings.update { $0.chordStyle = .block }
        let store = InstrumentProfileStore(defaults: env.defaults)
        store.update { $0.bassNotes = true }
        store.setWalkUps(.everyChange)
        let library = try await env.openLibrary()
        library.instrument = store
        library.sound = rig.session
        let song = try await library.createSong(source: Self.song)
        library.beginEditing(song)
        let editor = try #require(library.editor)
        try await AISettingsTests.waitUntil(timeout: .seconds(30)) {
            WalkUpPickerTests.runs(editor.renderModel).first != nil
        }
        let run = try #require(WalkUpPickerTests.runs(editor.renderModel).first)
        let change = try #require(editor.walkUpDetails(run.change)).change
        let options = change.candidates.filter { $0.kind != .hold }
        #expect(options.count >= 2)
        let audition = try #require(editor.walkUpAudition)
        return Opened(
            env: env,
            rig: rig,
            editor: editor,
            song: song,
            change: change,
            options: options,
            listening: WalkUpListening(audition: audition),
            recorder: recorder,
        )
    }

    /// Moves the scripted clock in 0.1 s steps for `seconds`, pumping the player each step.
    private func run(_ opened: Opened, for seconds: Double) {
        for _ in 0 ..< Int((seconds * 10).rounded()) {
            opened.env.clock.advance(by: 0.1)
            opened.rig.session.player?.pump()
        }
    }

    /// The bass notes handed out at or after `from` (seconds since the reference date).
    private func bass(_ opened: Opened, from: TimeInterval = 0) -> [Int] {
        opened.rig.outputs.last?.played
            .filter { $0.event.voice == .bass && $0.at >= from - 1e-6 }
            .map { Int($0.event.note) } ?? []
    }

    private func expected(_ opened: Opened, _ candidate: WalkUpCandidate?) throws -> [Int] {
        let phrase = try #require(opened.listening.audition.phrase(opened.change, candidate))
        return phrase.events.filter { $0.voice == .bass }.map { Int($0.note) }
    }

    @Test
    func `the play button plays that option's two bars once`() async throws {
        let opened = try await open()
        opened.listening.toggle(1, opened.options[1], change: opened.change)
        #expect(opened.listening.isSounding(1))
        run(opened, for: 6)
        #expect(try bass(opened) == expected(opened, opened.options[1]))
        #expect(opened.rig.session.player?.isPlaying == false)
        #expect(opened.recorder.features == ["walkUpAudition"])
        // "Nothing here" plays the change with no walk-up: root on 1 and 3, then C.
        opened.listening.toggle(opened.options.count, nil, change: opened.change)
        run(opened, for: 6)
        #expect(try expected(opened, nil) == [31, 31, 36])
    }

    @Test
    func `playing B while A sounds stops A at once, and Space toggles`() async throws {
        let opened = try await open()
        opened.listening.toggle(0, opened.options[0], change: opened.change)
        opened.listening.toggle(1, opened.options[1], change: opened.change)
        let calls = try #require(opened.rig.outputs.last?.calls)
        let stop = try #require(calls.firstIndex(of: .stopAll))
        #expect(calls[..<stop].contains {
            if case .play = $0 {
                true
            } else {
                false
            }
        })
        #expect(opened.listening.isSounding(1))
        // Space on the sounding option stops it.
        opened.listening.toggle(1, opened.options[1], change: opened.change)
        #expect(!opened.listening.isSounding(1))
        #expect(opened.rig.session.player?.isPlaying == false)
    }

    @Test
    func `while looping a new selection takes over at the next phrase start`() async throws {
        let opened = try await open()
        let start = opened.env.clock.now().timeIntervalSinceReferenceDate
        opened.listening.setLooping(true, { opened.options[$0] }, change: opened.change)
        opened.listening.toggle(0, opened.options[0], change: opened.change)
        let length = try #require(opened.listening.audition.phrase(
            opened.change,
            opened.options[0],
        )).length
        run(opened, for: 1)
        #expect(opened.listening.select(1, opened.options[1], change: opened.change, name: "B"))
        run(opened, for: length * 2)
        let firstPass = try bass(opened).prefix(expected(opened, opened.options[0]).count)
        #expect(try Array(firstPass) == expected(opened, opened.options[0]))
        let secondPass = try bass(opened, from: start + length)
            .prefix(expected(opened, opened.options[1]).count)
        #expect(try Array(secondPass) == expected(opened, opened.options[1]))
        #expect(opened.rig.session.player?.isPlaying == true)
        #expect(opened.rig.outputs.last?.stops == 0) // seamless: nothing was cut
        opened.listening.stop()
    }

    @Test
    func `a pick stops the sound and writes the sidecar only`() async throws {
        let opened = try await open()
        let cho = try opened.env.read(opened.song.relativePath)
        opened.listening.setLooping(true, { opened.options[$0] }, change: opened.change)
        opened.listening.toggle(1, opened.options[1], change: opened.change)
        // Return: the picker stops, then saves the pick (`WalkUpPopover.pick`).
        opened.listening.stop()
        opened.editor.pickWalkUp(opened.change, opened.options[1])
        #expect(opened.rig.session.player?.isPlaying == false)
        #expect(opened.rig.outputs.last?.stops == 1)
        await opened.editor.bassTask?.value
        #expect(try opened.env.read(opened.song.relativePath) == cho)
        let saved = opened.editor.bassPrefs.walkUps
        #expect(saved.map(\.offsets) == [opened.options[1].offsets])
    }
}
