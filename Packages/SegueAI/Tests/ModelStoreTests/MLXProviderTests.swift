import Foundation
import Ingest
@testable import MLXAdapter
import ModelPort
import Synchronization
import Testing

/// The MLX provider's logic behind the `GuidedEngine` seam (no MLX: SwiftPM's command line
/// cannot build its Metal library). Real inference is covered by `make eval-ai`.
struct MLXProviderTests {
    /// A scripted engine: answers per call in order, counts loads and unloads.
    final class FakeEngine: GuidedEngine, Sendable {
        enum Step: Sendable {
            case answer(String)
            case fail(GuidedFailure)
            /// Runs until `shouldStop`, then fails `.stopped`.
            case hang
        }

        struct State {
            var steps: [Step]
            var requests: [GuidedRequest] = []
            var loads = 0
            var unloads = 0
        }

        let state: Mutex<State>

        init(_ steps: [Step]) {
            state = Mutex(State(steps: steps))
        }

        var requests: [GuidedRequest] {
            state.withLock { $0.requests }
        }

        var loads: Int {
            state.withLock { $0.loads }
        }

        var unloads: Int {
            state.withLock { $0.unloads }
        }

        func load(folder _: URL) async throws(GuidedFailure) -> any LoadedGuidedModel {
            state.withLock { $0.loads += 1 }
            return Loaded(engine: self)
        }

        struct Loaded: LoadedGuidedModel {
            let engine: FakeEngine

            func generate(
                _ request: GuidedRequest,
                shouldStop: @escaping @Sendable () -> Bool,
            ) async throws(GuidedFailure) -> GuidedOutput {
                let step: Step = engine.state.withLock { state in
                    state.requests.append(request)
                    return state.steps.isEmpty ? .fail(.other) : state.steps.removeFirst()
                }
                switch step {
                case let .answer(text):
                    return GuidedOutput(text: text, promptTokens: 100, outputTokens: 20)
                case let .fail(failure):
                    throw failure
                case .hang:
                    while !shouldStop() {
                        try? await Task.sleep(for: .milliseconds(5))
                    }
                    throw .stopped
                }
            }

            func unload() async {
                engine.state.withLock { $0.unloads += 1 }
            }
        }
    }

    struct Installed: ModelFolderResolver {
        var installed = true

        func activeModel() async -> (manifest: LocalModelManifest, folder: URL)? {
            guard installed else { return nil }
            let license = LocalModelManifest.License(
                id: "mit",
                name: "MIT",
                url: URL(filePath: "/tmp/LICENSE"),
                upstreamRepo: "x/M",
            )
            let manifest = LocalModelManifest(
                id: "m",
                displayName: "M",
                status: .locked,
                role: .standard,
                repo: "mlx-community/M",
                revision: String(repeating: "0", count: 40),
                files: [],
                license: license,
                memoryBytes: 1,
            )
            return (manifest, URL(filePath: "/tmp/m"))
        }
    }

    static let model = ModelRef(
        repo: "mlx-community/M",
        revision: String(repeating: "0", count: 40),
    )

    static func provider(
        _ engine: FakeEngine,
        installed: Bool = true,
        timeout: Duration = .seconds(30),
        linger: Duration = .milliseconds(50),
        showRunning: Bool = false,
    ) -> MLXProvider {
        MLXProvider(
            engine: engine,
            resolver: Installed(installed: installed),
            defaultModel: model,
            configuration: .init(timeout: timeout, linger: linger),
            isShowRunning: { showRunning },
        )
    }

    static let labels = SectionLabelTask(blocks: [
        .init(index: 0, lines: ["G D Em C"], hint: ""),
        .init(index: 1, lines: ["Lamps along the harbour wall"], hint: ""),
    ])

    static let labelsJSON = #"{"blocks":[{"block":0,"label":"intro"},{"block":1,"label":"verse"}]}"#

    @Test
    func `a labels call sends the compact grammar and maps the answer`() async throws {
        let engine = FakeEngine([.answer(Self.labelsJSON)])
        let result = try await Self.provider(engine).run(
            Self.labels, context: CallContext(allowsChunking: false),
        )
        #expect(result.output.labels == [.intro, .verse])
        #expect(result.metrics.retries == 0)
        let request = try #require(engine.requests.first)
        #expect(request.grammar == MLXGrammars.labels(blockNumbers: [0, 1]))
        #expect(request.system.hasSuffix("Write compact JSON with no spaces or line breaks."))
        #expect(request.system.contains(#""minItems":2"#))
        #expect(!request.whitespaceBias)
    }

