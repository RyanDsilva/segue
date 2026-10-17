import Diagrams
import Foundation
import MusicTheory
import Support
import Testing

/// Every chord in the fixture corpus, parsed by the real chord-symbol parser, gets a
/// playable guitar shape in each preset tuning and a piano voicing (phase 1 acceptance 5/6).
struct DiagramCorpusTests {
    /// Unique chord tokens (`[...]` contents) across every fixture `.cho`, in file order.
    static func corpusChords() throws -> [ChartChord] {
        let fixtures = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let fileSystem = LiveFileSystem()
        var seen = Set<String>()
        var chords: [ChartChord] = []
        let files = try fileSystem.contentsOfDirectory(at: fixtures)
            .filter { $0.pathExtension == "cho" }
        for file in files {
            let text = try #require(String(bytes: fileSystem.readData(at: file), encoding: .utf8))
            for match in text.matches(of: /\[([^\[\]\r\n]+)\]/) {
                let token = String(match.output.1)
                guard seen.insert(token).inserted,
                      let chord = ChordToken(parsing: token).chord
                else { continue }
                chords.append(chord)
            }
        }
        return chords
    }

    @Test
    func `corpus has chords to check`() throws {
        #expect(try Self.corpusChords().count >= 20)
    }

    @Test(arguments: Tuning.presets)
    func `every corpus chord gets a playable guitar shape`(tuning: Tuning) throws {
        let resolver = ShapeResolver(defines: [], userLibrary: .empty, tuning: tuning)
        var failures: [String] = []
        for chord in try Self.corpusChords() {
            guard let resolved = resolver.guitarShape(for: chord) else {
                failures.append("\(chord.original): no shape")
                continue
            }
            let problems = ShapeCheck.problems(resolved.shape, tones: chord.tones, tuning: tuning)
            if !problems.isEmpty {
                failures.append("\(chord.original) \(ShapeCheck.text(resolved.shape)): \(problems)")
            }
        }
        #expect(failures.isEmpty, "\(tuning.name):\n\(failures.joined(separator: "\n"))")
    }

    @Test
    func `every corpus chord gets a piano voicing with its root and bass`() throws {
        let chords = try Self.corpusChords()
        let resolver = ShapeResolver(defines: [], userLibrary: .empty, tuning: .standard)
        let voicings = resolver.pianoVoicings(for: chords)
        #expect(voicings.count == chords.count)
        for (chord, voicing) in zip(chords, voicings) {
            let classes = Set(voicing.foldedPitchClasses)
            let essential = chord.tones.formula.essential
                .map { chord.tones.root.transposed(by: $0) }
            #expect(classes.isSuperset(of: essential), "\(chord.original)")
            #expect(voicing.root == chord.tones.root, "\(chord.original)")
            #expect(
                voicing.bass.map(PitchClass.init(midi:)) == chord.tones.lowest,
                "\(chord.original)",
            )
        }
    }
}
