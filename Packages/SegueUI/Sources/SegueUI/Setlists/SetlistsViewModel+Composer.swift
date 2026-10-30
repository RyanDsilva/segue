import Editing
import Foundation
import Library
import MusicTheory
import Services
import Setlists
import Support

/// What a Return in the set composer did (P8-5 section 8.2).
public enum ComposeOutcome: Sendable, Equatable {
    /// A song slot was appended.
    case added(SetlistItemID)
    /// A break row was appended.
    case breakAdded(SetlistItemID)
    /// The chosen song is already in the set (at this slot); nothing was written.
    case alreadyInSet(SetlistItemID)
    /// The line names no song; nothing was written.
    case noMatch
    /// Nothing to do: an empty line, a read-only setlist, or a failed write.
    case ignored
}

/// The new slot a composer candidate would become: its overrides for a typed gig key and
/// what its row would show (P8-5 sections 4.1, 7).
struct ComposerSlotPreview: Equatable {
    /// The item ID of the not-yet-added slot (never saved).
    private static let previewItem = SetlistItemID(ULID(
        milliseconds: 0,
        randomness: Array(repeating: 0, count: 10),
    ))

    var overrides: SetlistOverrides
    /// A key was typed but the song has no key, so it is ignored.
    var keyIgnored: Bool
    var display: SetlistEntryDisplay

    init(record: SongRecord, key: SongKey?) {
        var overrides = SetlistOverrides()
        var keyIgnored = false
        if let key {
            let options = record.sidecar.displayPrefs.displayOptions
            let result = SetlistOverrides.transpose(
                toShow: key,
                written: KeyContext(document: record.document).writtenKey,
                songTranspose: options.transpose,
                capoOffset: Capo.displayOffset(
                    capo: record.document.metadata.capo,
                    mode: options.capoMode,
                ),
            )
            switch result {
            case .noOverride: break
            case let .transpose(semitones): overrides.transpose = semitones
            case .songHasNoKey: keyIgnored = true
            }
        }
        self.overrides = overrides
        self.keyIgnored = keyIgnored
        display = SetlistEntryDisplay(
            entry: SetlistEntry(
                itemId: Self.previewItem,
                songId: record.id,
                overrides: overrides,
            ),
            record: record,
        )
    }
}

/// The set composer's writes (P8-5 section 8): one Return is one store write and one undo
/// step, always at the end of the set.
public extension SetlistsViewModel {
    /// Applies `resolution` to setlist `id`: the candidate at `choice` (a song, with the
    /// typed gig key) or a break. A song already in the set is flagged, never added again.
    /// Records `Segue.Setlist.composed` for every outcome but `.ignored`.
    func compose(
        _ resolution: SetComposerResolution,
        choice: Int,
        in id: SetlistID,
        songs: (SongID) -> SongRecord?,
        entry: ComposerEntry = .click,
    ) async -> ComposeOutcome {
        guard let setlist = setlist(id), setlist.readOnly == nil else { return .ignored }
        switch resolution.kind {
        case .empty:
            return .ignored
        case .breakRow:
            return await composeBreak(in: id, entry: entry)
        case .song:
            guard resolution.matches.indices.contains(choice) else {
                recordComposed(.noMatch, match: nil, choice: choice, key: false, entry: entry)
                return .noMatch
            }
            let match = resolution.matches[choice]
            if let existing = setlist.entries.first(where: { $0.songId == match.id }) {
                recordComposed(
                    .alreadyInSet,
                    match: match,
                    choice: choice,
                    key: false,
                    entry: entry,
                )
                return .alreadyInSet(existing.itemId)
            }
            guard let record = songs(match.id) else { return .ignored }
            let preview = ComposerSlotPreview(record: record, key: resolution.key)
            let updated = await mutate(undo: (id, "Add Song")) { store in
                try await store.insertSong(match.id, overrides: preview.overrides, into: id)
            }
            guard let added = updated?.entries.last(where: { $0.songId == match.id }) else {
                return .ignored
            }
            recordComposed(
                .song,
                match: match,
                choice: choice,
                key: resolution.key != nil && !preview.keyIgnored,
                entry: entry,
            )
            services.record(.featureUsed(.setlistEdit, .builder))
            return .added(added.itemId)
        }
    }

    /// Records a composer session that added at least one row (focus left the composer).
    func recordComposerSession(songs: Int, cycles: Int) {
        services.record(.setlistComposerSession(
            songs: SmallBucket(songs),
            cycles: SmallBucket(cycles),
        ))
    }

    /// "---": a break at the very end (never after Arrange's selection: the composer is
    /// the end of the set, R158 Q6).
    private func composeBreak(in id: SetlistID, entry: ComposerEntry) async -> ComposeOutcome {
        let updated = await mutate(undo: (id, "Insert Break")) { store in
            try await store.insertBreak(into: id, at: nil)
        }
        guard let added = updated?.entries.last, added.isBreak else { return .ignored }
        recordComposed(.break, match: nil, choice: 0, key: false, entry: entry)
        services.record(.featureUsed(.setlistEdit, .builder))
        return .breakAdded(added.itemId)
    }

    private func recordComposed(
        _ action: ComposerAction,
        match: SongMatch?,
        choice: Int,
        key: Bool,
        entry: ComposerEntry,
    ) {
        services.record(.setlistComposed(ComposerSummary(
            action: action,
            tier: match.map { ComposerTier(rawValue: $0.tier.rawValue) ?? .noTier } ?? .noTier,
            form: match.map { ComposerForm(rawValue: $0.form.rawValue) ?? .noForm } ?? .noForm,
            alternative: match != nil && choice > 0,
            key: key,
            entry: entry,
        )))
    }
}