    @Test
    func `the grammars leave no room for whitespace`() {
        let grammar = MLXGrammars.labels(blockNumbers: [0, 3])
        #expect(grammar.contains(#"b1 ::= "{\"block\":3,\"label\":" label "}""#))
        #expect(!grammar.contains("ws"))
        let tags = MLXGrammars.setRequest(libraryTags: ["upbeat", "say \"hi\""])
        #expect(tags.contains(#""\"say \\\"hi\\\"\"""#))
        #expect(tags.contains("more{0,3}"))
        #expect(MLXGrammars.setRequest(libraryTags: []).contains(#"tags ::= "[]""#))
        #expect(MLXGrammars.metadata().contains("char{0,80}"))
    }

    @Test
    func `incomplete output gets one retry with a whitespace bias`() async throws {
        let engine = FakeEngine([.fail(.incompleteOutput), .answer(Self.labelsJSON)])
        let result = try await Self.provider(engine).run(
            Self.labels, context: CallContext(allowsChunking: false),
        )
        #expect(result.metrics.retries == 1)
        #expect(engine.requests.map(\.whitespaceBias) == [false, true])
    }

    @Test
    func `a second incomplete output falls through as incompleteOutput`() async {
        let engine = FakeEngine([.fail(.incompleteOutput), .fail(.incompleteOutput)])
        await #expect(throws: ProviderError.incompleteOutput) {
            try await Self.provider(engine).run(
                Self.labels, context: CallContext(allowsChunking: false),
            )
        }
    }

    @Test
    func `an answer that does not fit the task is a decoding failure`() async {
        let engine = FakeEngine([.answer(#"{"blocks":[{"block":0,"label":"intro"}]}"#)])
        await #expect(throws: ProviderError.decodingFailure) {
            try await Self.provider(engine).run(
                Self.labels, context: CallContext(allowsChunking: false),
            )
        }
    }

    @Test
    func `a stalled call times out and stops at its next token`() async throws {
        let engine = FakeEngine([.hang])
        let provider = Self.provider(engine, timeout: .milliseconds(100))
        await #expect(throws: ProviderError.timeout) {
            try await provider.run(Self.labels, context: CallContext(allowsChunking: false))
        }
        // The stopped generation releases the model and it unloads after the linger.
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while await provider.isModelLoaded, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await !provider.isModelLoaded)
    }

    @Test
    func `the model loads once per paste and unloads right after`() async throws {
        let metadata = #"{"title":"Harbour Wall","artist":"","key":"G"}"#
        let engine = FakeEngine([.answer(Self.labelsJSON), .answer(metadata)])
        let provider = Self.provider(engine, linger: .milliseconds(200))
        let context = CallContext(allowsChunking: false)
        _ = try await provider.run(Self.labels, context: context)
        let answer = try await provider.run(
            MetadataTask(topLines: ["Harbour Wall"], bottomLines: [], chords: ["G"]),
            context: context,
        )
        #expect(answer.output == MetadataOutput(title: "Harbour Wall", artist: "", key: "G"))
        #expect(engine.loads == 1)
        #expect(await provider.isModelLoaded)
        try await Task.sleep(for: .milliseconds(500))
        #expect(await !provider.isModelLoaded)
        #expect(engine.unloads == 1)
    }

    @Test
    func `no model, no call: not installed, and nothing loads during a show`() async {
        let engine = FakeEngine([])
        #expect(await Self.provider(engine, installed: false).availability()
            == .unavailable(.notInstalled))
        #expect(await Self.provider(engine, showRunning: true).availability()
            == .unavailable(.duringShow))
        #expect(await Self.provider(engine).availability() == .available)
        await #expect(throws: ProviderError.notInstalled) {
            try await Self.provider(engine, installed: false).run(
                Self.labels, context: CallContext(allowsChunking: false),
            )
        }
        #expect(engine.loads == 0)
    }

    @Test
    func `a call while another runs is busy`() async throws {
        let engine = FakeEngine([.hang, .answer(Self.labelsJSON)])
        let provider = Self.provider(engine, timeout: .milliseconds(300))
        let context = CallContext(allowsChunking: false)
        async let first: Void = {
            _ = try? await provider.run(Self.labels, context: context)
        }()
        try await Task.sleep(for: .milliseconds(50))
        await #expect(throws: ProviderError.busy) {
            try await provider.run(Self.labels, context: context)
        }
        await first
    }

    @Test
    func `the router asks MLX first and falls through to the next provider`() async {
        let engine = FakeEngine([.fail(.other)])
        let router = Router(providers: [Self.provider(engine)])
        let routed = await router.run(Self.labels)
        #expect(routed.output == nil)
        #expect(routed.report.attempts.first?.provider == .mlx)
        #expect(routed.report.attempts.first?.outcome == .failed(.other))
    }
}
