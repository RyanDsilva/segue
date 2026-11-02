#if os(macOS)
    import AppKit
    import Library
    import SwiftUI

    /// Tap Timing's panel under the chord-length lane (P8-7 section 7): the mode and options,
    /// a big tap pad with the chord being waited for and a running count, then the review
    /// (Keep, Discard and, without the click, the tempo from the taps). The keys come through
    /// the lane, which holds the focus while the panel is open.
    struct TapCapturePanel: View {
        let tap: TapCapture

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                options
                if tap.phase == .review {
                    TapReviewRow(tap: tap)
                } else {
                    TapPad(tap: tap)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(uiString("Tap Timing"))
            .accessibilityIdentifier(AccessibilityID.playAlongTapPanel)
        }

        private var options: some View {
            HStack(spacing: 14) {
                SegmentedGroup {
                    SegmentButton(title: uiString("With Click"), isOn: tap.mode == .click) {
                        tap.setMode(.click)
                    }
                    .accessibilityIdentifier(AccessibilityID.playAlongTapMode("click"))
                    .help(
                        uiString("Segue clicks at the song's tempo; taps land on the nearest beat"),
                    )
                    SegmentButton(title: uiString("No Click"), isOn: tap.mode == .free) {
                        tap.setMode(.free)
                    }
                    .accessibilityIdentifier(AccessibilityID.playAlongTapMode("free"))
                    .help(uiString("No sound; the tempo comes from your taps"))
                }
                .fixedSize()
                .disabled(tap.phase != .ready)
                Toggle(
                    uiString("Half beats"),
                    isOn: Binding(get: { tap.halfBeats }, set: tap.setHalfBeats),
                )
                .toggleStyle(.checkbox)
                .help(uiString("Snap every tap to half a beat (or hold ⌥ as you tap)"))
                if tap.mode == .click, tap.phase != .review {
                    Toggle(
                        uiString("Chords"),
                        isOn: Binding(get: { tap.playChords }, set: tap.setPlayChords),
                    )
                    .toggleStyle(.checkbox)
                    .help(uiString("Play the chords as they are timed now"))
                    Toggle(
                        uiString("Bass"),
                        isOn: Binding(get: { tap.playBass }, set: tap.setPlayBass),
                    )
                    .toggleStyle(.checkbox)
                    .help(uiString("Play the bass as it is timed now"))
                }
                Toggle(
                    uiString("Announce taps"),
                    isOn: Binding(get: { tap.announcesTaps }, set: tap.setAnnouncesTaps),
                )
                .toggleStyle(.checkbox)
                .help(uiString("VoiceOver says each chord as you tap it"))
                Spacer(minLength: 8)
                if tap.phase != .review {
                    Button(tap.phase == .tapping ? uiString("Stop") : uiString("Cancel")) {
                        tap.phase == .tapping ? tap.stop() : tap.cancel()
                    }
                    .buttonStyle(.segueSecondary)
                    .controlSize(.small)
                    .help(tap
                        .phase == .tapping ? uiString("Stop and review (Esc)") :
                        uiString("Close (Esc)"))
                    .accessibilityIdentifier(AccessibilityID.playAlongTapStop)
                }
            }
            .font(.callout)
        }
    }

    /// The tap target: click it, or press Space or a pedal (Page Down).
    private struct TapPad: View {
        let tap: TapCapture
        /// Bumped on each tap, for the pad's flash.
        @State private var flash = 0
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: 10)
        }

        var body: some View {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    headline
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(Theme.color.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                if tap.phase == .tapping {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(verbatim: "\(tap.taps)")
                            .font(SchibstedGrotesk.bold.font(size: 30))
                            .monospacedDigit()
                            .foregroundStyle(Theme.color.ink)
                            .contentTransition(.numericText())
                        Text(tap.taps == 1 ? uiString("tap") : uiString("taps"))
                            .font(.callout)
                            .foregroundStyle(Theme.color.muted)
                    }
                    .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .background(shape.fill(background))
            .overlay {
                shape.strokeBorder(
                    tap.phase == .tapping ? Theme.color.cueText.opacity(0.6) : Theme.color
                        .lineStrong,
                    lineWidth: 1,
                )
            }
            .overlay {
                shape.fill(Theme.color.cue.opacity(0.18))
                    .opacity(flash.isMultiple(of: 2) ? 0 : 1)
                    .allowsHitTesting(false)
            }
            .contentShape(shape)
            .onTapGesture {
                tap.tap(half: NSEvent.modifierFlags.contains(.option))
            }
            .onChange(of: tap.taps) {
                guard !reduceMotion else { return }
                flash += 1
                withAnimation(.easeOut(duration: 0.18)) { flash += 1 }
            }
            .accessibilityElement()
            .accessibilityLabel(uiString("Tap pad"))
            .accessibilityValue(tap.spokenValue)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default) { tap.tap() }
            .accessibilityAction(named: "Skip") { tap.skip() }
            .accessibilityIdentifier(AccessibilityID.playAlongTapPad)
        }

        private var background: Color {
            tap.phase == .tapping ? Theme.color.cue.opacity(0.08) : Theme.color.surfaceAlt
        }

        @ViewBuilder private var headline: some View {
            if tap.phase == .ready {
                Text("Press Space to start", bundle: #bundle)
                    .font(SchibstedGrotesk.bold.font(size: 20))
                    .foregroundStyle(Theme.color.ink)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 20)) { _ in
                    if let beat = tap.countInBeat() {
                        CountInDots(beat: beat, beats: max(1, tap.countInBeats))
                    } else {
                        Text(tap.next < tap.chords.count
                            ? "Next: \(tap.title(tap.next))" : "Next: End")
                            .font(SchibstedGrotesk.bold.font(size: 20))
                            .foregroundStyle(Theme.color.ink)
                            .lineLimit(1)
                    }
                }
            }
        }

        private var subtitle: String {
            switch tap.phase {
            case .ready:
                tap.mode == .click
                    ? "One bar of count-in, then tap each time the next chord starts"
                    : "Your first tap starts \(tap.firstTitle); Segue works out the tempo"
            case .tapping:
                (tap.next < tap.chords.count ? "Chord \(tap.next + 1) of \(tap.chords.count)"
                    : "Tap once more where the last chord ends")
                    + "  \u{00B7}  Space or pedal: next  \u{00B7}  Tab: skip"
                    + "  \u{00B7}  ⌥: half beat  \u{00B7}  Esc: stop"
            case .review:
                ""
            }
        }
    }

    /// One dot per count-in beat, filled up to the beat now.
    private struct CountInDots: View {
        let beat: Int
        let beats: Int

        var body: some View {
            HStack(spacing: 8) {
                Text("Count-in", bundle: #bundle)
                    .font(SchibstedGrotesk.bold.font(size: 20))
                    .foregroundStyle(Theme.color.ink)
                ForEach(1 ... beats, id: \.self) { index in
                    Circle()
                        .fill(index <= beat ? Theme.color.cueText : Theme.color.lineStrong)
                        .frame(width: 9, height: 9)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(uiString("Count-in, beat \(beat) of \(beats)"))
        }
    }

    /// After stopping: what changed, the tempo from the taps (no click), Discard and Keep.
    private struct TapReviewRow: View {
        let tap: TapCapture

        var body: some View {
            HStack(spacing: 12) {
                Text(tap.reviewSummary)
                    .font(SchibstedGrotesk.semiBold.font(size: 13))
                    .foregroundStyle(Theme.color.ink)
                    .accessibilityIdentifier(AccessibilityID.playAlongTapSummary)
                if tap.showsTempo, let tempo = tap.proposal?.tempo {
                    Rectangle().fill(Theme.color.line).frame(width: 1, height: 18)
                    Text("Tempo from your taps", bundle: #bundle)
                        .font(.callout)
                        .foregroundStyle(Theme.color.muted)
                    StepButton(symbol: "minus", label: uiString("Slower")) {
                        tap.setReviewTempo(tempo - 1)
                    }
                    Text("\(TapCapture.tempoText(tempo)) BPM", bundle: #bundle)
                        .font(SchibstedGrotesk.semiBold.font(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(Theme.color.ink)
                        .frame(minWidth: 60)
                        .accessibilityLabel(uiString("Tempo from your taps"))
                        .accessibilityValue(
                            uiString("\(TapCapture.tempoText(tempo)) beats per minute"),
                        )
                        .accessibilityIdentifier(AccessibilityID.playAlongTapTempo)
                    StepButton(symbol: "plus", label: uiString("Faster")) {
                        tap.setReviewTempo(tempo + 1)
                    }
                    SegmentedGroup {
                        SegmentButton(title: "½×", isOn: false) { tap.setReviewTempo(tempo / 2) }
                            .help(uiString("Half the tempo: each tap was two beats"))
                            .accessibilityLabel(uiString("Half the tempo"))
                        SegmentButton(title: "2×", isOn: false) { tap.setReviewTempo(tempo * 2) }
                            .help(uiString("Double the tempo: each tap was half as many beats"))
                            .accessibilityLabel(uiString("Double the tempo"))
                    }
                    .fixedSize()
                }
                Spacer(minLength: 8)
                if tap.offersSongTempo || tap.tempoSet {
                    Button(tap.tempoSet ? uiString("Song Tempo Set")
                        : "Set Song Tempo to \(TapCapture.tempoText(tap.proposal?.tempo ?? 0))")
                    {
                        tap.setSongTempo()
                    }
                    .buttonStyle(.segueSecondary)
                    .controlSize(.small)
                    .disabled(tap.tempoSet)
                    .help(uiString("Write this tempo into the song as {tempo}"))
                    .accessibilityIdentifier(AccessibilityID.playAlongTapSetTempo)
                }
                Button(uiString("Discard")) { tap.discard() }
                    .buttonStyle(.segueSecondary)
                    .controlSize(.small)
                    .help(uiString("Keep the lengths as they were (Esc)"))
                    .accessibilityIdentifier(AccessibilityID.playAlongTapDiscard)
                Button(uiString("Keep")) { tap.keep() }
                    .buttonStyle(.seguePrimary)
                    .controlSize(.small)
                    .disabled(tap.proposal?.changed.isEmpty ?? true)
                    .help(uiString("Save the tapped lengths (Return)"))
                    .accessibilityIdentifier(AccessibilityID.playAlongTapKeep)
            }
            .frame(minHeight: 32)
        }
    }
#endif
