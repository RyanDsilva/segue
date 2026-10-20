import Foundation
import ModelPort

/// The HTTP side of a model download (R66, R54): one file from
/// `<base>/<repo>/resolve/<revision>/<name>` into a partial file, resuming from the bytes
/// already there with a `Range` request, hashing as it writes. Headers are Segue's own on
/// every hop, the CDN redirect included: a fixed `Segue/<version>` User-Agent and an
/// `Accept-Language` of `*`, so neither the Mac's languages nor device details are sent.
/// Ephemeral session: no cookies, cache or credentials.
final class FileTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Outcome: Sendable, Equatable {
        case completed
        case cancelled
        case failed(ModelDownloadFailure)
    }

    /// The headers every request and redirect hop carries.
    static func headers(appVersion: String) -> [String: String] {
        ["User-Agent": "Segue/\(appVersion)", "Accept-Language": "*"]
    }

    private let lock = NSLock()
    private let url: URL
    private let partial: URL
    private let file: LocalModelManifest.File
    private let headers: [String: String]
    private let progress: @Sendable (Int64) -> Void
    private var handle: FileHandle?
    private var digest: FileDigest
    private var written: Int64 = 0
    private var failure: ModelDownloadFailure?
    private var continuation: CheckedContinuation<Outcome, Never>?
    private var task: URLSessionDataTask?
    private var cancelled = false

    /// - Parameters:
    ///   - progress: bytes of this file on disk so far (called from the session's queue).
    init?(
        url: URL,
        partial: URL,
        file: LocalModelManifest.File,
        appVersion: String,
        progress: @escaping @Sendable (Int64) -> Void,
    ) {
        guard let digest = FileDigest(for: file) else { return nil }
        self.url = url
        self.partial = partial
        self.file = file
        self.digest = digest
        headers = Self.headers(appVersion: appVersion)
        self.progress = progress
    }

    /// The ephemeral, header-clean session configuration (R54).
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpAdditionalHeaders = [:]
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60 * 24
        return configuration
    }

    /// Downloads the rest of the file into `partial`. `completed` means the partial file is
    /// exactly the pinned file (size and digest); a mismatch deletes it.
    func run() async -> Outcome {
        do {
            try prepareFile()
        } catch {
            return .failed(Self.failure(for: error))
        }
        if written == file.size {
            return finish()
        }
        if written > file.size {
            discardPartial()
            return .failed(.checksum)
        }
        let session = URLSession(
            configuration: Self.configuration(),
            delegate: self,
            delegateQueue: nil,
        )
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        apply(&request)
        if written > 0 {
            request.setValue("bytes=\(written)-", forHTTPHeaderField: "Range")
        }
        let outcome = await withCheckedContinuation { continuation in
            let start: Bool = lock.withLock {
                self.continuation = continuation
                guard !cancelled else { return false }
                task = session.dataTask(with: request)
                return true
            }
            if start {
                lock.withLock { task }?.resume()
            } else {
                complete(.cancelled)
            }
        }
        try? lock.withLock { handle }?.close()
        guard outcome == .completed else { return outcome }
        return finish()
    }

    /// Stops the transfer; the partial file stays for a later resume.
    func cancel() {
        let task: URLSessionDataTask? = lock.withLock {
            cancelled = true
            return self.task
        }
        task?.cancel()
        if task == nil {
            complete(.cancelled)
        }
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(
        _: URLSession,
        dataTask _: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void,
    ) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let accepted: Bool = lock.withLock {
            switch status {
            case 206 where written > 0:
                return true
            case 200:
                // A full body: start over (the server ignored the Range).
                do {
                    try handle?.truncate(atOffset: 0)
                    try handle?.seek(toOffset: 0)
                } catch {
                    failure = Self.failure(for: error)
                    return false
                }
                written = 0
                if let fresh = FileDigest(for: file) {
                    digest = fresh
                }
                return true
            default:
                failure = .network
                return false
            }
        }
        completionHandler(accepted ? .allow : .cancel)
    }

    func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let total: Int64? = lock.withLock {
            do {
                try handle?.write(contentsOf: data)
            } catch {
                failure = Self.failure(for: error)
                return nil
            }
            digest.update(data)
            written += Int64(data.count)
            return written > file.size ? nil : written
        }
        guard let total else {
            lock.withLock {
                if failure == nil {
                    failure = .checksum
                }
            }
            dataTask.cancel()
            return
        }
        progress(total)
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void,
    ) {
        // The CDN hop gets the same headers (and the same Range) as the first request.
        var next = request
        apply(&next)
        let written = lock.withLock { self.written }
        if written > 0 {
            next.setValue("bytes=\(written)-", forHTTPHeaderField: "Range")
        }
        completionHandler(next)
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        didCompleteWithError error: (any Error)?,
    ) {
        let outcome: Outcome = lock.withLock {
            if let failure {
                return .failed(failure)
            }
            if cancelled {
                return .cancelled
            }
            if error != nil {
                return .failed(.network)
            }
            return .completed
        }
        complete(outcome)
    }

    // MARK: - Private

    private func apply(_ request: inout URLRequest) {
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
    }

    private func complete(_ outcome: Outcome) {
        let continuation: CheckedContinuation<Outcome, Never>? = lock.withLock {
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(returning: outcome)
    }

    /// Opens (or creates) the partial file and hashes what is already there.
    private func prepareFile() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: partial.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        if !fileManager.fileExists(atPath: partial.path) {
            guard fileManager.createFile(atPath: partial.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let existing = FileDigest.fileSize(partial) ?? 0
        if existing > 0, existing <= file.size {
            try digest.update(contentsOf: partial, length: existing)
        }
        let handle = try FileHandle(forWritingTo: partial)
        try handle.seekToEnd()
        lock.withLock {
            self.handle = handle
            written = existing
        }
    }

    /// Size and digest check of the finished partial file.
    private func finish() -> Outcome {
        let (size, matches) = lock.withLock { (written, digest.matches()) }
        guard size == file.size, matches else {
            discardPartial()
            return .failed(.checksum)
        }
        return .completed
    }

    private func discardPartial() {
        try? FileManager.default.removeItem(at: partial)
    }

    static func failure(for error: any Error) -> ModelDownloadFailure {
        let nsError = error as NSError
        let outOfSpace = (nsError.domain == NSCocoaErrorDomain
            && nsError.code == NSFileWriteOutOfSpaceError)
            || (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOSPC))
        return outOfSpace ? .disk : .other
    }
}
