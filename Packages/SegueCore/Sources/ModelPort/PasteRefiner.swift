import Foundation
import Ingest

/// One step of a paste's AI refinement: the merged result so far and how each task routed.
public struct PasteRefinementUpdate: Sendable {
    /// The deterministic result with every answer so far merged in (`IngestPipeline.apply`).
    public var result: IngestResult
    /// The answers so far, as merged.
    public var refinements: Refinements
    /// How each task that ran was routed.
    public var reports: [ModelTaskKind: RoutingReport]
    /// True on the last update.
    public var isFinal: Bool
}

/// The AI refinement of a paste (spec section 3): builds the tasks from the deterministic
/// result, routes them one after another (labels, metadata, then unknown lines), and merges
/// each answer as it arrives. The review sheet shows the deterministic result before this
/// starts and takes each update as it streams in.
public enum PasteRefiner {
    /// The labels call: every block with its hints, or `nil` when no block is unheaded.
    public static func labelTask(for result: IngestResult) -> SectionLabelTask? {
        guard !result.isAlreadyChordPro, !result.questions.unheadedBlocks.isEmpty else {
            return nil
        }
        return SectionLabelTask(blocks: result.blocks.map { block in
            SectionLabelTask.Block(
                index: block.index,
                lines: block.lines.map(\.text),
                hint: block.hints.summary,
            )
        })
    }

    /// The metadata call, or `nil` when code already has a title (R121: the converter wins,
    /// whatever the key; artists come from code only, R174), or when there is no top or bottom
    /// candidate block (spike 5.3: without one FM took a chord as the title).
    public static func metadataTask(for result: IngestResult) -> MetadataTask? {
        guard !result.isAlreadyChordPro,
              let candidates = result.questions.metadataCandidates,
              !candidates.topLines.isEmpty || !candidates.bottomLines.isEmpty,
              result.metadata.title == nil
        else { return nil }
        return MetadataTask(
            topLines: candidates.topLines,
            bottomLines: candidates.bottomLines,
            chords: candidates.chords,
        )
    }

    /// The unknown-lines call: only `.unknown` lines inside song sections (lines around the
    /// song are notes and credits by position), or `nil` when there are none.
    public static func ambiguousLineTask(for result: IngestResult) -> AmbiguousLineTask? {
        guard !result.isAlreadyChordPro else { return nil }
        let unknown = Set(result.questions.unknownLines)
        let lines = result.blocks.filter { $0.role == .content }.flatMap { block in
            block.lines.enumerated().compactMap { position, line -> AmbiguousLineTask.Line? in
                guard unknown.contains(line.index) else { return nil }
                let around = block.lines[max(0, position - 1) ..< min(
                    block.lines.count,
                    position + 2,
                )]
                return AmbiguousLineTask.Line(
                    index: line.index,
                    text: line.text,
                    context: around.filter { $0.index != line.index }.map(\.text),
                )
            }
        }
        return lines.isEmpty ? nil : AmbiguousLineTask(lines: lines)
    }

    // MARK: - Mapping answers

    public static func refinements(
        _ output: SectionLabelOutput,
        for task: SectionLabelTask,
    ) -> Refinements {
        var refinements = Refinements()
        for (block, label) in zip(task.blocks, output.labels) {
            refinements.labels[block.index] = label
        }
        return refinements
    }

    /// The title only when it appears in the candidate lines (case-insensitive) and could be
    /// a name: chord tokens, a capo or tuning note or a chord legend are dropped (the
    /// real-paste eval saw a chord list and a capo line come back as the title). The value
    /// returned is the sheet's own spelling of the matched text, never the model's casing
    /// (R163: code results win; no AI step re-spells a name).
    public static func refinements(
        _ output: MetadataOutput,
        for task: MetadataTask,
    ) -> Refinements {
        let normalized = output.normalized()
        let text = (task.topLines + task.bottomLines).joined(separator: "\n")
        func written(_ value: String) -> String? {
            guard !value.isEmpty,
                  let range = text.range(of: value, options: [.caseInsensitive])
            else { return nil }
            let sheet = String(text[range])
            return IngestPipeline.isPlausibleName(sheet) ? sheet : nil
        }
        return Refinements(
            title: written(normalized.title),
            key: normalized.key.isEmpty ? nil : normalized.key,
        )
    }

    public static func refinements(
        _ output: AmbiguousLineOutput,
        for task: AmbiguousLineTask,
    ) -> Refinements {
        var refinements = Refinements()
        for (line, lineClass) in zip(task.lines, output.classes) {
            refinements.lineClasses[line.index] = lineClass.lineClass
        }
        return refinements
    }

    // MARK: - Running

    /// Routes each task in turn and yields the merged result after each one; the last update
    /// has `isFinal`. Cancelling the consuming task stops the refinement (the user edited or
    /// accepted).
    public static func refine(
        _ base: IngestResult,
        router: Router,
    ) -> AsyncStream<PasteRefinementUpdate> {
        AsyncStream { continuation in
            let work = Task {
                var merged = Refinements()
                var reports: [ModelTaskKind: RoutingReport] = [:]
                func yield(final: Bool) {
                    continuation.yield(PasteRefinementUpdate(
                        result: IngestPipeline.apply(merged, to: base),
                        refinements: merged,
                        reports: reports,
                        isFinal: final,
                    ))
                }
                if let task = labelTask(for: base) {
                    let routed = await router.run(task)
                    reports[.sectionLabels] = routed.report
                    if let output = routed.output {
                        merged.labels = refinements(output, for: task).labels
                    }
                    yield(final: false)
                }
                if !Task.isCancelled, let task = metadataTask(for: base) {
                    let routed = await router.run(task)
                    reports[.metadata] = routed.report
                    if let output = routed.output {
                        let answer = refinements(output, for: task)
                        merged.title = answer.title
                        merged.key = answer.key
                    }
                    yield(final: false)
                }
                if !Task.isCancelled, let task = ambiguousLineTask(for: base) {
                    let routed = await router.run(task)
                    reports[.ambiguousLines] = routed.report
                    if let output = routed.output {
                        merged.lineClasses = refinements(output, for: task).lineClasses
                    }
                }
                yield(final: true)
                continuation.finish()
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    /// The final update of `refine`.
    public static func refined(
        _ base: IngestResult,
        router: Router,
    ) async -> PasteRefinementUpdate {
        var last: PasteRefinementUpdate?
        for await update in refine(base, router: router) {
            last = update
        }
        return last ?? PasteRefinementUpdate(
            result: base, refinements: Refinements(), reports: [:], isFinal: true,
        )
    }
}
