#if os(macOS)
    import ChordPro
    import Editing
    import Foundation
    import Library
    import LiveLayout
    import Printing
    import Setlists

    // P9-1 spec 5.10 and 9 (R178, R193): slot and setlist songbook jobs, and a medley slot as
    // one print song whose members flow on, each later one opening with the stage's member
    // header at paper sizes.

    extension PrintRequests {
        /// A slot export: a song slot, a medley slot (the medley alone), or one member.
        static func slotJob(
            _ slot: PDFSlotSnapshot,
            snapshot: PDFSnapshot,
            options: PrintOptions,
        ) -> PrintJob {
            if let medley = slot.medley {
                var printed = MedleyPrint(
                    medley: medley,
                    records: slot.records,
                    number: slot.number,
                    index: 0,
                    snapshot: snapshot,
                    options: options,
                )
                return PrintJob(
                    target: .slot,
                    title: snapshot.title,
                    songs: printed.build().song.map { [$0] } ?? [],
                    options: options,
                    date: snapshot.date,
                )
            }
            let songs = slot.record.map { record in
                [song(
                    record,
                    slot: StageSlot(slot.entry),
                    snapshot: snapshot,
                    options: options,
                    slotLabel: slot.slotLabel,
                )]
            } ?? []
            return PrintJob(
                target: .slot,
                title: snapshot.title,
                songs: songs,
                options: options,
                author: slot.record
                    .flatMap { ArtistNames.display($0.document.metadata.artists) },
                tags: slot.record?.sidecar.tags ?? [],
                date: snapshot.date,
            )
        }

        /// The songs of a setlist songbook in set order, with the set list's slots.
        struct SetlistSongs {
            var songs: [PrintSong] = []
            var slots: [SetlistItemID: PrintSlot] = [:]
            var medleys: [SetlistItemID: PrintMedleySlot] = [:]
        }

        static func setlistSongs(
            _ setlist: Setlist,
            records: [SongID: SongRecord],
            snapshot: PDFSnapshot,
            options: PrintOptions,
        ) -> SetlistSongs {
            let total = setlist.entries.count { !$0.isBreak }
            var result = SetlistSongs()
            var number = 0
            for entry in setlist.entries where !entry.isBreak {
                number += 1
                if let medley = entry.medley {
                    var printed = MedleyPrint(
                        medley: medley,
                        records: records,
                        number: number,
                        index: result.songs.count,
                        snapshot: snapshot,
                        options: options,
                    )
                    let built = printed.build()
                    result.medleys[entry.itemId] = built.slot
                    result.songs += built.song.map { [$0] } ?? []
                    continue
                }
                guard let id = entry.songId, let record = records[id] else { continue }
                let song = song(
                    record,
                    slot: StageSlot(entry),
                    snapshot: snapshot,
                    options: options,
                    slotLabel: "\(number) of \(total)",
                    outlineTitle: "\(number). \(SongSummary.title(record))",
                )
                result.slots[entry.itemId] = PrintSlot(
                    title: song.header.title,
                    credits: song.header.credits,
                    key: setListKey(song.request.model, part: options.part),
                    song: result.songs.count,
                )
                result.songs.append(song)
            }
            return result
        }

        static func setlistJob(
            _ setlist: Setlist,
            records: [SongID: SongRecord],
            snapshot: PDFSnapshot,
            options: PrintOptions,
        ) -> PrintJob {
            let printed = setlistSongs(
                setlist,
                records: records,
                snapshot: snapshot,
                options: options,
            )
            let timing = SetlistTiming(
                setlist: setlist,
                songs: { records[$0] },
                defaultChangeover: snapshot.defaultChangeover,
            )
            let rows = PrintSetList.rows(
                entries: setlist.entries,
                timing: timing,
                slots: printed.slots,
                medleys: printed.medleys,
            )
            let count = setlist.songCount
            let venue = setlist.venue?.trimmingCharacters(in: .whitespaces)
            let line = [
                venue?.isEmpty == false ? venue : nil,
                setlist.date?.displayText,
                count == 1 ? "1 song" : "\(count) songs",
                timing.totalText,
            ].compactMap(\.self).joined(separator: " \u{00B7} ")
            let subject = [venue?.isEmpty == false ? venue : nil, setlist.date?.displayText]
                .compactMap(\.self).joined(separator: " \u{00B7} ")
            return PrintJob(
                target: .setlist,
                title: setlist.name,
                songs: printed.songs,
                contents: PrintJob.Contents(title: setlist.name, line: line, rows: rows),
                options: options,
                subject: subject.isEmpty ? nil : subject,
                footerName: setlist.name,
                date: snapshot.date,
            )
        }
    }

    /// A medley slot as one print song (P9-1 spec 9, R193): a segment per member with its own
    /// overrides, arrangement, walk-ups and notes; each later member opens with the stage's
    /// member header (its transition and change line), the first member's header being the
    /// page header ("Medley 5 · 1 of 3"). Also the set list slot: the medley row and a row
    /// per member. No song when every member is missing.
    @MainActor
    struct MedleyPrint {
        let medley: SetlistMedley
        let records: [SongID: SongRecord]
        /// The slot's number in the set, and the print song's index in the job.
        let number: Int
        let index: Int
        let snapshot: PDFSnapshot
        let options: PrintOptions

        private var segments: [LayoutSegment] = []
        private var members: [PrintMember] = []
        private var slots: [PrintSlot?] = []
        private var segmentIndexes: [Int?] = []
        private var diagrams: [RenderDiagram] = []
        private var pageHeader: PrintHeader?

        init(
            medley: SetlistMedley,
            records: [SongID: SongRecord],
            number: Int,
            index: Int,
            snapshot: PDFSnapshot,
            options: PrintOptions,
        ) {
            self.medley = medley
            self.records = records
            self.number = number
            self.index = index
            self.snapshot = snapshot
            self.options = options
        }

        private var lyrics: Bool {
            options.part == .lyrics
        }

        mutating func build() -> (song: PrintSong?, slot: PrintMedleySlot) {
            for position in medley.members.indices {
                add(position)
            }
            let titles = slots.compactMap { $0?.title }
            let slot = PrintMedleySlot(
                title: medley.title ?? "Medley: " + SetlistMedley.memberLine(titles),
                song: pageHeader == nil ? nil : index,
                members: slots,
                segments: segmentIndexes,
            )
            guard let pageHeader else { return (nil, slot) }
            var request = LayoutRequest(
                segments: segments,
                viewport: LayoutSize(width: 1, height: 1),
                minLyricSize: options.textSize.lyricSize,
                style: .print(lyricSize: options.textSize.lyricSize),
                view: lyrics ? .singer : .chart,
            )
            // The request's own model (the first member's) carries the medley's diagrams,
            // every member's once, for the block after the last section (spec 5.8).
            request.model.diagrams = diagrams
            let block = diagrams.isEmpty ? nil : PrintDiagramBlock(
                count: diagrams.count,
                cell: PrintDiagramCell.size(request.model),
                spacing: PrintDiagramCell.spacing,
            )
            let song = PrintSong(
                request: request,
                header: pageHeader,
                diagrams: block,
                outlineTitle: "\(number). \(medley.displayTitle)",
                members: members,
            )
            return (song, slot)
        }

        /// Member `position`: its segment, page header (the first printed member), member
        /// entry, set list slot and diagrams; a missing song only holds its row's place.
        private mutating func add(_ position: Int) {
            let member = medley.members[position]
            guard let record = records[member.songId] else {
                slots.append(nil)
                segmentIndexes.append(nil)
                return
            }
            let slot = StageSlot(
                overrides: member.overrides,
                note: member.note,
                arrangement: member.arrangement,
            )
            let resolution = StageRequest.resolution(slot.arrangement, song: record)
            var passes: [PlayedPass]?
            if case let .applied(order, _) = resolution {
                passes = order
            }
            let model = StageRequest.renderModel(
                record,
                overrides: slot.overrides,
                bass: PrintRequests.bassView(snapshot.profile, options: options),
                diagrams: PrintRequests.showsDiagrams(record, options: options),
                userShapes: snapshot.userShapes,
            )
            if lyrics {
                passes = PrintRequests.singerPasses(model, passes: passes)
            }
            let label = "Medley \(number) \u{00B7} \(position + 1) of \(medley.members.count)"
            let title = SongSummary.title(record)
            segments.append(LayoutSegment(
                model: model,
                passes: passes,
                cues: options.stageNotes ? record.sidecar.cues : [],
                notes: options.stageNotes && !lyrics
                    ? StageRequest.notes(record, slot: slot) : [],
                walkUps: lyrics ? nil
                    : StageRequest.walkUps(model, song: record, passes: passes),
                // The first printed member's header is the page header (R193).
                header: pageHeader == nil ? nil : memberHeader(position, record: record),
            ))
            if pageHeader == nil {
                pageHeader = PrintRequests.header(
                    record,
                    model: model,
                    part: options.part,
                    outOfDate: resolution?.isOutOfDate == true,
                    slotLabel: label,
                )
            }
            members.append(PrintMember(title: title, slotLabel: label))
            noteSlot(title: title, model: model)
        }

        /// The member's set list row, its segment and its diagrams (each name once).
        private mutating func noteSlot(title: String, model: RenderModel) {
            slots.append(PrintSlot(
                title: title,
                credits: SongSummary.credits(
                    artists: model.header.artists,
                    album: model.header.album,
                ),
                key: PrintRequests.setListKey(model, part: options.part),
                song: index,
            ))
            segmentIndexes.append(segments.count - 1)
            for diagram in model.diagrams where !diagrams.contains(where: {
                $0.name == diagram.name
            }) {
                diagrams.append(diagram)
            }
        }

        /// The stage's member header (P9-3 9.2), so stage and paper say the same thing.
        private func memberHeader(_ position: Int, record: SongRecord) -> MemberHeader {
            let previous = position > 0 ? medley.members[position - 1] : nil
            return MemberHeader.make(
                member: medley.members[position],
                previous: previous,
                record: record,
                previousRecord: previous.flatMap { records[$0.songId] },
                index: position,
                count: medley.members.count,
                title: SongSummary.title(record),
                singer: lyrics,
            )
        }
    }
#endif
