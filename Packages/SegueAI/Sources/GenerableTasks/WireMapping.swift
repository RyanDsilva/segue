import Foundation
import Ingest
import ModelPort

/// Wire answers -> Core outputs (pure; the adapters' only post-processing). Any answer that
/// does not fit the task (wrong count, a value outside the vocabulary) is a
/// `decodingFailure`, so the router moves on.
public enum WireMapping {
    /// Decodes a generated JSON object (`GeneratedContent.jsonString`) as a wire type.
    public static func decode<Wire: Decodable>(
        _ type: Wire.Type,
        json: String,
    ) throws(ProviderError) -> Wire {
        do {
            return try JSONDecoder().decode(type, from: Data(json.utf8))
        } catch {
            throw .decodingFailure
        }
    }

    /// Labels for `blocks` (the block indices one call covered, in order). Entries are matched
    /// by block number when the numbers are exactly the expected ones, else by position.
    public static func labels(
        _ wire: BlockLabelsWire,
        blocks: [Int],
    ) throws(ProviderError) -> [SectionLabel] {
        guard wire.blocks.count == blocks.count else { throw .decodingFailure }
        let byNumber = Dictionary(wire.blocks.map { ($0.block, $0.label) }) { first, _ in first }
        let ordered = Set(byNumber.keys) == Set(blocks) && byNumber.count == blocks.count
            ? blocks.map { byNumber[$0] ?? "" }
            : wire.blocks.map(\.label)
        return try ordered.map { text throws(ProviderError) in
            guard let label = SectionLabel(rawValue: text) else { throw .decodingFailure }
            return label
        }
    }

    /// Joins chunk answers into one `SectionLabelOutput` for `task`.
    public static func labels(
        chunks: [(range: Range<Int>, wire: BlockLabelsWire)],
        task: SectionLabelTask,
    ) throws(ProviderError) -> SectionLabelOutput {
        var labels: [SectionLabel] = []
        for chunk in chunks {
            labels += try Self.labels(
                chunk.wire,
                blocks: task.blocks[chunk.range].map(\.index),
            )
        }
        guard labels.count == task.blocks.count else { throw .decodingFailure }
        return SectionLabelOutput(labels: labels)
    }

    /// Spike 5.3 post-processing ("unknown" key -> empty, "Unknown" -> empty, artist equal to
    /// the title -> empty).
    public static func metadata(_ wire: MetadataWire) -> MetadataOutput {
        let key = wire.key == ModelVocabulary.unknownKey ? "" : wire.key
        return MetadataOutput(title: wire.title, artist: wire.artist, key: key).normalized()
    }

    public static func lineClasses(
        _ wire: LineClassesWire,
        task: AmbiguousLineTask,
    ) throws(ProviderError) -> AmbiguousLineOutput {
        guard wire.lines.count == task.lines.count else { throw .decodingFailure }
        let classes = try wire.lines.map { entry throws(ProviderError) in
            guard let lineClass = AmbiguousLineClass(rawValue: entry.kind) else {
                throw .decodingFailure
            }
            return lineClass
        }
        return AmbiguousLineOutput(classes: classes)
    }

    public static func setRequest(
        _ wire: SetRequestWire,
        task: SetRequestTask,
    ) -> SetRequestOutput {
        SetRequestOutput(
            includeTags: wire.includeTags,
            excludeTags: wire.excludeTags,
            minProficiency: ProficiencyFloor(rawValue: wire.minProficiency) ?? .any,
            openerTag: wire.openerTag,
            closerTag: wire.closerTag,
        ).normalized(libraryTags: task.libraryTags)
    }
}
