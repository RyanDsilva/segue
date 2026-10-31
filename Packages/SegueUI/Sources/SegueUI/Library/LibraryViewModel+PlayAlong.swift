import Editing
import Library

/// Play along in the library's song pane (P8-6 10.3): one bar model, following the song
/// shown. Timing writes go to the sidecar only, with no undo (as walk-up picks).
extension LibraryViewModel {
    /// Makes the bar's model for the sound session handed over (nil without sound).
    func makePlayAlong() {
        playAlong?.stop()
        playAlong = sound.map { sound in
            let model = PlayAlong(session: sound, context: .library) { [weak self] _, change in
                guard let self, let id = playAlongSong else { return }
                writeBassPrefs(songID: id) { change(&$0.timing) }
            }
            model.writeDirective = { [weak self] operation in
                guard let self, let id = playAlongSong else { return }
                Task { await self.editSongSource(id: id, operation) }
            }
            // The song's saved fills replace the bass line where they apply (P8-7 13).
            model.fillProvider = { [weak model] built in model?.source?.fills(built) ?? [] }
            return model
        }
    }

    /// The pane shows `record` rendered as `render`: a new song stops what was playing.
    func showPlayAlong(_ record: SongRecord, render: RenderModel) {
        guard let playAlong else { return }
        if playAlongSong != record.id {
            playAlong.stop()
            playAlongSong = record.id
        }
        playAlong.update(PlayAlongSource.make(
            model: render,
            document: record.document,
            prefs: record.sidecar.bass,
            parts: record.sidecar.parts,
            profile: instrument?.profile,
            canEdit: !record.isReadOnly,
        ))
    }
}
