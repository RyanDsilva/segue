import Foundation
import Ingest
import Library
@testable import SegueUI
import Services
import Testing

/// "Looks like a song in your library" in the review sheet (P8-1 section 6.3, R154, R158
/// Q4 and Q9): beside the card, never blocking, re-checked as the text changes.
extension PasteReviewTests {
    /// The library's copy of the test song (a live note makes its bytes differ from any
    /// fresh conversion).
    private static var librarySource: String {
        IngestPipeline.ingest(paste, origin: .paste).text + "{comment: Live version}\n"
    }

    private static let chordPro = """
    {title: Harbour Lights}
    {artist: Segue Originals}
    [G]Lanterns on the [C]water, ropes upon the quay
    [D]Every boat is coming home, every one but me
    """

    @Test
    func `an imported text file that looks like a library song carries the warning`(
    ) async throws {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        _ = try await library.store.createSong(source: Self.librarySource)
        await library.reload()
        let file = env.scratch.appending(path: "harbour.txt")
        try Data(Self.paste.utf8).write(to: file)

        await library.importWithReview([file], method: .dragDrop)

        let item = try #require(library.pasteReview?.selected)
        let match = try #require(item.nearDuplicate)
        #expect(!item.isAlreadyInLibrary)
        #expect(match.title == "Harbour Lights")
        #expect(item.nearDuplicateText
            == "Looks like “Harbour Lights” by Segue Originals in your library.")
        // Renaming the song to an unrelated title clears it.
        item.edit(item.text.replacingOccurrences(of: "Harbour Lights", with: "Quiet Meadow"))
        #expect(item.nearDuplicate == nil)
        #expect(item.nearDuplicateText == nil)
        await library.cancelPasteReview()
    }

    @Test
    func `a byte-identical paste says it is already in the library`() async throws {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        _ = try await library.store.createSong(source: Self.chordPro)
        await library.reload()

        library.beginPasteReview(text: Self.chordPro, source: .clipboard)

        let item = try #require(library.pasteReview?.selected)
        #expect(item.text == Self.chordPro)
        #expect(item.isAlreadyInLibrary)
        #expect(item.nearDuplicateText == "Already in your library as “Harbour Lights”.")
        #expect(library.pasteReview?.canAccept == true)
        await library.cancelPasteReview()
    }

    /// R163: an accepted paste that looks like a library song flags its row 5 event.
    @Test
    func `an accepted lookalike paste flags its song-created event`() async throws {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        let recording = RecordingLog(url: env.scratch.appending(path: "services.jsonl"))
        library.services = ServicesHub(
            factory: RecordingServicesFactory(log: recording),
            consent: ConsentState(analytics: .granted(.now), crashReports: .declined(.now)),
            throttle: AnalyticsThrottle(suiteName: env.suiteName, clock: env.clock),
        )
        _ = try await library.store.createSong(source: Self.librarySource)
        await library.reload()

        library.beginPasteReview(text: Self.paste, source: .clipboard)
        #expect(library.pasteReview?.selected?.nearDuplicate != nil)
        await library.pasteReview?.awaitRefinement()
        await library.acceptPasteReview()

        let signal = try #require(recording.entries().first {
            $0["name"] as? String == "Segue.Song.created"
        })
        let params = try #require(signal["params"] as? [String: String])
        #expect(params == ["segue.source": "newSong", "segue.nearDuplicate": "true"])
    }

    @Test
    func `a ChordPro lookalike is reviewed as read and lands with the others`() async throws {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        let recording = RecordingLog(url: env.scratch.appending(path: "services.jsonl"))
        library.services = ServicesHub(
            factory: RecordingServicesFactory(log: recording),
            consent: ConsentState(analytics: .granted(.now), crashReports: .declined(.now)),
            throttle: AnalyticsThrottle(suiteName: env.suiteName, clock: env.clock),
        )
        _ = try await library.store.createSong(source: Self.chordPro)
        await library.reload()
        let manager = UndoManager()
        manager.groupsByEvent = false
        library.undoManager = manager
        let folder = env.scratch.appending(path: "drop", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let lookalike = Self.chordPro.replacingOccurrences(of: "[G]", with: "[G7]") + "\r\n"
        try Data(lookalike.utf8).write(to: folder.appending(path: "harbour.cho"))
        try Data("{title: Already}\n[G]Done\n".utf8).write(to: folder.appending(path: "a.cho"))

        await library.importWithReview([folder], method: .dragDrop)

        let review = try #require(library.pasteReview)
        #expect(review.directFiles.map(\.fileName) == ["a.cho"])
        let item = try #require(review.items.first)
        #expect(review.items.count == 1)
        #expect(item.source == .fileCho)
        #expect(item.text == lookalike)
        #expect(item.status == .notNeeded)
        #expect(item.nearDuplicate?.title == "Harbour Lights")

        manager.beginUndoGrouping()
        await library.acceptPasteReview()
        manager.endUndoGrouping()

        let summary = try #require(library.importSummary)
        #expect(summary.imported.count == 2)
        let written = try #require(summary.imported
            .first { $0.relativePath != "songs/already.cho" })
        #expect(try env.read(written.relativePath) == lookalike)
        #expect(env.exists("songs/already.cho"))
        #expect(manager.undoActionName == "Import")
        manager.undo()
        try await env.waitFor { library.catalog.count == 1 ? true : nil }

        let signal = try #require(recording.entries().first {
            $0["name"] as? String == "Segue.Song.imported"
        })
        let params = try #require(signal["params"] as? [String: String])
        #expect(params["segue.nearDuplicate"] == "true")
    }

    @Test
    func `during a show a ChordPro lookalike imports directly without the sheet`() async throws {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        _ = try await library.store.createSong(source: Self.chordPro)
        await library.reload()
        library.isPerforming = true
        let file = env.scratch.appending(path: "harbour.cho")
        try Data((Self.chordPro + "\n{comment: again}\n").utf8).write(to: file)

        await library.importWithReview([file], method: .dragDrop)

        #expect(library.pasteReview == nil)
        #expect(library.importSummary?.imported.count == 1)
    }
}
