import Editing
import MusicTheory
import Testing

/// `SongKey.scaleNotes` and the bass view's scale line (P8-4 section 11.1, R158 Q10).
struct ScaleTests {
    @Test(arguments: [
        ("G", "G A B C D E F#"),
        ("F", "F G A Bb C D E"),
        ("Bb", "Bb C D Eb F G A"),
        ("Eb", "Eb F G Ab Bb C D"),
        ("E", "E F# G# A B C# D#"),
        ("D", "D E F# G A B C#"),
        ("Am", "A B C D E F G"),
        ("Em", "E F# G A B C D"),
        ("Dm", "D E F G A Bb C"),
        ("Bm", "B C# D E F# G A"),
        ("F#m", "F# G# A B C# D E"),
        ("Cm", "C D Eb F G Ab Bb"),
        // White keys stay natural, as the chart spells them.
        ("F#", "F# G# A# B C# D# F"),
        ("Gb", "Gb Ab Bb B Db Eb F"),
    ])
    func `scale notes spelled like the chart`(key: String, notes: String) throws {
        let parsed = try #require(SongKey(parsing: key))
        #expect(parsed.scaleNotes.map(\.chartName).joined(separator: " ") == notes)
    }

    @Test(arguments: [
        ("A", "A major: A B C# D E F# G#"),
        ("F#m", "F#m: F# G# A B C# D E"),
    ])
    func `header scale text`(key: String, text: String) throws {
        #expect(try RenderHeader.scaleText(for: #require(SongKey(parsing: key))) == text)
    }
}
