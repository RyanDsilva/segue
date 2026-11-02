// Owner: P9-1 (spec 7.1). The print document: every page positioned and numbered, the
// outline, the metadata and the file name. SegueUI draws it; nothing here touches a view.

import Foundation
import LiveLayout

/// A song's header lines (spec 5.2), already worded by the caller.
public struct PrintHeader: Sendable, Hashable {
    public var title: String
    /// "Vishal Dadlani, Shekhar Ravjiani · Kalank".
    public var credits: String?
    /// "G, capo 2, 96" (the sounding key and no capo in the bass part).
    public var performance: String?
    /// "Sounding A major: A B C# D E F# G#" (bass part).
    public var scale: String?
    /// "Arrangement out of date: printed as written".
    public var notice: String?
    /// "4 of 18" in a setlist songbook; nil for a single chart or a selection.
    public var slotLabel: String?
    /// The section map line (spec 5.5), at most two lines; set by the assembler.
    public var mapLines: [String]

    public init(
        title: String,
        credits: String? = nil,
        performance: String? = nil,
        scale: String? = nil,
        notice: String? = nil,
        slotLabel: String? = nil,
        mapLines: [String] = [],
    ) {
        self.title = title
        self.credits = credits
        self.performance = performance
        self.scale = scale
        self.notice = notice
        self.slotLabel = slotLabel
        self.mapLines = mapLines
    }

    /// The continuation pages' one line: "Harbour Lights (cont.)".
    public var continuationTitle: String {
        "\(title) (cont.)"
    }
}

/// "Friday Set" on the left (songbooks), "Page 7 of 31" on the right.
public struct PrintFooter: Sendable, Hashable {
    public var left: String?
    public var right: String

    public init(left: String?, right: String) {
        self.left = left
        self.right = right
    }
}

/// The chord diagrams block after a song's last section (spec 5.8): `count` cells of `cell`
/// size, wrapped into rows across the body width with `spacing` between cells.
public struct PrintDiagramBlock: Sendable, Hashable {
    public var count: Int
    public var cell: LayoutSize
    public var spacing: Double

    public init(count: Int, cell: LayoutSize, spacing: Double) {
        self.count = count
        self.cell = cell
        self.spacing = spacing
    }

    public func perRow(width: Double) -> Int {
        max(1, Int(((width + spacing) / (cell.width + spacing)).rounded(.down)))
    }

    public func height(width: Double) -> Double {
        let rows = (count + perRow(width: width) - 1) / perRow(width: width)
        return Double(rows) * cell.height + Double(max(rows - 1, 0)) * spacing
    }
}

/// One member of a printed medley, by its segment in the medley's request (P9-1 spec 9,
/// R193): what a continuation page whose top is in this member says.
public struct PrintMember: Sendable, Hashable {
    /// "Kesariya".
    public var title: String
    /// "Medley 5 · 2 of 3".
    public var slotLabel: String?

    public init(title: String, slotLabel: String?) {
        self.title = title
        self.slotLabel = slotLabel
    }
}

/// One song (a library song, a slot or a selected song) ready to print: its layout request
/// built the stage's way, its header and its optional diagrams. A medley slot is one print
/// song whose request has a segment per member (P9-3 9.1), its members flowing on with no
/// page break (R178).
public struct PrintSong: Sendable {
    public var request: LayoutRequest
    public var header: PrintHeader
    public var diagrams: PrintDiagramBlock?
    /// The outline entry's title: "3. Harbour Lights" in a setlist songbook.
    public var outlineTitle: String
    /// A medley's members, one per segment; empty for a song.
    public var members: [PrintMember]

    public init(
        request: LayoutRequest,
        header: PrintHeader,
        diagrams: PrintDiagramBlock? = nil,
        outlineTitle: String? = nil,
        members: [PrintMember] = [],
    ) {
        self.request = request
        self.header = header
        self.diagrams = diagrams
        self.outlineTitle = outlineTitle ?? header.title
        self.members = members
    }
}

