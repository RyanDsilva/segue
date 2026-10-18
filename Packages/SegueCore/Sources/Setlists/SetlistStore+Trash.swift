import Foundation
import Library
import Support

// Setlists go to the Trash and come back from the receipt; `replace` writes an undo
// snapshot back (WS2a 3.3, 3.9).

public extension SetlistStore {
    /// Moves the setlist's file to the Trash and forgets the setlist. Shows that ran it keep
    /// their own snapshot. A file already gone from disk is simply forgotten (empty receipt).
    @discardableResult
    func delete(_ id: SetlistID) throws -> TrashReceipt {
        guard let root else { throw SetlistError.notLoaded }
        guard let stored = setlists[id] else { throw SetlistError.setlistNotFound(id) }
        let url = Self.url(root: root, slug: stored.slug)
        var receipt = TrashReceipt()
        if fileSystem.fileExists(at: url) {
            try receipt.items.append(TrashedItem(
                original: url,
                trashed: fileSystem.trashItem(at: url),
            ))
        }
        setlists[id] = nil
        return receipt
    }

    /// Puts a setlist deleted with `delete` back from `receipt` and loads it again; under the
    /// next free slug when its file name was taken meanwhile. Returns nil when the file
    /// holds no loadable setlist, or one whose ID is already loaded (the duplicate-ID rule of
    /// `load`: the file is back on disk but not listed). Throws `TrashRestoreError` when the
    /// file is no longer in the Trash.
    @discardableResult
    func restore(_ receipt: TrashReceipt) throws -> Setlist? {
        guard let root else { throw SetlistError.notLoaded }
        let suffix = LibraryRoot.setlistSuffix
        guard let item = receipt.items
            .first(where: { $0.original.lastPathComponent.hasSuffix(suffix) })
        else { return nil }
        let oldSlug = String(item.original.lastPathComponent.dropLast(suffix.count))
        let used = Set(setlists.values.map(\.slug))
        let slug = Slug.unique(oldSlug) { candidate in
            used.contains(candidate) || fileSystem.fileExists(at: Self.url(
                root: root,
                slug: candidate,
            ))
        }
        let url = Self.url(root: root, slug: slug)
        try TrashReceipt(items: [item]).restore(using: fileSystem) { _ in url }
        guard let setlist = try? Self.decode(fileSystem.readData(at: url)),
              setlists[setlist.id] == nil
        else { return nil }
        setlists[setlist.id] = Stored(setlist: setlist, slug: slug)
        return setlist
    }

    /// Writes `setlist` back whole (an undo snapshot): same file, `updatedAt` stamped, written
    /// at the current schema version. Refused for read-only setlists and unknown IDs.
    @discardableResult
    func replace(_ setlist: Setlist) throws -> Setlist {
        try mutateSetlist(setlist.id) { current in
            let readOnly = current.readOnly
            current = setlist
            current.readOnly = readOnly
        }
    }

    /// Loads every setlist file again (picking up edits made in other apps); like `load`.
    @discardableResult
    func reloadFromDisk() throws -> [SetlistLoadIssue] {
        guard let root else { throw SetlistError.notLoaded }
        return try load(root: root)
    }

    /// The file of setlist `id` (`setlists/<slug>.setlist.json`), or nil when it is not
    /// loaded. The file itself may be gone from disk.
    func fileURL(for id: SetlistID) -> URL? {
        guard let root, let stored = setlists[id] else { return nil }
        return Self.url(root: root, slug: stored.slug)
    }
}
