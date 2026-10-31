import Diagrams
import Editing
import MusicTheory
import Playback
import Services
import SwiftUI

/// What a preview's chord units can do (P8-6 section 10.1), injected by the preview's
/// owner (the editor, the library). The stage never injects one, so it has no chord click
/// targets at all.
struct ChordHearing {
    /// False during a gig: the units stay visible but do not play ("Sound is off during a
    /// show").
    var isEnabled: Bool
    /// A preview chord unit (written chord, transformed to sounding pitch).
    var play: @MainActor (RenderChord) -> Void
    /// A diagram strip cell's chord, already at concert pitch ("G/B").
    var playConcert: @MainActor (String) -> Void
    /// A bass fretboard cell's note (MIDI pitch of its suggested position).
    var playBass: @MainActor (Int) -> Void
}

extension EnvironmentValues {
    @Entry var chordHearing: ChordHearing?
}

extension SoundSession {
    /// Plays a preview chord at sounding pitch over its bass note (the slash bass, else the
    /// root), in the Settings sound and style. `N.C.` and unknown chords play nothing.
    /// Returns whether it played.
    @discardableResult
    func hearChord(
        written original: String,
        in model: RenderModel,
        profile: InstrumentProfile?,
        context: FeatureContext,
    ) -> Bool {
        guard let concert = model.transform.concert(ChordToken(parsing: original)).chord
        else { return false }
        let placement = Self.placement(for: model, profile: profile)
        let phrase = PhraseBuilder.chord(
            concert.symbol,
            sound: settings.settings.chordSound,
            style: settings.settings.chordStyle,
            bass: Voicing.bassNote(of: concert.symbol, placement: placement),
        )
        guard play(phrase) else { return false }
        settings.services.record(.featureUsed(.hearChord, context))
        return true
    }

    /// Plays a bass note alone (a bass fretboard cell) at `pitch`.
    @discardableResult
    func hearBassNote(_ pitch: Int, context: FeatureContext) -> Bool {
        guard play(PhraseBuilder.bassNote(UInt8(clamping: pitch))) else { return false }
        settings.services.record(.featureUsed(.hearChord, context))
        return true
    }

    /// The preview action for `model` (nil without a model).
    func hearing(
        model: @escaping @MainActor () -> RenderModel?,
        profile: @escaping @MainActor () -> InstrumentProfile?,
        context: FeatureContext,
    ) -> ChordHearing {
        ChordHearing(
            isEnabled: isAvailable,
            play: { [weak self] chord in
                guard let self, chord.kind == .chord, let model = model() else { return }
                hearChord(written: chord.original, in: model, profile: profile(), context: context)
            },
            playConcert: { [weak self] name in
                guard let self, let model = model() else { return }
                hearConcertChord(name, in: model, profile: profile(), context: context)
            },
            playBass: { [weak self] pitch in
                self?.hearBassNote(pitch, context: context)
            },
        )
    }

    /// Plays a chord already at concert pitch (a diagram cell's) over its bass.
    @discardableResult
    func hearConcertChord(
        _ name: String,
        in model: RenderModel,
        profile: InstrumentProfile?,
        context: FeatureContext,
    ) -> Bool {
        guard let symbol = ChordSymbol(parsing: name) else { return false }
        let phrase = PhraseBuilder.chord(
            symbol,
            sound: settings.settings.chordSound,
            style: settings.settings.chordStyle,
            bass: Voicing.bassNote(
                of: symbol,
                placement: Self.placement(for: model, profile: profile),
            ),
        )
        guard play(phrase) else { return false }
        settings.services.record(.featureUsed(.hearChord, context))
        return true
    }

    /// Where the bass sits for a song: the Settings > Instrument strings and tuning for
    /// anyone, with or without "I play bass", as the mini neck does (R163); EADG without a
    /// profile. Home from the concert key, else the song's first bass note (P8-6 6.2).
    static func placement(for model: RenderModel, profile: InstrumentProfile?) -> BassPlacement {
        let tuning = profile?.tuning ?? .bassStandard4
        let first = model.sections.lazy.flatMap(\.items).compactMap { item -> PitchClass? in
            guard case let .lyrics(line) = item else { return nil }
            return line.chords.lazy.compactMap { chord -> PitchClass? in
                guard chord.kind == .chord,
                      let symbol = model.transform.concert(ChordToken(parsing: chord.original))
                          .chord?.symbol
                else { return nil }
                return (symbol.bass ?? symbol.root).pitchClass
            }.first
        }.first
        return BassPlacement.song(
            concertKey: model.transform.concertKey,
            firstBass: first,
            tuning: tuning,
        )
    }
}

/// A chord unit that plays when clicked (P8-6 10.1): a pointer cursor and a subtle hover
/// tint, nothing else; disabled with the show help during a gig.
struct ChordUnitPlayback: ViewModifier {
    let chord: RenderChord?
    @Environment(\.chordHearing) private var hearing
    @State private var isHovered = false

    func body(content: Content) -> some View {
        if let hearing, let chord, chord.kind == .chord {
            content
                .padding(.horizontal, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.color.cueText
                            .opacity(isHovered && hearing.isEnabled ? 0.12 : 0)),
                )
                .padding(.horizontal, -2)
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
                .pointerStyle(hearing.isEnabled ? .link : nil)
                .onTapGesture {
                    if hearing.isEnabled {
                        hearing.play(chord)
                    }
                }
                .help(hearing.isEnabled ? "" : SoundGate.offHelp)
        } else {
            content
        }
    }
}

/// VoiceOver's way to hear a line's chords (P8-6 13): one "Play chord G" action per
/// playable chord on the line, in the actions rotor. The line is still read as before.
struct ChordPlayActions: ViewModifier {
    let tokens: [LyricToken]
    @Environment(\.chordHearing) private var hearing

    func body(content: Content) -> some View {
        let chords = tokens.compactMap { token -> PlayableChord? in
            guard let source = token.source, source.kind == .chord, let text = token.chord
            else { return nil }
            return PlayableChord(
                id: token.id,
                spoken: LyricLineView.spokenChord(text, detail: token.detail),
                chord: source,
            )
        }
        if let hearing, hearing.isEnabled, !chords.isEmpty {
            content.accessibilityActions {
                ForEach(chords) { playable in
                    Button("Play chord \(playable.spoken)") {
                        hearing.play(playable.chord)
                    }
                }
            }
        } else {
            content
        }
    }
}

private struct PlayableChord: Identifiable {
    var id: Int
    var spoken: String
    var chord: RenderChord
}
