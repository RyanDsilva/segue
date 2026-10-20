// The lexicon's numeric readers (spike section 4, v3: code parses minutes, counts, BPM and
// keys). Each claims the tokens it reads, so later readers never see them.

import Foundation
import Library
import MusicTheory

extension Scan {
    // MARK: Numbers

    private static let numberWords: [String: Double] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20,
        "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "ninety": 90, "dozen": 12,
        // Hindi in Latin script (RomanNormalizer forms): ek, teen, char, panch, dedh, dhai.
        "ek": 1, "tin": 3, "char": 4, "panch": 5, "das": 10, "bis": 20, "dedh": 1.5, "dai": 2.5,
    ]

    /// The number at `index` ("45", "1.5", "two", "dedh"), if any.
    func number(at index: Int) -> Double? {
        guard let word = word(at: index) else { return nil }
        let digits = word.hasSuffix("+") ? String(word.dropLast()) : word
        if let value = Double(digits), value >= 0 {
            return value
        }
        return Self.numberWords[word] ?? Self.numberWords[RomanNormalizer.normalizeWord(word)]
    }

    // MARK: Tempo (R92: a filter only)

    private static let below: Set = [
        "under", "below", "upto", "max", "maximum", "slower", "less", "to",
    ]
    private static let above: Set = [
        "over", "above", "min", "minimum", "faster", "least", "more",
    ]

    /// "under 100 bpm", "between 100 and 130 bpm", "100-130 bpm", "120 bpm" (+/- 5).
    mutating func readTempo() {
        for index in tokens.indices {
            guard let word = word(at: index) else { continue }
            if word == "bpm" {
                claimTempo(numberAt: index - 1, unitAt: index)
            } else if word.hasSuffix("bpm"), Double(word.dropLast(3)) != nil {
                claimTempo(numberAt: index, unitAt: index)
            }
        }
    }

    /// The BPM number at `index`: "120", "100+", or the number of "120bpm".
    private func bpmValue(at index: Int) -> Double? {
        guard let word = word(at: index) else { return nil }
        if word.hasSuffix("bpm") {
            return Double(word.dropLast(3))
        }
        return number(at: index)
    }

    private mutating func claimTempo(numberAt start: Int, unitAt unit: Int) {
        // "100-130 bpm" (one token before the unit).
        if start < unit, let word = word(at: start), let range = Self.span(word) {
            claim(start ..< unit + 1, .tempo(TempoRange(min: range.0, max: range.1)))
            return
        }
        guard let value = bpmValue(at: start) else { return }
        // "between 100 and 130 bpm", "100 to 130 bpm", "from 100 to 130 bpm"
        if let link = word(at: start - 1), link == "and" || link == "to",
           let low = number(at: start - 2)
        {
            var first = start - 2
            if let lead = word(at: first - 1), lead == "between" || lead == "from" {
                first -= 1
            }
            let range = TempoRange(min: min(low, value), max: max(low, value))
            claim(first ..< unit + 1, .tempo(range))
            return
        }
        let (first, range) = bound(value, numberAt: start)
        claim(first ..< unit + 1, .tempo(range))
    }

    /// One-sided bounds and their lead words: "under 100", "less than 100", "up to 100",
    /// "at least 90", "100+"; a bare or "around" number is +/- 5.
    private func bound(_ value: Double, numberAt start: Int) -> (Int, TempoRange) {
        if word(at: start)?.hasSuffix("+") == true {
            return (start, TempoRange(min: value))
        }
        guard let previous = word(at: start - 1) else {
            return (start, TempoRange(min: value - 5, max: value + 5))
        }
        let lead = previous == "than" ? word(at: start - 2) ?? "" : previous
        let first = start - (previous == "than" ? 2 : 1)
        if Self.below.contains(lead) {
            let extended = lead == "to" && word(at: first - 1) == "up"
            return (extended ? first - 1 : first, TempoRange(max: value))
        }
        if Self.above.contains(lead) {
            let extended = lead == "least" && word(at: first - 1) == "at"
            return (extended ? first - 1 : first, TempoRange(min: value))
        }
        let around = ["around", "about", "roughly"].contains(previous)
        return (around ? start - 1 : start, TempoRange(min: value - 5, max: value + 5))
    }

    /// "100-130" -> (100, 130).
    private static func span(_ word: String) -> (Double, Double)? {
        let parts = word.split(separator: "-")
        guard parts.count == 2, let low = Double(parts[0]), let high = Double(parts[1]) else {
            return nil
        }
        return (min(low, high), max(low, high))
    }

    // MARK: Lengths

    private static let aadha = RomanNormalizer.normalizeWord("aadha")
    private static let minuteUnits: Set = ["min", "mins", "minute", "minutes", "m", "minit"]
    private static let hourUnits: Set = [
        "hour", "hours", "hr", "hrs", "h", "ganta", "gante", "ganton", "gantey",
    ]

    /// The unit of the word at `index` in seconds per unit (60 or 3600), if it is one.
    private func lengthUnit(at index: Int) -> Double? {
        guard let word = word(at: index) else { return nil }
        if Self.minuteUnits.contains(word) {
            return 60
        }
        let folded = RomanNormalizer.normalizeWord(word)
        return Self.hourUnits.contains(word) || Self.hourUnits.contains(folded) ? 3600 : nil
    }

    /// "45 min", "an hour", "1.5 hours", "two hour", "half an hour", "an hour and a half",
    /// "45min", "dedh ghanta".
    mutating func readLengths() {
        var index = 0
        while index < tokens.count {
            defer { index += 1 }
            if let (seconds, range) = attachedLength(at: index) ?? spelledLength(at: index) {
                claim(range, .length(seconds))
                index = range.upperBound - 1
            }
        }
    }

    /// "45min", "2h", "1.5hrs".
    private func attachedLength(at index: Int) -> (TimeInterval, Range<Int>)? {
        guard let word = word(at: index), let first = word.first, first.isNumber else { return nil }
        let digits = word.prefix { $0.isNumber || $0 == "." }
        let unit = String(word.dropFirst(digits.count))
        guard !unit.isEmpty, let value = Double(digits) else { return nil }
        if Self.minuteUnits.contains(unit) {
            return (value * 60, index ..< index + 1)
        }
        if Self.hourUnits.contains(unit) {
            return (value * 3600, index ..< index + 1)
        }
        return nil
    }

    private func spelledLength(at index: Int) -> (TimeInterval, Range<Int>)? {
        if let half = halfHour(at: index) {
            return half
        }
        guard let value = lengthCount(at: index), value > 0 else { return nil }
        var next = index + 1
        // "one and a half hours"
        let andAHalf = isAndAHalf(at: next)
        if andAHalf {
            next += 3
        }
        guard let unit = lengthUnit(at: next) else { return nil }
        var end = next + 1
        var extra = andAHalf ? 0.5 : 0
        // "an hour and a half", "2 hours and 15 minutes"
        if unit == 3600, !andAHalf {
            if isAndAHalf(at: end) {
                extra = 0.5
                end += 3
            } else if word(at: end) == "and", let minutes = number(at: end + 1),
                      lengthUnit(at: end + 2) == 60
            {
                extra = minutes / 60
                end += 3
            }
        }
        return ((value + extra) * unit, index ..< end)
    }

    /// "half an hour", "half hour", "aadha ghanta".
    private func halfHour(at index: Int) -> (TimeInterval, Range<Int>)? {
        guard let word = word(at: index),
              word == "half" || RomanNormalizer.normalizeWord(word) == Self.aadha
        else { return nil }
        var next = index + 1
        if let article = self.word(at: next), article == "an" || article == "a" {
            next += 1
        }
        return lengthUnit(at: next) == 3600 ? (1800, index ..< next + 1) : nil
    }

    /// The count before a length unit: a number, or "an"/"a"/"do" before an hour word.
    private func lengthCount(at index: Int) -> Double? {
        guard let word = word(at: index) else { return nil }
        if word == "an" || word == "a" || word == "do" {
            return lengthUnit(at: index + 1) == 3600 ? (word == "do" ? 2 : 1) : nil
        }
        return number(at: index)
    }

    private func isAndAHalf(at index: Int) -> Bool {
        word(at: index) == "and" && word(at: index + 1) == "a" && word(at: index + 2) == "half"
    }

    // MARK: Song counts

    private static let songWords: Set = [
        "songs", "song", "tunes", "tune", "tracks", "track", "numbers", "gaane", "gane", "gaana",
        "gana", "geet", "pieces",
    ]

    /// "10 songs", "5 mellow songs" (up to two words between; only the number and the noun
    /// are claimed, the words between stay for the tag readers), "ten tracks".
    mutating func readCounts() {
        var index = 0
        while index < tokens.count {
            defer { index += 1 }
            guard let value = number(at: index), value >= 1, value == value.rounded(),
                  lengthUnit(at: index + 1) == nil
            else { continue }
            for gap in 0 ... 2 {
                let noun = index + 1 + gap
                guard let word = word(at: noun) else { break }
                if Self.songWords.contains(word) {
                    claim(index ..< index + 1, .songCount(Int(value)))
                    used[noun] = true
                    break
                }
                if number(at: noun) != nil {
                    break
                }
            }
        }
    }

    // MARK: Keys

    private static let keyLeads: Set = ["in", "key", "keys"]
    private static let keyNegators: Set = [
        "no", "not", "nothing", "except", "avoid", "skip", "without",
    ]
    private static let keyLinks: Set = ["or", "and", ",", "nor"]

    /// "in G", "key of E minor", "songs in D or A", "no Bb", "not in F#", "Em".
    mutating func readKeys() {
        var index = 0
        while index < tokens.count {
            defer { index += 1 }
            guard !used[index] else { continue }
            let lead = tokens[index].word
            var cursor = index
            var negated = false
            if Self.keyNegators.contains(lead) {
                negated = true
                cursor += 1
                if word(at: cursor) == "in" {
                    cursor += 1
                }
            } else if Self.keyLeads.contains(lead) {
                cursor += 1
                if word(at: cursor) == "of" {
                    cursor += 1
                }
            }
            let contextual = cursor > index
            guard let (key, length) = key(at: cursor, contextual: contextual) else { continue }
            var keys = [key]
            var end = cursor + length
            // "in D or A", "in G, C and D"
            while let link = word(at: end), Self.keyLinks.contains(link),
                  let (next, nextLength) = self.key(at: end + 1, contextual: true)
            {
                keys.append(next)
                end += 1 + nextLength
            }
            // "G key", "in the key of G"
            if word(at: end) == "key" {
                end += 1
            }
            for (offset, key) in keys.enumerated() {
                let chip: SetChip = negated ? .excludeKey(key) : .key(key)
                claim(offset == 0 ? index ..< end : end ..< end, chip)
            }
            index = end - 1
        }
    }

    /// A key at `index` and how many tokens it spans ("E minor" = 2). Without a lead word
    /// only unmistakable spellings count: an upper-case letter with an accidental or "m"
    /// ("Bb", "F#m", "Em"), or a letter plus "minor"/"major" ("E minor"); a bare "A" or "a"
    /// is an article.
    private func key(at index: Int, contextual: Bool) -> (String, Int)? {
        guard let word = word(at: index) else { return nil }
        let text = tokens[index].text
        let modeWord = self.word(at: index + 1)
            .flatMap { $0 == "minor" || $0 == "major" ? $0 : nil }
        if let modeWord, let key = SongKey(parsing: Self.keyText(text) + " " + modeWord),
           text.count <= 2, text.first?.isUppercase == true || contextual,
           !(word == "a" && !contextual)
        {
            return (SongKey(canonical: key.tonic.pitchClass, mode: key.mode).name, 2)
        }
        guard let key = SongKey(parsing: Self.keyText(text)) else { return nil }
        let upper = text.first?.isUppercase == true
        let marked = text.count >= 2
        if contextual {
            // "in a minute", "in am": lower-case "a" and "am" read as words.
            if text == "a" || text == "am" {
                return nil
            }
        } else if !(upper && marked) || text == "Am" && index == 0 {
            return nil
        }
        return (SongKey(canonical: key.tonic.pitchClass, mode: key.mode).name, 1)
    }

    /// "g" -> "G", "f#m" -> "F#m", "bb" -> "Bb" (only the letter is case-folded).
    private static func keyText(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
