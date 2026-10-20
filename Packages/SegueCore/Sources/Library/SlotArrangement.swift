// Owner: P3-16. Per-slot arrangements (R122, R123): which sections of a song a setlist slot
// plays for one gig, in which order and how many times. The `.cho` is never changed. The
// types live here (not in Setlists) because live layout applies them and depends on Library
// only.

import ChordPro
import Editing
import Foundation

/// A labelled section by its display label and 1-based occurrence of that label (the
/// section notes anchoring rule, `SectionNotes.pin`).
public struct SectionRef: Sendable, Hashable {
    public var label: String
    public var occurrence: Int

    public init(label: String, occurrence: Int) {
        self.label = label
        self.occurrence = occurrence
    }

    /// Same section: labels compared case-insensitively after trimming.
    public func matches(_ other: Self) -> Bool {
        occurrence == other.occurrence && SectionNotes.key(label) == SectionNotes.key(other.label)
    }
}

/// Which part of the song an arrangement row plays.
public enum SectionAnchor: Sendable, Hashable {
    /// A labelled section (or `{chorus}` repeat).
    case section(SectionRef)
    /// The `block`-th (1-based) run of loose lines right after the labelled section `after`,
    /// or before the first labelled section when `after` is nil (the "Lead-in", R123).
    case loose(after: SectionRef?, block: Int)

    /// Same part of the song (labels compared case-insensitively).
    public func matches(_ other: Self) -> Bool {
        switch (self, other) {
        case let (.section(left), .section(right)):
            left.matches(right)
        case let (.loose(leftAfter, leftBlock), .loose(rightAfter, rightBlock)):
            leftBlock == rightBlock && {
                switch (leftAfter, rightAfter) {
                case (nil, nil): true
                case let (left?, right?): left.matches(right)
                default: false
                }
            }()
        default:
            false
        }
    }
}

/// One row of an arrangement.
public struct ArrangementStep: Sendable, Hashable, Codable {
    public var anchor: SectionAnchor
    /// The section's content fingerprint when the row was saved (`SongSections`); a
    /// mismatch marks the arrangement out of date (R123). Nil when not recorded.
    public var fingerprint: String?
    /// 0 = skipped, else how many times in a row it is played (1 ... `maxPlays`).
    public var plays: Int

    public init(anchor: SectionAnchor, fingerprint: String? = nil, plays: Int = 1) {
        self.anchor = anchor
        self.fingerprint = fingerprint
        self.plays = plays
    }

    public var isSkipped: Bool {
        plays <= 0
    }

    /// `{"section": "Chorus", "occurrence": 2, "fp": "...", "plays": 1}`, or for loose
    /// lines `{"loose": 1, "after": "Verse 2", "afterOccurrence": 1, ...}` (`after` absent for
    /// the lead-in).
    private enum CodingKeys: String, CodingKey {
        case section
        case occurrence
        case loose
        case after
        case afterOccurrence
        case fingerprint = "fp"
        case plays
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let block = try container.decodeIfPresent(Int.self, forKey: .loose) {
            let after = try container.decodeIfPresent(String.self, forKey: .after).map { label in
                try SectionRef(
                    label: label,
                    occurrence: container.decodeIfPresent(Int.self, forKey: .afterOccurrence) ?? 1,
                )
            }
            anchor = .loose(after: after, block: max(block, 1))
        } else {
            anchor = try .section(SectionRef(
                label: container.decode(String.self, forKey: .section),
                occurrence: container.decodeIfPresent(Int.self, forKey: .occurrence) ?? 1,
            ))
        }
        fingerprint = try container.decodeIfPresent(String.self, forKey: .fingerprint)
        plays = try container.decodeIfPresent(Int.self, forKey: .plays) ?? 1
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch anchor {
        case let .section(ref):
            try container.encode(ref.label, forKey: .section)
            try container.encode(ref.occurrence, forKey: .occurrence)
        case let .loose(after, block):
            try container.encode(block, forKey: .loose)
            if let after {
                try container.encode(after.label, forKey: .after)
                try container.encode(after.occurrence, forKey: .afterOccurrence)
            }
        }
        try container.encodeIfPresent(fingerprint, forKey: .fingerprint)
        try container.encode(plays, forKey: .plays)
    }
}

