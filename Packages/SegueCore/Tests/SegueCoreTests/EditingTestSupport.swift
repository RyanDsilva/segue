import ChordPro
import Editing
import Foundation
import Testing

/// Shared helpers for the editing-engine suites.
enum EditingFixtures {
    /// Every `.cho` fixture, sorted.
    static let names: [String] = {
        guard let directory = Bundle.module.url(forResource: "Fixtures", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return [] }
        return files.filter { $0.hasSuffix(".cho") }.sorted()
    }()

    /// Fixtures that parse cleanly (malformed ones only promise idempotence).
    static let wellFormed = names.filter { !$0.hasPrefix("malformed-") }

    static func load(_ name: String) throws -> String {
        let url = try #require(Bundle.module.url(
            forResource: "Fixtures/\(name)",
            withExtension: nil,
        ))
        return try String(contentsOf: url, encoding: .utf8)
    }
}

extension SourceSnapshot {
    /// Applies `change` and returns the next snapshot.
    func applying(_ change: SourceChange) -> SourceSnapshot {
        SourceSnapshot(text: text.applying(change.edits))
    }

    /// Paths of every lyric line (the `.line` blocks outside tab/grid sections), in order.
    var lyricLinePaths: [BlockPath] {
        var result: [BlockPath] = []
        for (index, block) in document.blocks.enumerated() {
            switch block {
            case .line:
                result.append(BlockPath(block: index))
            case let .section(section):
                if case .tab = section.kind {
                    continue
                }
                if case let .custom(name) = section.kind, name.lowercased() == "grid" {
                    continue
                }
                for (item, inner) in section.items.enumerated() {
                    if case .line = inner {
                        result.append(BlockPath(block: index, item: item))
                    }
                }
            default:
                continue
            }
        }
        return result
    }

    /// 0-based source line indices covered by `range` (an empty range counts its line).
    func lineIndices(of range: Range<Int>) -> ClosedRange<Int> {
        let utf16 = Array(text.utf16)
        func line(at offset: Int) -> Int {
            utf16[..<min(offset, utf16.count)].count(where: { $0 == 0x0A })
        }
        let first = line(at: range.lowerBound)
        let last = range.isEmpty ? first : line(at: range.upperBound - 1)
        return first ... max(first, last)
    }
}

/// UTF-16 text of `range` in `text`.
func substring(_ text: String, _ range: Range<Int>) -> String {
    let utf16 = Array(text.utf16)
    return String(decoding: utf16[range], as: UTF16.self)
}

// MARK: - Edit assertions

func lyricPath(_ snapshot: SourceSnapshot, _ index: Int) throws -> BlockPath {
    let paths = snapshot.lyricLinePaths
    try #require(paths.indices.contains(index))
    return paths[index]
}

func lines(_ text: String) -> [String] {
    text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" })
        .map(String.init)
}

func block(_ snapshot: SourceSnapshot, _ path: BlockPath) -> Block? {
    guard snapshot.document.blocks.indices.contains(path.block) else { return nil }
    let top = snapshot.document.blocks[path.block]
    guard let item = path.item else { return top }
    guard case let .section(section) = top, section.items.indices.contains(item) else {
        return nil
    }
    return section.items[item]
}

func lyricText(_ snapshot: SourceSnapshot, _ path: BlockPath) -> String? {
    guard case let .line(line) = block(snapshot, path) else { return nil }
    return line.segments.map(\.text).joined()
}

func chordRanges(_ snapshot: SourceSnapshot, _ path: BlockPath) -> [Range<Int>] {
    var result: [Range<Int>] = []
    while let range = snapshot.sourceRange(of: ChordRef(line: path, index: result.count)) {
        result.append(range)
    }
    return result
}

/// Edits ascending, non-overlapping, minimal (no no-op edit), result idempotent through
/// the serializer.
func expectWellFormed(_ change: SourceChange, in snapshot: SourceSnapshot) throws {
    for (lhs, rhs) in zip(change.edits, change.edits.dropFirst()) {
        #expect(lhs.range.upperBound <= rhs.range.lowerBound)
    }
    for edit in change.edits {
        #expect(substring(snapshot.text, edit.range) != edit.replacement)
    }
    let after = snapshot.applying(change)
    let reserialized = ChordProSerializer.serialize(after.document)
    let (again, _) = ChordProParser.parse(reserialized)
    #expect(ChordProSerializer.serialize(again) == reserialized)
    if snapshot.parseDiagnostics.isEmpty {
        #expect(Array(reserialized.utf8) == Array(after.text.utf8))
    }
}

/// `change` is one edit equivalent to `expected` (same result, same size; trimming may
/// pick an equivalent position when the neighbouring text repeats).
func expectMinimal(
    _ change: SourceChange,
    in snapshot: SourceSnapshot,
    equals expected: TextEdit,
) throws {
    let edit = try #require(change.edits.count == 1 ? change.edits.first : nil)
    #expect(edit.range.count == expected.range.count)
    #expect(edit.replacement.utf16.count == expected.replacement.utf16.count)
    #expect(snapshot.text.applying(change.edits) == snapshot.text.applying([expected]))
}

/// `expectWellFormed`, plus every edit lies on the given lines (their content and line
/// ending).
func expectLocal(
    _ change: SourceChange,
    in snapshot: SourceSnapshot,
    lines paths: [BlockPath],
) throws {
    try expectWellFormed(change, in: snapshot)
    var allowed = Set<Int>()
    for path in paths {
        let range = try #require(snapshot.sourceRange(of: path))
        allowed.formUnion(snapshot.lineIndices(of: range))
    }
    for edit in change.edits {
        let touched = snapshot.lineIndices(of: edit.range)
        #expect(
            Set(touched).isSubset(of: allowed),
            "edit \(edit) touches lines \(touched) outside \(allowed)",
        )
    }
}
