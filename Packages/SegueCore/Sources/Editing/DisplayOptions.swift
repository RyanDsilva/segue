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
    /// The user's bass-note view (P8-4, from `InstrumentProfile`; nil = off). Never
    /// persisted: excluded from coding and absent from `DisplayPrefs`, so no per-song write
    /// can carry it.
    public var bass: BassView?

    public init(
        transpose: Int = 0,
        capoMode: CapoMode = .shapes,
        nashville: Bool = false,
        showDiagrams: Bool = false,
        instrument: Instrument = .guitar,
        tuning: Tuning = .standard,
        bass: BassView? = nil,
    ) {
        self.transpose = transpose
        self.capoMode = capoMode
        self.nashville = nashville
        self.showDiagrams = showDiagrams
        self.instrument = instrument
        self.tuning = tuning
        self.bass = bass
    }

    private enum CodingKeys: String, CodingKey {
        case transpose
        case capoMode
        case nashville
        case showDiagrams
        case instrument
        case tuning
    }
}

/// The bass-note view's text for one chord (`DisplayTransform.bassText`).
public struct BassChordText: Sendable, Equatable {
    /// "B", or "3 · B" when the song's Nashville toggle is on.
    public var note: String
    /// The concert chord ("A/C#" for `G/B` under capo 2) when `chordBeside` is on.
    public var chord: String?

    public init(note: String, chord: String?) {
        self.note = note
        self.chord = chord
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
        declared = document.metadata.key.flatMap(SongKey.init(parsing:))
        detection = declared == nil ? KeyDetector.detect(document.chartChords) : nil
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

    /// The sounding (concert) key: the written key + capo + transpose.
    public var concertKey: SongKey? {
        key.writtenKey?.transposed(by: concertSemitones)
    }

    /// The bass-note view's text for a chord (P8-4 section 6.1): nil unless
    /// `options.bass?.notes`. The note is the slash bass, else the root, at sounding pitch
    /// whatever the capo mode, spelled as the transposer spelled it; "3 · B" when the
    /// song's Nashville toggle is on and a key is known. `N.C.` and unknown chords come
    /// back verbatim with no chord.
    public func bassText(_ token: ChordToken) -> BassChordText? {
        guard let bass = options.bass, bass.notes else { return nil }
        guard let concert = concert(token).chord else {
            return BassChordText(note: token.original, chord: nil)
        }
        let symbol = concert.symbol
        let noteClass = symbol.bass ?? symbol.root
        var note = noteClass.chartName
        if options.nashville, let written = key.writtenKey {
            // Numbers are transposition-invariant: the concert note in the concert key.
            let sounding = written.transposed(by: concertSemitones)
            note = Nashville.degree(of: noteClass.pitchClass, in: sounding) + " \u{00B7} " + note
        }
        return BassChordText(note: note, chord: bass.chordBeside ? concert.original : nil)
    }

    /// Text to show for a chord as written: transposed, or a Nashville number when
    /// `options.nashville` (relative to `displayKey`; verbatim if there is no key).
    public func display(_ token: ChordToken) -> String {
        guard options.nashville else { return displayed(token).original }
        guard let written = key.writtenKey else { return token.original }
        // Nashville numbers are transposition-invariant, so numbering the chord as written
        // in the written key equals numbering the displayed chord in `displayKey`, without
        // depending on the transform's enharmonic choices.
        return Nashville.number(for: token, in: written)
    }

    /// The chord as displayed in letter names (transposed and capo-shifted; also used for
    /// diagram names in Nashville view).
    public func displayed(_ token: ChordToken) -> ChordToken {
        Transposer(semitones: semitones, sourceKey: key.writtenKey).transpose(token)
    }

    /// The chord as written, transposed to concert pitch (for piano diagrams).
    public func concert(_ token: ChordToken) -> ChordToken {
        Transposer(semitones: concertSemitones, sourceKey: key.writtenKey).transpose(token)
    }

    /// Inverse transform for chord input: a chord typed in the display key -> source text.
    /// Letter names are accepted in every view; in Nashville view a number (`1`, `4`, `6m`,
    /// `b7`, `5/7`, `3(7)`) is also accepted and resolves against `displayKey`. Since
    /// numbers are transposition-invariant, that is the same chord as the number read in
    /// the written key, so it is spelled there directly. Unparseable input is returned
    /// unchanged (it becomes an unknown chord).
    public func sourceChord(fromDisplayed text: String) -> String {
        if options.nashville, let written = key.writtenKey, Nashville.looksLikeNumber(text) {
            return Nashville.chord(parsing: text, in: written)?.original ?? text
        }
        let token = ChordToken(parsing: text)
        guard token.chord != nil, PitchClass(semitones).rawValue != 0 else { return text }
        let transposer = if let displayKey, let written = key.writtenKey {
            Transposer(from: displayKey, to: written)
        } else {
            Transposer(semitones: -semitones, sourceKey: nil)
        }
        return transposer.transpose(token).original
    }
}
