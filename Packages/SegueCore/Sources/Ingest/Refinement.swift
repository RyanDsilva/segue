import ChordPro
import Foundation
import MusicTheory

extension IngestPipeline {
    /// Merges a model's answers into the deterministic result (spec section 3, P3-2 step 3):
    ///
    /// - labels only for unheaded blocks (`questions.unheadedBlocks`; headed labels, and the
    ///   R101 repetition labels, always come from code);
    /// - a title only where code found none (artists come from code only, R174);
    /// - a model key only when `KeyDetector` is ambiguous and the key is one of its top two,
    ///   and then only as the review sheet's suggestion: it is never written into the `.cho`
    ///   (R101);
    /// - line classes only for `.unknown` lines;
    /// - then the lyric guard: a block whose refinement would change any lyric word, alone or
    ///   beside the blocks already accepted, keeps its deterministic result and gets a
    ///   `.refinementRejected` diagnostic; every other block keeps its refinement (R124).
    ///
    /// `base` must be the deterministic result of `ingest`. ChordPro passthrough is returned
    /// unchanged.
    public static func apply(_ refinements: Refinements, to base: IngestResult) -> IngestResult {
        guard !base.isAlreadyChordPro else { return base }
        let unheaded = Set(base.questions.unheadedBlocks)
        let unknown = Set(base.questions.unknownLines)
        let labels = refinements.labels.filter { unheaded.contains($0.key) }
        let lineClasses = refinements.lineClasses.filter { unknown.contains($0.key) }

        let guarded = combined(
            guarded(labels: labels, lineClasses: lineClasses, base: base),
            base: base,
        )
        let acceptedLabels = guarded.labels
        let acceptedLines = guarded.lines
        let rejected = guarded.rejected

        var metadata = base.metadata
        var refinedFields: Set<RefinedField> = []
        if metadata.title == nil, let title = nonEmpty(refinements.title) {
            metadata.title = title
            refinedFields.insert(.title)
        }
        var result = base.reassembled(
            labels: acceptedLabels,
            lineClasses: acceptedLines,
            metadata: metadata,
        )
        if let text = refinements.key, let key = SongKey(parsing: text),
           base.keyInference.accepts(modelKey: key)
        {
            result.keyInference.refined = key
        }
        result.refinedFields = refinedFields
        result.artistSplits = base.artistSplits
        result.diagnostics += rejected.map { .refinementRejected(block: $0) }
        return result
    }

    /// The lyric guard, block by block: each block's refinement alone must keep every word.
    private static func guarded(
        labels: [Int: SectionLabel],
        lineClasses: [Int: LineClass],
        base: IngestResult,
    ) -> Guarded {
        var acceptedLabels: [Int: SectionLabel] = [:]
        var acceptedLines: [Int: LineClass] = [:]
        var rejected: [Int] = []
        for block in base.blocks {
            let blockLabel = labels[block.index]
            let blockLines = lineClasses.filter { entry in
                block.lines.contains { $0.index == entry.key }
            }
            guard blockLabel != nil || !blockLines.isEmpty else { continue }
            let candidate = base.reassembled(
                labels: blockLabel.map { [block.index: $0] } ?? [:],
                lineClasses: blockLines,
            )
            if keepsLyrics(candidate, of: base) {
                acceptedLabels[block.index] = blockLabel
                acceptedLines.merge(blockLines) { first, _ in first }
            } else {
                rejected.append(block.index)
            }
        }
        return Guarded(labels: acceptedLabels, lines: acceptedLines, rejected: rejected)
    }

    /// The guard over the blocks that passed alone, together (R124): when their refinements
    /// fail as a set, they are added back block by block in order and only a block whose
    /// refinement breaks the lyrics of what is already accepted is rejected. One bad label
    /// never discards the rest of the song.
    private static func combined(_ guarded: Guarded, base: IngestResult) -> Guarded {
        guard !keepsLyrics(
            base.reassembled(labels: guarded.labels, lineClasses: guarded.lines),
            of: base,
        ) else { return guarded }
        var result = Guarded(labels: [:], lines: [:], rejected: guarded.rejected)
        for block in base.blocks {
            let blockLabel = guarded.labels[block.index]
            let blockLines = guarded.lines.filter { entry in
                block.lines.contains { $0.index == entry.key }
            }
            guard blockLabel != nil || !blockLines.isEmpty else { continue }
            var labels = result.labels
            labels[block.index] = blockLabel
            let lines = result.lines.merging(blockLines) { first, _ in first }
            if keepsLyrics(base.reassembled(labels: labels, lineClasses: lines), of: base) {
                result.labels = labels
                result.lines = lines
            } else {
                result.rejected.append(block.index)
            }
        }
        result.rejected.sort()
        return result
    }

    private struct Guarded {
        var labels: [Int: SectionLabel]
        var lines: [Int: LineClass]
        var rejected: [Int]
    }

    private static func keepsLyrics(_ candidate: IngestResult, of base: IngestResult) -> Bool {
        LyricGuard.check(original: base.document, refined: candidate.document) == .identical
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
