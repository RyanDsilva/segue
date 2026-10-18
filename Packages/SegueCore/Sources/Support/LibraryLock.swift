import Foundation

/// An exclusive advisory lock on a library folder (`<root>/.segue/library.lock`), held for
/// as long as a copy of Segue has the library open. The Personal and App Store flavors have
/// separate bundle IDs, so the single-instance guard no longer keeps them apart; this lock
/// does (WS1 4.8g, B-2).
///
/// `flock(LOCK_EX | LOCK_NB)` on a descriptor this object owns: the kernel releases it when
/// the descriptor closes, the process exits or crashes, so there is no stale lock to clean
/// up. `flock` locks belong to the open file description, so two `LibraryLock`s in one
/// process exclude each other exactly like two processes do. The file lives in the
/// user-selected folder, so it needs no extra entitlement. It is advisory: network or synced
/// folders that do not honour `flock` are not protected.
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

    /// Takes the lock on `root`, creating `<root>/.segue/` and the lock file as needed.
    /// Throws `Failure.inUse` when another holder has it, `Failure.unavailable` when the
    /// file cannot be opened or locked, or the file system's error for the folder.
    public init(root: LibraryRoot) throws {
        url = root.lockURL
        try FileManager.default.createDirectory(
            at: root.appDirectory,
            withIntermediateDirectories: true,
        )
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
