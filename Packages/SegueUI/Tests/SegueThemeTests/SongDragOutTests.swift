import Foundation
@testable import SegueUI
import Testing

/// P9-5 section 5 (P2): a library row drags out as a copy of its `.cho`, never during a show.
@MainActor
struct SongDragOutTests {
    @Test
    func `a library row drags out a copy of its cho file`() async throws {
        let env = try TestEnvironment()
        try FileManager.default.createDirectory(
            at: env.libraryURL.appending(path: "songs", directoryHint: .isDirectory),
            withIntermediateDirectories: true,
        )
        // Romanized Hindi content leaves byte for byte.
        let source = "{title: Kitaabon Wali Gali}\n[Am]Purani si gali mein [G]kitaabon ki dukaan\n"
        try env.write(source, to: "songs/kitaabon-wali-gali.cho")
        let app = try await env.openApp()
        let session = try #require(app.session)
        let record = try #require(session.library.catalog.first)

        let drag = try #require(session.dragOut(record))
        #expect(drag.fileName == "kitaabon-wali-gali.cho")
        #expect(SongFileDrag.chordPro.conforms(to: .plainText))
        let copy = try drag.writeCopy(in: env.scratch)
        #expect(copy.lastPathComponent == "kitaabon-wali-gali.cho")
        #expect(try String(contentsOf: copy, encoding: .utf8) == source)
        #expect(copy.deletingLastPathComponent() != env.libraryURL.appending(path: "songs"))
        #expect(try env.read("songs/kitaabon-wali-gali.cho") == source, "the library file stays")

        session.library.isPerforming = true
        #expect(session.dragOut(record) == nil, "nothing drags out during a show")
    }
}
