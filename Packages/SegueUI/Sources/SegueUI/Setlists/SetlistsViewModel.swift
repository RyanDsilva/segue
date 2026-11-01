import Foundation
import Library
import Observation
import Services
import Setlists
import Support

/// Setlists as the main window sees them: the list, the selection and the edit actions.
/// Every mutation goes through `SetlistStore` (which writes to disk) and adopts the returned
/// value, so the UI never shows unsaved state.
@MainActor
@Observable
public final class SetlistsViewModel {
    public private(set) var setlists: [Setlist] = []
    public var selection: SetlistID? {
        didSet {
            if selection != oldValue {
                arrangeSelection = ListSelection()
            }
        }
    }

    /// The builder's mode (Setlist > Pick Songs ⌘1 / Arrange Set ⌘2), shared by every
    /// setlist so switching setlists keeps it.
    public var builderMode: BuilderMode = .pick
    /// Arrange's selected rows (songs, breaks, medley headers and members) in the shown
    /// setlist.
    var arrangeSelection = ListSelection<SetlistItemID>()
    /// Medleys shown collapsed to one row of member chips (P9-3 6.2); in memory only.
    var collapsedMedleys: Set<SetlistItemID> = []
    /// The medley whose title field is being edited (double-click, Return on its header).
    var renamingMedley: SetlistItemID?
    /// The row Delete asked to remove, waiting for confirmation (R188).
    var pendingRemoval: PendingRemoval?
    /// The slot whose Arrange Sections sheet is open (P3-16).
    public var arranging: ArrangingSlot?
    /// The set composer at the end of the shown builder's set list (P8-5); ⌘L focuses it.
    public let composer = SetComposerModel()
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
    /// Every setlist write (edits, undo and redo), run one after another so each edit's
    /// before-snapshot is read after the previous write lands and undo steps register in
    /// the order the user acted (R154).
    var writeWork: Task<Void, Never>?
    /// Records analytics events (WS3 spec 5); the session hands over the app's hub.
    @ObservationIgnored public var services: ServicesHub = .disabled
    /// Days since the first launch, set by the session (milestones).
    @ObservationIgnored var daysSinceFirstLaunch: DaysBucket = .zero

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
            recordCreated(.new)
        }
        return created
    }

    /// Appends `songID` to setlist `id`; returns whether it was added. A song already a slot
    /// of the setlist is not added again; one that is only a medley member is added as its
    /// reprise (P9-3 decision 8).
    @discardableResult
    public func add(_ songID: SongID, to id: SetlistID) async -> Bool {
        let alreadyIn = await store.setlist(id: id).map {
            !$0.canAdd(songID, as: .slot).isAllowed
        } ?? false
        let updated = await mutate(undo: (id, "Add Song")) { store in
            try await store.addSong(songID, to: id)
        }
        return updated != nil && !alreadyIn
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
        services.record(.featureUsed(.setlistEdit, .builder))
    }

    /// Removes entries (`onDelete`, context menu).
    public func remove(in id: SetlistID, atOffsets offsets: IndexSet) async {
        await mutate(undo: (id, offsets.count == 1 ? "Remove Song" : "Remove Songs")) { store in
            try await store.remove(in: id, atOffsets: offsets)
        }
        services.record(.featureUsed(.setlistEdit, .builder))
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
            recordCreated(.duplicate)
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
    /// library column, or its `+` button. Songs already a slot are skipped; a medley
    /// member's song is added as its reprise (P9-3 decision 8).
    public func insert(_ songIDs: [SongID], into id: SetlistID, at offset: Int?) async {
        let current = setlist(id)
        var seen: Set<SongID> = []
        let fresh = songIDs.filter { song in
            current?.canAdd(song, as: .slot).isAllowed != false && seen.insert(song).inserted
        }
        guard !fresh.isEmpty else { return }
        await mutate(undo: (id, fresh.count == 1 ? "Add Song" : "Add Songs")) { store in
            try await store.insertSongs(fresh, into: id, at: offset)
        }
        services.record(.featureUsed(.setlistEdit, .builder))
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
        if details.targetDuration != nil {
            services.record(.featureUsed(.setlistTarget, .builder))
        }
    }

    /// The setlist with `id`, if loaded.
    public func setlist(_ id: SetlistID) -> Setlist? {
        setlists.first { $0.id == id }
    }

    /// Runs `operation` through the store, then reloads. With `undo`, the setlist's value
    /// before (from the store, not any optimistic local change) and after are registered
    /// as one undoable step named `undo.name`, unless the operation changed nothing (an add
    /// of songs already in the setlist). The whole step runs on the write queue, after any
    /// write still in flight; `operation` must not call `mutate` itself (it would wait on
    /// its own queue).
    @discardableResult
    func mutate(
        undo: (id: SetlistID, name: String)? = nil,
        _ operation: @escaping @MainActor (SetlistStore) async throws -> Setlist,
        then: @escaping @MainActor (Setlist) -> Void = { _ in },
    ) async -> Setlist? {
        await serialized { [self] in
            let before: Setlist? = if let undo {
                await store.setlist(id: undo.id)
            } else {
                nil
            }
            do {
                let updated = try await operation(store)
                await reload()
                then(updated)
                if let undo, let before, before != updated {
                    registerSnapshotUndo(
                        undo.id,
                        actionName: undo.name,
                        before: before,
                        after: updated,
                    )
                }
                return updated
            } catch {
                errorMessage = UserMessage.describe(error)
                await reload()
                return nil
            }
        }
    }
}

// MARK: - Analytics (WS3 spec 5 rows 10 and 13)

extension SetlistsViewModel {
    func recordCreated(_ source: SetlistSource) {
        services.record(.setlistCreated(source))
        services.record(.milestoneReached(
            .firstSetlist,
            daysSinceFirstLaunch: daysSinceFirstLaunch,
        ))
    }
}
