import Foundation
import Library
@testable import SegueUI
import Setlists
import Support
import Testing

/// The section, song and gig restored on the next launch (WS2a 3.10, A26).
@MainActor
struct SessionRestoreTests {
    @Test
    func `the state round trips per library root`() throws {
        let env = try TestEnvironment()
        let first = LibraryRoot(url: env.scratch.appending(path: "One"))
        let second = LibraryRoot(url: env.scratch.appending(path: "Two"))
        let song = SongID(ULID(milliseconds: 1, randomness: Array(repeating: 2, count: 10)))
        let state = RestoredState(section: .gigLog, song: song, gig: nil)

        SessionRestore(defaults: env.defaults, root: first).write(state)

        #expect(SessionRestore(defaults: env.defaults, root: first).load() == state)
        #expect(SessionRestore(defaults: env.defaults, root: second).load() == nil)
        #expect(SessionRestore.key(for: first) != SessionRestore.key(for: second))
        #expect(state.songID == song)
    }

    @Test
    func `a relaunch restores the setlist and the song, and falls back when they are gone`(
    ) async throws {
        let env = try TestEnvironment()
        env.libraryLock = .unlocked
        var app = try await env.openApp()
        var session = try #require(app.session)
        let song = try await session.library.createSong(source: "{title: Harbour}\nLine\n")
        let setlist = try #require(await session.setlists.create(name: "Friday"))
        session.section = .setlist(setlist.id)
        session.library.selection = song.id
        session.restore?.write(session.currentRestoredState)

        app = try await env.openApp()
        session = try #require(app.session)
        #expect(session.section == .setlist(setlist.id))
        #expect(session.library.selection == song.id)
        #expect(session.library.editor == nil)

        // Both gone on disk: back to the Library with nothing selected, no crash.
        try FileManager.default.removeItem(at: env.libraryURL.appending(path: song.relativePath))
        try FileManager.default.removeItem(
            at: env.libraryURL.appending(path: "setlists/friday.setlist.json"),
        )
        app = try await env.openApp()
        session = try #require(app.session)
        #expect(session.section == .library)
        #expect(session.library.selection == nil)
    }
}
