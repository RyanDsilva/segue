#if os(macOS)
    import Shows

    /// The checklist's metronome switch (R108): it writes Settings > Live, so the choice is
    /// the next show's default too. The click switch (`rehearsalClickOn`) is per rehearsal.
    public extension PreShowChecklist {
        /// The stage metronome's pulse for this show.
        var metronomeOn: Bool {
            get { settings.metronomeOn }
            set { settings.metronomeOn = newValue }
        }

        /// The click, offered for a rehearsal only.
        var offersClick: Bool {
            kind == .rehearsal
        }
    }
#endif
