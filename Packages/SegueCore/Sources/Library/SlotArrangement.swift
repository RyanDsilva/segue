// Owner: P3-16, P8-2. Per-slot arrangements (R122, R123, R149): which parts of a song a
// setlist slot plays for one gig, in which order, and how each pass is shown. The `.cho` is
// never changed. The types live here (not in Setlists) because live layout applies them and
// depends on Library only.

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

/// How a pass is shown on stage (R149). The coded values are stable.
public enum PassMode: String, Sendable, Hashable, Codable, CaseIterable {
    /// Every line, as written (the default).
    case full
    /// The chord row of each lyric line, no lyrics.
    case chordsOnly = "chords"
    /// The first lyric line, then "+ N more lines".
    case firstLine = "first"
    /// Kept in the arrangement for the editor; never on stage or in the map.
    case skip

    /// The mode a pass takes in singer view (P9-2 section 6.3, R178): a Chords only pass
    /// shows its first lyric line (it is played, but its words were not chosen to be read);
    /// the others are kept.
    public var singer: Self {
        self == .chordsOnly ? .firstLine : self
    }
}

/// One pass of a slot arrangement (R149): a part of the song and how it is shown. "x2" is
/// two consecutive passes.
public struct ArrangementPass: Sendable, Hashable, Codable {
    public var anchor: SectionAnchor
    /// The part's content fingerprint when the pass was saved (`SongSections`, R123, R146);
    /// a mismatch marks the arrangement out of date. Nil when not recorded.
    public var fingerprint: String?
    public var mode: PassMode

    public init(anchor: SectionAnchor, fingerprint: String? = nil, mode: PassMode = .full) {
        self.anchor = anchor
        self.fingerprint = fingerprint
        self.mode = mode
    }

    /// Whether the pass is on stage (every mode but Skip).
    public var isShown: Bool {
        mode != .skip
    }

    /// `{"section": "Chorus", "occurrence": 2, "fp": "...", "mode": "chords"}`, or for loose
    /// lines `{"loose": 1, "after": "Verse 2", "afterOccurrence": 1, ...}` (`after` absent for
    /// the lead-in). `mode` is omitted for Full; an unknown mode reads as Full; a v5 `plays`
    /// key is ignored.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnchorCodingKeys.self)
        anchor = try SectionAnchor.decode(from: container)
        fingerprint = try container.decodeIfPresent(String.self, forKey: .fingerprint)
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
            .flatMap(PassMode.init(rawValue:)) ?? .full
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: AnchorCodingKeys.self)
        try anchor.encode(to: &container)
        try container.encodeIfPresent(fingerprint, forKey: .fingerprint)
        if mode != .full {
            try container.encode(mode.rawValue, forKey: .mode)
        }
    }
}

/// A part the arrangement knew when it was saved: the song's parts in neither this list nor
/// the passes are "New in the song" (R123).
public struct KnownPart: Sendable, Hashable, Codable {
    public var anchor: SectionAnchor
    public var fingerprint: String?

    public init(anchor: SectionAnchor, fingerprint: String? = nil) {
        self.anchor = anchor
        self.fingerprint = fingerprint
    }

    /// Every part of the song as it is now (what an editor writes on every save).
    public static func all(_ units: [SongSectionUnit]) -> [Self] {
        units.map { Self(anchor: $0.anchor, fingerprint: $0.fingerprint) }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnchorCodingKeys.self)
        anchor = try SectionAnchor.decode(from: container)
        fingerprint = try container.decodeIfPresent(String.self, forKey: .fingerprint)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: AnchorCodingKeys.self)
        try anchor.encode(to: &container)
        try container.encodeIfPresent(fingerprint, forKey: .fingerprint)
    }
}

/// Why an arrangement cannot be played as saved (`SlotArrangement.problems`).
public enum ArrangementProblem: Sendable, Hashable {
    /// Every pass is Skip, or there are no passes.
    case noShownPass
    /// More than `SlotArrangement.maxPasses` passes.
    case tooManyPasses
}

/// A setlist slot's arrangement for this gig only (R122, R149): an ordered list of passes.
/// Saved in the setlist entry as `"arrangement": {"passes": [...], "knownParts": [...]}`. The
/// slot's time comes from the passes it plays (`SlotTimes.slot`, P8-8); an older file's
/// `"length"` key is ignored and dropped on the next save.
public struct SlotArrangement: Sendable, Hashable, Codable {
    /// The most passes an arrangement may hold.
    public static let maxPasses = 48

