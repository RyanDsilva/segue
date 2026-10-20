// P3-7: accessibility identifiers of the set assistant's command bar and its row scores.
// Mirror new IDs in the UITests target (it cannot import SegueUI).

public extension AccessibilityID {
    static let assistantBar = "segue.assistant.bar"
    static let assistantField = "segue.assistant.field"
    static let assistantBuild = "segue.assistant.build"
    static let assistantRebuild = "segue.assistant.rebuild"
    static let assistantChips = "segue.assistant.chips"
    /// A stated chip (lexicon, hand-added or accepted).
    static let assistantChip = "segue.assistant.chip"
    /// A dashed suggestion from the local model.
    static let assistantSuggestedChip = "segue.assistant.suggested"
    static let assistantStatus = "segue.assistant.status"
    /// R107: "N songs left out: no length".
    static let assistantLeftOut = "segue.assistant.leftOut"
    static let assistantLeftOutList = "segue.assistant.leftOut.list"
    /// A row's score (hover, Space or VoiceOver opens the breakdown).
    static let entryScore = "segue.setlist.entry.score"
    static let entryLock = "segue.setlist.entry.lock"
    static let assistantBreakdown = "segue.assistant.breakdown"
}

public extension AccessibilityID {
    /// The stage search's lexicon chips (P3-7).
    static let liveSearchChips = "segue.live.search.chips"
}

public extension AccessibilityID {
    /// The library search's lexicon chips and local-model suggestions (P3-7).
    static let librarySearchChips = "segue.library.search.chips"
    static let librarySearchChip = "segue.library.search.chip"
}
