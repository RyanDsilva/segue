import Foundation

/// Row 12 parameters.
public struct ShowSummary: Sendable, Hashable {
    public var kind: AnalyticsShowKind
    public var duration: DurationBucket
    public var played: SmallBucket
    public var skipped: SmallBucket
    public var requestsUsed: Bool
    public var autoScrollUsed: Bool
    public var reordered: Bool
    public var endedBy: ShowEndReason
    /// Singer view was on at any time during the run (P9-2 section 13).
    public var singerView: Bool

    public init(
        kind: AnalyticsShowKind,
        duration: DurationBucket,
        played: SmallBucket,
        skipped: SmallBucket,
        requestsUsed: Bool,
        autoScrollUsed: Bool,
        reordered: Bool,
        endedBy: ShowEndReason,
        singerView: Bool = false,
    ) {
        self.kind = kind
        self.duration = duration
        self.played = played
        self.skipped = skipped
        self.requestsUsed = requestsUsed
        self.autoScrollUsed = autoScrollUsed
        self.reordered = reordered
        self.endedBy = endedBy
        self.singerView = singerView
    }
}
