// P9-3 9.2-9.4: the medley on stage. Mirror new IDs in the UITests target (it cannot import
// SegueUI).

public extension AccessibilityID {
    /// The header's "Medley 2 of 3" chip (label "Love medley, song 2 of 3").
    static let liveMedley = "segue.live.medley"
    /// A member header block in the chart (label "Tum Hi Ho, 2 of 3, A, capo 2, 120").
    static let liveMemberHeader = "segue.live.medley.member"
    /// The transition under a member header ("Hold the D, drums fill").
    static let liveMemberTransition = "segue.live.medley.transition"
    /// The derived change line under a transition ("G → A · capo 2 → no capo").
    static let liveMemberChanges = "segue.live.medley.changes"
    /// A member's group of chips in the section map (label: the member's title).
    static let liveMapMember = "segue.live.map.member"
}
