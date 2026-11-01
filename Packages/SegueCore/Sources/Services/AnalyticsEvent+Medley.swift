import Foundation

// Medley analytics (P9-3 section 14): row 32 of the closed vocabulary. Enums and buckets
// only: never medley titles, transition text, item IDs or keys.

/// Row 32 `segue.action`: what a builder medley action did.
public enum MedleyAction: String, Sendable, CaseIterable {
    case created
    case ungrouped
    case memberAdded
    case memberRemoved
    case memberMoved
    case renamed
    case transitionEdited
}

/// Row 32 `segue.entry`: where the action came from.
public enum MedleyEntryPoint: String, Sendable, CaseIterable {
    case menu
    case contextMenu
    case composer
    case drag
    case key
}

extension AnalyticsEvent {
    /// Row 32's parameters.
    var medleyParams: [String: String] {
        guard case let .setlistMedley(action, members, entry) = self else { return [:] }
        return [
            "segue.action": action.rawValue,
            "segue.members": members.rawValue,
            "segue.entry": entry.rawValue,
        ]
    }
}
