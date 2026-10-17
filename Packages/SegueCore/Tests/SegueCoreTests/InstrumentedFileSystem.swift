import Foundation
import Library
import Support
import Synchronization

/// Real IO (`LiveFileSystem`) with two test hooks: it counts reads per file name, and it can
/// fail chosen operations, to reproduce disk errors the OS won't produce on demand.
final class InstrumentedFileSystem: FileSystem {
    enum Operation: Sendable {
        case read
        case write
        case remove
    }

    struct InjectedFailure: Error, LocalizedError {
        var errorDescription: String? {
            "Injected failure"
        }
    }

    private struct State {
        var reads: [String: Int] = [:]
        var failing: [(Operation, String)] = []
        var slowWrites: [(String, TimeInterval)] = []
    }

    private let live = LiveFileSystem()
    private let state = Mutex(State())

    /// Reads so far, keyed by file name.
    var reads: [String: Int] {
        state.withLock { $0.reads }
    }

    /// Total reads so far.
    var readCount: Int {
        reads.values.reduce(0, +)
    }

    func resetCounts() {
        state.withLock { $0.reads = [:] }
    }

    /// Makes `operation` fail for files whose name ends with `suffix` until `heal()`.
    func fail(_ operation: Operation, suffix: String) {
        state.withLock { $0.failing.append((operation, suffix)) }
    }

    func heal() {
        state.withLock { $0.failing = [] }
    }

    /// Makes writes of files whose name ends with `suffix` take `seconds` longer.
    func slowDown(writes suffix: String, by seconds: TimeInterval) {
        state.withLock { $0.slowWrites.append((suffix, seconds)) }
    }

    private func check(_ operation: Operation, _ url: URL) throws {
        let name = url.lastPathComponent
        let fails = state.withLock { state in
            state.failing.contains { $0.0 == operation && name.hasSuffix($0.1) }
        }
        if fails {
            throw InjectedFailure()
        }
    }

    func fileExists(at url: URL) -> Bool {
        live.fileExists(at: url)
    }

    func directoryExists(at url: URL) -> Bool {
        live.directoryExists(at: url)
    }

    func createDirectory(at url: URL) throws {
        try live.createDirectory(at: url)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try live.contentsOfDirectory(at: url)
    }

    func readData(at url: URL) throws -> Data {
        try check(.read, url)
        state.withLock { $0.reads[url.lastPathComponent, default: 0] += 1 }
        return try live.readData(at: url)
    }

    func writeAtomically(_ data: Data, to url: URL) throws {
        try check(.write, url)
        let name = url.lastPathComponent
        let delay = state.withLock { state in
            state.slowWrites.first { name.hasSuffix($0.0) }?.1
        }
        if let delay {
            Thread.sleep(forTimeInterval: delay)
        }
        try live.writeAtomically(data, to: url)
    }

    func removeItem(at url: URL) throws {
        try check(.remove, url)
        try live.removeItem(at: url)
    }

    func moveItem(from source: URL, to destination: URL) throws {
        try live.moveItem(from: source, to: destination)
    }

    func attributes(at url: URL) throws -> FileAttributes {
        try live.attributes(at: url)
    }
}

extension TestLibrary {
    /// A new `LibraryStore` on this folder that does its IO through `fileSystem`.
    func openStore(fileSystem: any FileSystem) async throws -> LibraryStore {
        let store = LibraryStore(fileSystem: fileSystem, clock: clock, ids: ids)
        try await store.open(root: root)
        return store
    }

    func writeBytes(_ bytes: some Sequence<UInt8>, to relativePath: String) throws {
        let target = url(relativePath)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data(bytes).write(to: target)
    }

    func bytes(_ relativePath: String) throws -> Data {
        try Data(contentsOf: url(relativePath))
    }

    /// Sets POSIX permissions (e.g. `0o000` for unreadable, `0o555` for a read-only folder).
    func setPermissions(_ mode: Int, of relativePath: String) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: mode],
            ofItemAtPath: url(relativePath).path(percentEncoded: false),
        )
    }
}
