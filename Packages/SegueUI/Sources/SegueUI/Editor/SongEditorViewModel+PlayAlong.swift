import Editing
import Library

/// Play along in the editor (P8-6 10.3): the bar's model, the song as the preview renders
/// it, and timing writes to the sidecar as one undo step each.
extension SongEditorViewModel {
    /// The bar's model; nil without sound (tests, no app).
    var playAlong: PlayAlong? {
        if let playAlongStore {
            return playAlongStore
        }
        guard let sound else { return nil }
        let model = PlayAlong(session: sound, context: .editor) { [weak self] name, change in
            self?.changeTiming(name, change)
        }
        model.writeDirective = { [weak self] operation in
            self?.perform(operation)
        }
        model.openFill = { [weak self] span in self?.openFillEditor(span: span) }
        // The song's saved fills replace the bass line where they apply (P8-7 section 13).
        model.fillProvider = { [weak model] built in model?.source?.fills(built) ?? [] }
        playAlongStore = model
        return model
    }

    /// The song as the preview renders it now; nil before the first render.
    var playAlongSource: PlayAlongSource? {
        guard let renderModel else { return nil }
        return PlayAlongSource.make(
            model: renderModel,
            document: snapshot.document,
            prefs: bassPrefs,
            parts: parts,
            profile: instrument?.profile,
            canEdit: canPickWalkUps,
        )
    }

    /// A timing change from the lane or the Timing menu: sidecar only, one undo step.
    func changeTiming(_ actionName: String, _ change: (inout ChordTiming) -> Void) {
        guard canPickWalkUps else { return }
        var prefs = bassPrefs
        change(&prefs.timing)
        setBassPrefs(prefs, actionName: actionName)
    }
}
