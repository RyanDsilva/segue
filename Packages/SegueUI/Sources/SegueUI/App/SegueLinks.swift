import Foundation

/// Every external URL the app knows, in one place (WS2a 3.1). Nothing else may spell the
/// site's host, the support address or an App Store URL: a SwiftLint rule fails the build
/// otherwise. Paths and anchors must be in WS4's URL and anchor table (I-16). Links open in
/// the default browser through `WorkspaceActions`, never an in-app web view.
public enum SegueLinks {
    /// The website.
    public static let site = url("https://segue.ryandsilva.dev")
    /// Help > Segue Help (R21).
    public static let help = url("https://segue.ryandsilva.dev/help")
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
    /// Third-party licences on the web (About credits, A34).
    public static let acknowledgements = url("https://segue.ryandsilva.dev/acknowledgements")
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

    /// A help page, e.g. `helpPage("keyboard")` is `/help/keyboard`. Only paths in WS4's URL
    /// table may be used; its link checker is the contract.
    public static func helpPage(_ path: String) -> URL {
        help.appending(path: path, directoryHint: .notDirectory)
    }

    private static func url(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("Invalid built-in URL \(string)")
        }
        return url
    }
}
