// Owner: unit A (MusicTheory). Frozen interface: docs/phases/1-interfaces.md.

/// Nashville number rendering (phase 1 spec, "Nashville rendering").
public enum Nashville {
    /// The Nashville form of `token` relative to `key`: `1 4 5 6m`, accidentals `b7` /
    /// `#4`, quality suffix kept (`2m7`, `57/7`), slash bass as a degree (`1/3`). Minor
    /// keys are numbered from the relative major (`Am` in A minor is `6m`).
    /// `.noChord` / `.unknown` come back verbatim. Transposition-invariant: transposing
    /// the token and the key by the same amount yields the same string.
    public static func number(for token: ChordToken, in key: SongKey) -> String {
        fatalError("unimplemented: unit A")
    }

    /// Key header for Nashville view: `"C"` for a major key, `"Am (rel. C)"` for a minor key.
    public static func header(for key: SongKey) -> String {
        fatalError("unimplemented: unit A")
    }
}
