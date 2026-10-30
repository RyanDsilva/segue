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

    // MARK: - Custom names offered again (R159)

    /// The custom section kinds used in `document`, de-duplicated (case-insensitively, as
    /// directives compare), in order of first appearance and spelled as first written. Not
    /// listed: the built-in kinds, Intro and Outro (already chips), Grid (a verbatim block)
    /// and labels (`{start_of_verse: Hook}` is a verse: a chip applies a kind).
    public static func customKinds(in document: SongDocument) -> [SectionKind] {
        var seen: Set<String> = []
        var kinds: [SectionKind] = []
        for block in document.blocks {
            guard case let .section(section) = block, isOfferedCustom(section.kind),
                  seen.insert(directiveKey(section.kind)).inserted
            else { continue }
            kinds.append(section.kind)
        }
        return kinds
    }

    /// The custom section kinds used across `documents` (the library), most used first:
    /// ranked by the number of songs using each (a one-off typo sinks to the bottom), then
    /// by display name; at most `limit`. Each kind is spelled as first seen.
    public static func customKinds(
        in documents: some Sequence<SongDocument>,
        limit: Int = 20,
    ) -> [SectionKind] {
        var counts: [String: Int] = [:]
        var spelling: [String: SectionKind] = [:]
        for document in documents {
            for kind in customKinds(in: document) {
                let key = directiveKey(kind)
                counts[key, default: 0] += 1
                if spelling[key] == nil {
                    spelling[key] = kind
                }
            }
        }
        let ranked = spelling.sorted { lhs, rhs in
            let left = counts[lhs.key] ?? 0
            let right = counts[rhs.key] ?? 0
            if left != right {
                return left > right
            }
            return displayName(lhs.value).localizedStandardCompare(displayName(rhs.value))
                == .orderedAscending
        }
        return ranked.prefix(limit).map(\.value)
    }

    /// Kinds never offered as extra names: the fixed chips and menu items, and Grid.
    private static let fixedKinds: [SectionKind] = [
        .verse, .chorus, .bridge, .tab, .custom("intro"), .custom("outro"),
    ]

    /// How directives compare a custom kind: its name, case-insensitively.
    private static func directiveKey(_ kind: SectionKind) -> String {
        if case let .custom(name) = kind {
            return name.lowercased()
        }
        return displayName(kind).lowercased()
    }

    private static func isOfferedCustom(_ kind: SectionKind) -> Bool {
        guard case .custom = kind, !DirectiveLine.isVerbatimSection(kind) else { return false }
        return !fixedKinds.contains { DirectiveLine.sameSectionKind($0, kind) }
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
