import Foundation
import SentrySwift
import Services
import Synchronization

/// Crashes, hangs (through MetricKit) and our own breadcrumbs, through the Sentry SDK
/// (spec 6). Constructed only by `ServicesHub` once crash-report consent is granted.
///
/// The SDK starts at most once per process. Restarting it after `SentrySDK.close()` is not
/// documented as supported, so after a revoke a re-grant in the same process records nothing
/// and crash reporting starts at the next launch (A11); `startsAtNextLaunch` says so.
public final class SentryCrashReporter: CrashReporter {
    /// Process-wide SDK state read by the `beforeSend` / `beforeBreadcrumb` callbacks.
    private struct Shared {
        var started = false
        var revoked = false
        var libraryRoot: String?
    }

    private static let shared = Mutex(Shared())

    private let cacheDirectory: String
    /// False when the SDK had already been started (and closed) in this process.
    private let isRecording: Bool

    /// Starts the SDK (on the main thread) unless it already ran in this process.
    /// - Parameter cacheDirectory: the SDK's cache directory (default: the app container's
    ///   `Library/Caches`, as the SDK itself defaults).
    public init(
        config: VendorConfig,
        environment: VendorEnvironment,
        cacheDirectory: String? = nil,
    ) {
        let cache = cacheDirectory ?? Self.defaultCacheDirectory
        self.cacheDirectory = cache
        let firstStart = Self.shared.withLock { state -> Bool in
            guard !state.started else { return false }
            state.started = true
            state.revoked = false
            return true
        }
        isRecording = firstStart
        guard firstStart else { return }

        let dsn = config.sentryDSN.description
        let release = config.sentryReleaseName
        let start: @Sendable () -> Void = {
            SentrySDK.start { options in
                Self.configure(
                    options,
                    dsn: dsn,
                    release: release,
                    environment: environment,
                    cacheDirectory: cache,
                )
            }
        }
        if Thread.isMainThread {
            start()
        } else {
            DispatchQueue.main.async(execute: start)
        }
    }

    /// True when the SDK was closed earlier in this process: crash reporting resumes at the
    /// next launch (Settings > Privacy shows the A11 caption).
    public static var startsAtNextLaunch: Bool {
        shared.withLock { $0.started && $0.revoked }
    }

    /// Tells the scrubber which library path to replace with `<library>`.
    public static func setLibraryRoot(_ root: URL?) {
        shared.withLock { $0.libraryRoot = root?.path(percentEncoded: false) }
    }

    // MARK: - CrashReporter

    public func addBreadcrumb(_ crumb: Services.Breadcrumb) {
        guard isRecording else { return }
        let sentryCrumb = SentrySwift.Breadcrumb(level: .info, category: crumb.category)
        sentryCrumb.message = crumb.message
        for (key, value) in crumb.data {
            sentryCrumb.setData(value: value, key: key)
        }
        SentrySDK.addBreadcrumb(sentryCrumb)
    }

    /// Revoke (spec 6.4): set the drop flag so `beforeSend` returns nil, delete the cached
    /// envelopes (keeping the `INSTALLATION` file so the Diagnostics ID stays stable, R25),
    /// then close the SDK, whose pending flush now finds nothing to send.
    public func shutDown(discardingQueue: Bool) async {
        guard isRecording else { return }
        Self.shared.withLock { $0.revoked = true }
        if discardingQueue {
            Self.deleteCachedEnvelopes(cacheDirectory: cacheDirectory)
        }
        await MainActor.run {
            SentrySDK.close()
        }
        if discardingQueue {
            Self.deleteCachedEnvelopes(cacheDirectory: cacheDirectory)
        }
    }

    /// The SDK's per-install ID (`<cache>/INSTALLATION`), used as `user.id` and shown in
    /// Settings > Privacy as the Diagnostics ID.
    public var installationID: String? {
        Self.installationID(cacheDirectory: cacheDirectory)
    }

    // MARK: - SDK options (spec 6.2)

    private static func configure(
        _ options: Options,
        dsn: String,
        release: String,
        environment: VendorEnvironment,
        cacheDirectory: String,
    ) {
        options.dsn = dsn
        options.releaseName = release
        options.environment = environment.sentryEnvironment
        options.cacheDirectoryPath = cacheDirectory
        options.sendDefaultPii = false
        options.enableCrashHandler = true
        options.enableUncaughtNSExceptionReporting = true
        options.enableMetricKit = true
        options.enableMetricKitRawPayload = false
        // Deprecated in the pinned SDK in favour of MetricKit hang diagnostics.
        options.enableAppHangTracking = false
        options.enableAutoSessionTracking = false
        options.enableWatchdogTerminationTracking = false
        options.enableAutoBreadcrumbTracking = false
        options.enableNetworkBreadcrumbs = false
        options.enableNetworkTracking = false
        options.enableCaptureFailedRequests = false
        options.enableSwizzling = false
        options.enableFileIOTracing = false
        // `enableUserInteractionTracing` is UIKit-only in the pinned SDK (absent on macOS).
        options.enableCoreDataTracing = false
        options.enableLogs = false
        options.attachStacktrace = true
        options.swiftAsyncStacktraces = true
        options.maxBreadcrumbs = 50
        options.beforeSend = { event in
            SentryScrubber.event(event, context: scrubContext())
        }
        options.beforeBreadcrumb = { crumb in
            SentryScrubber.breadcrumb(crumb, context: scrubContext())
        }
    }

    private static func scrubContext() -> SentryScrubber.Context {
        shared.withLock { SentryScrubber.Context(revoked: $0.revoked, libraryRoot: $0.libraryRoot) }
    }

    // MARK: - Files

    static var defaultCacheDirectory: String {
        NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first ?? ""
    }

    static func installationID(cacheDirectory: String) -> String? {
        let file = URL(fileURLWithPath: cacheDirectory).appending(path: "INSTALLATION")
        guard let data = try? Data(contentsOf: file),
              let id = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty
        else {
            return nil
        }
        return id
    }

    /// Deletes everything the SDK keeps waiting to be sent: `<cache>/io.sentry` (cached
    /// envelopes, sessions) and `<cache>/SentryCrash` (raw crash reports converted at the next
    /// start). The `INSTALLATION` file sits beside them and is kept.
    static func deleteCachedEnvelopes(cacheDirectory: String) {
        let base = URL(fileURLWithPath: cacheDirectory)
        for folder in ["io.sentry", "SentryCrash"] {
            try? FileManager.default.removeItem(at: base.appending(path: folder))
        }
    }
}
