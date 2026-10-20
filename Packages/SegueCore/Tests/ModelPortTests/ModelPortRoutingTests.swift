import Foundation
import Ingest
@testable import ModelPort
import Synchronization
import Testing

/// The router (spec 4.1): AI off and show-running skips, availability, fall-through on every
/// typed error, the one spaced retry, the chunking context, the config file.
struct ModelPortRoutingTests {
    static let task = MetadataTask(
        topLines: ["Paper Lanterns - The Hollow Pines"],
        bottomLines: [],
        chords: ["G"],
    )
    static let answer = MetadataOutput(
        title: "Paper Lanterns",
        artist: "The Hollow Pines",
        key: "G",
    )
    static let mlxID = ProviderID.mlx(ModelRef(repo: "mlx-community/test", revision: "abc"))

    static func provider(
        _ id: ProviderID,
        availability: ProviderAvailability = .available,
        failures: [ProviderError] = [],
    ) throws -> ScriptedProvider {
        try ScriptedProvider(
            id: id,
            recordings: [RecordedCall.answered(task, answer)],
            availability: availability,
            failures: failures.isEmpty ? [:] : [.metadata: failures],
            onMissing: { Issue.record("no recording for \($0)") },
        )
    }

    @Test
    func `AI off asks no provider`() async throws {
        let fm = try Self.provider(.foundationModels)
        let router = Router(providers: [fm], isEnabled: { false })
        let routed = await router.run(Self.task)
        #expect(routed.output == nil)
        #expect(routed.report.skipped == .aiOff)
        #expect(fm.calls.isEmpty)
    }

    @Test
    func `a running show loads no model`() async throws {
        let fm = try Self.provider(.foundationModels)
        let router = Router(providers: [fm], isShowRunning: { true })
        let routed = await router.run(Self.task)
        #expect(routed.output == nil)
        #expect(routed.report.skipped == .duringShow)
        #expect(fm.calls.isEmpty)
    }

    @Test
    func `MLX first when installed, then FM, by default (R63)`() async throws {
        let mlx = try Self.provider(Self.mlxID)
        let fm = try Self.provider(.foundationModels)
        let routed = await Router(providers: [fm, mlx]).run(Self.task)
        #expect(routed.output == Self.answer)
        #expect(routed.report.answeredBy == Self.mlxID)
        #expect(fm.calls.isEmpty)
    }

    @Test(arguments: [
        ProviderAvailability.unavailable(.notInstalled),
        .unavailable(.duringShow),
    ])
    func `an unavailable MLX falls to FM`(availability: ProviderAvailability) async throws {
        let mlx = try Self.provider(Self.mlxID, availability: availability)
        let fm = try Self.provider(.foundationModels)
        let routed = await Router(providers: [mlx, fm]).run(Self.task)
        #expect(routed.report.answeredBy == .foundationModels)
        #expect(mlx.calls.isEmpty)
        guard case let .unavailable(cause) = availability else { return }
        #expect(routed.report.attempts.first?.outcome == .unavailable(cause))
    }

    @Test
    func `no MLX provider registered reads as not installed`() async throws {
        let fm = try Self.provider(.foundationModels)
        let routed = await Router(providers: [fm]).run(Self.task)
        #expect(routed.report.attempts.map(\.outcome) == [.unavailable(.notInstalled), .answered])
        #expect(routed.report.firstMiss == .unavailable(.notInstalled))
    }

    @Test(arguments: [
        UnavailableCause.appleIntelligenceNotEnabled, .modelNotReady, .deviceNotEligible, .unknown,
    ])
    func `FM unavailable leaves the deterministic result`(cause: UnavailableCause) async throws {
        let fm = try Self.provider(.foundationModels, availability: .unavailable(cause))
        let routed = await Router(providers: [fm]).run(Self.task)
        #expect(routed.output == nil)
        #expect(routed.report.attempts.last?.outcome == .unavailable(cause))
    }

    /// Every typed error falls through to the next provider (here MLX after FM by config),
    /// and to the deterministic result when none is left.
    @Test(arguments: ProviderError.allCases.filter { $0 != .rateLimited && $0 != .busy })
    func `each error falls through to the next provider`(error: ProviderError) async throws {
        let policy = RoutingPolicy(orders: [.metadata: [.foundationModels, .mlx]])
        let fm = try Self.provider(.foundationModels, failures: [error])
        let mlx = try Self.provider(Self.mlxID)
        let routed = await Router(providers: [fm, mlx], policy: policy).run(Self.task)
        #expect(routed.output == Self.answer)
        #expect(routed.report.attempts.map(\.outcome) == [.failed(error), .answered])
        #expect(fm.calls.count == 1)

        let alone = try Self.provider(.foundationModels, failures: [error])
        let deterministic = await Router(providers: [alone]).run(Self.task)
        #expect(deterministic.output == nil)
        #expect(deterministic.report.attempts.last?.outcome == .failed(error))
    }

