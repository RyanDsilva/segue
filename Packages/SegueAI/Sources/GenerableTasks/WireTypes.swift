import Foundation
import FoundationModels
import Ingest
import ModelPort

// One @Generable wire type per task (spec section 4): no optionals (FM never fills them under
// greedy decoding, spike 2.1 A), `.anyOf` enums for labels, keys and classes, an exact count
// where the count is known (`WireSchemas`), `.maximumCount` on every other array. The MLX
// adapter (P3-3) takes its JSON Schema from the same types through `WireSchemas.json`.

/// The label vocabulary as wire strings.
public enum WireVocabulary {
    public static let labels: [String] = ModelVocabulary.labels.map(\.rawValue)
    public static let keysOrUnknown: [String] = ModelVocabulary.keys + [ModelVocabulary.unknownKey]
    public static let lineClasses: [String] = AmbiguousLineClass.allCases.map(\.rawValue)
    public static let proficiency: [String] = ProficiencyFloor.allCases.map(\.rawValue)
}

@Generable
public struct BlockLabelWire: Codable, Sendable, Equatable {
    @Guide(description: "Block number as shown in the sheet")
    public var block: Int
    @Guide(description: "Section kind of this block", .anyOf(WireVocabulary.labels))
    public var label: String

    public init(block: Int, label: String) {
        self.block = block
        self.label = label
    }
}

/// `SectionLabelTask`'s answer. Sent with an exact-count schema (`WireSchemas.labels`).
@Generable
public struct BlockLabelsWire: Codable, Sendable, Equatable {
    @Guide(description: "Exactly one entry per block, in block order")
    public var blocks: [BlockLabelWire]

    public init(blocks: [BlockLabelWire]) {
        self.blocks = blocks
    }
}

/// `MetadataTask`'s answer (spike `SongMetadata`).
@Generable
public struct MetadataWire: Codable, Sendable, Equatable {
    @Guide(description: "Song title exactly as written, or an empty string if no title is written")
    public var title: String
    @Guide(
        // swiftlint:disable:next line_length
        description: "Artist, band or singer exactly as written, or an empty string if none is written",
    )
    public var artist: String
    @Guide(
        // swiftlint:disable:next line_length
        description: "Key of the song: the stated key (Key:, Scale:) if any, else your best guess from the chords, or unknown if there are no chords",
        .anyOf(WireVocabulary.keysOrUnknown),
    )
    public var key: String

    public init(title: String, artist: String, key: String) {
        self.title = title
        self.artist = artist
        self.key = key
    }
}

@Generable
public struct LineClassWire: Codable, Sendable, Equatable {
    @Guide(description: "Line number as shown")
    public var line: Int
    @Guide(description: "What the line is", .anyOf(WireVocabulary.lineClasses))
    public var kind: String

    public init(line: Int, kind: String) {
        self.line = line
        self.kind = kind
    }
}

/// `AmbiguousLineTask`'s answer. Sent with an exact-count schema (`WireSchemas.lineClasses`).
@Generable
public struct LineClassesWire: Codable, Sendable, Equatable {
    @Guide(description: "Exactly one entry per line, in line order")
    public var lines: [LineClassWire]

    public init(lines: [LineClassWire]) {
        self.lines = lines
    }
}

/// `SetRequestTask`'s answer (spike v3 without energy, R71). The tags are constrained to the
/// library's own tags at run time (`WireSchemas.setRequest`).
@Generable
public struct SetRequestWire: Codable, Sendable, Equatable {
    @Guide(description: "Minimum proficiency", .anyOf(WireVocabulary.proficiency))
    public var minProficiency: String
    @Guide(description: "Tags named in the request", .maximumCount(4))
    public var includeTags: [String]
    @Guide(description: "Tags the request excludes", .maximumCount(4))
    public var excludeTags: [String]
    @Guide(description: "Tag for the opening song, or an empty string")
    public var openerTag: String
    @Guide(description: "Tag for the closing song, or an empty string")
    public var closerTag: String

    public init(
        minProficiency: String,
        includeTags: [String],
        excludeTags: [String],
        openerTag: String,
        closerTag: String,
    ) {
        self.minProficiency = minProficiency
        self.includeTags = includeTags
        self.excludeTags = excludeTags
        self.openerTag = openerTag
        self.closerTag = closerTag
    }
}
