import ChordPro
import Editing
import Testing

/// `Metadata.album` (P8-8 section 4.1): the first `{album}`, set and cleared through
/// `setDirective`.
struct MetadataAlbumTests {
    @Test(arguments: [
        ("{title: Ghar More Pardesiya}\n{album: Kalank}\n", "Kalank" as String?),
        ("{album: Kalank}\n{album: Other}\n", "Kalank"),
        ("{meta: album Kalank}\n", "Kalank"),
        ("{album:  }\n", nil),
        ("{title: S}\n", nil),
    ])
    func `read`(source: String, album: String?) {
        let metadata = ChordProParser.parse(source).0.metadata
        #expect(metadata.album == album)
    }

    @Test
    func `set and clear`() throws {
        let source = "{title: S}\n{artist: A}\n[G]La\n"
        let set = try DocumentEditor.change(
            for: .setDirective(name: "album", value: "Kalank"),
            in: SourceSnapshot(text: source),
        )
        let withAlbum = source.applying(set.edits)
        #expect(withAlbum == "{title: S}\n{artist: A}\n{album: Kalank}\n[G]La\n")
        #expect(ChordProParser.parse(withAlbum).0.metadata.album == "Kalank")
        let clear = try DocumentEditor.change(
            for: .setDirective(name: "album", value: nil),
            in: SourceSnapshot(text: withAlbum),
        )
        #expect(withAlbum.applying(clear.edits) == source)
    }
}
