// Phase 3 P3-7 (spec section 7, R65, R71, R92): a set request as chips. The lexicon fills the
// chips instantly, the async model pass adds suggested ones, the user edits them; the builder
// reads the confirmed chips as a `SetRequest`. Tempo is a filter only (R92).

import Foundation
import Library

/// The proficiency a request asks for. Learning songs are left out by default.
public enum ProficiencyRequirement: String, Sendable, Hashable, Codable, CaseIterable {
    /// Every song, Learning included ("including ones I'm learning").
    case anything
    /// Everything but Learning (the default); songs with no proficiency set stay in.
    case notLearning
    /// Ready or Pro ("songs I know well").
    case ready
    /// Pro only ("songs I know cold").
    case pro

    /// Whether a song at `level` (nil = not set) meets the requirement.
    public func admits(_ level: Proficiency?) -> Bool {
        switch self {
        case .anything: true
        case .notLearning: level != .learning
        case .ready: level == .ready || level == .pro
        case .pro: level == .pro
        }
    }

    /// The chip text ("Ready+").
    public var title: String {
        switch self {
        case .anything: "Any proficiency"
        case .notLearning: "No Learning"
        case .ready: "Ready+"
        case .pro: "Pro"
        }
    }
}

/// Inclusive BPM bounds; a nil side is open (R92: an explicit filter, never a score).
public struct TempoRange: Sendable, Hashable, Codable {
    public var min: Double?
    public var max: Double?

    public init(min: Double? = nil, max: Double? = nil) {
        self.min = min
        self.max = max
    }

    /// Whether `bpm` lies within the bounds (both ends included).
    public func contains(_ bpm: Double) -> Bool {
        if let min, bpm < min {
            return false
        }
        if let max, bpm > max {
            return false
        }
        return true
    }

