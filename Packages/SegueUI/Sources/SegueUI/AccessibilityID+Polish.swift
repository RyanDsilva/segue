// WS2b: accessibility identifiers of the Welcome sheet, What's New, the Settings panes and
// the export. Consent identifiers are WS3's. Mirror new IDs in the UITests target (it cannot
// import SegueUI). Page 1 of the Welcome sheet reuses `chooserCreate` / `chooserOpen`.

public extension AccessibilityID {
    // MARK: Welcome sheet

    /// The sheet's title (every page).
    static let welcomeTitle = "segue.welcome.title"
    /// "Step n of m".
    static let welcomeStep = "segue.welcome.step"
    /// Page 1's inline "could not be opened" message.
    static let welcomeLibraryError = "segue.welcome.libraryError"
    /// Page 2's "Add 4 songs and a setlist…" checkbox.
    static let welcomeAddSongs = "segue.welcome.addSongs"
    static let welcomeContinue = "segue.welcome.continue"
    static let welcomeSeedError = "segue.welcome.seedError"
    static let welcomeRetry = "segue.welcome.retry"
    static let welcomeSkip = "segue.welcome.skip"
    /// Revisit mode: "Add Welcome Songs".
    static let welcomeAddButton = "segue.welcome.addWelcomeSongs"
    /// Revisit mode: "The Welcome songs are in your library (tag: Welcome)."
    static let welcomeInLibrary = "segue.welcome.inLibrary"
    static let welcomeDone = "segue.welcome.done"

    // MARK: What's New

    static let whatsNewTitle = "segue.whatsNew.title"
    /// One release section's heading, by version.
    static func whatsNewRelease(_ version: String) -> String {
        "segue.whatsNew.release.\(version)"
    }

    /// A highlight row's badge ("New", "Improved", "Fixed").
    static let whatsNewBadge = "segue.whatsNew.badge"
    static let whatsNewRow = "segue.whatsNew.row"
    static let whatsNewLearnMore = "segue.whatsNew.learnMore"
    static let whatsNewMore = "segue.whatsNew.more"
    static let whatsNewAllNotes = "segue.whatsNew.allNotes"
    static let whatsNewContinue = "segue.whatsNew.continue"

    // MARK: Settings

    /// A pane's root, by its tag ("general", "appearance", "live", "privacy", "data").
    static func settingsPane(_ pane: String) -> String {
        "segue.settings.pane.\(pane)"
    }

    static let settingsLibraryPath = "segue.settings.general.libraryPath"
    static let settingsChangeLibrary = "segue.settings.general.change"
    static let settingsShowLibrary = "segue.settings.general.showInFinder"
    static let settingsAppearance = "segue.settings.appearance.mode"
    static let settingsRebuildIndex = "segue.settings.data.rebuildIndex"
    static let settingsAddWelcome = "segue.settings.data.addWelcome"
    static let settingsRemoveWelcome = "segue.settings.data.removeWelcome"
    static let settingsRemoveWelcomeConfirm = "segue.settings.data.removeWelcome.confirm"
    static let settingsResetTips = "segue.settings.data.resetTips"
    static let settingsResetAll = "segue.settings.data.resetAll"
    static let settingsResetAllConfirm = "segue.settings.data.resetAll.confirm"
    /// The Data pane's last result line ("Tips will show again…", "Added 4 songs…").
    static let settingsDataStatus = "segue.settings.data.status"

    // MARK: Export

    static let exportArchive = "segue.export.archive"
    static let exportProgress = "segue.export.progress"
}
