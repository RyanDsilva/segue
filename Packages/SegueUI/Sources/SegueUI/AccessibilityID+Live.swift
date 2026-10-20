// Phase 2: accessibility identifiers of live mode (stage, overlays, checklist, settings).
// Owner: unit C. Mirror new IDs in the UITests target (it cannot import SegueUI).

public extension AccessibilityID {
    // Stage
    static let liveBody = "segue.live.body"
    static let liveLyric = "segue.live.lyric"
    static let liveCue = "segue.live.cue"
    static let liveEndOfSet = "segue.live.endOfSet"
    static let liveRehearsal = "segue.live.rehearsal"
    static let liveUpNextLabel = "segue.live.upNextLabel"
    static let liveScrollStatus = "segue.live.scrollStatus"
    static let liveRequestCount = "segue.live.requestCount"
    static let liveNotice = "segue.live.notice"
    static let liveProblem = "segue.live.problem"
    static let liveSongUnavailable = "segue.live.songUnavailable"
    static let liveIndicator = "segue.live.indicator"
    static let liveEndDialog = "segue.live.endDialog"
    static let liveEndConfirm = "segue.live.endConfirm"

    // Quick search
    static let liveSearch = "segue.live.search"
    static let liveSearchField = "segue.live.search.field"
    static let liveSearchResult = "segue.live.search.result"
    static let liveSearchPlayNow = "segue.live.search.playNow"
    static let liveSearchAddRequest = "segue.live.search.addRequest"
    static let liveSearchNote = "segue.live.search.note"
    static let liveSearchAddRequestConfirm = "segue.live.search.addRequestConfirm"
    static let liveSearchInsertNext = "segue.live.search.insertNext"
    /// R102: the "already in the show" message and its buttons.
    static let liveSearchRefusal = "segue.live.search.refusal"
    static let liveSearchMoveToNext = "segue.live.search.moveToNext"
    static let liveSearchRefusalBack = "segue.live.search.refusalBack"

    // Request queue and set order drawer
    static let liveRequests = "segue.live.requests"
    static let liveRequestRow = "segue.live.requests.row"
    static let liveRequestPlay = "segue.live.requests.play"
    static let liveDrawer = "segue.live.drawer"
    static let liveDrawerList = "segue.live.drawer.list"
    static let liveDrawerRow = "segue.live.drawer.row"
    static let liveDrawerPlayNext = "segue.live.drawer.playNext"
    static let liveDrawerSkip = "segue.live.drawer.skip"
    static let liveDrawerUnskip = "segue.live.drawer.unskip"

    /// Before the show
    static let checklist = "segue.live.checklist"
    /// The stage's keyboard help overlay (`?`) and one of its rows.
    static let keysOverlay = "segue.live.keys"
    static let keysOverlayRow = "segue.live.keys.row"
    static let checklistStart = "segue.live.checklist.start"
    static let checklistCancel = "segue.live.checklist.cancel"
    static let checklistRow = "segue.live.checklist.row"
    static let checklistMissing = "segue.live.checklist.missing"
    /// E2E instrumentation only: "<row title>: done" / "<row title>: not done".
    static let checklistRowState = "segue.live.checklist.row.state"
    static let checklistFocusDone = "segue.live.checklist.focus.done"
    static let checklistFocusRetry = "segue.live.checklist.focus.retry"
    static let resumeShow = "segue.live.resume"
    static let resumeShowResume = "segue.live.resume.resume"
    static let resumeShowEnd = "segue.live.resume.end"

    // Settings > Live
    static let settingsMinLyricSize = "segue.settings.live.minLyricSize"
    static let settingsDefaultColumns = "segue.settings.live.defaultColumns"
    static let settingsStartShortcut = "segue.settings.live.startShortcut"
    static let settingsEndShortcut = "segue.settings.live.endShortcut"
    static let settingsRehearsalShortcuts = "segue.settings.live.rehearsalShortcuts"
    static let settingsShortcutTestResult = "segue.settings.live.shortcutTestResult"
    static let settingsAutomationSettings = "segue.settings.live.automationSettings"
}
