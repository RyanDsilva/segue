#if os(macOS)
    import Diagrams
    import Editing
    import Foundation
    import LiveLayout

    /// The bass-note view on stage (P8-4 6.5, 7.3): `B` flips the user-level setting for
    /// anyone, so the editor and the stage always agree; the mini neck shows where to play the
    /// chord at the reading line.
    extension LiveSession {
        /// The bass view the stage renders with (nil = chords as the song shows them).
        var bassView: BassView? {
            context.instrument?.bassView
        }

        /// `B`: the bass-note view on or off, re-laid out at once, with a brief "Bass notes" /
        /// "Chords" indicator.
        func toggleBassNotes() {
            guard let instrument = context.instrument else { return }
            instrument.toggleBassNotes(from: .stage)
            relayout()
            flash(instrument.profile.bassNotes ? "Bass notes" : "Chords")
        }

        /// `T`: "Fills as tab" on or off (P8-7 14.2), the same user-level setting as the
        /// editor's Bass menu and Settings; display only, so it works in Live and Rehearsal
        /// alike and never makes a sound. A song with no saved fill only flashes.
        func toggleFillTab() {
            guard let instrument = context.instrument else { return }
            guard currentSongHasFills else {
                flash("No fills in this song")
                return
            }
            instrument.toggleFillsAsTab(from: .stage)
            relayout()
            flash(instrument.profile.fillsAsTab ? "Fills as tab" : "Fills as names")
        }

        /// Whether the current slot's song has a saved fill (the status line then names `T`).
        var currentSongHasFills: Bool {
            state.current?.song?.sidecar.parts.isEmpty == false
        }

        /// Whether the mini neck is up: the bass view with its neck on, a laid-out song with
        /// at least one chord, not in a break (past the end and an unavailable song have no
        /// plan). Hidden otherwise, with no placeholder.
        var showsBassNeck: Bool {
            guard bassView?.neck == true, state.record.currentBreak == nil, let plan else {
                return false
            }
            return !StagePasses.placedChords(in: plan).isEmpty
        }

        /// The neck for the chord at the reading line at `now` (P8-4 7.3), in the profile's
        /// tuning for a bassist, else EADG; home from the sounding key, else the first bass note.
        func bassNeck(at now: Date) -> StageBassNeckState? {
            guard showsBassNeck, let plan, let model = currentModel,
                  let tuning = bassView?.tuning,
                  let chord = StagePasses.chord(
                      at: scrollOffset(at: now),
                      plan: plan,
                      pinned: pinnedPass,
                  )
            else { return nil }
            let first = StagePasses.placedChords(in: plan).first { $0.kind == .chord }
            let home = model.transform.concertKey.map { key in
                BassFretboard.homeFret(tonic: key.tonic.pitchClass, tuning: tuning)
            } ?? first.flatMap { StageBassNeckState.make(drawn: $0.text, home: 0, tuning: tuning) }
                .map { BassFretboard.homeFret(tonic: $0.pitchClass, tuning: tuning) } ?? 0
            // The chord as written gives its tones (R166); the drawn note is the fallback.
            var state = chord.written.flatMap { written in
                StageBassNeckState.make(
                    chord: written,
                    transform: model.transform,
                    home: home,
                    tuning: tuning,
                )
            } ?? StageBassNeckState.make(drawn: chord.text, home: home, tuning: tuning)
            state?.dimmed = chord.dimmed
            // A fill covering the change wins: its path, never also the walk-up's (P8-7 14.4).
            if let fill = chord.fill {
                return state?.with(fill: fill)
            }
            return state?.with(walkUp: chord.walkUp)
        }

        /// `bassNeck` once per stage session, when the neck first shows (P8-4 6.6).
        func recordBassNeckShown() {
            guard showsBassNeck, !bassNeckRecorded else { return }
            bassNeckRecorded = true
            services.record(.featureUsed(.bassNeck, .stage))
        }
    }
#endif
