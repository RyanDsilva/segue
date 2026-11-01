import Foundation
@testable import SegueUI
import Support
import Testing

/// The library state outside the folder through the real `AppModel` (P9-6 5.2, 5.3).
@MainActor
struct LibraryStateAppTests {
    @Test
    func `an open library keeps its index and lock in the state directory`() async throws {
        let env = try TestEnvironment()
        let app = try await env.openApp()
        let session = try #require(app.session)

        let base = env.stateLocation.librariesDirectory.path(percentEncoded: false)
        #expect(session.state.url.path(percentEncoded: false).hasPrefix(base))
        #expect(env.fileSystem.fileExists(at: session.state.indexDatabase))
        #expect(session.lock?.url == session.state.lockURL)
        let inFolder = try FileManager.default.contentsOfDirectory(
            atPath: LibraryRoot(url: env.libraryURL).appDirectory.path(percentEncoded: false),
        )
        #expect(Set(inFolder) == ["library.json", "upgrades.json"])
        #expect(session.upgradeNote == nil)
    }

    @Test
    func `opening a Finder copy of the open library notes its new identity once`() async throws {
        let env = try TestEnvironment()
        let app = try await env.openApp()
        let original = try #require(app.session?.state)
        let copy = env.scratch.appending(path: "Library copy", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: env.libraryURL, to: copy)

        let second = env.app(override: copy)
        await second.start()
        let session = try #require(second.session)

        #expect(session.state != original)
        #expect(session.upgradeNote == LibraryNote(title: LibraryState.copyNote))
    }
}
