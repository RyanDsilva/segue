// P8-4a: accessibility identifiers of the bass-note view, Settings > Instrument and the
// stage mini neck. Mirror new IDs in the UITests target (it cannot import SegueUI).

public extension AccessibilityID {
    /// The editor's Bass segment (the user-level bass-note view).
    static let editorBass = "segue.editor.bass"
    /// The small concert chord beside a bass note on stage.
    static let liveChordDetail = "segue.live.chordDetail"
    /// The stage mini neck.
    static let liveBassNeck = "segue.live.bassNeck"
    /// The stage header's scale line.
    static let liveBassScale = "segue.live.bassScale"

    /// Settings > Instrument controls.
    static let settingsInstrumentBassNotes = "segue.settings.instrument.bassNotes"
    static let settingsInstrumentChordBeside = "segue.settings.instrument.chordBeside"
    static let settingsInstrumentStageNeck = "segue.settings.instrument.stageNeck"
    static let settingsInstrumentPlaysBass = "segue.settings.instrument.playsBass"
    static let settingsInstrumentStrings = "segue.settings.instrument.strings"
    static let settingsInstrumentTuning = "segue.settings.instrument.tuning"
    static let settingsInstrumentCustomTuning = "segue.settings.instrument.customTuning"
}
