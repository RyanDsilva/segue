// Owner: P9-1 (spec 5, 7.1). Lays every song out on pages, numbers them after the set list
// pages, and builds the outline, links, metadata and file name. Pure.

import Foundation
import LiveLayout

/// What one export prints.
public struct PrintJob: Sendable {
    public enum Target: String, Sendable, Hashable, CaseIterable {
        case song
        case slot
        case setlist
        case selection
    }

    /// A set list page (a setlist songbook) or a contents page (a selection).
    public struct Contents: Sendable, Hashable {
        /// "Friday Set" or "Songbook".
        public var title: String
        /// "The Anchor · Fri 23 Oct 2026 · 18 songs · 1:12:30", or "12 songs".
        public var line: String?
        public var rows: [SetListRow]

        public init(title: String, line: String?, rows: [SetListRow]) {
            self.title = title
            self.line = line
            self.rows = rows
        }
    }

    public var target: Target
    /// The document title: the song's title, the setlist's name, or "Songbook".
    public var title: String
    public var songs: [PrintSong]
    public var contents: Contents?
    public var options: PrintOptions
    /// A single chart's artists ("A, B").
    public var author: String?
    /// A songbook's "Venue · date".
    public var subject: String?
    /// A single chart's tags.
    public var tags: [String]
    /// The footer's left side in a songbook: the setlist name or "Songbook".
    public var footerName: String?
    public var date: Date

    public init(
        target: Target,
        title: String,
        songs: [PrintSong],
        contents: Contents? = nil,
        options: PrintOptions,
        author: String? = nil,
        subject: String? = nil,
        tags: [String] = [],
        footerName: String? = nil,
        date: Date,
    ) {
        self.target = target
        self.title = title
        self.songs = songs
        self.contents = contents
        self.options = options
        self.author = author
        self.subject = subject
        self.tags = tags
        self.footerName = footerName
        self.date = date
    }

    public var isSongbook: Bool {
        target == .setlist || target == .selection
    }
}

/// One song laid out on its pages (before page numbers are known).
public struct LaidSong: Sendable {
    public var header: PrintHeader
    public var paged: PagedSong
    public var diagrams: PrintDiagramBlock?
    public var fitFailed: Bool
}

public enum PrintAssembler {
    /// The Fit on one page floor (spec 5.9).
    public static let fitFloor = 9.0

    /// The whole document.
    public static func document(_ job: PrintJob, metrics: any TextMeasuring) -> PrintDocument {
        let laid = job.songs.map { layout($0, job: job, metrics: metrics) }
        return assemble(job, laid: laid)
    }

    /// One song on pages: the header's map line, diagrams after the last section, Compact
    /// repeats when asked, Fit on one page for a single chart. Independent per song, so the
    /// caller may run songs concurrently.
    public static func layout(
        _ song: PrintSong,
        job: PrintJob,
        metrics: any TextMeasuring,
    ) -> LaidSong {
        let options = job.options
        let paper = options.paper
        let width = PrintPageMetrics.bodyWidth(paper)
        var header = song.header
        var request = song.request
        request.style = .print(lyricSize: options.textSize.lyricSize)
        let extras = song.diagrams.map { [$0.height(width: width)] } ?? []
        func paginate() -> PagedSong {
            PageLayout.paginate(
                request,
                page: PrintPageMetrics.geometry(
                    paper,
                    header: header,
                    columns: options.columns.count,
                ),
                extras: extras,
                compactRepeats: options.repeats == .compact,
                metrics: metrics,
            )
        }
        var paged = paginate()
        if options.sectionMap, let map = PrintMapLine.text(paged.passes) {
            header.mapLines = PrintMapLine.lines(map, width: width, metrics: metrics)
            paged = paginate()
        }
        var fitFailed = false
        if options.fitOnePage, !job.isSongbook, paged.pages.count > 1 {
            if let fitted = fitOnePage(
                request,
                header: header,
                extras: extras,
                job: job,
                metrics: metrics,
            ) {
                paged = fitted
            } else {
                fitFailed = true
            }
        }
        return LaidSong(header: header, paged: paged, diagrams: song.diagrams, fitFailed: fitFailed)
    }

    /// The stage's fit search on the first page's body (less any diagrams), down to 9 pt;
    /// nil when it does not fit.
    private static func fitOnePage(
        _ request: LayoutRequest,
        header: PrintHeader,
        extras: [Double],
        job: PrintJob,
        metrics: any TextMeasuring,
    ) -> PagedSong? {
        let options = job.options
        let geometry = PrintPageMetrics.geometry(options.paper, header: header, columns: nil)
        var request = request
        let reserved = extras
            .reduce(0) { $0 + $1 + options.textSize.lyricSize * request.style.sectionSpacing }
        request.viewport = LayoutSize(
            width: geometry.firstBody.width,
            height: geometry.firstBody.height - reserved,
        )
        request.minLyricSize = fitFloor
        request.zoom = 1
        request.columns = options.columns.count
        var plan = LayoutEngine.plan(request, metrics: metrics)
        guard plan.fit == .fits else { return nil }
        plan.pageStops = []
        plan.viewport = geometry.firstBody
        let bottom = plan.contentHeight
        let gap = plan.lyricSize * request.style.sectionSpacing
        var y = bottom > 0 ? bottom + gap : 0
        let placed = extras.enumerated().map { index, height in
            defer { y += height + gap }
            return PlacedExtra(index: index, page: 0, y: y, height: height)
        }
        return PagedSong(
            pages: [plan],
            extras: placed,
            columns: plan.columns.count,
        )
    }

