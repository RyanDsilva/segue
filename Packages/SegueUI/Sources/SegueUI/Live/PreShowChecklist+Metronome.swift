#if os(macOS)
    import Shows

    /// The checklist's metronome switches (R108): they write Settings > Live, so the choice
    /// is the next show's default too.
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

        /// The rehearsal click for this rehearsal.
        var rehearsalClickOn: Bool {
            get { settings.rehearsalClickOn }
            set { settings.rehearsalClickOn = newValue }
        }
    }
#endif
