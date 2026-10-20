// Phase 3 (P3-14): accessibility identifiers of the stage metronome. Mirror new IDs in the
// UITests target (it cannot import SegueUI).

public extension AccessibilityID {
    /// The pulse overlay on stage.
    static let liveMetronome = "segue.live.metronome"
    /// The pre-show checklist's metronome switch.
    static let checklistMetronome = "segue.live.checklist.metronome"
    /// The pre-show checklist's rehearsal click switch.
    static let checklistMetronomeClick = "segue.live.checklist.metronomeClick"
    /// Settings > Live: start shows with the metronome on.
    static let settingsMetronome = "segue.settings.live.metronome"
}
