import ChordPro
import Editing
import Foundation
import Library
@testable import SegueUI
import Support
import Testing

/// The song card's Length row (P3-5, R91) on a real temp library: the field's commit and a
/// scripted Time it run go through the real `DocumentEditor` and editor, and the reloaded
/// `.cho` carries exactly the expected `{duration}`. Nothing is mocked.
@MainActor
struct LengthEntryTests {
    private static let path = "songs/harbour-lights.cho"

    /// A temp library with one song open in the editor, undo grouped per edit.
    @MainActor
    private struct Harness {
        let env: TestEnvironment
        let library: LibraryViewModel
        let editor: SongEditorViewModel
        let song: SongRecord

        init(source: String) async throws {
            env = try TestEnvironment()
            try FileManager.default.createDirectory(
                at: env.libraryURL.appending(path: "songs", directoryHint: .isDirectory),
                withIntermediateDirectories: true,
            )
            try env.write(source, to: LengthEntryTests.path)
            let app = try await env.openApp()
            library = try #require(app.session?.library)
            song = try #require(library.catalog.first)
            library.beginEditing(song)
            editor = try #require(library.editor)
            editor.sourceEditor.undoManager.groupsByEvent = false
        }

        var current: TimeInterval? {
            editor.snapshot.document.metadata.duration
        }

        /// Commits what the field would, then saves and reads the file back.
        func commit(_ commit: LengthCommit) async throws -> String {
            if case let .write(seconds) = commit {
                #expect(editor.perform(.setLength(seconds)))
            }
            #expect(await library.flushEditor())
            return try env.read(LengthEntryTests.path)
        }
    }

    private static let source = "{title: Harbour Lights}\n[G]Lanterns on the [C]water\n"

    @Test
    func `typing 4 05 writes the duration as one undo step`() async throws {
        let harness = try await Harness(source: Self.source)
        let commit = LengthCommit.of("4 05", current: harness.current)
        #expect(commit == .write(245))
        let saved = try await harness.commit(commit)
        #expect(saved == "{title: Harbour Lights}\n{duration: 4:05}\n[G]Lanterns on the [C]water\n")
        #expect(harness.current == 245)

        let undo = harness.editor.sourceEditor.undoManager
        #expect(undo.undoActionName == "Set Duration")
        undo.undo()
        #expect(harness.editor.source == Self.source)
    }

    @Test
    func `a scripted Time it run writes 4 05 and the run ends`() async throws {
        let harness = try await Harness(source: Self.source)
        let clock = ManualClock()
        let timer = TimeItModel(clock: clock)
        #expect(timer.start(harness.song.id))
        clock.advance(by: 244.6)
        #expect(abs(timer.elapsed() - 244.6) < 0.001)
        let seconds = try #require(timer.stop(harness.song.id))
        #expect(seconds == 245)
        #expect(timer.run == nil)

        let saved = try await harness.commit(.timed(seconds, current: harness.current))
        #expect(saved.contains("{duration: 4:05}\n"))
    }

    @Test
    func `escape cancels the run and nothing is written`() async throws {
        let harness = try await Harness(source: Self.source)
        let clock = ManualClock()
        let timer = TimeItModel(clock: clock)
        #expect(timer.start(harness.song.id))
        clock.advance(by: 200)
        timer.cancel(harness.song.id)
        #expect(timer.run == nil)
        #expect(timer.stop(harness.song.id) == nil)
        #expect(try await harness.commit(.unchanged) == Self.source)
        #expect(!harness.editor.hasUnsavedChanges)
    }

    @Test
    func `clearing the field removes the directive`() async throws {
        let harness = try await Harness(
            source: "{title: Harbour Lights}\n{duration: 3:40}\n[G]Lanterns\n",
        )
        #expect(harness.current == 220)
        #expect(LengthCommit.of("3:40", current: harness.current) == .unchanged)
        let commit = LengthCommit.of("  ", current: harness.current)
        #expect(commit == .write(nil))
        #expect(try await harness.commit(commit) == "{title: Harbour Lights}\n[G]Lanterns\n")
    }

    @Test
    func `an invalid value never reaches the file`() async throws {
        let harness = try await Harness(source: Self.source)
        #expect(LengthCommit.of("0:00", current: nil) == .rejected("Length must be more than zero"))
        #expect(LengthCommit.of("-3:00", current: nil) == .rejected("Length can't be negative"))
        #expect(LengthCommit.of("4:75", current: nil)
            == .rejected("Minutes and seconds go up to 59"))
        #expect(LengthCommit.timed(0, current: nil) == .rejected("Length must be more than zero"))
        #expect(try await harness.commit(LengthCommit.of("soon", current: nil)) == Self.source)
    }

    @Test
    func `one run at a time, kept across songs, ended by deleting its song`() {
        let clock = ManualClock()
        let ids = ULIDGenerator(clock: clock, seed: 1)
        let timer = TimeItModel(clock: clock)
        let first = SongID(ids.next())
        let second = SongID(ids.next())
        #expect(timer.start(first))
        #expect(!timer.start(second))
        #expect(timer.isTimingOther(than: second))
        #expect(timer.stop(second) == nil)
        timer.cancel(second)
        #expect(timer.isTiming(first))
        timer.songsDeleted([second])
        #expect(timer.isTiming(first))
        timer.songsDeleted([first])
        #expect(timer.run == nil)
    }
}
