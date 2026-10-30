import ChordPro
import Diagrams
import Editing
import Library
import MusicTheory
import Setlists
import Testing

/// The bass-note view (P8-4 section 11.1): `DisplayTransform.bassText` through a real
/// `RenderModel` built from a tiny `.cho` per row.
struct BassNoteTests {
    struct Row: CustomTestStringConvertible, Sendable {
        var chord: String
        var key: String?
        var capo: Int?
        var mode = CapoMode.shapes
        var transpose = 0
        var override: SetlistOverrides?
        var nashville = false
        var note: String
        /// The detail with `chordBeside` on; nil for `N.C.` and unknown chords.
        var detail: String?

        var testDescription: String {
            "\(chord) in \(key ?? "-") capo \(capo ?? 0) \(mode) t\(transpose)"
                + " \(override.map { "\($0)" } ?? "-") \(nashville ? "nashville" : "")"
        }
    }

    static let rows: [Row] = [
        Row(chord: "G", key: "G", note: "G", detail: "G"),
        Row(chord: "G/B", key: "G", note: "B", detail: "G/B"),
        Row(chord: "Cmaj7", key: "G", note: "C", detail: "Cmaj7"),
        Row(chord: "F#m7b5", key: "G", note: "F#", detail: "F#m7b5"),
        Row(chord: "C6/9", key: "C", note: "C", detail: "C6/9"),
        Row(chord: "G", key: "G", capo: 2, note: "A", detail: "A"),
        Row(chord: "G/B", key: "G", capo: 2, note: "C#", detail: "A/C#"),
        Row(chord: "Em", key: "G", capo: 2, mode: .concert, note: "F#", detail: "F#m"),
        Row(chord: "C", key: "C", capo: 3, note: "Eb", detail: "Eb"),
        Row(chord: "Bb", key: "F", capo: 1, note: "B", detail: "B"),
        Row(
            chord: "G",
            key: "G",
            capo: 2,
            override: SetlistOverrides(capo: 0),
            note: "A",
            detail: "A",
        ),
        Row(
            chord: "G",
            key: "G",
            capo: 2,
            override: SetlistOverrides(capo: 4),
            note: "A",
            detail: "A",
        ),
        Row(
            chord: "G",
            key: "G",
            capo: 2,
            override: SetlistOverrides(transpose: 2),
            note: "B",
            detail: "B",
        ),
        Row(chord: "D", key: "G", nashville: true, note: "5 \u{00B7} D", detail: "D"),
        Row(chord: "G/B", key: "G", nashville: true, note: "3 \u{00B7} B", detail: "G/B"),
        Row(chord: "Am", key: "Am", nashville: true, note: "6 \u{00B7} A", detail: "Am"),
        Row(chord: "E7", key: "Am", nashville: true, note: "3 \u{00B7} E", detail: "E7"),
        Row(chord: "Bb", key: "C", nashville: true, note: "b7 \u{00B7} Bb", detail: "Bb"),
        Row(chord: "N.C.", key: "G", nashville: true, note: "N.C.", detail: nil),
        Row(chord: "Xyz", key: "G", note: "Xyz", detail: nil),
    ]

    static func source(chord: String, key: String?, capo: Int?) -> String {
        var lines = ["{title: Bass}"]
        if let key {
            lines.append("{key: \(key)}")
        }
        if let capo {
            lines.append("{capo: \(capo)}")
        }
        lines += ["", "[\(chord)]Hello there"]
        return lines.joined(separator: "\n") + "\n"
    }

    /// The first chord of a one-line song rendered with the bass view.
    static func render(_ row: Row, chordBeside: Bool, bassNotes: Bool = true) -> RenderModel {
        let (document, _) = ChordProParser.parse(source(
            chord: row.chord,
            key: row.key,
            capo: row.capo,
        ))
        let profile = InstrumentProfile(bassNotes: bassNotes, chordBeside: chordBeside)
        let options = DisplayOptions(
            transpose: row.transpose,
            capoMode: row.mode,
            nashville: row.nashville,
        ).withBass(profile)
        let (applied, capo) = row.override.map {
            $0.applied(to: options, songCapo: document.metadata.capo)
        } ?? (options, document.metadata.capo)
        return RenderModel(document: document, options: applied, capo: capo)
    }

