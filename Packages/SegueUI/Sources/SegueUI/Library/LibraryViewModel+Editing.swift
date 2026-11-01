import ChordPro
import Editing
import Foundation
import Library

/// A new song's editor session: the song its first save created (WS2a 3.4, A18).
@MainActor
final class CreatedSong {
    var id: SongID?
}

// MARK: - Navigation

public extension LibraryViewModel {
    /// Whether the open editor holds edits not yet on disk (pending, saving, failed or in
    /// conflict).
    var hasUnsavedEdits: Bool {
        editor?.needsFlush ?? false
    }

    /// Runs `action` (a navigation that closes the editor) after the editor's edits are
    /// saved: at once when nothing is pending, else after a flush. Only when that save fails
    /// is the action held in `pendingNavigation` for the "aren't saved" prompt; `onCancel`
    /// runs if the user stays.
    func navigate(
        _ action: @escaping @MainActor () -> Void,
        onCancel: (@MainActor () -> Void)? = nil,
    ) {
        guard let editor, editor.needsFlush else {
            closeEditor()
            action()
            return
        }
        Task { await flushThenNavigate(editor, action: action, onCancel: onCancel) }
    }

    /// Saves the open editor's edits now. Returns whether everything is on disk (true when
    /// no editor is open).
    @discardableResult
    func flushEditor() async -> Bool {
        guard let editor else { return true }
        return await editor.flush()
    }

    /// Answers the "aren't saved" prompt: save the edits as a new song then navigate,
    /// discard them then navigate, or stay in the editor.
    func resolvePendingNavigation(_ choice: UnsavedChangesChoice) async {
        guard let pending = pendingNavigation else { return }
        pendingNavigation = nil
        switch choice {
        case .cancel:
            pending.onCancel?()
        case .discard:
            closeEditor()
            pending.action()
        case .saveAsCopy:
            guard let editor else {
                pending.action()
                return
            }
            do {
                _ = try await store.createSong(source: editor.source)
                closeEditor()
                await reload()
                pending.action()
            } catch {
                editor.errorMessage = UserMessage.describe(error)
                pending.onCancel?()
            }
        }
    }

    /// Selects a song in the list (saving the open editor's edits first).
    func select(_ id: SongID?) {
        guard let id else {
            // Deselecting (e.g. clicking empty list space) never closes an open editor.
            if editor == nil {
                selection = nil
                detail = .empty
            } else {
                restoreListSelection()
            }
            return
        }
        // Re-selecting the song already shown (or being edited) is not a navigation.
        guard detail != .song(id) else { return }
        let show: @MainActor () -> Void = { [weak self] in
            self?.selection = id
            self?.detail = .song(id)
            SegueTips.donate(SegueTips.songViewed)
        }
        let stay: @MainActor () -> Void = { [weak self] in self?.restoreListSelection() }
        navigate(show, onCancel: stay)
    }

    /// Opens the editor for a new song (saving the open editor's edits first).
    func beginNewSong() {
        if detail == .newSong, editor != nil {
            return
        }
        navigate { [weak self] in self?.openNewSongEditor() }
    }

    /// Opens the editor on the selected song's source.
    func beginEditing(_ record: SongRecord) {
        guard !record.isReadOnly else { return }
        navigate { [weak self] in self?.openEditor(on: record) }
    }

    /// Editor "Done": saves now and closes the editor, then reloads the library. A new song
    /// with only blank text creates nothing. A failed save asks first.
    func finishEditing() async {
        guard let editor else { return }
        let wasNew = editor.mode == .create
        guard await editor.flush() else {
            navigate {}
            return
        }
        guard self.editor === editor else { return }
        closeEditor()
        if !wasNew || createdSong?.id != nil || editor.mode != .create {
            await reload()
        }
    }

    /// File > Save: saves the open editor now and confirms in its subtitle; with no editor
    /// open everything is already saved, which the bottom bar confirms.
    func confirmSave() async {
        if let editor {
            await editor.confirmSave()
        } else {
            flash("All changes saved")
        }
    }

    /// Shows `message` in the bottom bar for 1.5 s.
    func flash(_ message: String) {
        transientMessage = message
        transientTask?.cancel()
        transientTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            self?.transientMessage = nil
        }
    }
}

extension LibraryViewModel {
    private func flushThenNavigate(
        _ editor: SongEditorViewModel,
        action: @escaping @MainActor () -> Void,
        onCancel: (@MainActor () -> Void)?,
    ) async {
        if await editor.flush() {
            if self.editor === editor {
                closeEditor()
            }
            action()
            return
        }
        guard self.editor === editor else { return }
        let title = editor.document.metadata.title?.trimmingCharacters(in: .whitespaces) ?? ""
        pendingNavigation = PendingNavigation(
            songTitle: title.isEmpty ? "Untitled" : title,
            action: action,
            onCancel: onCancel,
        )
    }

