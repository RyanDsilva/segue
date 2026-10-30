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

    /// Settings > Audio controls.
    static let settingsAudioChordSound = "segue.settings.audio.chordSound"
    static let settingsAudioChordStyle = "segue.settings.audio.chordStyle"
    static let settingsAudioBassSound = "segue.settings.audio.bassSound"
    static let settingsAudioVolume = "segue.settings.audio.volume"
    static let settingsAudioTest = "segue.settings.audio.test"
}
