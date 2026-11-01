#if os(macOS)
    import Shows
    import SwiftUI

    /// Live (P3-14 via P3-4, the menus' owner): stage commands while a show is up. The
    /// items carry no plain-letter key equivalent: the stage reads its own keys (`M` for the
    /// metronome, `InputBindings`), and a plain-letter menu equivalent would swallow that
    /// letter in every text field of the main window during a show. Singer View has ⌥⌘V.
    struct LiveCommands: Commands {
        let app: AppModel

        /// Through the stage (flash, same pass).
        private var singerView: Binding<Bool> {
            Binding(
                get: { app.liveSettings.settings.singerView },
                set: { app.live?.setSingerView($0) },
            )
        }

        var body: some Commands {
            CommandMenu("Live") {
                Button("Metronome") {
                    app.live?.dispatchMetronome(.toggleMetronome)
                }
                .disabled(app.live == nil)
                .help("Pulse the song's tempo on stage (M on the stage)")
                // ⌥⌘V (R188): shares its chord with New Song from Clipboard, which is off
                // during a show, so this one is on only during one; plain V on stage too.
                Toggle(MenuShortcuts.singerView.title, isOn: singerView)
                    .keyboardShortcut(MenuShortcuts.singerView)
                    .disabled(app.live == nil)
                    .help("Show lyrics only on stage, chords hidden (V on the stage)")
            }
        }
    }
#endif
