import Foundation
import Ingest

/// The four model tasks (spec section 4). Outputs have no optionals: `""` and empty sentinels,
/// normalised in code.
public enum ModelTaskKind: String, Sendable, Hashable, Codable, CaseIterable,
    CodingKeyRepresentable
{
    case sectionLabels
    case metadata
    case ambiguousLines
    case setRequest
}

/// A typed model call. The input is the task value itself; recordings are keyed by
/// `recordingKey` (task kind + a stable hash of the input).
public protocol ModelTask: Sendable, Hashable, Codable {
    associatedtype Output: Sendable, Hashable, Codable
    static var kind: ModelTaskKind { get }
    func dispatch(
        to handler: some ModelTaskHandler,
        context: CallContext,
    ) async throws(ProviderError) -> ModelResult<Output>
}

public extension ModelTask {
    /// FNV-1a 64 of the input's canonical JSON (sorted keys): the same input always gives
    /// the same hash, on every machine.
    var inputHash: String {
        StableHash.hex(of: self)
    }

    /// `<kind>-<inputHash>`, the key `ScriptedProvider` replays by.
    var recordingKey: String {
        "\(Self.kind.rawValue)-\(inputHash)"
    }
}

/// The closed vocabularies the wire types constrain to (spike `Vocab`).
public enum ModelVocabulary {
    /// Section labels, in the order the prompts list them.
    public static let labels: [SectionLabel] = SectionLabel.allCases
    public static let roots = [
        "C", "C#", "Db", "D", "Eb", "E", "F", "F#", "Gb", "G", "Ab", "A", "Bb", "B",
    ]
    /// Every major and minor key name the metadata task may answer.
    public static let keys: [String] = roots + roots.map { $0 + "m" }
    /// The metadata wire value for "no idea" (normalised to `""`).
    public static let unknownKey = "unknown"
}

// MARK: - Section labels

/// Label every block of a sheet (spike variant E: exact count, hints in the prompt). Only the
/// labels of unheaded blocks are used; headed labels always come from code.
public struct SectionLabelTask: ModelTask {
    public struct Block: Sendable, Hashable, Codable {
        /// 0-based block index (`IngestBlock.index`).
        public var index: Int
        /// The block's normalized lines as pasted (header lines included).
        public var lines: [String]
        /// Deterministic hints in the spike's wording (`BlockHints.summary`), or `""`.
        public var hint: String

        public init(index: Int, lines: [String], hint: String) {
            self.index = index
            self.lines = lines
            self.hint = hint
        }
    }

    /// Every block of the sheet, in order.
    public var blocks: [Block]

    public init(blocks: [Block]) {
        self.blocks = blocks
    }

    public static let kind = ModelTaskKind.sectionLabels

    public func dispatch(
        to handler: some ModelTaskHandler,
        context: CallContext,
    ) async throws(ProviderError) -> ModelResult<SectionLabelOutput> {
        try await handler.sectionLabels(self, context: context)
    }
}

/// One label per block of the task, in block order (exact count).
public struct SectionLabelOutput: Sendable, Hashable, Codable {
    public var labels: [SectionLabel]

    public init(labels: [SectionLabel]) {
        self.labels = labels
    }
}

// MARK: - Metadata

/// Title, artist and key from the top/bottom chord-free blocks plus the chord list (spike 5.3:
/// the call is skipped when there is no top or bottom candidate).
public struct MetadataTask: ModelTask {
    public var topLines: [String]
    public var bottomLines: [String]
    /// Every chord in song order.
    public var chords: [String]

    public init(topLines: [String], bottomLines: [String], chords: [String]) {
        self.topLines = topLines
        self.bottomLines = bottomLines
        self.chords = chords
    }

    public static let kind = ModelTaskKind.metadata

    public func dispatch(
        to handler: some ModelTaskHandler,
        context: CallContext,
    ) async throws(ProviderError) -> ModelResult<MetadataOutput> {
        try await handler.metadata(self, context: context)
    }
}

/// `""` means "not named" for every field. No artist: artists come from code only (R174).
public struct MetadataOutput: Sendable, Hashable, Codable {
    public var title: String
    /// A name from `ModelVocabulary.keys`, or `""`.
    public var key: String

    public init(title: String, key: String) {
        self.title = title
        self.key = key
    }

    /// Spike 5.3 post-processing: trimmed, "Unknown"/"none"/"n/a" -> empty, a key outside
    /// the vocabulary -> empty.
    public func normalized() -> Self {
        func clean(_ text: String) -> String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let placeholders: Set = ["unknown", "none", "n/a", "na", "null", "-"]
            return placeholders.contains(trimmed.lowercased()) ? "" : trimmed
        }
        let key = ModelVocabulary.keys.contains(key) ? key : ""
        return Self(title: clean(title), key: key)
    }
}

