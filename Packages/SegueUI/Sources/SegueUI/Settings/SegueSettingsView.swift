#if os(macOS)
    import SwiftUI

    /// The app's Settings window (Segue > Settings…, WS2b 4.6): General, Appearance,
    /// Instrument (P8-4), Audio (P8-6), Live, AI (P3-3, R73), Privacy (WS3's view, hosted as is)
    /// and Data.
    /// The window title follows the pane, and the last pane comes back when Settings reopens
    /// (HIG).
    public struct SegueSettingsView: View {
        let app: AppModel

        public init(app: AppModel) {
            self.app = app
        }

        /// The panes, by the tag stored in `settings.selectedPane`.
        enum Pane: String, CaseIterable {
            case general
            case appearance
            case instrument
            case audio
            case live
            case ai
            case privacy
            case data
        }

        public var body: some View {
            let preferences = app.polish.preferences
            TabView(selection: Binding(
                get: { preferences.selectedPane.flatMap(Pane.init) ?? .general },
                set: { preferences.selectedPane = $0.rawValue },
            )) {
                Tab("General", systemImage: "gearshape", value: Pane.general) {
                    GeneralSettingsView(app: app)
                        .accessibilityIdentifier(AccessibilityID.settingsPane("general"))
                }
                Tab("Appearance", systemImage: "circle.lefthalf.filled", value: Pane.appearance) {
                    AppearanceSettingsView(store: app.polish.appearance)
                        .accessibilityIdentifier(AccessibilityID.settingsPane("appearance"))
                }
                Tab("Instrument", systemImage: "guitars", value: Pane.instrument) {
                    InstrumentSettingsView(store: app.instrumentProfile)
                        .accessibilityIdentifier(AccessibilityID.settingsPane("instrument"))
                }
                Tab("Audio", systemImage: "speaker.wave.2", value: Pane.audio) {
                    AudioSettingsView(sound: app.sound, instrument: app.instrumentProfile)
                        .accessibilityIdentifier(AccessibilityID.settingsPane("audio"))
                }
                Tab("Live", systemImage: "music.mic", value: Pane.live) {
                    LiveSettingsView(
                        store: app.liveSettings,
                        shortcuts: app.dependencies.live.shortcuts,
                        workspace: app.dependencies.workspace,
                    )
                }
                Tab("AI", systemImage: "sparkles", value: Pane.ai) {
                    AISettingsView(
                        ai: app.ai,
                        workspace: app.dependencies.workspace,
                        services: app.dependencies.services,
                    )
                    .accessibilityIdentifier(AccessibilityID.settingsPane("ai"))
                }
                Tab("Privacy", systemImage: "hand.raised", value: Pane.privacy) {
                    PrivacySettingsView(
                        store: app.dependencies.consent,
                        workspace: app.dependencies.workspace,
                    )
                }
                Tab("Data", systemImage: "externaldrive", value: Pane.data) {
                    DataSettingsView(app: app)
                        .accessibilityIdentifier(AccessibilityID.settingsPane("data"))
                }
            }
            .frame(width: 560)
            .guideLinks(app.dependencies.workspace)
        }
    }

    /// A pane's explanatory line under its controls.
    struct SettingsNote: View {
        let text: String

        var body: some View {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
#endif
