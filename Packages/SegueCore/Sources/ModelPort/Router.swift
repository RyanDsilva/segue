import Foundation

/// The provider order per task (spec 4.1). Config-driven: the app reads it from a bundled
/// JSON file; `standard` is R63 (curated MLX if installed, else FM, else code), also for set
/// requests (R92).
public struct RoutingPolicy: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var orders: [ModelTaskKind: [ProviderKind]]

    public init(orders: [ModelTaskKind: [ProviderKind]]) {
        schemaVersion = 1
        self.orders = orders
    }

    /// R63 for every task.
    public static let standard = Self(orders: Dictionary(
        uniqueKeysWithValues: ModelTaskKind.allCases.map { ($0, [.mlx, .foundationModels]) },
    ))

    /// The order for `kind`; a task the file does not name keeps the standard order.
    public func order(for kind: ModelTaskKind) -> [ProviderKind] {
        orders[kind] ?? Self.standard.orders[kind] ?? []
    }

    /// Reads a routing file (`{"schemaVersion": 1, "orders": {"sectionLabels": ["mlx", "fm"]}}`).
    public static func decode(_ data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }
}

/// Why the router asked no provider at all.
public enum RoutingSkip: String, Sendable, Hashable, Codable {
    /// The AI toggle is off (R93).
    case aiOff
    /// A show is running: no model loads (R65, R95).
    case duringShow
    /// The caller's task was cancelled.
    case cancelled
}

/// What happened to one provider in the order.
public enum RoutingAttemptOutcome: Sendable, Hashable {
    case answered
    case unavailable(UnavailableCause)
    case failed(ProviderError)
}

/// One provider the router considered.
public struct RoutingAttempt: Sendable, Hashable {
    public var provider: ProviderKind
    /// `nil` when no provider of that kind is registered (reported as `notInstalled`).
    public var id: ProviderID?
    public var outcome: RoutingAttemptOutcome
}

/// Which provider answered, and why every earlier one did not. Feeds the review sheet footer
/// and the analytics fallback bucket (P3-4).
public struct RoutingReport: Sendable, Hashable {
    public var skipped: RoutingSkip?
    public var attempts: [RoutingAttempt]

    public var answeredBy: ProviderID? {
        attempts.first { $0.outcome == .answered }?.id
    }

    /// The reason the first provider in the order did not answer, if none did or a later one
    /// did (the "fallback" of `Segue.AI.pasteFinished`).
    public var firstMiss: RoutingAttemptOutcome? {
        attempts.first { $0.outcome != .answered }?.outcome
    }
}

/// A routed call: the provider's output, or `nil` when the deterministic result stands.
public struct Routed<Output: Sendable>: Sendable {
    public var result: ModelResult<Output>?
    public var report: RoutingReport

    public var output: Output? {
        result?.output
    }
}

/// Runs a task down the ordered provider list (spec 4.1): skips everything when the AI
/// toggle is off or a show is running, skips unavailable providers, falls through on every
/// typed error, and spaces one retry on `rateLimited`/`busy`.
public struct Router: Sendable {
    public typealias Flag = @Sendable () async -> Bool
    public typealias Sleep = @Sendable (Duration) async throws -> Void

    public let providers: [any LanguageModelProvider]
    public let policy: RoutingPolicy
    private let isEnabled: Flag
    private let isShowRunning: Flag
    private let retryDelay: Duration
    private let sleep: Sleep

    /// - Parameters:
    ///   - isEnabled: the AI toggle (R93; its storage is P3-3's).
    ///   - isShowRunning: true while a show runs (no model loads, R65).
    ///   - retryDelay: the spacing of the one retry on `rateLimited`/`busy`.
    public init(
        providers: [any LanguageModelProvider],
        policy: RoutingPolicy = .standard,
        isEnabled: @escaping Flag = { true },
        isShowRunning: @escaping Flag = { false },
        retryDelay: Duration = .seconds(2),
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
    ) {
        self.providers = providers
        self.policy = policy
        self.isEnabled = isEnabled
        self.isShowRunning = isShowRunning
        self.retryDelay = retryDelay
        self.sleep = sleep
    }

    /// The registered provider for each kind in `kind`'s order.
    public func order(for kind: ModelTaskKind) -> [(ProviderKind, (any LanguageModelProvider)?)] {
        policy.order(for: kind).map { providerKind in
            (providerKind, providers.first { $0.id.kind == providerKind })
        }
    }

    public func run<T: ModelTask>(_ task: T) async -> Routed<T.Output> {
        guard await isEnabled() else {
            return Routed(result: nil, report: RoutingReport(skipped: .aiOff, attempts: []))
        }
        guard await !isShowRunning() else {
            return Routed(result: nil, report: RoutingReport(skipped: .duringShow, attempts: []))
        }
        let order = order(for: T.kind)
        var attempts: [RoutingAttempt] = []
        for (position, (kind, provider)) in order.enumerated() {
            if Task.isCancelled {
                return Routed(
                    result: nil,
                    report: RoutingReport(skipped: .cancelled, attempts: attempts),
                )
            }
            guard let provider else {
                attempts.append(RoutingAttempt(
                    provider: kind, id: nil, outcome: .unavailable(.notInstalled),
                ))
                continue
            }
            if case let .unavailable(cause) = await provider.availability() {
                attempts.append(RoutingAttempt(
                    provider: kind, id: provider.id, outcome: .unavailable(cause),
                ))
                continue
            }
            let laterMLX = order.dropFirst(position + 1).contains { $0.0 == .mlx && $0.1 != nil }
            let context = CallContext(allowsChunking: !laterMLX)
            switch await call(provider, task, context: context) {
            case let .success(result):
                attempts.append(RoutingAttempt(provider: kind, id: provider.id, outcome: .answered))
                return Routed(
                    result: result,
                    report: RoutingReport(skipped: nil, attempts: attempts),
                )
            case let .failure(error):
                attempts.append(RoutingAttempt(
                    provider: kind, id: provider.id, outcome: .failed(error),
                ))
            }
        }
        return Routed(result: nil, report: RoutingReport(skipped: nil, attempts: attempts))
    }

    /// One call plus, on `rateLimited`/`busy`, one spaced retry.
    private func call<T: ModelTask>(
        _ provider: any LanguageModelProvider,
        _ task: T,
        context: CallContext,
    ) async -> Result<ModelResult<T.Output>, ProviderError> {
        do throws(ProviderError) {
            return try await .success(provider.run(task, context: context))
        } catch where error == .rateLimited || error == .busy {
            do {
                try await sleep(retryDelay)
            } catch {
                return .failure(.other)
            }
            do throws(ProviderError) {
                var result = try await provider.run(task, context: context)
                result.metrics.retries += 1
                return .success(result)
            } catch {
                return .failure(error)
            }
        } catch {
            return .failure(error)
        }
    }
}
