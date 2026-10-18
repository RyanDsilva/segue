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
    /// Removes the file or directory at `url` (coordinated). Never used for user data:
    /// songs, setlists and shows go to the Trash (`trashItem`).
    func removeItem(at url: URL) throws
    /// Moves the item at `url` to the Trash (coordinated) and returns its new URL there.
    /// Throws `FileSystemError.trashUnavailable` when the volume has no Trash; it never
    /// falls back to removing the item.
    func trashItem(at url: URL) throws -> URL
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
public enum FileSystemError: Error, Equatable, LocalizedError {
    case coordinationFailed(URL)
    /// The item's volume has no Trash (some network volumes), so nothing was deleted.
    case trashUnavailable(URL)

    public var errorDescription: String? {
        switch self {
        case let .coordinationFailed(url):
            "“\(url.lastPathComponent)” is busy in another app. Try again."
        case .trashUnavailable:
            "This volume has no Trash, so Segue did not delete it."
        }
    }
}

/// Where `LiveFileSystem.trashItem(at:)` puts things.
public enum TrashLocation: Sendable, Equatable {
    /// The user's Trash (`FileManager.trashItem`): Finder's Put Back works.
    case system
    /// A plain folder, created on demand. Tests use it so they never fill the user's Trash;
    /// E2E runs pass it with `-SegueTrashPath`.
    case directory(URL)
}

/// `FileSystem` backed by `FileManager` and `NSFileCoordinator`.
public struct LiveFileSystem: FileSystem {
    /// Where trashed items go.
    public let trash: TrashLocation

    public init(trash: TrashLocation = .system) {
        self.trash = trash
    }

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

    public func trashItem(at url: URL) throws -> URL {
        switch trash {
        case .system:
            return try coordinate { coordinator, errorPointer in
                var result: Result<URL, any Error> = .failure(
                    FileSystemError.coordinationFailed(url),
                )
                coordinator.coordinate(
                    writingItemAt: url,
                    options: .forDeleting,
                    error: errorPointer,
                ) { actual in
                    result = Result {
                        var resulting: NSURL?
                        do {
                            try FileManager.default.trashItem(
                                at: actual,
                                resultingItemURL: &resulting,
                            )
                        } catch let error as CocoaError where error.code == .featureUnsupported {
                            throw FileSystemError.trashUnavailable(url)
                        }
                        guard let resulting = resulting as URL? else {
                            throw FileSystemError.trashUnavailable(url)
                        }
                        return resulting
                    }
                }
                return try result.get()
            }
        case let .directory(folder):
            try createDirectory(at: folder)
            let destination = Self.freeName(for: url.lastPathComponent, in: folder) { candidate in
                fileExists(at: candidate)
            }
            try moveItem(from: url, to: destination)
            return destination
        }
    }

    /// `folder/name`, or `folder/<stem> 2.<rest>`, `... 3`, ... when taken (the stem ends
    /// at the first dot, so `song.segue.json` becomes `song 2.segue.json`).
    static func freeName(
        for name: String,
        in folder: URL,
        isTaken: (URL) -> Bool,
    ) -> URL {
        let first = folder.appending(path: name, directoryHint: .notDirectory)
        guard isTaken(first) else { return first }
        let dot = name.firstIndex(of: ".").flatMap { $0 == name.startIndex ? nil : $0 }
        let stem = dot.map { String(name[..<$0]) } ?? name
        let rest = dot.map { String(name[$0...]) } ?? ""
        var counter = 2
        while true {
            let candidate = folder.appending(
                path: "\(stem) \(counter)\(rest)",
                directoryHint: .notDirectory,
            )
            if !isTaken(candidate) {
                return candidate
            }
            counter += 1
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
