import ChordPro
import Diagrams
import Editing
import Observation

/// The bass-note view in the editor (P8-4 6.3, 6.5): the user-level profile, never the song's.
extension SongEditorViewModel {
    /// Whether the bass-note view is on (user-level, R158 Q7).
    var showsBassNotes: Bool {
        instrument?.profile.bassNotes ?? false
    }

    /// The editor's Bass segment: flips the user-level bass-note view for every song and
    /// the stage. The song's sidecar is never written.
    func toggleBassNotes() {
        instrument?.toggleBassNotes(from: .editor)
    }

    /// Re-renders the preview whenever the profile's bass view changes, from anywhere (the
    /// stage's `b`, Settings, another editor).
    func observeInstrument() {
        guard let instrument else { return }
        withObservationTracking {
            _ = instrument.bassView
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.scheduleRender(delay: .zero)
                self.observeInstrument()
            }
        }
    }

    /// The background render: the preview with the bass view, and the visual canvas's
    /// model. The canvas keeps chart chords (P8-4 decision 5): with the bass view on in
    /// visual mode (`needsCanvas`) a second, bass-free model is rendered for it; otherwise
    /// the one render serves both, so text mode keeps a single render.
    nonisolated static func renderModels(
        _ document: SongDocument,
        options: DisplayOptions,
        bass: BassView?,
        needsCanvas: Bool = false,
        userShapes: UserShapeLibrary,
    ) -> (preview: RenderModel, canvas: RenderModel) {
        var preview = options
        preview.bass = bass
        let model = RenderModel(document: document, options: preview, userShapes: userShapes)
        guard needsCanvas else { return (model, model) }
        var chart = options
        chart.showDiagrams = false
        return (model, RenderModel(document: document, options: chart))
    }

    /// One background render: the preview, the snapshot's diagnostics and the canvas model.
    struct Rendered: Sendable {
        var preview: RenderModel
        var diagnostics: [EditorDiagnostic]
        var canvas: RenderModel
    }

    /// `renderModels` off the main thread, with the snapshot's diagnostics.
    nonisolated static func render(
        _ snapshot: SourceSnapshot,
        _ options: DisplayOptions,
        _ bass: BassView?,
        _ needsCanvas: Bool,
        _ userShapes: UserShapeLibrary,
    ) async -> Rendered {
        await Task.detached(priority: .userInitiated) {
            let models = renderModels(
                snapshot.document,
                options: options,
                bass: bass,
                needsCanvas: needsCanvas,
                userShapes: userShapes,
            )
            return Rendered(
                preview: models.preview,
                diagnostics: snapshot.diagnostics,
                canvas: models.canvas,
            )
        }.value
    }
}
