import Foundation
import Setlists

/// The medley a show item plays in (P9-3 5.4): copied at show start like `overrides`, so
/// the gig log stays truthful after the setlist is edited. Consecutive items with the same
/// `slot` are one medley: the stage lays them out as one plan.
public struct ShowMedleyRef: Sendable, Hashable, Codable {
    /// The medley's setlist slot ID.
    public var slot: SetlistItemID
    /// The medley's title at start; nil = "Medley".
    public var title: String?
    /// This member's index among the members that play (0-based).
    public var index: Int
    /// How many members play.
    public var count: Int
    /// The transition into this member; nil for the first.
    public var transition: String?

    public init(
        slot: SetlistItemID,
        title: String?,
        index: Int,
        count: Int,
        transition: String? = nil,
    ) {
        self.slot = slot
        self.title = title
        self.index = index
        self.count = count
        self.transition = transition
    }

    /// "Medley" when untitled.
    public var displayTitle: String {
        SetlistMedley(title: title, members: []).displayTitle
    }

    /// Whether this is the medley's last member.
    public var isLast: Bool {
        index == count - 1
    }
}
