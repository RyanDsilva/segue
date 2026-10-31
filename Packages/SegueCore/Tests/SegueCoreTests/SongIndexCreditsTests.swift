import Foundation
@testable import Library
import Testing

/// The index's album columns and any-artist search (P8-8 sections 3.5, 3.9, 4.3).
struct SongIndexCreditsTests {
    static let songs = [
        "{title: Ghar More Pardesiya}\n{artist: Shreya Ghoshal}\n{album: Kalank}\n[G]Ghar more\n",
        "{title: Dilli Nights}\n{artist: Vishal}\n{artist: Shekhar}\n[Am]Raat hai\n",
        "{title: Dus Bahane}\n{artist: Vishal & Shekhar}\n{album: Dus}\n[C]Dus bahane\n",
        "{title: River Song}\n{artist: The Fixtures}\n[G]Down by the river\n",
    ]

    static func library() async throws -> (TestLibrary, LibraryStore) {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        for source in songs {
            _ = try await store.createSong(source: source)
        }
        return (lib, store)
    }

    @Test
    func `the index version is 4 for the album columns`() {
        #expect(SongIndex.schemaVersion == 4)
        #expect(SongIndex.version / 1000 == 4)
        #expect(SongIndex.version % 1000 == RomanNormalizer.version)
    }

    @Test(arguments: [
        ("kalank", ["Ghar More Pardesiya"]),
        ("Kalank", ["Ghar More Pardesiya"]),
        ("kalaank", ["Ghar More Pardesiya"]),
        // The edit-distance tier stays on titles and first lines.
        ("kalnk", []),
        ("shekhar", ["Dilli Nights", "Dus Bahane"]),
        ("vishal shekhar", ["Dilli Nights", "Dus Bahane"]),
        ("shreya", ["Ghar More Pardesiya"]),
    ])
    func `search finds albums and any artist`(query: String, expected: [String]) async throws {
        let (lib, store) = try await Self.library()
        _ = lib
        #expect(try await store.search(query: query).titles.sorted() == expected.sorted())
    }

}
