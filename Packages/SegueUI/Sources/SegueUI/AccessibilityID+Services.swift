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

public extension AccessibilityID {
    // MARK: Report a Problem

    static let reportSheet = "segue.report.sheet"
    static let reportMessage = "segue.report.message"
    static let reportCounter = "segue.report.counter"
    static let reportProblem = "segue.report.problem"
    /// The error banner's Report... (P9-5 5, P1).
    static let errorBannerReport = "segue.errorBanner.report"
    static let reportEmail = "segue.report.email"
    static let reportAttachLogs = "segue.report.attach.logs"
    static let reportAttachMetricKit = "segue.report.attach.metricKit"
    static let reportAttachSong = "segue.report.attach.song"
    static let reportRequestFeature = "segue.report.requestFeature"
    static let reportPreviewButton = "segue.report.preview"
    static let reportSend = "segue.report.send"
    static let reportCancel = "segue.report.cancel"
    static let reportBack = "segue.report.back"
    static let reportEmailInstead = "segue.report.emailInstead"
    static let reportSaveReport = "segue.report.save"
    static let reportTryAgain = "segue.report.tryAgain"
    static let reportFailure = "segue.report.failure"
    static let reportSent = "segue.report.sent"
    static let reportDone = "segue.report.done"
    /// The preview's scrolling content.
    static let reportPreview = "segue.report.preview.content"
    /// One attachment's disclosure in the preview (label = file name).
    static let reportPreviewAttachment = "segue.report.preview.attachment"
    /// UI testing only: the frozen payload's SHA-256 as the element's label.
    static let reportPreviewHash = "segue.report.preview.hash"
}
