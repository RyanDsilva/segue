import Foundation
import Ingest
import Plugins
import SeguePersonalModules

/// One page's verdict (spec 16.3).
struct EvalScore {
    var row: EvalRow
    var reading: WebImportEval.Reading
    var failing: [String] = []
    var silentWrong = false

    init(row: EvalRow, reading: WebImportEval.Reading) {
        self.row = row
        self.reading = reading
        guard let gold = row.gold else {
            failing = ["no gold"]
            return
        }
        guard gold.kind == "chart" else {
            if case let .noChart(reason) = reading.failure,
               reason.rawValue == gold.kind || gold.kind == "notFound"
            {
                return
            }
            failing = ["expected \(gold.kind)"]
            silentWrong = reading.result != nil
            return
        }
        guard let result = reading.result else {
            failing = ["failed: \(String(describing: reading.failure))"]
            return
        }
        failing = Self.fieldFailures(result.metadata, gold) + Self.textFailures(result.text, gold)
        let wrongField = failing.contains { $0.hasPrefix("title") || $0.hasPrefix("artists") }
        silentWrong = wrongField && !reading.fellBack
    }

    static func fieldFailures(_ meta: IngestMetadata, _ gold: Gold) -> [String] {
        var failing: [String] = []
        if !same(meta.title, gold.title) {
            failing.append("title \(meta.title ?? "-")")
        }
        if Set((gold.artists ?? []).map(loose)) != Set(meta.artists.map(loose)) {
            failing.append("artists \(meta.artists)")
        }
        if !same(meta.album, gold.album) {
            failing.append("album \(meta.album ?? "-")")
        }
        if gold.key != nil, !same(meta.key, gold.key) {
            failing.append("key \(meta.key ?? "-")")
        }
        if meta.capo != gold.capo {
            failing.append("capo \(meta.capo.map(String.init) ?? "-")")
        }
        return failing
    }

    static func textFailures(_ text: String, _ gold: Gold) -> [String] {
        var failing: [String] = []
        if let lyrics = gold.lyrics {
            let distance = editDistance(lyricWords(text).map(loose), lyrics.map(loose))
            let accuracy = 1 - Double(distance) / Double(max(lyrics.count, 1))
            if accuracy < 0.99 {
                failing.append(String(format: "lyrics %.1f%%", accuracy * 100))
            }
        }
        if let gold = gold.chords {
            let written = chords(text)
            let common = Double(lcs(written, gold))
            let precision = common / Double(max(written.count, 1))
            let recall = common / Double(max(gold.count, 1))
            let f1 = precision + recall == 0 ? 0 : 2 * precision * recall / (precision + recall)
            if f1 < 0.98 {
                failing.append(String(format: "chords F1 %.1f%%", f1 * 100))
            }
        }
        for line in gold.mustContain ?? [] where !plain(text).contains(loose(line)) {
            failing.append("missing \"\(line.prefix(30))\"")
        }
        if let least = gold.minChords, chords(text).count < least {
            failing.append("chords \(chords(text).count) < \(least)")
        }
        if let least = gold.minLyricWords, lyricWords(text).count < least {
            failing.append("lyric words \(lyricWords(text).count) < \(least)")
        }
        // A line carrying chords is chart content (a bar line), whatever the junk rule says.
        let junk = text.components(separatedBy: "\n")
            .filter { IngestPipeline.isJunkLine($0) && !$0.contains("[") }
        if let line = junk.first {
            failing.append("junk \(junk.count): \(line.prefix(40))")
        }
        return failing
    }

    var passed: Bool {
        failing.isEmpty
    }

    private static func same(_ lhs: String?, _ rhs: String?) -> Bool {
        (lhs.map(loose) ?? "") == (rhs.map(loose) ?? "")
    }

    // MARK: Text measures

    /// The rendered `.cho` without directives, chords and section markers, as loose words.
    static func lyricWords(_ cho: String) -> [String] {
        plain(cho).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func plain(_ cho: String) -> String {
        cho.components(separatedBy: "\n")
            .filter { !$0.hasPrefix("{") && !$0.hasPrefix("#") }
            .joined(separator: "\n")
            .replacing(/\[[^\]]*\]/, with: "")
            .lowercased()
            .replacing(/[^\p{L}\p{N}\s']/, with: " ")
    }

    static func chords(_ cho: String) -> [String] {
        cho.matches(of: /\[([^\]]+)\]/).map { String($0.output.1) }
    }

    static func editDistance(_ lhs: [String], _ rhs: [String]) -> Int {
        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }
        var previous = Array(0 ... rhs.count)
        for (row, left) in lhs.enumerated() {
            var current = [row + 1] + Array(repeating: 0, count: rhs.count)
            for (col, right) in rhs.enumerated() {
                current[col + 1] = min(
                    previous[col + 1] + 1,
                    current[col] + 1,
                    previous[col] + (left == right ? 0 : 1),
                )
            }
            previous = current
        }
        return previous[rhs.count]
    }

    static func lcs(_ lhs: [String], _ rhs: [String]) -> Int {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        var previous = Array(repeating: 0, count: rhs.count + 1)
        for left in lhs {
            var current = Array(repeating: 0, count: rhs.count + 1)
            for (col, right) in rhs.enumerated() {
                current[col + 1] = left == right ? previous[col] + 1 : max(
                    previous[col + 1],
                    current[col],
                )
            }
            previous = current
        }
        return previous[rhs.count]
    }
}

func loose(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
}

/// The per-reader table (spec 16.3 output).
struct EvalReport {
    var scores: [EvalScore] = []

    mutating func add(_ score: EvalScore) {
        scores.append(score)
    }

    func render() -> String {
        var lines: [String] = []
        for site in ["ug", "chordie", "echords", "generic"] {
            let group = scores.filter { $0.row.site == site }
            guard !group.isEmpty else { continue }
            let passed = group.count(where: \.passed)
            let checked = group.filter(\.row.reviewed)
            let reviewedPass = checked.count(where: \.passed)
            let share = Double(passed) / Double(group.count) * 100
            lines.append(
                site.padding(toLength: 8, withPad: " ", startingAt: 0)
                    + " \(passed)/\(group.count) pass"
                    + " (\(Int(share.rounded()))%); reviewed \(reviewedPass)/\(checked.count);"
                    + " silent wrong \(group.count(where: \.silentWrong))"
                    + " (reviewed \(checked.count(where: \.silentWrong)))",
            )
            for score in group where !score.passed {
                let reader = score.reading.reader?.rawValue ?? "-"
                let flag = score.silentWrong ? " SILENT-WRONG" : ""
                let path = score.reading.fellBack ? " (fell back)" : ""
                let name = score.row.url.lastPathComponent.prefix(48)
                let reasons = score.failing.joined(separator: "; ")
                let tag = score.row.reviewed ? "R " : "  "
                lines.append(" \(tag)\(name) [\(reader)\(path)]\(flag): \(reasons)")
            }
        }
        let silent = scores.count(where: \.silentWrong)
        lines.append("silent wrong charts: \(silent)")
        return lines.joined(separator: "\n")
    }
}
