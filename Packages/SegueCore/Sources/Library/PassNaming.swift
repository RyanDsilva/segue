// Owner: P8-2. Names of the passes of a slot arrangement (R147, R149): "Chorus 2/3" on the
// stage map and the editor's chips, "2 of 3" in the stage gutter. One function names all of
// them, so "2 of 3" means the same everywhere.

import Foundation

/// A pass's name: its part's title, a short form, and its number among the shown passes
/// with the same label.
public struct PassName: Sendable, Hashable {
    /// "Chorus", "Verse 2", "Lead-in", "After Verse 2".
    public var title: String
    /// "C", "V2", "Lead", "+V2" (`PassNaming.short`).
    public var short: String
    /// 1-based among the shown passes with this label; nil for a skipped pass and for a
    /// label shown once.
    public var number: Int?
    /// How many shown passes carry this label.
    public var total: Int

    public init(title: String, short: String, number: Int?, total: Int) {
        self.title = title
        self.short = short
        self.number = number
        self.total = total
    }

    /// "Chorus 2/3", or "Chorus" when unnumbered.
    public var chipText: String {
        number.map { "\(title) \($0)/\(total)" } ?? title
    }

    /// "2 of 3", or nil when unnumbered.
    public var badgeText: String? {
        number.map { "\($0) of \(total)" }
    }
}

public enum PassNaming {
    /// The names of an arrangement's passes against the song's parts; nil for a pass that
    /// does not resolve. Skip passes are named but not numbered.
    public static func names(
        _ passes: [ArrangementPass],
        units: [SongSectionUnit],
    ) -> [PassName?] {
        let resolved = passes.map { ArrangementResolver.unit(for: $0, in: units) }
        let present = resolved.indices.filter { resolved[$0] != nil }
        let names = Self.names(
            titles: present.map { resolved[$0]?.title ?? "" },
            shown: present.map { passes[$0].isShown },
        )
        var result = [PassName?](repeating: nil, count: passes.count)
        for (offset, index) in present.enumerated() {
            result[index] = names[offset]
        }
        return result
    }

    /// Names for passes by title, in order: shown passes sharing a label key
    /// (`SectionNotes.key`) are numbered "1 of n" ... "n of n"; a pass that is not shown
    /// gets no number and is not counted.
    public static func names(titles: [String], shown: [Bool]) -> [PassName] {
        let keys = titles.map(SectionNotes.key)
        var totals: [String: Int] = [:]
        for (key, isShown) in zip(keys, shown) where isShown {
            totals[key, default: 0] += 1
        }
        var seen: [String: Int] = [:]
        return titles.indices.map { index in
            let key = keys[index]
            let total = totals[key] ?? 0
            var number: Int?
            if shown.indices.contains(index), shown[index] {
                let next = (seen[key] ?? 0) + 1
                seen[key] = next
                number = total > 1 ? next : nil
            }
            return PassName(
                title: titles[index],
                short: short(titles[index]),
                number: number,
                total: total,
            )
        }
    }

    /// The short form for a narrow chip: "Verse 2" -> "V2", "Chorus" -> "C", "Pre Chorus" ->
    /// "PC", "Lead-in" -> "Lead", "After Verse 2" -> "+V2"; otherwise the initials of each
    /// word plus a trailing number.
    public static func short(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if trimmed.caseInsensitiveCompare("Lead-in") == .orderedSame {
            return "Lead"
        }
        let afterPrefix = "After "
        if trimmed.count > afterPrefix.count,
           trimmed.lowercased().hasPrefix(afterPrefix.lowercased())
        {
            return "+" + short(String(trimmed.dropFirst(afterPrefix.count)))
        }
        let words = trimmed
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .map(String.init)
        var initials = ""
        var number = ""
        for (offset, word) in words.enumerated() {
            if offset == words.count - 1, offset > 0, word.allSatisfy(\.isNumber) {
                number = word
            } else if let first = word.first {
                initials += first.uppercased()
            }
        }
        return initials.isEmpty ? trimmed : initials + number
    }
}
