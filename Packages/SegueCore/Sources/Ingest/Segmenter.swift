import Foundation

/// Splits classified lines into blocks and computes per-block hints (ported from the
/// phase 3 spike's `SpikeCore/Segmenter.swift`).
enum Segmenter {
    /// Blocks on blank lines; a header line inside a block starts a new block; a block that
    /// is only a header joins the block after it (unless that one starts with a header).
    static func groups(_ lines: [IngestLine]) -> [[IngestLine]] {
        var groups: [[IngestLine]] = []
        var current: [IngestLine] = []
        for line in lines {
            if line.lineClass == .blank {
                if !current.isEmpty {
                    groups.append(current)
                    current = []
                }
            } else if line.lineClass == .headerLine, !current.isEmpty {
                groups.append(current)
                current = [line]
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty {
            groups.append(current)
        }
        var merged: [[IngestLine]] = []
        var index = 0
        while index < groups.count {
            let group = groups[index]
            if group.count == 1, group[0].lineClass == .headerLine,
               index + 1 < groups.count, groups[index + 1][0].lineClass != .headerLine
            {
                merged.append(group + groups[index + 1])
                index += 2
            } else {
                merged.append(group)
                index += 1
            }
        }
        return merged
    }

    /// Fills `hints` on every block.
    static func computeHints(_ blocks: inout [IngestBlock]) {
        let sheetHasChords = blocks.contains(where: hasChords)
        var lyricSets: [Set<String>] = []
        for index in blocks.indices {
            let block = blocks[index]
            let body = block.lines.filter { $0.lineClass != .headerLine }
            var hints = BlockHints(headerLabel: block.header?.label)
            let hasTab = body.contains { $0.lineClass == .tab }
            if hasTab, body.allSatisfy({ [.tab, .unknown].contains($0.lineClass) }) {
                hints.guitarTab = true
            } else if hasChords(block), body.allSatisfy({ isChordOnly($0) }) {
                hints.chordsOnly = true
            } else {
                hints.noChords = sheetHasChords && !hasChords(block)
            }
            let keys = Set(body.filter { $0.lineClass == .lyricLine }.map { lyricKey($0.text) }
                .filter { $0.count > 3 })
            if !hints.guitarTab, !hints.chordsOnly, !keys.isEmpty {
                hints.sameLyricsAs = lyricSets.indices.first { earlier in
                    let other = lyricSets[earlier]
                    guard !other.isEmpty else { return false }
                    let overlap = Double(keys.intersection(other).count) / Double(keys.count)
                    return overlap >= 0.6
                }
            }
            blocks[index].hints = hints
            lyricSets.append(keys)
        }
    }

    static func hasChords(_ block: IngestBlock) -> Bool {
        block.header?.trailingChords != nil || block.lines.contains { line in
            line.lineClass == .chordLine
                || line.lineClass == .lyricLine && ChordLines.hasInlineChords(line.text)
        }
    }

    private static func isChordOnly(_ line: IngestLine) -> Bool {
        switch line.lineClass {
        case .chordLine, .directive: true
        case .lyricLine: lyricKey(line.text).isEmpty && ChordLines.hasInlineChords(line.text)
        default: false
        }
    }

    /// Lowercased letters and single spaces, inline chords removed (the "same lyrics"
    /// comparison key; never shown or written).
    static func lyricKey(_ line: String) -> String {
        let noChords = line.replacing(/\[[^\]]*\]/, with: "")
        return noChords.lowercased()
            .filter { $0.isLetter || $0 == " " }
            .split(separator: " ")
            .joined(separator: " ")
    }
}
