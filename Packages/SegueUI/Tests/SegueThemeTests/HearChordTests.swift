import AppKit
import Diagrams
import Editing
import Foundation
import Library
import Playback
@testable import SegueUI
import Testing

/// Hearing a chord (P8-6 10.1, 15.2): a preview chord plays at sounding pitch over its bass
/// through the real editor and library view models, a new chord stops the last, the canvas
/// plays only on ⌥-click, a bass strip cell plays its note.
@MainActor
@Suite(.serialized)
struct HearChordTests {
    /// The editor on `source`, with sound and the profile given.
    private func editor(
        _ env: TestEnvironment,
        _ source: String,
        rig: SoundRig,
        profile: (inout InstrumentProfile) -> Void = { _ in },
    ) async throws -> (LibraryViewModel, SongEditorViewModel) {
        let instrument = InstrumentProfileStore(defaults: env.defaults)
        instrument.update(profile)
        let library = try await env.openLibrary()
        library.instrument = instrument
        library.sound = rig.session
        let song = try await library.createSong(source: source)
        library.beginEditing(song)
        let editor = try #require(library.editor)
        try await AISettingsTests.waitUntil(timeout: .seconds(30)) { editor.renderModel != nil }
        return (library, editor)
    }

    static func chords(_ model: RenderModel?) -> [RenderChord] {
        model?.sections.flatMap(\.items).flatMap { item -> [RenderChord] in
            guard case let .lyrics(line) = item else { return [] }
            return line.chords
        } ?? []
    }

    @Test(arguments: [
        ("{key: G}\n[G]La\n", [55, 59, 62], 31),
        ("{key: G}\n{capo: 2}\n[G]La\n", [57, 61, 64], 33),
        ("{key: G}\n[G/B]La\n", [55, 59, 62], 35),
        ("{key: G}\n[Cmaj7]La\n", [48, 52, 55, 59], 36),
    ])
    func `a preview chord plays at sounding pitch over its bass`(
        source: String,
        chord: [Int],
        bass: Int,
    ) async throws {
        let env = try TestEnvironment()
        let recorder = RecordingAnalytics(env)
        let rig = SoundRig(env, services: recorder.hub)
        rig.session.settings.update { $0.chordStyle = .block }
        let (_, editor) = try await editor(env, source, rig: rig)
        let hearing = try #require(editor.chordHearing)
        try hearing.play(#require(Self.chords(editor.renderModel).first))
        #expect(rig.notes(.chord) == chord)
        #expect(rig.notes(.bass) == [bass])
        #expect(rig.outputs.last?.calls.first == .prepare(.piano, .finger))
        #expect(recorder.features == ["hearChord"])
    }

    /// R163: the bass sounds on the Settings strings and tuning for anyone, as the mini neck
    /// shows them, with or without "I play bass" (EADG would put D on the A string, 38).
    @Test(arguments: [false, true])
    func `the bass follows the Settings tuning with or without I play bass`(
        playsBass: Bool,
    ) async throws {
        let env = try TestEnvironment()
        let rig = SoundRig(env)
        let (_, editor) = try await editor(env, "{key: D}\n[D]La\n", rig: rig) {
            $0.playsBass = playsBass
            $0.strings = 5
            $0.tuning = .bassStandard5
        }
        let hearing = try #require(editor.chordHearing)
        try hearing.play(#require(Self.chords(editor.renderModel).first))
        #expect(rig.notes(.bass) == [26])
    }

    @Test
    func `a second chord stops the first, and N.C. plays nothing`() async throws {
        let env = try TestEnvironment()
        let rig = SoundRig(env)
        let (_, editor) = try await editor(env, "{key: G}\n[G]La [C]la [N.C.]la\n", rig: rig)
        let hearing = try #require(editor.chordHearing)
        let chords = Self.chords(editor.renderModel)
        hearing.play(chords[0])
        hearing.play(chords[1])
        let calls = try #require(rig.outputs.last?.calls)
        let stop = try #require(calls.firstIndex(of: .stopAll))
        #expect(calls[..<stop].contains {
            if case .play = $0 {
                true
            } else {
                false
            }
        })
        #expect(rig.notes(.bass) == [31, 36])
        let count = calls.count
        hearing.play(chords[2])
        #expect(rig.outputs.last?.calls.count == count)
    }

