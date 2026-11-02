#if os(macOS)
    import AppKit
    import ChordPro
    import Diagrams
    import Editing
    import Foundation
    import Library
    import LiveLayout
    import Printing
    import Setlists
    import Shows
    import SwiftUI

    /// What a PDF export prints (P9-1 spec section 4).
    enum PDFTarget: Equatable {
        case song(SongID)
        case slot(SetlistID, SetlistItemID)
        case setlist(SetlistID)
        /// Two or more library songs, in the list's order (spec 5.13).
        case selection([SongID])

        var kind: PrintJob.Target {
            switch self {
            case .song: .song
            case .slot: .slot
            case .setlist: .setlist
            case .selection: .selection
            }
        }
    }

    /// The songs and setlist an export prints, taken when the sheet opens (spec 6.2: the PDF
    /// is a snapshot; edits made while the sheet is open are not followed).
    struct PDFSnapshot {
        enum Content {
            case song(SongRecord)
            case slot(PDFSlotSnapshot)
            case setlist(Setlist, [SongID: SongRecord])
            case selection([SongRecord])
        }

        var content: Content
        var profile: InstrumentProfile
        var userShapes: UserShapeLibrary
        /// Settings > General's changeover, for the set list totals.
        var defaultChangeover: Int
        var date: Date

        /// Every song record the export prints.
        var records: [SongRecord] {
            switch content {
            case let .song(record): [record]
            case let .slot(slot):
                slot.record.map { [$0] } ?? slot.entry.songIds.compactMap { slot.records[$0] }
            case let .setlist(setlist, songs): setlist.songIds.compactMap { songs[$0] }
            case let .selection(records): records
            }
        }

        /// The sheet's title: the song's title or the setlist's name.
        var title: String {
            switch content {
            case let .song(record): SongSummary.title(record)
            case let .slot(slot):
                slot.record.map(SongSummary.title) ?? slot.medley?.displayTitle ?? "Untitled"
            case let .setlist(setlist, _): setlist.name
            case .selection: "Songbook"
            }
        }

        var target: PrintJob.Target {
            switch content {
            case .song: .song
            case .slot: .slot
            case .setlist: .setlist
            case .selection: .selection
            }
        }

        /// The medley slots it prints (analytics' `segue.medleys`).
        var medleyCount: Int {
            switch content {
            case let .slot(slot): slot.medley == nil ? 0 : 1
            case let .setlist(setlist, _): setlist.entries.count { $0.medley != nil }
            case .selection, .song: 0
            }
        }

        /// Any printed song has a saved fill (the Bass part's Fills as tab option shows).
        var hasFills: Bool {
            records.contains { !$0.sidecar.parts.isEmpty }
        }
    }

    /// A slot export: the slot, its song (nil when missing or a medley), its number among the
    /// numbered slots and how many the set has. A medley slot carries its members' songs; a
    /// medley member exported alone carries its label ("Medley 5 · 2 of 3").
    struct PDFSlotSnapshot {
        var setlist: Setlist
        var entry: SetlistEntry
        var record: SongRecord?
        var number: Int
        var total: Int
        var records: [SongID: SongRecord] = [:]
        var label: String?

        var medley: SetlistMedley? {
            entry.medley
        }

        /// "4 of 18", or a member's "Medley 5 · 2 of 3".
        var slotLabel: String {
            label ?? "\(number) of \(total)"
        }
    }

    /// Builds the print job the stage's way (spec decision 2): `StageRequest`'s statics
    /// resolve each slot's arrangement, render the model with its overrides and the bass view,
    /// and attach walk-ups and fills; print only swaps the style, drops the zoom, and adds
    /// notes and cues when the export includes them and diagrams when asked.
    @MainActor
    enum PrintRequests {
        static let outOfDateNotice = "Arrangement out of date: printed as written"

        static func job(_ snapshot: PDFSnapshot, options: PrintOptions) -> PrintJob {
            switch snapshot.content {
            case let .song(record):
                let song = song(record, slot: StageSlot(), snapshot: snapshot, options: options)
                return PrintJob(
                    target: .song,
                    title: song.header.title,
                    songs: [song],
                    options: options,
                    author: ArtistNames.display(record.document.metadata.artists),
                    tags: record.sidecar.tags,
                    date: snapshot.date,
                )
            case let .slot(slot):
                return slotJob(slot, snapshot: snapshot, options: options)
            case let .setlist(setlist, records):
                return setlistJob(setlist, records: records, snapshot: snapshot, options: options)
            case let .selection(records):
                return selectionJob(records, snapshot: snapshot, options: options)
            }
        }

        private static func selectionJob(
            _ records: [SongRecord],
            snapshot: PDFSnapshot,
            options: PrintOptions,
        ) -> PrintJob {
            let songs = records.map { record in
                song(record, slot: StageSlot(), snapshot: snapshot, options: options)
            }
            let slots = songs.enumerated().map { index, song in
                PrintSlot(
                    title: song.header.title,
                    credits: song.header.credits,
                    key: setListKey(song.request.model, part: options.part),
                    song: index,
                )
            }
            let count = records.count == 1 ? "1 song" : "\(records.count) songs"
            return PrintJob(
                target: .selection,
                title: PrintFileName.selectionTitle(songs: records.count),
                songs: songs,
                contents: PrintJob.Contents(
                    title: "Songbook",
                    line: count,
                    rows: PrintSetList.selectionRows(slots),
                ),
                options: options,
                footerName: "Songbook",
                date: snapshot.date,
            )
        }

        /// One song or slot: its layout request (style, size and zoom set by the
        /// assembler), its header and its diagrams.
        static func song(
            _ record: SongRecord,
            slot: StageSlot,
            snapshot: PDFSnapshot,
            options: PrintOptions,
            slotLabel: String? = nil,
            outlineTitle: String? = nil,
        ) -> PrintSong {
            let resolution = StageRequest.resolution(slot.arrangement, song: record)
            var passes: [PlayedPass]?
            if case let .applied(order, _) = resolution {
                passes = order
            }
            let bass = bassView(snapshot.profile, options: options)
            let diagrams = showsDiagrams(record, options: options)
            let model = StageRequest.renderModel(
                record,
                overrides: slot.overrides,
                bass: bass,
                diagrams: diagrams,
                userShapes: snapshot.userShapes,
            )
            let lyrics = options.part == .lyrics
            if lyrics {
                passes = singerPasses(model, passes: passes)
            }
            var request = LayoutRequest(
                model: model,
                viewport: LayoutSize(width: 1, height: 1),
                minLyricSize: options.textSize.lyricSize,
                cues: options.stageNotes ? record.sidecar.cues : [],
                notes: options.stageNotes ? StageRequest.notes(record, slot: slot) : [],
                passes: passes,
                style: .print(lyricSize: options.textSize.lyricSize),
                walkUps: StageRequest.walkUps(model, song: record, passes: passes),
            )
            if lyrics {
                request = lyricsRequest(request)
            }
            let header = header(
                record,
                model: model,
                part: options.part,
                outOfDate: resolution?.isOutOfDate == true,
                slotLabel: slotLabel,
            )
            let block = diagrams && !model.diagrams.isEmpty
                ? PrintDiagramBlock(
                    count: model.diagrams.count,
                    cell: PrintDiagramCell.size(model),
                    spacing: PrintDiagramCell.spacing,
                ) : nil
            return PrintSong(
                request: request,
                header: header,
                diagrams: block,
                outlineTitle: outlineTitle,
            )
        }

        /// A song's header lines: the Lyrics part shows the sounding key with no capo and no
        /// scale line ("Key A, 96", R178).
        static func header(
            _ record: SongRecord,
            model: RenderModel,
            part: PrintPart,
            outOfDate: Bool,
            slotLabel: String?,
        ) -> PrintHeader {
            let lyrics = part == .lyrics
            return PrintHeader(
                title: SongSummary.title(record),
                credits: SongSummary.credits(
                    artists: model.header.artists,
                    album: model.header.album,
                ),
                performance: lyrics
                    ? SongSummary.singerKeyLine(
                        key: model.transform.concertKey,
                        tempo: model.header.tempo,
                    )
                    : SongSummary.performanceLine(model),
                scale: lyrics ? nil : model.header.scale.map { "Sounding \($0)" },
                notice: outOfDate ? outOfDateNotice : nil,
                slotLabel: slotLabel,
            )
        }

        /// The Bass notes part: the user's profile with the notes forced on and the export's
        /// Fills as tab (never written back to the profile). Nil for the other parts.
        static func bassView(_ profile: InstrumentProfile, options: PrintOptions) -> BassView? {
            guard options.part == .bass else { return nil }
            var profile = profile
            profile.bassNotes = true
            profile.fillsAsTab = options.fillsAsTab
            return profile.bassView
        }

        /// Diagrams print in the Chords part only: per song (its own toggle), all or none.
        static func showsDiagrams(_ record: SongRecord, options: PrintOptions) -> Bool {
            guard options.part == .chords else { return false }
            return switch options.diagrams {
            case .asSong: record.sidecar.displayPrefs.displayOptions.showDiagrams
            case .all: true
            case .off: false
            }
        }

        /// The set list page's key: the performance line without the tempo ("A, capo 2"; the
        /// sounding key in the bass part; "Key A" in the Lyrics part, as singer view's header
        /// says it, P9-2 section 8 item 4).
        static func setListKey(_ model: RenderModel, part: PrintPart = .chords) -> String? {
            if part == .lyrics {
                return SongSummary.singerKeyLine(key: model.transform.concertKey, tempo: nil)
            }
            var model = model
            model.header.tempo = nil
            return SongSummary.performanceLine(model)
        }

        /// The Lyrics part's request (spec section 8): the stage's singer request (lyrics
        /// only, no walk-ups, fills or song and slot notes; cues stay when included), at the
        /// print style and size the assembler sets, never the singer stage's zoom or floor.
        static func lyricsRequest(_ request: LayoutRequest) -> LayoutRequest {
            var lyrics = StageRequest.singerRequest(request, settings: LiveSettings())
            lyrics.style = request.style
            lyrics.minLyricSize = request.minLyricSize
            lyrics.zoom = 1
            return lyrics
        }

        /// The passes a lyric sheet prints: the slot's (nil = the full song) less any
        /// unlabelled block with nothing to sing or read, which singer view's previews and
        /// print leave out (P9-2 5.2 rule 7) while the stage keeps it as a pass. Nil when
        /// nothing is left out, so a full song stays a full song.
        static func singerPasses(_ model: RenderModel, passes: [PlayedPass]?) -> [PlayedPass]? {
            let kept = Set(SingerView.sections(model.sections).map(\.id))
            let units = SongSections.units(of: model.sections)
            let order = passes ?? ArrangementResolver.fullSong(units)
            let shown = order.filter { pass in
                model.sections.indices.contains(pass.index)
                    && kept.contains(model.sections[pass.index].id)
            }
            guard shown.count != order.count, !shown.isEmpty else { return passes }
            return shown
        }
    }

    /// The printed diagram cells: compact diagrams in cells of one size per song.
    @MainActor
    enum PrintDiagramCell {
        static let spacing = 10.0

        /// The largest cell of the song's diagrams, measured as SwiftUI lays them out.
        static func size(_ model: RenderModel) -> LayoutSize {
            var width = 0.0
            var height = 0.0
            for diagram in model.diagrams {
                let host = NSHostingView(rootView: PrintDiagramView(
                    diagram: diagram,
                    instrument: model.transform.options.instrument,
                    tuning: model.tuning,
                ))
                let size = host.fittingSize
                width = max(width, size.width)
                height = max(height, size.height)
            }
            return LayoutSize(width: width.rounded(.up), height: height.rounded(.up))
        }
    }

    private extension String {
        var nonEmpty: String? {
            isEmpty ? nil : self
        }
    }
#endif