/// A setlist slot's arrangement for this gig only (R122). Saved in the setlist entry as
/// `"arrangement": {"steps": [...], "length": 215}`.
public struct SlotArrangement: Sendable, Hashable, Codable {
    /// The most times a row can be played in a row.
    public static let maxPlays = 9

    /// Every part of the song, in played order. Skipped rows stay (plays 0) so a section
    /// added to the song later is recognisable as new; "Play Again Later" rows repeat an
    /// anchor.
    public var steps: [ArrangementStep]
    /// The slot's length in seconds (typed or timed); nil = unknown, flagged in totals. Never
    /// derived from the song's `{duration}` (R122).
    public var length: TimeInterval?

    public init(steps: [ArrangementStep], length: TimeInterval? = nil) {
        self.steps = steps
        self.length = length
    }

    /// The song as written: every part once, in song order.
    public static func fullSong(_ units: [SongSectionUnit]) -> Self {
        Self(steps: units.map { ArrangementStep(anchor: $0.anchor, fingerprint: $0.fingerprint) })
    }

    /// Rows that are played.
    public var playedSteps: [ArrangementStep] {
        steps.filter { !$0.isSkipped }
    }

    /// The played rows by name, in order: "Intro, Verse 1, Chorus 3rd x2, After Chorus"
    /// (the gig log's line; read from the saved anchors, so it needs no song).
    public var playedSummary: String {
        playedSteps.map { step in
            let name = switch step.anchor {
            case let .section(ref):
                ref.occurrence > 1
                    ? "\(ref.label) \(SongSections.ordinal(ref.occurrence))" : ref.label
            case let .loose(after, _):
                after.map { "After \($0.label)" } ?? "Lead-in"
            }
            return step.plays > 1 ? "\(name) x\(step.plays)" : name
        }.joined(separator: ", ")
    }

    private enum CodingKeys: String, CodingKey {
        case steps
        case length
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        steps = try container.decodeIfPresent([ArrangementStep].self, forKey: .steps) ?? []
        length = try container.decodeIfPresent(TimeInterval.self, forKey: .length)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(steps, forKey: .steps)
        if let length, length > 0 {
            try container.encode(length, forKey: .length)
        }
    }
}

// MARK: - The song's parts

/// One part of a song an arrangement can name: a labelled section, a `{chorus}` repeat, or a
/// run of loose lines (one `RenderSection` each).
public struct SongSectionUnit: Sendable, Hashable, Identifiable {
    /// Index into the song's `RenderModel.sections`.
    public var index: Int
    public var anchor: SectionAnchor
    public var fingerprint: String
    /// "Verse 2", "Chorus", "Lead-in", "After Verse 2".
    public var title: String
    /// "2nd" when the title occurs more than once in the song, else nil.
    public var ordinal: String?
    public var kind: SectionKind?
    public var isRepeat: Bool
    /// The first lyric line (or chords, comment, tab line) for the editor row.
    public var firstLine: String?

    public var id: Int {
        index
    }

    /// "Chorus 2nd" / "Verse 1": what VoiceOver and summaries read.
    public var name: String {
        ordinal.map { "\(title) \($0)" } ?? title
    }
}

/// The parts of a song an arrangement can name, in song order.
public enum SongSections {
    /// The parts of `document`, rendered with default options (so a transposition or capo
    /// never changes which part an anchor names).
    public static func units(of document: SongDocument) -> [SongSectionUnit] {
        units(of: RenderModel(document: document, options: DisplayOptions()).sections)
    }

