import ChordPro
import Editing
import Foundation
import Library
import Testing

/// Round-trip corpus for the editing engine (phase 1 spec, "Test strategy"): every fixture
/// goes through tree operations planned by `DocumentEditor`, and every resulting change
/// touches only the lines the operation targets, keeps everything else byte-identical, and
/// still round-trips through the parser and serializer.
struct EditingRoundTripTests {
    // MARK: - Generic operations over the whole corpus

    @Test(arguments: EditingFixtures.wellFormed)
    func `inserting a chord on every lyric line changes only that line`(name: String) throws {
        let snapshot = try SourceSnapshot(text: EditingFixtures.load(name))
        for path in snapshot.lyricLinePaths {
            let count = try #require(lyricText(snapshot, path)).count
            for offset in Set([0, count / 2, count]) {
                let position = LyricPosition(line: path, offset: offset)
                let change = try DocumentEditor.change(
                    for: .insertChord("Gsus4", at: position),
                    in: snapshot,
                )
                let at = try #require(snapshot.sourceOffset(of: position))
                try expectMinimal(change, in: snapshot, equals: TextEdit(
                    range: at ..< at,
                    replacement: "[Gsus4]",
                ))
                try expectLocal(change, in: snapshot, lines: [path])
                let after = snapshot.applying(change)
                #expect(after.document.plainLyrics == snapshot.document.plainLyrics)
                let caret = try #require(change.selectionAfter)
                #expect(caret == at + 7 ..< at + 7)
            }
        }
    }

    @Test(arguments: EditingFixtures.wellFormed)
    func `every existing chord can be changed, moved and deleted locally`(name: String) throws {
        let snapshot = try SourceSnapshot(text: EditingFixtures.load(name))
        for path in snapshot.lyricLinePaths {
            let count = try #require(lyricText(snapshot, path)).count
            let chordCount = chordRanges(snapshot, path).count
            for index in 0 ..< chordCount {
                let ref = ChordRef(line: path, index: index)
                let range = try #require(snapshot.sourceRange(of: ref))

                let delete = try DocumentEditor.change(for: .deleteChord(ref), in: snapshot)
                try expectMinimal(
                    delete,
                    in: snapshot,
                    equals: TextEdit(range: range, replacement: ""),
                )
                try expectLocal(delete, in: snapshot, lines: [path])

                let replace = try DocumentEditor.change(
                    for: .replaceChord(ref, with: "Bbmaj7"),
                    in: snapshot,
                )
                try expectLocal(replace, in: snapshot, lines: [path])
                let replaced = snapshot.text.applying(replace.edits)
                let expected = snapshot.text.applying([TextEdit(
                    range: range.lowerBound + 1 ..< range.upperBound - 1,
                    replacement: "Bbmaj7",
                )])
                #expect(replaced == expected)

                for operation in [
                    EditOperation.moveChord(ref, to: LyricPosition(line: path, offset: count)),
                    .duplicateChord(ref, to: LyricPosition(line: path, offset: 0)),
                ] {
                    let change = try DocumentEditor.change(for: operation, in: snapshot)
                    try expectLocal(change, in: snapshot, lines: [path])
                    let after = snapshot.applying(change)
                    #expect(after.document.plainLyrics == snapshot.document.plainLyrics)
                }
            }
        }
    }

    @Test(arguments: EditingFixtures.wellFormed)
    func `lyric edits, splits and joins stay on their lines`(name: String) throws {
        let snapshot = try SourceSnapshot(text: EditingFixtures.load(name))
        let paths = snapshot.lyricLinePaths
        for path in paths {
            let lyrics = try #require(lyricText(snapshot, path))
            guard lyrics.count >= 4 else { continue }
            let chordsBefore = chordRanges(snapshot, path).count

            // Replace the second character: chords keep their count, other lines untouched.
            let edit = try DocumentEditor.change(
                for: .editLyrics(path, range: 1 ..< 2, replacement: "Xy"),
                in: snapshot,
            )
            try expectLocal(edit, in: snapshot, lines: [path])
            let edited = snapshot.applying(edit)
            var expectedLyrics = Array(lyrics)
            expectedLyrics.replaceSubrange(1 ..< 2, with: Array("Xy"))
            #expect(lyricText(edited, path) == String(expectedLyrics))
            #expect(chordRanges(edited, path).count == chordsBefore)

            // Split in the middle and join back: the original bytes return.
            let middle = lyrics.count / 2
            let split = try DocumentEditor.change(
                for: .splitLine(at: LyricPosition(line: path, offset: middle)),
                in: snapshot,
            )
            try expectLocal(split, in: snapshot, lines: [path])
            let afterSplit = snapshot.applying(split)
            let second = path.item.map { BlockPath(block: path.block, item: $0 + 1) }
                ?? BlockPath(block: path.block + 1)
            guard case .line = block(afterSplit, second), case .line = block(afterSplit, path)
            else { continue } // a half was whitespace only: it is a blank line now
            let join = try DocumentEditor.change(for: .joinWithPrevious(second), in: afterSplit)
            #expect(afterSplit.text.applying(join.edits) == snapshot.text)
            let caret = try #require(split.selectionAfter)
            #expect(afterSplit.sourceRange(of: second)?.lowerBound == caret.lowerBound)
        }
    }

