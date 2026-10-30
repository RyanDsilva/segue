// P8-4a (docs/phases/8-workstreams/P8-4-bass.md section 6.1, R152, R158 Q7).

import Diagrams

/// The user's instrument (Settings > Instrument, R152). App-level: never in a sidecar or a
/// `.cho`. Decoded leniently per field: a missing or unreadable field keeps its default.
public struct InstrumentProfile: Sendable, Hashable, Codable {
    /// The bassist profile ("I play bass").
    public var playsBass: Bool
    /// 4 or 5.
    public var strings: Int
    /// The bass tuning; `tuning.strings.count == strings`.
    public var tuning: Tuning
    /// The bass-note view, for anyone (R158 Q7).
    public var bassNotes: Bool
    /// The full chord small beside the note.
    public var chordBeside: Bool
    /// The mini neck on stage while the bass-note view is on (R161: on by default).
    public var stageNeck: Bool
    /// The editor's fretboard strip (P8-4b; needs `playsBass`).
    public var fretboard: Bool

    public init(
        playsBass: Bool = false,
        strings: Int = 4,
        tuning: Tuning = .bassStandard4,
        bassNotes: Bool = false,
        chordBeside: Bool = false,
        stageNeck: Bool = true,
        fretboard: Bool = true,
    ) {
        self.playsBass = playsBass
        self.strings = strings
        self.tuning = tuning
        self.bassNotes = bassNotes
        self.chordBeside = chordBeside
        self.stageNeck = stageNeck
        self.fretboard = fretboard
        normalize()
    }

    /// What renderers get (`DisplayOptions.bass`): nil unless the bass-note view is on.
    /// P8-4b widens this to `playsBass` for its fretboard strip.
    public var bassView: BassView? {
        guard bassNotes else { return nil }
        return BassView(
            notes: true,
            chordBeside: chordBeside,
            // Without "I play bass" the neck uses EADG (decision 2, section 7.3).
            tuning: playsBass ? tuning : .bassStandard4,
            neck: stageNeck,
            fretboard: playsBass && fretboard,
        )
    }

    /// The invariant every write keeps: `strings` in 4 ... 5 and the tuning has that many
    /// strings, else that count's standard tuning.
    public mutating func normalize() {
        if !Tuning.bassStringCounts.contains(strings) {
            strings = Tuning.bassStringCounts.contains(tuning.strings.count)
                ? tuning.strings.count : 4
        }
        if tuning.strings.count != strings {
            tuning = .bassStandard(strings: strings)
        }
    }

    /// Switches the string count; the tuning resets to that count's standard unless it
    /// already has that many strings.
    public mutating func setStrings(_ count: Int) {
        strings = count
        normalize()
    }

    /// Turns the bassist profile on or off. Turning it on also turns the bass-note view on
    /// (once; it can be turned off again); turning it off leaves the view as it is.
    public mutating func setPlaysBass(_ on: Bool) {
        playsBass = on
        if on {
            bassNotes = true
        }
    }

    private enum CodingKeys: String, CodingKey {
        case playsBass
        case strings
        case tuning
        case bassNotes
        case chordBeside
        case stageNeck
        case fretboard
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        func field<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        playsBass = field(.playsBass, defaults.playsBass)
        strings = field(.strings, defaults.strings)
        tuning = field(.tuning, defaults.tuning)
        bassNotes = field(.bassNotes, defaults.bassNotes)
        chordBeside = field(.chordBeside, defaults.chordBeside)
        stageNeck = field(.stageNeck, defaults.stageNeck)
        fretboard = field(.fretboard, defaults.fretboard)
        normalize()
    }
}

/// The render-time slice of the profile (`DisplayOptions.bass`). Never persisted: Nashville
/// numbers come from the song's own `DisplayOptions.nashville` (R158 Q2).
public struct BassView: Sendable, Hashable {
    /// Show bass notes instead of chord names.
    public var notes: Bool
    /// The full concert chord small beside the note.
    public var chordBeside: Bool
    /// The profile's tuning, else `.bassStandard4`.
    public var tuning: Tuning
    /// The stage mini neck (`bassNotes && stageNeck`).
    public var neck: Bool
    /// The editor fretboard strip (P8-4b; `playsBass && fretboard`).
    public var fretboard: Bool

    public init(
        notes: Bool = true,
        chordBeside: Bool = false,
        tuning: Tuning = .bassStandard4,
        neck: Bool = false,
        fretboard: Bool = false,
    ) {
        self.notes = notes
        self.chordBeside = chordBeside
        self.tuning = tuning
        self.neck = neck
        self.fretboard = fretboard
    }
}

public extension DisplayOptions {
    /// These options with the profile's bass view applied (`bass` is nil when the view is
    /// off). `forcingNotes` turns the notes on whatever the profile says (the "Bass chart"
    /// PDF option, section 7.4).
    func withBass(_ profile: InstrumentProfile, forcingNotes: Bool = false) -> Self {
        var profile = profile
        if forcingNotes {
            profile.bassNotes = true
        }
        var options = self
        options.bass = profile.bassView
        return options
    }
}
