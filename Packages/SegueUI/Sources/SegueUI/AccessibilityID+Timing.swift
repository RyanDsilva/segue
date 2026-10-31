// P8-7b: accessibility identifiers of the chord-length lane's additions, Tap Timing, the
// key-change chip and the directive inserts. Mirror new IDs in the UITests target (it cannot
// import SegueUI) when a UI test uses them.

public extension AccessibilityID {
    /// A key, time or tempo change marked above a lane block.
    static let playAlongMarker = "segue.playAlong.marker"
    /// The selected block's Push pop-up.
    static let playAlongPush = "segue.playAlong.push"

    /// Tap Timing (P8-7 section 7): the bar's button, its panel and controls.
    static let playAlongTap = "segue.playAlong.tap"
    static let playAlongTapPanel = "segue.playAlong.tap.panel"
    static let playAlongTapPad = "segue.playAlong.tap.pad"
    static let playAlongTapStop = "segue.playAlong.tap.stop"
    static let playAlongTapSummary = "segue.playAlong.tap.summary"
    static let playAlongTapTempo = "segue.playAlong.tap.tempo"
    static let playAlongTapSetTempo = "segue.playAlong.tap.setTempo"
    static let playAlongTapDiscard = "segue.playAlong.tap.discard"
    static let playAlongTapKeep = "segue.playAlong.tap.keep"

    /// The tap panel's mode segment ("click", "free").
    static func playAlongTapMode(_ mode: String) -> String {
        "segue.playAlong.tap.mode.\(mode)"
    }
}
