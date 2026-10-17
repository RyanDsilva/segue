import Foundation

/// File attributes Core cares about (change detection for the index).
public struct FileAttributes: Sendable, Equatable {
    public var modificationDate: Date
    public var size: Int

    public init(modificationDate: Date, size: Int) {
        self.modificationDate = modificationDate
        self.size = size
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
    /// Writes atomically (temp file + rename) through `NSFileCoordinator`.
    func writeAtomically(_ data: Data, to url: URL) throws
    /// Removes the file or directory at `url` (coordinated).
    func removeItem(at url: URL) throws
    /// Moves/renames `source` to `destination` (coordinated). Fails if destination exists.
    func moveItem(from source: URL, to destination: URL) throws
    /// Modification date and size of the file at `url`.
    func attributes(at url: URL) throws -> FileAttributes
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
        try FileManager.default
            .contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles],
            )
            .sorted { $0.path < $1.path }
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
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return FileAttributes(
            modificationDate: values.contentModificationDate ?? .distantPast,
            size: values.fileSize ?? 0,
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
