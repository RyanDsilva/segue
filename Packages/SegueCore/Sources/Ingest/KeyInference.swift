import MusicTheory

/// The song key: a stated key wins; else `KeyDetector` (phase 1). A model key may be used
/// only when `isAmbiguous` and the key is one of `topTwo` (spec section 3).
public struct KeyInference: Sendable, Equatable, Hashable {
    public enum Source: String, Sendable, Equatable, Hashable {
        /// `{key}`, `Key:` or `Scale:` in the sheet.
        case stated
        /// Detected from the chords.
        case detected
        /// No stated key and no chords.
        case unknown
    }

    public var stated: SongKey?
    public var detection: KeyDetection?

    public init(stated: SongKey?, detection: KeyDetection?) {
        self.stated = stated
        self.detection = detection
    }

    /// Infers from a stated key text (if it parses) and the song's chords in order.
    public init(stated text: String?, chords: [ChartChord]) {
        stated = text.flatMap(SongKey.init(parsing:))
        detection = KeyDetector.detect(chords)
    }

    public var key: SongKey? {
        stated ?? detection?.key
    }

    public var source: Source {
        if stated != nil {
            return .stated
        }
        return detection == nil ? .unknown : .detected
    }

    /// True only for a detected key whose runner-up is within the ambiguity margin.
    public var isAmbiguous: Bool {
        stated == nil && detection?.isAmbiguous == true
    }

    /// The two best detected keys (empty without chords).
    public var topTwo: [SongKey] {
        detection.map { Array($0.ranking.prefix(2).map(\.key)) } ?? []
    }

    /// Whether a model's key may replace the detected one.
    public func accepts(modelKey: SongKey) -> Bool {
        isAmbiguous && topTwo.contains(modelKey)
    }
}
