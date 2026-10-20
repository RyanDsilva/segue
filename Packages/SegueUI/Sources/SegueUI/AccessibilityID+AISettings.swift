// P3-3: accessibility identifiers of Settings > AI. Mirror new IDs in the UITests target (it
// cannot import SegueUI).

public extension AccessibilityID {
    /// "Use AI to refine pastes and set requests".
    static let settingsAIUseAI = "segue.settings.ai.useAI"
    /// The Apple Intelligence status line (available, or the R69 note).
    static let settingsAIAppleIntelligence = "segue.settings.ai.appleIntelligence"
    static let settingsAIOpenSystemSettings = "segue.settings.ai.openSystemSettings"

    /// One model card, by model id.
    static func settingsAIModel(_ id: String) -> String {
        "segue.settings.ai.model.\(id)"
    }

    /// The card's facts line: download size, memory need, licence.
    static let settingsAIModelSize = "segue.settings.ai.model.size"
    static let settingsAIModelLicense = "segue.settings.ai.model.license"
    static let settingsAIModelMemory = "segue.settings.ai.model.memory"
    static let settingsAIFreeDisk = "segue.settings.ai.freeDisk"
    /// The state line (Not downloaded, Downloading 40%, Installed, the failure).
    static let settingsAIModelState = "segue.settings.ai.model.state"
    static let settingsAIDownload = "segue.settings.ai.model.download"
    static let settingsAICancel = "segue.settings.ai.model.cancel"
    static let settingsAIDelete = "segue.settings.ai.model.delete"
    static let settingsAIDeleteConfirm = "segue.settings.ai.model.delete.confirm"
    static let settingsAIProgress = "segue.settings.ai.model.progress"
    /// The under-16 GB note (R68).
    static let settingsAILowMemory = "segue.settings.ai.lowMemory"
    /// The Personal-only Advanced section (R62).
    static let settingsAIAdvanced = "segue.settings.ai.advanced"
}
