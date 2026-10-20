import CryptoKit
import Foundation
import ModelPort

/// Streams a file's bytes into the digest its manifest entry pins: SHA256 when the entry has
/// one (every curated file), else the Hub's git blob id (SHA1 over `blob <size>\0` + bytes).
struct FileDigest {
    private enum Kind {
        case sha256(SHA256, expected: String)
        case gitBlob(Insecure.SHA1, expected: String)
    }

    private var kind: Kind
    private let file: LocalModelManifest.File

    /// Nil when the entry pins no digest (the store refuses such a manifest up front).
    init?(for file: LocalModelManifest.File) {
        self.file = file
        if let sha256 = file.sha256 {
            kind = .sha256(SHA256(), expected: sha256.lowercased())
        } else if let blob = file.gitBlobID {
            var hasher = Insecure.SHA1()
            hasher.update(data: Data("blob \(file.size)\u{0}".utf8))
            kind = .gitBlob(hasher, expected: blob.lowercased())
        } else {
            return nil
        }
    }

    mutating func update(_ data: Data) {
        switch kind {
        case .sha256(var hasher, let expected):
            hasher.update(data: data)
            kind = .sha256(hasher, expected: expected)
        case .gitBlob(var hasher, let expected):
            hasher.update(data: data)
            kind = .gitBlob(hasher, expected: expected)
        }
    }

    /// Whether the bytes seen so far are exactly the pinned file.
    func matches() -> Bool {
        switch kind {
        case let .sha256(hasher, expected):
            Self.hex(hasher.finalize()) == expected
        case let .gitBlob(hasher, expected):
            Self.hex(hasher.finalize()) == expected
        }
    }

    /// Hashes the first `length` bytes of the file at `url` (8 MB reads).
    mutating func update(contentsOf url: URL, length: Int64) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var remaining = length
        while remaining > 0 {
            let chunk = Int(min(remaining, 8 << 20))
            guard let data = try handle.read(upToCount: chunk), !data.isEmpty else { break }
            update(data)
            remaining -= Int64(data.count)
        }
    }

    /// Whether the file at `url` is exactly `file` (size, then digest).
    static func verify(_ url: URL, against file: LocalModelManifest.File) -> Bool {
        guard let size = fileSize(url), size == file.size, var digest = Self(for: file) else {
            return false
        }
        do {
            try digest.update(contentsOf: url, length: size)
        } catch {
            return false
        }
        return digest.matches()
    }

    static func fileSize(_ url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }

    private static func hex(_ digest: some Sequence<UInt8>) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// The cross-flavour download lock (spec 5.3): an exclusive `flock` on a file in the shared
/// store, so the Personal and App Store builds never download at once. The holder writes the
/// model id into the file so the other flavour can say which model is on its way.
final class DownloadLock: @unchecked Sendable {
    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }

    /// Takes the lock without waiting, or returns nil when another process (or another
    /// download in this one) holds it.
    static func acquire(at url: URL, modelID: String) -> DownloadLock? {
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        ftruncate(descriptor, 0)
        let bytes = Array(modelID.utf8)
        _ = bytes.withUnsafeBytes { pwrite(descriptor, $0.baseAddress, $0.count, 0) }
        return DownloadLock(descriptor: descriptor)
    }

    /// The model another process is downloading, or nil when nobody holds the lock.
    static func holder(at url: URL) -> String? {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        if flock(descriptor, LOCK_SH | LOCK_NB) == 0 {
            flock(descriptor, LOCK_UN)
            return nil
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
