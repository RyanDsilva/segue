// P8-7b: accessibility identifiers of the chord-length lane's additions, Tap Timing, the
// key-change chip and the directive inserts. Mirror new IDs in the UITests target (it cannot
// import SegueUI) when a UI test uses them.

public extension AccessibilityID {
    /// A key, time or tempo change marked above a lane block.
    static let playAlongMarker = "segue.playAlong.marker"
    /// The selected block's Push pop-up.
    static let playAlongPush = "segue.playAlong.push"
}
