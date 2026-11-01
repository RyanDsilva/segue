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
        let state = LibraryStateLocation(base: folder).directory(for: TestLibrary.libraryID)

        do {
            let first = try LibraryLock(state: state)
            #expect(FileManager.default.fileExists(atPath: first.url.path(percentEncoded: false)))
            #expect(throws: LibraryLock.Failure.inUse) {
                _ = try LibraryLock(state: state)
            }
            withExtendedLifetime(first) {}
        }

        // The first lock is released with its descriptor.
        let second = try LibraryLock(state: state)
        #expect(second.url == state.lockURL)
    }
}
