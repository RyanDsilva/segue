import Foundation
import Ingest
import Library

/// Spec 6.3: LRCLIB matches keywords on the server, so "tuj mai rab" can miss "tujh mein
/// rab". When the first answer is thin and the query is romanized Hindi, at most two more
/// queries swap each word for its most common attested spelling, from a small hand-curated
/// table keyed by `RomanNormalizer`'s normal form. Deterministic, shown to the user, and
/// nothing the user typed is changed. No model is involved.
enum LyricsQueryVariants {
    /// Below this many results the variants run.
    static let thinAnswer = 5
    static let maximumVariants = 2

    /// Normal form -> spellings, most common first. Data with tests: add words, never logic.
    /// Source words shared with the romanizer's overrides (spec 7.3).
    static let spellings: [String: [String]] = [
        "mai": ["mein", "main"], "mei": ["mein", "main"], "main": ["main", "mein"],
        "tuj": ["tujh"], "tuje": ["tujhe"], "muje": ["mujhe"], "mje": ["mujhe"],
        "pyar": ["pyaar"], "kabi": ["kabhi"], "nahi": ["nahin", "nahi"], "nai": ["nahin", "nahi"],
        "hai": ["hai"], "hain": ["hain"], "kyu": ["kyun", "kyon"], "kyo": ["kyun", "kyon"],
        "wo": ["woh", "vo"], "vo": ["woh", "vo"], "yeh": ["yeh", "ye"], "ye": ["yeh", "ye"],
        "dikta": ["dikhta"], "dekta": ["dekhta"], "zindgi": ["zindagi"], "jindagi": ["zindagi"],
        "kesaria": ["kesariya"], "mereya": ["mereya"], "pehela": ["pehla"], "pehla": ["pehla"],
        "hoo": ["ho"], "dil": ["dil"], "tera": ["tera"], "teri": ["teri"],
    ]

    /// The table's key for a typed word.
    static func key(_ word: String) -> String {
        RomanNormalizer.normalizeWord(word.lowercased())
    }

    /// Whether the query reads as romanized Hindi: a marker word or a table word in it.
    static func isRomanizedHindi(_ query: String) -> Bool {
        words(query).contains { word in
            RomanizedHindi.markers.contains(word.lowercased()) || spellings[key(word)] != nil
        }
    }

    /// Up to two variant queries, none equal to the query or to each other.
    static func variants(for query: String, firstAnswerCount: Int) -> [String] {
        guard firstAnswerCount < thinAnswer, isRomanizedHindi(query) else { return [] }
        let typed = words(query)
        var seen: Set<String> = [typed.joined(separator: " ").lowercased()]
        var result: [String] = []
        for choice in 0 ..< maximumVariants {
            let variant = typed.map { word -> String in
                guard let options = spellings[key(word)] else { return word }
                return options[min(choice, options.count - 1)]
            }.joined(separator: " ")
            if seen.insert(variant.lowercased()).inserted {
                result.append(variant)
            }
        }
        return result
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
    }
}
