#if os(macOS)
    import Diagrams
    import Editing
    import MusicTheory
    import SwiftUI

    /// Settings > Instrument (P8-4 6.4, R152, R158 Q7): the bass-note view for anyone, and
    /// the bassist profile with strings and tuning. User-level: never per song.
    struct InstrumentSettingsView: View {
        let store: InstrumentProfileStore
        /// The tuning menu's "Custom..." row is chosen (or the stored tuning is no preset).
        @State private var customChosen = false
        @State private var customDraft = ""

        private var profile: InstrumentProfile {
            store.profile
        }

        var body: some View {
            Form {
                Section("Bass notes") {
                    Toggle("Show bass notes instead of chords", isOn: binding(\.bassNotes))
                        .accessibilityIdentifier(AccessibilityID.settingsInstrumentBassNotes)
                    SettingsNote(text: Self.bassNotesNote)
                    Toggle("Show the full chord beside the note", isOn: binding(\.chordBeside))
                        .disabled(!profile.bassNotes)
                        .accessibilityIdentifier(AccessibilityID.settingsInstrumentChordBeside)
                    Toggle("Mini neck on stage", isOn: binding(\.stageNeck))
                        .disabled(!profile.bassNotes)
                        .accessibilityIdentifier(AccessibilityID.settingsInstrumentStageNeck)
                    SettingsNote(text: "Shows where to play the current chord, bottom left on "
                        + "stage.")
                }
                Section("Bass") {
                    Toggle("I play bass", isOn: Binding(
                        get: { profile.playsBass },
                        set: { on in store.update { $0.setPlaysBass(on) } },
                    ))
                    .accessibilityIdentifier(AccessibilityID.settingsInstrumentPlaysBass)
                    SettingsNote(text: "Turns on bass notes. The strings and tuning below set "
                        + "the mini neck either way.")
                    Picker("Strings", selection: Binding(
                        get: { profile.strings },
                        set: { count in
                            store.update { $0.setStrings(count) }
                            customChosen = false
                        },
                    )) {
                        ForEach(Array(Tuning.bassStringCounts), id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .accessibilityIdentifier(AccessibilityID.settingsInstrumentStrings)
                    Picker("Tuning", selection: tuningChoice) {
                        ForEach(presets, id: \.self) { tuning in
                            Text(Self.title(tuning)).tag(TuningChoice.preset(tuning))
                        }
                        Divider()
                        Text("Custom…").tag(TuningChoice.custom)
                    }
                    .accessibilityIdentifier(AccessibilityID.settingsInstrumentTuning)
                    if showsCustom {
                        customField
                    }
                    Toggle("Fretboard in the editor", isOn: binding(\.fretboard))
                        .disabled(!profile.playsBass)
                        .accessibilityIdentifier(AccessibilityID.settingsInstrumentFretboard)
                    SettingsNote(text: "Shows where to play each chord's bass note in the "
                        + "editor's diagram strip.")
                }
                walkUpsSection
            }
            .formStyle(.grouped)
            .onAppear {
                customDraft = isPreset ? "" : profile.tuning.name
            }
        }

        /// Walk-ups on charts and the default feel (P8-4b section 8.7), while bass notes show.
        private var walkUpsSection: some View {
            Section("Walk-ups") {
                Picker("Walk-ups on charts", selection: Binding(
                    get: { profile.walkUps },
                    set: { density in store.setWalkUps(density) },
                )) {
                    ForEach(WalkUpDensity.allCases, id: \.self) { density in
                        Text(density.title).tag(density)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.settingsInstrumentWalkUps)
                SettingsNote(text: "A short run of notes into the next chord, after the chord "
                    + "it leaves. Change one in the editor or library.")
                Picker("Default feel", selection: Binding(
                    get: { profile.genre },
                    set: { genre in store.update { $0.genre = genre } },
                )) {
                    ForEach(BassGenre.allCases, id: \.self) { genre in
                        Text(genre.title).tag(genre)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.settingsInstrumentGenre)
                SettingsNote(text: "Songs use this unless you set their own feel.")
            }
            .disabled(!profile.bassNotes)
        }

        static let bassNotesNote = "Shows the note to play at sounding pitch in every song "
            + "and on stage, even when the chart is written for a capo. Nashville numbers "
            + "follow each song's Nashville setting."

        private enum TuningChoice: Hashable {
            case preset(Tuning)
            case custom
        }

        private var presets: [Tuning] {
            Tuning.bassPresets.filter { $0.strings.count == profile.strings }
        }

        private var isPreset: Bool {
            presets.contains(profile.tuning)
        }

        private var showsCustom: Bool {
            customChosen || !isPreset
        }

        private var tuningChoice: Binding<TuningChoice> {
            Binding(
                get: { showsCustom ? .custom : .preset(profile.tuning) },
                set: { choice in
                    switch choice {
                    case let .preset(tuning):
                        customChosen = false
                        customDraft = ""
                        store.update { $0.tuning = tuning }
                    case .custom:
                        customChosen = true
                        if customDraft.isEmpty {
                            customDraft = profile.tuning.name
                        }
                    }
                },
            )
        }

        private var customField: some View {
            VStack(alignment: .leading, spacing: 4) {
                TextField(
                    "Custom tuning",
                    text: $customDraft,
                    prompt: Text(profile.strings == 5 ? "BEADG or B0 E1 A1 D2 G2"
                        : "EADG or E1 A1 D2 G2"),
                )
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .accessibilityIdentifier(AccessibilityID.settingsInstrumentCustomTuning)
                .onChange(of: customDraft) { _, text in
                    if let tuning = parsedCustom(text) {
                        store.update { $0.tuning = tuning }
                    }
                }
                if !customDraft.isEmpty, parsedCustom(customDraft) == nil {
                    Text("Enter \(profile.strings) notes, low to high")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }

        /// The draft as a tuning with the profile's string count; nil otherwise.
        private func parsedCustom(_ text: String) -> Tuning? {
            Tuning(bassLetters: text).flatMap { $0.strings.count == profile.strings ? $0 : nil }
        }

        /// "EADG", "Drop D (DADG)" style titles for the menu.
        private static func title(_ tuning: Tuning) -> String {
            switch tuning {
            case .bassStandard4, .bassStandard5: "Standard (\(tuning.name))"
            case .bassDropD: "Drop D (\(tuning.name))"
            case .bassHalfDown4: "Half step down (\(tuning.name))"
            case .bassHighC5: "High C (\(tuning.name))"
            default: tuning.name
            }
        }

        private func binding(_ keyPath: WritableKeyPath<InstrumentProfile, Bool>) -> Binding<Bool> {
            Binding(
                get: { profile[keyPath: keyPath] },
                set: { value in store.update { $0[keyPath: keyPath] = value } },
            )
        }
    }
#endif
