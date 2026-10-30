import Editing

/// Hearing chords in the library's song preview (P8-6 10.1): the song's own display
/// options, at sounding pitch.
extension LibraryViewModel {
    /// The preview's chord action for `render`; nil without sound (tests, no app).
    func chordHearing(_ render: RenderModel) -> ChordHearing? {
        sound?.hearing(
            model: { render },
            profile: { [weak self] in self?.instrument?.profile },
            context: .library,
        )
    }
}
