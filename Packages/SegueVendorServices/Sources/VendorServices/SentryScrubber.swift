import Foundation
import SentrySwift

/// Strips user data from crash events and breadcrumbs before the Sentry SDK stores or sends
/// them (spec 6.3). Pure functions over their inputs: `beforeSend` / `beforeBreadcrumb` run
/// on whatever thread captured the event, so nothing here hops actors or holds state.
public enum SentryScrubber {
    /// What the scrubber needs besides the event.
    public struct Context: Sendable, Hashable {
        /// True once crash reporting was revoked: everything is dropped.
        public var revoked: Bool
        /// The open library's root path, if any (replaced by `<library>`).
        public var libraryRoot: String?

        public init(revoked: Bool, libraryRoot: String? = nil) {
            self.revoked = revoked
            self.libraryRoot = libraryRoot
        }
    }

    /// The only breadcrumb category that may leave the Mac (spec 3.6).
    static let allowedCategory = "segue"
    /// Exception values are cut to this length (NSException reasons can embed data).
    static let exceptionValueLimit = 200
    /// MetricKit CPU-exception and disk-write diagnostics with fewer frames are dropped.
    static let metricKitMinimumFrames = 3

    // MARK: - Events

    /// The scrubbed event, or nil to drop it.
    public static func event(_ event: Event, context: Context) -> Event? {
        guard !context.revoked, !isLowValueMetricKit(event) else { return nil }
        let scrub = { (string: String) in self.scrub(string, libraryRoot: context.libraryRoot) }

        // Identity: only the SDK's per-install id (R25).
        if let user = event.user {
            let kept = user.userId.map(User.init(userId:))
            event.user = kept
        }
        event.serverName = nil
        event.request = nil
        event.extra = nil
        event.breadcrumbs = event.breadcrumbs?.filter {
            breadcrumb($0, context: context) != nil
        }

        if let message = event.message {
            event.message = SentryMessage(formatted: scrub(message.formatted))
        }
        event.tags = event.tags?.mapValues(scrub)
        event.context = event.context.map { contexts in
            var scrubbed = contexts.mapValues { scrubValues($0, scrub) }
            scrubbed["device"]?.removeValue(forKey: "name")
            return scrubbed
        }
        for exception in event.exceptions ?? [] {
            if let value = exception.value {
                exception.value = String(scrub(value).prefix(exceptionValueLimit))
            }
            if let description = exception.mechanism?.desc {
                exception.mechanism?.desc = scrub(description)
            }
            scrubFrames(exception.stacktrace, scrub)
        }
        for thread in event.threads ?? [] {
            thread.name = thread.name.map(scrub)
            scrubFrames(thread.stacktrace, scrub)
        }
        scrubFrames(event.stacktrace, scrub)
        for image in event.debugMeta ?? [] {
            image.codeFile = image.codeFile.map(scrub)
        }
        return event
    }

    /// The breadcrumb, or nil to drop it: only our own `segue` crumbs, never once revoked.
    public static func breadcrumb(_ crumb: Breadcrumb, context: Context) -> Breadcrumb? {
        guard !context.revoked, crumb.category == allowedCategory else { return nil }
        return crumb
    }

    // MARK: - Strings

    /// Replaces paths and song file names in one string:
    /// - anything under the library root or `~/Music` becomes `<library>/<file>`;
    /// - `/Users/<name>` becomes `/Users/<user>`;
    /// - a `.cho` or `.segue.json` file name becomes `<song file>`.
    public static func scrub(_ string: String, libraryRoot: String? = nil) -> String {
        var result = string
        if let root = libraryRoot?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
           !root.isEmpty
        {
            result = result.replacing("/\(root)", with: "<library>")
            result = result.replacing(/<library>\/[^\n"']*/, with: "<library>/<file>")
        }
        result = result.replacing(/\/Users\/[^\/\s]+\/Music(?:\/[^\n"']*)?/) { _ in
            "<library>/<file>"
        }
        result = result.replacing(/\/Users\/[^\/\s]+/) { _ in "/Users/<user>" }
        result = result.replacing(/"[^"\n]*\.(?:cho|segue\.json)"/) { _ in "\"<song file>\"" }
        result = result.replacing(/'[^'\n]*\.(?:cho|segue\.json)'/) { _ in "'<song file>'" }
        result = result.replacing(/[^\s\/"'<>]+\.(?:cho|segue\.json)\b/) { _ in "<song file>" }
        return result
    }

    private static func scrubValues(
        _ values: [String: Any],
        _ scrub: (String) -> String,
    ) -> [String: Any] {
        values.mapValues { value -> Any in
            switch value {
            case let string as String: scrub(string)
            case let nested as [String: Any]: scrubValues(nested, scrub)
            case let list as [Any]:
                list.map { item -> Any in
                    if let string = item as? String {
                        return scrub(string)
                    }
                    if let nested = item as? [String: Any] {
                        return scrubValues(nested, scrub)
                    }
                    return item
                }
            default: value
            }
        }
    }

    private static func scrubFrames(_ stacktrace: SentryStacktrace?, _ scrub: (String) -> String) {
        for frame in stacktrace?.frames ?? [] {
            frame.fileName = frame.fileName.map(scrub)
            frame.package = frame.package.map(scrub)
            frame.contextLine = nil
            frame.preContext = nil
            frame.postContext = nil
            frame.vars = nil
        }
    }

    // MARK: - MetricKit quota filter

    /// CPU-exception or disk-write MetricKit diagnostics with too few frames to act on
    /// (research 07 H.3): dropped to save quota.
    static func isLowValueMetricKit(_ event: Event) -> Bool {
        let lowValueTypes: Set = [
            "MXCPUException", "MXDiskWriteException", "mx_cpu_exception",
            "mx_disk_write_exception",
        ]
        let exceptions = event.exceptions ?? []
        let isLowValueKind = exceptions.contains { exception in
            lowValueTypes.contains(exception.type ?? "")
                || lowValueTypes.contains(exception.mechanism?.type ?? "")
        }
        guard isLowValueKind else { return false }
        let frames = exceptions.reduce(0) { $0 + ($1.stacktrace?.frames.count ?? 0) }
            + (event.threads ?? []).reduce(0) { $0 + ($1.stacktrace?.frames.count ?? 0) }
        return frames < metricKitMinimumFrames
    }
}
