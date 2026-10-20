import ChordPro
import Foundation
import Ingest
import ModelPort
import Services

/// `Segue.AI.pasteFinished` for one reviewed song (spec section 11, R74, R98). Only enums,
/// buckets and booleans: never the song's text, title or artist.
@MainActor
enum PasteAnalytics {
    static func summary(for item: PasteReviewItem, outcome: PasteOutcome) -> PasteFinishedSummary {
        let (provider, fallback) = routing(item.reports)
        return PasteFinishedSummary(
            source: item.source,
            provider: provider,
            fallback: fallback,
            latency: LatencyBucket(seconds: item.refinementSeconds),
            outcome: outcome,
            correction: outcome == .accepted ? correction(of: item) : .noCorrection,
            romanHindi: item.isRomanizedHindi,
        )
    }

    /// Which provider answered and why the preferred one did not. With no answer the last
    /// miss is the most telling (MLX not installed, then Apple Intelligence off: `fmOff`);
    /// with an answer, the miss before it.
    nonisolated static func routing(_ reports: [ModelTaskKind: RoutingReport])
        -> (AIProviderUsed, PasteFallback)
    {
        let ordered = [ModelTaskKind.sectionLabels, .metadata, .ambiguousLines]
            .compactMap { reports[$0] }
        guard let report = ordered.first(where: { $0.answeredBy != nil }) ?? ordered.first
        else { return (.noProvider, .noFallback) }
        if report.skipped == .aiOff {
            return (.noProvider, .aiOff)
        }
        let provider: AIProviderUsed = switch report.answeredBy?.kind {
        case .mlx: .mlx
        case .foundationModels: .fm
        case nil: .noProvider
        }
        let misses = report.attempts.filter { $0.outcome != .answered }
        let miss = provider == .noProvider ? misses.last : report.firstMiss.flatMap { outcome in
            misses.first { $0.outcome == outcome }
        }
        return (provider, miss.map { fallback($0.outcome) } ?? .noFallback)
    }

    nonisolated static func fallback(_ outcome: RoutingAttemptOutcome) -> PasteFallback {
        switch outcome {
        case .answered: .noFallback
        case let .unavailable(cause): fallback(cause)
        case let .failed(error): fallback(error)
        }
    }

    nonisolated static func fallback(_ cause: UnavailableCause) -> PasteFallback {
        switch cause {
        case .notInstalled: .notInstalled
        case .appleIntelligenceNotEnabled: .fmOff
        case .modelNotReady: .fmNotReady
        case .deviceNotEligible: .fmIneligible
        case .duringShow, .unknown: .other
        }
    }

    nonisolated static func fallback(_ error: ProviderError) -> PasteFallback {
        switch error {
        case .unsupportedLanguage: .unsupportedLang
        case .guardrail, .refusal: .guardrail
        case .decodingFailure, .incompleteOutput: .decoding
        case .contextOverflow: .overBudget
        case .busy, .rateLimited: .busy
        case .timeout: .timeout
        case .notInstalled: .notInstalled
        case .other: .other
        }
    }

    /// The edit distance between what the AI decided and what was accepted: the section
    /// label sequence (Levenshtein, only when a model labelled a block) plus one per
    /// AI-filled title or artist the user changed.
    static func correction(of item: PasteReviewItem) -> CorrectionBucket {
        guard item.hasAIDecisions else { return .noCorrection }
        let proposed = ChordProParser.parse(item.proposal.text).0
        let accepted = ChordProParser.parse(item.text).0
        var changes = 0
        if !item.aiLabelledBlocks.isEmpty {
            changes += distance(labels(proposed), labels(accepted))
        }
        if item.aiFields.contains(.title), proposed.metadata.title != accepted.metadata.title {
            changes += 1
        }
        if item.aiFields.contains(.artist),
           proposed.metadata.artists.first != accepted.metadata.artists.first
        {
            changes += 1
        }
        return CorrectionBucket(changes: changes)
    }

    nonisolated static func labels(_ document: SongDocument) -> [String] {
        document.blocks.compactMap { block in
            guard case let .section(section) = block else { return nil }
            return "\(section.kind)|\(section.label ?? "")"
        }
    }

    /// Levenshtein distance over two sequences.
    nonisolated static func distance(_ lhs: [String], _ rhs: [String]) -> Int {
        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }
        var previous = Array(0 ... rhs.count)
        for (row, left) in lhs.enumerated() {
            var current = [row + 1]
            for (column, right) in rhs.enumerated() {
                current.append(min(
                    previous[column + 1] + 1,
                    current[column] + 1,
                    previous[column] + (left == right ? 0 : 1),
                ))
            }
            previous = current
        }
        return previous[rhs.count]
    }
}
