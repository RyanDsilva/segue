// Owner: P3-11. The one numbering rule for new section labels, shared by the visual
// editor's section band and the Text mode slash menu (P3-10).

import ChordPro
import Foundation

/// Display names and automatic numbering for section labels.
public enum SectionLabels {
    /// The plain name of a kind: "Verse", "Chorus", "Bridge", "Tab", or a custom kind's
    /// name with underscores as spaces and capitalised ("pre_chorus" -> "Pre Chorus").
    public static func displayName(_ kind: SectionKind) -> String {
        switch kind {
        case .verse: "Verse"
        case .chorus: "Chorus"
        case .bridge: "Bridge"
        case .tab: "Tab"
        case let .custom(name): name.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// The label for a new section of `kind`: "<Name> N", where N is one more than both
    /// the number of sections of that kind already in the song and the highest number any
    /// of their labels carries ("Verse 2" when "Verse 1" exists; "Chorus 2" when one
    /// unlabelled chorus exists).
    public static func next(for kind: SectionKind, in document: SongDocument) -> String {
        let name = displayName(kind)
        var count = 0
        var highest = 0
        for case let .section(section) in document.blocks
            where DirectiveLine.sameSectionKind(section.kind, kind)
        {
            count += 1
            if let number = number(in: section.label, after: name) {
                highest = max(highest, number)
            }
        }
        return "\(name) \(max(count, highest) + 1)"
    }

    /// N in a label "<name> N" (case-insensitive, any spacing), else nil.
    private static func number(in label: String?, after name: String) -> Int? {
        guard let label else { return nil }
        let words = label.split(whereSeparator: \.isWhitespace)
        guard words.count >= 2, let number = Int(words[words.count - 1]), number > 0 else {
            return nil
        }
        let head = words.dropLast().joined(separator: " ")
        return head.caseInsensitiveCompare(name) == .orderedSame ? number : nil
    }
}
