// Owner: P9-1 (spec 5.10, 9). A song's pages with their headers, medley member anchors
// (R193: members flow on, each later one opening with the stage's member header), and the
// set list rows' link targets.

import LiveLayout

extension PrintAssembler {
    /// Where a medley member's inline header sits: its page and its distance from the
    /// paper's top edge (nil for the first member, which opens the medley's first page).
    struct Anchor: Hashable {
        var page: Int
        var top: Double?
    }

    /// Each member's anchor in a medley laid out on `plans` (page 0 is `firstPage`).
    static func memberAnchors(_ plans: [LayoutPlan], firstPage: Int, header: PrintHeader)
        -> [Int: Anchor]
    {
        var anchors: [Int: Anchor] = [0: Anchor(page: firstPage, top: nil)]
        for (offset, plan) in plans.enumerated() {
            let body = PrintPageMetrics.top + (offset == 0
                ? PrintPageMetrics.headerHeight(header)
                : PrintPageMetrics.continuationHeight)
            for block in plan.columns.flatMap(\.blocks) where block.memberHeader != nil {
                guard anchors[block.segment] == nil else { continue }
                anchors[block.segment] = Anchor(
                    page: firstPage + offset,
                    top: body + block.y + block.memberHeaderTop,
                )
            }
        }
        return anchors
    }

    /// The member at the top of a page: its first column's first block.
    static func topSegment(_ plan: LayoutPlan) -> Int? {
        plan.columns.first?.blocks.first?.segment
    }

    /// A song's pages; a medley's continuation page names the member at its top (spec 9).
    static func songPages(
        _ song: LaidSong,
        plans: [LayoutPlan],
        members: [PrintMember],
        at place: (song: Int, firstPage: Int),
        footer: (Int) -> PrintFooter,
    ) -> [PrintPage] {
        plans.enumerated().map { offset, plan in
            var header = song.header
            if offset > 0, let segment = topSegment(plan), members.indices.contains(segment) {
                header.title = members[segment].title
                header.slotLabel = members[segment].slotLabel
            }
            return .song(SongPage(
                header: header,
                isFirst: offset == 0,
                plan: plan,
                extras: song.paged.extras.filter { $0.page == offset },
                diagrams: song.diagrams,
                footer: footer(place.firstPage + offset),
                song: place.song,
            ))
        }
    }

    /// A set list page with its footer and each row's link target: a song's or medley's
    /// first page, a medley member's inline header.
    static func targeted(
        _ page: SetListPage,
        footer: PrintFooter,
        firstPages: [Int],
        anchors: [Int: [Int: Anchor]],
    ) -> SetListPage {
        var page = page
        page.footer = footer
        page.rows = page.rows.map { placed in
            var placed = placed
            switch placed.row {
            case let .medley(song), let .song(song):
                guard firstPages.indices.contains(song.song) else { break }
                placed.target = firstPages[song.song]
                if let member = song.member, let anchor = anchors[song.song]?[member] {
                    placed.target = anchor.page
                    placed.targetTop = anchor.top
                }
            case .breakHeading, .missing:
                break
            }
            return placed
        }
        return page
    }
}
