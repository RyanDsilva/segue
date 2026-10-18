import Foundation
import Support

// Delete Song (WS2a 3.3): songs go to the Trash, never `removeItem`, and come back from the
// receipt (Edit > Undo).

public extension LibraryStore {
    /// Moves song `id` to the Trash: the `.cho` first, then its sidecar. A sidecar left
    /// without its `.cho` is harmless (scans only list `.cho` files), whereas a `.cho` left
    /// without its sidecar would come back with a new ID, so a sidecar that fails to move is
    /// recorded in `TrashReceipt.leftBehind` and the song is still deleted. A `.cho` already
    /// gone from disk is simply forgotten. Read-only songs can be deleted. Plays stay in the
    /// show files.
    func deleteSong(id: SongID) throws -> TrashReceipt {
        let library = try openLibrary()
        guard let song = library.songs[id] else { throw LibraryError.songNotFound(id) }
        var receipt = TrashReceipt()
        let cho = library.files.choURL(slug: song.slug)
        if fileSystem.fileExists(at: cho) {
            try receipt.items.append(TrashedItem(
                original: cho,
                trashed: fileSystem.trashItem(at: cho),
            ))
        }
        let sidecar = library.files.sidecarURL(slug: song.slug)
        if fileSystem.fileExists(at: sidecar) {
            do {
                try receipt.items.append(TrashedItem(
                    original: sidecar,
                    trashed: fileSystem.trashItem(at: sidecar),
                ))
            } catch {
                receipt.leftBehind.append(sidecar)
            }
        }
        var changes = IndexChanges()
        changes.deletes = [id.description]
        try library.index.apply(changes)
        self.library?.songs[id] = nil
        return receipt
    }

    /// Puts a deleted song's files back from `receipt` and returns it (same ID, so setlists
    /// resolve it again); nil when the restored files hold no loadable song. When its old
    /// file name was taken meanwhile, both files come back under the next free slug
    /// (`<slug>-2`). Throws `TrashRestoreError` when a file is no longer in the Trash;
    /// nothing is moved then.
    @discardableResult
    func restoreSong(_ receipt: TrashReceipt) throws -> SongRecord? {
        let library = try openLibrary()
        let choSuffix = "." + LibraryRoot.songExtension
        guard let cho = receipt.items
            .first(where: { $0.original.lastPathComponent.hasSuffix(choSuffix) })
        else { return nil }
        let oldSlug = String(cho.original.lastPathComponent.dropLast(choSuffix.count))
        let usedSlugs = Set(library.songs.values.map(\.slug))
        let slug = Slug.unique(oldSlug) { candidate in
            usedSlugs.contains(candidate) || library.files.isTaken(slug: candidate)
        }
        try receipt.restore(using: fileSystem) { item in
            item.original.lastPathComponent.hasSuffix(choSuffix)
                ? library.files.choURL(slug: slug)
                : library.files.sidecarURL(slug: slug)
        }
        try refresh()
        return self.library?.songs.values.first { $0.slug == slug }?.record
    }
}
