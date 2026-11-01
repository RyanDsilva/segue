#if os(macOS)
    import Editing
    import Foundation
    import Library
    import LiveLayout
    import Setlists
    import Shows

    /// What a stage needs from a setlist slot: its overrides, its note and its arrangement
    /// (P8-2 section 5.11). Built from a running show's item or a setlist entry, so the stage
    /// and the Arrange Sections preview lay a song out the same way.
    struct StageSlot: Equatable {
        var overrides: SetlistOverrides
        var note: String?
        var arrangement: SlotArrangement?

        init(
            overrides: SetlistOverrides = SetlistOverrides(),
            note: String? = nil,
            arrangement: SlotArrangement? = nil,
        ) {
            self.overrides = overrides
            self.note = note
            self.arrangement = arrangement
        }

        init(_ item: ShowItem) {
            self.init(overrides: item.overrides, note: item.note, arrangement: item.arrangement)
        }

        init(_ entry: SetlistEntry) {
            self.init(
                overrides: entry.overrides,
                note: entry.note,
                arrangement: entry.arrangement,
            )
        }
    }

    /// The one place a stage layout request is built (P8-2 section 5.11): the stage's
    /// `relayout()` and P8-3's preview call it, the preview with its draft arrangement.
    enum StageRequest {
        // The signature is the P8-3 contract (P8-2 section 5.11).
        // swiftlint:disable:next function_parameter_count
        static func make(
            song: SongRecord,
            slot: StageSlot,
            prefs: LivePrefs,
            settings: LiveSettings,
            minLyricSize: Double,
            viewport: LayoutSize,
            bass: BassView? = nil,
        ) -> (request: LayoutRequest, resolution: ArrangementResolution?) {
            let resolution = resolution(slot.arrangement, song: song)
            var passes: [PlayedPass]?
            if case let .applied(order, _) = resolution {
                passes = order
            }
            let notes = [song.sidecar.notes, slot.note]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let model = renderModel(song, overrides: slot.overrides, bass: bass)
            let request = LayoutRequest(
                model: model,
                viewport: viewport,
                minLyricSize: minLyricSize,
                zoom: prefs.zoom,
                columns: settings.columns(for: prefs),
                cues: song.sidecar.cues,
                notes: notes,
                passes: passes,
                walkUps: walkUps(model, song: song, passes: passes),
            )
            return (request, resolution)
        }

        /// Walk-ups and fills on stage, only in the bass-note view. Walk-ups (P8-4b) while
        /// the density is not Off: the song's pick else the top candidate, never alternates,
        /// none on a change a saved fill covers in that pass (P8-7c). The saved fills draw
        /// whatever the density (R175) where the played `passes` (nil = the full song) play
        /// them (P8-7e), on a timeline in that order built once per plan.
        static func walkUps(
            _ model: RenderModel,
            song: SongRecord,
            passes: [PlayedPass]? = nil,
        ) -> BassLineContext? {
            guard model.transform.options.bass?.notes == true,
                  let context = BassLine.context(
                      for: model,
                      document: song.document,
                      prefs: song.sidecar.bass,
                      parts: song.sidecar.parts,
                      order: passes
                          ?? ArrangementResolver.fullSong(SongSections.units(of: song.document)),
                  ),
                  context.draws
            else { return nil }
            return context
        }

        /// The song in a slot as it renders there: sidecar view options with the setlist
        /// overrides applied, no diagrams. The user's bass view (P8-4) is set before the
        /// overrides, so the slot's capo and transpose still feed the sounding pitch.
        static func renderModel(
            _ song: SongRecord,
            overrides: SetlistOverrides,
            bass: BassView? = nil,
        ) -> RenderModel {
            var options = song.sidecar.displayPrefs.displayOptions
            options.showDiagrams = false
            options.bass = bass
            let (applied, capo) = overrides.applied(
                to: options,
                songCapo: song.document.metadata.capo,
            )
            return RenderModel(document: song.document, options: applied, capo: capo)
        }

        /// A slot's arrangement checked against its song as loaded (R122); nil for a slot
        /// that plays the full song.
        static func resolution(
            _ arrangement: SlotArrangement?,
            song: SongRecord,
        ) -> ArrangementResolution? {
            arrangement.map {
                ArrangementResolver.resolve($0, units: SongSections.units(of: song.document))
            }
        }
    }
#endif
