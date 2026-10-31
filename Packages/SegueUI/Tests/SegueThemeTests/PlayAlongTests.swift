import Editing
import Foundation
import Library
import MusicTheory
import Playback
@testable import SegueUI
import Testing

/// Play along in the editor and library (P8-6 10.3, 15.2) through the real editor, store and
/// timeline, on the scripted clock with a recording output: count-in then events, voices,
/// seamless section loops, timing corrections in the sidecar with undo, the rule menu, the
/// tempo control, the preview cue, song switches and the fill hook.
@MainActor
@Suite(.serialized)
struct PlayAlongTests {
    /// Two sections at 120 BPM: a bar is 2 s, each chord one bar.
    static let song = """
    {title: Harbour}
    {key: G}
    {tempo: 120}

    {start_of_verse}
    [G]Hello there [C]my friend
    {end_of_verse}

    {start_of_chorus}
    [D]Sing it [G]out
    {end_of_chorus}

    """

    struct Opened {
        var env: TestEnvironment
        var rig: SoundRig
        var library: LibraryViewModel
        var editor: SongEditorViewModel
        var song: SongRecord
        var playAlong: PlayAlong
        var recorder: RecordingAnalytics
    }

    private func open(
        _ source: String = Self.song,
        walkUps: WalkUpDensity? = nil,
    ) async throws -> Opened {
        let env = try TestEnvironment()
        let recorder = RecordingAnalytics(env)
        let rig = SoundRig(env, services: recorder.hub)
        rig.session.settings.update { $0.chordStyle = .block }
        let library = try await env.openLibrary()
        library.sound = rig.session
        if let walkUps {
            let instrument = InstrumentProfileStore(defaults: env.defaults)
            instrument.setWalkUps(walkUps)
            library.instrument = instrument
        }
        let song = try await library.createSong(source: source)
        library.beginEditing(song)
        let editor = try #require(library.editor)
        try await AISettingsTests.waitUntil(timeout: .seconds(30)) { editor.renderModel != nil }
        let playAlong = try #require(editor.playAlong)
        playAlong.setOpen(true)
        playAlong.update(editor.playAlongSource)
        return Opened(
            env: env,
            rig: rig,
            library: library,
            editor: editor,
            song: song,
            playAlong: playAlong,
            recorder: recorder,
        )
    }

    /// Moves the scripted clock in 0.1 s steps, pumping the player and the playhead.
    private func run(_ opened: Opened, for seconds: Double) {
        for _ in 0 ..< Int((seconds * 10).rounded()) {
            opened.env.clock.advance(by: 0.1)
            opened.rig.session.player?.pump()
            opened.playAlong.tick()
        }
    }

    private var origin: TimeInterval {
        Date(timeIntervalSinceReferenceDate: 0).timeIntervalSinceReferenceDate
    }

    /// (voice, note, seconds after `start`) of every event handed out.
    private func played(
        _ opened: Opened,
        from start: TimeInterval,
    ) -> [RecordingSoundOutput.Played] {
        (opened.rig.outputs.last?.played ?? []).map { played in
            var played = played
            played.at = ((played.at - start) * 1000).rounded() / 1000
            return played
        }
    }

    private func bassNotes(_ opened: Opened, from start: TimeInterval) -> [String] {
        played(opened, from: start).filter { $0.event.voice == .bass }
            .map { "\($0.event.note)@\($0.at)" }
    }

    private func now(_ opened: Opened) -> TimeInterval {
        opened.env.clock.now().timeIntervalSinceReferenceDate
    }

