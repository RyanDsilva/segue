// P8-4a: accessibility identifiers of the bass-note view, Settings > Instrument and the
// stage mini neck. Mirror new IDs in the UITests target (it cannot import SegueUI).

public extension AccessibilityID {
    /// The editor's Bass segment (the user-level bass-note view).
    static let editorBass = "segue.editor.bass"
    /// The small concert chord beside a bass note on stage.
    static let liveChordDetail = "segue.live.chordDetail"
    /// A walk-up run on stage (P8-4b section 8.8).
    static let liveWalkUp = "segue.live.walkUp"
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
    static let settingsInstrumentFretboard = "segue.settings.instrument.fretboard"
    static let settingsInstrumentWalkUps = "segue.settings.instrument.walkUps"
    static let settingsInstrumentGenre = "segue.settings.instrument.genre"

    /// A walk-up run in the editor or library preview (a button, P8-4b section 8.9).
    static let sheetWalkUp = "segue.walkUp.run"
    /// The walk-up picker popover and its rows.
    static let walkUpPopover = "segue.walkUp.popover"
    static func walkUpOption(_ index: Int) -> String {
        "segue.walkUp.option.\(index)"
    }

    static let walkUpNothing = "segue.walkUp.nothing"
    static let walkUpReset = "segue.walkUp.reset"
    /// The score breakdown under a row while Option is held.
    static let walkUpBreakdown = "segue.walkUp.breakdown"

    /// The Walk-ups list (P8-4b 8.9): its openers in the editor and the library, the sheet,
    /// its feel and scale pickers, rows, and the unmatched footer.
    static let editorWalkUps = "segue.editor.walkUps"
    static let librarySongWalkUps = "segue.library.song.walkUps"
    static let walkUpsSheet = "segue.walkUps.sheet"
    static let walkUpsFeel = "segue.walkUps.feel"
    static let walkUpsScale = "segue.walkUps.scale"
    static let walkUpsDone = "segue.walkUps.done"
    static let walkUpsUnmatched = "segue.walkUps.unmatched"
    static let walkUpsRemoveAll = "segue.walkUps.removeAll"
    static func walkUpsRow(_ index: Int) -> String {
        "segue.walkUps.row.\(index)"
    }

    static func walkUpsRemove(_ index: Int) -> String {
        "segue.walkUps.remove.\(index)"
    }

    /// The editor top bar's bassist controls (P8-4 6.5): the Fretboard button and the
    /// "Bass, BEADG" menu.
    static let editorFretboard = "segue.editor.fretboard"
    static let editorBassInstrument = "segue.editor.bassInstrument"
}
