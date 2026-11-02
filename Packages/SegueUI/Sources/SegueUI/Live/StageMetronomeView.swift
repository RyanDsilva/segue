#if os(macOS)
    import Shows
    import SwiftUI

    /// The stage metronome, "Beat pips" (R151, R158 Q1): at the right end of the status band
    /// above the footer, the tempo ("96 BPM") and one 30 pt pip per pulse of the bar. The
    /// sounding pip flashes and fades over the first 45% of its beat; beat 1 is coral with a
    /// glow. More than 8 pulses, or Reduce Motion, shows a stepping numeral instead (beat 1 in
    /// cue text). Drawn per display frame from the monotonic stage clock (`TimelineView`), so
    /// a busy frame can drop a flash but never shifts the grid; it takes no clicks and no key
    /// focus. An exception to brand.md section 8 (R151).
    struct StageMetronomeView: View {
        let metronome: StageMetronome
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        /// A pip's side and corner radius, and the gap between pips.
        static let pip: CGFloat = 30
        static let pipRadius: CGFloat = 8
        static let pipSpacing: CGFloat = 7
        /// Opacity of a pip between flashes.
        static let restOpacity = 0.14
        /// More pulses than this show the numeral.
        static let maxPips = 8

        var body: some View {
            if metronome.mayShowPulse, let track = metronome.track {
                TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 30 : nil)) { _ in
                    let now = metronome.clock.now()
                    if metronome.showsPulse(at: now) {
                        let beat = track.beat(at: now)
                        HStack(spacing: 12) {
                            bpm(track.bpm)
                            if reduceMotion || track.meter.pulses > Self.maxPips {
                                numeral(beat)
                            } else {
                                pips(beat, count: track.meter.pulses)
                            }
                        }
                    }
                }
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                // One label (a container's value never reaches XCUITest).
                .accessibilityLabel(
                    uiString("Metronome, \(Self.bpmText(track.bpm)) beats per minute"),
                )
                .accessibilityAddTraits(.isStaticText)
                .accessibilityIdentifier(AccessibilityID.liveMetronome)
            }
        }

        private func bpm(_ bpm: Double) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Self.bpmText(bpm))
                    .font(SchibstedGrotesk.bold.font(size: 22))
                    .monospacedDigit()
                    .foregroundStyle(Theme.color.ink)
                Text("BPM", bundle: #bundle)
                    .font(SchibstedGrotesk.semiBold.font(size: 12))
                    .foregroundStyle(Theme.color.muted)
            }
        }

        private func pips(_ beat: MetronomeBeat, count: Int) -> some View {
            HStack(spacing: Self.pipSpacing) {
                ForEach(0 ..< count, id: \.self) { index in
                    let sounding = index + 1 == beat.beatInBar
                    let flash = sounding ? Self.flash(beat.phase) : 0
                    let color = index == 0 ? Theme.color.cue : Theme.color.ink
                    RoundedRectangle(cornerRadius: Self.pipRadius, style: .continuous)
                        .fill(color)
                        .frame(width: Self.pip, height: Self.pip)
                        .opacity(sounding ? 0.16 + 0.84 * flash : Self.restOpacity)
                        .background {
                            if index == 0, flash > 0 {
                                // The downbeat's glow: an 18 f blur, spread 6 f, cue at 0.45 f.
                                RoundedRectangle(
                                    cornerRadius: Self.pipRadius + 6 * flash,
                                    style: .continuous,
                                )
                                .fill(Theme.color.cue.opacity(0.45 * flash))
                                .padding(-6 * flash)
                                .blur(radius: 9 * flash)
                            }
                        }
                        .scaleEffect(1 + 0.12 * flash)
                }
            }
        }

        private func numeral(_ beat: MetronomeBeat) -> some View {
            Text(verbatim: "\(beat.beatInBar)")
                .font(SchibstedGrotesk.extraBold.font(size: 28))
                .monospacedDigit()
                .foregroundStyle(beat.isDownbeat ? Theme.color.cueText : Theme.color.ink)
                .frame(width: 30)
        }

        /// The flash at `phase` through a pulse: full on the pulse, fading out over the
        /// first 45% of it.
        static func flash(_ phase: Double) -> Double {
            max(0, 1 - phase / 0.45)
        }

        /// "96", "92.5".
        static func bpmText(_ bpm: Double) -> String {
            bpm.formatted(.number.precision(.fractionLength(0 ... 1)))
        }
    }
#endif
