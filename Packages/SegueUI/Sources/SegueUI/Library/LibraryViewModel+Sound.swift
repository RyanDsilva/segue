import Editing
import Library

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

    /// The walk-up picker's audition for the song rendered as `render`.
    func walkUpAudition(_ render: RenderModel) -> WalkUpAudition? {
        sound?.audition(
            model: { render },
            profile: { [weak self] in self?.instrument?.profile },
            context: .library,
        )
    }

    /// The Walk-ups list's audition for song `id`.
    func walkUpAudition(songID id: SongID) -> WalkUpAudition? {
        sound?.audition(
            model: { [weak self] in
                self?.song(id: id).map { SongSummary.renderModel($0) }
            },
            profile: { [weak self] in self?.instrument?.profile },
            context: .library,
        )
    }
}
