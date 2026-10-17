import MusicTheory
import Testing

/// Golden expectations for the song pipeline suite: unique displayed chords (in order of
/// first appearance) and the header key, per fixture and view toggles.
extension EditingSongPipelineTests {
    struct Golden: CustomTestStringConvertible, Sendable {
        var fixture: String
        var transpose = 0
        var capoMode = CapoMode.shapes
        var nashville = false
        /// Unique displayed chord texts in order of first appearance.
        var chords: [String]
        var headerKey: String?

        var testDescription: String {
            "\(fixture) \(transpose) \(capoMode) \(nashville ? "nashville" : "letters")"
        }
    }

    static let basic = "basic-verse-chorus.cho"
    static let defines = "editing-capo-defines.cho"

    static let goldens: [Golden] = [
        Golden(fixture: basic, chords: ["G", "Em", "C", "D", "Am"], headerKey: "G"),
        Golden(fixture: basic, transpose: 12, chords: ["G", "Em", "C", "D", "Am"], headerKey: "G"),
        Golden(fixture: basic, transpose: -12, chords: ["G", "Em", "C", "D", "Am"], headerKey: "G"),
        Golden(
            fixture: basic,
            capoMode: .concert,
            chords: ["A", "F#m", "D", "E", "Bm"],
            headerKey: "A",
        ),
        Golden(fixture: basic, transpose: 2, chords: ["A", "F#m", "D", "E", "Bm"], headerKey: "A"),
        Golden(fixture: basic, transpose: -2, chords: ["F", "Dm", "Bb", "C", "Gm"], headerKey: "F"),
        Golden(
            fixture: basic,
            transpose: 1,
            chords: ["Ab", "Fm", "Db", "Eb", "Bbm"],
            headerKey: "Ab",
        ),
        Golden(
            fixture: basic,
            transpose: 3,
            chords: ["Bb", "Gm", "Eb", "F", "Cm"],
            headerKey: "Bb",
        ),
        Golden(
            fixture: basic,
            transpose: -3,
            chords: ["E", "C#m", "A", "B", "F#m"],
            headerKey: "E",
        ),
        Golden(
            fixture: basic,
            transpose: 4,
            chords: ["B", "G#m", "E", "F#", "C#m"],
            headerKey: "B",
        ),
        Golden(fixture: basic, transpose: 5, chords: ["C", "Am", "F", "G", "Dm"], headerKey: "C"),
        Golden(
            fixture: basic,
            transpose: -4,
            chords: ["Eb", "Cm", "Ab", "Bb", "Fm"],
            headerKey: "Eb",
        ),
        Golden(
            fixture: basic,
            nashville: true,
            chords: ["1", "6m", "4", "5", "2m"],
            headerKey: "G",
        ),
        Golden(
            fixture: basic,
            transpose: -5,
            capoMode: .concert,
            nashville: true,
            chords: ["1", "6m", "4", "5", "2m"],
            headerKey: "E",
        ),
        Golden(
            fixture: "hindi-pyaar-ki-raah.cho",
            chords: ["Am", "G", "F", "E"],
            headerKey: "Am",
        ),
        Golden(
            fixture: "hindi-pyaar-ki-raah.cho",
            transpose: 2,
            chords: ["Bm", "A", "G", "F#"],
            headerKey: "Bm",
        ),
        Golden(
            fixture: "hindi-pyaar-ki-raah.cho",
            transpose: 3,
            chords: ["Cm", "Bb", "Ab", "G"],
            headerKey: "Cm",
        ),
        Golden(
            fixture: "hindi-pyaar-ki-raah.cho",
            nashville: true,
            chords: ["6m", "5", "4", "3"],
            headerKey: "Am (rel. C)",
        ),
        Golden(
            fixture: defines,
            chords: ["G", "Em", "C", "D", "Gadd9", "G/B", "Am7", "N.C.", "D7sus4"],
            headerKey: "G",
        ),
        Golden(
            fixture: defines,
            capoMode: .concert,
            chords: ["A", "F#m", "D", "E", "Aadd9", "A/C#", "Bm7", "N.C.", "E7sus4"],
            headerKey: "A",
        ),
        Golden(
            fixture: defines,
            capoMode: .concert,
            nashville: true,
            chords: ["1", "6m", "4", "5", "1add9", "1/3", "2m7", "N.C.", "5(7sus4)"],
            headerKey: "A",
        ),
        Golden(
            fixture: "chord-edge-cases.cho",
            chords: ["Bb", "F/A", "Gm7", "Eb", "F", "Cm7", "F7sus4", "", "N.C.", "Bb/D", "Ebmaj7"],
            headerKey: "Bb",
        ),
        Golden(
            fixture: "chord-edge-cases.cho",
            transpose: 2,
            chords: ["C", "G/B", "Am7", "F", "G", "Dm7", "G7sus4", "", "N.C.", "C/E", "Fmaj7"],
            headerKey: "C",
        ),
        Golden(
            fixture: "chord-edge-cases.cho",
            nashville: true,
            chords: ["1", "5/7", "6m7", "4", "5", "2m7", "5(7sus4)", "", "N.C.", "1/3", "4maj7"],
            headerKey: "Bb",
        ),
        Golden(
            fixture: "hindi-dil-kabhie.cho",
            nashville: true,
            chords: ["1", "5", "6m", "4"],
            headerKey: "D",
        ),
    ]
}
