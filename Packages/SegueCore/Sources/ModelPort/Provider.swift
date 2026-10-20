// Phase 3 AI provider port (docs/phases/3-ai-entry-and-assistant.md section 4, R77). The
// Foundation Models and MLX adapters live in `Packages/SegueAI`; everything here is pure.

/// A model a provider runs: the curated MLX model or a custom one (Personal only, R62).
public struct ModelRef: Sendable, Hashable, Codable, CustomStringConvertible {
    /// Hugging Face repo id (`mlx-community/Qwen3-4B-Instruct-2507-4bit`).
    public var repo: String
    /// The pinned commit revision.
    public var revision: String

    public init(repo: String, revision: String) {
        self.repo = repo
        self.revision = revision
    }

    public var description: String {
        "\(repo)@\(revision)"
    }
}

/// The kind of provider a routing order names (R63: curated MLX, then Foundation Models).
public enum ProviderKind: String, Sendable, Hashable, Codable, CaseIterable {
    case mlx
    case foundationModels = "fm"
}

/// Which provider answered (or was asked).
public enum ProviderID: Sendable, Hashable, Codable, CustomStringConvertible {
    case foundationModels
    case mlx(ModelRef)

    public var kind: ProviderKind {
        switch self {
        case .foundationModels: .foundationModels
        case .mlx: .mlx
        }
    }

    public var description: String {
        switch self {
        case .foundationModels: "fm"
        case let .mlx(model): "mlx(\(model))"
        }
    }
}

/// Why a provider cannot run right now.
public enum UnavailableCause: String, Sendable, Hashable, Codable, CaseIterable {
    // Foundation Models' `SystemLanguageModel.Availability.UnavailableReason` (R69).
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    /// A reason this build does not know (a future `UnavailableReason`).
    case unknown
    /// No local model is downloaded (MLX), or the provider is not built into this app.
    case notInstalled
    /// A show is running: no model loads during a show (R65, R95).
    case duringShow
}

/// Whether a provider can take a call.
public enum ProviderAvailability: Sendable, Hashable {
    case available
    case unavailable(UnavailableCause)
}

/// Typed reasons a call failed (no strings). The router falls through to the next provider
/// on every one of them; `rateLimited` and `busy` get one spaced retry first (spec 4.1).
public enum ProviderError: String, Error, Sendable, Hashable, Codable, CaseIterable {
    /// FM's language check rejected the text (deterministic, about 3 ms, spike 2.2).
    case unsupportedLanguage
    case guardrail
    case refusal
    case decodingFailure
    /// Guided generation stopped before the output was complete (MLX).
    case incompleteOutput
    /// The input does not fit the context window (and chunking is not allowed).
    case contextOverflow
    case rateLimited
    /// The provider is serving another request.
    case busy
    case timeout
    case notInstalled
    case other
}

/// What one call cost. Used only for analytics buckets (R74): no local metrics store.
public struct CallMetrics: Sendable, Hashable, Codable {
    public var latency: Duration
    /// 0 when the provider cannot count.
    public var promptTokens: Int
    public var outputTokens: Int
    /// Spaced retries the router (or the adapter) made before this answer.
    public var retries: Int

    public init(
        latency: Duration = .zero,
        promptTokens: Int = 0,
        outputTokens: Int = 0,
        retries: Int = 0,
    ) {
        self.latency = latency
        self.promptTokens = promptTokens
        self.outputTokens = outputTokens
        self.retries = retries
    }

    /// Several calls (chunks) as one.
    public static func += (lhs: inout Self, rhs: Self) {
        lhs = lhs + rhs
    }

    /// Several calls (chunks) as one.
    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            latency: lhs.latency + rhs.latency,
            promptTokens: lhs.promptTokens + rhs.promptTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            retries: lhs.retries + rhs.retries,
        )
    }
}

/// A provider's answer.
public struct ModelResult<Output: Sendable>: Sendable {
    public var output: Output
    public var metrics: CallMetrics

    public init(output: Output, metrics: CallMetrics) {
        self.output = output
        self.metrics = metrics
    }
}

extension ModelResult: Equatable where Output: Equatable {}

/// What the router tells a provider about the call.
public struct CallContext: Sendable, Hashable {
    /// No MLX provider comes after this one in the task's order, so an over-budget sheet may
    /// be chunked (chunking costs about 18 points, spike 2.1 F); otherwise the provider throws
    /// `contextOverflow` and the router moves on to MLX.
    public var allowsChunking: Bool

    public init(allowsChunking: Bool) {
        self.allowsChunking = allowsChunking
    }
}

/// One AI provider (Foundation Models, MLX, or a scripted replay in tests).
public protocol LanguageModelProvider: Sendable {
    var id: ProviderID { get }
    func availability() async -> ProviderAvailability
    func run<T: ModelTask>(
        _ task: T,
        context: CallContext,
    ) async throws(ProviderError) -> ModelResult<T.Output>
}

/// The per-task entry points a real adapter implements; `ModelTask.dispatch` picks one, so an
/// adapter never casts a generic task.
public protocol ModelTaskHandler: Sendable {
    func sectionLabels(
        _ task: SectionLabelTask,
        context: CallContext,
    ) async throws(ProviderError) -> ModelResult<SectionLabelOutput>
    func metadata(
        _ task: MetadataTask,
        context: CallContext,
    ) async throws(ProviderError) -> ModelResult<MetadataOutput>
    func ambiguousLines(
        _ task: AmbiguousLineTask,
        context: CallContext,
    ) async throws(ProviderError) -> ModelResult<AmbiguousLineOutput>
    func setRequest(
        _ task: SetRequestTask,
        context: CallContext,
    ) async throws(ProviderError) -> ModelResult<SetRequestOutput>
}

public extension LanguageModelProvider where Self: ModelTaskHandler {
    func run<T: ModelTask>(
        _ task: T,
        context: CallContext,
    ) async throws(ProviderError) -> ModelResult<T.Output> {
        try await task.dispatch(to: self, context: context)
    }
}
