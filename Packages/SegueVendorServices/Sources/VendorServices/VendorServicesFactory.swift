import Foundation
import Services
import Support

/// Builds the vendor adapters for `ServicesHub` (spec 3.3). The hub calls a method only once
/// the matching consent is granted, so constructing this factory touches no vendor code.
public struct VendorServicesFactory: ServicesFactory {
    public let config: VendorConfig
    public let environment: VendorEnvironment
    private let suiteName: String?
    private let analyticsDirectory: URL
    private let log: DiagnosticLog?
    /// Test seams: batching timing and the URL session configuration (a `URLProtocol` stub).
    var timing = IngestTiming.production
    var configureSession: @Sendable (URLSessionConfiguration) -> Void = { _ in }

    /// - Parameters:
    ///   - suiteName: the UserDefaults suite for `analytics.installID` (nil = standard).
    ///   - analyticsDirectory: `Application Support/<bundle id>/Analytics` (`queue.json`).
    public init(
        config: VendorConfig,
        environment: VendorEnvironment,
        suiteName: String?,
        analyticsDirectory: URL,
        log: DiagnosticLog?,
    ) {
        self.config = config
        self.environment = environment
        self.suiteName = suiteName
        self.analyticsDirectory = analyticsDirectory
        self.log = log
    }

    public func makeAnalytics() -> any AnalyticsSink {
        TelemetryDeckIngestSink(
            endpoint: config.telemetryDeckEndpoint,
            appID: config.telemetryDeckAppID,
            isTestMode: environment.isTestMode,
            context: .current(appVersion: config.appVersion, buildNumber: config.buildNumber),
            suiteName: suiteName,
            queueFile: TelemetryDeckIngestSink.queueFile(in: analyticsDirectory),
            timing: timing,
            clock: SystemClock(),
            log: log,
            configureSession: configureSession,
        )
    }

    public func makeCrashReporter() -> any CrashReporter {
        SentryCrashReporter(config: config, environment: environment)
    }
}
