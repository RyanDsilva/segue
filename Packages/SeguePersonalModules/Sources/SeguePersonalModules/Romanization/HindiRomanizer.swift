import Foundation

/// Devanagari to casual Bollywood romanization (spec 7, R182): a native rule engine, ported
/// rule for rule from the bake-off's prototype `segue_rules_v2`, with no dependency, runtime
/// or model. It touches only Devanagari runs: Latin text, digits, punctuation and spacing
/// pass through unchanged, and it never respells a Latin word. It runs only on text Segue
/// fetched (lyrics records and web pages), never on pasted text (Language rulings).
public enum HindiRomanizer {
    /// Whether `text` holds any Devanagari letter.
    public static func containsDevanagari(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isDevanagari)
    }

    /// `text` with every Devanagari run converted; the danda becomes a full stop.
    public static func romanize(_ text: String) -> String {
        var output = ""
        var word: [Unicode.Scalar] = []
        func flush() {
            guard !word.isEmpty else { return }
            output += romanizeWord(word)
            word.removeAll()
        }
        for scalar in text.unicodeScalars {
            if scalar == "\u{0964}" || scalar == "\u{0965}" {
                flush()
                output += "."
            } else if isDevanagari(scalar) {
                word.append(scalar)
            } else {
                flush()
                output.unicodeScalars.append(scalar)
            }
        }
        flush()
        return output
    }

    static func isDevanagari(_ scalar: Unicode.Scalar) -> Bool {
        (0x0900 ... 0x097F).contains(scalar.value) || (0xA8E0 ... 0xA8FF).contains(scalar.value)
    }

    // MARK: Words

    /// One unit: a consonant (or an independent vowel with no consonant), its vowel (nil is
    /// the inherent schwa, "" a virama) and a trailing nasal or visarga.
    struct Unit: Equatable {
        var consonant: String
        var vowel: String?
        var mark: Mark = .plain

        enum Mark: Equatable { case plain, nasal, visarga }
    }

    static func romanizeWord(_ scalars: [Unicode.Scalar]) -> String {
        let decomposed = decompose(scalars)
        let key = String(String.UnicodeScalarView(decomposed))
        if let override = Table.overrides[key] {
            return override
        }
        let units = syllabify(decomposed)
        guard !units.isEmpty else { return "" }
        var vowels = units.map(\.vowel)
        let count = units.count
        // Final schwa: dropped, except after a cluster that needs it (a conjunct ending whose
        // first consonant is not n, m, s or sh).
        if count >= 2, vowels[count - 1] == nil, units[count - 1].mark == .plain,
           !(vowels[count - 2]?.isEmpty == true && !["n", "m", "s", "sh"]
               .contains(units[count - 2].consonant))
        {
            vowels[count - 1] = ""
        }
        // Medial schwa, right to left: V C [a] C V loses the schwa, then one unit is skipped
        // so no three-consonant cluster forms (bake-off 5.5 rule 2).
        var index = count - 2
        while index >= 1 {
            if vowels[index] == nil, !units[index].consonant.isEmpty, units[index].mark == .plain,
               vowels[index - 1]?.isEmpty != true, !units[index + 1].consonant.isEmpty,
               vowels[index + 1]?.isEmpty != true
            {
                vowels[index] = ""
                index -= 2
                continue
            }
            index -= 1
        }
        var out = ""
        for (unit, vowel) in zip(units, vowels) {
            out += unit.consonant + (vowel ?? "a")
            switch unit.mark {
            case .nasal: out += "n"
            case .visarga: out += "h"
            case .plain: break
            }
        }
        out = out.replacing(/n(?=[pbm])/, with: "m")
        // Casual "eh" (bake-off 5.5 rule 3): "ah" before a consonant or the word end.
        out = casualEh(out)
        return casualEndings(out)
    }

    /// Casual "eh" (bake-off 5.5 rule 3): an "a" before "h" becomes "e" when it does not follow
    /// a vowel and the "h" is not followed by one ("pahla" -> "pehla", "rah" -> "reh").
    static func casualEh(_ word: String) -> String {
        var letters = Array(word)
        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
        var index = 0
        while index + 1 < letters.count {
            if letters[index] == "a", letters[index + 1] == "h",
               index == 0 || !vowels.contains(letters[index - 1]),
               index + 2 >= letters.count || !vowels.contains(letters[index + 2])
            {
                letters[index] = "e"
            }
            index += 1
        }
        return String(letters)
    }

    /// Word-final long vowels written short ("deewaanaa" -> "deewaana"), then "ii"/"uu" as
    /// "ee"/"oo".
    static func casualEndings(_ word: String) -> String {
        var word = word
        if word.count > 2 {
            if word.hasSuffix("aa") {
                word.removeLast()
            } else if word.hasSuffix("ee") || word.hasSuffix("ii") {
                word.removeLast(2)
                word += "i"
            } else if word.hasSuffix("oo") || word.hasSuffix("uu") {
                word.removeLast(2)
                word += "u"
            }
        }
        return word.replacingOccurrences(of: "ii", with: "ee").replacingOccurrences(
            of: "uu",
            with: "oo",
        )
    }

    /// Precomposed nukta letters (U+0958-095F) split into base plus nukta, as NFC does.
    static func decompose(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        scalars.flatMap { scalar -> [Unicode.Scalar] in
            if let base = Table.nuktaBases[scalar.value], let first = Unicode.Scalar(base) {
                return [first, "\u{093C}"]
            }
            return [scalar]
        }
    }

    static func syllabify(_ scalars: [Unicode.Scalar]) -> [Unit] {
        var units: [Unit] = []
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            let nukta = index + 1 < scalars.count && scalars[index + 1] == "\u{093C}"
            if let consonant = nukta ? Table.nuktaConsonants[scalar] : nil {
                units.append(Unit(consonant: consonant, vowel: nil))
                index += 2
                continue
            }
            if let consonant = Table.consonants[scalar] {
                units.append(Unit(consonant: consonant, vowel: nil))
            } else if let vowel = Table.vowels[scalar] {
                units.append(Unit(consonant: "", vowel: vowel))
            } else if let sign = Table.signs[scalar], !units.isEmpty {
                units[units.count - 1].vowel = sign
            } else if scalar == "\u{094D}", !units.isEmpty {
                units[units.count - 1].vowel = ""
            } else if scalar == "\u{0902}" || scalar == "\u{0901}", !units.isEmpty {
                units[units.count - 1].mark = .nasal
            } else if scalar == "\u{0903}", !units.isEmpty {
                units[units.count - 1].mark = .visarga
            }
            index += 1
        }
        return units
    }
}
