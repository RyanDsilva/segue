import ChordPro
import Diagrams
import Editing
import MusicTheory
import Playback
import Testing

/// Which MIDI notes a chord sounds as, at sounding pitch (P8-6 sections 6.2, 15.1).
struct VoicingTests {
    /// The concert chord for `written` under the song's capo and the view's transpose.
    static func concert(_ written: String, key: String?, capo: Int = 0, transpose: Int = 0)
        -> ChordSymbol?
    {
        let transform = DisplayTransform(
            options: DisplayOptions(transpose: transpose),
            key: KeyContext(declared: key.flatMap(SongKey.init(parsing:)), detection: nil),
            capo: capo,
        )
        return transform.concert(ChordToken(parsing: written)).chord?.symbol
    }

    @Test(arguments: [
        ("G", 0, 0, [55, 59, 62]),
        ("G", 2, 0, [57, 61, 64]),
        ("G", 0, 2, [57, 61, 64]),
        ("Cmaj7", 0, 0, [48, 52, 55, 59]),
        ("F#m7b5", 0, 0, [54, 57, 60, 64]),
        ("G/B", 0, 0, [55, 59, 62]),
    ])
    func `piano voicings`(written: String, capo: Int, transpose: Int, notes: [Int]) throws {
        let chord = try #require(Self.concert(written, key: "G", capo: capo, transpose: transpose))
        #expect(Voicing.chord(chord, sound: .piano).map(Int.init) == notes)
    }

    @Test
    func `piano drops the fifth beyond four tones and stays inside C3 to C5`() throws {
        let chord = try #require(ChordSymbol(parsing: "G9"))
        let notes = Voicing.chord(chord, sound: .piano).map(Int.init)
        #expect(notes.count == 4)
        #expect(!notes.contains(62)) // no D, the fifth
        #expect(notes.allSatisfy { Voicing.pianoRange.contains($0) })
    }

    @Test(arguments: [
        ("G", [43, 47, 50, 55, 59, 67]),
        ("C", [48, 52, 55, 60, 64]),
    ])
    func `clean guitar plays the strip's shape`(written: String, notes: [Int]) throws {
        let chord = try #require(ChordSymbol(parsing: written))
        #expect(Voicing.chord(chord, sound: .cleanGuitar).map(Int.init) == notes)
    }

    @Test(arguments: [
        ("G", "G", 0, Tuning.bassStandard4, 31),
        ("G/B", "G", 0, .bassStandard4, 35),
        ("G", "G", 2, .bassStandard4, 33),
        ("D", "D", 0, .bassStandard5, 26),
    ])
    func `bass notes`(written: String, key: String, capo: Int, tuning: Tuning, note: Int) throws {
        let chord = try #require(Self.concert(written, key: key, capo: capo))
        let concertKey = SongKey(parsing: key)?.transposed(by: capo)
        let placement = BassPlacement.song(concertKey: concertKey, firstBass: nil, tuning: tuning)
        #expect(Int(Voicing.bassNote(of: chord, placement: placement)) == note)
    }

    @Test
    func `with no key the home comes from the first bass note`() throws {
        let chord = try #require(ChordSymbol(parsing: "D"))
        let placement = BassPlacement.song(
            concertKey: nil,
            firstBass: chord.root.pitchClass,
            tuning: .bassStandard4,
        )
        #expect(placement.home == 5)
        #expect(Voicing.bassNote(of: chord, placement: placement) == 33 + 5) // A string fret 5
    }
}
