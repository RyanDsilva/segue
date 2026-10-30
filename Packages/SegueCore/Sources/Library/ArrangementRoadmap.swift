// Owner: P8-3. The typed roadmap of a slot arrangement (R149): the lane of passes written as
// text, for example `I:CH V1 C V2 C -B C O:1`, and read back. Pure; the Arrange Sections
// sheet keeps its field and the lane in sync with it.

import Foundation

/// One roadmap token: a group of the song's parts that share a display label (and, for loose
/// lines, a block number), written as one short code.
public struct RoadmapToken: Sendable, Hashable {
    /// "V1", "C", "PC", "IN", "L", "V2+", "V2+2".
    public var text: String
    /// The parts' display label: "Verse 1", "Chorus", "Lead-in", "After Verse 2".
    public var title: String
    /// The group's occurrences in song order: indices into the units the tokens were derived
    /// from (a part's `SongSectionUnit.index` when the units are the whole song).
    public var units: [Int]

    public init(text: String, title: String, units: [Int]) {
        self.text = text
        self.title = title
        self.units = units
    }
}

/// Why a roadmap does not parse. The first problem wins; `message` is shown verbatim.
public enum RoadmapError: Error, Sendable, Hashable {
    /// Nothing typed (a commit of an empty field changes nothing).
    case empty
    /// `"Q" is not a part. Parts: I V1 C V2 B O.`
    case notAPart(String, parts: String)
    /// `C#4: the song has 3 Choruses.`
    case noSuchOccurrence(String, count: Int, title: String)
    /// `"C:x" - modes are :ch and :1.`
    case badMode(String)
    /// `"Cx12" - repeat a pass x2 to x9.`
    case badCount(String)
    /// `At least one part plays.`
    case nothingPlays
    /// `A slot can have up to 48 passes.`
    case tooManyPasses

    public var message: String {
        switch self {
        case .empty:
            ""
        case let .notAPart(item, parts):
            "\"\(item)\" is not a part. Parts: \(parts)."
        case let .noSuchOccurrence(item, count, title):
            "\(item): the song has \(ArrangementRoadmap.counted(count, title))."
        case let .badMode(item):
            "\"\(item)\" - modes are :ch and :1."
        case let .badCount(item):
            "\"\(item)\" - repeat a pass x2 to x9."
        case .nothingPlays:
            "At least one part plays."
        case .tooManyPasses:
            "A slot can have up to \(SlotArrangement.maxPasses) passes."
        }
    }
}

public enum ArrangementRoadmap {
    // MARK: Tokens

    /// The song's tokens in order of first appearance. A label's token is the initials of its
    /// words (split on spaces and hyphens) upper-cased, a trailing number kept ("Verse 1"
    /// V1, "Pre-Chorus" PC); on a clash with an earlier token the later one extends its first
    /// word's prefix until unique ("Instrumental" after "Intro" is IN). The lead-in is L;
    /// loose lines after a part are that part's token plus "+" (a second block "+2").
    public static func tokens(_ units: [SongSectionUnit]) -> [RoadmapToken] {
        var tokens: [RoadmapToken] = []
        var byKey: [String: Int] = [:]
        var labelTokens: [String: String] = [:]
        for (offset, unit) in units.enumerated() {
            let key = groupKey(unit)
            if let existing = byKey[key] {
                tokens[existing].units.append(offset)
                continue
            }
            let taken = Set(tokens.map { $0.text.lowercased() })
            let text: String
            switch unit.anchor {
            case .section:
                text = unique(labelCandidates(unit.title), taken: taken)
                labelTokens[SectionNotes.key(unit.title)] = text
            case let .loose(after?, block):
                let base = labelTokens[SectionNotes.key(after.label)]
                    ?? unique(labelCandidates(after.label), taken: taken)
                text = unique(["\(base)+" + (block > 1 ? "\(block)" : "")], taken: taken)
            case let .loose(nil, block):
                let lead = unique(["L"] + labelCandidates("Lead"), taken: taken)
                text = block > 1 ? unique(["\(lead)\(block)"], taken: taken) : lead
            }
            byKey[key] = tokens.count
            tokens.append(RoadmapToken(text: text, title: unit.title, units: [offset]))
        }
        return tokens
    }

    /// "I V1 C V2 B O": every token, for the help line and error messages.
    public static func partList(_ units: [SongSectionUnit]) -> String {
        tokens(units).map(\.text).joined(separator: " ")
    }

