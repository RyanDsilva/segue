import Foundation

public extension SetlistStore {
    /// Why `replaceEntries(_:in:)` should not write setlist `id` now, checked against the
    /// file on disk: it was deleted (in Segue or from the folder) or became read-only (saved
    /// by a newer Segue) since it was loaded. Nil when it can be saved. The show-end review
    /// disables Save with this reason (2-interfaces.md, open question 17).
    func saveBlocker(for id: SetlistID) -> SetlistError? {
        guard let root else { return .notLoaded }
        guard let stored = setlists[id] else { return .setlistNotFound(id) }
        if let reason = stored.setlist.readOnly {
            return .readOnly(id, reason)
        }
        let url = Self.url(root: root, slug: stored.slug)
        guard fileSystem.fileExists(at: url) else { return .setlistNotFound(id) }
        if let data = try? fileSystem.readData(at: url),
           let onDisk = try? Self.decode(data)
        {
            if onDisk.id != id {
                return .setlistNotFound(id)
            }
            if let reason = onDisk.readOnly {
                return .readOnly(id, reason)
            }
        }
        return nil
    }
}
