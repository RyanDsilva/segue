/// Line-oriented ChordPro v0 parser (grammar in docs/phases/0-walking-skeleton.md).
///
/// Contract:
/// - Never throws or crashes on malformed input. Unclosed braces/brackets become text and
///   produce a `Diagnostic`.
/// - `ChordProSerializer.serialize(parse(x).0)` is byte-identical for canonical input and
///   idempotent for any input.
/// - Parsing a 300-line song takes < 5 ms.
public enum ChordProParser {
    /// Parses ChordPro source into an AST plus diagnostics.
    public static func parse(_ source: String) -> (SongDocument, [Diagnostic]) {
        _ = source
        fatalError("unimplemented")
    }
}
