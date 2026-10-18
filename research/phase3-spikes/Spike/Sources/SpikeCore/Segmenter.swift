import Foundation

/// Deterministic stand-in for Normalizer + FormatDetector: splits a paste into blocks
/// and computes cheap hints. The model only ever sees block numbers + raw lines.
public struct Sheet: Sendable {
    public struct Block: Sendable {
        public var index: Int
        public var lines: [String]
        public var hint: String?
    }
    public var name: String
    public var blocks: [Block]

    public init(name: String, raw: String) {
        self.name = name
        let lines = Sheet.normalize(raw).components(separatedBy: "\n")
        var groups: [[String]] = []
        var cur: [String] = []
        for l in lines {
            if l.trimmingCharacters(in: .whitespaces).isEmpty {
                if !cur.isEmpty { groups.append(cur); cur = [] }
            } else {
                cur.append(l)
            }
        }
        if !cur.isEmpty { groups.append(cur) }
        // merge a header-only group into the following group
        var merged: [[String]] = []
        var i = 0
        while i < groups.count {
            if groups[i].count == 1, Sheet.isHeader(groups[i][0]), i + 1 < groups.count {
                merged.append(groups[i] + groups[i + 1])
                i += 2
            } else {
                merged.append(groups[i])
                i += 1
            }
        }
        blocks = merged.enumerated().map { Block(index: $0.offset, lines: $0.element, hint: nil) }
        computeHints()
    }

    static func normalize(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        t = t.replacingOccurrences(of: "\t", with: "    ")
        for (a, b) in [("\u{2018}", "'"), ("\u{2019}", "'"), ("\u{201C}", "\""), ("\u{201D}", "\"")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        return t.components(separatedBy: "\n").map {
            var x = $0
            while x.last == " " { x.removeLast() }
            return x
        }.joined(separator: "\n")
    }

    static let headerRegex = try! NSRegularExpression(
        pattern: #"^\s*(\[[^\]]+\]|\([^)]+\)|[A-Za-z][A-Za-z0-9 \-]{0,20}:(\s*\(x\d\))?|V\d|CH|BR|CH x\d)\s*$"#)
    static func isHeader(_ l: String) -> Bool {
        headerRegex.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)) != nil
    }

