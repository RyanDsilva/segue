// P8-2: accessibility identifiers of the stage map, passes, jump and loop, and single-song
// sessions. Mirror new IDs in the UITests target (it cannot import SegueUI).

public extension AccessibilityID {
    /// The section map strip under the stage header.
    static let liveMap = "segue.live.map"
    /// The "Jumped to ..." confirmation.
    static let liveJumped = "segue.live.jumped"
    /// The header's "Looping ..." pill (rehearsal).
    static let liveLoop = "segue.live.loop"
    /// The song detail header's Rehearse and Live buttons.
    static let librarySongRehearse = "segue.library.song.rehearse"
    static let librarySongLive = "segue.library.song.live"

    /// Map chip `number` (1-based among the shown passes).
    static func liveMapChip(_ number: Int) -> String {
        "segue.live.map.chip.\(number)"
    }

    /// The gutter pass badge of shown pass `number` (1-based).
    static func livePassBadge(_ number: Int) -> String {
        "segue.live.passBadge.\(number)"
    }
}
