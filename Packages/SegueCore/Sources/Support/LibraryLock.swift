import Foundation

/// An exclusive advisory lock on a library, held for as long as a copy of Segue has the
/// library open. The Personal and App Store flavors have separate bundle IDs, so the
/// single-instance guard no longer keeps them apart; this lock does (WS1 4.8g, B-2).
///
/// The lock file is `library.lock` in the library's state directory (P9-6 5.2), outside the
/// library folder and keyed by its library ID, in the app group both flavors share. A file
/// sync service therefore never uploads it, and it never depends on whether a synced or
/// network folder honours `flock`.
///
/// `flock(LOCK_EX | LOCK_NB)` on a descriptor this object owns: the kernel releases it when
/// the descriptor closes, the process exits or crashes, so there is no stale lock to clean
/// up. `flock` locks belong to the open file description, so two `LibraryLock`s in one
/// process exclude each other exactly like two processes do. It is advisory, and per Mac:
/// it never excludes another Mac.
public final class LibraryLock: Sendable {
    /// Why the lock could not be taken.
    public enum Failure: Error, Equatable, LocalizedError {
        /// Another copy of Segue holds it.
        case inUse
        /// The lock file could not be opened or locked (errno).
        case unavailable(Int32)

        public var errorDescription: String? {
            switch self {
            case .inUse:
                "This library is open in another copy of Segue."
            case let .unavailable(code):
                "The library lock could not be taken (\(String(cString: strerror(code))))."
            }
        }
    }

    /// The locked file.
    public let url: URL
    private let descriptor: Int32

    /// Takes the lock of the library whose state directory is `state`, creating the
    /// directory and the lock file as needed. Throws `Failure.inUse` when another holder has
    /// it, `Failure.unavailable` when the file cannot be opened or locked, or the file
    /// system's error for the directory.
    public init(state: LibraryStateDirectory) throws {
        url = state.lockURL
        try FileManager.default.createDirectory(at: state.url, withIntermediateDirectories: true)
        let fd = open(url.path(percentEncoded: false), O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw Failure.unavailable(errno) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(fd)
            throw code == EWOULDBLOCK ? Failure.inUse : Failure.unavailable(code)
        }
        descriptor = fd
    }

    deinit {
        // Closing the descriptor releases the lock.
        close(descriptor)
    }
}
