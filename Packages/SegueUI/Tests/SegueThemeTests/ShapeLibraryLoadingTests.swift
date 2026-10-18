import Diagrams
import Foundation
import Library
@testable import SegueUI
import Support
import Testing

/// The user chord shape library (lookup order step 2): loaded from disk by the real
/// `AppModel` when the library opens, and used by the editor and the song page.
@MainActor
@Suite(.serialized)
struct ShapeLibraryLoadingTests {
    @Test
    func `the user shape library loads from disk and wins over built-in shapes`() async throws {
        let env = try TestEnvironment()
        let url = env.scratch.appending(path: "Support/shape-library.json")
        let custom = GuitarShape(frets: [3, 2, 0, 0, 3, 3], fingers: [2, 1, 0, 0, 3, 4])
        var shapes = UserShapeLibrary()
        shapes.set(custom, named: "G", tuning: .standard)
        try shapes.save(to: url, fileSystem: LiveFileSystem())

        var dependencies = env.dependencies(
            location: env.location(),
            override: env.libraryURL,
            remember: false,
        )
        dependencies.shapeLibraryURL = url
        let app = AppModel(dependencies: dependencies)
        await app.start()
        let library = try #require(app.session?.library)
        #expect(library.userShapes == shapes)
        #expect(library.errorMessage == nil)

        let created = try await library.createSong(source: "{title: Shapes}\n[G]One [C]two\n")
        var prefs = created.sidecar.displayPrefs
        prefs.showDiagrams = true
        let record = try await library.updateDisplayPrefs(id: created.id, prefs)

        // The editor's diagram strip and the song page both resolve G from the library.
        library.beginEditing(record)
        let editor = try #require(library.editor)
        let editorG = try #require(editor.diagrams.first { $0.name == "G" })
        #expect(editorG.guitar?.source == .userLibrary)
        #expect(editorG.guitar?.shape == custom)
        #expect(editor.diagrams.first { $0.name == "C" }?.guitar?.source == .curated)
        let page = SongSummary.renderModel(record, userShapes: library.userShapes)
        #expect(page.diagrams.first { $0.name == "G" }?.guitar?.source == .userLibrary)
    }

    @Test
    func `a missing shape library is empty and an unreadable one is reported`() async throws {
        let env = try TestEnvironment()
        // Several in-process app instances on one library, on purpose.
        env.libraryLock = .unlocked
        var dependencies = env.dependencies(
            location: env.location(),
            override: env.libraryURL,
            remember: false,
        )
        dependencies.shapeLibraryURL = env.scratch.appending(path: "none/shape-library.json")
        let missing = AppModel(dependencies: dependencies)
        await missing.start()
        #expect(missing.session?.library.userShapes == .empty)
        #expect(missing.session?.library.errorMessage == nil)

        let broken = env.scratch.appending(path: "shape-library.json")
        try Data("not json".utf8).write(to: broken)
        dependencies.shapeLibraryURL = broken
        let unreadable = AppModel(dependencies: dependencies)
        await unreadable.start()
        let library = try #require(unreadable.session?.library)
        #expect(library.userShapes == .empty)
        #expect(library.errorMessage?.contains("chord shape library") == true)
    }
}
