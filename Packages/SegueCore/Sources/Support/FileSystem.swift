import Foundation

/// File attributes Core cares about (change detection for the index).
public struct FileAttributes: Sendable, Equatable {
    public var modificationDate: Date
    public var size: Int
    /// When the file was created, if the volume records it (used to tell an original from a
    /// Finder duplicate).
    public var creationDate: Date?

    public init(modificationDate: Date, size: Int, creationDate: Date? = nil) {
        self.modificationDate = modificationDate
        self.size = size
        self.creationDate = creationDate
    }
}

/// All Core file IO goes through this protocol so the library root and IO strategy are
/// injectable. Tests use `LiveFileSystem` on a temp directory (real IO, not fakes).
///
/// Implementers may add methods as later phases need them; keep the protocol small.
public protocol FileSystem: Sendable {
    /// Whether anything exists at `url`.
    func fileExists(at url: URL) -> Bool
    /// Whether `url` exists and is a directory.
    func directoryExists(at url: URL) -> Bool
    /// Creates `url` and any missing parents. No-op if it already exists.
    func createDirectory(at url: URL) throws
    /// Non-recursive listing of `url`, excluding hidden files, sorted by path.
    func contentsOfDirectory(at url: URL) throws -> [URL]
    /// Reads the whole file (coordinated read).
    func readData(at url: URL) throws -> Data
    /// Reads several files inside `directory` under one coordinated read of the directory
    /// (per-file coordination costs about a millisecond each, which dominates a library scan).
    /// One result per URL, in order; a failure affects only its own file.
    func readFiles(_ urls: [URL], in directory: URL) -> [Result<Data, any Error>]
    /// Writes atomically (temp file + rename) through `NSFileCoordinator`.
    func writeAtomically(_ data: Data, to url: URL) throws
    /// Removes the file or directory at `url` (coordinated).
    func removeItem(at url: URL) throws
    /// Moves/renames `source` to `destination` (coordinated). Fails if destination exists.
    func moveItem(from source: URL, to destination: URL) throws
    /// Modification date and size of the file at `url`.
    func attributes(at url: URL) throws -> FileAttributes
}

public extension FileSystem {
    /// Default: one `readData(at:)` per file.
    func readFiles(_ urls: [URL], in _: URL) -> [Result<Data, any Error>] {
        urls.map { url in Result { try readData(at: url) } }
    }
}

/// Errors raised by `LiveFileSystem` beyond the underlying Foundation errors.
public enum FileSystemError: Error, Equatable {
    case coordinationFailed(URL)
}

/// `FileSystem` backed by `FileManager` and `NSFileCoordinator`.
public struct LiveFileSystem: FileSystem {
    public init() {}

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    public func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory,
        )
        return exists && isDirectory.boolValue
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        // No prefetched properties: callers stat what they need (`attributes(at:)`), and
        // prefetching for every file in a large library costs more than the listing itself.
        try FileManager.default
            .contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [],
                options: [.skipsHiddenFiles],
            )
            .map { ($0.path(percentEncoded: false), $0) }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
    }

    public func readData(at url: URL) throws -> Data {
        try coordinate { coordinator, errorPointer in
            var result: Result<Data, any Error> = .failure(FileSystemError.coordinationFailed(url))
            coordinator.coordinate(readingItemAt: url, options: [], error: errorPointer) { actual in
                result = Result { try Data(contentsOf: actual) }
            }
            return try result.get()
        }
    }

    public func readFiles(_ urls: [URL], in directory: URL) -> [Result<Data, any Error>] {
        let base = directory.standardizedFileURL.path(percentEncoded: false)
        let prefix = base.hasSuffix("/") ? base : base + "/"
        var results: [Result<Data, any Error>] = urls.map { url in
            .failure(FileSystemError.coordinationFailed(url))
        }
        do {
            try coordinate { coordinator, errorPointer in
                coordinator.coordinate(
                    readingItemAt: directory,
                    options: [],
                    error: errorPointer,
                ) { actual in
                    for (index, url) in urls.enumerated() {
                        let path = url.standardizedFileURL.path(percentEncoded: false)
                        // Files outside `directory` fall back to their own coordinated read.
                        guard path.hasPrefix(prefix) else {
                            results[index] = Result { try readData(at: url) }
                            continue
                        }
                        let target = actual.appending(path: String(path.dropFirst(prefix.count)))
                        results[index] = Result { try Data(contentsOf: target) }
                    }
                }
            }
        } catch {
            return urls.map { _ in .failure(error) }
        }
        return results
    }

    public func writeAtomically(_ data: Data, to url: URL) throws {
        try coordinate { coordinator, errorPointer in
            var result: Result<Void, any Error> = .failure(FileSystemError.coordinationFailed(url))
            coordinator.coordinate(
                writingItemAt: url,
                options: .forReplacing,
                error: errorPointer,
            ) { actual in
                // `.atomic` writes to a temporary file in the same directory, then renames.
                result = Result { try data.write(to: actual, options: .atomic) }
            }
            try result.get()
        }
    }

    public func removeItem(at url: URL) throws {
        try coordinate { coordinator, errorPointer in
            var result: Result<Void, any Error> = .failure(FileSystemError.coordinationFailed(url))
            coordinator.coordinate(
                writingItemAt: url,
                options: .forDeleting,
                error: errorPointer,
            ) { actual in
                result = Result { try FileManager.default.removeItem(at: actual) }
            }
            try result.get()
        }
    }

    public func moveItem(from source: URL, to destination: URL) throws {
        try coordinate { coordinator, errorPointer in
            var result: Result<Void, any Error> = .failure(
                FileSystemError.coordinationFailed(source),
            )
            coordinator.coordinate(
                writingItemAt: source,
                options: .forMoving,
                writingItemAt: destination,
                options: .forReplacing,
                error: errorPointer,
            ) { actualSource, actualDestination in
                result = Result {
                    try FileManager.default.moveItem(at: actualSource, to: actualDestination)
                }
            }
            try result.get()
        }
    }

    public func attributes(at url: URL) throws -> FileAttributes {
        // A fresh URL each time: `URL` caches resource values, which would hide changes.
        let fresh = URL(fileURLWithPath: url.path(percentEncoded: false))
        let values = try fresh.resourceValues(forKeys: [
            .contentModificationDateKey, .fileSizeKey, .creationDateKey,
        ])
        return FileAttributes(
            modificationDate: values.contentModificationDate ?? .distantPast,
            size: values.fileSize ?? 0,
            creationDate: values.creationDate,
        )
    }

    /// Runs `body` with a fresh coordinator and rethrows any coordination error.
    private func coordinate<T>(
        _ body: (NSFileCoordinator, NSErrorPointer) throws -> T,
    ) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        let value = try body(coordinator, &coordinationError)
        if let coordinationError {
            throw coordinationError
        }
        return value
    }
}
