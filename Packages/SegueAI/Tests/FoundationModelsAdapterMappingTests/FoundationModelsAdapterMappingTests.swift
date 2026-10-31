import Foundation
import FoundationModels
import FoundationModelsAdapter
import GenerableTasks
import Ingest
import ModelPort
import Testing

/// Pure mapping only: FM errors and availability to the port's typed values, wire answers to
/// Core outputs, and the schemas (never a real model call).
struct FoundationModelsAdapterMappingTests {
    typealias GenerationError = LanguageModelSession.GenerationError
    static let context = GenerationError.Context(debugDescription: "test")

    @Test(arguments: [
        (GenerationError.exceededContextWindowSize(context), ProviderError.contextOverflow),
        (.assetsUnavailable(context), .notInstalled),
        (.guardrailViolation(context), .guardrail),
        (.unsupportedGuide(context), .other),
        (.unsupportedLanguageOrLocale(context), .unsupportedLanguage),
        (.decodingFailure(context), .decodingFailure),
        (.rateLimited(context), .rateLimited),
        (.concurrentRequests(context), .busy),
    ])
    func `every generation error maps to a typed reason`(
        error: GenerationError,
        expected: ProviderError,
    ) {
        #expect(FoundationModelsMapping.providerError(error) == expected)
        #expect(FoundationModelsMapping.providerError(error as any Error) == expected)
    }

    @Test
    func `other errors map to other, provider errors pass through`() {
        #expect(FoundationModelsMapping.providerError(CancellationError()) == .other)
        #expect(FoundationModelsMapping.providerError(ProviderError.timeout) == .timeout)
    }

    @Test
    func `unavailable reasons map to the R69 causes`() {
        typealias Reason = SystemLanguageModel.Availability.UnavailableReason
        #expect(FoundationModelsMapping.cause(Reason.deviceNotEligible) == .deviceNotEligible)
        #expect(FoundationModelsMapping.cause(Reason.appleIntelligenceNotEnabled)
            == .appleIntelligenceNotEnabled)
        #expect(FoundationModelsMapping.cause(Reason.modelNotReady) == .modelNotReady)
        #expect(FoundationModelsMapping.availability(.available) == .available)
        #expect(FoundationModelsMapping.availability(.unavailable(.modelNotReady))
            == .unavailable(.modelNotReady))
    }

    // MARK: - Wire answers

    static let task = SectionLabelTask(blocks: (0 ..< 3).map {
        .init(index: $0, lines: ["line \($0)"], hint: "")
    })

    @Test
    func `labels map by block number, else by position`() throws {
        let shuffled = BlockLabelsWire(blocks: [
            .init(block: 2, label: "chorus"), .init(block: 0, label: "other"),
            .init(block: 1, label: "verse"),
        ])
        #expect(try WireMapping.labels(shuffled, blocks: [0, 1, 2]) == [.other, .verse, .chorus])
        let renumbered = BlockLabelsWire(blocks: [
            .init(block: 1, label: "intro"), .init(block: 2, label: "verse"),
            .init(block: 3, label: "chorus"),
        ])
        #expect(try WireMapping.labels(renumbered, blocks: [0, 1, 2]) == [.intro, .verse, .chorus])
    }

    @Test
    func `a wrong count or an unknown label is a decoding failure`() {
        let short = BlockLabelsWire(blocks: [.init(block: 0, label: "verse")])
        #expect(throws: ProviderError.decodingFailure) {
            try WireMapping.labels(short, blocks: [0, 1])
        }
        let unknown = BlockLabelsWire(blocks: [.init(block: 0, label: "hook")])
        #expect(throws: ProviderError.decodingFailure) {
            try WireMapping.labels(unknown, blocks: [0])
        }
        #expect(throws: ProviderError.decodingFailure) {
            try WireMapping.decode(BlockLabelsWire.self, json: "{\"blocks\": 3")
        }
    }

    @Test
    func `chunk answers join in block order`() throws {
        let first = BlockLabelsWire(blocks: [
            .init(block: 0, label: "intro"),
            .init(block: 1, label: "verse"),
        ])
        let second = BlockLabelsWire(blocks: [.init(block: 2, label: "chorus")])
        let output = try WireMapping.labels(
            chunks: [(0 ..< 2, first), (2 ..< 3, second)],
            task: Self.task,
        )
        #expect(output.labels == [.intro, .verse, .chorus])
    }

    @Test
    func `metadata post-processing`() {
        #expect(WireMapping.metadata(MetadataWire(title: "Unknown", key: "unknown"))
            == MetadataOutput(title: "", key: ""))
        #expect(WireMapping.metadata(MetadataWire(title: "Safar", key: "Am"))
            == MetadataOutput(title: "Safar", key: "Am"))
    }

    @Test
    func `line classes and set requests map to the Core outputs`() throws {
        let lines = AmbiguousLineTask(lines: [
            .init(index: 4, text: "Tuning: DADGAD", context: []),
            .init(index: 9, text: "e|--0--|", context: []),
        ])
        let wire = LineClassesWire(lines: [
            .init(line: 0, kind: "note"),
            .init(line: 1, kind: "tab"),
        ])
        #expect(try WireMapping.lineClasses(wire, task: lines).classes == [.note, .tab])

        let request = SetRequestTask(words: "upbeat stuff", libraryTags: ["upbeat", "ballad"])
        let answer = WireMapping.setRequest(SetRequestWire(
            minProficiency: "ready",
            includeTags: ["upbeat", "rock"],
            excludeTags: [],
            openerTag: "",
            closerTag: "ballad",
        ), task: request)
        #expect(answer.includeTags == ["upbeat"])
        #expect(answer.minProficiency == .ready && answer.closerTag == "ballad")
    }

    // MARK: - Schemas (one source for FM and MLX)

    @Test
    func `label schemas pin the count and, for MLX, bound the block number`() throws {
        let json = try schemaJSON(for: Self.task)
        #expect(json.contains("\"minItems\":3") && json.contains("\"maxItems\":3"))
        #expect(json.contains("\"maximum\":2"))
        #expect(json.contains("\"prechorus\""))
        let plain = try WireSchemas.json(WireSchemas.labels(blockCount: 3))
        #expect(plain.contains("\"minItems\":3"))
    }

    /// The MLX system prompt carries this schema as text: the label vocabulary appears once,
    /// as an inline string enum (the spike's form). A named `anyOf` schema printed it twice as
    /// one-value enums, about 140 more prompt tokens, and cost Qwen3-4B about 1.5 points of
    /// label accuracy on Ryan's pastes.
    @Test
    func `the MLX label schema lists the vocabulary once, inline`() throws {
        let json = try schemaJSON(for: Self.task)
        let vocabulary = WireVocabulary.labels.map { "\"\($0)\"" }.joined(separator: ",")
        #expect(json.contains("\"enum\":[\(vocabulary)],\"type\":\"string\""))
        #expect(json.components(separatedBy: "\"prechorus\"").count == 2)
        #expect(!json.contains("anyOf"))
    }

    @Test
    func `set request schemas offer only the library's tags`() throws {
        let json = try schemaJSON(for: SetRequestTask(
            words: "x",
            libraryTags: ["upbeat", "ballad"],
        ))
        #expect(json.contains("\"upbeat\"") && json.contains("\"ballad\""))
        #expect(!json.contains("\"crowd pleaser\""))
        #expect(json.contains("\"maxItems\":4"))
        _ = try WireSchemas.setRequest(libraryTags: [])
    }
}
