// P8-4a (docs/phases/8-workstreams/P8-4-bass.md section 6.1, R152, R158 Q7).

import Diagrams
import MusicTheory
import Support

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
    /// Walk-ups on charts (P8-4b section 8.7; default off).
    public var walkUps: WalkUpDensity
    /// The default feel for songs without their own (P8-4b section 8.7; default Pop).
    public var genre: BassGenre
    /// "Fills as tab" (P8-7 section 14.2, R168 Q8): every saved fill draws as a mini tab,
    /// whatever its own choice (`t` on stage, the editor's Bass menu, Settings). Default off.
    public var fillsAsTab: Bool
    /// Keys this build does not model, kept for the next save
    /// (docs/architecture/data-compatibility.md).
    public var unknown: UnknownFields = .empty

    public init(
        playsBass: Bool = false,
        strings: Int = 4,
        tuning: Tuning = .bassStandard4,
        bassNotes: Bool = false,
        chordBeside: Bool = false,
        stageNeck: Bool = true,
        fretboard: Bool = true,
        walkUps: WalkUpDensity = .off,
        genre: BassGenre = .pop,
        fillsAsTab: Bool = false,
    ) {
        self.playsBass = playsBass
        self.strings = strings
        self.tuning = tuning
        self.bassNotes = bassNotes
        self.chordBeside = chordBeside
        self.stageNeck = stageNeck
        self.fretboard = fretboard
        self.walkUps = walkUps
        self.genre = genre
        self.fillsAsTab = fillsAsTab
        normalize()
    }

    /// What renderers get (`DisplayOptions.bass`): nil unless the bass-note view is on or
    /// the bassist's fretboard strip is (P8-4b; `notes` is false then, so charts keep their
    /// chords).
    public var bassView: BassView? {
        guard bassNotes || (playsBass && fretboard) else { return nil }
        return BassView(
            notes: bassNotes,
            chordBeside: chordBeside,
            // The Settings strings and tuning, with or without "I play bass" (R163).
            tuning: tuning,
            neck: bassNotes && stageNeck,
            fretboard: playsBass && fretboard,
            walkUps: walkUps,
            genre: genre,
            fillsAsTab: fillsAsTab,
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

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case playsBass
        case strings
        case tuning
        case bassNotes
        case chordBeside
        case stageNeck
        case fretboard
        case walkUps
        case genre
        case fillsAsTab
    }

    public init(from decoder: any Decoder) throws {
        var object = try LenientObject<CodingKeys>(decoder)
        let defaults = Self()
        playsBass = object.value(.playsBass, default: defaults.playsBass)
        strings = object.value(.strings, default: defaults.strings)
        tuning = object.value(.tuning, default: defaults.tuning)
        bassNotes = object.value(.bassNotes, default: defaults.bassNotes)
        chordBeside = object.value(.chordBeside, default: defaults.chordBeside)
        stageNeck = object.value(.stageNeck, default: defaults.stageNeck)
        fretboard = object.value(.fretboard, default: defaults.fretboard)
        walkUps = object.value(.walkUps, default: defaults.walkUps)
        genre = object.value(.genre, default: defaults.genre)
        fillsAsTab = object.value(.fillsAsTab, default: defaults.fillsAsTab)
        unknown = object.unknown
        normalize()
    }

    public func encode(to encoder: any Encoder) throws {
        try unknown.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(playsBass, forKey: .playsBass)
        try container.encode(strings, forKey: .strings)
        try container.encode(tuning, forKey: .tuning)
        try container.encode(bassNotes, forKey: .bassNotes)
        try container.encode(chordBeside, forKey: .chordBeside)
        try container.encode(stageNeck, forKey: .stageNeck)
        try container.encode(fretboard, forKey: .fretboard)
        try container.encode(walkUps, forKey: .walkUps)
        try container.encode(genre, forKey: .genre)
        try container.encode(fillsAsTab, forKey: .fillsAsTab)
    }
}

/// The render-time slice of the profile (`DisplayOptions.bass`). Never persisted: Nashville
/// numbers come from the song's own `DisplayOptions.nashville` (R158 Q2).
public struct BassView: Sendable, Hashable {
    /// Show bass notes instead of chord names.
    public var notes: Bool
    /// The full concert chord small beside the note.
    public var chordBeside: Bool
    /// The profile's strings and tuning, for anyone (R163).
    public var tuning: Tuning
    /// The stage mini neck (`bassNotes && stageNeck`).
    public var neck: Bool
    /// The editor fretboard strip (P8-4b; `playsBass && fretboard`).
    public var fretboard: Bool
    /// Walk-ups on charts (P8-4b): drawn only in the bass-note view (R162 Q4).
    public var walkUps: WalkUpDensity
    /// The default feel for songs without their own (P8-4b).
    public var genre: BassGenre
    /// Every saved fill as a mini tab (P8-7 section 14.2); else each fill's own choice.
    public var fillsAsTab: Bool

    public init(
        notes: Bool = true,
        chordBeside: Bool = false,
        tuning: Tuning = .bassStandard4,
        neck: Bool = false,
        fretboard: Bool = false,
        walkUps: WalkUpDensity = .off,
        genre: BassGenre = .pop,
        fillsAsTab: Bool = false,
    ) {
        self.notes = notes
        self.chordBeside = chordBeside
        self.tuning = tuning
        self.neck = neck
        self.fretboard = fretboard
        self.walkUps = walkUps
        self.genre = genre
        self.fillsAsTab = fillsAsTab
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
