// P8-7d (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 12.3, P8-6 section
// 9). Hearing fills in the fill editor on the shared engine, the way `WalkUpAudition` hears
// walk-ups: injected by the sheet's owner, off during a gig, never saving anything.

import Playback
import Services

struct FillAudition {
    /// False during a gig ("Sound is off during a show").
    var isEnabled: Bool
    /// The Settings > Audio sounds and the song's bass placement.
    var voices: @MainActor () -> PlaybackVoices
    /// The player, made on first use; nil during a gig.
    var player: @MainActor () -> SoundPlayer?
    /// The player if one exists (never makes one).
    var current: @MainActor () -> SoundPlayer?
    /// A candidate or the draft was played (analytics `fillAudition`).
    var played: @MainActor () -> Void
}

extension SoundSession {
    /// The fill editor's audition for a song whose bass sits at `placement`.
    func fillAudition(
        placement: @escaping @MainActor () -> BassPlacement,
        context: FeatureContext,
    ) -> FillAudition {
        FillAudition(
            isEnabled: isAvailable,
            voices: { [weak self] in
                PlaybackVoices(
                    sound: self?.settings.settings.chordSound ?? .piano,
                    style: self?.settings.settings.chordStyle ?? .strum,
                    placement: placement(),
                )
            },
            player: { [weak self] in self?.makePlayer() },
            current: { [weak self] in self?.player },
            played: { [weak self] in
                self?.settings.services.record(.featureUsed(.fillAudition, context))
            },
        )
    }
}