    public static func units(of sections: [RenderSection]) -> [SongSectionUnit] {
        let anchors = Anchors(sections)
        var units: [SongSectionUnit] = []
        var lastRef: SectionRef?
        var block = 0
        var titleCounts: [String: Int] = [:]
        var titles: [String] = []
        for (index, section) in sections.enumerated() {
            let anchor: SectionAnchor
            let title: String
            if let label = SectionNotes.label(of: section) {
                let ref = SectionRef(label: label, occurrence: anchors.occurrence[index])
                anchor = .section(ref)
                lastRef = ref
                block = 0
                title = label
            } else {
                block += 1
                anchor = .loose(after: lastRef, block: block)
                title = lastRef.map { "After \($0.label)" } ?? "Lead-in"
            }
            titles.append(title)
            titleCounts[SectionNotes.key(title), default: 0] += 1
            units.append(SongSectionUnit(
                index: index,
                anchor: anchor,
                fingerprint: fingerprint(of: section),
                title: title,
                ordinal: nil,
                kind: section.kind,
                isRepeat: section.isRepeat,
                firstLine: firstLine(of: section, in: sections, at: index),
            ))
        }
        // Ordinals for titles that repeat ("Chorus 1st / 2nd / 3rd").
        var seen: [String: Int] = [:]
        for index in units.indices {
            let key = SectionNotes.key(titles[index])
            guard (titleCounts[key] ?? 0) > 1 else { continue }
            let number = (seen[key] ?? 0) + 1
            seen[key] = number
            units[index].ordinal = ordinal(number)
        }
        return units
    }

    /// "1st", "2nd", "3rd", "4th", "11th", "22nd".
    public static func ordinal(_ number: Int) -> String {
        let tens = number % 100
        let suffix = switch (tens, number % 10) {
        case (11 ... 13, _): "th"
        case (_, 1): "st"
        case (_, 2): "nd"
        case (_, 3): "rd"
        default: "th"
        }
        return "\(number)\(suffix)"
    }

    /// The content fingerprint (R123): the first two content lines (lyrics normalized;
    /// chords only for a chord-only line; comments; tab lines), FNV-1a 32-bit in hex. A
    /// `{chorus}` repeat is "repeat" (its content is its chorus's).
    public static func fingerprint(of section: RenderSection) -> String {
        if section.isRepeat {
            return "repeat"
        }
        let lines = section.items.lazy.compactMap { item -> String? in
            switch item {
            case let .lyrics(line):
                let lyrics = normalize(line.lyrics)
                if !lyrics.isEmpty {
                    return "l:" + lyrics
                }
                let chords = line.chords.map(\.text).joined(separator: " ")
                return chords.isEmpty ? nil : "h:" + chords
            case let .comment(text, _, _):
                return "c:" + normalize(text)
            case let .verbatim(text, _):
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? nil : "v:" + trimmed
            case .stanzaBreak:
                return nil
            }
        }
        return fnv1a(Array(lines.prefix(2)).joined(separator: "\n"))
    }

    private static func firstLine(
        of section: RenderSection,
        in sections: [RenderSection],
        at index: Int,
    ) -> String? {
        let source = section.isRepeat
            ? repeatTarget(of: index, in: sections).map { sections[$0] } ?? section
            : section
        for item in source.items {
            switch item {
            case let .lyrics(line):
                let text = line.lyrics.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    return text
                }
                let chords = line.chords.map(\.text).joined(separator: "  ")
                if !chords.isEmpty {
                    return chords
                }
            case let .comment(text, _, _):
                return text
            case let .verbatim(text, _):
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    return trimmed
                }
            case .stanzaBreak:
                continue
            }
        }
        return nil
    }

    /// The chorus a `{chorus}` repeat at `index` refers to: the latest earlier written-out
    /// chorus whose label matches, else the latest written-out chorus (the live layout's
    /// `RepeatCollapser.repeatTarget` rule).
    public static func repeatTarget(of index: Int, in sections: [RenderSection]) -> Int? {
        guard sections.indices.contains(index) else { return nil }
        let wanted = SectionNotes.label(of: sections[index])?.lowercased()
        let choruses = sections[..<index].indices.reversed().filter { candidate in
            let section = sections[candidate]
            return section.kind == .chorus && !section.isRepeat && !section.items.isEmpty
        }
        return choruses.first { SectionNotes.label(of: sections[$0])?.lowercased() == wanted }
            ?? choruses.first
    }

    /// Lower-cased letters, marks and digits, single-spaced (punctuation dropped).
    static func normalize(_ text: String) -> String {
        var result = ""
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

    static func fnv1a(_ text: String) -> String {
        var hash: UInt32 = 0x811C_9DC5
        for byte in text.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 8 - hex.count) + hex
    }
}
