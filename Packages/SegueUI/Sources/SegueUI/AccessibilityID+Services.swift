// WS3: accessibility identifiers of the consent prompt, Settings > Privacy and Report a
// Problem. Mirror new IDs in the UITests target (it cannot import SegueUI).

public extension AccessibilityID {
    // MARK: Consent prompt (ConsentSheet, ConsentChoiceView)

    /// The sheet's title.
    static let consentSheet = "segue.consent.sheet"
    static let consentContinue = "segue.consent.continue"
    /// "Don't Share" / "Don't Send".
    static func consentDecline(_ toggle: ConsentStore.Toggle) -> String {
        "segue.consent.\(toggle.rawValue).decline"
    }

    /// "Share" / "Send".
    static func consentAccept(_ toggle: ConsentStore.Toggle) -> String {
        "segue.consent.\(toggle.rawValue).accept"
    }

    static func consentWhatsSent(_ toggle: ConsentStore.Toggle) -> String {
        "segue.consent.\(toggle.rawValue).whatsSent"
    }

    /// A policy link by its title ("Privacy Policy", "What Segue collects").
    static func privacyPolicyLink(_ title: String) -> String {
        "segue.privacy.link.\(title.filter(\.isLetter).lowercased())"
    }

    // MARK: Settings > Privacy

    static func privacyToggle(_ toggle: ConsentStore.Toggle) -> String {
        "segue.privacy.\(toggle.rawValue).toggle"
    }

    /// What turning the toggle off did, and how to request deletion.
    static func privacyCaption(_ toggle: ConsentStore.Toggle) -> String {
        "segue.privacy.\(toggle.rawValue).caption"
    }

    static let privacyDiagnosticsID = "segue.privacy.diagnosticsID"
    static let privacyCopyID = "segue.privacy.diagnosticsID.copy"
    /// "Crash reporting starts the next time you open Segue." (A11)
    static let privacyRestartCaption = "segue.privacy.crashReports.restart"
    /// "Analytics and crash reporting are not part of this build."
    static let privacyUnavailable = "segue.privacy.unavailable"
}
