#if os(macOS)
    import Shows
    import SwiftUI

    /// Settings > Live: minimum lyric size, the Gig Mode Shortcuts (with Test buttons and a
    /// short guide) and the pre-show checklist rows.
    struct LiveSettingsView: View {
        @Bindable var store: LiveSettingsStore
        let shortcuts: any ShortcutRunner
        let workspace: any WorkspaceActions
        @State private var testResult: String?
        /// The last Test was refused because Automation is off for Segue.
        @State private var testNotPermitted = false

        var body: some View {
            Form {
                Section("Lyrics on stage") {
                    LabeledContent("Minimum lyric size") {
                        Stepper(value: minSize, in: LiveSettings.minLyricSizeRange, step: 1) {
                            Text("\(Int(store.settings.minLyricSize)) pt")
                                .monospacedDigit()
                        }
                        .accessibilityIdentifier(AccessibilityID.settingsMinLyricSize)
                    }
                    Text("Songs that do not fit at this size scroll instead of shrinking.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Picker("Columns", selection: $store.settings.defaultColumns) {
                        Text("Auto").tag(Int?.none)
                        ForEach(LiveSettings.columnRange, id: \.self) { count in
                            Text("\(count)").tag(Int?.some(count))
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .accessibilityIdentifier(AccessibilityID.settingsDefaultColumns)
                    Text(Self.columnsHelp)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("Gig Mode Shortcuts") {
                    shortcutRow(
                        "On show start",
                        text: shortcutBinding(\.startShortcut),
                        prompt: LiveSettings.suggestedStartShortcut,
                        id: AccessibilityID.settingsStartShortcut,
                    )
                    shortcutRow(
                        "On show end",
                        text: shortcutBinding(\.endShortcut),
                        prompt: LiveSettings.suggestedEndShortcut,
                        id: AccessibilityID.settingsEndShortcut,
                    )
                    Toggle("Also run them for rehearsals", isOn: $store.runsShortcutsForRehearsals)
                        .accessibilityIdentifier(AccessibilityID.settingsRehearsalShortcuts)
                    if let testResult {
                        Text(testResult)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(AccessibilityID.settingsShortcutTestResult)
                    }
                    if testNotPermitted,
                       let url = AppleEventShortcutRunner.Message.automationSettingsURL
                    {
                        Button("Open Automation Settings…") { workspace.open(url) }
                            .accessibilityIdentifier(AccessibilityID.settingsAutomationSettings)
                    }
                    Text(Self.guide)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("Pre-show checklist") {
                    ForEach(ChecklistItem.allCases, id: \.self) { item in
                        Toggle(Self.title(item), isOn: checklistBinding(item))
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 520)
        }

        static let columnsHelp = "Auto fits each song at the largest size, preferring two "
            + "columns. A song's own choice (C on stage, or Stage in the song editor) wins over "
            + "this default."

        static let guide = "Gig Mode Shortcuts are off until you set them up. Segue cannot switch "
            + "Focus on by itself, so it can run a Shortcut you own when a show starts and ends. "
            + "Create a Shortcut named “\(LiveSettings.suggestedStartShortcut)” that turns on "
            + "your Performing Focus, then enter its name here. Do the same with "
            + "“\(LiveSettings.suggestedEndShortcut)” turning it off. Press Test once and "
            + "allow Segue to control Shortcuts Events: that lets Segue run them and see that "
            + "they finished. Segue brings the stage back to the front afterwards."

        private func shortcutRow(
            _ label: String,
            text: Binding<String>,
            prompt: String,
            id: String,
        ) -> some View {
            LabeledContent(label) {
                HStack(spacing: 8) {
                    // The suggested name is a placeholder only, never a stored value (R18).
                    TextField("Shortcut name", text: text, prompt: Text(prompt))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .autocorrectionDisabled()
                        .accessibilityIdentifier(id)
                    Button("Test") { test(text.wrappedValue) }
                        .disabled(LiveSettingsStore.shortcutName(text.wrappedValue) == nil)
                }
            }
        }

        /// Runs the Shortcut through the app's runner and shows what was really observed.
        /// This is where the one-time Automation prompt appears, so it never first shows up
        /// mid-show.
        private func test(_ name: String) {
            guard let name = LiveSettingsStore.shortcutName(name) else { return }
            testResult = "Running “\(name)”…"
            testNotPermitted = false
            Task {
                let outcome = await shortcuts.runAskingPermission(name)
                testNotPermitted = outcome == .failed(AppleEventShortcutRunner.Message.notPermitted)
                testResult = switch outcome {
                case .completed: "“\(name)” ran."
                case .handedOver:
                    "Asked Shortcuts to run “\(name)”; Segue can’t confirm it finished."
                case let .failed(message): "“\(name)” failed: \(message)."
                }
            }
        }

        private var minSize: Binding<Double> {
            Binding(
                get: { store.settings.minLyricSize },
                set: { store.settings.minLyricSize = LiveSettingsStore.clampedMinLyricSize($0) },
            )
        }

        private func shortcutBinding(_ keyPath: WritableKeyPath<LiveSettings, String?>)
            -> Binding<String>
        {
            Binding(
                get: { store.settings[keyPath: keyPath] ?? "" },
                set: { store.settings[keyPath: keyPath] = $0.isEmpty ? nil : $0 },
            )
        }

        private func checklistBinding(_ item: ChecklistItem) -> Binding<Bool> {
            Binding(
                get: { !store.settings.hiddenChecklistItems.contains(item) },
                set: { shown in
                    if shown {
                        store.settings.hiddenChecklistItems.remove(item)
                    } else {
                        store.settings.hiddenChecklistItems.insert(item)
                    }
                },
            )
        }

        static func title(_ item: ChecklistItem) -> String {
            switch item {
            case .focus: "Focus on"
            case .charger: "Charger connected"
            case .brightness: "Screen brightness up"
            }
        }
    }
#endif
