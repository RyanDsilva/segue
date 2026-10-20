import Foundation
import Synchronization

/// Replays recorded real outputs (spec 4, R77): every automated test runs through it. Calls
/// are keyed by task kind + input hash; a call with no recording is reported through
/// `onMissing` (a crash by default, `Issue.record` in tests) and then throws `.other`, so a
/// missing recording is never a silent pass. It can also script availability and failures
/// for routing tests.
public final class ScriptedProvider: LanguageModelProvider {
    public let id: ProviderID
    private let recordings: [String: RecordedCall]
    private let onMissing: @Sendable (String) -> Void
    private let state: Mutex<State>

    private struct State {
        var availability: ProviderAvailability
        /// Errors to throw before replaying, per task kind, first one first.
        var failures: [ModelTaskKind: [ProviderError]]
        var calls: [String] = []
    }

    public init(
        id: ProviderID,
        recordings: [RecordedCall] = [],
        availability: ProviderAvailability = .available,
        failures: [ModelTaskKind: [ProviderError]] = [:],
        onMissing: @escaping @Sendable (String) -> Void = { key in
            preconditionFailure("ScriptedProvider: no recording for \(key)")
        },
    ) {
        self.id = id
        self.recordings = Dictionary(recordings.map { ($0.key, $0) }) { first, _ in first }
        self.onMissing = onMissing
        state = Mutex(State(availability: availability, failures: failures))
    }

    /// Loads every recording file in `directory` (`recorded/<provider>/`).
    public convenience init(
        id: ProviderID,
        directory: URL,
        availability: ProviderAvailability = .available,
        failures: [ModelTaskKind: [ProviderError]] = [:],
        onMissing: @escaping @Sendable (String) -> Void = { key in
            preconditionFailure("ScriptedProvider: no recording for \(key)")
        },
    ) throws {
        try self.init(
            id: id,
            recordings: RecordingFile.load(directory: directory).flatMap(\.calls),
            availability: availability,
            failures: failures,
            onMissing: onMissing,
        )
    }

    /// The recording keys of every call made so far, in order (failed calls included).
    public var calls: [String] {
        state.withLock { $0.calls }
    }

    public func setAvailability(_ availability: ProviderAvailability) {
        state.withLock { $0.availability = availability }
    }

    public func availability() async -> ProviderAvailability {
        state.withLock { $0.availability }
    }

    public func run<T: ModelTask>(
        _ task: T,
        context _: CallContext,
    ) async throws(ProviderError) -> ModelResult<T.Output> {
        let key = task.recordingKey
        let scripted: ProviderError? = state.withLock { state in
            state.calls.append(key)
            guard var queue = state.failures[T.kind], !queue.isEmpty else { return nil }
            let error = queue.removeFirst()
            state.failures[T.kind] = queue
            return error
        }
        if let scripted {
            throw scripted
        }
        guard let recording = recordings[key] else {
            onMissing(key)
            throw .other
        }
        if let error = recording.error {
            throw error
        }
        guard let output = try? recording.output?.decode(T.Output.self) else {
            onMissing("\(key) (output does not decode as \(T.Output.self))")
            throw .other
        }
        return ModelResult(output: output, metrics: CallMetrics())
    }
}
