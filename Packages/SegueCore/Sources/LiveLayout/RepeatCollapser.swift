// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit B.

import ChordPro
import Editing
import Foundation
import Library

/// Repeat detection: the first occurrence always renders in full; a later section whose
/// content equals an earlier one (normalized lyrics and display chords) becomes a reference,
/// plus any differing lines. `{chorus}` repeats (`RenderSection.isRepeat`) always collapse
/// when enabled. With `enabled == false` every section is in full.
///
/// A later section counts as a repeat with differences when it has the same kind (not a
/// loose group), the same number of lines (at least two) and at most half of them differ.
public enum RepeatCollapser {
    public static func collapse(_ sections: [RenderSection], enabled: Bool) -> [CollapsedSection] {
        guard enabled else {
            return sections.indices.map {
                CollapsedSection(index: $0, repeatOf: nil, occurrence: 1, differingItems: [])
            }
        }
        var result: [CollapsedSection] = []
        var roots: [Int] = []
        var occurrences: [Int: Int] = [:]
        let keys = sections.map(contentKeys)
        for (index, section) in sections.enumerated() {
            var match: (root: Int, differing: [Int])?
            if section.isRepeat {
                match = repeatTarget(of: index, in: sections).map { target in
                    (result[target].repeatOf ?? target, [])
                }
            } else if !keys[index].isEmpty {
                match = bestRoot(for: index, roots: roots, sections: sections, keys: keys)
            }
            guard let match else {
                result.append(CollapsedSection(
                    index: index, repeatOf: nil, occurrence: 1, differingItems: [],
                ))
                if !section.isRepeat {
                    roots.append(index)
                }
                continue
            }
            let occurrence = (occurrences[match.root] ?? 1) + 1
            occurrences[match.root] = occurrence
            result.append(CollapsedSection(
                index: index,
                repeatOf: match.root,
                occurrence: occurrence,
                differingItems: match.differing,
            ))
        }
        return result
    }

    /// The chorus a `{chorus}` repeat at `index` refers to: the latest earlier written-out
    /// chorus whose label matches (case-insensitively), else the latest written-out chorus.
    public static func repeatTarget(of index: Int, in sections: [RenderSection]) -> Int? {
        guard sections.indices.contains(index) else { return nil }
        let wanted = displayLabel(sections[index])?.lowercased()
        let choruses = sections[..<index].indices.reversed().filter { candidate in
            let section = sections[candidate]
            return section.kind == .chorus && !section.isRepeat && !section.items.isEmpty
        }
        return choruses.first { displayLabel(sections[$0])?.lowercased() == wanted }
            ?? choruses.first
    }

    /// The label the gutter shows: the section's own, else its kind's name. The same label
    /// section notes pin to (`SectionNotes.label(of:)`).
    public static func displayLabel(_ section: RenderSection) -> String? {
        SectionNotes.label(of: section)
    }

    // MARK: - Matching

    private static func bestRoot(
        for index: Int,
        roots: [Int],
        sections: [RenderSection],
        keys: [[(item: Int, key: String)]],
    ) -> (root: Int, differing: [Int])? {
        let section = sections[index]
        let mine = keys[index]
        let candidates = roots.filter { sections[$0].kind == section.kind }
        if let exact = candidates.first(where: { keys[$0].map(\.key) == mine.map(\.key) }) {
            return (exact, [])
        }
        guard section.kind != nil, mine.count >= 2 else { return nil }
        for root in candidates where keys[root].count == mine.count {
            let differing = zip(keys[root], mine).filter { $0.key != $1.key }.map(\.1.item)
            if differing.count * 2 <= mine.count {
                return (root, differing)
            }
        }
        return nil
    }

    /// One comparison key per non-blank item, with its index in `items`.
    private static func contentKeys(_ section: RenderSection) -> [(item: Int, key: String)] {
        section.items.enumerated().compactMap { index, item in
            switch item {
            case let .lyrics(line):
                let chords = line.chords.map(\.text).joined(separator: " ")
                return (index, "L:" + normalize(line.lyrics) + "|" + chords)
            case let .comment(text, _, _):
                return (index, "C:" + normalize(text))
            case let .verbatim(text, _):
                return (index, "V:" + text)
            case .stanzaBreak:
                return nil
            }
        }
    }

    /// Lower-cased letters, marks and digits, single-spaced (punctuation dropped).
    static func normalize(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        var pendingSpace = false
        for character in text.lowercased() {
            if character.isLetter || character.isNumber
                || character.unicodeScalars.allSatisfy(\.properties.isAlphabetic)
            {
                if pendingSpace, !result.isEmpty {
                    result.append(" ")
                }
                pendingSpace = false
                result.append(character)
            } else {
                pendingSpace = true
            }
        }
        return result
    }
}
