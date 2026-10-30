import ChordPro
import Editing
import Foundation
import Testing

/// Custom section names offered again (R159): which names a song and the library use.
struct SectionLabelsTests {
    private static func document(_ source: String) -> SongDocument {
        ChordProParser.parse(source).0
    }

    private static func names(_ kinds: [SectionKind]) -> [String] {
        kinds.map(SectionLabels.displayName)
    }

    @Test
    func `a song's custom kinds in first-appearance order, first spelling kept`() {
        let song = Self.document("""
        {start_of_hook}
        Oh
        {end_of_hook}
        {start_of_intro}
        {end_of_intro}
        {start_of_tag}
        La
        {end_of_tag}
        {start_of_Hook}
        Oh
        {end_of_Hook}
        {start_of_outro}
        {end_of_outro}
        {start_of_grid}
        | G . |
        {end_of_grid}
        {start_of_verse: Hook}
        Words
        {end_of_verse}
        {start_of_tab}
        e|--
        {end_of_tab}
        """)
        let kinds = SectionLabels.customKinds(in: song)
        #expect(Self.names(kinds) == ["Hook", "Tag"])
        #expect(kinds.first == .custom("hook"))
    }

    @Test
    func `the library's custom kinds rank by songs using them, then name, at most 20`() {
        func song(_ kinds: [String]) -> SongDocument {
            Self.document(kinds.map { "{start_of_\($0)}\nLa\n{end_of_\($0)}\n" }.joined())
        }
        let library = [
            song(["solo", "tag", "tag"]),
            song(["tag"]),
            song(["Tag", "antara"]),
            song(["mukhda"]),
            song(["antara"]),
        ]
        #expect(Self.names(SectionLabels.customKinds(in: library))
            == ["Tag", "Antara", "Mukhda", "Solo"])

        let many = (1 ... 25).map { song(["part_\($0)"]) }
        let capped = SectionLabels.customKinds(in: many)
        #expect(capped.count == 20)
        #expect(Self.names(Array(capped.prefix(2))) == ["Part 1", "Part 2"])
    }
}
