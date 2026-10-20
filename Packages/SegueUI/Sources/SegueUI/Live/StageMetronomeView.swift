#if os(macOS)
    import Shows
    import SwiftUI

    /// The stage metronome, design A (R118): the tempo and one dot in the bottom-right
    /// corner of the song area. The dot flashes on every pulse and fades over it; beat 1
    /// flashes in the cue red with a soft halo. With Reduce Motion it is a stepping numeral
    /// instead (beat 1 in cue text). Drawn per display frame from the monotonic stage clock
    /// (`TimelineView`), so a busy frame can drop a flash but never shifts the grid; it takes
    /// no clicks and no key focus.
    struct StageMetronomeView: View {
        let metronome: StageMetronome
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        /// The dot's diameter.
        static let dot: CGFloat = 18
        /// Opacity of the dot between flashes.
        static let restOpacity = 0.18

        var body: some View {
            if metronome.showsPulse, let track = metronome.track {
                TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 30 : nil)) { _ in
                    let beat = track.beat(at: metronome.clock.now())
                    HStack(spacing: 10) {
                        Text(Self.bpmText(track.bpm))
                            .font(SchibstedGrotesk.semiBold.font(size: 13))
                            .monospacedDigit()
                            .foregroundStyle(Theme.color.muted)
                        if reduceMotion {
                            numeral(beat)
                        } else {
                            pulse(beat)
                        }
                    }
                }
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Metronome")
                .accessibilityValue("\(Self.bpmText(track.bpm)) beats per minute")
                .accessibilityIdentifier(AccessibilityID.liveMetronome)
            }
        }

        private func pulse(_ beat: MetronomeBeat) -> some View {
            let flash = Self.flash(beat.phase)
            let color = beat.isDownbeat ? Theme.color.cue : Theme.color.ink
            let peak = beat.isDownbeat ? 1.0 : 0.85
            return Circle()
                .fill(color)
                .frame(width: Self.dot, height: Self.dot)
                .opacity(Self.restOpacity + (peak - Self.restOpacity) * flash)
                .scaleEffect(1 + (beat.isDownbeat ? 0.25 : 0.15) * flash)
                .background {
                    if beat.isDownbeat {
                        Circle()
                            .fill(Theme.color.cue.opacity(0.22 * flash))
                            .frame(width: Self.dot + 12, height: Self.dot + 12)
                    }
                }
                .frame(width: Self.dot + 12, height: Self.dot + 12)
        }

        private func numeral(_ beat: MetronomeBeat) -> some View {
            Text("\(beat.beatInBar)")
                .font(SchibstedGrotesk.extraBold.font(size: 20))
                .monospacedDigit()
                .foregroundStyle(beat.isDownbeat ? Theme.color.cueText : Theme.color.ink)
                .frame(width: 26)
        }

        /// The flash at `phase` through a pulse: full on the pulse, fading out over the
        /// first 60% of it.
        static func flash(_ phase: Double) -> Double {
            max(0, 1 - phase / 0.6)
        }

        /// "96", "92.5".
        static func bpmText(_ bpm: Double) -> String {
            bpm.formatted(.number.precision(.fractionLength(0 ... 1)))
        }
    }
#endif
