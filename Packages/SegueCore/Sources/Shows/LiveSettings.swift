// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit C (persistence in UI).

import Foundation
import Library
import Support

/// A pre-show checklist row.
public enum ChecklistItem: String, Sendable, Hashable, Codable, CaseIterable {
    /// "Focus on": ticks only when the start Shortcut was observed to finish, or when the
    /// performer pressed Done (R18, R35). Hidden while no start Shortcut is set.
    case focus
    /// "Charger connected": read from the IOKit power source.
    case charger
    /// "Screen brightness up": a reminder; the user ticks it.
    case brightness
    /// "Singer view is on: the stage shows lyrics only" with Show Chords (P9-2 6.10): shown
    /// only while singer view is on.
    case singerView

    /// The rows every Segue before P9-2 knows. `LiveSettings` writes the user's hidden rows
    /// among these under the old key, so an older build reading the file keeps every setting.
    static let legacy: Set<Self> = [.focus, .charger, .brightness]
}

/// App-level live-mode settings (Settings > Live), not per song. Stored in UserDefaults by
/// the UI; a plain value here so the layout engine and tests share the defaults.
public struct LiveSettings: Sendable, Hashable, Codable {
    /// Default minimum lyric size in points (brand.md: 22pt).
    public static let defaultMinLyricSize: Double = 22
    /// The range Settings offers for `minLyricSize`.
    public static let minLyricSizeRange: ClosedRange<Double> = 16 ... 48
    /// Suggested Shortcut names, shown by the Settings guide and as text field prompts only.
    /// The Shortcuts are off until the user sets them up (R18): nothing is stored by default.
    public static let suggestedStartShortcut = "Gig Mode On"
    public static let suggestedEndShortcut = "Gig Mode Off"

    /// `live.minLyricFont`: auto-fit never goes below this; the song scrolls instead.
    public var minLyricSize: Double
    /// Shortcut run on show start (nil or blank = none).
    public var startShortcut: String?
    /// Shortcut run on show end (nil or blank = none).
    public var endShortcut: String?
    /// Checklist rows the user dismissed with "Don't show again".
    public var hiddenChecklistItems: Set<ChecklistItem>
    /// The default column count on stage (Settings > Live): nil = auto-fit chooses, else a
    /// fixed count in `columnRange`. A song's own choice wins (`columns(for:)`).
    public var defaultColumns: Int?

    /// Singer view on stage (P9-2 6.1, `V`): lyrics only, chords hidden. Remembered across
    /// shows; separate from the library and editor preview's own toggle.
    public var singerView: Bool
    /// Cmd +/- in singer view (P9-2 6.5): one zoom for every song while singer view is on,
    /// never a song's own `LivePrefs.zoom`. Clamped to `singerZoomRange` on read.
    public var singerZoom: Double
    /// The display the Singer Screen last opened on (P9-2c 6.13), by its localized name; it
    /// is used again whenever a display of that name is connected.
    public var singerScreenDisplay: String?
    /// Keys this build does not model, kept for the next save
    /// (docs/architecture/data-compatibility.md).
    public var unknown: UnknownFields = .empty

    /// The column counts a song or the default can fix.
    public static let columnRange: ClosedRange<Int> = 1 ... 3
    /// The range of `singerZoom` (the stage's zoom range).
    public static let singerZoomRange: ClosedRange<Double> = 0.5 ... 3.0

    public init(
        minLyricSize: Double = Self.defaultMinLyricSize,
        startShortcut: String? = nil,
        endShortcut: String? = nil,
        hiddenChecklistItems: Set<ChecklistItem> = [],
        defaultColumns: Int? = nil,
        singerView: Bool = false,
        singerZoom: Double = 1,
        singerScreenDisplay: String? = nil,
    ) {
        self.minLyricSize = minLyricSize
        self.startShortcut = startShortcut
        self.endShortcut = endShortcut
        self.hiddenChecklistItems = hiddenChecklistItems
        self.defaultColumns = defaultColumns
        self.singerView = singerView
        self.singerZoom = singerZoom
        self.singerScreenDisplay = singerScreenDisplay
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case minLyricSize
        case startShortcut
        case endShortcut
        case hiddenChecklistItems
        case defaultColumns
        case singerView
        case singerZoom
        case singerScreenDisplay
        /// Every hidden row, the newer ones included (P9-2); `hiddenChecklistItems` keeps
        /// only the rows an older Segue knows, which decodes that key strictly.
        case hiddenChecklistRows
    }

    /// Lenient (P9-2 section 11): every field falls back to its default when missing or
    /// unreadable, unknown checklist rows are dropped, so one new or odd key never resets
    /// the user's Live settings.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys) -> T? {
            try? container.decodeIfPresent(T.self, forKey: key)
        }
        let rows: [String] = (value(.hiddenChecklistItems) ?? [])
            + (value(.hiddenChecklistRows) ?? [])
        self.init(
            minLyricSize: value(.minLyricSize) ?? Self.defaultMinLyricSize,
            startShortcut: value(.startShortcut),
            endShortcut: value(.endShortcut),
            hiddenChecklistItems: Set(rows.compactMap(ChecklistItem.init(rawValue:))),
            defaultColumns: value(.defaultColumns),
            singerView: value(.singerView) ?? false,
            singerZoom: (value(.singerZoom) as Double?).map(Self.clampedSingerZoom) ?? 1,
            singerScreenDisplay: value(.singerScreenDisplay),
        )
        unknown = UnknownFields(from: decoder, known: Set(CodingKeys.allCases.map(\.stringValue)))
    }

    public func encode(to encoder: any Encoder) throws {
        try unknown.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(minLyricSize, forKey: .minLyricSize)
        try container.encodeIfPresent(startShortcut, forKey: .startShortcut)
        try container.encodeIfPresent(endShortcut, forKey: .endShortcut)
        let hidden = hiddenChecklistItems.map(\.rawValue).sorted()
        try container.encode(
            hidden
                .filter { ChecklistItem(rawValue: $0).map(ChecklistItem.legacy.contains) == true },
            forKey: .hiddenChecklistItems,
        )
        try container.encode(hidden, forKey: .hiddenChecklistRows)
        try container.encodeIfPresent(defaultColumns, forKey: .defaultColumns)
        try container.encode(singerView, forKey: .singerView)
        try container.encode(singerZoom, forKey: .singerZoom)
        try container.encodeIfPresent(singerScreenDisplay, forKey: .singerScreenDisplay)
    }

    /// `zoom` within `singerZoomRange`, rounded to a hundredth; 1 when not finite.
    public static func clampedSingerZoom(_ zoom: Double) -> Double {
        guard zoom.isFinite else { return 1 }
        let clamped = min(max(zoom, singerZoomRange.lowerBound), singerZoomRange.upperBound)
        return (clamped * 100).rounded() / 100
    }

    /// The column count a song is laid out with (decisions.md, "Columns"): the song's own
    /// choice (`LivePrefs.columns`, from the stage's C key or the editor), else this default,
    /// else nil for auto-fit. Out-of-range counts are clamped.
    public func columns(for prefs: LivePrefs) -> Int? {
        (prefs.columns ?? defaultColumns).map { count in
            min(max(count, Self.columnRange.lowerBound), Self.columnRange.upperBound)
        }
    }
}