    /// "under 100 bpm", "100-130 bpm", "over 120 bpm".
    public var title: String {
        switch (min, max) {
        case let (low?, high?): "\(Self.format(low))-\(Self.format(high)) bpm"
        case let (nil, high?): "Under \(Self.format(high)) bpm"
        case let (low?, nil): "Over \(Self.format(low)) bpm"
        case (nil, nil): "Any tempo"
        }
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// One request condition, as a chip. Tags keep the library's spelling.
public enum SetChip: Sendable, Hashable, Codable {
    /// The set length to pack to, in seconds ("45 min").
    case length(TimeInterval)
    /// How many songs ("10 songs").
    case songCount(Int)
    case proficiency(ProficiencyRequirement)
    /// The song has this tag (several tag chips: any of them).
    case tag(String)
    /// The song does not have this tag.
    case excludeTag(String)
    /// The song is in this key (several key chips: any of them). Canonical key name.
    case key(String)
    /// The song is not in this key.
    case excludeKey(String)
    case tempo(TempoRange)
    /// The song matches this saved smart filter.
    case smartFilter(SmartFilterID)
    /// Open with a song tagged so (only when the request asks, R92).
    case opener(tag: String)
    /// Close with a song tagged so (only when the request asks, R92).
    case closer(tag: String)
    /// Score recently played songs down (on by default).
    case avoidRecent(Bool)

    /// Chips of the same slot replace each other (a second length replaces the first);
    /// tag and key chips accumulate, one per value.
    public var slot: String {
        switch self {
        case .length: "length"
        case .songCount: "count"
        case .proficiency: "proficiency"
        case let .tag(tag): "tag:" + SetRequest.fold(tag)
        case let .excludeTag(tag): "tag:" + SetRequest.fold(tag)
        case let .key(key): "key:" + key
        case let .excludeKey(key): "key:" + key
        case .tempo: "tempo"
        case let .smartFilter(id): "filter:\(id)"
        case .opener: "opener"
        case .closer: "closer"
        case .avoidRecent: "recent"
        }
    }
}

/// Where a chip came from: the lexicon (or the user) states it; a model suggestion counts
/// only once the user accepts it (R65, R92).
public enum ChipOrigin: String, Sendable, Hashable, Codable {
    /// Read by the lexicon from the request text.
    case lexicon
    /// Added or edited by hand, or a suggestion the user accepted.
    case confirmed
    /// From the async model pass: shown dashed, not applied until accepted.
    case suggested
}

/// A chip and where it came from.
public struct RequestChip: Sendable, Hashable, Codable, Identifiable {
    public var kind: SetChip
    public var origin: ChipOrigin

    public init(_ kind: SetChip, origin: ChipOrigin) {
        self.kind = kind
        self.origin = origin
    }

    public var id: String {
        kind.slot
    }

    /// Whether the builder applies it (every chip but an unaccepted suggestion).
    public var isApplied: Bool {
        origin != .suggested
    }
}

/// What the builder is asked for: the applied chips, merged. Later chips of a slot win.
public struct SetRequest: Sendable, Hashable, Codable {
    /// The set length to pack to, in seconds; nil packs to `songCount` (or the fallback).
    public var targetLength: TimeInterval?
    public var songCount: Int?
    public var proficiency: ProficiencyRequirement
    /// Any of these tags (case-insensitive); empty = no constraint.
    public var includeTags: [String]
    public var excludeTags: [String]
    /// Any of these keys (enharmonics match); empty = no constraint.
    public var keys: [String]
    public var excludeKeys: [String]
    /// A filter only (R92); a song without `{tempo}` never matches a set range.
    public var tempo: TempoRange?
    /// The song must match every one of these smart filters.
    public var smartFilters: [SmartFilterID]
    /// Slot shaping, only when asked (R92).
    public var openerTag: String?
    public var closerTag: String?
    public var avoidRecent: Bool

    public init(
        targetLength: TimeInterval? = nil,
        songCount: Int? = nil,
        proficiency: ProficiencyRequirement = .notLearning,
        includeTags: [String] = [],
        excludeTags: [String] = [],
        keys: [String] = [],
        excludeKeys: [String] = [],
        tempo: TempoRange? = nil,
        smartFilters: [SmartFilterID] = [],
        openerTag: String? = nil,
        closerTag: String? = nil,
        avoidRecent: Bool = true,
    ) {
        self.targetLength = targetLength
        self.songCount = songCount
        self.proficiency = proficiency
        self.includeTags = includeTags
        self.excludeTags = excludeTags
        self.keys = keys
        self.excludeKeys = excludeKeys
        self.tempo = tempo
        self.smartFilters = smartFilters
        self.openerTag = openerTag
        self.closerTag = closerTag
        self.avoidRecent = avoidRecent
    }

    /// The request the applied chips of `chips` make (suggestions left out).
    public init(chips: [RequestChip]) {
        self.init(kinds: chips.filter(\.isApplied).map(\.kind))
    }

    /// The request `kinds` make, in order (a later chip of a slot wins).
    public init(kinds: [SetChip]) {
        self.init()
        for kind in kinds {
            apply(kind)
        }
    }

    private mutating func apply(_ kind: SetChip) {
        switch kind {
        case let .length(seconds): targetLength = seconds > 0 ? seconds : nil
        case let .songCount(count): songCount = count > 0 ? count : nil
        case let .proficiency(level): proficiency = level
        case let .tempo(range): tempo = range.min == nil && range.max == nil ? nil : range
        case let .opener(tag): openerTag = tag
        case let .closer(tag): closerTag = tag
        case let .avoidRecent(on): avoidRecent = on
        case .excludeKey, .excludeTag, .key, .smartFilter, .tag: applyListChip(kind)
        }
    }

    /// Tags, keys and smart filters accumulate; including a tag or key drops its exclusion
    /// and the other way round.
    private mutating func applyListChip(_ kind: SetChip) {
        switch kind {
        case let .tag(tag):
            excludeTags.removeAll { Self.fold($0) == Self.fold(tag) }
            Self.appendUnique(tag, to: &includeTags)
        case let .excludeTag(tag):
            includeTags.removeAll { Self.fold($0) == Self.fold(tag) }
            Self.appendUnique(tag, to: &excludeTags)
        case let .key(key):
            excludeKeys.removeAll { $0 == key }
            Self.appendUnique(key, to: &keys)
        case let .excludeKey(key):
            keys.removeAll { $0 == key }
            Self.appendUnique(key, to: &excludeKeys)
        case let .smartFilter(id):
            smartFilters.removeAll { $0 == id }
            smartFilters.append(id)
        default:
            break
        }
    }

    private static func appendUnique(_ tag: String, to tags: inout [String]) {
        if !tags.contains(where: { fold($0) == fold(tag) }) {
            tags.append(tag)
        }
    }

    /// Case-, width- and diacritic-insensitive tag form, whitespace collapsed.
    public static func fold(_ tag: String) -> String {
        tag.split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .folding(
                options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive],
                locale: nil,
            )
    }
}

public extension [RequestChip] {
    /// Adds `chip`, replacing a chip of the same slot (`SetChip.slot`). A suggestion never
    /// replaces a stated or confirmed chip.
    mutating func merge(_ chip: RequestChip) {
        if let index = firstIndex(where: { $0.id == chip.id }) {
            if chip.origin == .suggested, self[index].origin != .suggested {
                return
            }
            self[index] = chip
        } else {
            append(chip)
        }
    }
}

public extension SetChip {
    /// The chip's text ("35 min", "Ready+", "no covers", "in G", "opens upbeat");
    /// `filterName` names a smart filter chip.
    func title(filterName: (SmartFilterID) -> String? = { _ in nil }) -> String {
        switch self {
        case let .length(seconds): Self.lengthTitle(seconds)
        case let .songCount(count): count == 1 ? "1 song" : "\(count) songs"
        case let .proficiency(level): level.title
        case let .tempo(range): range.title
        case let .smartFilter(id): filterName(id) ?? "Smart filter"
        case let .avoidRecent(on): on ? "Avoid recent" : "Recent OK"
        case .closer, .excludeKey, .excludeTag, .key, .opener, .tag: nameTitle
        }
    }

    /// Tag, key and slot chips: "covers", "no covers", "in G", "opens upbeat".
    private var nameTitle: String {
        switch self {
        case let .tag(tag): tag
        case let .excludeTag(tag): "no \(tag)"
        case let .key(key): "in \(key)"
        case let .excludeKey(key): "not in \(key)"
        case let .opener(tag): "opens \(tag)"
        case let .closer(tag): "closes \(tag)"
        default: ""
        }
    }

    /// "35 min", "1 h", "1 h 30 min".
    static func lengthTitle(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        guard minutes >= 60 else { return "\(minutes) min" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(rest) min"
    }
}

public extension SetRequest {
    /// The song conditions of the request as a library matcher (NL picks in the library
    /// search and on stage): tags (any of), excluded tags, keys, the proficiency floor and
    /// the tempo range. Lengths, counts, slots and smart filters do not apply to a search.
    /// Nil when the request holds none of them.
    var songFilter: SongFilter? {
        var filter = SongFilter(
            anyTags: Set(includeTags),
            excludedTags: Set(excludeTags),
            keys: Set(keys),
        )
        switch proficiency {
        case .anything, .notLearning: break
        case .ready: filter.proficiencies = [.ready, .pro]
        case .pro: filter.proficiencies = [.pro]
        }
        if let tempo {
            filter.tempo = SongFilter.Bounds(lower: tempo.min, upper: tempo.max)
        }
        return filter.hasConstraints ? filter : nil
    }
}
