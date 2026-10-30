// P3-16, P8-3: accessibility identifiers of per-slot arrangements (R122, R123, R149).
// Mirror new IDs in the UITests target (it cannot import SegueUI).

public extension AccessibilityID {
    /// The slot popover's "Arrangement" row button ("Full song" / "Custom ...").
    static let arrangementOpen = "segue.setlist.arrangement.open"
    /// The slot row's "Custom arrangement" / "out of date" line.
    static let arrangementMark = "segue.setlist.arrangement.mark"
    static let arrangementSheet = "segue.setlist.arrangement.sheet"
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

    /// The lane of pass chips (P8-3).
    static let arrangementLane = "segue.setlist.arrangement.lane"
    /// The inspector's mode picker segments: full, chords, first, skip.
    static func arrangementMode(_ mode: String) -> String {
        "segue.setlist.arrangement.mode.\(mode)"
    }

    static let arrangementDuplicate = "segue.setlist.arrangement.duplicate"
    static let arrangementRemove = "segue.setlist.arrangement.remove"
    static let arrangementRoadmap = "segue.setlist.arrangement.roadmap"
    static let arrangementRoadmapError = "segue.setlist.arrangement.roadmapError"
    static let arrangementRehearse = "segue.setlist.arrangement.rehearse"

    /// Chip `index` (0-based lane position) and its hover buttons.
    static func arrangementChip(_ index: Int) -> String {
        "segue.setlist.arrangement.chip.\(index)"
    }

    static func arrangementChipDuplicate(_ index: Int) -> String {
        "segue.setlist.arrangement.chip.\(index).duplicate"
    }

    static func arrangementChipRemove(_ index: Int) -> String {
        "segue.setlist.arrangement.chip.\(index).remove"
    }

    /// Palette button `index` (label group, 0-based).
    static func arrangementPalette(_ index: Int) -> String {
        "segue.setlist.arrangement.palette.\(index)"
    }
}
