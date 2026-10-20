#if os(macOS)
    import Foundation
    import Library

    // P3-6: smart filters in the session (load, list scope from the sidebar selection) and
    // library-wide tag management (rename, merge, delete), each one undo step.

    extension SmartFilterStore {
        /// A store on the app's file system, clock and ID generator.
        static func make(_ dependencies: AppDependencies) -> SmartFilterStore {
            SmartFilterStore(
                fileSystem: dependencies.fileSystem,
                clock: dependencies.clock,
                ids: dependencies.ids,
            )
        }
    }

    public extension LibrarySession {
        /// Loads the filter files and keeps the list scope in step with them.
        internal func loadSmartFilters() async {
            smartFilters.didChange = { [weak self] in self?.syncLibraryScope() }
            await smartFilters.load(root: root)
        }

        /// Narrows the library list to the selected smart filter (or the built-in one), or
        /// shows every song. A selected filter that is gone falls back to the Library.
        internal func syncLibraryScope() {
            switch section {
            case let .smartFilter(id):
                if let filter = smartFilters.filter(id) {
                    library.scope = .smartFilter(filter)
                } else {
                    section = .library
                }
            case .missingEssentials:
                library.scope = .missingEssentials
            case .gigLog, .library, nil, .setlist:
                library.scope = .all
            }
        }

        /// Shows the library list narrowed to filter `id`.
        func showSmartFilter(_ id: SmartFilterID) {
            library.navigate { [weak self] in self?.section = .smartFilter(id) }
        }

        /// Saves a new filter from the editor sheet and shows its songs.
        func createSmartFilter(name: String, conditions: SmartFilterConditions) async {
            if let created = await smartFilters.create(name: name, conditions: conditions) {
                showSmartFilter(created.id)
            }
        }

        // MARK: Tags

        /// Renames tag `old` to `new` in every song (a merge when `new` exists); saved
        /// filters follow. One undo step.
        func renameTag(_ old: String, to new: String) async {
            await rewriteTags(actionName: "Rename Tag") { store in
                try await store.renameTag(old, to: new)
            } filters: {
                await self.smartFilters.rewriteTags([old], to: new)
            }
        }

        /// Merges tag `source` into `target` in every song; saved filters follow. One undo
        /// step.
        func mergeTag(_ source: String, into target: String) async {
            await rewriteTags(actionName: "Merge Tags") { store in
                try await store.mergeTags([source], into: target)
            } filters: {
                await self.smartFilters.rewriteTags([source], to: target)
            }
        }

        /// Removes tag `tag` from every song. One undo step; saved filters are untouched.
        func deleteTag(_ tag: String) async {
            await rewriteTags(actionName: "Delete Tag") { store in
                try await store.deleteTag(tag)
            } filters: {
                []
            }
        }

        private func rewriteTags(
            actionName: String,
            songs: (LibraryStore) async throws -> TagRewrite,
            filters: () async -> [SmartFilter],
        ) async {
            do {
                let rewrite = try await songs(stores.library)
                let snapshots = await filters()
                await library.reload()
                if !rewrite.skipped.isEmpty {
                    library.errorMessage = rewrite.skipped.count == 1
                        ? "1 read-only song kept its tags."
                        : "\(rewrite.skipped.count) read-only songs kept their tags."
                }
                if !rewrite.isEmpty || !snapshots.isEmpty {
                    let done = Task<TagUndoState?, Never> { (rewrite, snapshots) }
                    registerTagUndo(pending: done, actionName: actionName)
                }
            } catch {
                library.errorMessage = UserMessage.describe(error)
                await library.reload()
            }
        }

        /// What one tag rewrite changed, for its undo: the songs' previous tags and the
        /// filters as they were.
        internal typealias TagUndoState = (rewrite: TagRewrite, filters: [SmartFilter])

        /// Undo puts back what `pending` changed; registered synchronously inside the undo,
        /// its reverse lands on the redo stack (and so on, like `TrashUndo`).
        private func registerTagUndo(pending: Task<TagUndoState?, Never>, actionName: String) {
            guard let manager = undoManager else { return }
            manager.registerUndo(withTarget: tagUndoTarget) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let reverse = Task<TagUndoState?, Never> { @MainActor in
                        guard let state = await pending.value else { return nil }
                        do {
                            let redo = try await self.stores.library.restoreTags(state.rewrite)
                            let replaced = await self.smartFilters.restore(snapshots: state.filters)
                            await self.library.reload()
                            return (redo, replaced)
                        } catch {
                            self.library.errorMessage = "Could not undo. "
                                + UserMessage.describe(error)
                            await self.library.reload()
                            return nil
                        }
                    }
                    self.registerTagUndo(pending: reverse, actionName: actionName)
                }
            }
            manager.setActionName(actionName)
        }

        /// The undo target of tag rewrites (one shared target: they touch many songs).
        private var tagUndoTarget: AnyObject {
            stores.library
        }
    }
#endif
