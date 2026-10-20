// Phase 3 P3-7 (spec section 7 step 4): weighted signals, each candidate with a breakdown
// (signal -> weighted contribution) that sums to its total. No energy (R71); tempo never
// scores (R92); slot fit only when the request asks (R92). A song appears at most once per
// setlist: that is the packer's invariant, never a score term.

import Foundation
import Library
import MusicTheory

/// One scored signal.
public enum ScoreSignal: String, Sendable, Hashable, Codable, CaseIterable {
    case proficiency
    case tags
    /// The recently-played penalty (global across gigs, decaying with days since played).
    case recent
    /// Opener / closer fit from tags (only when asked).
    case slot
    /// Key, capo and tuning change from the song before it in the same part.
    case keyFlow
    /// The seeded shuffle that lets Rebuild offer near-equal songs (shown, so the total adds
    /// up).
    case variety

    /// The breakdown row label.
    public var title: String {
        switch self {
        case .proficiency: "Proficiency"
        case .tags: "Tag match"
        case .recent: "Played recently"
        case .slot: "Opener / closer"
        case .keyFlow: "Key flow"
        case .variety: "Variety"
        }
    }
}

/// A song's score: every signal's weighted contribution, in `ScoreSignal` order, and their
/// sum. Signals that contributed nothing are kept (as 0) so the popover always lists the
/// same rows.
public struct ScoreBreakdown: Sendable, Hashable, Codable {
    public struct Contribution: Sendable, Hashable, Codable {
        public var signal: ScoreSignal
        public var value: Double
        /// Why ("Pro", "2 of 2 tags", "played 3 days ago", "same key as before").
        public var reason: String

        public init(signal: ScoreSignal, value: Double, reason: String) {
            self.signal = signal
            self.value = value
            self.reason = reason
        }
    }

    public private(set) var contributions: [Contribution]

    public init(_ contributions: [Contribution] = []) {
        self.contributions = []
        for contribution in contributions {
            set(contribution)
        }
    }

    /// The sum of every contribution.
    public var total: Double {
        contributions.reduce(0) { $0 + $1.value }
    }

    public func value(of signal: ScoreSignal) -> Double {
        contributions.first { $0.signal == signal }?.value ?? 0
    }

    public func contribution(of signal: ScoreSignal) -> Contribution? {
        contributions.first { $0.signal == signal }
    }

    /// Sets (replaces) `contribution`'s signal, keeping `ScoreSignal` order.
    public mutating func set(_ contribution: Contribution) {
        contributions.removeAll { $0.signal == contribution.signal }
        contributions.append(contribution)
        let order = ScoreSignal.allCases
        contributions.sort {
            order.firstIndex(of: $0.signal) ?? 0 < order.firstIndex(of: $1.signal) ?? 0
        }
    }
}

/// Where a song sits, for the position signals.
public struct SlotContext: Sendable, Hashable {
    public var isOpener: Bool
    public var isCloser: Bool
    /// The song before it in the same part (nil: it opens a part).
    public var previous: AssistantSong?

    public init(isOpener: Bool = false, isCloser: Bool = false, previous: AssistantSong? = nil) {
        self.isOpener = isOpener
        self.isCloser = isCloser
        self.previous = previous
    }
}

/// Computes the signals. Pure; the weights come from `AssistantConfig`.
public struct Scorer: Sendable {
    public let config: AssistantConfig
    public let request: SetRequest
    public let now: Date
    private let variety: [SongID: Double]

    /// - Parameter variety: each song's seeded raw variety value in `0 ... varietySpread`
    ///   (the builder draws it from its seed).
    public init(
        config: AssistantConfig,
        request: SetRequest,
        now: Date,
        variety: [SongID: Double] = [:],
    ) {
        self.config = config
        self.request = request
        self.now = now
        self.variety = variety
    }

    /// The position-free signals: proficiency, tags, recent, variety.
    public func base(_ song: AssistantSong) -> ScoreBreakdown {
        let weights = config.weights
        var breakdown = ScoreBreakdown()
        let (level, levelText) = proficiencyValue(song.proficiency)
        breakdown.set(.init(
            signal: .proficiency,
            value: weights.proficiency * level,
            reason: levelText,
        ))
        let (tagValue, tagText) = tagMatch(song)
        breakdown.set(.init(signal: .tags, value: weights.tags * tagValue, reason: tagText))
        let (recentValue, recentText) = recent(song)
        breakdown.set(.init(
            signal: .recent,
            value: weights.recent * recentValue,
            reason: recentText,
        ))
        breakdown.set(.init(signal: .slot, value: 0, reason: ""))
        breakdown.set(.init(signal: .keyFlow, value: 0, reason: ""))
        let shuffle = variety[song.id] ?? 0
        breakdown.set(.init(
            signal: .variety,
            value: weights.variety * shuffle,
            reason: shuffle > 0 ? "Seeded shuffle" : "",
        ))
        return breakdown
    }

