import Foundation
import Library
import Observation
import Setlists
import Support

/// Setlists as the main window sees them: the list, the selection and the edit actions.
/// Every mutation goes through `SetlistStore` (which writes to disk) and adopts the returned
/// value, so the UI never shows unsaved state.
@MainActor
@Observable
public final class SetlistsViewModel {
    public private(set) var setlists: [Setlist] = []
    public var selection: SetlistID?
    /// The last failure, shown as a dismissible banner.
    public var errorMessage: String?
    /// Setlist files that could not be loaded (reported, never deleted).
    public internal(set) var loadIssues: [SetlistLoadIssue]

    let store: SetlistStore
    /// The main window's undo manager (Edit > Undo).
    @ObservationIgnored weak var undoManager: UndoManager?
    /// Undo targets of Move Setlist to Trash, one per setlist.
    let trashTargets = UndoTargets<SetlistID>()
    /// Undo targets of builder edits, one per setlist, so one setlist's actions can be
    /// dropped (an external edit, a failed undo) without touching the others (3.9).
    let editTargets = UndoTargets<SetlistID>()
    /// Each setlist as Segue last loaded or wrote it: a reload that finds another value was
    /// edited in another app, and its undo actions go (B-16).
    var known: [SetlistID: Setlist] = [:]
    /// Undo and redo file work, run in order.
    var undoWork: Task<Void, Never>?

    public init(store: SetlistStore, loadIssues: [SetlistLoadIssue] = []) {
        self.store = store
        self.loadIssues = loadIssues
    }

    /// The selected setlist, if any.
    public var selected: Setlist? {
        guard let selection else { return nil }
        return setlists.first { $0.id == selection }
    }

    public func reload() async {
        setlists = await store.all()
        known = Dictionary(setlists.map { ($0.id, $0) }) { first, _ in first }
        if let selection, !setlists.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }

    /// Creates an empty setlist named `name` (trimmed; blank names are refused) and selects it.
    @discardableResult
    public func create(name: String) async -> Setlist? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let created = await mutate { store in
            try await store.create(name: trimmed)
        } then: { setlist in
            self.selection = setlist.id
        }
        if let created {
            registerCreationUndo(created.id, actionName: "New Setlist")
        }
        return created
    }

    /// Appends `songID` to setlist `id` (repeats allowed); returns whether it was saved.
    @discardableResult
    public func add(_ songID: SongID, to id: SetlistID) async -> Bool {
        await mutate(undo: (id, "Add Song")) { store in
            try await store.addSong(songID, to: id)
        } != nil
    }

    /// Drag reorder (`onMove`).
    public func move(in id: SetlistID, fromOffsets source: IndexSet, toOffset destination: Int)
        async
    {
        // Reorder locally first so the row doesn't snap back while the write is in flight.
        if let index = setlists.firstIndex(where: { $0.id == id }) {
            setlists[index].entries.move(fromOffsets: source, toOffset: destination)
        }
        await mutate(undo: (id, "Move Song")) { store in
            try await store.move(in: id, fromOffsets: source, toOffset: destination)
        }
    }

    /// Removes entries (`onDelete`, context menu).
    public func remove(in id: SetlistID, atOffsets offsets: IndexSet) async {
        await mutate(undo: (id, offsets.count == 1 ? "Remove Song" : "Remove Songs")) { store in
            try await store.remove(in: id, atOffsets: offsets)
        }
    }

    /// Renames setlist `id` (blank names are refused).
    public func rename(_ id: SetlistID, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await mutate(undo: (id, "Rename Setlist")) { store in
            try await store.rename(id, to: trimmed)
        }
    }

    /// Saves a copy of setlist `id` ("<name> copy") and selects it.
    @discardableResult
    public func duplicate(_ id: SetlistID) async -> Setlist? {
        let copy = await mutate { store in
            try await store.duplicate(id)
        } then: { copy in
            self.selection = copy.id
        }
        if let copy {
            registerCreationUndo(copy.id, actionName: "Duplicate Setlist")
        }
        return copy
    }

    /// Moves setlist `id`'s file to the Trash (shows that ran it keep their snapshot);
    /// Edit > Undo puts it back.
    public func delete(_ id: SetlistID) async {
        let pending = Task { await trash(id) }
        guard await pending.value != nil else { return }
        TrashUndo(
            manager: undoManager,
            target: trashTargets.target(for: id),
            actionName: "Move Setlist to Trash",
            trash: { [weak self] in await self?.trash(id) },
            restore: { [weak self] receipt in await self?.restore(receipt) ?? false },
        ).register(pending: pending)
    }

    /// The file of setlist `id`, for Show in Finder.
    public func fileURL(for id: SetlistID) async -> URL? {
        await store.fileURL(for: id)
    }

    private func trash(_ id: SetlistID) async -> TrashReceipt? {
        do {
            let receipt = try await store.delete(id)
            await reload()
            return receipt
        } catch {
            errorMessage = UserMessage.describe(error)
            await reload()
            return nil
        }
    }

    private func restore(_ receipt: TrashReceipt) async -> Bool {
        do {
            let restored = try await store.restore(receipt)
            await reload()
            guard let restored else {
                errorMessage = "Could not undo Move Setlist to Trash: the file could not be read."
                return false
            }
            selection = restored.id
            return true
        } catch {
            errorMessage = "Could not undo Move Setlist to Trash. " + UserMessage.describe(error)
            return false
        }
    }

    /// Inserts `songIDs` into setlist `id` at `offset` (nil appends): drag from the
    /// library column, or its `+` button.
    public func insert(_ songIDs: [SongID], into id: SetlistID, at offset: Int?) async {
        guard !songIDs.isEmpty else { return }
        await mutate(undo: (id, songIDs.count == 1 ? "Add Song" : "Add Songs")) { store in
            try await store.insertSongs(songIDs, into: id, at: offset)
        }
    }

    /// Saves one entry's overrides and note.
    public func updateEntry(_ entry: SetlistEntry, in id: SetlistID) async {
        await mutate(undo: (id, "Edit Song Settings")) { store in
            try await store.updateEntry(entry, in: id)
        }
    }

    /// Saves venue, date and target length.
    public func updateDetails(_ details: SetlistDetails, of id: SetlistID) async {
        await mutate(undo: (id, "Edit Details")) { store in
            try await store.updateDetails(details, of: id)
        }
    }

    /// The setlist with `id`, if loaded.
    public func setlist(_ id: SetlistID) -> Setlist? {
        setlists.first { $0.id == id }
    }

    /// Runs `operation` through the store, then reloads. With `undo`, the setlist's value
    /// before (from the store, not any optimistic local change) and after are registered
    /// as one undoable step named `undo.name`.
    @discardableResult
    private func mutate(
        undo: (id: SetlistID, name: String)? = nil,
        _ operation: (SetlistStore) async throws -> Setlist,
        then: (Setlist) -> Void = { _ in },
    ) async -> Setlist? {
        let before: Setlist? = if let undo {
            await store.setlist(id: undo.id)
        } else {
            nil
        }
        do {
            let updated = try await operation(store)
            await reload()
            then(updated)
            if let undo, let before {
                registerSnapshotUndo(undo.id, actionName: undo.name, before: before, after: updated)
            }
            return updated
        } catch {
            errorMessage = UserMessage.describe(error)
            await reload()
            return nil
        }
    }
}
