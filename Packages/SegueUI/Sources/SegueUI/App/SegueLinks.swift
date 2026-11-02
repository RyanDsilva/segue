import Foundation

/// Every external URL the app knows, in one place (WS2a 3.1). Nothing else may spell the
/// site's host, the support address or an App Store URL: a SwiftLint rule fails the build
/// otherwise. Paths and anchors must be in WS4's URL and anchor table (I-16). Links open in
/// the default browser through `WorkspaceActions`, never an in-app web view.
public enum SegueLinks {
    /// The website.
    public static let site = url("https://segue.ryandsilva.dev")
    /// Help > Segue Help: the user guide (R126; `/help` redirects to it).
    public static let help = url("https://segue.ryandsilva.dev/guide")
    /// Help > Privacy Policy (Guideline 5.1.1(i)); the Privacy pane links it too.
    public static let privacy = url("https://segue.ryandsilva.dev/privacy")
    /// Help > Terms of Use: the site terms, which link Apple's standard EULA (R7).
    public static let terms = url("https://segue.ryandsilva.dev/terms")
    /// About credits.
    public static let support = url("https://segue.ryandsilva.dev/support")
    /// Release notes on the web: What's New's fallback and "All Release Notes" (B-14).
    public static let changelog = url("https://segue.ryandsilva.dev/changelog")
    /// The feature board (redirects to the board vendor, R29).
    public static let feedback = url("https://segue.ryandsilva.dev/feedback")
    /// The support address (R28): Report a Problem's fallback.
    public static let supportEmail = url("mailto:\(supportAddress)")
    /// The bare support address (R28), for copy and the bug report's email draft.
    public static let supportAddress = "segue@ryandsilva.dev"
    /// "What Segue collects": the policy's usage statistics section (Settings > Privacy).
    public static let privacyUsage = url("https://segue.ryandsilva.dev/privacy#usage-statistics")
    /// The host of the bug-report and crash service, named in the report preview's footer
    /// (WS3 spec 8.3). Shown as text, never opened.
    public static let bugReportServiceHost = "sentry.io"

    /// Segue's numeric App Store Apple ID; nil until the App Store Connect record exists
    /// (WS5 fills it). Help > Rate Segue on the App Store is hidden while it is nil.
    public static let appStoreID: String? = nil

    /// The App Store app's Write a Review sheet for Segue; nil while `appStoreID` is nil.
    public static var writeReview: URL? {
        writeReview(appStoreID: appStoreID)
    }

    /// The Write a Review URL for `appStoreID` (the spike in WS2a step 0 confirmed the App
    /// Store app opens it).
    public static func writeReview(appStoreID: String?) -> URL? {
        guard let appStoreID, !appStoreID.isEmpty else { return nil }
        return URL(string: "macappstore://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }

    /// The user guide pages the app opens from Help buttons, tips and menus (WS6 7.2). Each
    /// raw value is the full URL, so `gen-site.swift --check` resolves every one against the
    /// built guide (page and `#id`): a renamed page or heading fails the site check.
    public enum Guide: String, CaseIterable, Sendable {
        case home = "https://segue.ryandsilva.dev/guide"
        case keyboard = "https://segue.ryandsilva.dev/guide/keyboard"
        case pasteASong = "https://segue.ryandsilva.dev/guide/paste-a-song"
        case pasteReview = "https://segue.ryandsilva.dev/guide/paste-a-song#review"
        case importBatch = "https://segue.ryandsilva.dev/guide/import-files#batch"
        case search = "https://segue.ryandsilva.dev/guide/library-folder#search"
        case fileSync = "https://segue.ryandsilva.dev/guide/library-folder#file-sync"
        case songCard = "https://segue.ryandsilva.dev/guide/song-card"
        case moveChord = "https://segue.ryandsilva.dev/guide/edit-a-song#chords"
        case sectionNotes = "https://segue.ryandsilva.dev/guide/section-notes"
        case transpose = "https://segue.ryandsilva.dev/guide/transpose#transpose"
        case setAssistant = "https://segue.ryandsilva.dev/guide/set-assistant"
        case medleys = "https://segue.ryandsilva.dev/guide/medleys"
        case unknownTimes = "https://segue.ryandsilva.dev/guide/running-time#unknown"
        case arrangeSections = "https://segue.ryandsilva.dev/guide/arrange-sections"
        case pdf = "https://segue.ryandsilva.dev/guide/print-and-pdf"
        case smartFilters = "https://segue.ryandsilva.dev/guide/smart-filters#smart"
        case goOnStage = "https://segue.ryandsilva.dev/guide/go-on-stage"
        case singerView = "https://segue.ryandsilva.dev/guide/singer-view"
        case checklist = "https://segue.ryandsilva.dev/guide/go-on-stage#checklist"
        case minimumSize = "https://segue.ryandsilva.dev/guide/go-on-stage#minimum-size"
        case gigMode = "https://segue.ryandsilva.dev/guide/gig-mode"
        case ai = "https://segue.ryandsilva.dev/guide/ai"
        case privacySettings = "https://segue.ryandsilva.dev/guide/privacy-settings"
        case backUp = "https://segue.ryandsilva.dev/guide/back-up"
        /// Troubleshooting's "Built-in help" (P9-5 7).
        case builtInHelp = "https://segue.ryandsilva.dev/guide/troubleshooting#help"

        public var url: URL {
            SegueLinks.url(rawValue)
        }

        /// The page's name, for the Help button's accessibility label ("Help: Song card").
        public var title: String {
            switch self {
            case .home: uiString("Segue Guide")
            case .keyboard: uiString("Keyboard shortcuts")
            case .pasteASong, .pasteReview: uiString("Paste a song")
            case .importBatch: uiString("Import files")
            case .search: uiString("Search")
            case .fileSync: uiString("Your library folder")
            case .songCard: uiString("The song card")
            case .moveChord: uiString("Edit a song")
            case .sectionNotes: uiString("Section notes")
            case .transpose: uiString("Transpose and capo")
            case .setAssistant: uiString("Set assistant")
            case .medleys: uiString("Medleys")
            case .unknownTimes: uiString("Running time")
            case .arrangeSections: uiString("Arrange sections")
            case .pdf: uiString("Print and PDF")
            case .smartFilters: uiString("Smart filters")
            case .goOnStage: uiString("Go on stage")
            case .singerView: uiString("Singer view")
            case .checklist: uiString("Pre-show checklist")
            case .minimumSize: uiString("Lyrics on stage")
            case .gigMode: uiString("Gig Mode Shortcuts")
            case .ai: uiString("AI in Segue")
            case .privacySettings: uiString("Privacy settings")
            case .backUp: uiString("Back up and restore")
            case .builtInHelp: uiString("Built-in help")
            }
        }
    }

    private static func url(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("Invalid built-in URL \(string)")
        }
        return url
    }
}
