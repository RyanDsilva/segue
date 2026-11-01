import Foundation

// PDF export analytics (P9-1 spec section 11, R181): row 31 of the closed vocabulary. Enums,
// Bools and buckets only: no titles, names, venues, file names or paths.

/// Row 31: `Segue.Export.pdf`, one per PDF preview sheet closed.
public struct PDFExportSummary: Sendable, Hashable {
    public var target: PDFExportTarget
    public var part: PDFExportPart
    public var paper: PDFExportPaper
    public var size: PDFExportSize
    public var columns: PDFExportColumns
    public var repeats: PDFExportRepeats
    public var fitOnePage: Bool
    public var sectionMap: Bool
    public var stageNotes: Bool
    public var diagrams: PDFExportDiagrams
    /// What the PDF drew for saved fills.
    public var fills: PDFExportFills
    /// The sheet's outcomes.
    public var saved: Bool
    public var printed: Bool
    public var shared: Bool
    public var songs: SmallBucket
    public var pages: SmallBucket
    public var medleys: SmallBucket
    public var optionChanges: SmallBucket
    /// The sheet's first render, to watch the low-spec budget (spec 7.3).
    public var renderTime: RenderTimeBucket

    public init(
        target: PDFExportTarget,
        part: PDFExportPart,
        paper: PDFExportPaper,
        size: PDFExportSize,
        columns: PDFExportColumns,
        repeats: PDFExportRepeats,
        fitOnePage: Bool,
        sectionMap: Bool,
        stageNotes: Bool,
        diagrams: PDFExportDiagrams,
        fills: PDFExportFills,
        saved: Bool,
        printed: Bool,
        shared: Bool,
        songs: SmallBucket,
        pages: SmallBucket,
        medleys: SmallBucket,
        optionChanges: SmallBucket,
        renderTime: RenderTimeBucket,
    ) {
        self.target = target
        self.part = part
        self.paper = paper
        self.size = size
        self.columns = columns
        self.repeats = repeats
        self.fitOnePage = fitOnePage
        self.sectionMap = sectionMap
        self.stageNotes = stageNotes
        self.diagrams = diagrams
        self.fills = fills
        self.saved = saved
        self.printed = printed
        self.shared = shared
        self.songs = songs
        self.pages = pages
        self.medleys = medleys
        self.optionChanges = optionChanges
        self.renderTime = renderTime
    }

    var params: [String: String] {
        [
            "segue.target": target.rawValue,
            "segue.part": part.rawValue,
            "segue.paper": paper.rawValue,
            "segue.size": size.rawValue,
            "segue.columns": columns.rawValue,
            "segue.repeats": repeats.rawValue,
            "segue.fitOnePage": String(fitOnePage),
            "segue.sectionMap": String(sectionMap),
            "segue.stageNotes": String(stageNotes),
            "segue.diagrams": diagrams.rawValue,
            "segue.fills": fills.rawValue,
            "segue.saved": String(saved),
            "segue.printed": String(printed),
            "segue.shared": String(shared),
            "segue.songs": songs.rawValue,
            "segue.pages": pages.rawValue,
            "segue.medleys": medleys.rawValue,
            "segue.optionChanges": optionChanges.rawValue,
            "segue.renderTime": renderTime.rawValue,
        ]
    }
}

public enum PDFExportTarget: String, Sendable, CaseIterable {
    case song
    case slot
    case setlist
    case selection
}

public enum PDFExportPart: String, Sendable, CaseIterable {
    case chords
    case bass
    case lyrics
}

public enum PDFExportPaper: String, Sendable, CaseIterable {
    case a4
    case letter
}

public enum PDFExportSize: String, Sendable, CaseIterable {
    case small
    case medium
    case large
}

public enum PDFExportColumns: String, Sendable, CaseIterable {
    case auto
    case one
    case two
}

public enum PDFExportRepeats: String, Sendable, CaseIterable {
    case full
    case compact
}

/// Raw value `none` is the spec's value; the case name avoids clashing with `Optional.none`.
public enum PDFExportDiagrams: String, Sendable, CaseIterable {
    case asSong
    case all
    case noDiagrams = "none"
    case notApplicable
}

/// Raw value `none` is the spec's value; the case name avoids clashing with `Optional.none`.
public enum PDFExportFills: String, Sendable, CaseIterable {
    case noFills = "none"
    case names
    case tab
}

/// How long the sheet's first render took.
public enum RenderTimeBucket: String, Sendable, CaseIterable {
    case under250ms
    case under500ms
    case under1s
    case under2s
    case over2s

    public init(_ duration: Duration) {
        let milliseconds = Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1e15
        self = switch milliseconds {
        case ..<250: .under250ms
        case ..<500: .under500ms
        case ..<1000: .under1s
        case ..<2000: .under2s
        default: .over2s
        }
    }
}
