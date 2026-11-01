import Foundation
import Library
import Setlists

// MARK: - Packer

/// Picks the songs: slot songs first when asked (R92), then by score down the list until the
/// target is reached without passing target + tolerance; when the fill falls short of
/// target - tolerance, swaps a picked song for a longer one.
struct Packer {
    let config: AssistantConfig
    let request: SetRequest
    /// Candidates, best first.
    let candidates: [AssistantSong]
    let base: [SongID: Double]
    let skeleton: Skeleton
    let changeover: TimeInterval

    private var picked: [AssistantSong] = []
    private var pickedIDs: Set<SongID> = []
    /// Slot songs are never swapped out.
    private var pinned: Set<SongID> = []

    init(
        config: AssistantConfig,
        request: SetRequest,
        candidates: [AssistantSong],
        base: [SongID: Double],
        skeleton: Skeleton,
        changeover: TimeInterval,
    ) {
        self.config = config
        self.request = request
        self.candidates = candidates
        self.base = base
        self.skeleton = skeleton
        self.changeover = changeover
    }

    private var timeSum: TimeInterval {
        picked.reduce(0) { $0 + ($1.time ?? 0) }
    }

    private func total(adding extra: TimeInterval = 0, songs: Int? = nil) -> TimeInterval {
        skeleton.total(
            times: timeSum + extra,
            songs: songs ?? picked.count,
            changeover: changeover,
        )
    }

    private mutating func add(_ song: AssistantSong, pin: Bool = false) {
        guard pickedIDs.insert(song.id).inserted else { return }
        picked.append(song)
        if pin {
            pinned.insert(song.id)
        }
    }

    mutating func pick(target: TimeInterval?, count: Int?) -> [AssistantSong] {
        let wanted = count.map { max($0 - skeleton.lockedSongCount, 0) }
        let tolerance = max(config.toleranceSeconds, 0)
        pickSlotSongs(wanted: wanted, target: target, tolerance: tolerance)
        for song in candidates where !pickedIDs.contains(song.id) {
            if let wanted, picked.count >= wanted {
                break
            }
            guard let target else {
                add(song)
                continue
            }
            if total() >= target {
                break
            }
            if total(adding: song.time ?? 0, songs: picked.count + 1) <= target + tolerance {
                add(song)
            }
        }
        if let target {
            fillShortfall(target: target, tolerance: tolerance, wanted: wanted)
        }
        return picked
    }

    /// The best-scoring song with the opener (closer) tag, when the request asks and the
    /// first (last) song slot is free.
    private mutating func pickSlotSongs(
        wanted: Int?,
        target: TimeInterval?,
        tolerance: TimeInterval,
    ) {
        let room = wanted ?? Int.max
        guard room > 0 else { return }
        let slots: [(String?, Bool)] = [
            (request.openerTag, skeleton.opensFree),
            (request.closerTag, skeleton.closesFree),
        ]
        for (tag, free) in slots {
            guard let tag, free, picked.count < room else { continue }
            let count = picked.count + 1
            let limit = target.map { $0 + tolerance }
            let found = candidates.first { song in
                guard !pickedIDs.contains(song.id), song.hasTag(tag) else { return false }
                guard let limit else { return true }
                return total(adding: song.time ?? 0, songs: count) <= limit
            }
            if let found {
                add(found, pin: true)
            }
        }
    }

    /// Below target - tolerance: add songs that still fit, else swap a picked song for a
    /// longer unpicked one (best score trade first) until the total is in the window or no
    /// swap helps.
    private mutating func fillShortfall(
        target: TimeInterval,
        tolerance: TimeInterval,
        wanted: Int?,
    ) {
        let low = target - tolerance
        let high = target + tolerance
        for _ in 0 ..< max(candidates.count, 1) {
            let current = total()
            guard current < low else { return }
            if wanted.map({ picked.count < $0 }) ?? true,
               let song = candidates.first(where: {
                   !pickedIDs.contains($0.id)
                       && total(adding: $0.time ?? 0, songs: picked.count + 1) <= high
               })
            {
                add(song)
                continue
            }
            guard let swap = bestSwap(current: current, low: low, high: high) else { return }
            pickedIDs.remove(picked[swap.out].id)
            picked[swap.out] = swap.in
            pickedIDs.insert(swap.in.id)
        }
    }

    /// A swap candidate: replace `picked[out]` by `in`.
    private struct Swap {
        var out: Int
        var `in`: AssistantSong
        /// Whether the total lands in the window after it.
        var reaches: Bool
        var gain: TimeInterval
        /// Base score gained (negative: lost).
        var trade: Double

        /// Reaching the window first; then the best score trade, or (still short) the most
        /// time gained.
        func beats(_ other: Self) -> Bool {
            if reaches != other.reaches {
                return reaches
            }
            return reaches ? trade > other.trade : gain > other.gain
        }
    }

