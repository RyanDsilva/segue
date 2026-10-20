// P3-16: accessibility identifiers of per-slot arrangements (R122, R123).
// Mirror new IDs in the UITests target (it cannot import SegueUI).

public extension AccessibilityID {
    /// The slot popover's "Arrangement" row button ("Full song" / "Custom ...").
    static let arrangementOpen = "segue.setlist.arrangement.open"
    /// The slot row's "Custom arrangement" / "out of date" line.
    static let arrangementMark = "segue.setlist.arrangement.mark"
    static let arrangementSheet = "segue.setlist.arrangement.sheet"
    static let arrangementLength = "segue.setlist.arrangement.length"
    static let arrangementReset = "segue.setlist.arrangement.reset"
    static let arrangementUpdate = "segue.setlist.arrangement.update"
    static let arrangementDone = "segue.setlist.arrangement.done"
    /// The banner listing rows that no longer match the song.
    static let arrangementMissing = "segue.setlist.arrangement.missing"
    /// The live preview of the stage.
    static let arrangementPreview = "segue.setlist.arrangement.preview"
    /// The stage header's "Arranged" / "Full song" note.
    static let liveArrangement = "segue.live.arrangement"
    /// The pre-show checklist row for out-of-date arrangements.
    static let checklistArrangements = "segue.checklist.arrangements"

    /// Row `index` (0-based, in the sheet's order) and its controls.
    static func arrangementRow(_ index: Int) -> String {
        "segue.setlist.arrangement.row.\(index)"
    }

    static func arrangementPlay(_ index: Int) -> String {
        "segue.setlist.arrangement.play.\(index)"
    }

    static func arrangementCount(_ index: Int) -> String {
        "segue.setlist.arrangement.count.\(index)"
    }

    static func arrangementCountUp(_ index: Int) -> String {
        "segue.setlist.arrangement.count.\(index).up"
    }

    static func arrangementCountDown(_ index: Int) -> String {
        "segue.setlist.arrangement.count.\(index).down"
    }
}
