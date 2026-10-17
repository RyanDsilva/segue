import ChordPro
import Editing
import Foundation
import MusicTheory
import Testing

/// `SourceSnapshot`: tree <-> text mapping, cursor mapping between modes, highlights and
/// diagnostics, over the real parser and the fixture corpus.
struct EditingSnapshotTests {
    @Test(arguments: EditingFixtures.names)
    func `every block path maps to its own source line`(name: String) throws {
        let text = try EditingFixtures.load(name)
        let snapshot = SourceSnapshot(text: text)
        let sourceLines = text.split(separator: /\r\n|\n|\r/, omittingEmptySubsequences: false)
            .map(String.init)
        for (index, block) in snapshot.document.blocks.enumerated() {
            let path = BlockPath(block: index)
            let range = try #require(snapshot.sourceRange(of: path))
            #expect(snapshot.path(atSourceOffset: range.lowerBound) == path)
            #expect(snapshot.path(atSourceOffset: range.upperBound) == path)
            let lineText = substring(text, range)
            #expect(sourceLines.contains(lineText))
            if case let .section(section) = block {
                #expect(lineText.contains("{"))
                for item in section.items.indices {
                    let itemPath = BlockPath(block: index, item: item)
                    let itemRange = try #require(snapshot.sourceRange(of: itemPath))
                    #expect(itemRange.lowerBound > range.upperBound)
                    #expect(snapshot.path(atSourceOffset: itemRange.lowerBound) == itemPath)
                }
            }
        }
        #expect(snapshot.sourceRange(of: BlockPath(block: snapshot.document.blocks.count)) == nil)
        if text.hasSuffix("\n") {
            #expect(snapshot.path(atSourceOffset: text.utf16.count) == nil)
        }
        #expect(snapshot.path(atSourceOffset: text.utf16.count + 1) == nil)
    }

