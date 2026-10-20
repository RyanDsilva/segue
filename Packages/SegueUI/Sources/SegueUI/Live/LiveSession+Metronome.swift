#if os(macOS)
    import Services
    import Shows

    /// The stage metronome's keys (R90, R118): `M` the pulse, `K` the rehearsal click.
    extension LiveSession {
        func dispatchMetronome(_ command: LiveCommand) {
            switch command {
            case .toggleMetronome:
                metronome.toggle()
                if metronome.isOn {
                    services.record(.featureUsed(.metronome, .stage))
                }
                flash(metronome.isOn
                    ? (metronome.track == nil ? "Metronome on: no tempo" : "Metronome on")
                    : "Metronome off")
            case .toggleMetronomeClick:
                // In a show K does nothing: there is no click to toggle.
                if metronome.toggleClick() {
                    flash(metronome.clicks ? "Click on" : "Click off")
                }
            default:
                break
            }
        }
    }
#endif