    private func bestSwap(current: TimeInterval, low: TimeInterval, high: TimeInterval)
        -> (out: Int, in: AssistantSong)?
    {
        var best: Swap?
        for (index, song) in picked.enumerated() where !pinned.contains(song.id) {
            let time = song.time ?? 0
            for other in candidates where !pickedIDs.contains(other.id) {
                let gain = (other.time ?? 0) - time
                guard gain > 0, current + gain <= high else { continue }
                let swap = Swap(
                    out: index,
                    in: other,
                    reaches: current + gain >= low,
                    gain: gain,
                    trade: (base[other.id] ?? 0) - (base[song.id] ?? 0),
                )
                if best.map(swap.beats) ?? true {
                    best = swap
                }
            }
        }
        return best.map { ($0.out, $0.in) }
    }
}

// MARK: - Orderer

/// Orders the picked songs into the free positions for flow: slot songs at the ends when
/// asked, then a nearest-neighbour walk by key flow, then pairwise swaps while they help.
struct Orderer {
    let scorer: Scorer
    let skeleton: Skeleton
    let request: SetRequest

    func order(_ songs: [AssistantSong], passes: Int) -> [AssistantSong] {
        guard songs.count > 1 else { return songs }
        let positions = skeleton.positions(for: songs.count)
        var order = greedy(songs, positions: positions)
        let freeIndices = Array(order.indices)
        var score = objective(order, positions: positions)
        for _ in 0 ..< max(passes, 0) {
            var improved = false
            for first in freeIndices {
                for second in freeIndices where second > first {
                    order.swapAt(first, second)
                    let candidate = objective(order, positions: positions)
                    if candidate > score + 1e-9 {
                        score = candidate
                        improved = true
                    } else {
                        order.swapAt(first, second)
                    }
                }
            }
            if !improved {
                break
            }
        }
        return order
    }

    /// The weighted slot and flow terms of the whole set with `order` in the free positions.
    func objective(_ order: [AssistantSong], positions: [Skeleton.Position]) -> Double {
        let weights = scorer.config.weights
        let sequence = resolve(order, positions: positions)
        let songIndices = sequence.indices.filter { sequence[$0] != nil }
        var total = 0.0
        var previous: AssistantSong?
        for (index, song) in sequence.enumerated() {
            // A medley: the flow into its first member counts; it scores no slot fit and
            // the next slot flows from its last member.
            if case let .medley(_, first, last) = positions[index] {
                if let first {
                    total += weights.keyFlow * scorer.flow(from: previous, to: first).0
                }
                previous = last
                continue
            }
            guard let song else {
                previous = nil
                continue
            }
            let slot = SlotContext(
                isOpener: index == songIndices.first,
                isCloser: index == songIndices.last,
                previous: previous,
            )
            total += weights.slot * scorer.slotFit(song, slot).0
            total += weights.keyFlow * scorer.flow(from: previous, to: song).0
            previous = song
        }
        return total
    }

    /// The songs of the set in order (nil = a break row, or a locked song the library no
    /// longer has, which breaks the flow chain).
    private func resolve(_ order: [AssistantSong], positions: [Skeleton.Position])
        -> [AssistantSong?]
    {
        var queue = order[...]
        return positions.map { position in
            switch position {
            case let .fixed(_, song): song
            case let .medley(_, first, _): first
            case .breakRow: nil
            case .free: queue.popFirst()
            }
        }
    }

    /// Opener / closer songs at the ends, then each free slot takes the remaining song with
    /// the best flow from the song before it (ties: the earlier, higher-scored pick).
    private func greedy(_ songs: [AssistantSong], positions: [Skeleton.Position])
        -> [AssistantSong]
    {
        var remaining = songs
        var firstSong: AssistantSong?
        var lastSong: AssistantSong?
        let songPositions = positions.indices.filter { !positions[$0].isBreak }
        if let tag = request.openerTag, let first = songPositions.first,
           positions[first] == .free, let index = remaining.firstIndex(where: { $0.hasTag(tag) })
        {
            firstSong = remaining.remove(at: index)
        }
        if let tag = request.closerTag, let last = songPositions.last,
           positions[last] == .free, remaining.count + (firstSong == nil ? 0 : 1) > 1,
           let index = remaining.firstIndex(where: { $0.hasTag(tag) })
        {
            lastSong = remaining.remove(at: index)
        }
        let freeCount = positions.count(where: { $0 == .free })
        var result: [AssistantSong] = []
        var previous: AssistantSong?
        var freeSeen = 0
        for position in positions {
            switch position {
            case .breakRow:
                previous = nil
            case let .fixed(_, song):
                previous = song
            case let .medley(_, _, last):
                previous = last
            case .free:
                freeSeen += 1
                let song: AssistantSong
                if freeSeen == 1, let firstSong {
                    song = firstSong
                } else if freeSeen == freeCount, let lastSong {
                    song = lastSong
                } else if !remaining.isEmpty {
                    let index = bestNext(after: previous, in: remaining)
                    song = remaining.remove(at: index)
                } else {
                    continue
                }
                result.append(song)
                previous = song
            }
        }
        return result
    }

    private func bestNext(after previous: AssistantSong?, in songs: [AssistantSong]) -> Int {
        guard let previous else { return 0 }
        var best = 0
        var bestValue = -Double.infinity
        for (index, song) in songs.enumerated() {
            let value = scorer.flow(from: previous, to: song).0
            if value > bestValue + 1e-9 {
                best = index
                bestValue = value
            }
        }
        return best
    }
}
