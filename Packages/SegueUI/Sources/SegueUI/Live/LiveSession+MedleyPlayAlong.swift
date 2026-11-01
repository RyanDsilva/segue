#if os(macOS)
    import Editing
    import Foundation
    import Library
    import LiveLayout
    import Playback
    import Shows

    /// Rehearsal play-along through a medley (P9-3 9.8, R178): `P` plays from the pass on
    /// through the members as one timeline, each member in its own key, tempo, meter,
    /// corrections, walk-up density and saved fills, with the walk-up at each boundary
    /// planned in the next member's key, no gap and no count-in between members. A later
    /// member with no tempo ends the timeline at its header. The follow model commits members
    /// as the audio crosses them; a gig has no play-along at all.
    extension LiveSession {
        /// One member as play-along voices it.
        private struct MemberPlay {
            var title: String
            var song: SongRecord
            var model: RenderModel
            var order: [PlayedPass]
        }

        /// The member laid out as segment `segment`, with its stage model and played passes.
        private func memberPlay(_ segment: Int) -> MemberPlay? {
            guard medleySegments.indices.contains(segment),
                  let slot = state.medley
                      .first(where: { $0.item.itemId == medleySegments[segment] }),
                  let song = slot.song
            else { return nil }
            var order = ArrangementResolver.fullSong(SongSections.units(of: song.document))
            if case let .applied(passes, _) = StageRequest.resolution(
                slot.item.arrangement,
                song: song,
            ) {
                order = passes
            }
            return MemberPlay(
                title: SongSummary.title(song),
                song: song,
                model: StageRequest.renderModel(
                    song,
                    overrides: slot.item.overrides,
                    bass: bassView,
                ),
                order: order,
            )
        }

        /// From plan pass `planIndex`: its member from that pass (or the pass alone when it
        /// loops), then every later member whole until one has no tempo.
        func medleyPlayAlong(from planIndex: Int, looping: Bool) -> PreparedPlayAlong? {
            guard let plan, plan.passes.indices.contains(planIndex) else { return nil }
            let segment = plan.passes[planIndex].segment
            guard let first = plan.passes.firstIndex(where: { $0.segment == segment }),
                  let opener = memberPlay(segment)
            else { return nil }
            let index = planIndex - first
            guard opener.order.indices.contains(index) else { return nil }
            let profile = context.instrument?.profile
            var parts: [PlayAlongTimeline] = []
            var previous: MemberPlay?
            var stopsAt: String?
            for member in (segment ..< medleySegments.count).lazy.compactMap(memberPlay) {
                let isOpener = parts.isEmpty
                if !isOpener, looping {
                    break
                }
                let part = Self.part(
                    member,
                    range: isOpener ? (looping ? .section(index) : .from(index)) : .whole,
                    profile: profile,
                )
                if !isOpener, part.timeline.chords.contains(where: { $0.tempo == nil }) {
                    stopsAt = member.title
                    break
                }
                if let previous, let last = parts.indices.last {
                    parts[last] = Self.walkingUp(
                        parts[last],
                        from: previous,
                        into: member,
                        part,
                        profile: profile,
                    )
                }
                parts.append(part)
                previous = member
            }
            let timeline = PlayAlongTimeline.concatenating(parts)
            return PreparedPlayAlong(
                timeline: timeline,
                model: opener.model,
                passOffset: first,
                fills: timeline.fills,
                stopsAt: stopsAt,
            )
        }

        /// `range` of `member`'s played passes with its saved fills.
        private static func part(
            _ member: MemberPlay,
            range: PlayAlongRange,
            profile: InstrumentProfile?,
        ) -> PlayAlongTimeline {
            var part = playAlongTimeline(
                song: member.song,
                model: member.model,
                order: member.order,
                range: range,
                profile: profile,
            )
            part.fills = playAlongFills(
                song: member.song,
                model: member.model,
                order: member.order,
                profile: profile,
            )(part)
            return part
        }

        /// `part` (member `from`'s play-along) with its last chord walking up into the first
        /// chord of `next` (member `into`'s), planned in that member's key (P9-3 9.1).
        private static func walkingUp(
            _ part: PlayAlongTimeline,
            from: MemberPlay,
            into: MemberPlay,
            _ next: PlayAlongTimeline,
            profile: InstrumentProfile?,
        ) -> PlayAlongTimeline {
            guard let last = part.chords.indices.last, part.chords[last].concert != nil,
                  next.chords.first?.concert != nil
            else { return part }
            let arranged = ArrangedSections.build(from.model.sections, order: from.order)
            let following = ArrangedSections.build(into.model.sections, order: into.order)
            let change = BassLine.boundary(
                from: MemberPasses(
                    sections: arranged.map(\.section),
                    origins: arranged.map(\.source),
                    context: playAlongWalkUps(song: from.song, model: from.model, profile: profile),
                ),
                into: MemberPasses(
                    sections: following.map(\.section),
                    origins: following.map(\.source),
                    context: playAlongWalkUps(song: into.song, model: into.model, profile: profile),
                ),
            )
            var part = part
            part.chords[last].walk = change?.shown?.offsets ?? []
            return part
        }
    }
#endif
