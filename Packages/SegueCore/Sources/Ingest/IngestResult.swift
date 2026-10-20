import ChordPro
import MusicTheory

/// The deterministic result of `IngestPipeline.ingest`: what the review sheet opens with.
public struct IngestResult: Sendable, Equatable {
    public var origin: IngestOrigin
    public var format: TextFormat
    /// Already ChordPro: imports directly without review (A29). `text` is then the source
    /// as given (minus a byte order mark).
    public var isAlreadyChordPro: Bool
    /// The ChordPro text to write as the new `.cho`.
    public var text: String
    /// `text`, parsed.
    public var document: SongDocument
    /// Every normalized line with its class (refinements refer to these by index).
    public var lines: [IngestLine]
    public var blocks: [IngestBlock]
    public var metadata: IngestMetadata
    public var keyInference: KeyInference
    /// What a model may refine (empty for ChordPro passthrough).
    public var questions: RefinementQuestions
    public var diagnostics: [IngestDiagnostic]
    /// Metadata fields a model filled in (`IngestPipeline.apply`); empty for the deterministic
    /// result.
    public var refinedFields: Set<RefinedField> = []

    /// Metadata fields the source already writes as directives (never written twice).
    var directiveFields: Set<MetadataKey>
    /// Lines whose metadata became directives (dropped from the body).
    var consumedLines: Set<Int>
    /// Junk lines the normalizer dropped.
    var removed: [RemovedLine]

    /// Re-renders with the given labels, line classes and metadata, applying no policy.
    /// P3-2's `apply(_ refinements:)` decides what to accept (labels only for unheaded
    /// blocks, metadata only where code found none, the key rule, the lyric guard) and calls
    /// this. Labels and line classes are by index; unknown indices are ignored.
    public func reassembled(
        labels: [Int: SectionLabel] = [:],
        lineClasses: [Int: LineClass] = [:],
        metadata: IngestMetadata? = nil,
    ) -> Self {
        guard !isAlreadyChordPro else { return self }
        var draft = self
        for (index, lineClass) in lineClasses where draft.lines.indices.contains(index) {
            draft.lines[index].lineClass = lineClass
        }
        for blockIndex in draft.blocks.indices {
            for lineIndex in draft.blocks[blockIndex].lines.indices {
                let line = draft.blocks[blockIndex].lines[lineIndex]
                draft.blocks[blockIndex].lines[lineIndex].lineClass = draft.lines[line.index]
                    .lineClass
            }
            if let label = labels[blockIndex] {
                draft.blocks[blockIndex].label = label
                draft.blocks[blockIndex].labelSource = .refined
                if draft.blocks[blockIndex].role == .metadata, label != .other {
                    draft.blocks[blockIndex].role = .content
                }
            }
        }
        if let metadata {
            draft.metadata = metadata
        }
        return IngestPipeline.assemble(draft)
    }
}

/// Metadata fields that become directives.
enum MetadataKey: String, Sendable, Equatable, Hashable, CaseIterable {
    case title
    case artist
    case composer
    case lyricist
    case album
    case key
    case capo
    case tempo
}
