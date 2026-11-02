#if os(macOS)
    import SwiftUI

    /// Settings > Appearance (R36, A42): Match System, Light or Dark; the stage stays dark.
    struct AppearanceSettingsView: View {
        @Bindable var store: AppearanceStore

        var body: some View {
            Form {
                Section {
                    Picker(uiString("Appearance"), selection: $store.mode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .accessibilityIdentifier(AccessibilityID.settingsAppearance)
                    SettingsNote(text: "The stage is always dark.")
                }
            }
            .formStyle(.grouped)
            .settingsPaneHeight(minimum: 220)
        }
    }
#endif
