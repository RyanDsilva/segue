// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit C (persistence in UI).

import Foundation

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

    public init(
        minLyricSize: Double = Self.defaultMinLyricSize,
        startShortcut: String? = Self.defaultStartShortcut,
        endShortcut: String? = Self.defaultEndShortcut,
        hiddenChecklistItems: Set<ChecklistItem> = [],
    ) {
        self.minLyricSize = minLyricSize
        self.startShortcut = startShortcut
        self.endShortcut = endShortcut
        self.hiddenChecklistItems = hiddenChecklistItems
    }
}
