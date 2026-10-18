import Foundation
import Library
@testable import SegueUI
import Testing

/// What a drop or the open panel hands the library (WS2a 3.2): file URLs go straight into
/// `importSongs`, which saves pending edits, selects the first import, shows the summary and
/// registers Undo Import. Drag and drop from Finder itself is a manual check (spike 0c).
@MainActor
struct ImportUITests {
    @Test
    func `dropped files import, select the first song and undo as one step`() async throws {
        let env = try TestEnvironment()
        let library = try await env.openLibrary()
        let manager = UndoManager()
        manager.groupsByEvent = false
        library.undoManager = manager
        let source = env.scratch.appending(path: "drop", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let first = source.appending(path: "harbour.cho")
        let second = source.appending(path: "river.chopro")
        let picture = source.appending(path: "cover.png")
        try Data("{title: Harbour}\nLanterns\n".utf8).write(to: first)
        try Data("{title: River}\nWater\n".utf8).write(to: second)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: picture)

        manager.beginUndoGrouping()
        await library.importSongs([first, second, picture])
        manager.endUndoGrouping()

        let summary = try #require(library.importSummary)
        #expect(ImportSummaryBar.headline(summary) == "Imported 2 songs. 1 skipped.")
        #expect(summary.skipped.map(\.reason) == ["Not a ChordPro or text file"])
        #expect(library.catalog.map(Self.title) == ["Harbour", "River"])
        #expect(library.selection == summary.imported.first?.id)
        #expect(manager.undoActionName == "Import")

        manager.undo()
        try await env.waitFor { library.catalog.isEmpty ? true : nil }
        #expect(!env.exists("songs/harbour.cho"))
        #expect(manager.canRedo)

        manager.redo()
        try await env.waitFor { library.catalog.count == 2 ? true : nil }
        #expect(env.exists("songs/harbour.cho"))
        #expect(env.exists("songs/river.cho"))
    }

    @Test
    func `nothing imported still says so`() {
        let summary = ImportSummary(skipped: [ImportSkip(fileName: "a.crd", reason: "x")])
        #expect(ImportSummaryBar.headline(summary) == "No songs imported")
        #expect(ImportSummaryBar.headline(ImportSummary()) == "No songs imported")
    }

    private static func title(_ record: SongRecord) -> String {
        record.document.metadata.title ?? ""
    }
}
