import Foundation
import Synchronization

/// One run's hold on a show: an exclusive advisory lock (`flock`) on
/// `shows/<ulid>.show.lock`, so a show can be performed, resumed or auto-closed by only one
/// Segue at a time (a second window or process gets `ShowError.claimedElsewhere`).
///
/// The OS drops the lock when the process dies, so a crashed run never blocks its own
/// resume. Locks are per open file, so two claims in one process exclude each other too.
public final class ShowClaim: Sendable {
    /// The lock file's descriptor while held.
    private let descriptor: Mutex<Int32?>
    let url: URL

    private init(descriptor: Int32, url: URL) {
        self.descriptor = Mutex(descriptor)
        self.url = url
    }

    deinit {
        release()
    }

    /// Takes the lock at `url` (creating the file); nil when another claim holds it.
    static func acquire(at url: URL) throws -> ShowClaim? {
        let path = url.path(percentEncoded: false)
        let fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else {
            throw ShowError.writeFailed("could not open \(url.lastPathComponent) (errno \(errno))")
        }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            let code = errno
            close(fd)
            if code == EWOULDBLOCK {
                return nil
            }
            throw ShowError.writeFailed("could not lock \(url.lastPathComponent) (errno \(code))")
        }
        return ShowClaim(descriptor: fd, url: url)
    }

    /// Whether the lock is still held by this claim.
    public var isHeld: Bool {
        descriptor.withLock { $0 != nil }
    }

    /// Lets go of the show. With `removingFile` (the show has ended) the lock file is
    /// deleted first, while still held. Idempotent.
    public func release(removingFile: Bool = false) {
        descriptor.withLock { fd in
            guard let held = fd else { return }
            if removingFile {
                unlink(url.path(percentEncoded: false))
            }
            flock(held, LOCK_UN)
            close(held)
            fd = nil
        }
    }
}