    /// Moves the list highlight back to the song actually shown, after the table has
    /// finished applying the click that moved it.
    func restoreListSelection() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            listSelection = selection
        }
    }

    /// Closes the editor. Its pending edits are dropped (callers flushed or discarded
    /// them). Leaving the new-song editor shows nothing.
    func closeEditor() {
        editor?.discardPending()
        editor = nil
        editorBase = nil
        createdSong = nil
        if detail == .newSong {
            detail = selection.map(Detail.song) ?? .empty
        }
    }

    // MARK: Opening editors

    /// Shows `record` with its editor open on `text` (default: its source).
    func openEditor(on record: SongRecord, text: String? = nil) {
        let id = record.id
        selection = id
        detail = .song(id)
        // Saves are checked against the revision the editor's text came from, so an edit
        // made in another app meanwhile is never silently overwritten (the conflict bar).
        let base = RevisionBox(record.revision)
        let save: (String) async throws -> SongRecord = { [weak self] source in
            guard let self else { throw CancellationError() }
            let saved = try await updateSong(id: id, source: source, basedOn: base.revision)
            base.revision = saved.revision
            return saved
        }
        let editor = SongEditorViewModel(
            mode: .edit(id),
            source: record.source,
            prefs: record.sidecar.displayPrefs,
            livePrefs: record.sidecar.live,
            fileName: record.relativePath,
            userShapes: userShapes,
            persistPrefs: persistPrefs(following: base),
            persistLivePrefs: persistLivePrefs(following: base),
            cues: record.sidecar.cues,
            persistCues: persistCues(following: base),
            autosave: autosave,
            instrument: instrument,
            save: save,
        )
        editor.librarySectionKinds = librarySectionKinds
        editor.sound = sound
        editor.preview = preview
        editor.attachBassPrefs(
            record.sidecar.bass,
            parts: record.sidecar.parts,
            persist: persistBassPrefs(following: base),
            persistParts: persistParts(following: base),
        )
        closeEditor()
        selection = id
        detail = .song(id)
        editorBase = base
        if let text, text != record.source {
            editor.sourceTextDidChange(text)
        }
        self.editor = editor
    }

    /// The new-song editor: its first autosave creates the file (slug from the title at
    /// that moment); while the editor stays open, later saves rename the file pair when the
    /// `{title}` changes (A18).
    func openNewSongEditor() {
        let created = CreatedSong()
        let base = RevisionBox(SongRevision(contentHash: "", sidecarHash: nil))
        let editor = SongEditorViewModel(
            mode: .create,
            source: "",
            userShapes: userShapes,
            persistPrefs: persistPrefs(following: base),
            persistLivePrefs: persistLivePrefs(following: base),
            persistCues: persistCues(following: base),
            autosave: autosave,
            instrument: instrument,
            save: { [weak self] source in
                guard let self else { throw CancellationError() }
                return try await saveNewSong(source, created: created, base: base)
            },
        )
        editor.librarySectionKinds = librarySectionKinds
        editor.sound = sound
        editor.preview = preview
        closeEditor()
        selection = nil
        detail = .newSong
        createdSong = created
        editorBase = base
        self.editor = editor
    }

    private func saveNewSong(
        _ source: String,
        created: CreatedSong,
        base: RevisionBox,
    ) async throws -> SongRecord {
        guard let id = created.id else {
            let record = try await store.createSong(source: source)
            created.id = record.id
            base.revision = record.revision
            await applySaved(record)
            recordSongsCreated(.newSong)
            // The new song is the selection from now on (the editor stays the same).
            detail = .song(record.id)
            selection = record.id
            return record
        }
        var record = try await store.updateSong(id: id, source: source, basedOn: base.revision)
        let title = record.document.metadata.title ?? ""
        record = try await store.renameSong(id: id, toSlugFor: title)
        base.revision = record.revision
        await applySaved(record)
        return record
    }

    /// Display toggles write the sidecar only; the editor's base revision follows the
    /// sidecar it wrote, so its own toggles never read as an outside change.
    private func persistPrefs(
        following base: RevisionBox,
    ) -> (SongID, DisplayPrefs) async throws -> SongRecord {
        { [weak self] id, prefs in
            guard let self else { throw CancellationError() }
            let saved = try await updateDisplayPrefs(id: id, prefs)
            base.revision.sidecarHash = saved.revision.sidecarHash
            return saved
        }
    }

    /// Walk-up picks and feel write the sidecar only, like the display toggles (P8-4b).
    private func persistBassPrefs(
        following base: RevisionBox,
    ) -> (SongID, BassPrefs) async throws -> SongRecord {
        { [weak self] id, prefs in
            guard let self else { throw CancellationError() }
            let saved = try await store.updateBassPrefs(id: id, prefs)
            await applySaved(saved)
            base.revision.sidecarHash = saved.revision.sidecarHash
            return saved
        }
    }

    /// Fills write the sidecar only, like walk-up picks (P8-7d); the library's record is
    /// replaced so every view of the song follows.
    private func persistParts(
        following base: RevisionBox,
    ) -> (SongID, [Part]) async throws -> SongRecord {
        { [weak self] id, parts in
            guard let self else { throw CancellationError() }
            let saved = try await store.updateParts(id: id, parts)
            await applySaved(saved)
            base.revision.sidecarHash = saved.revision.sidecarHash
            return saved
        }
    }

    /// Stage-only section notes write the sidecar only, like the display toggles.
    private func persistCues(
        following base: RevisionBox,
    ) -> (SongID, [SongCue]) async throws -> SongRecord {
        { [weak self] id, cues in
            guard let self else { throw CancellationError() }
            let saved = try await store.updateSectionNotes(id: id, source: nil, cues: cues)
            await applySaved(saved)
            base.revision.sidecarHash = saved.revision.sidecarHash
            return saved
        }
    }

    private func persistLivePrefs(
        following base: RevisionBox,
    ) -> (SongID, LivePrefs) async throws -> SongRecord {
        { [weak self] id, prefs in
            guard let self else { throw CancellationError() }
            let saved = try await updateLivePrefs(id: id, prefs)
            base.revision.sidecarHash = saved.revision.sidecarHash
            return saved
        }
    }
}

