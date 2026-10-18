import Foundation

/// The newest MetricKit diagnostic payload kept on this Mac (WS3 spec 8.5):
/// `Application Support/<bundle id>/Diagnostics/latest-diagnostic.json`, overwritten by each
/// new payload. Kept whatever the consent (MetricKit delivery is local); it leaves the Mac
/// only inside a previewed bug report.
public actor DiagnosticStore {
    public static let fileName = "latest-diagnostic.json"

    private let directory: URL
    private let log: DiagnosticLog?

    public init(directory: URL, log: DiagnosticLog?) {
        self.directory = directory
        self.log = log
    }

    public var fileURL: URL {
        directory.appending(path: Self.fileName, directoryHint: .notDirectory)
    }

    /// Replaces the stored payload with `json` (MetricKit's `jsonRepresentation()`).
    public func store(_ json: Data) {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
            )
            try json.write(to: fileURL, options: .atomic)
            log?.notice(.metricKit, "received", ["bytes": .int(json.count)])
        } catch {
            log?.error(.metricKit, "store.failed", ["error": .error(LoggedError(error))])
        }
    }

    /// The stored payload, pretty-printed so the report preview is readable.
    public func latest() -> DiagnosticFile? {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return nil }
        let pretty = (try? JSONSerialization.jsonObject(with: data))
            .flatMap { try? JSONSerialization.data(
                withJSONObject: $0,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes],
            )
            } ?? data
        return DiagnosticFile(name: Self.fileName, contentType: "application/json", data: pretty)
    }
}

/// What a bug report may attach on this Mac: the diagnostic log files and the newest
/// MetricKit payload.
public struct LocalDiagnostics: DiagnosticsSource {
    private let log: DiagnosticLog?
    private let store: DiagnosticStore?

    public init(log: DiagnosticLog?, store: DiagnosticStore?) {
        self.log = log
        self.store = store
    }

    public func recentLogFiles() async -> [DiagnosticFile] {
        guard let log else { return [] }
        await log.flush()
        return await log.files().filter { !$0.data.isEmpty }
    }

    public func latestMetricKitPayload() async -> DiagnosticFile? {
        await store?.latest()
    }
}
