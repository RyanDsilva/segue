/// Serializes a `SongDocument` back to ChordPro source. Output is canonical: parsing it and
/// serializing again yields the same bytes.
public enum ChordProSerializer {
    /// Renders `document` as ChordPro text.
    public static func serialize(_ document: SongDocument) -> String {
        _ = document
        fatalError("unimplemented")
    }
}
