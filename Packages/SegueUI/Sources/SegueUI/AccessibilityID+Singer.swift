// P9-2: accessibility identifiers of singer view (the stage chip, the previews, the Singer
// Screen). Mirror new IDs in the UITests target (it cannot import SegueUI).

public extension AccessibilityID {
    /// The stage header's "Singer" chip.
    static let liveSinger = "segue.live.singer"
    /// Settings > Live: "Show lyrics only on stage (Singer view)".
    static let settingsSingerView = "segue.settings.singerView"
    /// The pre-show checklist's "Show Chords" button on the singer view row.
    static let checklistShowChords = "segue.checklist.showChords"
    /// The pre-show checklist's "Singer Screen: no second display" warning (R188).
    static let checklistSingerScreen = "segue.checklist.singerScreen"
    /// The library detail pane's "Chords / Singer" control.
    static let librarySingerPreview = "segue.library.singerPreview"
    /// The editor's "Chords / Singer" control in the display group.
    static let editorDisplaySinger = "segue.editor.display.singer"
    /// The bar over the editor's read-only singer page in Visual mode, and its Turn Off.
    static let editorSingerBar = "segue.editor.singerBar"
    static let editorSingerTurnOff = "segue.editor.singerBar.turnOff"
    /// The Singer Screen window's content.
    static let singerScreen = "segue.singerScreen"
}
