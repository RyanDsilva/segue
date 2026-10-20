import Foundation
import Library
import Observation
import Services
import Support

/// Saved smart filters as the main window sees them (P3-6, R72): the sidebar list, its
/// counts, and the edits. Every mutation goes through `SmartFilterStore` (which writes the
/// `filters/<slug>.filter.json` file) and adopts the result. Undo covers create, edit,
/// rename, duplicate and Move to Trash.
@MainActor
@Observable
public final class SmartFiltersViewModel {
    public private(set) var filters: [SmartFilter] = []
    /// The last failure, shown as a dismissible banner.
    public var errorMessage: String?
    /// Filter files that could not be loaded (reported, never deleted).
    public private(set) var loadIssues: [SmartFilterLoadIssue] = []

    /// What the editor sheet is open for, if it is (sidebar New / Edit, the list header).
    public enum EditorRequest: Identifiable, Equatable {
        case new
        case edit(SmartFilterID)

        public var id: String {
            switch self {
            case .new: "new"
            case let .edit(id): id.description
            }
        }
    }

    /// The editor sheet's request; nil while it is closed.
    public var editing: EditorRequest?

    let store: SmartFilterStore
    /// The main window's undo manager (Edit > Undo).
    @ObservationIgnored weak var undoManager: UndoManager?
    /// Called after every change to `filters`, so the session can re-apply the list scope.
    @ObservationIgnored var didChange: (@MainActor () -> Void)?
    /// One undo target per filter.
    private let targets = UndoTargets<SmartFilterID>()
    /// Records analytics events; the session hands over the app's hub.
    @ObservationIgnored public var services: ServicesHub = .disabled

    public init(store: SmartFilterStore) {
        self.store = store
    }

    /// The filter with `id`, if loaded.
    public func filter(_ id: SmartFilterID) -> SmartFilter? {
        filters.first { $0.id == id }
    }

    public func reload() async {
        filters = await store.all()
        didChange?()
    }

    /// Loads the filter files of the library at `root` (session open).
    func load(root: LibraryRoot) async {
        do {
            loadIssues = try await store.load(root: root)
        } catch {
            errorMessage = UserMessage.describe(error)
        }
        await reload()
    }

    /// Re-reads every filter file (Library > Refresh, app activation).
    public func reloadFromDisk() async {
        do {
            loadIssues = try await store.reloadFromDisk()
        } catch {
            errorMessage = UserMessage.describe(error)
        }
        await reload()
    }

    /// How many of `songs` filter `filter` matches.
    public static func count(
        of filter: SmartFilter,
        in songs: [SongRecord],
        playStats: [SongID: PlayStats],
    ) -> Int {
        let matcher = filter.conditions.compiled(playStats: playStats)
        return songs.count(where: matcher.matches)
    }

    /// How many of `songs` lack a set essential (the built-in filter's count).
    public static func missingEssentialsCount(in songs: [SongRecord]) -> Int {
        songs.count { SongEssentials.isMissingAny(in: $0.document) }
    }

