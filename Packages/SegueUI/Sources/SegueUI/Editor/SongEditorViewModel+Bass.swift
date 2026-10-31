import ChordPro
import Diagrams
import Editing
import Library
import Observation

/// The bass-note view in the editor (P8-4 6.3, 6.5): the user-level profile, never the song's.
extension SongEditorViewModel {
    /// Whether the bass-note view is on (user-level, R158 Q7).
    var showsBassNotes: Bool {
        instrument?.profile.bassNotes ?? false
    }

    /// "I play bass" (P8-4 6.5): the top bar's diagram group becomes the bassist's.
    var playsBass: Bool {
        instrument?.profile.playsBass ?? false
    }

    /// The bassist's fretboard strip (user-level, the top bar's "Fretboard" button).
    var showsFretboard: Bool {
        instrument?.profile.fretboard ?? false
    }

    /// Flips the bassist's fretboard strip for every song; the song's own guitar or piano
    /// diagrams setting is never touched.
    func toggleFretboard() {
        instrument?.update { $0.fretboard.toggle() }
    }

    /// "Fills as tab" (P8-7 14.2): every saved fill as a mini tab, for every song and the
    /// stage (the same setting as `t` on stage and Settings > Instrument).
    var fillsAsTab: Bool {
        instrument?.profile.fillsAsTab ?? false
    }

    func toggleFillsAsTab() {
        instrument?.toggleFillsAsTab(from: .editor)
    }

    /// "Bass, BEADG": the Settings > Instrument tuning.
    var bassInstrumentTitle: String {
        "Bass, " + (instrument?.profile.tuning.name ?? Tuning.bassStandard4.name)
    }

    /// The editor's Bass segment: flips the user-level bass-note view for every song and
    /// the stage. The song's sidecar is never written.
    func toggleBassNotes() {
        // The observation (`observeInstrument`) re-renders this and every other open editor.
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
        bassPrefs: BassPrefs = BassPrefs(),
        parts: [Part] = [],
    ) -> (preview: RenderModel, canvas: RenderModel) {
        var preview = options
        preview.bass = bass
        // Walk-ups only in the bass-note view (R162 Q4); the canvas never shows them.
        let model = BassLine.annotated(
            RenderModel(document: document, options: preview, userShapes: userShapes),
            document: document,
            prefs: bassPrefs,
            parts: parts,
        )
        guard needsCanvas else { return (model, model) }
        var chart = options
        chart.showDiagrams = false
        return (model, RenderModel(document: document, options: chart))
    }

    /// The user's bass view, the song's walk-up picks and its fills, for one background
    /// render.
    struct BassRender: Sendable {
        var view: BassView?
        var prefs: BassPrefs
        var parts: [Part]
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
        _ bass: BassRender,
        _ needsCanvas: Bool,
        _ userShapes: UserShapeLibrary,
    ) async -> Rendered {
        await Task.detached(priority: .userInitiated) {
            let models = renderModels(
                snapshot.document,
                options: options,
                bass: bass.view,
                needsCanvas: needsCanvas,
                userShapes: userShapes,
                bassPrefs: bass.prefs,
                parts: bass.parts,
            )
            return Rendered(
                preview: models.preview,
                diagnostics: snapshot.diagnostics,
                canvas: models.canvas,
            )
        }.value
    }
}
