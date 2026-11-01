// Owner: P9-1 (spec 5.3). The print paginator beside `FitSearch`: the same measured passes,
// section layout and column packer as the stage, at a fixed lyric size, broken into pages.

import Editing

/// The body of a printed page: the first page's is shorter by the song header.
public struct PageGeometry: Sendable, Hashable {
    public var firstBody: LayoutSize
    public var laterBody: LayoutSize
    /// Forced column count (1 or 2); nil = Auto: 2 when every lyric line fits a column
    /// without wrapping at the chosen size, else 1 (spec 5.1).
    public var columns: Int?

    public init(firstBody: LayoutSize, laterBody: LayoutSize, columns: Int? = nil) {
        self.firstBody = firstBody
        self.laterBody = laterBody
        self.columns = columns
    }
}

/// A block kept whole after a song's last section (the chord diagrams, spec 5.8), as placed:
/// the full body width, on `page` at `y` from the body's top.
public struct PlacedExtra: Sendable, Hashable {
    public var index: Int
    public var page: Int
    public var y: Double
    public var height: Double

    public init(index: Int, page: Int, y: Double, height: Double) {
        self.index = index
        self.page = page
        self.y = y
        self.height = height
    }
}

/// One song broken into pages.
public struct PagedSong: Sendable {
    /// One plan per page: its columns in reading order, `fit == .fits`, no page stops, and
    /// the passes whose first block starts on that page. A page may hold only extras.
    public var pages: [LayoutPlan]
    public var extras: [PlacedExtra]
    /// The column count used on every page.
    public var columns: Int
    /// Compact repeats' reference rows whose target starts on another page.
    var references: [PageReference]

    /// Every shown pass once, in played order (the section map line, spec 5.5).
    public var passes: [PlanPass] {
        pages.flatMap(\.passes)
    }

    /// The pages with each reference row naming its target's document page ("as Chorus 1
    /// on page 2"), the song's first page being `firstPage`.
    public func numbered(firstPage: Int) -> [LayoutPlan] {
        var pages = pages
        for reference in references {
            let page = firstPage + reference.targetPage
            let text = CompactRepeats.onPage(reference.prefix, page: page)
            for column in pages[reference.page].columns.indices {
                for block in pages[reference.page].columns[column].blocks.indices
                    where pages[reference.page].columns[column].blocks[block].id == reference.pass
                {
                    guard case var .rows(rows) = pages[reference.page].columns[column]
                        .blocks[block].content else { continue }
                    for row in rows.indices where rows[row].kind == .moreLines {
                        for run in rows[row].text.indices {
                            rows[row].text[run].text = text
                        }
                    }
                    pages[reference.page].columns[column].blocks[block].content = .rows(rows)
                }
            }
        }
        return pages
    }
}

/// A reference row on `page` (pass `pass`) whose target starts on `targetPage`.
struct PageReference {
    var page: Int
    var pass: Int
    var targetPage: Int
    var prefix: String
}

public enum PageLayout {
    /// Lays `request` out at its style's `maxLyricSize` (the print style's chosen size) and
    /// breaks it into pages (spec 5.3): a unit is never split, a section moves whole when it
    /// fits an empty column, an over-tall section splits between units (at a stanza break in
    /// its latter half when there is one) leaving and carrying at least two lines, a fill's
    /// tab stays with its line, notes come first, and `extras` (heights of blocks kept whole)
    /// follow the last section at the full body width. With `compactRepeats`, exact repeats
    /// print as reference rows (5.6).
    public static func paginate(
        _ request: LayoutRequest,
        page: PageGeometry,
        extras: [Double] = [],
        compactRepeats: Bool = false,
        metrics: any TextMeasuring,
    ) -> PagedSong {
        var request = request
        request.viewport = page.firstBody
        request.zoom = 1
        let measurer = Measurer(metrics: metrics)
        var song = SongPreparation(request: request, measurer: measurer).measure()
        var compacted: [CompactReference] = []
        if compactRepeats {
            let applied = CompactRepeats.apply(song.sections, measurer: measurer)
            song.sections = applied.sections
            compacted = applied.references
        }
        let search = FitSearch(request: request, song: song, measurer: measurer)
        let style = request.style
        let size = max(1, style.maxLyricSize)
        let columns = columnCount(page.columns, search: search, size: size)
        let sections = search.laid(size: size, columns: columns)
        var packer = search.packer(sections, size: size)
        packer.moveWholeFirst = true
        packer.minimumUnitsAtSplit = 2
        let pages = packer.paginate(
            columns: columns,
            first: page.firstBody.height,
            later: page.laterBody.height,
        )
        var plans = pages.enumerated().map { index, placements in
            plan(
                placements,
                viewport: index == 0 ? page.firstBody : page.laterBody,
                request: request,
                search: search,
                packer: packer,
                sections: sections,
                columns: columns,
            )
        }
        let placedExtras = place(extras, on: &plans, page: page, gap: packer.gap)
        return PagedSong(
            pages: plans,
            extras: placedExtras,
            columns: columns,
            references: references(compacted, in: plans),
        )
    }

