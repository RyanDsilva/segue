import Editing
import Foundation
import Library
import MusicTheory
import Playback
@testable import SegueUI
import Testing

/// Tap Timing (P8-7 sections 7, 16.3) through the real editor, store and timeline, on the
/// scripted clock with a recording output: the count-in and click, taps to proposed lengths,
/// nothing written before Keep, Keep as one sidecar write with `source: "tap"` and one undo
/// step, Discard, Tab, Esc, the tempo from the taps and the explicit `{tempo}` write, and the
/// gig gate.
@MainActor
@Suite(.serialized)
struct TapCaptureTests {
    /// Four chords at 120 BPM in 4/4: a beat is 0.5 s, each chord one bar by the rule.
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
        var tap: TapCapture
        var recorder: RecordingAnalytics

        /// Row 27's events as (outcome, mode, chords) strings.
        var captures: [String] {
            recorder.log.entries().filter { $0["name"] as? String == "Segue.Timing.tapCaptured" }
                .compactMap { $0["params"] as? [String: String] }
                .map { params in
                    ["segue.outcome", "segue.mode", "segue.chords"]
                        .map { params[$0] ?? "" }.joined(separator: " ")
                }
        }
    }

    private func open(_ source: String = Self.song) async throws -> Opened {
        let env = try TestEnvironment()
        let recorder = RecordingAnalytics(env)
        let rig = SoundRig(env, services: recorder.hub)
        let library = try await env.openLibrary()
        library.sound = rig.session
        let song = try await library.createSong(source: source)
        library.beginEditing(song)
        let editor = try #require(library.editor)
        editor.sourceEditor.undoManager.groupsByEvent = false
        try await AISettingsTests.waitUntil(timeout: .seconds(30)) { editor.renderModel != nil }
        let playAlong = try #require(editor.playAlong)
        playAlong.setOpen(true)
        playAlong.update(editor.playAlongSource)
        playAlong.beginTapCapture()
        let tap = try #require(playAlong.tap)
        return Opened(
            env: env,
            rig: rig,
            library: library,
            editor: editor,
            song: song,
            playAlong: playAlong,
            tap: tap,
            recorder: recorder,
        )
    }

    /// Moves the scripted clock, pumping the player.
    private func wait(_ opened: Opened, _ seconds: Double) {
        for _ in 0 ..< Int((seconds * 20).rounded()) {
            opened.env.clock.advance(by: 0.05)
            opened.rig.session.player?.pump()
        }
    }

    /// Taps after each of `gaps` seconds (the first tap after `gaps[0]`).
    private func taps(_ opened: Opened, _ gaps: [Double]) {
        for gap in gaps {
            wait(opened, gap)
            opened.tap.tap()
        }
    }

    /// One gesture: one undo group, as one event in the app.
    private func gesture(_ opened: Opened, _ action: () -> Void) {
        let undo = opened.editor.sourceEditor.undoManager
        undo.beginUndoGrouping()
        action()
        undo.endUndoGrouping()
        opened.playAlong.update(opened.editor.playAlongSource)
    }

    private func saved(_ opened: Opened) async throws -> SongRecord {
        await opened.editor.bassTask?.value
        return try #require(try await opened.library.store.song(id: opened.song.id))
    }

    @Test
    func `with the click it counts in, clicks, and taps become proposed lengths`() async throws {
        let opened = try await open()
        #expect(opened.tap.mode == .click)
        #expect(opened.tap.waitingFor == "Done")
        // The first Space starts the count-in (one bar at 120: 2 s).
        opened.tap.tap()
        #expect(opened.tap.phase == .tapping)
        #expect(opened.tap.taps == 0)
        wait(opened, 1.1)
        #expect(opened.tap.countInBeat() == 3)
        // G on the downbeat, C two beats later, D after three, G after four, then the end.
        taps(opened, [0.9, 1.0, 1.5, 2.0, 2.0])
        #expect(opened.tap.phase == .review)
        let played = opened.rig.outputs.last?.played ?? []
        let clicks = played.filter {
            if case .click = $0.event.voice {
                return true
            }
            return false
        }
        // Four count-in clicks and a click on every beat since; no chords or bass.
        #expect(clicks.count >= 4 + 12)
        #expect(!played.contains { $0.event.voice == .bass || $0.event.voice == .chord })
        #expect(opened.rig.session.player?.isPlaying == false)
        let proposal = try #require(opened.tap.proposal)
        #expect(proposal.chords.map(\.new) == [960, 1440, 1920, 1920])
        #expect(proposal.chords.map(\.outcome) == [.changed, .changed, .unchanged, .unchanged])
        #expect(opened.tap.reviewSummary == "2 chords changed")
        // Nothing is written before Keep.
        #expect(opened.editor.bassPrefs.timing.chords.isEmpty)
        #expect(try await saved(opened).sidecar.bass.timing.chords.isEmpty)
    }

    @Test
    func `keep writes the changed chords as tapped corrections in one undo step`() async throws {
        let opened = try await open()
        let cho = try opened.env.read(opened.song.relativePath)
        opened.tap.tap()
        taps(opened, [2.0, 1.0, 1.5, 2.0, 2.0])
        gesture(opened) { opened.tap.keep() }
        #expect(opened.playAlong.tap == nil)
        let corrections = try await saved(opened).sidecar.bass.timing.chords
        #expect(corrections.map(\.ticks) == [960, 1440])
        #expect(corrections.allSatisfy { $0.source == .tap })
        #expect(opened.playAlong.timeline.timeline.chords.map(\.source).prefix(3) == [
            .tap, .tap, .rule,
        ])
        #expect(try opened.env.read(opened.song.relativePath) == cho)
        #expect(opened.recorder.features.contains("timingTap"))
        #expect(opened.captures == ["kept click 2-4"])
        opened.editor.sourceEditor.undoManager.undo()
        #expect(try await saved(opened).sidecar.bass.timing.chords.isEmpty)
    }

    @Test
    func `discard and esc write nothing`() async throws {
        let opened = try await open()
        opened.tap.tap()
        taps(opened, [2.0, 1.0])
        // Esc stops into the review; nothing is saved.
        opened.tap.stop()
        #expect(opened.tap.phase == .review)
        #expect(opened.tap.proposal?.changed.count == 1)
        opened.tap.discard()
        #expect(opened.playAlong.tap == nil)
        #expect(opened.captures == ["discarded click 0"])
        #expect(try await saved(opened).sidecar.bass.timing.chords.isEmpty)
        // Esc before any tap closes the panel.
        opened.playAlong.beginTapCapture()
        let again = try #require(opened.playAlong.tap)
        again.tap()
        again.stop()
        #expect(opened.playAlong.tap == nil)
    }

    @Test
    func `tab skips a chord, which keeps its length`() async throws {
        let opened = try await open()
        opened.tap.tap()
        wait(opened, 2.0)
        opened.tap.tap()
        #expect(opened.tap.waitingFor == "Next: C, chord 2 of 4")
        opened.tap.skip()
        #expect(opened.tap.waitingFor == "Next: D, chord 3 of 4")
        // G for two beats, then C's four, then D starts.
        taps(opened, [3.0])
        opened.tap.stop()
        let proposal = try #require(opened.tap.proposal)
        #expect(proposal.chords.map(\.outcome) == [.changed, .skipped, .untapped, .untapped])
        #expect(proposal.chords[0].new == 960)
        #expect(opened.tap.reviewSummary == "1 chord changed, 1 skipped")
    }

    @Test
    func `without the click the tempo comes from the taps and is written only when asked`()
        async throws
    {
        let opened = try await open(Self.song.replacingOccurrences(of: "{tempo: 120}\n", with: ""))
        opened.tap.setMode(.free)
        // Nothing sounds; the first tap starts G. Bars of four at 96 BPM (2.5 s).
        opened.tap.tap()
        #expect(opened.tap.taps == 1)
        taps(opened, [2.55, 2.45, 2.5, 2.5])
        #expect(opened.tap.phase == .review)
        #expect(opened.rig.outputs.last?.played.isEmpty ?? true)
        #expect(opened.tap.proposal?.tempo == 96)
        #expect(opened.tap.proposal?.changed.isEmpty == true)
        #expect(opened.tap.offersSongTempo)
        // -/+ re-quantises; halving makes every chord two beats.
        opened.tap.setReviewTempo(48)
        #expect(opened.tap.proposal?.chords.map(\.new) == [960, 960, 960, 960])
        opened.tap.setReviewTempo(96)
        let before = try opened.env.read(opened.song.relativePath)
        #expect(!before.contains("{tempo"))
        gesture(opened) { opened.tap.setSongTempo() }
        #expect(opened.tap.tempoSet)
        #expect(opened.editor.source.contains("{tempo: 96}"))
        #expect(opened.recorder.features.contains("chartDirective"))
        gesture(opened) { opened.tap.keep() }
        // Equal lengths: nothing to save, and the timing is untouched.
        #expect(try await saved(opened).sidecar.bass.timing.chords.isEmpty)
    }

    @Test
    func `the remembered mode and the gig gate`() async throws {
        let opened = try await open()
        opened.tap.setMode(.free)
        opened.tap.setHalfBeats(true)
        #expect(opened.rig.session.settings.settings.tapMode == .free)
        #expect(opened.rig.session.settings.settings.tapHalfBeats)
        opened.tap.cancel()
        opened.rig.session.gate.gigRunning = true
        #expect(!opened.playAlong.canTapTiming)
        opened.playAlong.beginTapCapture()
        #expect(opened.playAlong.tap == nil)
        opened.rig.session.gate.gigRunning = false
        opened.playAlong.beginTapCapture()
        let tap = try #require(opened.playAlong.tap)
        #expect(tap.mode == .free)
        // A gig starting mid-capture closes the panel without writing.
        tap.tap()
        opened.rig.session.gate.gigRunning = true
        tap.tap()
        #expect(opened.playAlong.tap == nil)
        #expect(try await saved(opened).sidecar.bass.timing.chords.isEmpty)
    }
}
