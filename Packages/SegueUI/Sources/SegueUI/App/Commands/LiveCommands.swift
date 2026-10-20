#if os(macOS)
    import Shows
    import SwiftUI

    /// Live (P3-14 via P3-4, the menus' owner): stage commands while a show is up. The
    /// items carry no key equivalent: the stage reads its own keys (`M` for the metronome,
    /// `InputBindings`), and a plain-letter menu equivalent would swallow that letter in
    /// every text field of the main window during a show.
    struct LiveCommands: Commands {
        let app: AppModel

        var body: some Commands {
            CommandMenu("Live") {
                Button("Metronome") {
                    app.live?.dispatchMetronome(.toggleMetronome)
                }
                .disabled(app.live == nil)
                .help("Pulse the song's tempo on stage (M on the stage)")
            }
        }
    }
#endif