    // swiftlint:disable:next function_parameter_count
    private static func plan(
        _ placements: [[Placement]],
        viewport: LayoutSize,
        request: LayoutRequest,
        search: FitSearch,
        packer: ColumnPacker,
        sections: LaidSections,
        columns: Int,
    ) -> LayoutPlan {
        var pageRequest = request
        pageRequest.viewport = viewport
        let size = max(1, request.style.maxLyricSize)
        var plan = PlanAssembly(
            candidate: Candidate(
                size: size,
                columns: columns,
                sections: sections,
                packing: Packing(columns: placements),
            ),
            packer: packer,
            request: pageRequest,
            columnWidth: search.columnWidth(columns),
            gutterWidth: search.gutterWidth,
            lineCount: search.song.lineCount,
        ).plan(fit: .fits)
        plan.pageStops = []
        let starts = Set(placements.joined().filter { $0.part == 0 }
            .map { sections[$0.section].id })
        plan.passes = plan.passes.filter { starts.contains($0.index) }
        return plan
    }

    /// Auto: 2 when two columns are allowed and wide enough and no lyric line wraps in them.
    static func columnCount(_ forced: Int?, search: FitSearch, size: Double) -> Int {
        let style = search.request.style
        let most = max(1, min(style.maxColumns, 2))
        if let forced {
            return min(max(forced, 1), most)
        }
        guard most >= 2, search.columnWidth(2) >= style.minColumnWidth else { return 1 }
        let two = search.laid(size: size, columns: 2)
        return two.indices.contains { two[$0].wrapped } ? 1 : 2
    }

    /// Each extra after the content of the last page, kept whole: on a new page when it does
    /// not fit what is left.
    private static func place(
        _ extras: [Double],
        on plans: inout [LayoutPlan],
        page: PageGeometry,
        gap: Double,
    ) -> [PlacedExtra] {
        var placed: [PlacedExtra] = []
        guard !extras.isEmpty else { return placed }
        var bottom = plans.last.map(\.contentHeight) ?? 0
        for (index, height) in extras.enumerated() {
            let capacity = plans.count <= 1 ? page.firstBody.height : page.laterBody.height
            var y = bottom > 0 ? bottom + gap : 0
            if y + height > capacity, bottom > 0, var empty = plans.last {
                empty.columns = []
                empty.passes = []
                empty.contentHeight = 0
                empty.viewport = page.laterBody
                plans.append(empty)
                y = 0
            }
            placed.append(PlacedExtra(index: index, page: plans.count - 1, y: y, height: height))
            bottom = y + height
        }
        return placed
    }

    private static func references(
        _ compacted: [CompactReference],
        in plans: [LayoutPlan],
    ) -> [PageReference] {
        func page(of pass: Int) -> Int? {
            plans.firstIndex { plan in plan.passes.contains { $0.index == pass } }
        }
        return compacted.compactMap { reference in
            guard let at = page(of: reference.pass), let target = page(of: reference.target),
                  at != target
            else { return nil }
            return PageReference(
                page: at,
                pass: reference.pass,
                targetPage: target,
                prefix: reference.prefix,
            )
        }
    }
}