    @Test(arguments: [ProviderError.rateLimited, .busy])
    func `rate limits get one spaced retry`(error: ProviderError) async throws {
        let slept = Locked<[Duration]>([])
        let fm = try Self.provider(.foundationModels, failures: [error])
        let router = Router(
            providers: [fm],
            retryDelay: .milliseconds(1500),
            sleep: { delay in slept.update { $0.append(delay) } },
        )
        let routed = await router.run(Self.task)
        #expect(routed.output == Self.answer)
        #expect(routed.result?.metrics.retries == 1)
        #expect(slept.value == [.milliseconds(1500)])
        #expect(fm.calls.count == 2)

        let twice = try Self.provider(.foundationModels, failures: [error, error])
        let failed = await Router(providers: [twice], sleep: { _ in }).run(Self.task)
        #expect(failed.output == nil)
        #expect(failed.report.attempts.last?.outcome == .failed(error))
        #expect(twice.calls.count == 2)
    }

    @Test
    func `chunking is allowed only when no MLX comes later`() async throws {
        let seen = Locked<[CallContext]>([])
        let spy = ContextSpy(id: .foundationModels, seen: seen)
        let mlx = try Self.provider(Self.mlxID)
        let fmFirst = RoutingPolicy(orders: [.metadata: [.foundationModels, .mlx]])
        _ = await Router(providers: [spy, mlx], policy: fmFirst).run(Self.task)
        _ = await Router(providers: [spy, mlx]).run(Self.task)
        _ = await Router(providers: [spy]).run(Self.task)
        #expect(seen.value.map(\.allowsChunking) == [false, true])
        // The default order asked MLX first, which answered, so the spy saw two calls.
    }

    @Test
    func `routing config file decodes and falls back to the standard order`() throws {
        let json = #"{"schemaVersion": 1, "orders": {"setRequest": ["fm"]}}"#
        let policy = try RoutingPolicy.decode(Data(json.utf8))
        #expect(policy.order(for: .setRequest) == [.foundationModels])
        #expect(policy.order(for: .sectionLabels) == [.mlx, .foundationModels])
        #expect(RoutingPolicy.standard.orders.count == ModelTaskKind.allCases.count)
    }

    @Test
    func `a missing recording is reported, never a silent pass`() async {
        let missing = Locked<[String]>([])
        let fm = ScriptedProvider(
            id: .foundationModels,
            onMissing: { key in missing.update { $0.append(key) } },
        )
        let routed = await Router(providers: [fm]).run(Self.task)
        #expect(routed.output == nil)
        #expect(missing.value == [Self.task.recordingKey])
    }

    /// The recording key must not drift: recordings on disk depend on it.
    @Test
    func `input hashes are stable`() {
        #expect(StableHash.hex(of: Data()) == "cbf29ce484222325")
        #expect(Self.task.recordingKey == "metadata-\(Self.task.inputHash)")
        #expect(Self.task.inputHash == StableHash.hex(of: StableHash.canonicalJSON(Self.task)))
        let reordered = MetadataTask(topLines: Self.task.topLines, bottomLines: [], chords: ["G"])
        #expect(reordered.inputHash == Self.task.inputHash)
    }

    @Test
    func `metadata and set request outputs are normalised`() {
        let output = MetadataOutput(title: " Unknown ", artist: "Glass Houses", key: "H")
        #expect(output.normalized() == MetadataOutput(title: "", artist: "Glass Houses", key: ""))
        let same = MetadataOutput(title: "Safar", artist: "safar", key: "Am").normalized()
        #expect(same.artist.isEmpty && same.key == "Am")
        let request = SetRequestOutput(
            includeTags: ["upbeat", "jazz", "upbeat", "ballad"],
            excludeTags: ["ballad"],
            minProficiency: .ready,
            openerTag: "upbeat",
            closerTag: "nope",
        ).normalized(libraryTags: ["upbeat", "ballad"])
        #expect(request.includeTags == ["upbeat"])
        #expect(request.excludeTags.isEmpty)
        #expect(request.openerTag == "upbeat" && request.closerTag.isEmpty)
    }
}

/// Records the call context and answers nothing (always `.other`).
private struct ContextSpy: LanguageModelProvider {
    let id: ProviderID
    let seen: Locked<[CallContext]>

    func availability() async -> ProviderAvailability {
        .available
    }

    func run<T: ModelTask>(
        _: T,
        context: CallContext,
    ) async throws(ProviderError) -> ModelResult<T.Output> {
        seen.update { $0.append(context) }
        throw .other
    }
}

/// A value shared with `@Sendable` closures in tests.
final class Locked<Value: Sendable>: Sendable {
    private let storage: Mutex<Value>

    init(_ value: Value) {
        storage = Mutex(value)
    }

    var value: Value {
        storage.withLock { $0 }
    }

    func update(_ change: (inout Value) -> Void) {
        storage.withLock { change(&$0) }
    }
}
