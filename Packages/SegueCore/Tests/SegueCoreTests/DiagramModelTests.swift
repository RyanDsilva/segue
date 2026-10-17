import Diagrams
import Foundation
import MusicTheory
import Support
import Testing
import Tonic

/// Tunings, `{define}` values, the user shape library and the shape lookup order.
struct DiagramModelTests {
    // MARK: - Tuning meta

    @Test(arguments: [
        ("Standard", Tuning.standard), ("standard", .standard), ("Drop D", .dropD),
        ("drop-d", .dropD), ("DROPD", .dropD), ("dadgad", .dadgad), (" Open G ", .openG),
        ("D2 A2 D3 G3 A3 D4", .dadgad), ("E2 A2 D3 G3 B3 E4", .standard),
    ])
    func `tuning meta parses preset names and pitches`(value: String, expected: Tuning) {
        #expect(Tuning(metaValue: value) == expected)
    }

    @Test
    func `custom tunings are named by their pitches and round trip`() throws {
        let openC = try #require(Tuning(metaValue: "C2 G2 C3 G3 C4 E4"))
        #expect(openC.strings == [36, 43, 48, 55, 60, 64])
        #expect(openC.name == "C2 G2 C3 G3 C4 E4")
        #expect(openC.metaValue == "C2 G2 C3 G3 C4 E4")
        #expect(Tuning(metaValue: openC.metaValue) == openC)

        let halfDown = try #require(Tuning(metaValue: "Eb2 Ab2 Db3 Gb3 Bb3 Eb4"))
        #expect(halfDown.strings == [39, 44, 49, 54, 58, 63])
        #expect(halfDown.metaValue == "D#2 G#2 C#3 F#3 A#3 D#4")
        #expect(Tuning(metaValue: halfDown.metaValue)?.strings == halfDown.strings)

        let bass = try #require(Tuning(metaValue: "E1, A1, D2, G2"))
        #expect(bass.strings == [28, 33, 38, 43])
    }

    @Test
    func `presets write their names`() {
        for preset in Tuning.presets {
            #expect(Tuning(metaValue: preset.metaValue) == preset)
        }
        #expect(Tuning.dadgad.metaValue == "DADGAD")
        // Preset pitches under another label still write the preset name.
        #expect(Tuning(name: "My DADGAD", strings: Tuning.dadgad.strings).metaValue == "DADGAD")
    }

    @Test(arguments: ["", "Nashville", "E2 A2 H3", "E A D G B E", "E2", "E2 A2 D10", "X2 A2 D3"])
    func `tuning meta rejects nonsense`(value: String) {
        #expect(Tuning(metaValue: value) == nil)
    }

    // MARK: - {define}

