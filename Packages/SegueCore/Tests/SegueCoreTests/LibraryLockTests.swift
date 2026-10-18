import Foundation
import Support
import Testing

/// The cross-flavor library lock (WS1 4.8g) on a real temp folder: two `LibraryLock`s use
/// two file descriptors, and `flock` locks belong to the open file description, so this is
/// the same exclusion two copies of Segue get.
struct LibraryLockTests {
    @Test
    func `a held library lock refuses a second holder until it is released`() throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "LibraryLockTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = LibraryRoot(url: folder)

        do {
            let first = try LibraryLock(root: root)
            #expect(FileManager.default.fileExists(atPath: first.url.path(percentEncoded: false)))
            #expect(throws: LibraryLock.Failure.inUse) {
                _ = try LibraryLock(root: root)
            }
            withExtendedLifetime(first) {}
        }

        // The first lock is released with its descriptor.
        let second = try LibraryLock(root: root)
        #expect(second.url == root.lockURL)
    }
}