// MARK: - Saved records and the disk

extension LibraryViewModel {
    /// Applies a record an autosave just wrote, without a full reload: replaces it in the
    /// catalog and results (re-sorting when its title changed), and refreshes the tag list
    /// only when its tags changed.
    func applySaved(_ record: SongRecord) async {
        let previous = catalogIndex[record.id]
        catalogIndex[record.id] = record
        if let index = catalog.firstIndex(where: { $0.id == record.id }) {
            catalog[index] = record
        } else {
            catalog.append(record)
        }
        let retitled = previous.map { Self.sortTitle($0) != Self.sortTitle(record) } ?? true
        if retitled {
            catalog.sort(by: Self.catalogOrder)
            catalogRevision += 1
        }
        if let index = results.firstIndex(where: { $0.id == record.id }) {
            results[index] = record
        }
        if retitled || previous == nil {
            try? await runSearch(filterState)
        }
        if previous?.sidecar.tags != record.sidecar.tags {
            tags = await (try? store.allTags()) ?? tags
        }
    }

    /// After a reload: a clean editor follows its song's file when another app changed it
    /// (one undoable "Reload from Disk" step); an editor with edits keeps them (its next
    /// save raises the conflict bar).
    func followDiskInEditor() {
        guard let editor, case let .edit(id) = editor.mode, let base = editorBase,
              let record = catalogIndex[id], !editor.needsFlush,
              record.revision.contentHash != base.revision.contentHash
        else { return }
        base.revision = record.revision
        editor.reloadFromDisk(record)
    }

    /// Answers the conflict bar.
    public func resolveSaveConflict(_ choice: SaveConflictChoice) async {
        guard let editor, let conflict = saveConflict else { return }
        let id = conflict.songID
        let text = editor.source
        do {
            switch choice {
            case .reload:
                try await store.refresh()
                await reload()
                if let record = song(id: id), !record.isReadOnly {
                    openEditor(on: record)
                } else {
                    closeEditor()
                }
            case .overwrite:
                let record = try await store.overwriteSong(id: id, source: text)
                editorBase?.revision = record.revision
                editor.conflictResolved(saved: record)
                await applySaved(record)
            case .saveAsCopy:
                let record = try await store.createSong(source: text)
                closeEditor()
                await reload()
                selection = record.id
                detail = .song(record.id)
            }
        } catch {
            editor.errorMessage = UserMessage.describe(error)
        }
    }

    /// The open editor's unresolved conflict, for the conflict bar.
    public var saveConflict: SaveConflict? {
        guard let editor, let kind = editor.conflict, case let .edit(id) = editor.mode
        else { return nil }
        let title = editor.document.metadata.title?.trimmingCharacters(in: .whitespaces) ?? ""
        return SaveConflict(songID: id, kind: kind, songTitle: title.isEmpty ? "Untitled" : title)
    }

    static func sortTitle(_ record: SongRecord) -> String {
        record.document.metadata.title
            ?? URL(filePath: record.relativePath).deletingPathExtension().lastPathComponent
    }

    /// The store's `allSongs()` order: title (case-insensitive, slug when untitled), then ID.
    static func catalogOrder(_ lhs: SongRecord, _ rhs: SongRecord) -> Bool {
        switch sortTitle(lhs).caseInsensitiveCompare(sortTitle(rhs)) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: lhs.id < rhs.id
        }
    }
}

extension LibraryViewModel {
    /// Custom...'s library suggestions (R159): one pass over the in-memory catalog when it
    /// opens, no store call.
    var librarySectionKinds: () -> [SectionKind] {
        { [weak self] in
            SectionLabels.customKinds(in: (self?.catalog ?? []).map(\.document))
        }
    }
}
