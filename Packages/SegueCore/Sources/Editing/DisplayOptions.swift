// Owner: unit C (Editing). Frozen interface: docs/phases/1-interfaces.md.

import ChordPro
import Diagrams
import MusicTheory

/// The per-song view toggles every renderer honours (editor preview, visual editor, live
/// view, later PDF). Persisted per song as `DisplayPrefs` in the sidecar.
public struct DisplayOptions: Sendable, Hashable, Codable {
    /// View transposition in semitones, -11 ... 11 (the UI wraps; any Int is accepted).
    public var transpose: Int
    /// Shapes vs concert when the song has a capo.
    public var capoMode: CapoMode
    /// Show Nashville numbers instead of chord names.
    public var nashville: Bool
    /// Show the diagram strip.
    public var showDiagrams: Bool
    /// Which instrument the diagram strip shows.
    public var instrument: Instrument
    /// Guitar tuning for diagrams when the song has no `{meta: tuning ...}`.
    public var tuning: Tuning

    public init(
        transpose: Int = 0,
        capoMode: CapoMode = .shapes,
        nashville: Bool = false,
        showDiagrams: Bool = true,
        instrument: Instrument = .guitar,
        tuning: Tuning = .standard,
    ) {
        self.transpose = transpose
        self.capoMode = capoMode
        self.nashville = nashville
        self.showDiagrams = showDiagrams
        self.instrument = instrument
        self.tuning = tuning
    }
}

/// Where the song's key came from.
public enum KeyStatus: Sendable, Hashable {
    /// A parseable `{key}`.
    case declared
    /// No `{key}`; detected with a clear winner. Shown as "inferred" until confirmed.
    case inferred
    /// No `{key}`; detected but the top two candidates are within the margin.
    case ambiguous
    /// No `{key}` and no chords to infer one from.
    case unknown
}

/// The key of the chords as written: declared `{key}` or the detector's result.
///
/// Convention (open question in docs/phases/1-interfaces.md): `{key}` names the key of the
/// chords as written, i.e. the shape key when the song has a capo.
public struct KeyContext: Sendable, Hashable {
    public var declared: SongKey?
    /// Only computed when there is no parseable `{key}`.
    public var detection: KeyDetection?

    public init(declared: SongKey?, detection: KeyDetection?) {
        self.declared = declared
        self.detection = detection
    }

    /// Parses `{key}`, else runs `KeyDetector` over the song's chords.
    public init(document: SongDocument) {
        fatalError("unimplemented: unit C")
    }

    /// `declared ?? detection?.key`.
    public var writtenKey: SongKey? {
        declared ?? detection?.key
    }

    public var status: KeyStatus {
        if declared != nil {
            return .declared
        }
        guard let detection else { return .unknown }
        return detection.isAmbiguous ? .ambiguous : .inferred
    }
}

/// The chord transform a renderer applies: transpose + capo mode (+ Nashville), and its
/// inverse for chord input in visual mode.
public struct DisplayTransform: Sendable, Hashable {
    public let options: DisplayOptions
    public let key: KeyContext
    /// `{capo}` from the song (nil or 0 = none).
    public let capo: Int?

    public init(options: DisplayOptions, key: KeyContext, capo: Int?) {
        self.options = options
        self.key = key
        self.capo = capo
    }

    /// Net semitones from written chords to displayed chords:
    /// `options.transpose + Capo.displayOffset(capo:mode:)`.
    public var semitones: Int {
        options.transpose + Capo.displayOffset(capo: capo, mode: options.capoMode)
    }

    /// Net semitones from written chords to concert pitch (piano diagrams):
    /// `options.transpose + capo`, whatever the capo mode.
    public var concertSemitones: Int {
        options.transpose + max(capo ?? 0, 0)
    }

    /// The key the displayed chords are in.
    public var displayKey: SongKey? {
        key.writtenKey?.transposed(by: semitones)
    }

    /// Text to show for a chord as written: transposed, or a Nashville number when
    /// `options.nashville` (relative to `displayKey`; verbatim if there is no key).
    public func display(_ token: ChordToken) -> String {
        fatalError("unimplemented: unit C")
    }

    /// The chord as written, transposed to concert pitch (for piano diagrams).
    public func concert(_ token: ChordToken) -> ChordToken {
        fatalError("unimplemented: unit C")
    }

    /// Inverse transform for chord input: a chord typed in the display key (letter names
    /// even in Nashville view; number input is out of scope this phase) -> source text.
    /// Unparseable input is returned unchanged (it becomes an unknown chord).
    public func sourceChord(fromDisplayed text: String) -> String {
        fatalError("unimplemented: unit C")
    }
}
