// P8-7d: accessibility identifiers of the bass fill editor. Mirror new IDs in the UITests
// target (it cannot import SegueUI).

public extension AccessibilityID {
    /// "Create Bass Fill..." under a selected span (P8-7 section 12.1).
    static let fillCreate = "segue.fill.create"
    /// A chord unit inside the selected span.
    static let fillSpanUnit = "segue.fill.spanUnit"
    /// The fill editor sheet (section 12.2).
    static let fillEditor = "segue.fill.editor"
    /// The Fretboard | Piano Roll toggle.
    static let fillView = "segue.fill.view"
    static let fillViewFretboard = "segue.fill.view.fretboard"
    static let fillViewPianoRoll = "segue.fill.view.pianoRoll"
    /// A candidate row, by letter ("a" ... "e", "saved").
    static func fillCandidate(_ letter: String) -> String {
        "segue.fill.candidate.\(letter.lowercased())"
    }

    static func fillCandidatePlay(_ letter: String) -> String {
        "segue.fill.candidate.\(letter.lowercased()).play"
    }

    static let fillMore = "segue.fill.more"
    static let fillScratch = "segue.fill.scratch"
    static let fillLoop = "segue.fill.loop"
    static let fillClick = "segue.fill.click"
    static let fillTempo = "segue.fill.tempo"
    static let fillRhythmSnap = "segue.fill.rhythmSnap"
    static let fillPitchSnap = "segue.fill.pitchSnap"
    static let fillNeck = "segue.fill.neck"
    static let fillGrid = "segue.fill.grid"
    static let fillPianoRoll = "segue.fill.pianoRoll"
    static let fillName = "segue.fill.name"
    static let fillShowsOn = "segue.fill.showsOn"
    static let fillShowAs = "segue.fill.showAs"
    static let fillSave = "segue.fill.save"
    static let fillCancel = "segue.fill.cancel"
    static let fillDelete = "segue.fill.delete"
    static let fillRevert = "segue.fill.revert"
    /// The fill editor's mini tab preview (P8-7 section 12.6).
    static let fillMiniTab = "segue.fill.miniTab"
    /// A saved fill's note names after a chord unit in a preview, and its tab block (P8-7
    /// section 14).
    static let sheetFillRun = "segue.sheet.fillRun"
    static let sheetFillTab = "segue.sheet.fillTab"
    /// The same on stage.
    static let liveFillRun = "segue.live.fillRun"
    static let liveFillTab = "segue.live.fillTab"
    /// "Fills as Tab" in the editor's Bass menu and Settings > Instrument's "Show fills as".
    static let editorFillsAsTab = "segue.editor.fillsAsTab"
    static let settingsInstrumentFillsAs = "segue.settings.instrument.fillsAs"
    /// The Walk-ups list's "Fills" group.
    static let walkUpsFills = "segue.walkUps.fills"
    static func walkUpsFill(_ index: Int) -> String {
        "segue.walkUps.fill.\(index)"
    }
}
