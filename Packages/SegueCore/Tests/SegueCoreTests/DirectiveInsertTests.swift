import ChordPro
import Editing
import Foundation
import Testing

/// `EditOperation.insertDirective` (P8-7 section 6.1, R167 Q2): one canonical line, byte-
/// minimal, only `key`, `time` and `tempo`.
struct DirectiveInsertTests {
    static let source = "{title: Lift}\r\n{key: G}\r\n{start_of_verse}\r\n[G]One\r\n[C]Two\r\n"
        + "{end_of_verse}\r\n{start_of_chorus}\r\n[D]Three\r\n{end_of_chorus}\r\n"

    static func insert(_ name: String, _ value: String, before path: BlockPath) throws -> String {
        let snapshot = SourceSnapshot(text: source)
        let change = try DocumentEditor.change(
            for: .insertDirective(name: name, value: value, before: path),
            in: snapshot,
        )
        return source.applying(change.edits)
    }

    @Test
    func `before a section header`() throws {
        let snapshot = SourceSnapshot(text: Self.source)
        let chorus = try #require(snapshot.document.blocks.indices.last {
            if case .section = snapshot.document.blocks[$0] {
                return true
            }
            return false
        })
        let result = try Self.insert("key", "A", before: BlockPath(block: chorus))
        #expect(result == Self.source.replacingOccurrences(
            of: "{start_of_chorus}",
            with: "{key: A}\r\n{start_of_chorus}",
        ))
        #expect(ChordProParser.parse(result).0.metadata.key == "G")
    }

    @Test
    func `before a line inside a section`() throws {
        let snapshot = SourceSnapshot(text: Self.source)
        let verse = try #require(snapshot.document.blocks.indices.first {
            if case .section = snapshot.document.blocks[$0] {
                return true
            }
            return false
        })
        let result = try Self.insert("time", " 3/4 ", before: BlockPath(block: verse, item: 1))
        #expect(result == Self.source.replacingOccurrences(
            of: "[C]Two",
            with: "{time: 3/4}\r\n[C]Two",
        ))
        let tempo = try Self.insert("tempo", "120", before: BlockPath(block: verse, item: 0))
        #expect(tempo.contains("{start_of_verse}\r\n{tempo: 120}\r\n[G]One"))
    }

    @Test(arguments: [
        ("capo", "2"), ("key", "H"), ("time", "3/5"), ("tempo", "fast"), ("key", "A}"),
        ("tempo", ""),
    ])
    func `other names and bad values are refused`(name: String, value: String) {
        #expect(throws: EditError.invalidDirective(name)) {
            try Self.insert(name, value, before: BlockPath(block: 0))
        }
    }

    @Test
    func `undo restores the bytes`() throws {
        let snapshot = SourceSnapshot(text: Self.source)
        let change = try DocumentEditor.change(
            for: .insertDirective(name: "key", value: "Bb", before: BlockPath(block: 2)),
            in: snapshot,
        )
        #expect(change.actionName == "Insert Key Change")
        // Byte-minimal: one inserted line, nothing else touched.
        #expect(change.edits.count == 1)
        #expect(change.edits.first?.range.isEmpty == true)
        let after = Self.source.applying(change.edits)
        // The text view's undo: each replacement put back.
        let original = Self.source as NSString
        var shift = 0
        let inverse = change.edits.map { edit in
            let start = edit.range.lowerBound + shift
            shift += edit.replacement.utf16.count - edit.range.count
            return TextEdit(
                range: start ..< start + edit.replacement.utf16.count,
                replacement: original.substring(with: edit.nsRange),
            )
        }
        #expect(after.applying(inverse) == Self.source)
    }
}