/// A row of the set list page (spec 5.10, R187 "taped" direction).
public enum SetListRow: Sendable, Hashable {
    case song(SetListSong)
    /// A break: its heading ("Set 2") and part total, after the intermission length
    /// ("Interval 20:00") when the break has one.
    case breakHeading(title: String, total: String?, interval: String?)
    /// A slot whose song is not in the library ("5b" for a medley member).
    case missing(number: String)
    /// A medley slot (P9-1 spec 9): "5  Medley: Tujh Mein Rab / Kesariya / Tum Hi Ho" with
    /// the medley's total, linking to its first page; its members follow as `.song` rows
    /// with `member` set, numbered "5a", "5b".
    case medley(SetListSong)
}

public struct SetListSong: Sendable, Hashable {
    /// "4" (a selection numbers 1...N).
    public var number: String
    public var title: String
    public var credits: String?
    /// "A, capo 2" (no tempo); the sounding key in the bass part.
    public var key: String?
    /// "3:40", "~3:40", "--:--"; nil in a selection (no times).
    public var time: String?
    /// Index into the job's songs.
    public var song: Int
    /// A medley member's segment in its medley's request: the row is indented and links to
    /// the member's inline header; nil for a song or a medley row.
    public var member: Int?

    public init(
        number: String,
        title: String,
        credits: String? = nil,
        key: String? = nil,
        time: String? = nil,
        song: Int,
        member: Int? = nil,
    ) {
        self.number = number
        self.title = title
        self.credits = credits
        self.key = key
        self.time = time
        self.song = song
        self.member = member
    }
}

/// A set list row as placed: `y` from the body's top, and the page index it links to.
public struct PlacedSetListRow: Sendable, Hashable {
    public var row: SetListRow
    public var y: Double
    public var height: Double
    public var target: Int?
    /// Where on `target` the link lands, from the paper's top edge; nil = the page top (a
    /// medley member's inline header shares its page, spec 9).
    public var targetTop: Double?
}

public struct SetListHead: Sendable, Hashable {
    /// "Friday Set", "Songbook", or "Friday Set (cont.)".
    public var title: String
    /// "The Anchor · Fri 23 Oct 2026 · 18 songs · 1:12:30"; nil on a continuation page.
    public var line: String?
    public var isContinuation: Bool
}

public struct SetListPage: Sendable, Hashable {
    public var head: SetListHead
    public var rows: [PlacedSetListRow]
    /// Times and totals print (a setlist, not a selection).
    public var showsTimes: Bool
    public var footer: PrintFooter
}

public struct SongPage: Sendable, Hashable {
    public var header: PrintHeader
    public var isFirst: Bool
    public var plan: LayoutPlan
    /// The extras on this page (the diagrams block), at the full body width.
    public var extras: [PlacedExtra]
    public var diagrams: PrintDiagramBlock?
    public var footer: PrintFooter
    /// Index into the job's songs.
    public var song: Int
}

public enum PrintPage: Sendable, Hashable {
    case setList(SetListPage)
    case song(SongPage)
}

public struct PrintOutlineEntry: Sendable, Hashable {
    public var title: String
    /// 0-based page index.
    public var page: Int
    /// From the paper's top edge; nil = the page top (a medley member's header, spec 9).
    public var top: Double?
    public var children: [Self]

    public init(title: String, page: Int, top: Double? = nil, children: [Self] = []) {
        self.title = title
        self.page = page
        self.top = top
        self.children = children
    }
}

public struct PrintMetadata: Sendable, Hashable {
    public var title: String
    public var author: String?
    public var subject: String?
    public var creator: String
    public var keywords: [String]
    public var date: Date
}

public struct PrintDocument: Sendable, Hashable {
    public var pages: [PrintPage]
    public var outline: [PrintOutlineEntry]
    public var metadata: PrintMetadata
    public var fileName: String
    public var paper: PrintPaper
    /// Fit on one page asked for but impossible at the floor size (spec 5.9).
    public var fitFailed: Bool

    /// Pages of each song, by song index.
    public var songPageCounts: [Int: Int] {
        var counts: [Int: Int] = [:]
        for case let .song(page) in pages {
            counts[page.song, default: 0] += 1
        }
        return counts
    }
}
