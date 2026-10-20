import Foundation
import GenerableTasks
import ModelPort
import Synchronization

/// The local MLX model behind the port (spec 4, R63, R94; P3-A section 5): the installed
/// curated (or, in Personal, custom) model, grammar-constrained greedy JSON with no free
/// whitespace, one retry with a whitespace bias on `incompleteOutput`, loaded per paste or set
/// request and unloaded right after, never during a show. Every call runs at
/// `.userInitiated`, holds a `ProcessInfo` activity and races a timeout that maps to
/// `ProviderError.timeout` (P3-A saw one call stall for 1,054 s under swap).
public struct MLXProvider: LanguageModelProvider, ModelTaskHandler {
    public struct Configuration: Sendable {
        /// The longest one call may take, loading included (a warm labels call takes about
        /// 3-8 s on an M1 Pro; low-memory Macs are slower).
        public var timeout: Duration
        /// How long the model stays loaded after a call, for the next call of the same paste.
        public var linger: Duration

        public init(timeout: Duration = .seconds(90), linger: Duration = .seconds(2)) {
            self.timeout = timeout
            self.linger = linger
        }
    }

    public typealias Flag = @Sendable () -> Bool
    public typealias Sleep = @Sendable (Duration) async throws -> Void

    private let resolver: any ModelFolderResolver
    private let residency: ModelResidency
    private let configuration: Configuration
    private let isShowRunning: Flag
    private let sleep: Sleep
    private let current: CurrentModel

    /// - Parameters:
    ///   - defaultModel: the model `id` names before an installed one is found.
    ///   - isShowRunning: true while a show runs (no model loads, R65).
    public init(
        engine: any GuidedEngine,
        resolver: any ModelFolderResolver,
        defaultModel: ModelRef,
        configuration: Configuration = Configuration(),
        isShowRunning: @escaping Flag = { false },
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
    ) {
        self.resolver = resolver
        self.configuration = configuration
        self.isShowRunning = isShowRunning
        self.sleep = sleep
        residency = ModelResidency(engine: engine, linger: configuration.linger, sleep: sleep)
        current = CurrentModel(defaultModel)
    }

    public var id: ProviderID {
        .mlx(current.value)
    }

    public func availability() async -> ProviderAvailability {
        if isShowRunning() {
            return .unavailable(.duringShow)
        }
        guard let active = await resolver.activeModel() else {
            return .unavailable(.notInstalled)
        }
        current.value = active.manifest.ref
        return .available
    }

    /// Unloads the model now if no call runs (a show starts).
    public func unloadIfIdle() async {
        await residency.unloadIfIdle()
    }

    /// Whether a model is loaded right now (tests and diagnostics).
    public var isModelLoaded: Bool {
        get async { await residency.isLoaded }
    }

    /// How many times a model was loaded (tests).
    var loadCount: Int {
        get async { await residency.loadCount }
    }

    // MARK: - Tasks

    public func sectionLabels(
        _ task: SectionLabelTask,
        context _: CallContext,
    ) async throws(ProviderError) -> ModelResult<SectionLabelOutput> {
        let count = task.blocks.count
        let (json, metrics) = try await generate(
            task,
            instructions: ModelPrompts.labelInstructions,
            prompt: ModelPrompts.labelPrompt(task),
            maxTokens: 60 + 16 * count,
        )
        let wire = try WireMapping.decode(BlockLabelsWire.self, json: json)
        let output = try WireMapping.labels(chunks: [(0 ..< count, wire)], task: task)
        return ModelResult(output: output, metrics: metrics)
    }

    public func metadata(
        _ task: MetadataTask,
        context _: CallContext,
    ) async throws(ProviderError) -> ModelResult<MetadataOutput> {
        let (json, metrics) = try await generate(
            task,
            instructions: ModelPrompts.metadataInstructions,
            prompt: ModelPrompts.metadataPrompt(task),
            maxTokens: 100,
        )
        let wire = try WireMapping.decode(MetadataWire.self, json: json)
        return ModelResult(output: WireMapping.metadata(wire), metrics: metrics)
    }

    public func ambiguousLines(
        _ task: AmbiguousLineTask,
        context _: CallContext,
    ) async throws(ProviderError) -> ModelResult<AmbiguousLineOutput> {
        let (json, metrics) = try await generate(
            task,
            instructions: ModelPrompts.ambiguousLineInstructions,
            prompt: ModelPrompts.ambiguousLinePrompt(task),
            maxTokens: 40 + 14 * task.lines.count,
        )
        let wire = try WireMapping.decode(LineClassesWire.self, json: json)
        return try ModelResult(output: WireMapping.lineClasses(wire, task: task), metrics: metrics)
    }

    public func setRequest(
        _ task: SetRequestTask,
        context _: CallContext,
    ) async throws(ProviderError) -> ModelResult<SetRequestOutput> {
        let (json, metrics) = try await generate(
            task,
            instructions: ModelPrompts.setRequestInstructions,
            prompt: ModelPrompts.setRequestPrompt(task),
            maxTokens: 150,
        )
        let wire = try WireMapping.decode(SetRequestWire.self, json: json)
        return ModelResult(output: WireMapping.setRequest(wire, task: task), metrics: metrics)
    }

    // MARK: - Calls