    @Test(arguments: EditingFixtures.names)
    func `cursor maps between modes on the same line and character`(name: String) throws {
        let snapshot = try SourceSnapshot(text: EditingFixtures.load(name))
        for path in snapshot.lyricLinePaths {
            let range = try #require(snapshot.sourceRange(of: path))
            // Visual -> text -> visual is the identity for every lyric offset.
            var count = 0
            while let offset = snapshot.sourceOffset(of: LyricPosition(line: path, offset: count)) {
                #expect(range.contains(offset) || offset == range.upperBound)
                #expect(
                    snapshot.lyricPosition(atSourceOffset: offset)
                        == LyricPosition(line: path, offset: count),
                )
                count += 1
            }
            #expect(count > 0)
            // Text -> visual -> text never leaves the line and is stable.
            for offset in range.lowerBound ... range.upperBound {
                let position = try #require(snapshot.lyricPosition(atSourceOffset: offset))
                #expect(position.line == path)
                let back = try #require(snapshot.sourceOffset(of: position))
                #expect(snapshot.lyricPosition(atSourceOffset: back) == position)
            }
        }
    }

    @Test
    func `cursor mapping snaps chords and non-lyric lines`() {
        let text = "{title: Snap}\n[G]Hello [C]world\n{c: note}\nSecond\n"
        let snapshot = SourceSnapshot(text: text)
        let first = BlockPath(block: 1)
        let second = BlockPath(block: 3)
        // Inside "[C]" (offsets 23...25 hold "[C]"): snaps to the chord's lyric offset 6.
        #expect(snapshot.lyricPosition(atSourceOffset: 24) == LyricPosition(line: first, offset: 6))
        // On the title line: start of the next lyric line.
        #expect(snapshot.lyricPosition(atSourceOffset: 3) == LyricPosition(line: first, offset: 0))
        // On the comment line: start of the following lyric line.
        #expect(snapshot.lyricPosition(atSourceOffset: 34) == LyricPosition(
            line: second,
            offset: 0,
        ))
        // Past the last line: the end of the preceding lyric line.
        #expect(
            snapshot.lyricPosition(atSourceOffset: text.utf16.count)
                == LyricPosition(line: second, offset: 6),
        )
        // Lyric offset 6 maps after the chord sitting there.
        #expect(snapshot.sourceOffset(of: LyricPosition(line: first, offset: 6)) == 26)
        #expect(snapshot.sourceOffset(of: LyricPosition(line: first, offset: 12)) == nil)
        #expect(snapshot.sourceRange(of: ChordRef(line: first, index: 1)) == 23 ..< 26)
        #expect(SourceSnapshot(text: "{title: x}\n").lyricPosition(atSourceOffset: 0) == nil)
    }

    @Test
    func `UTF-16 offsets count emoji and combining marks as TextKit does`() throws {
        let text = "{key: C}\n[C]☕️🎸 caf\u{65}\u{301} [G]né\n"
        let snapshot = SourceSnapshot(text: text)
        let line = BlockPath(block: 1)
        let ns = text as NSString
        let chord = try #require(snapshot.sourceRange(of: ChordRef(line: line, index: 1)))
        #expect(ns
            .substring(with: NSRange(location: chord.lowerBound, length: chord.count)) == "[G]")
        // "☕️🎸 café " is 8 characters (the combining accent joins its "e").
        let lyric = try #require(snapshot.sourceOffset(of: LyricPosition(line: line, offset: 8)))
        #expect(lyric == chord.upperBound)
        #expect(snapshot.lyricPosition(atSourceOffset: chord.lowerBound)?.offset == 8)
    }

    @Test
    func `highlights colour chords, directives, markers and comments`() {
        let text = """
        # file comment
        {title: Colours}
        {soc}
        [G]La [N.C.]la [Hxyz]la
        {c: Softly}
        {eoc}
        {chorus}
        """
        let snapshot = SourceSnapshot(text: text)
        let runs = snapshot.highlights(in: 0 ..< text.utf16.count)
        let kinds = runs.map { ($0.kind, substring(text, $0.range)) }
        #expect(kinds.map(\.0) == [
            .fileComment, .directive, .sectionMarker, .chord, .noChord, .unknownChord,
            .commentDirective, .sectionMarker, .sectionMarker,
        ])
        #expect(kinds.map(\.1) == [
            "# file comment", "{title: Colours}", "{soc}", "[G]", "[N.C.]", "[Hxyz]",
            "{c: Softly}", "{eoc}", "{chorus}",
        ])
        for (lhs, rhs) in zip(runs, runs.dropFirst()) {
            #expect(lhs.range.upperBound <= rhs.range.lowerBound)
        }
        // A window only returns what it intersects.
        let window = snapshot.highlights(in: 40 ..< 50)
        #expect(window.map(\.kind) == [.chord, .noChord])
    }

    @Test
    func `diagnostics cover parser problems, unknown chords and defines`() throws {
        let text = """
        {title: Problems}
        {capo: two}
        {define: Hm7 base-fret 1 frets x 2 4 2 3 2}
        {define: G base-fret 1 frets 3 2 0 0 0 3}
        {define: Broken frets}
        {start_of_verse}
        [G]Fine [Qx7]odd
        {title
        """
        let snapshot = SourceSnapshot(text: text)
        let diagnostics = snapshot.diagnostics
        let summary = diagnostics.map { ($0.kind, $0.line) }
        #expect(summary.contains { $0 == (.malformedDirective, 2) })
        #expect(summary.contains { $0 == (.unusedDefine, 3) })
        #expect(!summary.contains { $0 == (.unusedDefine, 4) })
        #expect(summary.contains { $0 == (.malformedDefine, 5) })
        #expect(summary.contains { $0 == (.unclosedSection, 6) })
        #expect(summary.contains { $0 == (.unknownChord, 7) })
        #expect(summary.contains { $0 == (.malformedDirective, 8) })
        let unknown = try #require(diagnostics.first { $0.kind == .unknownChord })
        #expect(substring(text, unknown.range) == "[Qx7]")
        #expect(snapshot.chordDefinitions.map(\.name) == ["Hm7", "G"])
    }

    @Test
    func `chords are listed in source order with their references`() throws {
        let snapshot = try SourceSnapshot(text: EditingFixtures.load("basic-verse-chorus.cho"))
        let chords = snapshot.chords
        #expect(chords.prefix(4).map(\.token.original) == ["G", "Em", "C", "D"])
        #expect(chords.allSatisfy { snapshot.sourceRange(of: $0.ref) != nil })
        #expect(chords.allSatisfy { $0.token.chord != nil })
        let tabs = try SourceSnapshot(text: EditingFixtures.load("generic-sections.cho"))
        #expect(tabs.chords.map(\.token.original) == ["Em", "C", "G", "D", "Em", "C", "G", "D"])
    }
}
