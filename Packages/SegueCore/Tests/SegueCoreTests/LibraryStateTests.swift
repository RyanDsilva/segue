import Foundation
import Library
import Shows
import Support
import Testing

/// The library state outside the folder (P9-6 5.2): identity across moves and copies, the
/// lock in the state directory, and the TTL backstop. Real temp folders throughout.
struct LibraryStateTests {
    private func open(_ root: LibraryRoot, _ lib: TestLibrary) throws
        -> (LibraryState.Resolved, LibraryLock)
    {
        try LibraryState.open(
            root: root,
            location: lib.stateLocation,
            fileSystem: lib.fileSystem,
            clock: lib.clock,
            ids: lib.ids,
            lock: LibraryLock.init(state:),
        )
    }

    /// A sibling folder of the test library (removed with the test's other folders).
    private func sibling(_ lib: TestLibrary, _ name: String) -> URL {
        lib.root.url.deletingLastPathComponent()
            .appending(
                path: lib.root.url.lastPathComponent + "-" + name,
                directoryHint: .isDirectory,
            )
    }

    @Test
    func `the ID is stable across reopen and a move of the folder`() throws {
        let lib = try TestLibrary()
        let (first, _) = try open(lib.root, lib)
        let (reopened, _) = try open(lib.root, lib)
        #expect(reopened.identity == first.identity)
        #expect(!reopened.isCopy)

        let moved = sibling(lib, "moved")
        defer { try? FileManager.default.removeItem(at: moved) }
        try FileManager.default.moveItem(at: lib.root.url, to: moved)
        let movedRoot = LibraryRoot(url: moved)
        let (afterMove, _) = try open(movedRoot, lib)

        #expect(afterMove.identity == first.identity)
        #expect(!afterMove.isCopy)
        let record = try #require(
            LibraryStateRecord.read(afterMove.directory, fileSystem: lib.fileSystem),
        )
        #expect(record.lastRoot == moved.path(percentEncoded: false))
        #expect(record.lastOpened == lib.clock.now())
    }

    @Test
    func `a Finder copy gets its own ID and the original keeps its own`() throws {
        let lib = try TestLibrary()
        let copy = sibling(lib, "copy")
        defer { try? FileManager.default.removeItem(at: copy) }
        let original: LibraryState.Resolved
        let copied: LibraryState.Resolved
        do {
            // The original stays open while its copy is opened (as when switching to it).
            let (opened, originalLock) = try open(lib.root, lib)
            original = opened
            try FileManager.default.copyItem(at: lib.root.url, to: copy)
            (copied, _) = try open(LibraryRoot(url: copy), lib)
            withExtendedLifetime(originalLock) {}
        }

        #expect(copied.isCopy)
        #expect(copied.identity.id != original.identity.id)
        #expect(lib.trashedNames() == ["library.json"])
        let (originalAgain, _) = try open(lib.root, lib)
        #expect(originalAgain.identity == original.identity)
        #expect(!originalAgain.isCopy)
        // The re-keyed copy stays itself on its next open.
        let (copyAgain, _) = try open(LibraryRoot(url: copy), lib)
        #expect(copyAgain.identity == copied.identity)
        #expect(!copyAgain.isCopy)
    }

    @Test
    func `a renamed folder keeps its ID`() throws {
        let lib = try TestLibrary()
        let (first, _) = try open(lib.root, lib)
        let renamed = sibling(lib, "Renamed Library")
        defer { try? FileManager.default.removeItem(at: renamed) }
        try FileManager.default.moveItem(at: lib.root.url, to: renamed)

        let (afterRename, _) = try open(LibraryRoot(url: renamed), lib)

        #expect(afterRename.identity == first.identity)
        #expect(!afterRename.isCopy)
        #expect(lib.trashedNames().isEmpty)
    }

    /// A move to another volume: the folder arrives with a new file identifier and the
    /// original is gone (here a copy, then the original deleted, as Finder does across
    /// volumes). It keeps its ID.
    @Test
    func `a folder with a new identifier whose original is gone keeps its ID`() throws {
        let lib = try TestLibrary()
        let (first, _) = try open(lib.root, lib)
        let elsewhere = sibling(lib, "other-volume")
        defer { try? FileManager.default.removeItem(at: elsewhere) }
        try FileManager.default.copyItem(at: lib.root.url, to: elsewhere)
        try FileManager.default.removeItem(at: lib.root.url)
        let record = try #require(LibraryStateRecord.read(
            first.directory,
            fileSystem: lib.fileSystem,
        ))
        #expect(record.rootIdentifier != LibraryFolderReference.identifier(of: elsewhere))

        let (moved, _) = try open(LibraryRoot(url: elsewhere), lib)

        #expect(moved.identity == first.identity)
        #expect(!moved.isCopy)
        let after = try #require(LibraryStateRecord.read(
            moved.directory,
            fileSystem: lib.fileSystem,
        ))
        #expect(after.rootIdentifier == LibraryFolderReference.identifier(of: elsewhere))
    }

    @Test
    func `two locks on one state directory exclude each other`() throws {
        let lib = try TestLibrary()
        let (resolved, held) = try open(lib.root, lib)

        #expect(throws: LibraryLock.Failure.inUse) {
            _ = try LibraryLock(state: resolved.directory)
        }
        #expect(throws: LibraryLock.Failure.inUse) {
            _ = try open(lib.root, lib)
        }
        #expect(held.url == resolved.directory.lockURL)
        #expect(held.url.path(percentEncoded: false)
            .hasPrefix(lib.stateLocation.base.path(percentEncoded: false)))
    }

    @Test
    func `only library.json is written inside the folder`() throws {
        let lib = try TestLibrary()
        _ = try open(lib.root, lib)

        let names = try FileManager.default
            .contentsOfDirectory(atPath: lib.root.appDirectory.path(percentEncoded: false))
        #expect(names == ["library.json"])
    }

    @Test
    func `the TTL moves only stale state directories whose lock is free`() throws {
        let lib = try TestLibrary()
        let fresh = sibling(lib, "fresh")
        let busy = sibling(lib, "busy")
        defer {
            try? FileManager.default.removeItem(at: fresh)
            try? FileManager.default.removeItem(at: busy)
        }
        for url in [fresh, busy] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let (stale, _) = try open(lib.root, lib)
        let (stillOpen, busyLock) = try open(LibraryRoot(url: busy), lib)
        lib.clock.advance(by: LibraryState.staleInterval - 60)
        let (recent, _) = try open(LibraryRoot(url: fresh), lib)
        lib.clock.advance(by: 120)

        let pruned = LibraryState.pruneStale(
            location: lib.stateLocation,
            fileSystem: lib.fileSystem,
            clock: lib.clock,
        )

        #expect(pruned == [stale.identity.id])
        #expect(!lib.fileSystem.directoryExists(at: stale.directory.url))
        #expect(lib.fileSystem.directoryExists(at: stillOpen.directory.url))
        #expect(lib.fileSystem.directoryExists(at: recent.directory.url))
        #expect(lib.trashedNames() == [stale.identity.id.description])
        withExtendedLifetime(busyLock) {}
    }

    @Test
    func `the index and show claims are created only under the state directory`() async throws {
        let harness = try await ShowHarness()
        let lib = harness.lib
        let (setlist, _) = try await harness.makeSet(2)
        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        let id = await show.state.record.id

        #expect(lib.fileSystem.fileExists(at: lib.state.indexDatabase))
        #expect(lib.fileSystem.fileExists(at: lib.state.showLockURL(id.ulid)))
        #expect(await harness.shows.isClaimedElsewhere(id))
        let names = try FileManager.default
            .contentsOfDirectory(atPath: lib.root.appDirectory.path(percentEncoded: false))
        #expect(names == ["upgrades.json"])
        let shows = try FileManager.default
            .contentsOfDirectory(atPath: lib.root.showsDirectory.path(percentEncoded: false))
        #expect(shows.allSatisfy { $0.hasSuffix(LibraryRoot.showSuffix) })
        withExtendedLifetime(show) {}
    }

    @Test
    func `the upgrade deletes the old index and free locks but leaves a held one`() async throws {
        let lib = try TestLibrary()
        for name in ["index.sqlite", "index.sqlite-wal", "index.sqlite-shm", "library.lock"] {
            try lib.write("old", to: ".segue/\(name)")
        }
        try lib.write("", to: "shows/01JBZ6S0X5Q4M3N2P1R0S9T8V7.show.lock")
        let held = "shows/01JBZ6S0X5Q4M3N2P1R0S9T8V8.show.lock"
        try lib.write("", to: held)
        let fd = Darwin.open(lib.url(held).path(percentEncoded: false), O_RDWR)
        #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)

        _ = try await lib.openStore()

        // The index and the free locks are gone; nothing is recorded while one is held.
        #expect(try FileManager.default
            .contentsOfDirectory(atPath: lib.root.appDirectory.path(percentEncoded: false))
            .isEmpty)
        #expect(try FileManager.default
            .contentsOfDirectory(atPath: lib.root.showsDirectory.path(percentEncoded: false))
            == ["01JBZ6S0X5Q4M3N2P1R0S9T8V8.show.lock"])
        #expect(!LibraryUpgrade.state(root: lib.root, fileSystem: lib.fileSystem).stateMoved)

        // The older build lets go: the next open finishes the move and records it.
        close(fd)
        _ = try await lib.openStore()
        #expect(!lib.exists(held))
        #expect(LibraryUpgrade.state(root: lib.root, fileSystem: lib.fileSystem).stateMoved)
    }
}