    /// Saves a new filter (blank names are refused); Undo moves it to the Trash.
    @discardableResult
    public func create(name: String, conditions: SmartFilterConditions) async -> SmartFilter? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let created = try await store.create(name: trimmed, conditions: conditions)
            await reload()
            registerCreationUndo(created.id, actionName: "New Smart Filter")
            services.record(.aiSmartFilterUsed(
                action: .created,
                conditions: SmallBucket(conditions.count),
            ))
            return created
        } catch {
            errorMessage = UserMessage.describe(error)
            return nil
        }
    }

    /// Saves a copy named "<name> copy"; Undo moves the copy to the Trash.
    @discardableResult
    public func duplicate(_ id: SmartFilterID) async -> SmartFilter? {
        guard let original = filter(id) else { return nil }
        do {
            let copy = try await store.create(
                name: "\(original.name) copy",
                conditions: original.conditions,
            )
            await reload()
            registerCreationUndo(copy.id, actionName: "Duplicate Smart Filter")
            return copy
        } catch {
            errorMessage = UserMessage.describe(error)
            return nil
        }
    }

    /// Replaces the name and conditions of filter `id` (Save in the editor sheet).
    public func save(_ id: SmartFilterID, name: String, conditions: SmartFilterConditions) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var edited = filter(id) else { return }
        edited.name = trimmed
        edited.conditions = conditions
        await replace(edited, actionName: "Edit Smart Filter")
    }

    /// Renames filter `id` (blank names are refused).
    public func rename(_ id: SmartFilterID, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var edited = filter(id) else { return }
        edited.name = trimmed
        await replace(edited, actionName: "Rename Smart Filter")
    }

    /// Moves filter `id`'s file to the Trash (R15); Edit > Undo puts it back.
    public func delete(_ id: SmartFilterID) async {
        let pending = Task { await trash(id) }
        guard await pending.value != nil else { return }
        TrashUndo(
            manager: undoManager,
            target: targets.target(for: id),
            actionName: "Move Smart Filter to Trash",
            trash: { [weak self] in await self?.trash(id) },
            restore: { [weak self] receipt in await self?.restore(receipt) ?? false },
        ).register(pending: pending)
    }

    /// Follows a library tag rename or merge in every saved filter, undoable together with
    /// it: returns the filters as they were, for `restore(snapshots:)`.
    func rewriteTags(_ sources: [String], to target: String) async -> [SmartFilter] {
        do {
            let previous = try await store.rewriteTags(sources, to: target)
            await reload()
            return previous
        } catch {
            errorMessage = UserMessage.describe(error)
            return []
        }
    }

    /// Writes filter snapshots back (undo of a tag rename); returns the values replaced.
    func restore(snapshots: [SmartFilter]) async -> [SmartFilter] {
        var replaced: [SmartFilter] = []
        for snapshot in snapshots {
            if let current = await store.filter(id: snapshot.id),
               await (try? store.replace(snapshot)) != nil
            {
                replaced.append(current)
            }
        }
        await reload()
        return replaced
    }

    /// The file of filter `id`, for Show in Finder.
    public func fileURL(for id: SmartFilterID) async -> URL? {
        await store.fileURL(for: id)
    }

    // MARK: - Private

    private func replace(_ edited: SmartFilter, actionName: String) async {
        guard let before = filter(edited.id) else { return }
        do {
            let after = try await store.replace(edited)
            await reload()
            registerSnapshotUndo(before: before, after: after, actionName: actionName)
        } catch {
            errorMessage = UserMessage.describe(error)
        }
    }

    /// Undo writes `before` back; its own undo (the Redo) writes `after`.
    private func registerSnapshotUndo(before: SmartFilter, after: SmartFilter, actionName: String) {
        guard let manager = undoManager else { return }
        manager.registerUndo(withTarget: targets.target(for: before.id)) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.registerSnapshotUndo(before: after, after: before, actionName: actionName)
                Task { await self.write(before) }
            }
        }
        manager.setActionName(actionName)
    }

    private func write(_ snapshot: SmartFilter) async {
        do {
            try await store.replace(snapshot)
        } catch {
            errorMessage = UserMessage.describe(error)
        }
        await reload()
    }

    /// New and Duplicate: Undo moves the new filter to the Trash, Redo restores it.
    private func registerCreationUndo(_ id: SmartFilterID, actionName: String) {
        guard let manager = undoManager else { return }
        manager.registerUndo(withTarget: targets.target(for: id)) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let pending = Task { await self.trash(id) }
                // The redo puts the trashed file back; its undo trashes it again.
                manager.registerUndo(withTarget: self.targets.target(for: id)) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        Task {
                            guard let receipt = await pending.value,
                                  await self.restore(receipt)
                            else { return }
                            self.registerCreationUndo(id, actionName: actionName)
                        }
                    }
                }
                manager.setActionName(actionName)
            }
        }
        manager.setActionName(actionName)
    }

    private func trash(_ id: SmartFilterID) async -> TrashReceipt? {
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
            if restored == nil {
                errorMessage = "Could not undo: the smart filter file could not be read."
            }
            return restored != nil
        } catch {
            errorMessage = "Could not undo. " + UserMessage.describe(error)
            return false
        }
    }
}
