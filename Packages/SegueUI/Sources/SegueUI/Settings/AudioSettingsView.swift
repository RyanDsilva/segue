#if os(macOS)
    import Playback
    import SwiftUI

    /// Settings > Audio (P8-6 section 11): how heard chords and walk-ups sound. The output
    /// picker comes with P8-6c; until then sound follows the system output.
    struct AudioSettingsView: View {
        let sound: SoundSession

        private var settings: AudioSettings {
            sound.settings.settings
        }

        var body: some View {
            Form {
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
                        Button("Play a G Chord") { sound.testSound() }
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
