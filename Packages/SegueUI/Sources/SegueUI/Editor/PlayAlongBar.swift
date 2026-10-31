#if os(macOS)
    import Library
    import Playback
    import SwiftUI

    /// The Play along bar under the preview (P8-6 section 10.3): transport, range and loop,
    /// voices, tempo, the Timing menu and the chord-length lane. Closed by default; closing
    /// it stops playback. Disabled (never hidden) while a show runs.
    struct PlayAlongBar: View {
        @Bindable var model: PlayAlong

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    transport
                    rangeMenu
                    Toggle("Loop", isOn: Binding(get: { model.loops }, set: model.setLoops))
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier(AccessibilityID.playAlongLoop)
                        .help("Repeat the range")
                    Spacer(minLength: 8)
                    PlayAlongTimingMenu(model: model)
                    Button {
                        model.setOpen(false)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.color.muted)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close Play Along")
                    .help("Close Play Along")
                    .accessibilityIdentifier(AccessibilityID.playAlongClose)
                }
                // Voices and tempo side by side, or stacked in a narrow pane.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        voices
                        Spacer(minLength: 8)
                        PlayAlongTempo(model: model)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        voices
                        PlayAlongTempo(model: model)
                    }
                }
                TimelineStrip(model: model)
                if let line = note {
                    Text(line)
                        .font(.callout)
                        .foregroundStyle(Theme.color.muted)
                        .accessibilityIdentifier(AccessibilityID.playAlongNote)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.color.surfaceAlt.opacity(0.5))
            .background(Theme.color.ground)
            .overlay(alignment: .top) { Hairline() }
            .disabled(!model.session.isAvailable)
            .help(model.session.isAvailable ? "" : SoundGate.offHelp)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.playAlongBar)
        }

        /// The tempo hint, or why sound stopped by itself.
        private var note: String? {
            if let status = model.session.player?.status, !model.isPlaying {
                return status
            }
            return model.tempoHint
        }

        private var transport: some View {
            Button {
                model.togglePlay()
            } label: {
                Label(
                    model.isPlaying ? "Stop" : "Play",
                    systemImage: model.isPlaying ? "stop.fill" : "play.fill",
                )
                .frame(minWidth: 58)
            }
            .buttonStyle(.seguePrimary)
            .controlSize(.small)
            .keyboardShortcut(.space, modifiers: .option)
            .disabled(model.timeline.chords.isEmpty)
            .accessibilityValue(model.transportValue)
            .help("Play along (⌥Space)")
            .accessibilityIdentifier(AccessibilityID.playAlongPlay)
        }

        private var rangeMenu: some View {
            Menu {
                Button("Whole Song") { model.setRange(.whole) }
                if let source = model.source {
                    let passes = source.playablePasses
                    if !passes.isEmpty {
                        Divider()
                        ForEach(passes, id: \.self) { pass in
                            Button(source.passTitle(pass)) { model.setRange(.section(pass)) }
                        }
                        Divider()
                        ForEach(passes.dropFirst(), id: \.self) { pass in
                            Button("From \(source.passTitle(pass)) to the End") {
                                model.setRange(.from(pass))
                            }
                        }
                    }
                }
            } label: {
                Text(rangeTitle)
                    .font(SchibstedGrotesk.semiBold.font(size: 13))
            }
            .menuStyle(.button)
            .fixedSize()
            .accessibilityLabel("Range")
            .accessibilityValue(rangeTitle)
            .accessibilityIdentifier(AccessibilityID.playAlongRange)
        }

        private var rangeTitle: String {
            switch model.range {
            case .whole: "Whole Song"
            case let .section(pass): model.source?.passTitle(pass) ?? "Section"
            case let .from(pass): "From \(model.source?.passTitle(pass) ?? "Section")"
            }
        }

        private var voices: some View {
            SegmentedGroup {
                voice("Bass", .bass)
                voice("Chords", .chords)
                voice("Click", .click)
                voice("Walk-ups", .walkUps)
            }
            .fixedSize()
        }

        private func voice(_ title: String, _ voice: VoiceToggle) -> some View {
            let isOn = model.voices.contains(voice)
            return SegmentButton(title: title, isOn: isOn) { model.setVoice(voice, !isOn) }
                .accessibilityIdentifier(AccessibilityID.playAlongVoice(voice.rawValue))
                .help(isOn ? "Mute the \(title.lowercased())" : "Play the \(title.lowercased())")
        }
    }

    /// The session tempo: the value, - / + and 50% / 75% / 100%. Never saved.
    private struct PlayAlongTempo: View {
        let model: PlayAlong

        var body: some View {
            HStack(spacing: 6) {
                StepButton(symbol: "minus", label: "Slower") { model.setTempo(model.tempo - 1) }
                    .disabled(model.tempo <= PlayAlong.tempoRange.lowerBound)
                Text("\(Int(model.tempo)) BPM")
                    .font(SchibstedGrotesk.semiBold.font(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(Theme.color.ink)
                    .frame(minWidth: 64)
                    .accessibilityLabel("Tempo")
                    .accessibilityValue("\(Int(model.tempo)) beats per minute")
                    .accessibilityIdentifier(AccessibilityID.playAlongTempo)
                StepButton(symbol: "plus", label: "Faster") { model.setTempo(model.tempo + 1) }
                    .disabled(model.tempo >= PlayAlong.tempoRange.upperBound)
                SegmentedGroup {
                    ForEach([0.5, 0.75, 1.0], id: \.self) { percent in
                        SegmentButton(
                            title: "\(Int(percent * 100))%",
                            isOn: abs(model.tempo - (model.songTempo * percent).rounded()) < 0.5,
                        ) { model.setTempo(percent: percent) }
                            .accessibilityIdentifier(
                                AccessibilityID.playAlongTempoPercent(Int(percent * 100)),
                            )
                    }
                }
                .fixedSize()
            }
        }
    }

    /// "Timing": the song's rule, resets and corrections that no longer match.
    struct PlayAlongTimingMenu: View {
        let model: PlayAlong

        var body: some View {
            Menu {
                Section("Each Chord") {
                    rule("One Chord per Half Bar", .each(.halfBar))
                    rule("One Chord per Bar", .each(.bar))
                    rule("One Chord per Two Bars", .each(.twoBars))
                }
                Section("Each Line") {
                    rule("Each Line Lasts 1 Bar", .line(1))
                    rule("Each Line Lasts 2 Bars", .line(2))
                    rule("Each Line Lasts 4 Bars", .line(4))
                }
                Menu("Every Chord Lasts") {
                    ForEach([1, 2, 3, 4, 6, 8, 12, 16], id: \.self) { beats in
                        rule(beats == 1 ? "1 Beat" : "\(beats) Beats", .beats(beats))
                    }
                }
                Divider()
                Button("Reset Corrections in This Section") { model.resetCorrectionsInSection() }
                    .disabled(!model.sectionHasCorrections)
                Button("Reset Corrections in the Song") { model.resetAllCorrections() }
                    .disabled(model.source?.timing.chords.isEmpty ?? true)
                let unmatched = model.unmatchedCorrections.count
                if unmatched > 0 {
                    Divider()
                    Section(unmatched == 1 ? "1 timing change no longer matches"
                        : "\(unmatched) timing changes no longer match")
                    {
                        Button("Remove") { model.removeUnmatchedCorrections() }
                    }
                }
            } label: {
                Text("Timing")
                    .font(SchibstedGrotesk.semiBold.font(size: 13))
            }
            .menuStyle(.button)
            .fixedSize()
            .disabled(!model.canEditTiming)
            .help(model.canEditTiming ? "How long each chord lasts" : "Save the song first")
            .accessibilityIdentifier(AccessibilityID.playAlongTiming)
        }

        private func rule(_ title: String, _ rule: TimingRule) -> some View {
            Toggle(title, isOn: Binding(get: { model.rule == rule }, set: { isOn in
                if isOn {
                    model.setRule(rule)
                }
            }))
        }
    }

    /// "Play Along": opens or closes the bar (the editor's toolbar, the library's pane).
    struct PlayAlongToggle: View {
        let model: PlayAlong

        var body: some View {
            Button {
                model.setOpen(!model.isOpen)
            } label: {
                Label("Play Along", systemImage: "play.circle")
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.segueSecondary)
            .accessibilityAddTraits(model.isOpen ? .isSelected : [])
            .help(model.session.isAvailable
                ?
                (model
                    .isOpen ? "Close Play Along" :
                    "Play bass, chords and click along with the song")
                : SoundGate.offHelp)
            .disabled(!model.session.isAvailable)
            .accessibilityIdentifier(AccessibilityID.playAlongToggle)
        }
    }

    extension View {
        /// Keeps the play-along cue's line in view (instant with Reduce Motion).
        func followsPlayAlong(_ cue: PlayAlongCue?, proxy: ScrollViewProxy) -> some View {
            modifier(FollowPlayAlong(row: cue?.row, proxy: proxy))
        }
    }

    private struct FollowPlayAlong: ViewModifier {
        let row: String?
        let proxy: ScrollViewProxy
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func body(content: Content) -> some View {
            content.onChange(of: row) { _, row in
                guard let row else { return }
                // The playing line sits a third of the way down, clear of the bar.
                let anchor = UnitPoint(x: 0, y: 0.35)
                if reduceMotion {
                    proxy.scrollTo(row, anchor: anchor)
                } else {
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(row, anchor: anchor) }
                }
            }
        }
    }
#endif
