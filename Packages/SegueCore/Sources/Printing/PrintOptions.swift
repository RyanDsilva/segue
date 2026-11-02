// Owner: P9-1 (spec 6.2). The PDF preview's options: what one export prints and how.

import LiveLayout

/// Which part one export prints (spec decision 6): chords, bass notes or lyrics (P9-2's
/// singer view, spec section 8).
public enum PrintPart: String, Sendable, Hashable, Codable, CaseIterable {
    case chords
    case bass
    case lyrics

    /// The file name suffix ("Harbour Lights (Bass).pdf").
    public var fileSuffix: String? {
        switch self {
        case .chords: nil
        case .bass: "Bass"
        case .lyrics: "Lyrics"
        }
    }

    /// The PDF keyword the part adds.
    public var keyword: String? {
        switch self {
        case .chords: nil
        case .bass: "bass chart"
        case .lyrics: "lyrics"
        }
    }
}

/// Paper, portrait (spec 5.1).
public enum PrintPaper: String, Sendable, Hashable, Codable, CaseIterable {
    case a4
    case letter

    /// Points.
    public var size: LayoutSize {
        switch self {
        case .a4: LayoutSize(width: 595, height: 842)
        case .letter: LayoutSize(width: 612, height: 792)
        }
    }

    /// The locale's default: US Letter where the measurement system is US, else A4.
    public static func locale(usesUSMeasurement: Bool) -> Self {
        usesUSMeasurement ? .letter : .a4
    }
}

/// The fixed lyric size (spec 5.1): chords print at 0.82 of it.
public enum PrintTextSize: String, Sendable, Hashable, Codable, CaseIterable {
    case small
    case medium
    case large

    public var lyricSize: Double {
        switch self {
        case .small: 10
        case .medium: 11.5
        case .large: 13
        }
    }
}

public enum PrintColumns: String, Sendable, Hashable, Codable, CaseIterable {
    case auto
    case one
    case two

    /// nil for Auto.
    public var count: Int? {
        switch self {
        case .auto: nil
        case .one: 1
        case .two: 2
        }
    }
}

/// Spec 5.6 (R158 Q9): every repeat written out by default.
public enum PrintRepeats: String, Sendable, Hashable, Codable, CaseIterable {
    case writtenOut
    case compact
}

/// Spec 5.8: each song's own diagram toggle, every song, or none.
public enum PrintDiagrams: String, Sendable, Hashable, Codable, CaseIterable {
    case asSong
    case all
    case off = "none"
}

/// Everything the preview sheet's options say (spec 6.2).
public struct PrintOptions: Sendable, Hashable {
    public var part: PrintPart
    public var paper: PrintPaper
    /// The Chords and Bass notes parts' text size.
    public var size: PrintTextSize
    /// The Lyrics part's own text size, Large by default (spec 8.3).
    public var lyricsSize: PrintTextSize
    public var columns: PrintColumns
    public var fitOnePage: Bool
    public var repeats: PrintRepeats
    public var sectionMap: Bool
    public var diagrams: PrintDiagrams
    /// The Bass part's fills as mini tabs; defaults to the user's stage setting.
    public var fillsAsTab: Bool
    /// Sidecar notes, cues and the slot note: off every time (resolved decision 3).
    public var stageNotes: Bool

    public init(
        part: PrintPart = .chords,
        paper: PrintPaper = .a4,
        size: PrintTextSize = .medium,
        lyricsSize: PrintTextSize = .large,
        columns: PrintColumns = .auto,
        fitOnePage: Bool = false,
        repeats: PrintRepeats = .writtenOut,
        sectionMap: Bool = true,
        diagrams: PrintDiagrams = .asSong,
        fillsAsTab: Bool = false,
        stageNotes: Bool = false,
    ) {
        self.part = part
        self.paper = paper
        self.size = size
        self.lyricsSize = lyricsSize
        self.columns = columns
        self.fitOnePage = fitOnePage
        self.repeats = repeats
        self.sectionMap = sectionMap
        self.diagrams = diagrams
        self.fillsAsTab = fillsAsTab
        self.stageNotes = stageNotes
    }

    /// The text size this part prints at: the Lyrics part keeps its own (Large unless
    /// changed), so a lyric sheet never inherits a chart's smaller size.
    public var textSize: PrintTextSize {
        get { part == .lyrics ? lyricsSize : size }
        set {
            if part == .lyrics {
                lyricsSize = newValue
            } else {
                size = newValue
            }
        }
    }

    /// The options remembered between exports (spec 6.2 "Remembered").
    public var remembered: RememberedPrintOptions {
        RememberedPrintOptions(
            paper: paper,
            size: size,
            lyricsSize: lyricsSize,
            columns: columns,
            fitOnePage: fitOnePage,
            repeats: repeats,
            sectionMap: sectionMap,
            diagrams: diagrams,
        )
    }

    /// The options for a new sheet: the remembered values, the part following the user's
    /// view, the fills setting the user's, stage notes off.
    public init(remembered: RememberedPrintOptions, part: PrintPart, fillsAsTab: Bool) {
        self.init(
            part: part,
            paper: remembered.paper,
            size: remembered.size,
            lyricsSize: remembered.lyricsSize,
            columns: remembered.columns,
            fitOnePage: remembered.fitOnePage,
            repeats: remembered.repeats,
            sectionMap: remembered.sectionMap,
            diagrams: remembered.diagrams,
            fillsAsTab: fillsAsTab,
        )
    }
}

/// The remembered subset, stored under `export.pdf.options`. Decoding is lenient: a missing
/// or unknown value falls back to its default, never failing the whole record.
public struct RememberedPrintOptions: Sendable, Hashable, Codable {
    public var paper: PrintPaper
    public var size: PrintTextSize
    public var lyricsSize: PrintTextSize
    public var columns: PrintColumns
    public var fitOnePage: Bool
    public var repeats: PrintRepeats
    public var sectionMap: Bool
    public var diagrams: PrintDiagrams

    public init(
        paper: PrintPaper,
        size: PrintTextSize = .medium,
        lyricsSize: PrintTextSize = .large,
        columns: PrintColumns = .auto,
        fitOnePage: Bool = false,
        repeats: PrintRepeats = .writtenOut,
        sectionMap: Bool = true,
        diagrams: PrintDiagrams = .asSong,
    ) {
        self.paper = paper
        self.size = size
        self.lyricsSize = lyricsSize
        self.columns = columns
        self.fitOnePage = fitOnePage
        self.repeats = repeats
        self.sectionMap = sectionMap
        self.diagrams = diagrams
    }

    /// The defaults with `paper` from the locale.
    public static func defaults(paper: PrintPaper) -> Self {
        Self(paper: paper)
    }

    private enum CodingKeys: String, CodingKey {
        case paper
        case size
        case lyricsSize
        case columns
        case fitOnePage
        case repeats
        case sectionMap
        case diagrams
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        self.init(
            paper: value(.paper, .a4),
            size: value(.size, .medium),
            lyricsSize: value(.lyricsSize, .large),
            columns: value(.columns, .auto),
            fitOnePage: value(.fitOnePage, false),
            repeats: value(.repeats, .writtenOut),
            sectionMap: value(.sectionMap, true),
            diagrams: value(.diagrams, .asSong),
        )
    }
}
