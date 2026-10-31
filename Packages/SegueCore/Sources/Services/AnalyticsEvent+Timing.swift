import Foundation

// Timing analytics (P8-7 section 15): rows 27 and 28 of the closed vocabulary. Enums and
// buckets only, no song data.

/// Row 27: `Segue.Timing.tapCaptured`, one per Tap Timing review closed (rare by nature).
public struct TapCapturedSummary: Sendable, Hashable {
    public var mode: TapCaptureMode
    public var outcome: TapCaptureOutcome
    /// Chords whose length the taps changed.
    public var chords: SmallBucket
    /// Chords skipped.
    public var skipped: SmallBucket
    /// "Set song tempo" was pressed.
    public var tempoSet: Bool

    public init(
        mode: TapCaptureMode,
        outcome: TapCaptureOutcome,
        chords: SmallBucket,
        skipped: SmallBucket,
        tempoSet: Bool,
    ) {
        self.mode = mode
        self.outcome = outcome
        self.chords = chords
        self.skipped = skipped
        self.tempoSet = tempoSet
    }
}

/// With Segue's click, or tempo-free (`TapMode`'s raw values).
public enum TapCaptureMode: String, Sendable, CaseIterable {
    case click
    case free
}

public enum TapCaptureOutcome: String, Sendable, CaseIterable {
    case kept
    case discarded
}

/// Row 28: what happened to a key change: the chip's Insert, its dismiss, or a `{key}`
/// inserted from the menus.
public enum KeyChangeAction: String, Sendable, CaseIterable {
    case confirmed
    case dismissed
    case inserted
}

/// The change from the key in effect: a half step up, a whole step up, or anything else.
public enum KeyChangeInterval: String, Sendable, CaseIterable {
    case halfUp
    case wholeUp
    case other

    /// From semitones up (0-11) between the tonics.
    public init(semitones: Int) {
        switch ((semitones % 12) + 12) % 12 {
        case 1: self = .halfUp
        case 2: self = .wholeUp
        default: self = .other
        }
    }
}