    // MARK: Format

    /// The passes as a roadmap: upper-case tokens separated by single spaces, `-` for Skip,
    /// `:CH` and `:1` for the modes, and `#n` only where the counting rule (`occurrence`)
    /// would pick a different occurrence. A pass naming no part of the song is left out.
    public static func format(_ passes: [ArrangementPass], units: [SongSectionUnit]) -> String {
        let tokens = tokens(units)
        var last: [Int: Int] = [:]
        var words: [String] = []
        for pass in passes {
            guard let unit = units.firstIndex(where: { $0.anchor.matches(pass.anchor) }),
                  let group = tokens.firstIndex(where: { $0.units.contains(unit) }),
                  let occurrence = tokens[group].units.firstIndex(of: unit).map({ $0 + 1 })
            else { continue }
            let token = tokens[group]
            var word = pass.mode == .skip ? "-" : ""
            word += token.text
            if occurrence != Self.occurrence(after: last[group], count: token.units.count) {
                word += "#\(occurrence)"
            }
            last[group] = occurrence
            switch pass.mode {
            case .chordsOnly: word += ":CH"
            case .firstLine: word += ":1"
            case .full, .skip: break
            }
            words.append(word)
        }
        return words.joined(separator: " ")
    }

    /// The counting rule (decision 10): the occurrence after the previous pass of the same
    /// group, capped at the last; the first when there is none.
    public static func occurrence(after previous: Int?, count: Int) -> Int {
        guard let previous else { return 1 }
        return min(previous + 1, max(count, 1))
    }

    // MARK: Parse

    /// Reads a roadmap: tokens separated by spaces or commas, case-insensitive. A pass is
    /// `["-"] part ["#" occurrence] [":" mode] [("x" | "×") count]`: `-` skips, `:ch` chords
    /// only, `:1` first line, `:f` full; `x2` repeats the pass (2 ... 9). A bare token
    /// follows the counting rule left to right.
    public static func parse(
        _ text: String,
        units: [SongSectionUnit],
    ) -> Result<[ArrangementPass], RoadmapError> {
        let items = text.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
        guard !items.isEmpty else { return .failure(.empty) }
        let tokens = tokens(units)
        let longestFirst = tokens.indices.sorted {
            tokens[$0].text.unicodeScalars.count > tokens[$1].text.unicodeScalars.count
        }
        var last: [Int: Int] = [:]
        var passes: [ArrangementPass] = []
        for item in items {
            switch parseItem(item, tokens: tokens, longestFirst: longestFirst, last: last) {
            case let .failure(error):
                return .failure(error)
            case let .success(parsed):
                let token = tokens[parsed.group]
                let unit = units[token.units[parsed.occurrence - 1]]
                last[parsed.group] = parsed.occurrence
                let pass = ArrangementPass(
                    anchor: unit.anchor,
                    fingerprint: unit.fingerprint,
                    mode: parsed.mode,
                )
                passes += Array(repeating: pass, count: parsed.count)
            }
        }
        if passes.count > SlotArrangement.maxPasses {
            return .failure(.tooManyPasses)
        }
        guard passes.contains(where: \.isShown) else { return .failure(.nothingPlays) }
        return .success(passes)
    }

    private struct ParsedItem {
        var group: Int
        var occurrence: Int
        var mode: PassMode
        var count: Int
    }

    /// What follows a token: a pinned occurrence, the mode and the repeat count.
    private struct Suffix {
        var occurrence: Int?
        var mode: PassMode
        var count: Int
    }

    private enum SuffixError: Error {
        case notMine
        case mode
        case count
    }

    private static func parseItem(
        _ item: String,
        tokens: [RoadmapToken],
        longestFirst: [Int],
        last: [Int: Int],
    ) -> Result<ParsedItem, RoadmapError> {
        let skip = item.hasPrefix("-")
        let body = skip ? String(item.dropFirst()) : item
        var firstError: RoadmapError?
        for group in longestFirst {
            let token = tokens[group]
            guard body.lowercased().hasPrefix(token.text.lowercased()) else { continue }
            let rest = String(body.dropFirst(token.text.count))
            let suffix: Suffix
            do {
                suffix = try parseSuffix(rest)
            } catch .mode {
                firstError = firstError ?? .badMode(item)
                continue
            } catch .count {
                firstError = firstError ?? .badCount(item)
                continue
            } catch {
                continue
            }
            let count = token.units.count
            let occurrence = suffix.occurrence ?? Self.occurrence(after: last[group], count: count)
            guard (1 ... count).contains(occurrence) else {
                return .failure(.noSuchOccurrence(
                    "\(token.text)#\(occurrence)",
                    count: count,
                    title: token.title,
                ))
            }
            return .success(ParsedItem(
                group: group,
                occurrence: occurrence,
                mode: skip ? .skip : suffix.mode,
                count: suffix.count,
            ))
        }
        return .failure(firstError ?? .notAPart(
            partName(body),
            parts: tokens.map(\.text).joined(separator: " "),
        ))
    }

