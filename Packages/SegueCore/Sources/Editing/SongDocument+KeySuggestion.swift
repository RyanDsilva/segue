import ChordPro
import MusicTheory

public extension SongDocument {
    /// The key `KeyDetector` hears in the song's chords, whether or not `{key}` is set: the
    /// song card offers it as a suggestion ("Am - from chords", R101) and never writes it
    /// by itself.
    var detectedKey: SongKey? {
        KeyDetector.detect(chartChords)?.key
    }
}
