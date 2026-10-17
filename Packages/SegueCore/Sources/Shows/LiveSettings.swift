// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit C (persistence in UI).

import Foundation
import Library

/// A pre-show checklist row.
public enum ChecklistItem: String, Sendable, Hashable, Codable, CaseIterable {
    /// "Focus on": ticked automatically only when the start Shortcut ran without error.
    case focus
    /// "Charger connected": read from the IOKit power source.
    case charger
    /// "Screen brightness up": a reminder; the user ticks it.
    case brightness
}

/// App-level live-mode settings (Settings > Live), not per song. Stored in UserDefaults by
/// the UI; a plain value here so the layout engine and tests share the defaults.
public struct LiveSettings: Sendable, Hashable, Codable {
    /// Default minimum lyric size in points (brand.md: 22pt).
    public static let defaultMinLyricSize: Double = 22
    /// The range Settings offers for `minLyricSize`.
    public static let minLyricSizeRange: ClosedRange<Double> = 16 ... 48
    public static let defaultStartShortcut = "Gig Mode On"
    public static let defaultEndShortcut = "Gig Mode Off"

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

    /// The column counts a song or the default can fix.
    public static let columnRange: ClosedRange<Int> = 1 ... 3

    public init(
        minLyricSize: Double = Self.defaultMinLyricSize,
        startShortcut: String? = Self.defaultStartShortcut,
        endShortcut: String? = Self.defaultEndShortcut,
        hiddenChecklistItems: Set<ChecklistItem> = [],
        defaultColumns: Int? = nil,
    ) {
        self.minLyricSize = minLyricSize
        self.startShortcut = startShortcut
        self.endShortcut = endShortcut
        self.hiddenChecklistItems = hiddenChecklistItems
        self.defaultColumns = defaultColumns
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
