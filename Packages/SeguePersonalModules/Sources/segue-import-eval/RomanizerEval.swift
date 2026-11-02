import Foundation
import Library
import SeguePersonalModules

/// Scores `HindiRomanizer` against the bake-off's gold (gitignored, contains lyrics).
enum RomanizerEval {
    struct Line: Decodable {
        var devanagari: [String]
        var gold: [String]

        enum CodingKeys: String, CodingKey {
            case devanagari = "deva_words"
            case gold = "gold_words"
        }
    }

    static func run(gold url: URL) -> String {
        guard let data = try? Data(contentsOf: url),
              let lines = try? JSONDecoder().decode([Line].self, from: data)
        else { return "no gold at \(url.path)" }
        var words = 0, exact = 0, normalized = 0, linesRight = 0
        var misses: [String] = []
        for line in lines where line.devanagari.count == line.gold.count {
            var lineRight = true
            for (deva, gold) in zip(line.devanagari, line.gold) {
                let output = HindiRomanizer.romanize(deva).lowercased()
                let target = gold.lowercased()
                words += 1
                if output == target {
                    exact += 1
                }
                if RomanNormalizer.normalizeWord(output) == RomanNormalizer.normalizeWord(target) {
                    normalized += 1
                } else {
                    lineRight = false
                    if misses.count < 25 {
                        misses.append("\(output) (gold \(target))")
                    }
                }
            }
            if lineRight {
                linesRight += 1
            }
        }
        let total = Double(max(words, 1))
        let exactShare = Double(exact) / total * 100
        let normalShare = Double(normalized) / total * 100
        let lineShare = Double(linesRight) / Double(max(lines.count, 1)) * 100
        let format = "word exact %.1f%%, normalized %.1f%%, lines right %.1f%%"
        let summary = String(format: format, exactShare, normalShare, lineShare)
        let missed = misses.joined(separator: ", ")
        return "\(words) words, \(lines.count) lines: \(summary)\nmisses: \(missed)"
    }
}
