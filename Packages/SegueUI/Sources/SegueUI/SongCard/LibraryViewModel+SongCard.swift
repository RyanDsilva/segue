import Editing
import Foundation
import Library

/// The library detail pane's song card writes (R80): one `EditOperation` on the song's
/// file per committed field, saved at once and undoable from Edit > Undo, plus the route
/// that selects a song and focuses a card field.
public extension LibraryViewModel {
    /// Selects song `id` in the library and asks its card to focus `field` (P3-12's
    /// missing-lengths list "Open Song" uses `.length`). Pending editor changes are saved
    /// first, as for any navigation; an editor already open on the song keeps it, and its
    /// token strip takes the focus. Callers outside the Library section switch the sidebar
    /// to it first.
    func showSong(_ id: SongID, focusing field: SongCardField) {
        SongCardFocusRouter.shared.focus(field, songID: id)
        select(id)
    }
}

extension LibraryViewModel {
    /// Applies `operation` to song `id`'s source and saves it (checked against the revision
    /// the catalog holds). Failures show in the error banner. One undo step.
    func editSongSource(id: SongID, _ operation: EditOperation) async {
        guard let record = song(id: id), !record.isReadOnly else { return }
        let before = record.source
        let snapshot = SourceSnapshot(text: before)
        guard let change = try? DocumentEditor.change(for: operation, in: snapshot),
              !change.isEmpty
        else { return }
        let after = before.applying(change.edits)
        guard await writeSource(id: id, after, basedOn: record.revision) else { return }
        registerSourceUndo(
            id,
            actionName: change.actionName,
            before: before,
            after: after,
        )
    }

    private func writeSource(id: SongID, _ source: String, basedOn revision: SongRevision?)
        async -> Bool
    {
        do {
            _ = try await updateSong(id: id, source: source, basedOn: revision)
            return true
        } catch {
            errorMessage = UserMessage.describe(error)
            await reload()
            return false
        }
    }

    /// Undo writes `before` back (against the catalog's current revision) and reselects the
    /// song; its own undo re-applies `after`.
    private func registerSourceUndo(
        _ id: SongID,
        actionName: String,
        before: String,
        after: String,
    ) {
        guard let manager = undoManager else { return }
        manager.registerUndo(withTarget: metadataTargets.target(for: id)) { [weak self] target in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.registerSourceUndo(id, actionName: actionName, before: after, after: before)
                let previous = self.metadataWork
                self.metadataWork = Task { @MainActor in
                    await previous?.value
                    guard let record = self.song(id: id) else {
                        self.errorMessage = "That song is no longer in the library."
                        manager.removeAllActions(withTarget: target)
                        return
                    }
                    guard await self.writeSource(id: id, before, basedOn: record.revision) else {
                        manager.removeAllActions(withTarget: target)
                        return
                    }
                    if self.editor == nil, self.detail != .song(id) {
                        self.selection = id
                        self.detail = .song(id)
                    }
                }
            }
        }
        manager.setActionName(actionName)
    }

    /// Distinct artists in the catalog as stored, most songs first (the chip field's
    /// suggestions; a legacy "Vishal & Shekhar" is offered whole, P8-8 section 3.3).
    var knownArtists: [String] {
        Self.mostSongsFirst(catalog.flatMap(\.document.metadata.artists))
    }

    /// Distinct Movie / Album values, most songs first (the album field's suggestions).
    var knownAlbums: [String] {
        Self.mostSongsFirst(catalog.compactMap(\.document.metadata.album))
    }

    /// The library's names the request lexicon reads besides tags.
    var lexiconCredits: LexiconCredits {
        LexiconCredits(artists: knownArtists, albums: knownAlbums)
    }

    /// `state`'s filter, with the library's tags, artists and albums for the lexicon.
    func songFilter(_ state: SongFilterState) -> SongFilter {
        state.filter(knownTags: tags.map(\.tag), credits: lexiconCredits)
    }

    nonisolated static func mostSongsFirst(_ values: [String]) -> [String] {
        var counts: [String: Int] = [:]
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                counts[trimmed, default: 0] += 1
            }
        }
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
    }
}
