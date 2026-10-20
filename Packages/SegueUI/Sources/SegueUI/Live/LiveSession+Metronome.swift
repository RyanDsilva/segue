#if os(macOS)
    import Shows

    /// The stage metronome's keys (R90): `M` the pulse, `⇧M` the rehearsal click.
    extension LiveSession {
        func dispatchMetronome(_ command: LiveCommand) {
            switch command {
            case .toggleMetronome:
                metronome.toggle()
                flash(metronome.isOn
                    ? (metronome.track == nil ? "Metronome on: no tempo" : "Metronome on")
                    : "Metronome off")
            case .toggleMetronomeClick:
                if metronome.toggleClick() {
                    flash(metronome.clicks ? "Click on" : "Click off")
                } else {
                    notice = "The click sounds in rehearsals only, never in a show."
                }
            default:
                break
            }
        }
    }
#endif