    @Test
    func `define parses the spec example`() throws {
        let define = try #require(
            ChordDefinition(
                directiveValue: "Gadd9 base-fret 1 frets 3 2 0 2 0 3 fingers 2 1 0 3 0 4",
            ),
        )
        #expect(define.name == "Gadd9")
        guard case let .guitar(shape) = define.shape else {
            Issue.record("expected a guitar define")
            return
        }
        #expect(shape.frets == [3, 2, 0, 2, 0, 3])
        #expect(shape.fingers == [2, 1, nil, 3, nil, 4])
        #expect(shape.baseFret == 1)
        #expect(shape.barres.isEmpty)
        #expect(define.directiveValue == "Gadd9 base-fret 1 frets 3 2 0 2 0 3 fingers 2 1 0 3 0 4")
    }

    @Test
    func `define reads muted strings base fret and barres`() throws {
        let define = try #require(
            ChordDefinition(
                directiveValue: "Bm  BASE-FRET 2 frets x 1 3 3 2 1 fingers - 1 3 4 2 1",
            ),
        )
        guard case let .guitar(shape) = define.shape else {
            Issue.record("expected a guitar define")
            return
        }
        #expect(shape.frets == [nil, 1, 3, 3, 2, 1])
        #expect(shape.absoluteFrets == [nil, 2, 4, 4, 3, 2])
        #expect(shape.barres == [Barre(fret: 1, strings: 1 ... 5, finger: 1)])
        #expect(define.directiveValue == "Bm base-fret 2 frets x 1 3 3 2 1 fingers 0 1 3 4 2 1")
        #expect(ChordDefinition(directiveValue: define.directiveValue) == define)
    }

    @Test
    func `define without fingers infers a barre but writes no fingers`() throws {
        let define = try #require(ChordDefinition(directiveValue: "F frets 1 3 3 2 1 1"))
        guard case let .guitar(shape) = define.shape else {
            Issue.record("expected a guitar define")
            return
        }
        #expect(shape.fingers.isEmpty)
        #expect(shape.barres == [Barre(fret: 1, strings: 0 ... 5, finger: 1)])
        #expect(define.directiveValue == "F base-fret 1 frets 1 3 3 2 1 1")
        #expect(ChordDefinition(directiveValue: define.directiveValue) == define)
    }

    @Test
    func `define parses piano keys`() throws {
        let define = try #require(ChordDefinition(directiveValue: "Cmaj7 keys 0 4 7 11"))
        #expect(define.shape == .piano(keys: [0, 4, 7, 11]))
        #expect(define.directiveValue == "Cmaj7 keys 0 4 7 11")
    }

    @Test(arguments: [
        "", "Am", "Am frets", "Am frets 1 2 q", "Am base-fret 0 frets 0 0 2 2 1 0",
        "Am frets 0 0 2 2 1 0 fingers 0 0 2 3", "Am frets x 0 2 2 1 0 display A-minor",
        "Am keys", "Am keys 0 3 x", "Am frets 0 0 2 2 1 0 keys 0 3 7", "Am color red",
    ])
    func `malformed defines are rejected`(value: String) {
        #expect(ChordDefinition(directiveValue: value) == nil)
    }

    // MARK: - User shape library

    @Test
    func `user library round trips through disk and a missing file is empty`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(
                path: "segue-shape-library-\(UUID().uuidString)",
                directoryHint: .isDirectory,
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "nested/\(UserShapeLibrary.fileName)")
        let fileSystem = LiveFileSystem()

        #expect(try UserShapeLibrary.load(from: url, fileSystem: fileSystem) == .empty)

        var library = UserShapeLibrary()
        library.set(GuitarShape(frets: [nil, 3, 2, 0, 1, 0]), named: "C", tuning: .standard)
        library.set(GuitarShape(absoluteFrets: [0, 0, 0, 2, 3, 2]), named: "D", tuning: .dropD)
        library.set(GuitarShape(frets: [nil, 3, 2, 0, 1, 3]), named: "C", tuning: .standard)
        #expect(library.entries.count == 2)
        try library.save(to: url, fileSystem: fileSystem)

        let reloaded = try UserShapeLibrary.load(from: url, fileSystem: fileSystem)
        #expect(reloaded == library)
        #expect(reloaded.shape(named: "C", tuning: .standard)?.frets == [nil, 3, 2, 0, 1, 3])
        #expect(reloaded.shape(named: "D", tuning: .standard) == nil)

        let text = try #require(String(bytes: fileSystem.readData(at: url), encoding: .utf8))
        #expect(text.contains("\"schemaVersion\" : 1"))
        #expect(text.hasSuffix("\n"))
    }

    @Test
    func `user library from a newer app is refused`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(
                path: "segue-shape-library-\(UUID().uuidString)",
                directoryHint: .isDirectory,
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileSystem = LiveFileSystem()
        try fileSystem.createDirectory(at: directory)
        let url = directory.appending(path: UserShapeLibrary.fileName)
        try fileSystem.writeAtomically(Data(#"{"schemaVersion": 9, "entries": []}"#.utf8), to: url)
        #expect(throws: UserShapeLibraryError.newerSchema(found: 9, supported: 1)) {
            try UserShapeLibrary.load(from: url, fileSystem: fileSystem)
        }
    }

    // MARK: - Shape resolver

    @Test
    func `lookup order is define then user library then curated then generated`() throws {
        let cMajor = DiagramChords.chart("C", root: .C)
        let defined = GuitarShape(frets: [nil, 3, 5, 5, 5, 3])
        let saved = GuitarShape(frets: [8, 10, 10, 9, 8, 8])
        let library = UserShapeLibrary(entries: [.init(name: "C", tuning: .standard, shape: saved)])
        let defines = [
            ChordDefinition(name: "C", shape: .guitar(GuitarShape(frets: [0, 0, 0, 0, 0, 0]))),
            ChordDefinition(name: "C", shape: .piano(keys: [0, 4, 7])),
            ChordDefinition(name: "C", shape: .guitar(defined)),
        ]

        let all = ShapeResolver(defines: defines, userLibrary: library, tuning: .standard)
        #expect(all.guitarShape(for: cMajor) == ResolvedGuitarShape(
            shape: defined,
            source: .songDefine,
        ))

        let noDefine = ShapeResolver(defines: [], userLibrary: library, tuning: .standard)
        #expect(noDefine.guitarShape(for: cMajor) == ResolvedGuitarShape(
            shape: saved,
            source: .userLibrary,
        ))

        let curated = try #require(ShapeResolver(
            defines: [],
            userLibrary: .empty,
            tuning: .standard,
        )
        .guitarShape(for: cMajor))
        #expect(curated.source == .curated)
        #expect(ShapeCheck.text(curated.shape) == "x32010")

        let generated = try #require(ShapeResolver(
            defines: [],
            userLibrary: library,
            tuning: .dadgad,
        )
        .guitarShape(for: cMajor))
        #expect(generated.source == .generated)
        #expect(ShapeCheck.problems(generated.shape, tones: cMajor.tones, tuning: .dadgad).isEmpty)
    }

    @Test
    func `curated overrides win over the generator wherever defined`() {
        let resolver = ShapeResolver(defines: [], userLibrary: .empty, tuning: .standard)
        for entry in CuratedShapes.all {
            let chord = DiagramChords.chart(entry.name, tones: entry.tones)
            #expect(
                resolver.guitarShape(for: chord)
                    == ResolvedGuitarShape(shape: entry.shape, source: .curated),
                "\(entry.name)",
            )
        }
        // A case where the generator alone would rank another shape first.
        let gSlashB = DiagramChords.chart("G/B", root: .G, bass: .B)
        let resolved = resolver.guitarShape(for: gSlashB)
        #expect(resolved?.source == .curated)
        #expect(resolved.map { ShapeCheck.text($0.shape) } == "x20003")
    }

    @Test
    func `defines match trimmed names and skip shapes for another string count`() {
        let fourString = GuitarShape(frets: [0, 2, 2, 1])
        let resolver = ShapeResolver(
            defines: [ChordDefinition(name: "E", shape: .guitar(fourString))],
            userLibrary: .empty,
            tuning: .standard,
        )
        #expect(resolver.guitarShape(for: DiagramChords.chart(" E ", root: .E))?.source == .curated)

        let sixString = GuitarShape(frets: [0, 2, 2, 1, 0, 0])
        let trimmed = ShapeResolver(
            defines: [ChordDefinition(name: "E", shape: .guitar(sixString))],
            userLibrary: .empty,
            tuning: .standard,
        )
        #expect(trimmed.guitarShape(for: DiagramChords.chart(" E ", root: .E))?
            .source == .songDefine)
    }

    @Test
    func `piano voicings use keys defines and voice-lead the rest`() {
        let resolver = ShapeResolver(
            defines: [ChordDefinition(name: "Fmaj7", shape: .piano(keys: [0, 4, 7, 11]))],
            userLibrary: .empty,
            tuning: .standard,
        )
        let voicings = resolver.pianoVoicings(for: [
            DiagramChords.chart("C", root: .C),
            DiagramChords.chart("Fmaj7", root: .F, "maj7"),
            DiagramChords.chart("G", root: .G),
        ])
        // Fmaj7's keys sit in the one octave that fits C3 ... C5; G then moves least from it.
        #expect(voicings.map(\.notes) == [[60, 64, 67], [53, 57, 60, 64], [55, 59, 62]])
        #expect(voicings.map(\.bass) == [48, 41, 43])
        #expect(voicings.map(\.root) == [PitchClass(0), PitchClass(5), PitchClass(7)])
    }
}
