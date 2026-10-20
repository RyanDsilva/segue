// Phase 3 P3-7 (spec section 7 steps 5-7): filter, pick, order. A greedy fill to the target
// length (+/- the tolerance) by score, a swap pass when it falls short, then an order pass
// for key flow (same key back to back, capo and tuning changes penalised, related keys a
// small bonus). Lengths are `{duration}` plus the setlist's changeover (R86); songs without
// a length are left out of a length target and named (R107). A song appears at most once
// (the setlist invariant, 1d027df). Rebuild keeps locked songs and break rows where they are
// and re-packs the other slots. Deterministic: same library, request and seed, same set.

import Foundation
import Library
import MusicTheory
import Setlists

/// The set the builder made.
public struct SetDraft: Sendable, Equatable {
    /// Song slots and break rows, in order.
    public var entries: [SetlistEntry]
    /// Every song slot's score, keyed by item (locked songs too).
    public var breakdowns: [SetlistItemID: ScoreBreakdown]
    /// The timing of `entries` (same rules as the builder header).
    public var timing: SetlistTiming
    /// The length packed to, if any (the request's, else the setlist's target).
    public var target: TimeInterval?
    /// The song count asked for, if any.
    public var songCount: Int?
    /// Songs that met the request but have no length, left out of a length target (R107:
    /// "N songs left out: no length"), sorted by title.
    public var leftOutNoLength: [SongID]
    /// How many songs met the request's filters (locked songs not counted).
    public var matchingCount: Int
    /// The tolerance used, in seconds.
    public var tolerance: TimeInterval

    /// Whether the set meets the request: the total is within target +/- tolerance (with no
    /// unknown length), and a requested count is met.
    public var isWithinTolerance: Bool {
        if let songCount, entries.count(where: { !$0.isBreak }) < songCount {
            return false
        }
        guard let target else { return true }
        return timing.unknownCount == 0 && abs(timing.total - target) <= tolerance
    }

    /// The song IDs in set order.
    public var songIDs: [SongID] {
        entries.compactMap(\.songId)
    }
}

/// What Rebuild keeps: the current entries and which song slots are locked. Break rows always
/// stay where they are.
public struct RebuildLayout: Sendable, Equatable {
    public var entries: [SetlistEntry]
    public var locked: Set<SetlistItemID>

    public init(entries: [SetlistEntry], locked: Set<SetlistItemID>) {
        self.entries = entries
        self.locked = locked
    }

    /// The layout of a saved setlist: its entries, locked as saved (R115).
    public init(entries: [SetlistEntry] = []) {
        self.init(entries: entries, locked: Set(entries.filter(\.locked).map(\.itemId)))
    }

    public static let empty = Self()
}

/// Builds a set from a request (spec section 7). Pure apart from `newItemID`.
public struct SetBuilder: Sendable {
    public let config: AssistantConfig

    public init(config: AssistantConfig = .standard) {
        self.config = config
    }

    /// Whether `song` meets the request's filters (tempo filters only, R92).
    public static func admits(
        _ song: AssistantSong,
        _ request: SetRequest,
        smartFilterMatches: [SmartFilterID: Set<SongID>],
    ) -> Bool {
        guard request.proficiency.admits(song.proficiency) else { return false }
        if !request.includeTags.isEmpty, !request.includeTags.contains(where: song.hasTag) {
            return false
        }
        if request.excludeTags.contains(where: song.hasTag) {
            return false
        }
        if !request.keys.isEmpty {
            guard let key = song.key, request.keys.contains(where: { sameKey($0, key) }) else {
                return false
            }
        }
        if let key = song.key, request.excludeKeys.contains(where: { sameKey($0, key) }) {
            return false
        }
        if let tempo = request.tempo {
            guard let bpm = song.tempo, tempo.contains(bpm) else { return false }
        }
        return request.smartFilters.allSatisfy { id in
            smartFilterMatches[id]?.contains(song.id) ?? false
        }
    }

