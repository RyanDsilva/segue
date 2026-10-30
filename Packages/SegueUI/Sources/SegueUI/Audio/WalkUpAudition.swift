import Editing
import Library
import MusicTheory
import Playback
import Services
import Shows
import SwiftUI

/// Hearing walk-ups in the picker and the Walk-ups list (P8-6 section 10.2), injected by the
/// preview's owner beside `walkUpPicking`. Playing never saves anything.
struct WalkUpAudition {
    /// False during a gig ("Sound is off during a show").
    var isEnabled: Bool
    /// The two-bar audition of `candidate` (nil: the change with no walk-up).
    var phrase: @MainActor (ChordChange, WalkUpCandidate?) -> Phrase?
    /// The player, made on first use; nil during a gig.
    var player: @MainActor () -> SoundPlayer?
    /// The player if one exists (never makes one), for showing what plays.
    var current: @MainActor () -> SoundPlayer?
    /// A candidate was played (analytics).
    var played: @MainActor () -> Void
}

extension EnvironmentValues {
    @Entry var walkUpAudition: WalkUpAudition?
}

extension SoundSession {
    /// The audition for songs rendered as `model()`: the song's `{tempo}` (else 90) and
    /// `{time}`, the Settings sounds, the bass placed as in the previews.
    func audition(
        model: @escaping @MainActor () -> RenderModel?,
        profile: @escaping @MainActor () -> InstrumentProfile?,
        context: FeatureContext,
    ) -> WalkUpAudition {
        WalkUpAudition(
            isEnabled: isAvailable,
            phrase: { [weak self] change, candidate in
                guard let self, let model = model() else { return nil }
                return PhraseBuilder.audition(
                    change,
                    candidate: candidate,
                    tempo: model.header.tempo,
                    meter: MetronomeMeter(time: model.header.time),
                    voices: PlaybackVoices(
                        sound: settings.settings.chordSound,
                        style: settings.settings.chordStyle,
                        placement: Self.placement(for: model, profile: profile()),
                    ),
                )
            },
            player: { [weak self] in self?.makePlayer() },
            current: { [weak self] in self?.player },
            played: { [weak self] in
                self?.settings.services.record(.featureUsed(.walkUpAudition, context))
            },
        )
    }
}

/// The picker's hearing state (P8-6 10.2): which option sounds, the Loop switch, A/B
/// switching at the next phrase start, and stopping before a pick. Options are indexed in
/// the picker's order (the last index is "Nothing here", candidate nil).
@MainActor
@Observable
final class WalkUpListening {
    @ObservationIgnored let audition: WalkUpAudition
    /// The Loop switch (default off).
    private(set) var looping = false
    /// The option sounding now.
    private(set) var sounding: Int?

    init(audition: WalkUpAudition) {
        self.audition = audition
    }

    /// Whether option `index` is sounding now.
    func isSounding(_ index: Int) -> Bool {
        sounding == index && audition.current()?.isPlaying == true
    }

    /// ▶ or Space: plays option `index` (once, or looping), or stops it when it sounds.
    /// Playing B while A sounds stops A at once.
    func toggle(_ index: Int, _ candidate: WalkUpCandidate?, change: ChordChange) {
        guard audition.isEnabled else { return }
        if isSounding(index) {
            stop()
            return
        }
        guard let player = audition.player(), let phrase = audition.phrase(change, candidate)
        else { return }
        player.stop()
        if looping {
            player.loop(phrase)
        } else {
            player.play(phrase)
        }
        sounding = index
        audition.played()
    }

    /// The selection moved to option `index`: while a loop sounds, it takes over at the
    /// next phrase start and VoiceOver hears "Now playing option B" once. Returns whether
    /// it switched.
    @discardableResult
    func select(_ index: Int, _ candidate: WalkUpCandidate?, change: ChordChange, name: String)
        -> Bool
    {
        guard looping, let sounding, sounding != index, let player = audition.current(),
              player.isPlaying, player.isLooping,
              let phrase = audition.phrase(change, candidate)
        else { return false }
        player.swapAtNextWrap(phrase)
        self.sounding = index
        audition.played()
        AccessibilityNotification.Announcement("Now playing \(name)").post()
        return true
    }

    /// Whether a click on a row should switch the option rather than pick it.
    var isLoopingSound: Bool {
        looping && sounding != nil && audition.current()?.isPlaying == true
    }

    /// The Loop switch: on restarts the sounding option looping, off stops it.
    func setLooping(_ isOn: Bool, _ candidate: (Int) -> WalkUpCandidate?, change: ChordChange) {
        guard isOn != looping else { return }
        looping = isOn
        guard let sounding, isSounding(sounding) else { return }
        if isOn {
            self.sounding = nil
            audition.current()?.stop()
            toggle(sounding, candidate(sounding), change: change)
        } else {
            stop()
        }
    }

    /// Stops what this picker started (a pick, closing the picker).
    func stop() {
        guard sounding != nil else { return }
        if audition.current()?.isPlaying == true {
            audition.current()?.stop()
        }
        sounding = nil
    }
}
