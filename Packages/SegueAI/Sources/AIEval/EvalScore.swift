import Foundation
import ModelPort

/// The spike metrics over a set of eval records (aggregate numbers only, so a score summary of
/// Ryan's local pastes never names a song): section labels split headed and unheaded, songs
/// with every label right, title, artist and key, call failures by kind, retries, and
/// latency p50/p90 for the labels call and per song.
public struct EvalScore: Sendable, Hashable, Codable {
    public var songs = 0
    public var songsAllLabelsRight = 0
    public var blocks = 0
    public var blocksRight = 0
    public var headed = 0
    public var headedRight = 0
    public var titles = 0
    public var titlesRight = 0
    public var artists = 0
    public var artistsRight = 0
    /// The deterministic result's artist lists right (code only, before any model answer);
    /// nil in a baseline written before P8-8.
    public var codeArtistsRight: Int?
    public var keys = 0
    public var keysRight = 0
    /// Songs whose block count differs from the gold (all their labels count as wrong).
    public var blockCountMismatches = 0
    public var calls = 0
    public var failures: [String: Int] = [:]
    public var retries = 0
    public var labelsCallP50Ms = 0
    public var labelsCallP90Ms = 0
    public var songP50Ms = 0
    public var songP90Ms = 0

    public init() {}

    /// Scores `records` against `gold` (records without a gold entry are left out).
    public init(records: [EvalRecord], gold: [String: GoldEntry]) {
        var labelLatencies: [Int] = []
        var songLatencies: [Int] = []
        for record in records where !record.skipped {
            guard let entry = gold[record.fixture] else { continue }
            add(record, gold: entry)
            labelLatencies += record.calls.filter { $0.task == .sectionLabels }.map(\.latencyMs)
            songLatencies.append(record.calls.reduce(0) { $0 + $1.latencyMs })
        }
        (labelsCallP50Ms, labelsCallP90Ms) = Self.percentiles(labelLatencies)
        (songP50Ms, songP90Ms) = Self.percentiles(songLatencies)
    }

    public var labelAccuracy: Double {
        Self.ratio(blocksRight, blocks)
    }

    public var unheadedAccuracy: Double {
        Self.ratio(blocksRight - headedRight, blocks - headed)
    }

    /// Title and artist both right.
    public var titleArtistAccuracy: Double {
        Self.ratio(titlesRight + artistsRight, titles + artists)
    }

    private mutating func add(_ record: EvalRecord, gold: GoldEntry) {
        songs += 1
        if record.labels.count != gold.labels.count {
            blockCountMismatches += 1
        }
        var allRight = record.labels.count == gold.labels.count
        for (position, accepted) in gold.labels.enumerated() {
            let label = position < record.labels.count ? record.labels[position] : ""
            let right = accepted.contains(label)
            let isHeaded = position < record.headed.count && record.headed[position]
            blocks += 1
            blocksRight += right ? 1 : 0
            headed += isHeaded ? 1 : 0
            headedRight += isHeaded && right ? 1 : 0
            allRight = allRight && right
        }
        songsAllLabelsRight += allRight ? 1 : 0
        titles += 1
        titlesRight += gold.title.contains(Self.norm(record.title)) ? 1 : 0
        artists += 1
        artistsRight += gold.artist.contains(record.artists.compactMap(Self.norm)) ? 1 : 0
        codeArtistsRight = (codeArtistsRight ?? 0)
            + (gold.artist.contains(record.codeArtists.compactMap(Self.norm)) ? 1 : 0)
        keys += 1
        keysRight += gold.key.contains(record.key ?? "unknown") ? 1 : 0
        for call in record.calls {
            calls += 1
            retries += call.retries
            if let error = call.error {
                failures[error.rawValue, default: 0] += 1
            }
        }
    }

    /// One line per metric, for the terminal and `summary.txt`.
    public var report: String {
        func percent(_ part: Int, _ whole: Int) -> String {
            whole == 0 ? "n/a" : String(format: "%.1f%%", Double(part) * 100 / Double(whole))
        }
        let failureText = failures.isEmpty ? "none"
            : failures.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }
            .joined(separator: ", ")
        return """
        songs \(songs) (block-count mismatches \(blockCountMismatches))
        labels \(blocksRight)/\(blocks) \(percent(blocksRight, blocks)); \
        headed \(headedRight)/\(headed); \
        unheaded \(blocksRight - headedRight)/\(blocks - headed) \
        \(percent(blocksRight - headedRight, blocks - headed))
        songs with every label right \(songsAllLabelsRight)/\(songs)
        title \(titlesRight)/\(titles), artist \(artistsRight)/\(artists) \
        (code only \(codeArtistsRight ?? 0)/\(artists)), \
        key \(keysRight)/\(keys)
        calls \(calls), failures: \(failureText), retries \(retries)
        labels call p50/p90 \(labelsCallP50Ms)/\(labelsCallP90Ms) ms; \
        per song p50/p90 \(songP50Ms)/\(songP90Ms) ms
        """
    }

    /// Where `self` fell short of `baseline` by more than the noise allowance: accuracy
    /// counts drop by more than `tolerance` of their total, or a new failure kind appears.
    public func regressions(against baseline: Self, tolerance: Double = 0.03) -> [String] {
        var found: [String] = []
        func check(_ name: String, _ now: Double, _ before: Double) {
            if now + tolerance < before {
                found.append(String(
                    format: "%@ %.1f%% < baseline %.1f%%",
                    name,
                    now * 100,
                    before * 100,
                ))
            }
        }
        check("labels", labelAccuracy, baseline.labelAccuracy)
        check("unheaded labels", unheadedAccuracy, baseline.unheadedAccuracy)
        check("title/artist", titleArtistAccuracy, baseline.titleArtistAccuracy)
        check("key", Self.ratio(keysRight, keys), Self.ratio(baseline.keysRight, baseline.keys))
        for kind in failures.keys where baseline.failures[kind] == nil {
            found.append("new failure kind: \(kind)")
        }
        return found
    }

    /// Lowercased letters and digits only; nil for nothing.
    public static func norm(_ text: String?) -> String? {
        let folded = (text ?? "").lowercased().filter { $0.isLetter || $0.isNumber }
        return folded.isEmpty ? nil : folded
    }

    static func ratio(_ part: Int, _ whole: Int) -> Double {
        whole == 0 ? 0 : Double(part) / Double(whole)
    }

    static func percentiles(_ values: [Int]) -> (Int, Int) {
        guard !values.isEmpty else { return (0, 0) }
        let sorted = values.sorted()
        func at(_ fraction: Double) -> Int {
            sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * fraction).rounded()))]
        }
        return (at(0.5), at(0.9))
    }
}
