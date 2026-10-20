import Foundation

/// Section header recognition: `[Verse 1]`, `Chorus:`, `Chorus: (x2)`, `(Chorus)`, `V1`, `CH x2`,
/// `Mukhda:` (chorus hint), `Antara 2:` (verse hint), `Intro: C G Am F`, `[Chorus] (play loud)`,
/// and any bracketed name (`[Harmonies]`: the header text stays the label, the kind is left to
/// the model).
enum HeaderParser {
    static func parse(_ line: String) -> HeaderInfo? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 60 else { return nil }
        if let match = trimmed.wholeMatch(of: /\[([^\[\]]+)\]\s*(.*)/) {
            return bracketed(String(match.output.1), rest: String(match.output.2))
        }
        if let match = trimmed.wholeMatch(of: /\(([^()]+)\)/) {
            let inner = String(match.output.1).trimmingCharacters(in: .whitespaces)
            guard isBareHeader(inner) else { return nil }
            return HeaderInfo(text: inner, label: label(for: inner))
        }
        if let match = trimmed.wholeMatch(of: /([^:\[\]{}]{1,30}):\s*(.*)/) {
            return colon(String(match.output.1), rest: String(match.output.2))
        }
        guard isBareHeader(trimmed) else { return nil }
        return HeaderInfo(text: trimmed, label: label(for: trimmed))
    }

    /// The label a header name points at, from its words (`Intro riff` -> intro).
    static func label(for name: String) -> SectionLabel? {
        if let abbreviation = abbreviationLabel(name) {
            return abbreviation
        }
        let words = name.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        if words.contains("pre") || words.contains("prechorus") {
            return .prechorus
        }
        for word in words {
            if let label = vocabulary[word] {
                return label
            }
        }
        if words.count >= 2, words[0] == "middle", ["8", "eight"].contains(words[1]) {
            return .bridge
        }
        return nil
    }

    // MARK: - Forms

    private static func bracketed(_ inner: String, rest: String) -> HeaderInfo? {
        let name = inner.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !ChordLines.isChord(name) else { return nil }
        return withRest(name, rest: rest, requireVocabulary: false)
    }

    private static func colon(_ name: String, rest: String) -> HeaderInfo? {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard name.split(separator: " ").count <= 4, label(for: name) != nil else { return nil }
        return withRest(name, rest: rest, requireVocabulary: true)
    }

    /// Accepts an empty rest, a repeat mark (kept in the label) or a chord line.
    private static func withRest(
        _ name: String,
        rest: String,
        requireVocabulary: Bool,
    ) -> HeaderInfo? {
        let rest = rest.trimmingCharacters(in: .whitespaces)
        let found = label(for: name)
        if requireVocabulary, found == nil {
            return nil
        }
        if rest.isEmpty {
            return HeaderInfo(text: name, label: found)
        }
        // A repeat mark or a performance note in parentheses stays in the label
        // (`[Chorus] (play loud)` -> `Chorus (play loud)`).
        if ChordLines.isRepeatMark(rest) || rest.wholeMatch(of: /\([^()]{1,40}\)/) != nil {
            return HeaderInfo(text: "\(name) \(rest)", label: found)
        }
        if ChordLines.isChordLine(rest) {
            return HeaderInfo(text: name, label: found, trailingChords: rest)
        }
        // Chords written inline after the header (`Music: [D#] [G#]`).
        if ChordLines.hasInlineChords(rest), Segmenter.lyricKey(rest).isEmpty {
            let chords = rest.replacing(/\[([^\[\]]+)\]/) { String($0.output.1) }
            return HeaderInfo(text: name, label: found, trailingChords: chords)
        }
        return nil
    }

    /// A header written as a plain line: a vocabulary word (optionally after `Final`,
    /// `Last` or `Repeat`), then only numbers or a repeat mark (`Chorus`, `Verse 2`,
    /// `Final Chorus x2`, `V1`, `CH x2`).
    private static func isBareHeader(_ text: String) -> Bool {
        let words = text.split(separator: " ").map(String.init)
        guard (1 ... 4).contains(words.count) else { return false }
        var index = 0
        if ["final", "last", "repeat"].contains(words[0].lowercased()), words.count > 1 {
            index = 1
        }
        let head = words[index].trimmingCharacters(in: .punctuationCharacters)
        let isVocabulary = vocabulary[head.lowercased()] != nil
            || ["pre-chorus", "prechorus"].contains(head.lowercased())
            || abbreviationLabel(head) != nil
        guard isVocabulary else { return false }
        return words[(index + 1)...].allSatisfy { word in
            word.allSatisfy(\.isNumber) || ChordLines.isRepeatMark(word)
        }
    }

    /// `V1`, `V2`, `CH`, `Ch`, `BR`, `PC`, `PRE` (case as commonly written).
    private static func abbreviationLabel(_ name: String) -> SectionLabel? {
        let core = name.split(separator: " ").first.map(String.init) ?? name
        if core.wholeMatch(of: /[Vv]\d{1,2}/) != nil {
            return .verse
        }
        switch core {
        case "Ch", "CH", "Cho", "CHO": return .chorus
        case "Br", "BR", "BRG": return .bridge
        case "PC", "Pre", "PRE": return .prechorus
        default: return nil
        }
    }

    /// Header words (lowercased). Mukhda and Antara are chorus and verse hints; the header
    /// text itself is kept as the section label.
    private static let vocabulary: [String: SectionLabel] = [
        "intro": .intro,
        "verse": .verse, "antara": .verse, "stanza": .verse,
        "prechorus": .prechorus,
        "chorus": .chorus, "refrain": .chorus, "hook": .chorus, "mukhda": .chorus,
        "bridge": .bridge, "sanchari": .bridge,
        "solo": .instrumental, "instrumental": .instrumental, "interlude": .instrumental,
        "riff": .instrumental, "break": .instrumental, "link": .instrumental,
        // Film-song sheets mark an instrumental passage `Music: (D#) (G#)`.
        "music": .instrumental,
        "turnaround": .instrumental,
        "outro": .outro, "ending": .outro, "coda": .outro,
    ]
}