    /// The system message: the instructions, the task's JSON Schema (P3-2's
    /// `schemaJSON(for:)`) and the compact-JSON rule the grammar enforces.
    static func system(instructions: String, schema: String) -> String {
        instructions + "\n\nReply with only a JSON object that matches this JSON schema:\n"
            + schema + "\nWrite compact JSON with no spaces or line breaks."
    }

    private func generate(
        _ task: some ModelTask,
        instructions: String,
        prompt: String,
        maxTokens: Int,
    ) async throws(ProviderError) -> (json: String, metrics: CallMetrics) {
        guard !isShowRunning() else { throw .other }
        guard let active = await resolver.activeModel() else { throw .notInstalled }
        current.value = active.manifest.ref
        let schema: String
        do {
            schema = try schemaJSON(for: task)
        } catch {
            throw .other
        }
        let request = GuidedRequest(
            system: Self.system(instructions: instructions, schema: schema),
            prompt: prompt,
            grammar: MLXGrammars.grammar(for: task),
            maxTokens: maxTokens,
        )
        let clock = ContinuousClock()
        let start = clock.now
        let (output, retries) = try await callWithTimeout(request, folder: active.folder)
        let metrics = CallMetrics(
            latency: clock.now - start,
            promptTokens: output.promptTokens,
            outputTokens: output.outputTokens,
            retries: retries,
        )
        return (output.text, metrics)
    }

    /// Runs the call on a detached `.userInitiated` task holding a `ProcessInfo` activity and
    /// races it against the timeout and the caller's cancellation. A call that loses keeps
    /// running until its next token, then stops and releases the model.
    private func callWithTimeout(
        _ request: GuidedRequest,
        folder: URL,
    ) async throws(ProviderError) -> (GuidedOutput, Int) {
        let stop = StopFlag()
        let gate = ResumeOnce<Result<(GuidedOutput, Int), ProviderError>>()
        let residency = residency
        let work = Task.detached(priority: .userInitiated) {
            let activity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiated,
                reason: "Segue is refining a paste with the local model",
            )
            defer { ProcessInfo.processInfo.endActivity(activity) }
            let result = await Self.run(request, folder: folder, residency: residency, stop: stop)
            gate.resume(with: result)
        }
        let timeout = configuration.timeout
        let sleep = sleep
        let timer = Task {
            do {
                try await sleep(timeout)
            } catch {
                return
            }
            stop.set()
            gate.resume(with: .failure(.timeout))
        }
        let result = await withTaskCancellationHandler {
            await gate.value()
        } onCancel: {
            stop.set()
            gate.resume(with: .failure(.other))
        }
        timer.cancel()
        _ = work
        return try result.get()
    }

    /// Acquire, generate (plus one whitespace-bias retry on `incompleteOutput`), release.
    private static func run(
        _ request: GuidedRequest,
        folder: URL,
        residency: ModelResidency,
        stop: StopFlag,
    ) async -> Result<(GuidedOutput, Int), ProviderError> {
        let model: any LoadedGuidedModel
        do throws(ProviderError) {
            model = try await residency.acquire(folder: folder)
        } catch {
            return .failure(error)
        }
        let result = await generate(request, on: model, stop: stop)
        await residency.release()
        return result
    }

    private static func generate(
        _ request: GuidedRequest,
        on model: any LoadedGuidedModel,
        stop: StopFlag,
    ) async -> Result<(GuidedOutput, Int), ProviderError> {
        let shouldStop: @Sendable () -> Bool = { stop.isSet }
        do throws(GuidedFailure) {
            return try await .success((model.generate(request, shouldStop: shouldStop), 0))
        } catch .incompleteOutput where !stop.isSet {
            var retry = request
            retry.whitespaceBias = true
            do throws(GuidedFailure) {
                return try await .success((model.generate(retry, shouldStop: shouldStop), 1))
            } catch {
                return .failure(providerError(error))
            }
        } catch {
            return .failure(providerError(error))
        }
    }

    static func providerError(_ failure: GuidedFailure) -> ProviderError {
        switch failure {
        case .incompleteOutput, .prematureEOS: .incompleteOutput
        case .stopped: .timeout
        case .grammar, .loadFailed, .other: .other
        }
    }
}

// MARK: - Small synchronisation helpers

/// The model the provider names in `ProviderID.mlx`.
private final class CurrentModel: Sendable {
    private let state: Mutex<ModelRef>

    init(_ model: ModelRef) {
        state = Mutex(model)
    }

    var value: ModelRef {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}

/// Set once to stop a generation at its next token.
final class StopFlag: Sendable {
    private let state = Mutex(false)

    var isSet: Bool {
        state.withLock { $0 }
    }

    func set() {
        state.withLock { $0 = true }
    }
}

/// A value delivered once, by whichever of several racers gets there first.
final class ResumeOnce<Value: Sendable>: Sendable {
    private let state = Mutex<(value: Value?, waiter: CheckedContinuation<Value, Never>?)>(
        (nil, nil),
    )

    func resume(with value: Value) {
        let waiter: CheckedContinuation<Value, Never>? = state.withLock { state in
            guard state.value == nil else { return nil }
            state.value = value
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume(returning: value)
    }

    func value() async -> Value {
        await withCheckedContinuation { continuation in
            let ready: Value? = state.withLock { state in
                if let value = state.value {
                    return value
                }
                state.waiter = continuation
                return nil
            }
            if let ready {
                continuation.resume(returning: ready)
            }
        }
    }
}
