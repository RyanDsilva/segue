import ChordPro
import Editing
import Foundation
import Library
import MusicTheory
@testable import SegueUI
import Support
import SwiftUI
import Testing

/// The song card (R80, direction 2) over a temp library and the real parser and editor:
/// every field writes exactly its directive and clearing removes it (one undo step each),
/// invalid values never reach the file, the editor strip and the top bar's capo stepper
/// share one binding, and draft mode writes nothing to disk.
@MainActor
struct SongCardTests {
    private static let songID = "01JC0000000000000000000K01"
    private static let file = "songs/kitaabon.cho"
    private static let source = "{title: Kitaabon Wali Gali}\n\n[Am]Purani si [G]gali mein\n"

    private struct Fixture {
        let env: TestEnvironment
        let model: LibraryViewModel
        let id: SongID
    }

    private func library() async throws -> Fixture {
        let env = try TestEnvironment()
        try FileManager.default.createDirectory(
            at: env.libraryURL.appending(path: "songs", directoryHint: .isDirectory),
            withIntermediateDirectories: true,
        )
        try env.write(Self.source, to: Self.file)
        try env.write(
            #"{"schemaVersion": 3, "id": "\#(Self.songID)", "createdAt": "2026-10-01T10:00:00Z", "#
                + #""updatedAt": "2026-10-01T10:00:00Z"}"#,
            to: "songs/kitaabon.segue.json",
        )
        let model = try await env.openLibrary()
        let id = try SongID(#require(ULID(string: Self.songID)))
        return Fixture(env: env, model: model, id: id)
    }

    @Test(arguments: [
        (SongCardWrite.key(SongKey(parsing: "Am")), "{key: Am}"),
        (SongCardWrite.capo(2), "{capo: 2}"),
        (EditOperation.setLength(245), "{duration: 4:05}"),
        (SongCardWrite.artist("Segue Originals"), "{artist: Segue Originals}"),
        (try? SongCardWrite.tempo("84").get(), "{tempo: 84}"),
        (try? SongCardWrite.time("3/4").get(), "{time: 3/4}"),
    ])
    func `each field writes exactly its directive and undo removes it`(
        operation: EditOperation?,
        line: String,
    ) async throws {
        let fixture = try await library()
        let (env, model, id) = (fixture.env, fixture.model, fixture.id)
        let manager = UndoManager()
        manager.groupsByEvent = false
        model.undoManager = manager
        let operation = try #require(operation)

        manager.beginUndoGrouping()
        await model.editSongSource(id: id, operation)
        manager.endUndoGrouping()
        let written = try env.read(Self.file)
        #expect(written.contains(line + "\n"), "\(written)")
        // Nothing else changed: dropping the new line gives the original back.
        #expect(written.replacingOccurrences(of: line + "\n", with: "") == Self.source)

        manager.undo()
        try await env.waitFor { (try? env.read(Self.file)) == Self.source ? true : nil }
    }

    @Test
    func `clearing a field removes its directive`() async throws {
        let fixture = try await library()
        let (env, model, id) = (fixture.env, fixture.model, fixture.id)
        await model.editSongSource(id: id, SongCardWrite.key(SongKey(parsing: "Am")))
        await model.editSongSource(id: id, .setLength(200))
        await model.editSongSource(id: id, SongCardWrite.key(nil))
        await model.editSongSource(id: id, .setLength(nil))
        await model.editSongSource(id: id, SongCardWrite.capo(0))
        #expect(try env.read(Self.file) == Self.source)
    }

    @Test
    func `invalid values are refused before the file`() {
        #expect(throws: SongCardWrite.Problem.self) { try SongCardWrite.tempo("fast").get() }
        #expect(throws: SongCardWrite.Problem.self) { try SongCardWrite.tempo("900").get() }
        #expect(throws: SongCardWrite.Problem.self) { try SongCardWrite.time("5/3").get() }
        #expect(throws: SongCardWrite.Problem.self) { try SongCardWrite.time("waltz").get() }
        #expect((try? SongCardWrite.tempo("96.5").get()) == .setDirective(
            name: "tempo",
            value: "96.5",
        ))
        #expect((try? SongCardWrite.time(" 6 / 8 ").get()) == .setDirective(
            name: "time",
            value: "6/8",
        ))
        #expect((try? SongCardWrite.tempo(" ").get()) == .setDirective(name: "tempo", value: nil))
    }

    @Test
    func `the editor strip and the top bar capo stepper share one binding`() {
        let model = SongEditorViewModel(mode: .create, source: Self.source) { _ in
            throw CancellationError()
        }
        model.sourceEditor.undoManager.groupsByEvent = false
        let host = SongCardHost(
            document: model.snapshot.document,
            songID: .standIn(),
            perform: { _ = model.perform($0) },
        )
        model.sourceEditor.undoManager.beginUndoGrouping()
        host.perform(SongCardWrite.capo(3))
        model.sourceEditor.undoManager.endUndoGrouping()
        #expect(model.capo == 3)
        model.sourceEditor.undoManager.beginUndoGrouping()
        model.stepCapo(by: 1)
        model.sourceEditor.undoManager.endUndoGrouping()
        #expect(SongCardValues(document: model.snapshot.document).capo == 4)
        #expect(model.source.contains("{capo: 4}"))
        model.sourceEditor.undoManager.undo()
        #expect(SongCardValues(document: model.snapshot.document).capo == 3)
    }

    @Test
    func `draft mode edits the text in memory and writes nothing to disk`() async throws {
        let env = try await library().env
        let before = try FileManager.default.contentsOfDirectory(atPath: env.libraryURL.path)
        var source = Self.source
        var metadata = SongMetadata()
        let host = SongCardHost.draft(
            source: Binding(get: { source }, set: { source = $0 }),
            metadata: Binding(get: { metadata }, set: { metadata = $0 }),
            songID: .standIn(),
        )
        host.perform(SongCardWrite.key(SongKey(parsing: "Am")))
        host.editMetadata? { $0.tags = ["hindi"] }
        #expect(source.contains("{key: Am}"))
        #expect(metadata.tags == ["hindi"])
        #expect(try env.read(Self.file) == Self.source)
        #expect(try FileManager.default.contentsOfDirectory(atPath: env.libraryURL.path) == before)
    }

    @Test
    func `missing essentials are key tempo and length`() {
        let blank = SourceSnapshot(text: "{title: X}\n").document.metadata
        #expect(SetEssential.missing(in: blank) == [.key, .tempo, .length])
        #expect(SetEssential
            .spokenMissing([.key, .tempo, .length]) == "Missing key, tempo and length")
        let full = SourceSnapshot(text: "{key: Am}\n{tempo: 84}\n{duration: 4:05}\n").document
            .metadata
        #expect(SetEssential.missing(in: full).isEmpty)
        let badKey = SourceSnapshot(text: "{key: Hm}\n{tempo: 84}\n{duration: 245}\n").document
            .metadata
        #expect(SetEssential.missing(in: badKey) == [.key])
    }

    @Test
    func `the detected key is offered but never written by itself`() {
        let values = SongCardValues(document: SourceSnapshot(text: Self.source).document)
        #expect(values.key == nil)
        #expect(values.detectedKey != nil)
        #expect(values.missing.contains(.key))
    }

    @Test
    func `tap tempo averages the run and restarts after a pause`() {
        var taps = TapTempo()
        #expect(taps.tap(at: 10) == nil)
        #expect(taps.tap(at: 10.5) == 120)
        #expect(taps.tap(at: 11.0) == 120)
        #expect(taps.tap(at: 11.5) == 120)
        // A pause longer than two seconds starts a new run.
        #expect(taps.tap(at: 20) == nil)
        #expect(taps.tap(at: 20.75) == 80)
    }

    @Test
    func `a focus request reaches only the card it names`() throws {
        let router = SongCardFocusRouter()
        let id = try SongID(#require(ULID(string: Self.songID)))
        router.focus(.length, songID: id)
        #expect(router.take(for: .standIn()) == nil)
        #expect(router.take(for: id) == .length)
        #expect(router.take(for: id) == nil)
        router.focus(.title)
        #expect(router.take(for: .standIn()) == .title)
    }
}