    @Test
    func `play counts in one bar, then bass chords and click, and the song stops at its end`()
        async throws
    {
        let opened = try await open()
        let start = now(opened)
        opened.playAlong.play()
        #expect(opened.playAlong.isPlaying)
        #expect(opened.recorder.features == ["playAlong"])
        run(opened, for: 12)
        let events = played(opened, from: start)
        let clicks = events.filter {
            if case .click = $0.event.voice {
                return true
            }
            return false
        }
        // The count-in's four clicks, then a click on every beat of four bars.
        #expect(clicks.count == 4 + 16)
        #expect(clicks.first?.event.voice == .click(.downbeat))
        // Roots on beats 1 and 3 from 2 s (after the count-in): G G C C D D G G.
        #expect(bassNotes(opened, from: start) == [
            "31@2.0", "31@3.0", "36@4.0", "36@5.0", "38@6.0", "38@7.0", "31@8.0", "31@9.0",
        ])
        #expect(events.contains { $0.event.voice == .chord && $0.at == 2 })
        #expect(!opened.playAlong.isPlaying)
        // Play again after the end starts it over.
        opened.playAlong.play()
        #expect(opened.playAlong.isPlaying)
    }

    @Test
    func `voice toggles filter what plays and are remembered`() async throws {
        let opened = try await open()
        opened.playAlong.setVoice(.chords, false)
        opened.playAlong.setVoice(.click, false)
        #expect(!opened.rig.session.settings.settings.playAlongChords)
        let start = now(opened)
        opened.playAlong.play()
        run(opened, for: 4)
        let events = played(opened, from: start)
        #expect(!events.contains { $0.event.voice == .chord })
        // Only the count-in clicks (the count-in always sounds).
        #expect(events.count { $0.event.voice != .bass } == 4)
    }

    @Test
    func `walk-ups follow the chart's density: Off plays none even with the toggle on`()
        async throws
    {
        // The roots alone: G G C C D D G G from 2 s.
        let roots = [
            "31@2.0",
            "31@3.0",
            "36@4.0",
            "36@5.0",
            "38@6.0",
            "38@7.0",
            "31@8.0",
            "31@9.0",
        ]
        for density in [WalkUpDensity.off, .sections] {
            let opened = try await open(walkUps: density)
            opened.playAlong.setVoice(.walkUps, true)
            #expect(opened.playAlong.voices.contains(.walkUps) == (density != .off))
            let start = now(opened)
            opened.playAlong.play()
            run(opened, for: 10)
            let bass = bassNotes(opened, from: start)
            if density == .off {
                #expect(bass == roots)
            } else {
                // Into the chorus, the C bar walks up to D (R170: no fallback when Off).
                #expect(bass != roots)
            }
        }
    }

    @Test
    func `a section loops seamlessly with one count-in at the start`() async throws {
        let opened = try await open()
        opened.playAlong.setRange(.section(1))
        #expect(opened.playAlong.loops)
        opened.playAlong.setVoice(.chords, false)
        opened.playAlong.setVoice(.click, false)
        let start = now(opened)
        opened.playAlong.play()
        run(opened, for: 2 + 4 * 3 - 0.5)
        // The chorus (D G) three times from 2 s, no gap at the wraps.
        #expect(bassNotes(opened, from: start) == [
            "38@2.0", "38@3.0", "31@4.0", "31@5.0",
            "38@6.0", "38@7.0", "31@8.0", "31@9.0",
            "38@10.0", "38@11.0", "31@12.0", "31@13.0",
        ])
        let clicks = played(opened, from: start).count { $0.event.voice != .bass }
        #expect(clicks == 4)
        #expect(opened.playAlong.isPlaying)
        opened.playAlong.setOpen(false)
        #expect(!opened.playAlong.isPlaying)
    }

    @Test
    func `the playhead's chord is cued in the preview`() async throws {
        let opened = try await open()
        opened.playAlong.play()
        run(opened, for: 1)
        #expect(opened.playAlong.cue == nil)
        run(opened, for: 1.5)
        #expect(opened.playAlong.cue?.text == "G")
        run(opened, for: 2)
        let cue = try #require(opened.playAlong.cue)
        #expect(cue.text == "C")
        #expect(cue.row.hasSuffix(".0"))
        #expect(opened.playAlong.transportValue == "Playing Verse, bar 2 of 4")
    }

    @Test
    func `a lane edit writes the sidecar, plays from the next bar and undoes`() async throws {
        let opened = try await open()
        let cho = try opened.env.read(opened.song.relativePath)
        opened.playAlong.setVoice(.chords, false)
        opened.playAlong.setVoice(.click, false)
        let start = now(opened)
        opened.playAlong.play()
        run(opened, for: 2.5)
        // While G plays, C becomes two beats: from the next bar (4 s) the new lengths play.
        opened.playAlong.setBeats(1, 2)
        opened.playAlong.update(opened.editor.playAlongSource)
        #expect(opened.recorder.features == ["playAlong", "playAlongTiming"])
        run(opened, for: 6)
        #expect(bassNotes(opened, from: start).prefix(6) == [
            "31@2.0", "31@3.0", "36@4.0", "38@5.0", "38@6.0", "31@7.0",
        ])
        await opened.editor.bassTask?.value
        #expect(try opened.env.read(opened.song.relativePath) == cho)
        let saved = try #require(try await opened.library.store.song(id: opened.song.id))
        #expect(saved.sidecar.bass.timing.chords.map(\.beats) == [2])
        #expect(opened.playAlong.correction(of: 1) != nil)

        opened.editor.sourceEditor.undoManager.undo()
        await opened.editor.bassTask?.value
        let undone = try #require(try await opened.library.store.song(id: opened.song.id))
        #expect(undone.sidecar.bass.timing.chords.isEmpty)
    }

    @Test
    func `the timing menu sets the rule and resets corrections`() async throws {
        let opened = try await open()
        opened.playAlong.setRule(.each(.halfBar))
        opened.playAlong.update(opened.editor.playAlongSource)
        #expect(opened.playAlong.timeline.timeline.chords.map(\.length) == [960, 960, 960, 960])
        opened.playAlong.setBeats(0, 3)
        opened.playAlong.update(opened.editor.playAlongSource)
        #expect(opened.playAlong.sectionHasCorrections)
        opened.playAlong.resetAllCorrections()
        opened.playAlong.update(opened.editor.playAlongSource)
        #expect(opened.editor.bassPrefs.timing.chords.isEmpty)
        #expect(opened.editor.bassPrefs.timing.rule == .each(.halfBar))
        // One bar per chord is the default and is saved as no rule.
        opened.playAlong.setRule(.each(.bar))
        #expect(opened.editor.bassPrefs.timing.rule == nil)
    }

    @Test
    func `the tempo control scales onsets and is never saved`() async throws {
        let opened = try await open()
        #expect(opened.playAlong.tempo == 120)
        #expect(opened.playAlong.tempoHint == nil)
        opened.playAlong.setTempo(percent: 0.5)
        #expect(opened.playAlong.tempo == 60)
        opened.playAlong.setVoice(.chords, false)
        opened.playAlong.setVoice(.click, false)
        let start = now(opened)
        opened.playAlong.play()
        run(opened, for: 6)
        // A bar is 4 s at 60: the count-in ends at 4 s, beat 3 at 6 s.
        #expect(bassNotes(opened, from: start).prefix(2) == ["31@4.0", "31@6.0"])
        #expect(!opened.editor.snapshot.text.contains("{tempo: 60}"))
    }

    @Test
    func `without a tempo it plays at 90 and says so`() async throws {
        let opened = try await open(Self.song.replacingOccurrences(of: "{tempo: 120}\n", with: ""))
        #expect(opened.playAlong.tempo == 90)
        #expect(opened.playAlong.tempoHint == "No tempo in this song: playing at 90")
    }

    @Test
    func `a fill from the hook replaces the bass line over its region`() async throws {
        let opened = try await open()
        opened.playAlong.fillProvider = { _ in
            [PlayAlongFill(region: 960 ..< 1920, notes: [
                PlayAlongFill.Note(tick: 960, length: 960, midi: 40),
            ])]
        }
        opened.playAlong.setRange(.section(0))
        opened.playAlong.setLoops(false)
        opened.playAlong.setVoice(.chords, false)
        opened.playAlong.setVoice(.click, false)
        let start = now(opened)
        opened.playAlong.play()
        run(opened, for: 6.5)
        #expect(bassNotes(opened, from: start) == ["31@2.0", "40@3.0", "36@4.0", "36@5.0"])
    }

    @Test
    func `another song in the library stops play-along`() async throws {
        let opened = try await open()
        opened.library.closeEditor()
        let other = try await opened.library.createSong(source: "{title: Other}\n[A]la\n")
        let first = try #require(opened.library.song(id: opened.song.id))
        let library = try #require(opened.library.playAlong)
        library.setOpen(true)
        opened.library.showPlayAlong(first, render: SongSummary.renderModel(first))
        library.play()
        #expect(library.isPlaying)
        let second = try #require(opened.library.song(id: other.id))
        opened.library.showPlayAlong(second, render: SongSummary.renderModel(second))
        #expect(!library.isPlaying)
        #expect(library.timeline.timeline.chords.map(\.token) == ["A"])
    }
}
