import Foundation
import os
import Support

/// Privacy-safe rolling file log (spec 7): gives bug reports the logs of previous launches,
/// which `OSLogStore` cannot read in the sandbox, without ever writing user content.
///
/// The API takes only `StaticString` messages and keys and typed values; there is no way to
/// log a `String`, so titles, lyrics and paths cannot reach the file. Errors are logged by
/// domain and code only (`LoggedError`), never by `localizedDescription`.
///
/// Files: `segue-0.log` (this launch) to `segue-3.log` (three launches back), rotated when the
/// log is created, each capped at 512 KB. Lines look like
/// `2026-10-17T21:03:11.402Z notice library opened songs=50-99 ms=212`.
///
/// `log(...)` is nonisolated and synchronous: it renders the line and hands it to the actor
/// through an `AsyncStream`, so call sites never `await` and never wait on disk.
public actor DiagnosticLog {
    public static let fileCount = 4
    public static let fileByteLimit = 512 * 1024
    /// At most this often a write is followed by `synchronize()`.
    static let syncInterval: TimeInterval = 2
    static let truncatedLine = "log.truncated"

    public enum Level: String, Sendable {
        case info
        case notice
        case error
    }

    private enum Entry: Sendable {
        case line(String)
        case flush(CheckedContinuation<Void, Never>)
    }

    private let directory: URL
    private let clock: any Clock
    private let mirror: Bool
    private let continuation: AsyncStream<Entry>.Continuation

    private var handle: FileHandle?
    private var bytesWritten = 0
    private var truncated = false
    private var lastSync: Date?

    /// Rotates the files in `directory` (creating it) and starts this launch's file.
    ///
    /// - Parameter mirrorToOSLog: also send each line to `os.Logger` (subsystem
    ///   `dev.ryandsilva.segue`, public: only typed values exist).
    public init(directory: URL, clock: any Clock = SystemClock(), mirrorToOSLog: Bool = true) {
        self.directory = directory
        self.clock = clock
        mirror = mirrorToOSLog
        let (stream, continuation) = AsyncStream<Entry>.makeStream()
        self.continuation = continuation
        handle = Self.rotate(in: directory)
        Task { [weak self] in
            for await entry in stream {
                await self?.process(entry)
            }
        }
    }

    deinit {
        continuation.finish()
        try? handle?.close()
    }

    /// The existing log files, newest first, for a bug report.
    public func files() -> [DiagnosticFile] {
        try? handle?.synchronize()
        return (0 ..< Self.fileCount).compactMap { index in
            guard let data = try? Data(contentsOf: fileURL(index)) else { return nil }
            return DiagnosticFile(name: "segue-\(index).log", contentType: "text/plain", data: data)
        }
    }

    // MARK: Writing

    private func process(_ entry: Entry) {
        switch entry {
        case let .line(text):
            write(text)
        case let .flush(done):
            sync()
            done.resume()
        }
    }

    private func write(_ text: String) {
        guard let handle, !truncated else { return }
        let line = Data((text + "\n").utf8)
        let marker = Data((Self.truncatedLine + "\n").utf8)
        do {
            if bytesWritten + line.count + marker.count > Self.fileByteLimit {
                truncated = true
                try handle.write(contentsOf: marker)
                bytesWritten += marker.count
                sync()
                return
            }
            try handle.write(contentsOf: line)
            bytesWritten += line.count
            let now = clock.now()
            if let lastSync, now.timeIntervalSince(lastSync) < Self.syncInterval {
                return
            }
            sync()
        } catch {
            disable()
        }
    }

    private func sync() {
        guard let handle else { return }
        do {
            try handle.synchronize()
            lastSync = clock.now()
        } catch {
            disable()
        }
    }

    /// A write failure turns the file log off for this launch and never surfaces.
    private func disable() {
        try? handle?.close()
        handle = nil
    }

    // MARK: Files

    private static func fileURL(_ index: Int, in directory: URL) -> URL {
        directory.appending(path: "segue-\(index).log", directoryHint: .notDirectory)
    }

    /// segue-2 -> 3, 1 -> 2, 0 -> 1, then a new empty segue-0. Returns its handle, or nil
    /// when the directory is not writable (file log off for this launch).
    private static func rotate(in directory: URL) -> FileHandle? {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            for index in stride(from: fileCount - 1, through: 1, by: -1) {
                let destination = fileURL(index, in: directory)
                let source = fileURL(index - 1, in: directory)
                if manager.fileExists(atPath: destination.path(percentEncoded: false)) {
                    try manager.removeItem(at: destination)
                }
                if manager.fileExists(atPath: source.path(percentEncoded: false)) {
                    try manager.moveItem(at: source, to: destination)
                }
            }
            let current = fileURL(0, in: directory)
            guard manager.createFile(atPath: current.path(percentEncoded: false), contents: nil)
            else {
                return nil
            }
            return try FileHandle(forWritingTo: current)
        } catch {
            return nil
        }
    }

    private static let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}