    /// Numbers the pages: the set list pages first, then each song's pages in order.
    public static func assemble(_ job: PrintJob, laid: [LaidSong]) -> PrintDocument {
        let setList = job.contents.map { setListPages($0, paper: job.options.paper) } ?? []
        var firstPages: [Int] = []
        var next = setList.count
        for song in laid {
            firstPages.append(next)
            next += song.paged.pages.count
        }
        let total = next
        func footer(_ index: Int) -> PrintFooter {
            PrintFooter(left: job.footerName, right: "Page \(index + 1) of \(total)")
        }
        var pages: [PrintPage] = setList.enumerated().map { index, page in
            var page = page
            page.footer = footer(index)
            page.rows = page.rows.map { placed in
                var placed = placed
                if case let .song(song) = placed.row, firstPages.indices.contains(song.song) {
                    placed.target = firstPages[song.song]
                }
                return placed
            }
            return .setList(page)
        }
        for (index, song) in laid.enumerated() {
            let plans = song.paged.numbered(firstPage: firstPages[index] + 1)
            for (offset, plan) in plans.enumerated() {
                pages.append(.song(SongPage(
                    header: song.header,
                    isFirst: offset == 0,
                    plan: plan,
                    extras: song.paged.extras.filter { $0.page == offset },
                    diagrams: song.diagrams,
                    footer: footer(firstPages[index] + offset),
                    song: index,
                )))
            }
        }
        return PrintDocument(
            pages: pages,
            outline: outline(job, firstPages: firstPages),
            metadata: metadata(job),
            fileName: PrintFileName.name(title: job.title, part: job.options.part),
            paper: job.options.paper,
            fitFailed: laid.contains(where: \.fitFailed),
        )
    }

    /// The set list rows on as many pages as they need; rows never split.
    static func setListPages(_ contents: PrintJob.Contents, paper: PrintPaper) -> [SetListPage] {
        let body = paper.size.height - PrintPageMetrics.top - PrintPageMetrics.bottom
        var pages: [SetListPage] = []
        var rows: [PlacedSetListRow] = []
        var y = 0.0
        var capacity = body - SetListMetrics.headHeight(continuation: false)
        func close() {
            let continuation = !pages.isEmpty
            pages.append(SetListPage(
                head: SetListHead(
                    title: continuation ? "\(contents.title) (cont.)" : contents.title,
                    line: continuation ? nil : contents.line,
                    isContinuation: continuation,
                ),
                rows: rows,
                showsTimes: contents.rows.contains { row in
                    if case let .song(song) = row {
                        return song.time != nil
                    }
                    return false
                },
                footer: PrintFooter(left: nil, right: ""),
            ))
            rows = []
            y = 0
            capacity = body - SetListMetrics.headHeight(continuation: true)
        }
        for row in contents.rows {
            let height = SetListMetrics.height(row)
            if y + height > capacity, !rows.isEmpty {
                close()
            }
            rows.append(PlacedSetListRow(row: row, y: y, height: height, target: nil))
            y += height
        }
        close()
        return pages
    }

    /// Single chart: the title. Songbook: "Set list" (or "Contents"), then each song,
    /// nested under its break heading when the set has breaks.
    static func outline(_ job: PrintJob, firstPages: [Int]) -> [PrintOutlineEntry] {
        guard let contents = job.contents else {
            return [PrintOutlineEntry(title: job.title, page: 0)]
        }
        var entries = [PrintOutlineEntry(
            title: job.target == .selection ? "Contents" : "Set list",
            page: 0,
        )]
        let hasBreaks = contents.rows.contains { row in
            if case .breakHeading = row {
                return true
            }
            return false
        }
        for row in contents.rows {
            switch row {
            case let .song(song):
                guard firstPages.indices.contains(song.song) else { continue }
                let entry = PrintOutlineEntry(
                    title: job.songs[song.song].outlineTitle,
                    page: firstPages[song.song],
                )
                if hasBreaks, entries.count > 1 {
                    entries[entries.count - 1].children.append(entry)
                } else {
                    entries.append(entry)
                }
            case let .breakHeading(title, _, _):
                entries.append(PrintOutlineEntry(title: title, page: 0))
            case .missing:
                continue
            }
        }
        // A heading points at its first song's page; one with no songs stays on the list.
        return entries.map { entry in
            var entry = entry
            if let first = entry.children.first {
                entry.page = first.page
            }
            return entry
        }
    }

    static func metadata(_ job: PrintJob) -> PrintMetadata {
        var keywords = job.isSongbook ? ["songbook"] : job.tags
        if let keyword = job.options.part.keyword {
            keywords.append(keyword)
        }
        return PrintMetadata(
            title: job.title,
            author: job.isSongbook ? nil : job.author,
            subject: job.isSongbook ? job.subject : nil,
            creator: "Segue",
            keywords: keywords,
            date: job.date,
        )
    }
}