// MARK: - Ambiguous lines

/// Classify lines code could not place, inside song sections (tuning notes, strumming
/// patterns, stray chord text). The classes never make a line a lyric: lyrics are code's.
public struct AmbiguousLineTask: ModelTask {
    public struct Line: Sendable, Hashable, Codable {
        /// `IngestLine.index`.
        public var index: Int
        public var text: String
        /// The lines around it in its block (context only).
        public var context: [String]

        public init(index: Int, text: String, context: [String]) {
            self.index = index
            self.text = text
            self.context = context
        }
    }

    public var lines: [Line]

    public init(lines: [Line]) {
        self.lines = lines
    }

    public static let kind = ModelTaskKind.ambiguousLines

    public func dispatch(
        to handler: some ModelTaskHandler,
        context: CallContext,
    ) async throws(ProviderError) -> ModelResult<AmbiguousLineOutput> {
        try await handler.ambiguousLines(self, context: context)
    }
}

/// What an unknown line is.
public enum AmbiguousLineClass: String, Sendable, Hashable, Codable, CaseIterable {
    /// A performance note (tuning, strumming, "palm mute"): stays a `{comment}`.
    case note
    /// Chord symbols that code could not parse as a chord line.
    case chords
    /// Guitar tab notation.
    case tab

    /// The `LineClass` the converter renders it as.
    public var lineClass: LineClass {
        switch self {
        case .note: .unknown
        case .chords: .chordLine
        case .tab: .tab
        }
    }
}

/// One class per line of the task, in order (exact count).
public struct AmbiguousLineOutput: Sendable, Hashable, Codable {
    public var classes: [AmbiguousLineClass]

    public init(classes: [AmbiguousLineClass]) {
        self.classes = classes
    }
}

// MARK: - Set requests

/// Map the words of a set request the lexicon left unmapped onto the library's actual tags and
/// the fixed chip vocabulary (R65, R92). The output only ever becomes suggested chips.
public struct SetRequestTask: ModelTask {
    /// The unmapped words, as typed.
    public var words: String
    /// The tags in use in the library (the only tags the model may answer).
    public var libraryTags: [String]

    public init(words: String, libraryTags: [String]) {
        self.words = words
        self.libraryTags = libraryTags
    }

    public static let kind = ModelTaskKind.setRequest

    public func dispatch(
        to handler: some ModelTaskHandler,
        context: CallContext,
    ) async throws(ProviderError) -> ModelResult<SetRequestOutput> {
        try await handler.setRequest(self, context: context)
    }
}

/// The proficiency floor a request asks for ("know well" -> ready, "know cold" -> pro).
public enum ProficiencyFloor: String, Sendable, Hashable, Codable, CaseIterable {
    case any
    case ready
    case pro
}

/// Suggested chips. Tags are always from `SetRequestTask.libraryTags`; `""` = none asked.
public struct SetRequestOutput: Sendable, Hashable, Codable {
    public var includeTags: [String]
    public var excludeTags: [String]
    public var minProficiency: ProficiencyFloor
    /// A tag for the opening song, only when the request asks (R92).
    public var openerTag: String
    /// A tag for the closing song, only when the request asks (R92).
    public var closerTag: String

    public init(
        includeTags: [String],
        excludeTags: [String],
        minProficiency: ProficiencyFloor,
        openerTag: String,
        closerTag: String,
    ) {
        self.includeTags = includeTags
        self.excludeTags = excludeTags
        self.minProficiency = minProficiency
        self.openerTag = openerTag
        self.closerTag = closerTag
    }

    /// Drops tags the library does not have and duplicates; a tag both included and
    /// excluded is dropped from both.
    public func normalized(libraryTags: [String]) -> Self {
        let known = Set(libraryTags)
        func unique(_ tags: [String]) -> [String] {
            var seen: Set<String> = []
            return tags.filter { known.contains($0) && seen.insert($0).inserted }
        }
        let include = unique(includeTags)
        let exclude = unique(excludeTags)
        let both = Set(include).intersection(exclude)
        return Self(
            includeTags: include.filter { !both.contains($0) },
            excludeTags: exclude.filter { !both.contains($0) },
            minProficiency: minProficiency,
            openerTag: known.contains(openerTag) ? openerTag : "",
            closerTag: known.contains(closerTag) ? closerTag : "",
        )
    }
}