    /// Builds a set.
    /// - Parameters:
    ///   - layout: Rebuild's current entries and locks; `.empty` for a new set.
    ///   - changeover: seconds between songs (the setlist's, else the app default).
    ///   - fallbackTarget: the setlist's target length, used when the request names neither a
    ///     length nor a count.
    ///   - seed: same seed, same set.
    ///   - newItemID: an item ID for each new song slot.
    public func build(
        _ request: SetRequest,
        library: AssistantLibrary,
        layout: RebuildLayout = .empty,
        changeover: TimeInterval = 0,
        fallbackTarget: TimeInterval? = nil,
        seed: UInt64,
        newItemID: () -> SetlistItemID,
    ) -> SetDraft {
        let songsByID = Dictionary(library.songs.map { ($0.id, $0) }) { first, _ in first }
        let scorer = Scorer(
            config: config,
            request: request,
            now: library.now,
            variety: variety(for: library.songs, seed: seed),
        )
        let skeleton = Skeleton(layout: layout, songs: songsByID)
        let target = request.targetLength
            ?? (request.songCount == nil ? fallbackTarget.flatMap { $0 > 0 ? $0 : nil } : nil)
        let count = request.songCount ?? (target == nil ? config.fallbackSongCount : nil)

        let pool = candidates(
            request,
            library: library,
            skeleton: skeleton,
            target: target,
            scorer: scorer,
        )
        var packer = Packer(
            config: config,
            request: request,
            candidates: pool.ranked,
            base: pool.base,
            skeleton: skeleton,
            changeover: max(changeover, 0),
        )
        let picked = packer.pick(target: target, count: count)
        let ordered = Orderer(scorer: scorer, skeleton: skeleton, request: request)
            .order(picked, passes: config.swapPasses)
        let entries = skeleton.entries(filling: ordered, newItemID: newItemID)

        let lengths = Dictionary(uniqueKeysWithValues: songsByID.values.compactMap { song in
            song.length.map { (song.id, SongLength(seconds: $0, source: .directive)) }
        })
        return SetDraft(
            entries: entries,
            breakdowns: breakdowns(entries, songs: songsByID, scorer: scorer),
            timing: SetlistTiming(
                entries: entries, lengths: lengths, target: target, changeover: changeover,
            ),
            target: target,
            songCount: request.songCount,
            leftOutNoLength: pool.leftOut,
            matchingCount: pool.matching,
            tolerance: config.toleranceSeconds,
        )
    }

    /// The songs a request admits (locked ones aside), best base score first, with songs
    /// without a length set aside under a length target (R107).
    private func candidates(
        _ request: SetRequest,
        library: AssistantLibrary,
        skeleton: Skeleton,
        target: TimeInterval?,
        scorer: Scorer,
    ) -> Pool {
        var admitted = library.songs.filter { song in
            !skeleton.lockedSongs.contains(song.id)
                && Self.admits(song, request, smartFilterMatches: library.smartFilterMatches)
        }
        let matching = admitted.count
        var leftOut: [AssistantSong] = []
        if target != nil {
            leftOut = admitted.filter { $0.length == nil }
            admitted.removeAll { $0.length == nil }
        }
        let base = Dictionary(uniqueKeysWithValues: admitted.map { ($0.id, scorer.base($0).total) })
        admitted.sort { lhs, rhs in
            let (left, right) = (base[lhs.id] ?? 0, base[rhs.id] ?? 0)
            return left != right ? left > right : lhs.id < rhs.id
        }
        let named = leftOut
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            .map(\.id)
        return Pool(ranked: admitted, base: base, leftOut: named, matching: matching)
    }

    /// The candidates of one build.
    private struct Pool {
        /// Best base score first.
        var ranked: [AssistantSong]
        var base: [SongID: Double]
        /// Admitted songs without a length (under a length target), by title.
        var leftOut: [SongID]
        /// How many songs the request admits.
        var matching: Int
    }

    /// Each song's raw variety value, drawn from `seed` in song-ID order.
    private func variety(for songs: [AssistantSong], seed: UInt64) -> [SongID: Double] {
        var random = SplitMix64(seed: seed)
        let spread = max(config.varietySpread, 0)
        return Dictionary(uniqueKeysWithValues: songs.map(\.id).sorted().map { id in
            (id, spread * random.nextUnit())
        })
    }

    /// Every song slot's breakdown in its final place.
    private func breakdowns(
        _ entries: [SetlistEntry],
        songs: [SongID: AssistantSong],
        scorer: Scorer,
    ) -> [SetlistItemID: ScoreBreakdown] {
        let songSlots = entries.indices.filter { !entries[$0].isBreak }
        var result: [SetlistItemID: ScoreBreakdown] = [:]
        var previous: AssistantSong?
        for (index, entry) in entries.enumerated() {
            guard let id = entry.songId, let song = songs[id] else {
                previous = nil
                continue
            }
            let slot = SlotContext(
                isOpener: index == songSlots.first,
                isCloser: index == songSlots.last,
                previous: previous,
            )
            result[entry.itemId] = scorer.score(song, in: slot)
            previous = song
        }
        return result
    }

    /// "F#" matches a song in Gb (enharmonics); minor only matches minor.
    static func sameKey(_ name: String, _ key: SongKey) -> Bool {
        guard let wanted = SongKey(parsing: name) else { return false }
        return wanted.mode == key.mode && wanted.tonic.pitchClass == key.tonic.pitchClass
    }
}

/// The deterministic random source (SplitMix64).
struct SplitMix64: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    /// A value in `0 ..< 1`.
    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
