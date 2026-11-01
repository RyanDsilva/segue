#if os(macOS)
    import Services
    import SwiftUI

    /// "Chords / Singer" (P9-2 section 7, R187 direction A): a small native segmented control
    /// that names both states, in the library pane beside Play Along and in the editor's
    /// display group. It flips the previews' shared `PreviewPrefs.singer`, never the stage's.
    struct SingerPreviewPicker: View {
        let prefs: PreviewPrefs
        let context: FeatureContext
        let identifier: String

        var body: some View {
            Picker("Preview", selection: selection) {
                Text("Chords").tag(false)
                Text("Singer").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Preview lyrics only, as a singer sees them")
            .accessibilityLabel("Preview")
            .accessibilityValue(prefs.singer ? "Singer, lyrics only" : "Chords")
            .accessibilityIdentifier(identifier)
        }

        private var selection: Binding<Bool> {
            Binding(
                get: { prefs.singer },
                set: { prefs.setSinger($0, from: context) },
            )
        }
    }
#endif
