import Foundation
import Library
import Observation
import Setlists

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
    public private(set) var loadIssues: [SetlistLoadIssue]

    private let store: SetlistStore

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
        if let selection, !setlists.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }

    /// Creates an empty setlist named `name` (trimmed; blank names are refused) and selects it.
    @discardableResult
    public func create(name: String) async -> Setlist? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return await mutate { store in
            try await store.create(name: trimmed)
        } then: { setlist in
            self.selection = setlist.id
        }
    }

    /// Appends `songID` to setlist `id`.
    public func add(_ songID: SongID, to id: SetlistID) async {
        await mutate { store in
            try await store.addSong(songID, to: id)
        }
    }

    /// Drag reorder (`onMove`).
    public func move(in id: SetlistID, fromOffsets source: IndexSet, toOffset destination: Int)
        async
    {
        // Reorder locally first so the row doesn't snap back while the write is in flight.
        if let index = setlists.firstIndex(where: { $0.id == id }) {
            setlists[index].entries.move(fromOffsets: source, toOffset: destination)
        }
        await mutate { store in
            try await store.move(in: id, fromOffsets: source, toOffset: destination)
        }
    }

    /// Removes entries (`onDelete`, context menu).
    public func remove(in id: SetlistID, atOffsets offsets: IndexSet) async {
        await mutate { store in
            try await store.remove(in: id, atOffsets: offsets)
        }
    }

    @discardableResult
    private func mutate(
        _ operation: (SetlistStore) async throws -> Setlist,
        then: (Setlist) -> Void = { _ in },
    ) async -> Setlist? {
        do {
            let updated = try await operation(store)
            await reload()
            then(updated)
            return updated
        } catch {
            errorMessage = UserMessage.describe(error)
            await reload()
            return nil
        }
    }
}
