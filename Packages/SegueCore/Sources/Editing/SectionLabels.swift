// Owner: P3-11. The one numbering rule for new section labels, shared by the visual
// editor's section band and the Text mode slash menu (P3-10).

import ChordPro
import Foundation

/// A label for a new (or re-kinded) section, plus the same-kind sections that get a number
/// at the same time ("Chorus" becomes "Chorus 1" when a second, different chorus arrives).
public struct SectionLabelProposal: Sendable, Hashable {
    /// `nil` = no label (`{start_of_chorus}`): an unnumbered section shows its kind name.
    public var label: String?
    /// Header path -> new label, for existing sections of the same kind.
    public var renames: [BlockPath: String]

    public init(label: String?, renames: [BlockPath: String] = [:]) {
        self.label = label
        self.renames = renames
    }
}

/// Display names and automatic numbering for section labels (Ryan, 2026-10-19):
/// verses are always numbered ("Verse 1", "Verse 2"); chorus, bridge, intro, outro and the
/// rest stay unnumbered until a second distinct one of that kind exists, and then all of
/// them are numbered. "Distinct" means different lyrics: a section whose lyrics repeat an
/// existing one of that kind takes the same label (the same chorus written out again).
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

    /// The label to write for a new section of `kind` whose lyrics are not known (or
    /// treated as distinct): the proposal's label, or the plain kind name when it stays
    /// unnumbered. Does not number the existing sections; `proposal` does.
    public static func next(for kind: SectionKind, in document: SongDocument) -> String {
        proposal(for: kind, lyrics: nil, in: document).label ?? displayName(kind)
    }

    /// The numbering rule. `lyrics` are the new section's lyric lines (`nil` = always
    /// distinct); `position` is the block index it will start at (`nil` = the end), so
    /// numbers follow source order; `excluding` leaves one section out (the one being
    /// re-kinded).
    public static func proposal(
        for kind: SectionKind,
        lyrics: [String]?,
        at position: Int? = nil,
        in document: SongDocument,
        excluding: BlockPath? = nil,
    ) -> SectionLabelProposal {
        let name = displayName(kind)
        let isVerse = DirectiveLine.sameSectionKind(kind, .verse)
        let same = sections(of: kind, in: document).filter { $0.path != excluding }
        let key = lyrics.map(lyricsKey) ?? ""
        if !key.isEmpty, let match = same.first(where: { $0.key == key }) {
            return SectionLabelProposal(label: match.label)
        }
        guard !same.isEmpty else {
            return SectionLabelProposal(label: isVerse ? "\(name) 1" : nil)
        }
        // The new section joins the list at its position (after a section at the same
        // block). Existing numbers stay; unnumbered sections, the new one included, take
        // their lyrics group's number, else the next free one after the highest number
        // above them, in source order.
        let new = Entry(path: nil, label: nil, key: key)
        let at = position ?? Int.max
        let ordered = same.filter { ($0.path?.block ?? 0) <= at } + [new]
            + same.filter { ($0.path?.block ?? 0) > at }
        var used = Set(same.compactMap { number(in: $0.label, after: name) })
        var byKey: [String: Int] = [:]
        for entry in same {
            if let number = number(in: entry.label, after: name), !entry.key.isEmpty {
                byKey[entry.key] = byKey[entry.key] ?? number
            }
        }
        var renames: [BlockPath: String] = [:]
        var label = ""
        var highest = 0
        for entry in ordered {
            if let number = number(in: entry.label, after: name) {
                highest = max(highest, number)
                continue
            }
            guard isUnnumbered(entry.label, name: name) else { continue }
            var number = byKey[entry.key] ?? highest + 1
            while byKey[entry.key] == nil, used.contains(number) {
                number += 1
            }
            used.insert(number)
            highest = max(highest, number)
            if !entry.key.isEmpty {
                byKey[entry.key] = number
            }
            if let path = entry.path {
                renames[path] = "\(name) \(number)"
            } else {
                label = "\(name) \(number)"
            }
        }
        return SectionLabelProposal(label: label, renames: renames)
    }

    // MARK: - Helpers

    private struct Entry {
        /// `nil` for the new section.
        var path: BlockPath?
        var label: String?
        var key: String
    }

    private static func sections(of kind: SectionKind, in document: SongDocument) -> [Entry] {
        document.blocks.enumerated().compactMap { index, block in
            guard case let .section(section) = block,
                  DirectiveLine.sameSectionKind(section.kind, kind)
            else { return nil }
            let lyrics = section.items.compactMap { item -> String? in
                guard case let .line(line) = item else { return nil }
                return line.segments.map(\.text).joined()
            }
            let label = section.label.flatMap { $0.trimmingCharacters(in: .whitespaces) }
            return Entry(
                path: BlockPath(block: index),
                label: label.flatMap { $0.isEmpty ? nil : $0 },
                key: lyricsKey(lyrics),
            )
        }
    }

    /// Lyrics compared case-insensitively with whitespace collapsed.
    static func lyricsKey(_ lines: [String]) -> String {
        lines.map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .lowercased()
    }

    private static func isUnnumbered(_ label: String?, name: String) -> Bool {
        guard let label else { return true }
        return label.caseInsensitiveCompare(name) == .orderedSame
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
