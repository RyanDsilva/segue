import Foundation

/// Whether a converted sheet's lyrics read as romanized Hindi (Hindi in Latin letters), for
/// the opt-in `romanHindi` flag of `Segue.AI.pasteFinished` (R98). Detection only: nothing
/// is transliterated, translated or respelled.
///
/// The rule: at least `minimumHits` lyric-line words, of at least `minimumDistinct` different
/// spellings, are common Hindi function words that are not English words. Casual spellings
/// are listed side by side (`hai`/`hain`/`hei`). Data, with its tests; add words, never
/// logic.
public enum RomanizedHindi {
    public static let minimumHits = 4
    public static let minimumDistinct = 3

    /// Common Hindi words in their usual Latin spellings (none is an English word).
    public static let markers: Set = [
        "hai", "hain", "hei", "hoon", "hun", "tha", "thi", "mein", "mai",
        "mera", "meri", "tera", "teri", "tere", "tum", "tumhe", "tujhe", "mujhe",
        "kya", "kyun", "kyon", "nahi", "nahin", "naa", "bhi", "dil", "pyaar", "pyar", "ki",
        "ka", "ko", "se", "aur", "ye", "yeh", "woh", "wo", "jo", "koi", "kabhi", "phir",
        "sab", "saath", "raat", "aaj", "kal", "zindagi", "jaane", "jaana",
        "humko", "tujhko", "mujhko", "rahi", "raha", "rahe", "gaya", "gayi", "lagta", "lage",
    ]

    /// Whether `result`'s lyric lines carry enough Hindi marker words.
    public static func isDetected(in result: IngestResult) -> Bool {
        var hits = 0
        var distinct: Set<String> = []
        for line in result.lines where line.lineClass == .lyricLine {
            for token in line.text.split(whereSeparator: { !$0.isLetter }) {
                let word = token.lowercased()
                guard markers.contains(word) else { continue }
                hits += 1
                distinct.insert(word)
            }
        }
        return hits >= minimumHits && distinct.count >= minimumDistinct
    }
}
