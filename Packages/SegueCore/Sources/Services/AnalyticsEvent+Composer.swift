import Foundation

// Set composer analytics (P8-5 section 10, R153): row 24 of the closed vocabulary, two
// signals. Enums, booleans and buckets only: never the typed text, titles, keys or IDs.

/// Row 24: `Segue.Setlist.composed`, one per Return in the composer, daily per action,
/// tier and whether an alternative was picked.
public struct ComposerSummary: Sendable, Hashable {
    public var action: ComposerAction
    public var tier: ComposerTier
    public var form: ComposerForm
    /// A candidate other than the first was accepted.
    public var alternative: Bool
    /// A key token ("in A") was applied to the new slot.
    public var key: Bool
    public var entry: ComposerEntry

    public init(
        action: ComposerAction,
        tier: ComposerTier,
        form: ComposerForm,
        alternative: Bool,
        key: Bool,
        entry: ComposerEntry,
    ) {
        self.action = action
        self.tier = tier
        self.form = form
        self.alternative = alternative
        self.key = key
        self.entry = entry
    }
}

/// What a Return in the composer did.
public enum ComposerAction: String, Sendable, CaseIterable {
    case song
    case `break`
    case alreadyInSet
    case noMatch
}

/// The matcher tier of the accepted (or flagged) candidate; `none` for a break or no
/// match. Mirrors `MatchTier` without importing the library.
public enum ComposerTier: String, Sendable, CaseIterable {
    case exactTitle
    case titlePrefix
    case titleWords
    case fuzzyTitle
    case firstLine
    /// P8-8 section 3.5.1: the line named an artist and the song is theirs.
    case artist
    case noTier = "none"
}

/// The spelling form the candidate matched in; `none` for a break or no match.
public enum ComposerForm: String, Sendable, CaseIterable {
    case original
    case normalized
    case loose
    case noForm = "none"
}

/// How the composer got focus for this session.
public enum ComposerEntry: String, Sendable, CaseIterable {
    /// Setlist > Add Song by Name (⌘L).
    case shortcut
    /// A click on the composer row (or keyboard focus from the set list).
    case click
}

extension AnalyticsEvent {
    /// Row 24's parameters (`params` for the two composer signals).
    var composerParams: [String: String] {
        switch self {
        case let .setlistComposed(summary):
            [
                "segue.action": summary.action.rawValue,
                "segue.tier": summary.tier.rawValue,
                "segue.form": summary.form.rawValue,
                "segue.alternative": String(summary.alternative),
                "segue.key": String(summary.key),
                "segue.entry": summary.entry.rawValue,
            ]
        case let .setlistComposerSession(songs, cycles):
            ["segue.songs": songs.rawValue, "segue.cycles": cycles.rawValue]
        default:
            [:]
        }
    }
}