    static let chordRegex = try! NSRegularExpression(
        pattern: #"^\(?[A-G][#b]?(m|maj|min|dim|aug|sus|add)?[0-9]*(/[A-G][#b]?)?\)?$"#)
    static let stop: Set<String> = ["a", "am", "do", "bas", "main", "hum", "tum", "em"]
    public static func isChordLine(_ l: String) -> Bool {
        let toks = l.split(separator: " ").map(String.init).filter { !$0.isEmpty && !$0.hasPrefix("(x") && $0 != "|" }
        guard !toks.isEmpty else { return false }
        let chords = toks.filter { chordRegex.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
        // a lyric line made of chord-like words ("Main Am Bas") has lowercase words; real chord
        // lines are mostly spaced tokens. Require all tokens chords and spacing typical of chord lines.
        if chords.count != toks.count { return false }
        if toks.count >= 3, !l.contains("  "), toks.allSatisfy({ stop.contains($0.lowercased()) }) { return false }
        return true
    }
    static func isTab(_ l: String) -> Bool {
        l.range(of: #"^[eBGDAEbgdae]\|[-0-9|hpbr/\\~x ]+$"#, options: .regularExpression) != nil
    }

    static func lyricKey(_ l: String) -> String {
        let noChords = l.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
        return noChords.lowercased().filter { $0.isLetter || $0 == " " }
            .split(separator: " ").joined(separator: " ")
    }

    public enum Mode: String, Sendable { case plain, hints, masked }

    static func headerLabel(_ l: String) -> String? {
        guard isHeader(l) else { return nil }
        let w = l.lowercased()
        let table: [(String, String)] = [
            ("pre-chorus", "prechorus"), ("prechorus", "prechorus"), ("pre chorus", "prechorus"),
            ("chorus", "chorus"), ("mukhda", "chorus"), ("refrain", "chorus"),
            ("verse", "verse"), ("antara", "verse"), ("bridge", "bridge"), ("intro", "intro"),
            ("outro", "outro"), ("solo", "instrumental"), ("instrumental", "instrumental"),
            ("interlude", "instrumental"),
        ]
        for (k, v) in table where w.contains(k) { return v }
        let t = w.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("ch") { return "chorus" }
        if t.hasPrefix("v") { return "verse" }
        if t.hasPrefix("br") { return "bridge" }
        return nil
    }

    public var hasChords: Bool { blocks.contains { $0.lines.contains(where: Sheet.isChordLine) || $0.lines.contains { $0.contains("[") && $0.range(of: #"\[[A-G]"#, options: .regularExpression) != nil } } }

    func blockHasChords(_ b: Block) -> Bool {
        b.lines.contains(where: Sheet.isChordLine) || b.lines.contains { $0.range(of: #"\[[A-G][^\]]*\]"#, options: .regularExpression) != nil }
    }

    mutating func computeHints() {
        var lyricSets: [Set<String>] = []
        let sheetHasChords = hasChords
        for b in blocks.indices {
            let lyr = blocks[b].lines.filter { !Sheet.isHeader($0) && !Sheet.isChordLine($0) && !Sheet.isTab($0) }
                .map(Sheet.lyricKey).filter { $0.count > 3 }
            let set = Set(lyr)
            var parts: [String] = []
            if let h = blocks[b].lines.lazy.compactMap(Sheet.headerLabel).first { parts.append("header says \(h)") }
            if blocks[b].lines.allSatisfy({ Sheet.isHeader($0) }) {
            } else if blocks[b].lines.contains(where: Sheet.isTab), blocks[b].lines.allSatisfy({ Sheet.isTab($0) || Sheet.isHeader($0) }) {
                parts.append("guitar tab, no lyrics")
            } else if blocks[b].lines.allSatisfy({ Sheet.isChordLine($0) || Sheet.isHeader($0) }) {
                parts.append("chords only, no lyrics")
            } else {
                if sheetHasChords, !blockHasChords(blocks[b]) { parts.append("no chords") }
                if !set.isEmpty {
                    for j in 0..<b where !lyricSets[j].isEmpty {
                        let overlap = Double(set.intersection(lyricSets[j]).count) / Double(set.count)
                        if overlap >= 0.6 { parts.append("same lyrics as Block \(j)"); break }
                    }
                }
            }
            blocks[b].hint = parts.isEmpty ? nil : parts.joined(separator: "; ")
            lyricSets.append(set)
        }
    }

    /// Masked mode: lyric lines become "~lyric N~" (same text -> same N), so the model sees the
    /// song's repetition structure without any lyric text (no language check, no guardrails).
    func maskedLines(_ b: Block, ids: inout [String: Int]) -> [String] {
        b.lines.map { l in
            if Sheet.isHeader(l) || Sheet.isChordLine(l) || Sheet.isTab(l) { return l }
            let chords = l.matches(of: /\[([A-G][^\]]*)\]/).map { String($0.output.1) }
            let key = Sheet.lyricKey(l)
            let id: Int
            if let x = ids[key] { id = x } else { id = ids.count + 1; ids[key] = id }
            let words = key.split(separator: " ").count
            var s = "~lyric \(id), \(words) words~"
            if !chords.isEmpty { s += " chords: " + chords.joined(separator: " ") }
            return s
        }
    }

    public func render(blocks subset: ArraySlice<Block>? = nil, mode: Mode) -> String {
        let bs = subset ?? blocks[...]
        var out = "Chord sheet with \(blocks.count) blocks (Block 0 to Block \(blocks.count - 1)).\n"
        if subset != nil {
            out = "Part of a chord sheet with \(blocks.count) blocks; this part has Block \(bs.first!.index) to Block \(bs.last!.index). Label only these blocks.\n"
        }
        if mode == .masked {
            out += "Lyric text is hidden: each lyric line is shown as ~lyric N~, and lines with the same N have the same words.\n"
        }
        var ids: [String: Int] = [:]
        // ids must be stable across chunks: precompute over all blocks
        if mode == .masked { for b in blocks { _ = maskedLines(b, ids: &ids) } }
        for b in bs {
            out += "\nBlock \(b.index):"
            if mode != .plain, let h = b.hint { out += " (\(h))" }
            let lines = mode == .masked ? maskedLines(b, ids: &ids) : b.lines
            out += "\n" + lines.joined(separator: "\n") + "\n"
        }
        return out
    }

    /// Metadata view: top block (if it has no chords) + bottom block (if no chords) + chord list.
    public func metadataPrompt() -> String? {
        var parts: [String] = []
        if let first = blocks.first, !blockHasChords(first) || first.lines.count <= 3 {
            let lines = first.lines.filter { !Sheet.isChordLine($0) }
            parts.append("Top of the sheet:\n" + lines.prefix(8).joined(separator: "\n"))
        }
        if blocks.count > 1, let last = blocks.last, !blockHasChords(last), last.hint?.contains("same lyrics") != true {
            parts.append("Bottom of the sheet:\n" + last.lines.prefix(4).joined(separator: "\n"))
        }
        var chords: [String] = []
        for b in blocks {
            for l in b.lines {
                if Sheet.isChordLine(l) {
                    chords += l.split(separator: " ").map(String.init).filter { !$0.hasPrefix("(") }
                } else {
                    chords += l.matches(of: /\[([A-G][^\]]*)\]/).map { String($0.output.1) }
                }
            }
        }
        if parts.isEmpty && chords.isEmpty { return nil }
        if !chords.isEmpty {
            parts.append("Chords in order (first 40): " + chords.prefix(40).joined(separator: " ") + "\nLast chord: " + chords.last!)
        } else {
            parts.append("The sheet has no chords.")
        }
        return parts.joined(separator: "\n\n")
    }
}

public func loadSheets(dir: String) throws -> [Sheet] {
    let fm = FileManager.default
    let files = try fm.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".txt") }.sorted()
    return try files.map { f in
        let data = try Data(contentsOf: URL(fileURLWithPath: dir).appendingPathComponent(f))
        let s = String(decoding: data, as: UTF8.self)
        return Sheet(name: String(f.dropLast(4)), raw: s)
    }
}
