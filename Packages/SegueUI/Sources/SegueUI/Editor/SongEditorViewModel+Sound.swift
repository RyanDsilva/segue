import Editing

/// Hearing chords in the editor (P8-6 10.1): the text-mode preview's chord units, ⌥-click
/// on the visual canvas's chord pills and the bass fretboard strip.
extension SongEditorViewModel {
    /// The preview's chord action (nil without sound).
    var chordHearing: ChordHearing? {
        sound?.hearing(
            model: { [weak self] in self?.renderModel },
            profile: { [weak self] in self?.instrument?.profile },
            context: .editor,
        )
    }

    /// The walk-up picker's and Walk-ups list's audition (nil without sound).
    var walkUpAudition: WalkUpAudition? {
        sound?.audition(
            model: { [weak self] in self?.renderModel },
            profile: { [weak self] in self?.instrument?.profile },
            context: .editor,
        )
    }

    /// Plays a chord as written in the source (the canvas's ⌥-click), at sounding pitch.
    func hearChord(written original: String) {
        guard let renderModel else { return }
        sound?.hearChord(
            written: original,
            in: renderModel,
            profile: instrument?.profile,
            context: .editor,
        )
    }
}
