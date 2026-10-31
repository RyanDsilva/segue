#if os(macOS)
    import Diagrams
    import Playback
    import SwiftUI

    /// Settings > Audio (P8-6 section 11): where sound goes, and how heard chords and walk-ups
    /// sound.
    struct AudioSettingsView: View {
        let sound: SoundSession
        /// The Settings > Instrument strings and tuning the Test chord's bass uses (R168).
        var instrument: InstrumentProfileStore?

        private var settings: AudioSettings {
            sound.settings.settings
        }

        var body: some View {
            Form {
                Section {
                    Picker("Play through", selection: outputBinding) {
                        Text(sound.systemOutputTitle).tag(String?.none)
                        ForEach(sound.outputChoices) { choice in
                            Text(choice.title).tag(Optional(choice.uid))
                        }
                    }
                    .accessibilityIdentifier(AccessibilityID.settingsAudioOutput)
                    if let note = sound.usbNote {
                        SettingsNote(text: note)
                    }
                }
                Section {
                    Picker("Chord sound", selection: binding(\.chordSound)) {
                        Text("Piano").tag(ChordSound.piano)
                        Text("Clean guitar").tag(ChordSound.cleanGuitar)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .accessibilityIdentifier(AccessibilityID.settingsAudioChordSound)
                    Picker("Chords play as", selection: binding(\.chordStyle)) {
                        Text("Strum").tag(ChordStyle.strum)
                        Text("Block").tag(ChordStyle.block)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .accessibilityIdentifier(AccessibilityID.settingsAudioChordStyle)
                    Picker("Bass", selection: binding(\.bassSound)) {
                        Text("Finger").tag(BassSound.finger)
                        Text("Pick").tag(BassSound.pick)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .accessibilityIdentifier(AccessibilityID.settingsAudioBassSound)
                }
                Section {
                    LabeledContent("Volume") {
                        HStack(spacing: 8) {
                            Image(systemName: "speaker.fill")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Slider(value: binding(\.volume), in: 0 ... 1)
                                .frame(minWidth: 160)
                                .accessibilityLabel("Volume")
                                .accessibilityValue("\(Int((settings.volume * 100).rounded()))%")
                                .accessibilityIdentifier(AccessibilityID.settingsAudioVolume)
                            Image(systemName: "speaker.wave.3.fill")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    LabeledContent("Test") {
                        Button("Play a G Chord") {
                            sound.testSound(tuning: instrument?.profile.tuning ?? .bassStandard4)
                        }
                        .disabled(!sound.isAvailable)
                        .help(sound.isAvailable ? "Plays a G chord with its bass note"
                            : SoundGate.offHelp)
                        .accessibilityIdentifier(AccessibilityID.settingsAudioTest)
                    }
                    SettingsNote(text: "Sound plays in the editor, the library and rehearsals. "
                        + "It never plays during a show.")
                }
            }
            .formStyle(.grouped)
        }

        private var outputBinding: Binding<String?> {
            Binding(
                get: { settings.outputUID },
                set: { uid in sound.chooseOutput(uid) },
            )
        }

        private func binding<Value>(_ keyPath: WritableKeyPath<AudioSettings, Value>)
            -> Binding<Value>
        {
            Binding(
                get: { settings[keyPath: keyPath] },
                set: { value in sound.settings.update { $0[keyPath: keyPath] = value } },
            )
        }
    }
#endif
