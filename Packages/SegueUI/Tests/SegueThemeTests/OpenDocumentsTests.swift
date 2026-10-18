import Foundation
import Library
@testable import SegueUI
import Testing

/// Finder's Open With through the app (WS2b 4.7, A31) on a real temp library: a song in the
/// library is selected, a file elsewhere is copied in through the import, anything else shows
/// the banner, and requests wait for the Welcome flow.
@MainActor
struct OpenDocumentsTests {
    @Test
    func `open with selects library songs, imports others and refuses the rest`() async throws {
        let env = try TestEnvironment()
        let app = try await env.openApp()
        let session = try #require(app.session)
        #expect(await app.seedWelcomeLibrary())

        app.requestOpen([env.libraryURL.appending(path: "songs/kitaabon-wali-gali.cho")])
        try await env.waitFor {
            session.library.selection.flatMap(session.library.song(id:))
                .map(SongSummary.title) == "Kitaabon Wali Gali" ? true : nil
        }

        let outside = env.scratch.appending(path: "Downloads", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let song = outside.appending(path: "bus-stop-blues.chordpro")
        try Data("{title: Bus Stop Blues}\n{key: E}\n[E]Waiting on the [A]number nine\n".utf8)
            .write(to: song)
        app.requestOpen([song])
        try await env.waitFor { env.exists("songs/bus-stop-blues.cho") ? true : nil }
        #expect(FileManager.default.fileExists(atPath: song.path), "the original stays")

        let pdf = outside.appending(path: "poster.pdf")
        try Data("%PDF-1.4".utf8).write(to: pdf)
        app.requestOpen([pdf])
        try await env.waitFor { session.library.errorMessage }
        #expect(session.library.errorMessage == AppModel.notASongMessage)
    }

    @Test
    func `requests wait for the welcome flow`() async throws {
        let env = try TestEnvironment()
        let app = try await env.openApp()
        let outside = env.scratch.appending(path: "first-song.cho")
        try Data("{title: First Song}\n[C]Hello\n".utf8).write(to: outside)

        app.onboarding.begin([.welcomeSongs], at: .welcomeSongs)
        app.requestOpen([outside])
        try await Task.sleep(for: .milliseconds(200))
        #expect(!env.exists("songs/first-song.cho"), "imported during the Welcome flow")
        #expect(app.pendingOpenURLs == [outside])

        await app.onboardingContinueFromWelcomeSongs()
        try await env.waitFor { env.exists("songs/first-song.cho") ? true : nil }
    }

    /// Project.swift cannot import SegueCore, so this keeps its declared extensions equal to
    /// the one shared list (A24, I-10).
    @Test
    func `the declared document type claims exactly the shared extensions`() throws {
        let project = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Project.swift")
        let text = try String(contentsOf: project, encoding: .utf8)
        let line = try #require(text.split(separator: "\n").first {
            $0.contains("\"public.filename-extension\":")
        })
        let declared = line.split(separator: "[").last?.split(separator: "]").first?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: ["\""]) }
        #expect(declared == SongFileTypes.claimedExtensions)
    }
}
