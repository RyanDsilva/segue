import Foundation
import Support

/// Errors raised by `LibraryArchive` beyond the underlying file-system errors.
public enum LibraryArchiveError: Error, Equatable {
    /// The library folder does not exist (or is not a folder).
    case libraryMissing(URL)
    /// The system did not produce a zip of the staged folder.
    case zipFailed
}

/// Exports a library as one zip (WS2b 4.8, B-23): a single top folder
/// `Segue Library YYYY-MM-DD/` holding `songs/`, `setlists/`, `shows/`, `timings/` and
/// `filters/` (saved smart filters, phase 3) as they are on disk. Excluded: `.segue/` (the
/// rebuildable index and app-private state), hidden files such as `.DS_Store`, and anything
/// else at the library root (a user's own files there are theirs, not Segue's). Empty or
/// missing folders are simply absent.
///
/// Mechanism (no third-party code, sandbox-safe): the folders are copied through the
/// injected `FileSystem` into a staging folder under `temporaryDirectory`, the system zips
/// the staged folder (`NSFileCoordinator` with `.forUploading`), and the zip is written to
/// the destination atomically, so a failure never leaves a partial file there. The staging
/// folder is always removed.
///
/// Synchronous and `Sendable`: callers run it off the main actor.
public struct LibraryArchive: Sendable {
    /// The library folders an archive carries, in archive order.
    public static let includedFolders = ["songs", "setlists", "shows", "timings", "filters"]

    private let fileSystem: any FileSystem
    private let clock: any Clock
    private let timeZone: TimeZone
    private let temporaryDirectory: URL

    /// - Parameters:
    ///   - timeZone: the zone whose local date names the archive (default: the current one).
    ///   - temporaryDirectory: where the staging folder is made (default: the process's
    ///     temporary directory, which is inside the container when sandboxed).
    public init(
        fileSystem: any FileSystem,
        clock: any Clock,
        timeZone: TimeZone = .current,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
    ) {
        self.fileSystem = fileSystem
        self.clock = clock
        self.timeZone = timeZone
        self.temporaryDirectory = temporaryDirectory
    }

    /// `Segue Library YYYY-MM-DD` for the clock's current local date: the archive's top
    /// folder name.
    public var folderName: String {
        "Segue Library \(CalendarDay(clock.now(), timeZone: timeZone))"
    }

    /// `Segue Library YYYY-MM-DD.zip`: the save panel's default file name.
    public var defaultFileName: String {
        folderName + ".zip"
    }

    /// Writes the archive of the library at `root` to `destination` (replacing a file
    /// already there, which the caller confirmed). Throws without leaving anything at
    /// `destination` when any step fails; the staging folder is removed either way.
    public func export(root: LibraryRoot, to destination: URL) throws {
        guard fileSystem.directoryExists(at: root.url) else {
            throw LibraryArchiveError.libraryMissing(root.url)
        }
        let staging = temporaryDirectory.appending(
            path: "SegueArchive-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        defer { try? fileSystem.removeItem(at: staging) }
        let top = staging.appending(path: folderName, directoryHint: .isDirectory)
        try fileSystem.createDirectory(at: top)
        for folder in Self.includedFolders {
            let source = root.url.appending(path: folder, directoryHint: .isDirectory)
            guard fileSystem.directoryExists(at: source) else { continue }
            try copyTree(from: source, to: top.appending(path: folder, directoryHint: .isDirectory))
        }
        let zip = try Self.zip(folder: top)
        try fileSystem.writeAtomically(zip, to: destination)
    }

    /// Copies the visible contents of `source` into a new folder `destination`, recursing
    /// into subfolders. Folders that end up empty are not created.
    private func copyTree(from source: URL, to destination: URL) throws {
        let entries = try fileSystem.contentsOfDirectory(at: source)
        guard !entries.isEmpty else { return }
        for entry in entries {
            let target = destination.appending(path: entry.lastPathComponent)
            if fileSystem.directoryExists(at: entry) {
                try copyTree(from: entry, to: target)
            } else {
                let data = try fileSystem.readData(at: entry)
                try fileSystem.createDirectory(at: destination)
                try fileSystem.writeAtomically(data, to: target)
            }
        }
    }

    /// The bytes of a zip of `folder` (the folder itself is the zip's single top entry).
    private static func zip(folder: URL) throws -> Data {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Data, any Error> = .failure(LibraryArchiveError.zipFailed)
        coordinator.coordinate(
            readingItemAt: folder,
            options: .forUploading,
            error: &coordinationError,
        ) { zipURL in
            // The zip only lives for the duration of this block.
            result = Result { try Data(contentsOf: zipURL) }
        }
        if let coordinationError {
            throw coordinationError
        }
        return try result.get()
    }
}
