import Foundation
import FoundationModels
import GenerableTasks
import Ingest
import ModelPort

/// Apple Foundation Models behind the port (spec section 4, R62): `SystemLanguageModel.default`,
/// a fresh session per call (never two calls on one session), greedy sampling, the spike's final
/// prompts, a runtime token budget, chunking only when the router allows it, and every
/// `GenerationError` mapped to a typed `ProviderError`.
public struct FoundationModelsProvider: LanguageModelProvider, ModelTaskHandler {
    public let id = ProviderID.foundationModels
    /// The longest one call may take (FM measured 5-30 s, at worst 69 s, spike 2.4) before it
    /// becomes `.timeout` and the router moves on.
    private let timeout: Duration

    public init(timeout: Duration = .seconds(120)) {
        self.timeout = timeout
    }

    private var model: SystemLanguageModel {
        .default
    }

    public func availability() async -> ProviderAvailability {
        FoundationModelsMapping.availability(model.availability)
    }

    // MARK: - Tasks

    public func sectionLabels(
        _ task: SectionLabelTask,
        context: CallContext,
    ) async throws(ProviderError) -> ModelResult<SectionLabelOutput> {
        let count = task.blocks.count
        let responseTokens = ModelPrompts.labelResponseTokens(blocks: count)
        let fullSchema = try schema { try WireSchemas.labels(blockCount: count) }
        let budget = await LabelChunking.budget(
            contextSize: model.contextSize,
            instructionTokens: tokens(instructions: ModelPrompts.labelInstructions),
            schemaTokens: tokens(schema: fullSchema),
            responseTokens: responseTokens,
        )
        let ranges = await LabelChunking.plan(blockCount: count, budget: budget) { range in
            await tokens(prompt: prompt(task, range))
        }
        if ranges.count > 1, !context.allowsChunking {
            throw .contextOverflow
        }
        var chunks: [(range: Range<Int>, wire: BlockLabelsWire)] = []
        var metrics = CallMetrics()
        for range in ranges {
            let schema = try schema { try WireSchemas.labels(blockCount: range.count) }
            let (json, callMetrics) = try await generate(
                instructions: ranges.count == 1
                    ? ModelPrompts.labelInstructions : ModelPrompts.chunkInstructions,
                prompt: prompt(task, range),
                schema: schema,
                responseTokens: ModelPrompts.labelResponseTokens(blocks: range.count),
            )
            try chunks.append((range, WireMapping.decode(BlockLabelsWire.self, json: json)))
            metrics += callMetrics
        }
        return try ModelResult(
            output: WireMapping.labels(chunks: chunks, task: task),
            metrics: metrics,
        )
    }

    public func metadata(
        _ task: MetadataTask,
        context _: CallContext,
    ) async throws(ProviderError) -> ModelResult<MetadataOutput> {
        let (json, metrics) = try await generate(
            instructions: ModelPrompts.metadataInstructions,
            prompt: ModelPrompts.metadataPrompt(task),
            schema: WireSchemas.metadata,
            responseTokens: ModelPrompts.metadataResponseTokens,
        )
        let wire = try WireMapping.decode(MetadataWire.self, json: json)
        return ModelResult(output: WireMapping.metadata(wire), metrics: metrics)
    }

    public func ambiguousLines(
        _ task: AmbiguousLineTask,
        context _: CallContext,
    ) async throws(ProviderError) -> ModelResult<AmbiguousLineOutput> {
        let schema = try schema { try WireSchemas.lineClasses(lineCount: task.lines.count) }
        let (json, metrics) = try await generate(
            instructions: ModelPrompts.ambiguousLineInstructions,
            prompt: ModelPrompts.ambiguousLinePrompt(task),
            schema: schema,
            responseTokens: ModelPrompts.ambiguousLineResponseTokens(lines: task.lines.count),
        )
        let wire = try WireMapping.decode(LineClassesWire.self, json: json)
        return try ModelResult(output: WireMapping.lineClasses(wire, task: task), metrics: metrics)
    }

    public func setRequest(
        _ task: SetRequestTask,
        context _: CallContext,
    ) async throws(ProviderError) -> ModelResult<SetRequestOutput> {
        let schema = try schema { try WireSchemas.setRequest(libraryTags: task.libraryTags) }
        let (json, metrics) = try await generate(
            instructions: ModelPrompts.setRequestInstructions,
            prompt: ModelPrompts.setRequestPrompt(task),
            schema: schema,
            responseTokens: ModelPrompts.setRequestResponseTokens,
        )
        let wire = try WireMapping.decode(SetRequestWire.self, json: json)
        return ModelResult(output: WireMapping.setRequest(wire, task: task), metrics: metrics)
    }

    // MARK: - Calls

    private func prompt(_ task: SectionLabelTask, _ range: Range<Int>) -> String {
        range.count == task.blocks.count
            ? ModelPrompts.labelPrompt(task)
            : ModelPrompts.labelPrompt(task, range: range)
    }

    private func schema(
        _ build: () throws -> GenerationSchema,
    ) throws(ProviderError) -> GenerationSchema {
        do {
            return try build()
        } catch {
            throw .other
        }
    }

    /// One greedy call on a fresh session, raced against the timeout.
    private func generate(
        instructions: String,
        prompt: String,
        schema: GenerationSchema,
        responseTokens: Int,
    ) async throws(ProviderError) -> (json: String, metrics: CallMetrics) {
        let model = model
        let timeout = timeout
        let clock = ContinuousClock()
        let start = clock.now
        let promptTokens = await tokens(prompt: prompt)
        let json: String
        do {
            json = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    let session = LanguageModelSession(
                        model: model,
                        instructions: Instructions(instructions),
                    )
                    let response = try await session.respond(
                        to: prompt,
                        schema: schema,
                        includeSchemaInPrompt: true,
                        options: GenerationOptions(
                            samplingMode: .greedy,
                            maximumResponseTokens: responseTokens,
                        ),
                    )
                    return response.content.jsonString
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw ProviderError.timeout
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else { throw ProviderError.other }
                return first
            }
        } catch {
            throw FoundationModelsMapping.providerError(error)
        }
        let metrics = await CallMetrics(
            latency: clock.now - start,
            promptTokens: promptTokens,
            outputTokens: tokens(prompt: json),
        )
        return (json, metrics)
    }

    // MARK: - Token counts (runtime values; chars/3 before macOS 26.4)

    private func tokens(prompt text: String) async -> Int {
        if #available(macOS 26.4, *), let count = try? await model.tokenCount(for: Prompt(text)) {
            return count
        }
        return LabelChunking.estimatedTokens(text)
    }

    private func tokens(instructions text: String) async -> Int {
        if #available(macOS 26.4, *),
           let count = try? await model.tokenCount(for: Instructions(text))
        {
            return count
        }
        return LabelChunking.estimatedTokens(text)
    }

    private func tokens(schema: GenerationSchema) async -> Int {
        if #available(macOS 26.4, *), let count = try? await model.tokenCount(for: schema) {
            return count
        }
        return LabelChunking.estimatedTokens((try? WireSchemas.json(schema)) ?? "")
    }
}
