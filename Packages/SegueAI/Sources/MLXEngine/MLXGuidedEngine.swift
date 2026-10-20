import Foundation
import MLX
import MLXAdapter
import MLXGuidedGeneration
import MLXLLM
import MLXLMCommon
import Tokenizers

/// The MLX binding of the provider's `GuidedEngine` seam (P3-A section 5): loads a model
/// folder with `LLMModelFactory.shared` directly (the `NSClassFromString` registry fails in a
/// static, dead-stripped app) and Segue's own tokenizer loader (no `MLXHuggingFace`, R66),
/// caps MLX's buffer cache at 512 MB, and runs `GuidedGenerationLoop` greedily under an
/// XGrammar EBNF grammar.
public struct MLXGuidedEngine: GuidedEngine {
    /// MLX's buffer cache cap (without one the footprint reached 11.6 GB, spike 3).
    public static let cacheLimitBytes = 512 << 20

    public init() {}

    public func load(folder: URL) async throws(GuidedFailure) -> any LoadedGuidedModel {
        Memory.cacheLimit = Self.cacheLimitBytes
        do {
            let container = try await LLMModelFactory.shared.loadContainer(
                from: folder,
                using: FolderTokenizerLoader(),
            )
            return MLXLoadedModel(container: container)
        } catch {
            throw .loadFailed
        }
    }
}

/// One loaded model; `unload()` drops the container and clears MLX's cache.
final class MLXLoadedModel: LoadedGuidedModel, @unchecked Sendable {
    private let lock = NSLock()
    private var container: ModelContainer?

    init(container: ModelContainer) {
        self.container = container
    }

    func generate(
        _ request: GuidedRequest,
        shouldStop: @escaping @Sendable () -> Bool,
    ) async throws(GuidedFailure) -> GuidedOutput {
        guard let container = lock.withLock({ container }) else { throw .loadFailed }
        do {
            return try await container.perform { context in
                try await Self.run(request, context: context, shouldStop: shouldStop)
            }
        } catch let failure as GuidedFailure {
            throw failure
        } catch GuidedGenerationError.incompleteOutput {
            throw .incompleteOutput
        } catch GuidedGenerationError.prematureEOS {
            throw .prematureEOS
        } catch is GrammarError {
            throw .grammar
        } catch {
            throw .other
        }
    }

    func unload() async {
        lock.withLock { container = nil }
        Memory.clearCache()
    }

    /// One guided call inside the container (the P3-A probe's code, with the EBNF grammar and
    /// the whitespace-bias retry of the final design).
    private static func run(
        _ request: GuidedRequest,
        context: ModelContext,
        shouldStop: @escaping @Sendable () -> Bool,
    ) async throws -> GuidedOutput {
        let tokenizer = context.tokenizer
        // Thinking off for hybrid models (Qwen3); instruct-only templates ignore it.
        let thinkingOff: [String: any Sendable] = ["enable_thinking": false]
        let input = try await context.processor.prepare(input: UserInput(
            chat: [.system(request.system), .user(request.prompt)],
            additionalContext: thinkingOff,
        ))
        let vocabulary = TokenizerVocabExtractor.extractForGrammar(from: tokenizer)
        let grammarTokenizer = try GrammarTokenizer(
            vocab: vocabulary.vocab,
            vocabType: vocabulary.vocabType,
            eosTokenId: Int32(tokenizer.eosTokenId ?? 0),
        )
        let constraint = try GrammarConstraint(
            tokenizer: grammarTokenizer,
            grammar: request.grammar,
            fastForward: true,
            hostTokenizer: tokenizer,
        )
        var whitespaceBias: MLXArray?
        var whitespaceIDs: Set<Int> = []
        if request.whitespaceBias {
            (whitespaceBias, whitespaceIDs) = WhitespaceTokenBias.compute(tokenizer: tokenizer)
        }
        var text = ""
        var stopped = false
        let generated = try GuidedGenerationLoop.run(
            input: input,
            context: context,
            constraint: constraint,
            maxTokens: request.maxTokens,
            vocabSize: grammarTokenizer.vocabSize,
            whitespaceBias: whitespaceBias,
            whitespaceTokenIDs: whitespaceIDs,
        ) { delta in
            text += delta
            if shouldStop() {
                stopped = true
                return false
            }
            return true
        }
        if stopped {
            throw GuidedFailure.stopped
        }
        return GuidedOutput(
            text: text,
            promptTokens: input.text.tokens.size,
            outputTokens: generated,
        )
    }
}

/// Loads the tokenizer from the model folder with swift-transformers (no Hub download, R66).
struct FolderTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        try await TokenizerBridge(AutoTokenizer.from(modelFolder: directory))
    }
}

/// swift-transformers' tokenizer as MLXLMCommon's (what the `MLXHuggingFace` macro expands
/// to, P3-A section 5.4).
struct TokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? {
        upstream.bosToken
    }

    var eosToken: String? {
        upstream.eosToken
    }

    var unknownToken: String? {
        upstream.unknownToken
    }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?,
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages, tools: tools, additionalContext: additionalContext,
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
