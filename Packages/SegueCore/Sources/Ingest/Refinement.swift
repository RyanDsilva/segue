import ChordPro
import Foundation
import MusicTheory

extension IngestPipeline {
    /// Merges a model's answers into the deterministic result (spec section 3, P3-2 step 3):
    ///
    /// - labels only for unheaded blocks (`questions.unheadedBlocks`; headed labels, and the
    ///   R101 repetition labels, always come from code);
    /// - title and artist only where code found none;
    /// - a model key only when `KeyDetector` is ambiguous and the key is one of its top two,
    ///   and then only as the review sheet's suggestion: it is never written into the `.cho`
    ///   (R101);
    /// - line classes only for `.unknown` lines;
    /// - then the lyric guard: a block whose refinement would change any lyric word keeps its
    ///   deterministic result and gets a `.refinementRejected` diagnostic.
    ///
    /// `base` must be the deterministic result of `ingest`. ChordPro passthrough is returned
    /// unchanged.
    public static func apply(_ refinements: Refinements, to base: IngestResult) -> IngestResult {
        guard !base.isAlreadyChordPro else { return base }
        let unheaded = Set(base.questions.unheadedBlocks)
        let unknown = Set(base.questions.unknownLines)
        let labels = refinements.labels.filter { unheaded.contains($0.key) }
        let lineClasses = refinements.lineClasses.filter { unknown.contains($0.key) }

        let guarded = guarded(labels: labels, lineClasses: lineClasses, base: base)
        let acceptedLabels = guarded.labels
        let acceptedLines = guarded.lines
        var rejected = guarded.rejected

        var metadata = base.metadata
        var refinedFields: Set<RefinedField> = []
        if metadata.title == nil, let title = nonEmpty(refinements.title) {
            metadata.title = title
            refinedFields.insert(.title)
        }
        // R121: the converter wins. A title code found (a site heading included) means the
        // artist line, if any, was already read: a model artist is never taken beside it.
        if metadata.artists.isEmpty, base.metadata.title == nil,
           let artist = nonEmpty(refinements.artist)
        {
            metadata.artists = [artist]
            refinedFields.insert(.artist)
        }

        var result = base.reassembled(
            labels: acceptedLabels,
            lineClasses: acceptedLines,
            metadata: metadata,
        )
        if !keepsLyrics(result, of: base) {
            // Defensive: refinements that pass alone but not together all fall back.
            rejected = Array(Set(rejected).union(acceptedLabels.keys).union(
                base.blocks.filter { block in
                    block.lines.contains { acceptedLines[$0.index] != nil }
                }.map(\.index),
            )).sorted()
            result = base.reassembled(metadata: metadata)
        }
        if let text = refinements.key, let key = SongKey(parsing: text),
           base.keyInference.accepts(modelKey: key)
        {
            result.keyInference.refined = key
        }
        result.refinedFields = refinedFields
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
