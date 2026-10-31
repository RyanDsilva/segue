// P8-6: accessibility identifiers of hearing chords, auditioning walk-ups and Settings >
// Audio. Mirror new IDs in the UITests target (it cannot import SegueUI).

public extension AccessibilityID {
    /// A walk-up option's play button in the picker, by letter ("A"); "nothing" for the
    /// "Nothing here" row.
    static func walkUpPlay(_ letter: String) -> String {
        "segue.walkUp.play.\(letter)"
    }

    /// The picker's Loop switch.
    static let walkUpLoop = "segue.walkUp.loop"
    /// The highlighted option's "Use this" button.
    static let walkUpUse = "segue.walkUp.use"
    /// A Walk-ups list row's play button.
    static let walkUpsPlay = "segue.walkUps.play"

    /// Play along (P8-6 10.3, 10.4): the toolbar / pane button, the bar and its controls.
    static let playAlongToggle = "segue.playAlong.toggle"
    static let playAlongBar = "segue.playAlong.bar"
    static let playAlongPlay = "segue.playAlong.play"
    static let playAlongRange = "segue.playAlong.range"
    static let playAlongLoop = "segue.playAlong.loop"
    static let playAlongClose = "segue.playAlong.close"
    static let playAlongTempo = "segue.playAlong.tempo"
    static let playAlongTiming = "segue.playAlong.timing"
    static let playAlongLane = "segue.playAlong.lane"
    static let playAlongBlock = "segue.playAlong.block"
    static let playAlongBeats = "segue.playAlong.beats"
    static let playAlongUseRule = "segue.playAlong.useRule"
    static let playAlongNote = "segue.playAlong.note"
    /// The stage header's "Playing along" pill.
    static let livePlayAlong = "segue.live.playAlong"

    /// A voice toggle ("bass", "chords", "click", "walkUps").
    static func playAlongVoice(_ voice: String) -> String {
        "segue.playAlong.voice.\(voice)"
    }

    /// A tempo percentage button (50, 75, 100).
    static func playAlongTempoPercent(_ percent: Int) -> String {
        "segue.playAlong.tempo.\(percent)"
    }

    /// Settings > Audio controls.
    static let settingsAudioOutput = "segue.settings.audio.output"
    static let settingsAudioChordSound = "segue.settings.audio.chordSound"
    static let settingsAudioChordStyle = "segue.settings.audio.chordStyle"
    static let settingsAudioBassSound = "segue.settings.audio.bassSound"
    static let settingsAudioVolume = "segue.settings.audio.volume"
    static let settingsAudioTest = "segue.settings.audio.test"
}