    @Test
    func `strummed chords go low to high and guitar plays its shape`() async throws {
        let env = try TestEnvironment()
        let rig = SoundRig(env)
        rig.session.settings.update { $0.chordSound = .cleanGuitar }
        let (_, editor) = try await editor(env, "{key: G}\n[C]La\n", rig: rig)
        try #require(editor.chordHearing).play(try #require(Self.chords(editor.renderModel).first))
        let chord = try #require(rig.outputs.last?.played.filter { $0.event.voice == .chord })
        #expect(chord.map { Int($0.event.note) } == [48, 52, 55, 60, 64])
        #expect(chord.map { ($0.event.onset * 1000).rounded() } == [0, 25, 50, 75, 100])
    }

    @Test
    func `the canvas plays on option-click only`() async throws {
        let env = try TestEnvironment()
        let rig = SoundRig(env)
        let (_, editor) = try await editor(env, "{key: G}\n[G]Hello there\n", rig: rig)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        editor.setEditorMode(.visual)
        let canvas = editor.visualEditor
        canvas.container.frame = window.contentLayoutRect
        window.contentView = canvas.container
        canvas.didAttach()
        var pills: [PillLayout] = []
        canvas.forEachRow(in: canvas.textView.bounds) { row in
            pills += canvas.pills(in: row)
            return true
        }
        let pill = try #require(pills.first)
        let point = canvas.textView.convert(CGPoint(x: pill.rect.midX, y: pill.rect.midY), to: nil)
        func click(_ flags: NSEvent.ModifierFlags) throws {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(NSEvent.mouseEvent(
                    with: type,
                    location: point,
                    modifierFlags: flags,
                    timestamp: 0,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: 1,
                ))
                _ = type == .leftMouseDown ? canvas.canvasMouseDown(event)
                    : canvas.canvasMouseUp(event)
            }
        }
        try click([])
        #expect(rig.outputs.made == 0)
        #expect(canvas.selectedChord != nil)
        try click(.option)
        #expect(rig.notes(.bass) == [31])
        #expect(editor.source == "{key: G}\n[G]Hello there\n") // nothing duplicated
    }

    @Test
    func `a bass strip cell plays its note, option-click its chord`() async throws {
        let env = try TestEnvironment()
        let rig = SoundRig(env)
        let (_, editor) = try await editor(env, "{key: G}\n[G/B]La\n", rig: rig) {
            $0.setPlaysBass(true)
        }
        let diagram = try #require(editor.renderModel?.diagrams.first)
        let bass = try #require(diagram.bass)
        let hearing = try #require(editor.chordHearing)
        try hearing.playBass(BassFretboard.pitch(#require(bass.suggested), tuning: bass.tuning))
        #expect(rig.notes(.bass) == [35])
        #expect(rig.notes(.chord).isEmpty)
        hearing.playConcert(bass.chordName)
        #expect(rig.notes(.chord) == [55, 59, 62])
    }

    @Test
    func `the library preview plays the song's own options`() async throws {
        let env = try TestEnvironment()
        let rig = SoundRig(env)
        let library = try await env.openLibrary()
        library.sound = rig.session
        let song = try await library.createSong(source: "{key: G}\n{capo: 2}\n[G]La\n")
        let render = SongSummary.renderModel(song)
        let hearing = try #require(library.chordHearing(render))
        try hearing.play(#require(Self.chords(render).first))
        #expect(rig.notes(.bass) == [33])
        #expect(rig.notes(.chord).sorted() == [57, 61, 64])
    }
}