    @Test
    func `operations reject what they cannot do`() throws {
        let snapshot = try SourceSnapshot(text: EditingFixtures.load("generic-sections.cho"))
        let tab = try #require(snapshot.document.blocks.firstIndex {
            if case let .section(section) = $0, case .tab = section.kind {
                return true
            }
            return false
        })
        let tabLine = BlockPath(block: tab, item: 0)
        #expect(throws: EditError.readOnlyBlock(tabLine)) {
            try DocumentEditor.change(
                for: .insertChord("G", at: LyricPosition(line: tabLine, offset: 0)),
                in: snapshot,
            )
        }
        #expect(throws: EditError.wrongBlockKind(BlockPath(block: 0))) {
            try DocumentEditor.change(
                for: .insertChord("G", at: LyricPosition(line: BlockPath(block: 0), offset: 0)),
                in: snapshot,
            )
        }
        let missing = BlockPath(block: 999)
        #expect(throws: EditError.invalidPath(missing)) {
            try DocumentEditor.change(
                for: .deleteChord(ChordRef(line: missing, index: 0)),
                in: snapshot,
            )
        }
        let line = try #require(snapshot.lyricLinePaths.first)
        for bad in ["", "  ", "A]", "[A", "A\nB"] {
            #expect(throws: EditError.invalidChordText(bad)) {
                try DocumentEditor.change(
                    for: .insertChord(bad, at: LyricPosition(line: line, offset: 0)),
                    in: snapshot,
                )
            }
        }
        let far = LyricPosition(line: line, offset: 10000)
        #expect(throws: EditError.offsetOutOfRange(far)) {
            try DocumentEditor.change(for: .insertChord("G", at: far), in: snapshot)
        }
        #expect(throws: EditError.invalidChord(ChordRef(line: line, index: 99))) {
            try DocumentEditor.change(
                for: .deleteChord(ChordRef(line: line, index: 99)),
                in: snapshot,
            )
        }
    }

    @Test
    func `stacked chords and lyric edits follow the documented rules`() throws {
        let snapshot = SourceSnapshot(text: "[A]Hel[B]lo world\n")
        let line = BlockPath(block: 0)
        let stacked = try DocumentEditor.change(
            for: .insertChord("C", at: LyricPosition(line: line, offset: 0)),
            in: snapshot,
        )
        #expect(snapshot.text.applying(stacked.edits) == "[A][C]Hel[B]lo world\n")

        // Removed range swallows [B]'s character: the chord moves to the range start.
        let removal = try DocumentEditor.change(
            for: .editLyrics(line, range: 2 ..< 5, replacement: "y"),
            in: snapshot,
        )
        #expect(snapshot.text.applying(removal.edits) == "[A]He[B]y world\n")

        // Typing before a chord's character keeps the chord on that character.
        let typing = try DocumentEditor.change(
            for: .editLyrics(line, range: 3 ..< 3, replacement: "l"),
            in: snapshot,
        )
        #expect(snapshot.text.applying(typing.edits) == "[A]Hell[B]lo world\n")
        #expect(typing.edits == [TextEdit(range: 6 ..< 6, replacement: "l")])

        let moved = try DocumentEditor.change(
            for: .moveChord(
                ChordRef(line: line, index: 0),
                to: LyricPosition(line: line, offset: 11),
            ),
            in: snapshot,
        )
        #expect(snapshot.text.applying(moved.edits) == "Hel[B]lo world[A]\n")
    }

    @Test
    func `move across lines edits both lines and nothing between`() throws {
        let snapshot = SourceSnapshot(text: "[G]First line\n{c: keep me}\nSecond line\n")
        let change = try DocumentEditor.change(
            for: .moveChord(
                ChordRef(line: BlockPath(block: 0), index: 0),
                to: LyricPosition(line: BlockPath(block: 2), offset: 7),
            ),
            in: snapshot,
        )
        #expect(change.edits == [
            TextEdit(range: 0 ..< 3, replacement: ""),
            TextEdit(range: 34 ..< 34, replacement: "[G]"),
        ])
        #expect(change.selectionAfter == 34 ..< 34)
    }
}
