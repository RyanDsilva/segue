import Foundation
import ModelPort
import ModelStore

// The seam between the MLX provider's logic (this target, MLX-free and unit-tested) and the
// MLX binding (`MLXEngine`, built only by xcodebuild because SwiftPM's command line cannot
// build MLX's Metal library, P3-A section 5.7).

/// One grammar-constrained, greedy generation.
public struct GuidedRequest: Sendable, Hashable {
    /// The system message: task instructions, the JSON Schema and the compact-JSON rule.
    public var system: String
    /// The user message.
    public var prompt: String
    /// An XGrammar EBNF grammar with no free whitespace (`MLXGrammars`).
    public var grammar: String
    public var maxTokens: Int
    /// The retry after `incompleteOutput`: whitespace-only tokens get a negative bias.
    public var whitespaceBias: Bool

    public init(
        system: String,
        prompt: String,
        grammar: String,
        maxTokens: Int,
        whitespaceBias: Bool = false,
    ) {
        self.system = system
        self.prompt = prompt
        self.grammar = grammar
        self.maxTokens = maxTokens
        self.whitespaceBias = whitespaceBias
    }
}

/// What a generation produced.
public struct GuidedOutput: Sendable, Hashable {
    /// The JSON text.
    public var text: String
    public var promptTokens: Int
    public var outputTokens: Int

    public init(text: String, promptTokens: Int, outputTokens: Int) {
        self.text = text
        self.promptTokens = promptTokens
        self.outputTokens = outputTokens
    }
}

/// Why an engine call failed (MLX's own errors, mapped by `MLXEngine`).
public enum GuidedFailure: Error, Sendable, Hashable {
    /// `maxTokens` ran out before the grammar accepted (the whitespace runaway, spike 3.2).
    case incompleteOutput
    /// EOS before the grammar accepted.
    case prematureEOS
    /// The model folder could not be loaded.
    case loadFailed
    /// The grammar did not compile.
    case grammar
    /// `shouldStop` asked the generation to stop (timeout or a cancelled caller).
    case stopped
    case other
}

/// Loads a model folder. `MLXEngine` is the real one; tests use a scripted fake.
public protocol GuidedEngine: Sendable {
    func load(folder: URL) async throws(GuidedFailure) -> any LoadedGuidedModel
}

/// A loaded model. Dropping the last reference after `unload()` frees its memory.
public protocol LoadedGuidedModel: Sendable {
    /// Runs one generation; `shouldStop` is polled between tokens.
    func generate(
        _ request: GuidedRequest,
        shouldStop: @escaping @Sendable () -> Bool,
    ) async throws(GuidedFailure) -> GuidedOutput

    /// Releases the weights and MLX's buffer cache.
    func unload() async
}

/// Where the installed model the provider runs lives. `ModelStore` answers it.
public protocol ModelFolderResolver: Sendable {
    func activeModel() async -> (manifest: LocalModelManifest, folder: URL)?
}

extension ModelStore: ModelFolderResolver {}