// Nonisolated entry points: call sites never await and never wait on disk.
// SwiftFormat orders `public` first, SwiftLint's modifier_order wants `nonisolated` first.
// swiftformat:disable:next modifierOrder
nonisolated public extension DiagnosticLog {
    /// The log file for `index` launches back (0 = this launch).
    func fileURL(_ index: Int) -> URL {
        Self.fileURL(index, in: directory)
    }

    // MARK: Logging

    func info(
        _ category: LogCategory,
        _ message: StaticString,
        _ fields: KeyValuePairs<StaticString, LogValue> = [:],
    ) {
        log(.info, category, message, fields)
    }

    func notice(
        _ category: LogCategory,
        _ message: StaticString,
        _ fields: KeyValuePairs<StaticString, LogValue> = [:],
    ) {
        log(.notice, category, message, fields)
    }

    func error(
        _ category: LogCategory,
        _ message: StaticString,
        _ fields: KeyValuePairs<StaticString, LogValue> = [:],
    ) {
        log(.error, category, message, fields)
    }

    func log(
        _ level: Level,
        _ category: LogCategory,
        _ message: StaticString,
        _ fields: KeyValuePairs<StaticString, LogValue>,
    ) {
        let rendered = fields.map { "\($0.key)=\($0.value.rendered)" }
        let body = ([category.rawValue, "\(message)"] + rendered).joined(separator: " ")
        let stamp = clock.now().formatted(Self.timestampStyle)
        continuation.yield(.line("\(stamp) \(level.rawValue) \(body)"))
        if mirror {
            let logger = Logger(subsystem: "dev.ryandsilva.segue", category: category.rawValue)
            logger.log(level: level.osLogType, "\(body, privacy: .public)")
        }
    }

    /// Waits until every line logged before this call is written and synchronised to disk
    /// (app termination, tests).
    func flush() async {
        await withCheckedContinuation { done in
            continuation.yield(.flush(done))
        }
    }
}

/// Log categories (also the `os.Logger` category).
public enum LogCategory: String, Sendable, CaseIterable {
    case app
    case library
    case index
    case show
    case consent
    case analytics
    case feedback
    case metricKit
    case services
}

/// A typed log value. There is deliberately no `String` case.
public enum LogValue: Sendable {
    case int(Int)
    case bool(Bool)
    case double(Double)
    case token(StaticString)
    case bucket(any LogBucket)
    case error(LoggedError)
    case duration(Duration)

    var rendered: String {
        switch self {
        case let .int(value): String(value)
        case let .bool(value): String(value)
        case let .double(value): String(format: "%.3f", value)
        case let .token(value): "\(value)"
        case let .bucket(value): value.rawValue
        case let .error(value): value.rendered
        case let .duration(value): "\(Int((value / .milliseconds(1)).rounded()))ms"
        }
    }
}

/// Our own error enums log a fixed code instead of their description.
public protocol LoggableError: Error {
    var logCode: StaticString { get }
}

/// An error reduced to what is safe to log: an `NSError` domain (only if it looks like an
/// identifier, else `other`) and code, or a `LoggableError`'s `logCode`. Never the
/// description or user info, which embed file names.
public struct LoggedError: Sendable, Hashable {
    let rendered: String

    public init(_ error: any Error) {
        if let loggable = error as? any LoggableError {
            rendered = "\(loggable.logCode)"
            return
        }
        let nsError = error as NSError
        let domain = Self.isSafeDomain(nsError.domain) ? nsError.domain : "other"
        rendered = "\(domain):\(nsError.code)"
    }

    static func isSafeDomain(_ domain: String) -> Bool {
        (1 ... 64).contains(domain.utf8.count)
            && domain.unicodeScalars.allSatisfy { scalar in
                scalar.isASCII
                    &&
                    (CharacterSet.alphanumerics
                        .contains(scalar) || scalar == "_" || scalar == ".")
            }
    }
}

extension DiagnosticLog.Level {
    var osLogType: OSLogType {
        switch self {
        case .info: .info
        case .notice: .default
        case .error: .error
        }
    }
}
