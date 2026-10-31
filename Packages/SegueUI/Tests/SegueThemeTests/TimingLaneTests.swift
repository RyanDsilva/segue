import Editing
import Foundation
import Library
import MusicTheory
import Playback
@testable import SegueUI
import Testing

/// The chord-length lane's P8-7b edits (P8-7 sections 8, 16.3) through the real editor, store
/// and timeline: snapped drags to eighths and sixteenths, typed sub-beat lengths, the push
/// cycle, edge styles per source, key / time / tempo markers, one undo step per gesture and
/// the shift-click span.
@MainActor
@Suite(.serialized)
struct TimingLaneTests {
    /// Four chords at 120 BPM in 4/4, one bar each by the song's rule.
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
        var library: LibraryViewModel
        var editor: SongEditorViewModel
        var song: SongRecord
        var playAlong: PlayAlong
    }

    private func open(_ source: String = Self.song) async throws -> Opened {
        let env = try TestEnvironment()
        let rig = SoundRig(env)
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
        return Opened(library: library, editor: editor, song: song, playAlong: playAlong)
    }

    /// The bar re-reads the song, as the editor view does after every write.
    private func refresh(_ opened: Opened) {
        opened.playAlong.update(opened.editor.playAlongSource)
    }

    /// One gesture: one undo group, as one event in the app.
    private func gesture(_ opened: Opened, _ action: () -> Void) {
        let undo = opened.editor.sourceEditor.undoManager
        undo.beginUndoGrouping()
        action()
        undo.endUndoGrouping()
        refresh(opened)
    }

    private func lengths(_ opened: Opened) -> [Int] {
        opened.playAlong.timeline.timeline.chords.map(\.length)
    }

    // MARK: Pure rules

    @Test(arguments: [
        // (option, shift, raw ticks, ticks per pulse, snapped)
        (false, false, 1300, 480, 1440),
        (true, false, 1300, 480, 1200),
        (true, true, 1300, 480, 1320),
        (false, false, 100, 480, 480),
        (true, false, 90, 480, 240),
        (false, false, 99999, 480, 32 * 480),
        // 6/8: a pulse is a dotted quarter; ⌥ still snaps to eighths.
        (false, false, 1000, 720, 720),
        (true, false, 1000, 720, 960),
    ])
    func `a dragged edge snaps to beats, eighths with option, sixteenths with option-shift`(
        option: Bool, shift: Bool, raw: Int, pulse: Int, snapped: Int,
    ) {
        #expect(LaneSnap(option: option, shift: shift).snap(raw, ticksPerPulse: pulse) == snapped)
    }

    @Test(arguments: [
        ("3", 1440), ("2.5", 1200), ("2,5", 1200), ("2½", 1200), ("2 ½", 1200),
        ("2 1/2", 1200), ("½", 240), ("3/2", 720), ("1¾", 840), (" 4 ", 1920),
    ])
    func `typed beats parse to ticks`(text: String, ticks: Int) {
        #expect(BeatsText.ticks(text, ticksPerPulse: 480) == ticks)
    }

    @Test(arguments: ["", "0", "-1", "two", "1/0", "2 1/2 3", "inf"])
    func `text that is not a length is refused`(text: String) {
        #expect(BeatsText.ticks(text, ticksPerPulse: 480) == nil)
    }

    @Test(arguments: [(3.0, "3"), (2.5, "2½"), (0.25, "¼"), (1.75, "1¾"), (2.375, "2.38")])
    func `lengths read back as the field shows them`(pulses: Double, text: String) {
        #expect(BeatsText.format(pulses) == text)
    }

    @Test
    func `each source has its own edge`() {
        #expect(LaneEdge(.chart) == .chart)
        #expect(LaneEdge(.grid) == .chart)
        #expect(LaneEdge(.rule) == .estimated)
        #expect(LaneEdge(.user) == .corrected)
        #expect(LaneEdge(.tap) == .tapped)
    }

    // MARK: Through the editor

    @Test
    func `a sub-beat length is stored as ticks and undoes in one step`() async throws {
        let opened = try await open()
        gesture(opened) { #expect(opened.playAlong.setLength(1, text: "2½")) }
        // The range ends on a bar line: the last chord takes up the rest of its bar.
        #expect(lengths(opened) == [1920, 1200, 1920, 2640])
        #expect(opened.playAlong.timeline.timeline.chords[1].source == .user)
        let saved = try #require(opened.editor.bassPrefs.timing.chords.first)
        #expect(saved.ticks == 1200)
        #expect(saved.beats == 3)
        #expect(!opened.playAlong.setLength(1, text: "soon"))
        // A drag to an eighth: one write, one undo step.
        gesture(opened) {
            opened.playAlong.setLength(0, ticks: LaneSnap.eighth.snap(1700, ticksPerPulse: 480))
        }
        #expect(lengths(opened).prefix(2) == [1680, 1200])
        opened.editor.sourceEditor.undoManager.undo()
        refresh(opened)
        #expect(lengths(opened).prefix(2) == [1920, 1200])
        opened.editor.sourceEditor.undoManager.undo()
        refresh(opened)
        #expect(lengths(opened) == [1920, 1920, 1920, 1920])
    }

    @Test
    func `the push cycles an eighth, a sixteenth and none, keeping the length`() async throws {
        let opened = try await open()
        gesture(opened) { opened.playAlong.setLength(2, text: "3") }
        gesture(opened) { opened.playAlong.cyclePush(2) }
        var chords = opened.playAlong.timeline.timeline.chords
        #expect(chords[2].push == .eighth)
        #expect(chords[2].onset == 2 * 1920 - 240)
        #expect(chords[1].length == 1920 - 240)
        // The field still shows the length on the bar grid.
        #expect(opened.playAlong.pulses(of: 2) == 3)
        #expect(opened.playAlong.pulses(of: 1) == 4)
        gesture(opened) { opened.playAlong.cyclePush(2) }
        chords = opened.playAlong.timeline.timeline.chords
        #expect(chords[2].push == .sixteenth)
        #expect(chords[2].onset == 2 * 1920 - 120)
        gesture(opened) { opened.playAlong.cyclePush(2) }
        chords = opened.playAlong.timeline.timeline.chords
        #expect(chords[2].push == nil)
        #expect(chords[2].length == 1440)
        #expect(opened.editor.bassPrefs.timing.chords.map(\.ticks) == [1440])
        // Three pushes, three undo steps, then the length's own.
        for _ in 0 ..< 3 {
            opened.editor.sourceEditor.undoManager.undo()
        }
        refresh(opened)
        #expect(opened.editor.bassPrefs.timing.chords.map(\.push) == [nil])
        #expect(opened.editor.bassPrefs.timing.chords.map(\.ticks) == [1440])
    }

    @Test
    func `pushing a chord without a correction keeps its length`() async throws {
        let opened = try await open()
        gesture(opened) { opened.playAlong.setPush(1, .sixteenth) }
        let chords = opened.playAlong.timeline.timeline.chords
        #expect(chords[1].push == .sixteenth)
        #expect(chords[1].source == .user)
        #expect(opened.playAlong.pulses(of: 1) == 4)
        #expect(opened.editor.bassPrefs.timing.chords.map(\.ticks) == [1920])
    }

    @Test
    func `a tapped length shows as tapped until it is edited`() async throws {
        let opened = try await open()
        let chord = opened.playAlong.timeline.timeline.chords[1]
        let source = try #require(opened.playAlong.source)
        let anchor = try #require(ChordAnchors.anchor(
            at: chord.position,
            units: source.units,
            sections: source.sections,
        ))
        gesture(opened) {
            opened.playAlong.save("Tap") { timing in
                timing.chords = [ChordBeatsOverride(
                    anchor: anchor,
                    ticks: 960,
                    meter: .common,
                    source: .tap,
                )]
            }
        }
        #expect(LaneEdge(opened.playAlong.timeline.timeline.chords[1].source) == .tapped)
        gesture(opened) { opened.playAlong.setLength(1, text: "3") }
        #expect(LaneEdge(opened.playAlong.timeline.timeline.chords[1].source) == .corrected)
        #expect(LaneEdge(opened.playAlong.timeline.timeline.chords[0].source) == .estimated)
    }

    @Test
    func `key, time and tempo changes are marked where they start`() async throws {
        let opened = try await open("""
        {title: Lift}
        {key: G}
        {time: 4/4}
        {tempo: 100}

        {start_of_verse}
        [G]One [C]two
        {end_of_verse}

        {key: A}
        {time: 3/4}
        {tempo: 120}
        {start_of_chorus}
        [A]Three [D]four
        {end_of_chorus}

        """)
        let markers = opened.playAlong.laneMarkers
        #expect(markers.map(\.index) == [2])
        #expect(markers.first?.text == "Key: A  3/4  \u{2669} 120")
        #expect(markers.first?.spoken == "key change to A, time change to 3/4, tempo change to 120")
        // Under a transposed view the key reads as the chart shows it.
        opened.editor.updateOptions { $0.transpose = 2 }
        try await AISettingsTests.waitUntil(timeout: .seconds(30)) {
            opened.editor.renderModel?.transform.options.transpose == 2
        }
        refresh(opened)
        #expect(opened.playAlong.laneMarkers.first?.text.hasPrefix("Key: B") == true)
    }

    @Test
    func `shift-click spans either way from the selection`() async throws {
        let opened = try await open()
        let model = opened.playAlong
        model.select(1, extending: false)
        #expect(model.span == nil)
        model.select(3, extending: true)
        #expect(model.span == 1 ... 3)
        model.select(0, extending: true)
        #expect(model.span == 0 ... 1)
        model.select(2, extending: false)
        #expect(model.span == nil)
        #expect(model.selected == 2)
        // A new range clears it.
        model.select(3, extending: true)
        model.setRange(.section(1))
        #expect(model.span == nil)
    }
}
