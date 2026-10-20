import Foundation
import FoundationModels
import ModelPort

/// The generation schemas per task, built from the wire types plus the dynamic constraints the
/// spike validated (exact counts where the count is known, the library's tags as an enum).
/// The one schema source for both adapters: FM passes these to `respond(schema:)`, MLX encodes
/// them with `json(_:)`.
public enum WireSchemas {
    /// `BlockLabelsWire` with exactly `blockCount` entries (spike variant E). With
    /// `boundedIndex` the block number is also limited to `0 ... blockCount - 1` (the MLX
    /// grammar needs it against digit runaway, spike 3.2; FM keeps the validated plain int).
    public static func labels(
        blockCount: Int,
        boundedIndex: Bool = false,
    ) throws -> GenerationSchema {
        let item = if boundedIndex {
            DynamicGenerationSchema(name: "BlockLabelWire", properties: [
                .init(
                    name: "block",
                    description: "Block number as shown in the sheet",
                    schema: DynamicGenerationSchema(
                        type: Int.self,
                        guides: [.range(0 ... max(blockCount - 1, 0))],
                    ),
                ),
                .init(
                    name: "label",
                    description: "Section kind of this block",
                    schema: DynamicGenerationSchema(
                        name: "SectionLabel",
                        anyOf: WireVocabulary.labels,
                    ),
                ),
            ])
        } else {
            DynamicGenerationSchema(type: BlockLabelWire.self)
        }
        return try exactArray(
            root: "BlockLabelsWire",
            property: "blocks",
            description: "Exactly one entry per block, in block order",
            item: item,
            count: blockCount,
        )
    }

    /// `LineClassesWire` with exactly `lineCount` entries.
    public static func lineClasses(lineCount: Int) throws -> GenerationSchema {
        try exactArray(
            root: "LineClassesWire",
            property: "lines",
            description: "Exactly one entry per line, in line order",
            item: DynamicGenerationSchema(type: LineClassWire.self),
            count: lineCount,
        )
    }

    /// `MetadataWire` as declared.
    public static var metadata: GenerationSchema {
        MetadataWire.generationSchema
    }

    /// `SetRequestWire` with every tag field limited to `libraryTags` (at most 4 per list; the
    /// opener and closer tag may also be empty). Without library tags the tag lists are empty.
    public static func setRequest(libraryTags: [String]) throws -> GenerationSchema {
        let tags = Array(Set(libraryTags)).sorted()
        let tag = DynamicGenerationSchema(name: "LibraryTag", anyOf: tags.isEmpty ? [""] : tags)
        let tagOrNone = DynamicGenerationSchema(name: "LibraryTagOrNone", anyOf: [""] + tags)
        let maximum = tags.isEmpty ? 0 : 4
        let root = DynamicGenerationSchema(name: "SetRequestWire", properties: [
            .init(
                name: "minProficiency",
                description: "Minimum proficiency",
                schema: DynamicGenerationSchema(
                    name: "Proficiency",
                    anyOf: WireVocabulary.proficiency,
                ),
            ),
            .init(
                name: "includeTags",
                description: "Tags named in the request",
                schema: DynamicGenerationSchema(
                    arrayOf: tag,
                    minimumElements: 0,
                    maximumElements: maximum,
                ),
            ),
            .init(
                name: "excludeTags",
                description: "Tags the request excludes",
                schema: DynamicGenerationSchema(
                    arrayOf: tag,
                    minimumElements: 0,
                    maximumElements: maximum,
                ),
            ),
            .init(
                name: "openerTag",
                description: "Tag for the opening song, or an empty string",
                schema: tagOrNone,
            ),
            .init(
                name: "closerTag",
                description: "Tag for the closing song, or an empty string",
                schema: tagOrNone,
            ),
        ])
        return try GenerationSchema(root: root, dependencies: [])
    }

    /// A schema as JSON Schema text (sorted keys): what the MLX adapter turns into its grammar
    /// (spike 3: `GenerationSchema` is `Codable` and encodes standard JSON Schema).
    public static func json(_ schema: GenerationSchema) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let text = try String(bytes: encoder.encode(schema), encoding: .utf8) else {
            throw CocoaError(.coderInvalidValue)
        }
        return text
    }

    private static func exactArray(
        root: String,
        property: String,
        description: String,
        item: DynamicGenerationSchema,
        count: Int,
    ) throws -> GenerationSchema {
        let rootSchema = DynamicGenerationSchema(name: root, properties: [
            .init(
                name: property,
                description: description,
                schema: DynamicGenerationSchema(
                    arrayOf: item,
                    minimumElements: count,
                    maximumElements: count,
                ),
            ),
        ])
        return try GenerationSchema(root: rootSchema, dependencies: [])
    }
}

/// `schemaJSON(for:)`: the JSON Schema of a task's call, for P3-3's MLX adapter.
public func schemaJSON(for task: some ModelTask) throws -> String {
    switch task {
    case let task as SectionLabelTask:
        try WireSchemas.json(WireSchemas.labels(blockCount: task.blocks.count, boundedIndex: true))
    case let task as AmbiguousLineTask:
        try WireSchemas.json(WireSchemas.lineClasses(lineCount: task.lines.count))
    case let task as SetRequestTask:
        try WireSchemas.json(WireSchemas.setRequest(libraryTags: task.libraryTags))
    default:
        try WireSchemas.json(WireSchemas.metadata)
    }
}
