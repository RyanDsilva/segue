import Foundation
import Ingest
import Library
import ModelPort
@testable import SegueUI
import Services
import Testing

/// The paste review sheet's model and routes (P3-4, spec 6.1-6.2, R83, R95/R109, R96) on a
/// real temp library, the real converter and `ScriptedProvider`.
@MainActor
struct PasteReviewTests {
    static let paste = """
    Harbour Lights - Segue Originals
    Capo 2

    G               C
    Lanterns on the water, ropes upon the quay
    D               G
    Every boat is coming home, every one but me

    C        G
    Hold the light, hold the light
    D            G
    Bring her home tonight

    G               C
    Gulls above the breakwater, salt upon the sill
    D               G
    Every window burning bright, burning for me still
    """

    // MARK: Paste and Accept / Cancel

    @Test
    func `a paste opens with the deterministic result and Accept writes exactly it`() async throws {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        library.beginPasteReview(text: Self.paste, source: .clipboard)
        let review = try #require(library.pasteReview)
        let item = try #require(review.selected)
        #expect(review.phase == .review)
        #expect(item.text == IngestPipeline.ingest(Self.paste, origin: .paste).text)

        await library.acceptPasteReview()

        #expect(library.pasteReview == nil)
        let written = try env.read("songs/harbour-lights.cho")
        #expect(written == item.base.text)
        #expect(written.contains("{title: Harbour Lights}"))
        #expect(written.contains("{artist: Segue Originals}"))
        #expect(written.contains("{capo: 2}"))
        // A detected key is a suggestion only (R101).
        #expect(!written.contains("{key"))
        #expect(item.suggestedKey == "G")
        #expect(library.catalog.count == 1)
        #expect(library.selection == library.catalog.first?.id)
    }

    @Test
    func `cancel writes nothing`() async throws {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        library.beginPasteReview(text: Self.paste, source: .listPaste)
        await library.cancelPasteReview()
        #expect(library.pasteReview == nil)
        #expect(!env.exists("songs/harbour-lights.cho"))
        await library.reload()
        #expect(library.catalog.isEmpty)
    }

    @Test
    func `swap Title and Artist swaps the two directives`() async throws {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        library.beginPasteReview(text: Self.paste, source: .clipboard)
        let item = try #require(library.pasteReview?.selected)
        #expect(item.canSwapTitleAndArtist)
        item.swapTitleAndArtist()
        #expect(item.text.contains("{title: Segue Originals}"))
        #expect(item.text.contains("{artist: Harbour Lights}"))
        #expect(item.isEdited)
        await library.acceptPasteReview()
        #expect(env.exists("songs/segue-originals.cho"))
    }

    // MARK: New Song (R83)

    @Test
    func `new Song shows the input state, and pasting moves it to review`() async throws {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        library.beginNewSongFlow()
        let review = try #require(library.pasteReview)
        #expect(review.phase == .input)
        #expect(!review.canAccept)
        review.draftText = Self.paste
        review.submitDraft()
        #expect(review.phase == .review)
        await library.acceptPasteReview()
        #expect(env.exists("songs/harbour-lights.cho"))
    }

    @Test
    func `start blank closes the sheet and opens a new song focused on Title`() async throws {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        library.beginNewSongFlow()
        library.startBlank()
        #expect(library.pasteReview == nil)
        #expect(library.detail == .newSong)
        #expect(library.editor?.source.isEmpty == true)
        #expect(SongCardFocusRouter.shared.pending?.field == .title)
    }

    // MARK: Import routing (R96, A29)

