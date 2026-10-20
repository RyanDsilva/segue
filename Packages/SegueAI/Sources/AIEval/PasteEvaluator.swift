import Foundation
import Ingest
import ModelPort
import Synchronization

/// One provider call as the eval saw it (no text: aggregate numbers only leave the machine).
public struct EvalCall: Sendable, Hashable, Codable {
    public var task: ModelTaskKind
    public var latencyMs: Int
    public var promptTokens: Int
    public var outputTokens: Int
    public var retries: Int
    /// nil when the call answered.
    public var error: ProviderError?
}

/// What the pipeline produced for one paste with one provider (`make eval-ai` writes one JSON
/// line per record).
public struct EvalRecord: Sendable, Hashable, Codable {
    public var fixture: String
    public var provider: String
    /// One label per block of the refined result, as the review sheet would show it.
    public var labels: [String]
    /// Whether each block's label came from a header (code decides those).
    public var headed: [Bool]
    public var title: String?
    public var artist: String?
    public var key: String?
    public var calls: [EvalCall]
    public var skipped: Bool

    public init(
        fixture: String,
        provider: String,
        labels: [String],
        headed: [Bool],
        title: String?,
        artist: String?,
        key: String?,
        calls: [EvalCall],
        skipped: Bool,
    ) {
        self.fixture = fixture
        self.provider = provider
        self.labels = labels
        self.headed = headed
        self.title = title
        self.artist = artist
        self.key = key
        self.calls = calls
        self.skipped = skipped
    }
}

/// Runs the real paste pipeline (deterministic converter, then `PasteRefiner` through a
/// single-provider router) over fixtures, timing and optionally recording every call.
public enum PasteEvaluator {
    public static func run(
        _ fixtures: [EvalFixture],
        provider: any LanguageModelProvider,
        recordingSource: String? = nil,
        progress: @Sendable (String) -> Void = { _ in },
    ) async -> (records: [EvalRecord], recordings: [RecordingFile]) {
        var records: [EvalRecord] = []
        var recordings: [RecordingFile] = []
        for fixture in fixtures {
            let base = IngestPipeline.ingest(fixture.text, origin: fixture.origin)
            let probe = CallProbe(base: provider)
            let router = Router(providers: [probe], policy: .standard)
            let update = await PasteRefiner.refined(base, router: router)
            let calls = probe.calls
            let result = update.result
            let key = result.keyInference.key?.name
            records.append(EvalRecord(
                fixture: fixture.name,
                provider: provider.id.kind.rawValue,
                labels: result.blocks.map(label),
                headed: result.blocks.map { $0.labelSource == .header },
                title: result.metadata.title,
                artist: result.metadata.artists.first,
                key: key,
                calls: calls.map(\.call),
                skipped: base.isAlreadyChordPro,
            ))
            if let recordingSource, !calls.isEmpty {
                recordings.append(RecordingFile(
                    provider: provider.id.kind,
                    fixture: fixture.name,
                    source: recordingSource,
                    calls: calls.compactMap(\.recorded),
                ))
            }
            let summary = calls.map { "\($0.call.task.rawValue) \($0.call.latencyMs) ms" }
            progress("\(fixture.name): " + (summary.isEmpty ? "nothing to ask"
                    : summary.joined(separator: ", ")))
        }
        return (records, recordings)
    }

    /// What the review sheet renders for a block: its label, `other` for metadata blocks,
    /// `verse` for an unlabelled placeholder.
    static func label(_ block: IngestBlock) -> String {
        switch block.role {
        case .metadata, .passthrough: "other"
        case .content: (block.label ?? .verse).rawValue
        }
    }
}

/// Wraps a provider: forwards every call and keeps its timing and its recording.
final class CallProbe: LanguageModelProvider, @unchecked Sendable {
    struct Entry {
        var call: EvalCall
        var recorded: RecordedCall?
    }

    private let base: any LanguageModelProvider
    private let entries = Mutex<[Entry]>([])

    init(base: any LanguageModelProvider) {
        self.base = base
    }

    var id: ProviderID {
        base.id
    }

    var calls: [Entry] {
        entries.withLock { $0 }
    }

    func availability() async -> ProviderAvailability {
        await base.availability()
    }

    func run<T: ModelTask>(
        _ task: T,
        context: CallContext,
    ) async throws(ProviderError) -> ModelResult<T.Output> {
        let clock = ContinuousClock()
        let start = clock.now
        do throws(ProviderError) {
            let result = try await base.run(task, context: context)
            let entry = Entry(
                call: EvalCall(
                    task: T.kind,
                    latencyMs: Self.milliseconds(result.metrics.latency),
                    promptTokens: result.metrics.promptTokens,
                    outputTokens: result.metrics.outputTokens,
                    retries: result.metrics.retries,
                    error: nil,
                ),
                recorded: try? RecordedCall.answered(task, result.output),
            )
            entries.withLock { $0.append(entry) }
            return result
        } catch {
            let entry = Entry(
                call: EvalCall(
                    task: T.kind,
                    latencyMs: Self.milliseconds(clock.now - start),
                    promptTokens: 0,
                    outputTokens: 0,
                    retries: 0,
                    error: error,
                ),
                recorded: RecordedCall.failed(task, error),
            )
            entries.withLock { $0.append(entry) }
            throw error
        }
    }

    static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1000
            + duration.components.attoseconds / 1_000_000_000_000_000)
    }
}
