import Foundation

// MARK: - Throttling

/// How often an event may be sent (spec 3.4 and section 5's Throttle column).
public enum ThrottleRule: Sendable, Hashable {
    /// Every occurrence (rare by nature).
    case perOccurrence
    /// At most once per local calendar day per key.
    case daily(key: String)
    /// Once per install per key (milestones).
    case once(key: String)
}

public extension AnalyticsEvent {
    /// The event's throttle rule. Keys are built from the signal name and fixed raw values.
    var throttle: ThrottleRule {
        let name = "Segue.\(area).\(eventName)"
        switch self {
        case .aiAssistantUsed, .aiModelDownload, .aiPasteFinished, .analyticsEnabled,
             .feedbackSent, .libraryCreated, .setlistComposerSession, .showEnded, .showStarted,
             .songImported, .timingTapCaptured:
            return .perOccurrence
        case .appLaunched, .librarySnapshot, .songDeleted:
            return .daily(key: name)
        case let .songCreated(source, nearDuplicate):
            return .daily(key: "\(name)|\(source.rawValue)|\(nearDuplicate)")
        case let .featureUsed(feature, context):
            return .daily(key: "\(name)|\(feature.rawValue)|\(context.rawValue)")
        case let .editorOpened(mode):
            return .daily(key: "\(name)|\(mode.rawValue)")
        case let .setlistCreated(source):
            return .daily(key: "\(name)|\(source.rawValue)")
        case let .milestoneReached(milestone, _):
            return .once(key: "\(name)|\(milestone.rawValue)")
        case let .helpOpened(item):
            return .daily(key: "\(name)|\(item.rawValue)")
        case let .errorOccurred(code):
            return .daily(key: "\(name)|\(code.rawValue)")
        case let .searchPerformed(context, tier, _):
            return .daily(key: "\(name)|\(context.rawValue)|\(tier.rawValue)")
        case let .editorChordPalette(action, _):
            return .daily(key: "\(name)|\(action.rawValue)")
        case let .aiSmartFilterUsed(action, _):
            return .daily(key: "\(name)|\(action.rawValue)")
        case let .notesEdited(summary):
            return .daily(key: "\(name)|\(summary.action.rawValue)|\(summary.kind.rawValue)|"
                + summary.placement.rawValue)
        case let .setlistComposed(summary):
            return .daily(key: "\(name)|\(summary.action.rawValue)|\(summary.tier.rawValue)|"
                + String(summary.alternative))
        case let .walkUpPicked(summary):
            return .daily(key: "\(name)|\(summary.kind.rawValue)|\(summary.rank.rawValue)|"
                + summary.genre.rawValue)
        case let .fillSaved(summary):
            return .daily(key: "\(name)|\(summary.family.rawValue)|\(summary.rank.rawValue)|"
                + String(summary.edited))
        case let .timingKeyChange(action, interval):
            return .daily(key: "\(name)|\(action.rawValue)|\(interval.rawValue)")
        case let .setlistTimed(summary):
            return .daily(key: "\(name)|\(summary.target.rawValue)")
        case let .songArtistSplit(summary):
            return .daily(key: "\(name)|\(summary.source.rawValue)|"
                + "\(summary.separator.rawValue)|\(summary.outcome.rawValue)")
        }
    }
}