    @Test
    func `a mixed import opens one sheet and lands as one undo step`() async throws {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        let manager = UndoManager()
        manager.groupsByEvent = false
        library.undoManager = manager
        let folder = env.scratch.appending(path: "in", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{title: Already}\n[G]Done\n".utf8).write(to: folder.appending(path: "a.cho"))
        for (name, title) in [
            ("one.txt", "Tide Song"),
            ("two.crd", "Pier Song"),
            ("three.txt", "Rope Song"),
        ] {
            let text = Self.paste.replacingOccurrences(of: "Harbour Lights", with: title)
            try Data(text.utf8).write(to: folder.appending(path: name))
        }

        await library.importWithReview([folder], method: .fileMenu)

        // The three conversion files wait in ONE sheet; the ChordPro file lands with them.
        #expect(!env.exists("songs/already.cho"))
        let review = try #require(library.pasteReview)
        #expect(review.directFiles.map(\.fileName) == ["a.cho"])
        #expect(review.isBatch)
        #expect(review.items.count == 3)
        #expect(Set(review.items.map(\.source)) == [.fileTxt, .fileCrd])
        let rope = try #require(review.items.first { $0.fileName == "three.txt" })
        review.setTicked(false, for: rope.id)
        #expect(review.acceptTitle == "Import 3 Songs")

        manager.beginUndoGrouping()
        await library.acceptPasteReview()
        manager.endUndoGrouping()

        #expect(env.exists("songs/tide-song.cho"))
        #expect(env.exists("songs/pier-song.cho"))
        #expect(!env.exists("songs/rope-song.cho"))
        let summary = try #require(library.importSummary)
        #expect(env.exists("songs/already.cho"))
        #expect(summary.imported.count == 3)
        #expect(summary.skipped.map(\.fileName) == ["three.txt"])
        #expect(library.catalog.count == 3)

        // One Undo Import removes all three.
        #expect(manager.undoActionName == "Import")
        manager.undo()
        try await env.waitFor { library.catalog.isEmpty ? true : nil }
        #expect(!manager.canUndo)
    }

    @Test
    func `cancelling a mixed import still imports its ChordPro files`() async throws {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        let folder = env.scratch.appending(path: "mixed", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{title: Already}\n[G]Done\n".utf8).write(to: folder.appending(path: "a.cho"))
        try Data(Self.paste.utf8).write(to: folder.appending(path: "p.txt"))
        await library.importWithReview([folder], method: .dragDrop)
        await library.cancelPasteReview()
        #expect(env.exists("songs/already.cho"))
        #expect(!env.exists("songs/harbour-lights.cho"))
        let summary = try #require(library.importSummary)
        #expect(summary.skipped.map(\.reason) == [LibraryViewModel.cancelledReason])
    }

    // MARK: During a show (R95, R109)

    @Test
    func `during a show paste routes are off, New Song starts blank, ChordPro still imports`()
        async throws
    {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        library.isPerforming = true
        #expect(!library.canPaste)
        #expect(library.pasteUnavailableReason == LibraryViewModel.pasteDuringShowReason)

        library.beginPasteReview(text: Self.paste, source: .clipboard)
        #expect(library.pasteReview == nil)

        library.beginNewSongFlow()
        #expect(library.pasteReview == nil)
        #expect(library.detail == .newSong)
        library.closeEditor()

        let folder = env.scratch.appending(path: "show", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{title: Encore}\n[G]Done\n".utf8).write(to: folder.appending(path: "e.cho"))
        try Data(Self.paste.utf8).write(to: folder.appending(path: "p.txt"))
        await library.importWithReview([folder], method: .dragDrop)
        #expect(library.pasteReview == nil)
        #expect(env.exists("songs/encore.cho"))
        #expect(!env.exists("songs/harbour-lights.cho"))
        // Nothing in the main window moves on stage: no selection, no editor.
        #expect(library.selection == nil)
        #expect(library.editor == nil)
        let skipped = try #require(library.importSummary?.skipped)
        #expect(skipped.map(\.reason) == [LibraryViewModel.pasteDuringShowReason])
    }

    // MARK: Refinement streaming and analytics

    @Test
    func `AI labels stream in, are marked, and the accepted paste is recorded`() async throws {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        let recording = RecordingLog(url: env.scratch.appending(path: "services.jsonl"))
        library.services = ServicesHub(
            factory: RecordingServicesFactory(log: recording),
            consent: ConsentState(analytics: .granted(.now), crashReports: .declined(.now)),
            throttle: AnalyticsThrottle(suiteName: env.suiteName, clock: env.clock),
        )
        let base = IngestPipeline.ingest(Self.paste, origin: .paste)
        let task = try #require(PasteRefiner.labelTask(for: base))
        let labels = task.blocks.map { block -> SectionLabel in
            base.questions.unheadedBlocks.contains(block.index)
                ? (block.index == base.questions.unheadedBlocks.first ? .verse : .chorus)
                : (base.blocks[block.index].label ?? .other)
        }
        let provider = try ScriptedProvider(
            id: .foundationModels,
            recordings: [.answered(task, SectionLabelOutput(labels: labels))],
            onMissing: { _ in },
        )
        library.aiRouter = Router(providers: [provider])

        library.beginPasteReview(text: Self.paste, source: .clipboard)
        let item = try #require(library.pasteReview?.selected)
        try await env.waitFor { item.status == .finished ? true : nil }
        #expect(!item.aiLabelledBlocks.isEmpty)
        #expect(item.text != base.text)
        let footer = PasteFooter.make(
            status: item.status,
            reports: item.reports,
            aiEnabled: true,
            availability: [.mlx: .unavailable(.notInstalled), .foundationModels: .available],
        )
        #expect(footer.producedBy == "Labels by Apple Intelligence")
        #expect(footer.showsDownloadLink)

        await library.acceptPasteReview()

        let signal = try #require(recording.entries().first {
            $0["name"] as? String == "Segue.AI.pasteFinished"
        })
        let params = try #require(signal["params"] as? [String: String])
        #expect(params["segue.source"] == "clipboard")
        #expect(params["segue.provider"] == "fm")
        #expect(params["segue.fallback"] == "notInstalled")
        #expect(params["segue.outcome"] == "accepted")
        #expect(params["segue.correction"] == "none")
        #expect(params["segue.romanHindi"] == "false")
    }

    @Test
    func `editing stops refinement so it never overwrites the user`() async throws {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        let provider = ScriptedProvider(id: .foundationModels, onMissing: { _ in })
        library.aiRouter = Router(providers: [provider])
        library.beginPasteReview(text: Self.paste, source: .clipboard)
        let item = try #require(library.pasteReview?.selected)
        item.edit(item.text + "\n{comment: mine}\n")
        #expect(item.status == .stopped)
        #expect(item.text.hasSuffix("{comment: mine}\n"))
    }

    @Test
    func `with AI off the footer says so and offers no download`() async throws {
        let task = try #require(PasteRefiner.labelTask(for: IngestPipeline.ingest(
            Self.paste,
            origin: .paste,
        )))
        let report = await Router(providers: [], isEnabled: { false }).run(task).report
        let footer = PasteFooter.make(
            status: .finished,
            reports: [.sectionLabels: report],
            aiEnabled: false,
            availability: [.mlx: .unavailable(.notInstalled)],
        )
        #expect(footer.producedBy == PasteFooter.aiOffLine)
        #expect(!footer.showsDownloadLink)
        #expect(PasteAnalytics.routing([.sectionLabels: report]) == (.noProvider, .aiOff))
    }
}
