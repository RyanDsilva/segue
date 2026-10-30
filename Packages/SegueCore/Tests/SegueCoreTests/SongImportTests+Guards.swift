import Foundation
import Library
import Testing

/// Import guards (R154): folder walks end on symlink loops, deep trees and huge folders;
/// UTF-16 files with a byte order mark import.
extension SongImportTests {
    private static func makeFolder(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    @Test
    func `a folder with a symlink to itself imports once and ends`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let folder = lib.url("src/loop")
        try Self.makeFolder(folder)
        try lib.write("{title: Loop Song}\nLa\n", to: "src/loop/loop-song.cho")
        try FileManager.default.createSymbolicLink(
            at: folder.appending(path: "again"),
            withDestinationURL: folder,
        )

        let summary = try await store.importSongs([folder])

        #expect(summary.imported.map(\.relativePath) == ["songs/loop-song.cho"])
        #expect(summary.skipped.isEmpty)
    }

    @Test
    func `a deep tree imports to depth 16 and reports the folder below once`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        var path = "src"
        for level in 1 ... 20 {
            path += "/d\(level)"
            try Self.makeFolder(lib.url(path))
            try lib.write("{title: Level \(level)}\nLa\n", to: "\(path)/level-\(level).cho")
        }

        let summary = try await store.importSongs([lib.url("src/d1")])

        #expect(summary.imported.count == 16)
        #expect(summary.skipped == [ImportSkip(
            fileName: "d17",
            reason: "Folder nested too deeply",
        )])
    }

    @Test
    func `a huge folder stops at the import limit with one skip line`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        try Self.makeFolder(lib.url("src/big"))
        for index in 0 ..< 600 {
            try lib.write("{title: Song \(index)}\nLa\n", to: "src/big/song-\(index).cho")
        }

        let summary = try await store.importSongs([lib.url("src/big")])

        #expect(summary.imported.count == SongImport.maxFiles)
        #expect(summary.skipped == [ImportSkip(
            fileName: "big",
            reason: "Import limit of 500 files reached; the rest of big was not read",
        )])
    }

    private static func utf16(_ text: String, bigEndian: Bool) -> Data {
        Data(text.utf16.flatMap { unit in
            let high = UInt8(unit >> 8)
            let low = UInt8(unit & 0xFF)
            return bigEndian ? [high, low] : [low, high]
        })
    }

    @Test
    func `UTF-16 files with a byte order mark import and others stay not text`() async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        try Self.makeFolder(lib.url("src"))
        let text = "{title: Notepad Song}\r\n[G]Hello\r\n"
        let little = Data([0xFF, 0xFE]) + Self.utf16(text, bigEndian: false)
        let big = Data([0xFE, 0xFF])
            + Self.utf16(text.replacingOccurrences(of: "Notepad", with: "Big"), bigEndian: true)
        let bare = Self.utf16("{title: No Mark}\n", bigEndian: false)
        try little.write(to: lib.url("src/little.txt"))
        try big.write(to: lib.url("src/big.txt"))
        try bare.write(to: lib.url("src/bare.txt"))
        try Data([0x7B, 0x00, 0x01, 0x02]).write(to: lib.url("src/binary.cho"))

        let summary = try await store.importSongs([
            lib.url("src/little.txt"), lib.url("src/big.txt"),
            lib.url("src/bare.txt"), lib.url("src/binary.cho"),
        ])

        #expect(summary.imported.map(\.document.metadata.title) == ["Notepad Song", "Big Song"])
        #expect(summary.converted == [
            "little.txt: converted from UTF-16", "big.txt: converted from UTF-16",
        ])
        #expect(summary.skipped.map(\.reason) == ["Not a text file", "Not a text file"])
        let stored = try Data(contentsOf: lib.root.url.appending(path: "songs/notepad-song.cho"))
        #expect(String(bytes: stored, encoding: .utf8)?.hasPrefix("{title: Notepad Song}") == true)
    }
}
