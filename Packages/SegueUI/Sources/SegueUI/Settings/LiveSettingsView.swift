#if os(macOS)
    import Shows
    import SwiftUI

    /// The app's Settings window (Segue > Settings…).
    public struct SegueSettingsView: View {
        let app: AppModel

        public init(app: AppModel) {
            self.app = app
        }

        public var body: some View {
            TabView {
                Tab("Live", systemImage: "music.mic") {
                    LiveSettingsView(
                        store: app.liveSettings,
                        shortcuts: app.dependencies.live.shortcuts,
                    )
                }
            }
            .frame(width: 560)
        }
    }

    /// Settings > Live: minimum lyric size, the Gig Mode Shortcuts (with Test buttons and a
    /// short guide) and the pre-show checklist rows.
    struct LiveSettingsView: View {
        @Bindable var store: LiveSettingsStore
        let shortcuts: any ShortcutRunner
        @State private var testResult: String?

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
                        id: AccessibilityID.settingsStartShortcut,
                    )
                    shortcutRow(
                        "On show end",
                        text: shortcutBinding(\.endShortcut),
                        id: AccessibilityID.settingsEndShortcut,
                    )
                    Toggle("Also run them for rehearsals", isOn: $store.runsShortcutsForRehearsals)
                        .accessibilityIdentifier(AccessibilityID.settingsRehearsalShortcuts)
                    if let testResult {
                        Text(testResult)
                            .font(.callout)
                            .foregroundStyle(.secondary)
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

        static let guide = "Segue cannot switch Focus on by itself, so it runs a Shortcut you own. "
            + "In the Shortcuts app, create a Shortcut named “Gig Mode On” with the action "
            + "“Set Focus” (Do Not Disturb, On), and “Gig Mode Off” turning it off. Segue runs "
            + "them when a show starts and ends, then brings the stage back to the front."

        private func shortcutRow(_ label: String, text: Binding<String>, id: String) -> some View {
            LabeledContent(label) {
                HStack(spacing: 8) {
                    TextField("Shortcut name", text: text, prompt: Text("None"))
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier(id)
                    Button("Test") { test(text.wrappedValue) }
                        .disabled(LiveSettingsStore.shortcutName(text.wrappedValue) == nil)
                }
            }
        }

        private func test(_ name: String) {
            guard let name = LiveSettingsStore.shortcutName(name) else { return }
            Task {
                do {
                    try await shortcuts.run(name)
                    testResult = "Asked Shortcuts to run “\(name)”."
                } catch {
                    testResult = "“\(name)” did not run: \(UserMessage.describe(error))"
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
