import Editing
import Foundation
import Library
import MusicTheory
import Services

/// Walk-ups from the library (P8-4b section 8.9): the preview's runs open the picker and a
/// song's "Walk-ups..." opens the list. Writes go to the sidecar only, with no undo ("Reset
/// to suggestion" is the way back).
extension LibraryViewModel {
    /// The library offers walk-ups only in the bass-note view (R162 Q4).
    var showsWalkUps: Bool {
        instrument?.profile.bassNotes == true
    }

    /// The song as the preview renders it, walk-ups included.
    private func walkUpModel(_ id: SongID) -> (RenderModel, SongRecord)? {
        guard let record = song(id: id), showsWalkUps else { return nil }
        let model = SongSummary.renderModel(
            record,
            userShapes: userShapes,
            bass: instrument?.bassView,
        )
        return (model, record)
    }

    private func feel(_ record: SongRecord) -> BassGenre {
        record.sidecar.bass.genre ?? instrument?.profile.genre ?? .pop
    }

    /// The picker for song `id`'s preview.
    func walkUpPicking(songID id: SongID) -> WalkUpPicking {
        WalkUpPicking(
            isEnabled: song(id: id).map { !$0.isReadOnly } ?? false,
            details: { [weak self] change in
                guard let self, let (model, record) = walkUpModel(id) else { return nil }
                let changes = BassLine.changes(
                    model,
                    document: record.document,
                    prefs: record.sidecar.bass,
                )
                guard let found = changes.first(where: { $0.id == change }) else { return nil }
                let section = model.sections.indices.contains(found.section)
                    ? SectionNotes.label(of: model.sections[found.section]) : nil
                return WalkUpDetails(change: found, section: section, feel: feel(record).title)
            },
            choose: { [weak self] change, candidate in
                self?.chooseWalkUp(songID: id, change: change, candidate: candidate)
            },
            reset: { [weak self] change in
                self?.resetWalkUp(songID: id, change: change)
            },
        )
    }

    /// The Walk-ups list for song `id`.
    func walkUpsSource(songID id: SongID) -> WalkUpsSource? {
        guard let (model, record) = walkUpModel(id) else { return nil }
        let prefs = record.sidecar.bass
        let key = model.transform.key.writtenKey
        let sections = model.sections
        return WalkUpsSource(
            title: SongSummary.title(record),
            changes: BassLine.changes(model, document: record.document, prefs: prefs),
            sectionLabel: { index in
                sections.indices.contains(index) ? SectionNotes.label(of: sections[index]) : nil
            },
            unmatched: BassLine.unmatched(model, document: record.document, prefs: prefs)
                .map { ($0, $0.savedSummary(key: key)) },
            feel: prefs.genre,
            defaultFeel: instrument?.profile.genre ?? .pop,
            density: instrument?.profile.walkUps ?? .off,
            readOnlyHelp: record.isReadOnly ? "This song was saved by a newer Segue" : nil,
            picking: walkUpPicking(songID: id),
            setFeel: { [weak self] genre in
                self?.writeBassPrefs(songID: id) { $0.genre = genre }
                self?.services.record(.featureUsed(.songFeel, .library))
            },
            remove: { [weak self] picks in
                self?.writeBassPrefs(songID: id) { prefs in
                    prefs.walkUps.removeAll { picks.contains($0) }
                }
            },
        )
    }

    private func chooseWalkUp(songID id: SongID, change: ChordChange, candidate: WalkUpCandidate?) {
        guard let (model, record) = walkUpModel(id),
              let anchor = ChordAnchors.anchor(
                  at: change.id.from,
                  units: SongSections.units(of: record.document),
                  sections: model.sections,
              )
        else { return }
        let pick = WalkUpPick(
            anchor: anchor,
            to: change.toBass,
            kind: candidate?.kind ?? .hold,
            offsets: candidate?.offsets ?? [],
        )
        writeBassPrefs(songID: id) { $0 = $0.saving(pick) }
        services.record(.featureUsed(.walkUpPick, .library))
        services.record(.walkUpPicked(.choosing(candidate, on: change, feel: feel(record))))
    }

    private func resetWalkUp(songID id: SongID, change: ChordChange) {
        guard let pick = change.pick, let record = song(id: id) else { return }
        writeBassPrefs(songID: id) { $0 = $0.removing(anchor: pick.anchor, to: pick.to) }
        services.record(.walkUpPicked(.resetting(change, feel: feel(record))))
    }

    /// Applies `change` to the song's saved bass prefs and writes the sidecar; writes are
    /// serialized so quick choices land in order.
    func writeBassPrefs(songID id: SongID, _ change: @escaping (inout BassPrefs) -> Void) {
        guard let record = song(id: id), !record.isReadOnly else { return }
        let previous = walkUpWrite
        walkUpWrite = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, let current = song(id: id) else { return }
            var prefs = current.sidecar.bass
            change(&prefs)
            guard prefs != current.sidecar.bass else { return }
            do {
                let saved = try await store.updateBassPrefs(id: id, prefs)
                await applySaved(saved)
            } catch {
                errorMessage = UserMessage.describe(error)
            }
        }
    }
}