    /// The passes in played order (Skip passes included).
    public var passes: [ArrangementPass]
    /// Every part of the song when the arrangement was last saved. Empty means "the parts
    /// named in `passes`" (a hand-written or migrated file).
    public var knownParts: [KnownPart]

    public init(passes: [ArrangementPass], knownParts: [KnownPart] = []) {
        self.passes = passes
        self.knownParts = knownParts
    }

    /// The song as written: every part once, Full, in song order; every part known.
    public static func fullSong(_ units: [SongSectionUnit]) -> Self {
        Self(
            passes: units.map { ArrangementPass(anchor: $0.anchor, fingerprint: $0.fingerprint) },
            knownParts: KnownPart.all(units),
        )
    }

    /// The passes shown on stage (every mode but Skip).
    public var shownPasses: [ArrangementPass] {
        passes.filter(\.isShown)
    }

    /// The known parts, or the parts named in `passes` when none were saved.
    public var effectiveKnownParts: [KnownPart] {
        guard knownParts.isEmpty else { return knownParts }
        var result: [KnownPart] = []
        for pass in passes where !result.contains(where: { $0.anchor.matches(pass.anchor) }) {
            result.append(KnownPart(anchor: pass.anchor, fingerprint: pass.fingerprint))
        }
        return result
    }

    /// What keeps the arrangement from being played as saved (the validator). The editor
    /// refuses edits that would create one; a file that has one still loads and reads out
    /// of date.
    public var problems: [ArrangementProblem] {
        var problems: [ArrangementProblem] = []
        if !passes.contains(where: \.isShown) {
            problems.append(.noShownPass)
        }
        if passes.count > Self.maxPasses {
            problems.append(.tooManyPasses)
        }
        return problems
    }

    /// The shown passes by name, in order, a run of the same part and mode merged:
    /// "Intro (chords), Verse 1, Chorus, Chorus 3rd x2, Outro (first line)" (the gig log's
    /// line; read from the saved anchors, so it needs no song).
    public var playedSummary: String {
        var runs: [(pass: ArrangementPass, count: Int)] = []
        for pass in shownPasses {
            if let last = runs.last, last.pass.anchor == pass.anchor, last.pass.mode == pass.mode {
                runs[runs.count - 1].count += 1
            } else {
                runs.append((pass, 1))
            }
        }
        return runs.map { run in
            var name = run.pass.anchor.summaryName
            switch run.pass.mode {
            case .chordsOnly: name += " (chords)"
            case .firstLine: name += " (first line)"
            case .full, .skip: break
            }
            return run.count > 1 ? "\(name) x\(run.count)" : name
        }.joined(separator: ", ")
    }

    private enum CodingKeys: String, CodingKey {
        case passes
        case knownParts
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        passes = try container.decodeIfPresent([ArrangementPass].self, forKey: .passes) ?? []
        knownParts = try container.decodeIfPresent([KnownPart].self, forKey: .knownParts) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(passes, forKey: .passes)
        if !knownParts.isEmpty {
            try container.encode(knownParts, forKey: .knownParts)
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
    /// The pre-R146 fingerprint (comments included), accepted when resolving older rows.
    public var legacyFingerprint: String
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
                legacyFingerprint: legacyFingerprint(of: section),
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

    /// The content fingerprint (R123, R146): the first two content lines (lyrics normalized;
    /// chords only for a chord-only line; tab lines), FNV-1a 32-bit in hex. `{comment}` lines
    /// are left out, so adding, moving or deleting a section note never changes it. A
    /// `{chorus}` repeat is "repeat" (its content is its chorus's).
    public static func fingerprint(of section: RenderSection) -> String {
        fingerprint(of: section, includingComments: false)
    }

    /// The fingerprint as builds before R146 computed it (comments counted as content lines).
    /// The resolver still accepts it, so an arrangement saved by such a build stays applied.
    public static func legacyFingerprint(of section: RenderSection) -> String {
        fingerprint(of: section, includingComments: true)
    }

    private static func fingerprint(of section: RenderSection, includingComments: Bool) -> String {
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
                return includingComments ? "c:" + normalize(text) : nil
            case let .verbatim(text, _):
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? nil : "v:" + trimmed
            case .fillTab, .stanzaBreak:
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
            case .fillTab, .stanzaBreak:
                continue
            }
        }
        return nil
    }

    /// The chorus a `{chorus}` repeat at `index` refers to: the latest earlier written-out
    /// chorus whose label matches, else the latest written-out chorus (the stage writes the
    /// repeat out with its lines, R147).
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