    /// `base` plus the position signals for `slot`.
    public func score(_ song: AssistantSong, in slot: SlotContext) -> ScoreBreakdown {
        var breakdown = base(song)
        let (slotValue, slotText) = slotFit(song, slot)
        breakdown.set(.init(
            signal: .slot,
            value: config.weights.slot * slotValue,
            reason: slotText,
        ))
        let (flowValue, flowText) = flow(from: slot.previous, to: song)
        breakdown.set(.init(
            signal: .keyFlow,
            value: config.weights.keyFlow * flowValue,
            reason: flowText,
        ))
        return breakdown
    }

    // MARK: Signals (raw values)

    func proficiencyValue(_ level: Proficiency?) -> (Double, String) {
        let values = config.proficiencyValues
        return switch level {
        case .pro: (values.pro, "Pro")
        case .ready: (values.ready, "Ready")
        case .learning: (values.learning, "Learning")
        case nil: (values.unset, "Not set")
        }
    }

    /// The share of the requested tags the song has (0 without requested tags).
    func tagMatch(_ song: AssistantSong) -> (Double, String) {
        let wanted = request.includeTags
        guard !wanted.isEmpty else { return (0, "") }
        let matched = wanted.filter(song.hasTag)
        return (
            Double(matched.count) / Double(wanted.count),
            "\(matched.count) of \(wanted.count) tags",
        )
    }

    /// `-0.5^(days / halfLife)`: -1 played today, -0.5 a half-life ago (only with avoid-recent).
    func recent(_ song: AssistantSong) -> (Double, String) {
        guard request.avoidRecent, let last = song.lastPlayed else {
            return (0, song.lastPlayed == nil ? "Never played" : "")
        }
        let days = max(now.timeIntervalSince(last) / 86400, 0)
        let halfLife = max(config.recentHalfLifeDays, 0.001)
        let value = -pow(0.5, days / halfLife)
        let whole = Int(days.rounded(.down))
        let text = switch whole {
        case 0: "Played today"
        case 1: "Played yesterday"
        default: "Played \(whole) days ago"
        }
        return (value, text)
    }

    func slotFit(_ song: AssistantSong, _ slot: SlotContext) -> (Double, String) {
        var value = 0.0
        var reasons: [String] = []
        if slot.isOpener, let tag = request.openerTag, song.hasTag(tag) {
            value += 1
            reasons.append("Opens with \(tag)")
        }
        if slot.isCloser, let tag = request.closerTag, song.hasTag(tag) {
            value += 1
            reasons.append("Closes with \(tag)")
        }
        return (value, reasons.joined(separator: ", "))
    }

    /// Raw flow from `previous` to `song`: same key, related key, capo and tuning changes.
    func flow(from previous: AssistantSong?, to song: AssistantSong) -> (Double, String) {
        guard let previous else { return (0, "") }
        let flow = config.flow
        var value = 0.0
        var reasons: [String] = []
        if let before = previous.key, let key = song.key {
            if before.tonic.pitchClass == key.tonic.pitchClass, before.mode == key.mode {
                value += flow.sameKey
                reasons.append("Same key as before")
            } else if Self.related(before, key) {
                value += flow.relatedKey
                reasons.append("Related key")
            }
        }
        if previous.capo != song.capo {
            value += flow.capoChange
            reasons.append("Capo change")
        }
        if previous.tuning != song.tuning {
            value += flow.tuningChange
            reasons.append("Tuning change")
        }
        return (value, reasons.joined(separator: ", "))
    }

    /// Relative major/minor, a fifth apart in the same mode, or parallel major/minor.
    static func related(_ lhs: SongKey, _ rhs: SongKey) -> Bool {
        let left = lhs.tonic.pitchClass.rawValue
        let right = rhs.tonic.pitchClass.rawValue
        let interval = ((right - left) % 12 + 12) % 12
        if lhs.mode == rhs.mode {
            return interval == 5 || interval == 7
        }
        if left == right {
            return true
        }
        // C -> Am (down 3) or Am -> C (up 3).
        return lhs.mode == .major ? interval == 9 : interval == 3
    }
}
