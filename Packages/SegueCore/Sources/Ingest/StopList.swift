import Foundation

/// Words that may look like chords but are lyrics (romanized Hindi and English).
///
/// A line containing any of these is a chord line only when every such word parses as a
/// chord and nothing else on the line fails to parse (`Am  F  C  G` is chords; `Main Am bas
/// Do pal` is a lyric). Compared case-insensitively. Data, with its own tests
/// (`IngestClassificationTests`); add words, never logic.
public enum StopList {
    public static let words: Set = [
        // English words that are (or nearly are) chord symbols.
        "a", "am", "an", "as", "at", "be", "bad", "bed", "cab", "dab", "dad", "deaf", "deed",
        "ebb", "egg", "fab", "fad", "fade", "feed", "gab", "gag", "i", "me", "my",
        // Romanized Hindi words.
        "ab", "aa", "aaj", "ae", "bas", "bhi", "dil", "do", "ek", "gaa", "hai", "hum",
        "main", "mein", "na", "ne", "o", "re", "se", "tu", "tum", "e", "dekh", "de", "ga",
        "ge", "dena", "bade", "baad", "da", "aage", "bada", "gaye", "dekhe",
    ]

    /// Whether `token` (punctuation around it ignored) is a stop word.
    public static func contains(_ token: some StringProtocol) -> Bool {
        let core = token.trimmingCharacters(in: .punctuationCharacters).lowercased()
        return words.contains(core)
    }
}
