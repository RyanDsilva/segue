#if os(macOS)
    import Editing
    import Foundation
    import Library
    import LiveLayout
    import Setlists
    import Shows

    /// A medley's stage request (P9-3 9.1): one segment per member, each with its own key,
    /// capo, arrangement, cues, notes and walk-ups, opened by a member header.
    extension StageRequest {
        /// What a medley plan was built from: its request and each member's arrangement
        /// resolution (an out-of-date member plays its full song, R122).
        struct Medley {
            var request: LayoutRequest
            var resolutions: [ShowItemID: ArrangementResolution]
        }

        static func make(
            medley slots: [ShowSlot],
            prefs: LivePrefs,
            settings: LiveSettings,
            minLyricSize: Double,
            viewport: LayoutSize,
            bass: BassView? = nil,
            singer: Bool = false,
        ) -> Medley {
            let bass = singer ? nil : bass
            var resolutions: [ShowItemID: ArrangementResolution] = [:]
            var segments: [LayoutSegment] = []
            for (index, slot) in slots.enumerated() {
                guard let song = slot.song else { continue }
                let stageSlot = StageSlot(slot.item)
                let resolution = resolution(stageSlot.arrangement, song: song)
                resolutions[slot.item.itemId] = resolution
                var passes: [PlayedPass]?
                if case let .applied(order, _) = resolution {
                    passes = order
                }
                let model = renderModel(song, overrides: stageSlot.overrides, bass: bass)
                segments.append(LayoutSegment(
                    model: model,
                    passes: passes,
                    cues: song.sidecar.cues,
                    notes: singer ? [] : notes(song, slot: stageSlot),
                    walkUps: walkUps(model, song: song, passes: passes),
                    header: header(slots, at: index, singer: singer),
                ))
            }
            var request = LayoutRequest(
                segments: segments,
                viewport: viewport,
                minLyricSize: minLyricSize,
                zoom: prefs.zoom,
                columns: settings.columns(for: prefs),
            )
            if singer {
                let singerRequest = singerRequest(request, settings: settings)
                request = singerRequest
                request.segments = segments.map { segment in
                    var segment = segment
                    segment.notes = []
                    segment.walkUps = nil
                    return segment
                }
            }
            return Medley(request: request, resolutions: resolutions)
        }

        /// Member `index`'s header, as print draws it too (`MemberHeader.make`).
        static func header(_ slots: [ShowSlot], at index: Int, singer: Bool) -> MemberHeader {
            let slot = slots[index]
            let previous = index > 0 ? slots[index - 1] : nil
            return MemberHeader.make(
                member: member(slot.item),
                previous: previous.map { member($0.item) },
                record: slot.song,
                previousRecord: previous?.song,
                index: slot.item.medley?.index ?? index,
                count: slot.item.medley?.count ?? slots.count,
                title: slot.song.map(SongSummary.title) ?? slot.item.title,
                singer: singer,
            )
        }

        /// A show item as the medley member it plays.
        static func member(_ item: ShowItem) -> MedleyMember {
            MedleyMember(
                itemId: item.itemId,
                songId: item.songId,
                overrides: item.overrides,
                note: item.note,
                arrangement: item.arrangement,
                transition: item.medley?.transition,
            )
        }
    }
#endif