    /// `#n`, `:mode` and `xN` after a token, in that order, each optional.
    private static func parseSuffix(
        _ rest: String,
    ) throws(SuffixError) -> Suffix {
        var rest = Substring(rest)
        var occurrence: Int?
        if rest.hasPrefix("#") {
            let digits = rest.dropFirst().prefix(while: \.isASCIIDigit)
            guard !digits.isEmpty, let number = Int(digits) else { throw .notMine }
            occurrence = number
            rest = rest.dropFirst(1 + digits.count)
        }
        var count = 1
        if let marker = rest.lastIndex(where: { $0 == "x" || $0 == "X" || $0 == "×" }),
           case let digits = rest[rest.index(after: marker)...],
           !digits.isEmpty, digits.allSatisfy(\.isASCIIDigit),
           rest.hasPrefix(":") || marker == rest.startIndex
        {
            guard let number = Int(digits), (1 ... 9).contains(number) else { throw .count }
            count = number
            rest = rest[..<marker]
        }
        var mode = PassMode.full
        if rest.hasPrefix(":") {
            switch rest.dropFirst().lowercased() {
            case "ch": mode = .chordsOnly
            case "1": mode = .firstLine
            case "f": mode = .full
            default: throw .mode
            }
            rest = ""
        }
        guard rest.isEmpty else { throw .notMine }
        return Suffix(occurrence: occurrence, mode: mode, count: count)
    }

    /// The part a failed item names, without its suffixes ("Q" for "Q#2:ch").
    private static func partName(_ body: String) -> String {
        let name = body.prefix { $0 != "#" && $0 != ":" }
        return name.isEmpty ? body : String(name)
    }

    // MARK: Helpers

    /// Parts sharing a token: labelled sections by label, loose lines by the label they
    /// follow and their block.
    private static func groupKey(_ unit: SongSectionUnit) -> String {
        switch unit.anchor {
        case .section:
            "s:" + SectionNotes.key(unit.title)
        case let .loose(after, block):
            "l:\(after.map { SectionNotes.key($0.label) } ?? ""):\(block)"
        }
    }

    /// Token candidates for a label, shortest first: the first word's prefix grows by one
    /// character each time.
    private static func labelCandidates(_ label: String) -> [String] {
        let words = label
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .map { word in String(word.filter { $0.isLetter || $0.isNumber }) }
            .filter { !$0.isEmpty }
        guard let first = words.first else { return ["P"] }
        var number = ""
        var others = Array(words.dropFirst())
        if words.count > 1, let tail = others.last, tail.allSatisfy(\.isNumber) {
            number = tail
            others.removeLast()
        }
        let initials = others.compactMap(\.first).map { String($0).uppercased() }.joined()
        return (1 ... first.count).map { length in
            String(first.prefix(length)).uppercased() + initials + number
        }
    }

    /// The first candidate not yet taken (case-insensitively); else the last one with a
    /// counter.
    private static func unique(_ candidates: [String], taken: Set<String>) -> String {
        if let free = candidates.first(where: { !taken.contains($0.lowercased()) }) {
            return free
        }
        let base = candidates.last ?? "P"
        var counter = 2
        while taken.contains("\(base)\(counter)".lowercased()) {
            counter += 1
        }
        return "\(base)\(counter)"
    }

    /// "3 Choruses", "1 Verse 1", "2 Verse 1 sections".
    static func counted(_ count: Int, _ title: String) -> String {
        guard count != 1 else { return "1 \(title)" }
        guard let last = title.last, last.isLetter else { return "\(count) \(title) sections" }
        let lower = title.lowercased()
        let plural = ["s", "x", "z", "ch", "sh"].contains(where: lower.hasSuffix)
            ? title + "es"
            : title + "s"
        return "\(count) \(plural)"
    }
}

private extension Character {
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
