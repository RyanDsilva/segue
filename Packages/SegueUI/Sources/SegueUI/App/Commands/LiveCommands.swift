#if os(macOS)
    import Shows
    import SwiftUI

    /// Live (P3-14 via P3-4, the menus' owner): stage commands while a show is up. The
    /// items carry no key equivalent: the stage reads its own keys (`M` for the metronome,
    /// `InputBindings`), and a plain-letter menu equivalent would swallow that letter in
    /// every text field of the main window during a show.
    struct LiveCommands: Commands {
        let app: AppModel

        /// Through the stage when it is up (flash, same pass), else the setting itself.
        private var singerView: Binding<Bool> {
            Binding(
                get: { app.liveSettings.settings.singerView },
                set: { on in
                    if let live = app.live {
                        live.setSingerView(on)
                    } else {
                        app.liveSettings.settings.singerView = on
                    }
                },
            )
        }

        var body: some Commands {
            CommandMenu("Live") {
                Button("Metronome") {
                    app.live?.dispatchMetronome(.toggleMetronome)
                }
                .disabled(app.live == nil)
                .help("Pulse the song's tempo on stage (M on the stage)")
                // A remembered setting, so it works before a show too (P9-2 6.1).
                Toggle("Singer View", isOn: singerView)
                    .help("Show lyrics only on stage, chords hidden (V on the stage)")
            }
        }
    }
#endif
