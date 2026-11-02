import Foundation
import Plugins
import Testing

/// The registry hands search sources back in the fixed group order (R182), whatever order
/// they registered in.
struct PluginRegistryTests {
    struct Source: SongSearchSource {
        var id: String
        var displayName: String {
            id
        }

        var group: SearchGroup

        func search(_: SongQuery) async throws(ImportFailure) -> [SearchCandidate] {
            []
        }

        func song(for _: SearchCandidate) async throws(ImportFailure) -> ImportedSong {
            throw .noChart(.notFound)
        }
    }

    @Test
    func `search sources come back in the fixed group order`() {
        let registry = PluginRegistry()
        registry.register(Source(id: "lyrics", group: .lyricsRecord))
        registry.register(Source(id: "pre", group: .chordPre))
        registry.register(Source(id: "tab", group: .tabJSON))
        registry.register(Source(id: "pre2", group: .chordPre))
        #expect(registry.songSearchSources.map(\.id) == ["tab", "pre", "pre2", "lyrics"])
    }
}