    static func firstChord(_ model: RenderModel) throws -> RenderChord {
        for section in model.sections {
            for case let .lyrics(line) in section.items {
                if let chord = line.chords.first {
                    return chord
                }
            }
        }
        throw Missing()
    }

    struct Missing: Error {}

    @Test(arguments: rows)
    func `bass note at sounding pitch`(row: Row) throws {
        let beside = try Self.firstChord(Self.render(row, chordBeside: true))
        #expect(beside.text == row.note)
        #expect(beside.detail == row.detail)
        let plain = try Self.firstChord(Self.render(row, chordBeside: false))
        #expect(plain.text == row.note)
        #expect(plain.detail == nil)
    }

    @Test
    func `no key gives the note alone even with the song's Nashville on`() {
        let (document, _) = ChordProParser.parse(Self.source(chord: "D", key: nil, capo: nil))
        let options = DisplayOptions(nashville: true).withBass(InstrumentProfile(bassNotes: true))
        let transform = DisplayTransform(
            options: options,
            key: KeyContext(declared: nil, detection: nil),
            capo: document.metadata.capo,
        )
        #expect(transform.bassText(ChordToken(parsing: "D")) == BassChordText(
            note: "D",
            chord: nil,
        ))
    }

    @Test
    func `numbers follow each song's own Nashville toggle with one profile`() throws {
        let numbered = Row(chord: "D", key: "G", nashville: true, note: "", detail: nil)
        let letters = Row(chord: "D", key: "G", nashville: false, note: "", detail: nil)
        #expect(try Self.firstChord(Self.render(numbered, chordBeside: false))
            .text == "5 \u{00B7} D")
        #expect(try Self.firstChord(Self.render(letters, chordBeside: false)).text == "D")
    }

    @Test
    func `bass notes work without the bass profile`() {
        let profile = InstrumentProfile(playsBass: false, bassNotes: true)
        #expect(profile.bassView?.notes == true)
        #expect(profile.bassView?.tuning == .bassStandard4)
    }

    @Test
    func `bass view off renders exactly as before`() throws {
        let row = Row(chord: "G/B", key: "G", capo: 2, note: "", detail: nil)
        let off = Self.render(row, chordBeside: true, bassNotes: false)
        let (document, _) = ChordProParser.parse(Self.source(chord: "G/B", key: "G", capo: 2))
        let today = RenderModel(document: document, options: DisplayOptions())
        #expect(off == today)
        #expect(try Self.firstChord(off).text == "G/B")
        #expect(off.header.key == "G")
        #expect(off.header.scale == nil)
    }

    @Test
    func `header names the sounding key without capo in bass view`() {
        let row = Row(chord: "G", key: "G", capo: 2, note: "", detail: nil)
        let model = Self.render(row, chordBeside: false)
        #expect(model.header.key == "A")
        #expect(model.header.scale == "A major: A B C# D E F# G#")
        let minor = Self.render(
            Row(chord: "F#m", key: "F#m", note: "", detail: nil),
            chordBeside: false,
        )
        #expect(minor.header.scale == "F#m: F# G# A B C# D E")
        let none = Self.render(
            Row(chord: "Xyz", key: nil, note: "", detail: nil),
            chordBeside: false,
        )
        #expect(none.header.scale == nil)
    }

    @Test
    func `per-song prefs never carry the bass view`() {
        let plain = DisplayOptions(transpose: 3, nashville: true)
        let withBass = plain.withBass(InstrumentProfile(bassNotes: true, chordBeside: true))
        #expect(withBass.bass != nil)
        #expect(DisplayPrefs(withBass) == DisplayPrefs(plain))
    }
}
