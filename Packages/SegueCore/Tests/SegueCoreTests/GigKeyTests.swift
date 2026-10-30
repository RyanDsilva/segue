import MusicTheory
import Setlists
import Testing

/// "in A" in the set composer: the transpose that makes the slot's Key column show the
/// typed key (P8-5 section 7; R158 Q1 the key the row shows, Q2 relative means no change).
struct GigKeyTests {
    struct Row: Sendable, CustomTestStringConvertible {
        var written: String?
        var typed: String
        var songTranspose = 0
        var capo = 0
        var mode = CapoMode.shapes
        var expected: GigKeyResult
        var note: String

        var testDescription: String {
            note
        }
    }

    /// A row: the song's written key, the typed key, the expected result, then the
    /// song's saved view transpose, capo and capo mode.
    private static func row(
        _ written: String?,
        _ typed: String,
        _ expected: GigKeyResult,
        _ note: String,
        transpose: Int = 0,
        capo: Int = 0,
        mode: CapoMode = .shapes,
    ) -> Row {
        Row(
            written: written,
            typed: typed,
            songTranspose: transpose,
            capo: capo,
            mode: mode,
            expected: expected,
            note: note,
        )
    }

    static let rows: [Row] = [
        row("G", "A", .transpose(2), "G in A"),
        row("G", "G", .noOverride, "G in G"),
        row("G", "F#", .transpose(-1), "G in F#"),
        row("G", "C#", .transpose(6), "G in C# (tritone)"),
        row("G", "Db", .transpose(6), "G in Db (tritone)"),
        row("Am", "Bm", .transpose(2), "Am in Bm"),
        row("Am", "C", .noOverride, "Am in C (relative major)"),
        row("Am", "D", .transpose(5), "Am in D shows Dm"),
        row("Am", "Cm", .transpose(3), "Am in Cm"),
        row("G", "Em", .noOverride, "G in Em (relative minor)"),
        row("G", "Am", .transpose(2), "G in Am shows A"),
        row("Am", "D", .noOverride, "Am +2 shows Bm, in D (relative)", transpose: 2),
        row("Am", "C", .transpose(3), "Am +2 shows Bm, in C shows Cm", transpose: 2),
        // The spec's row says "shapes mode (shows A)"; a capo shows A only in concert mode
        // (`Capo.displayOffset`), so the relative-key row runs in concert mode.
        row("G", "F#m", .noOverride, "G capo 2 concert shows A, in F#m", capo: 2, mode: .concert),
        row("G", "A", .noOverride, "G +2 shows A, in A", transpose: 2),
        row("G", "G", .transpose(0), "G +2 shows A, in G is transpose 0", transpose: 2),
        row("G", "A", .transpose(2), "G capo 2 shapes, in A", capo: 2),
        row("G", "A", .noOverride, "G capo 2 concert, in A", capo: 2, mode: .concert),
        row(nil, "A", .songHasNoKey, "no key"),
    ]

    @Test(arguments: rows)
    func `typed key gives the transpose the row shows`(row: Row) throws {
        let target = try #require(SongKey(parsing: row.typed))
        let result = SetlistOverrides.transpose(
            toShow: target,
            written: row.written.flatMap(SongKey.init(parsing:)),
            songTranspose: row.songTranspose,
            capoOffset: Capo.displayOffset(capo: row.capo, mode: row.mode),
        )
        #expect(result == row.expected)
    }

    @Test(arguments: [
        ("Am", "C"), ("C", "Am"), ("G", "Em"), ("Em", "G"), ("Eb", "Cm"), ("F#", "D#m"),
        ("Bb", "Gm"), ("D#m", "F#"), ("Ebm", "Gb"), ("Db", "Bbm"),
    ])
    func `relative keys share a signature`(key: String, relative: String) throws {
        let parsed = try #require(SongKey(parsing: key))
        #expect(parsed.relative.name == relative)
    }
}
