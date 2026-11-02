import Foundation
import Plugins

/// R183, spec 6.10: UG versions of one song ranked by a vote-weighted rating toward a mean of
/// 4.0, `score = v / (v + k) x rating + k / (v + k) x 4.0`, where the prior's weight `k` is the
/// median vote count of that song's listed versions, clamped to 3-50. A popular song's
/// versions are judged mostly by their votes; a less popular song's few-vote versions still
/// rank by their own ratings instead of all collapsing toward the mean.
enum VersionRanker {
    static let mean = 4.0
    static let minimumWeight = 3.0
    static let maximumWeight = 50.0

    /// One version's score and its two parts, which sum to it.
    struct Ranked: Sendable, Hashable {
        var candidate: SearchCandidate
        var fromRating: Double
        var fromPrior: Double

        var score: Double {
            fromRating + fromPrior
        }
    }

    /// The prior's weight for a song: the median vote count, clamped to 3-50.
    static func weight(votes: [Int]) -> Double {
        let sorted = votes.sorted()
        guard !sorted.isEmpty else { return minimumWeight }
        let middle = sorted.count / 2
        let median = sorted.count.isMultiple(of: 2)
            ? Double(sorted[middle - 1] + sorted[middle]) / 2 : Double(sorted[middle])
        return min(max(median, minimumWeight), maximumWeight)
    }

    static func ranked(_ candidate: SearchCandidate, weight: Double) -> Ranked {
        let votes = Double(max(candidate.votes ?? 0, 0))
        let rating = candidate.rating ?? mean
        return Ranked(
            candidate: candidate,
            fromRating: votes / (votes + weight) * rating,
            fromPrior: weight / (votes + weight) * mean,
        )
    }

    /// One song's versions, best first; ties keep the site's order.
    static func rank(_ versions: [SearchCandidate]) -> [Ranked] {
        let weight = weight(votes: versions.map { $0.votes ?? 0 })
        return versions.map { ranked($0, weight: weight) }.enumerated()
            .sorted { lhs, rhs in
                lhs.element.score == rhs.element.score
                    ? lhs.offset < rhs.offset : lhs.element.score > rhs.element.score
            }
            .map(\.element)
    }
}

/// One song in a search group, its versions nested under it (the parent/child rule), best
/// first.
struct SearchSong: Sendable, Hashable {
    var key: String
    var title: String
    var artist: String?
    var album: String?
    var versions: [SearchCandidate]
}
