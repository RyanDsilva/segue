import AppKit
import Diagrams
import Editing
import ImageIO
import MusicTheory
@testable import SegueUI
import SwiftUI
import Testing
import UniformTypeIdentifiers

/// Renders chord diagrams through the real generators and views in light and dark, writes
/// them to `.build/screenshots/diagrams/` for review, and samples pixels at known geometry
/// (dots, markers, nut, capo, keys, root and bass) against the theme tokens.
@MainActor
struct DiagramSnapshotTests {
    nonisolated static let schemes: [ColorScheme] = [.light, .dark]

    // MARK: - Snapshot gallery

    @Test(arguments: schemes)
    func `guitar gallery renders`(scheme: ColorScheme) throws {
        #expect(Theme.registerFonts())
        let gallery = VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 20) {
                ForEach(Self.standardChords, id: \.name) { chord in
                    GuitarDiagramView(name: chord.name, shape: chord.shape, tuning: .standard)
                }
            }
            HStack(alignment: .top, spacing: 20) {
                ForEach(Self.alternateChords, id: \.name) { chord in
                    GuitarDiagramView(name: chord.name, shape: chord.shape, tuning: chord.tuning)
                }
            }
            HStack(alignment: .top, spacing: 24) {
                ForEach([DiagramSize.compact, .regular, .stage], id: \.self) { size in
                    GuitarDiagramView(
                        name: "G",
                        shape: Self.curated("G"),
                        tuning: .standard,
                        capoFret: 2,
                        size: size,
                    )
                }
                GuitarDiagramView(
                    name: "Bm",
                    shape: Self.curated("Bm"),
                    tuning: .standard,
                    size: .stage,
                )
            }
        }
        try snapshot(gallery, name: "guitar", scheme: scheme)
    }

    @Test(arguments: schemes)
    func `piano gallery renders`(scheme: ColorScheme) throws {
        let voicings = PianoVoicingGenerator.voicings(for: Self.pianoChords.map(\.tones))
        let gallery = VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 20) {
                ForEach(
                    Array(zip(Self.pianoChords, voicings).enumerated()),
                    id: \.offset,
                ) { _, pair in
                    PianoDiagramView(name: pair.0.name, voicing: pair.1)
                }
            }
            HStack(alignment: .top, spacing: 24) {
                ForEach([DiagramSize.compact, .regular, .stage], id: \.self) { size in
                    PianoDiagramView(name: "F#m7b5", voicing: voicings[3], size: size)
                }
            }
        }
        try snapshot(gallery, name: "piano", scheme: scheme)
    }

    @Test(arguments: schemes)
    func `diagram strip renders for both instruments`(scheme: ColorScheme) throws {
        let chords: [(String, ChordTones)] = [
            ("G", DiagramChords.tones(7)), ("D/F#", DiagramChords.tones(2, bass: 6)),
            ("Em", DiagramChords.tones(4, .minor)), ("C", DiagramChords.tones(0)),
            ("Cadd9", DiagramChords.tones(0, .add9)),
        ]
        let voicings = PianoVoicingGenerator.voicings(for: chords.map(\.1))
        let diagrams = chords.enumerated().map { index, chord in
            let shape = CuratedShapes.shape(for: chord.1, tuning: .standard)
                ?? GuitarShapeGenerator.shapes(for: chord.1, tuning: .standard).first
            return RenderDiagram(
                name: chord.0,
                concertName: chord.0,
                guitar: shape.map { ResolvedGuitarShape(shape: $0, source: .curated) },
                piano: voicings[index],
                capoFret: nil,
            )
        }
        let unknown = RenderDiagram(
            name: "Hm7",
            concertName: "Hm7",
            guitar: nil,
            piano: nil,
            capoFret: nil,
        )
        let strips = VStack(alignment: .leading, spacing: 16) {
            // The strip's cells as `DiagramStrip` lays them out; ImageRenderer cannot draw the
            // scroll view around them.
            DiagramStripContent(
                diagrams: diagrams + [unknown],
                instrument: .guitar,
                tuning: .standard,
                size: .compact,
                onCustomize: { _ in },
            )
            DiagramStripContent(
                diagrams: diagrams + [unknown],
                instrument: .piano,
                tuning: .standard,
                size: .compact,
                onCustomize: nil,
            )
            DiagramStripContent(
                diagrams: Array(diagrams.prefix(4)),
                instrument: .guitar,
                tuning: .standard,
                size: .stage,
                onCustomize: nil,
            )
        }
        .frame(width: 760)
        try snapshot(strips, name: "strip", scheme: scheme)
    }

    @Test(arguments: schemes)
    func `shape editor renders for both instruments`(scheme: ColorScheme) throws {
        let editors = HStack(alignment: .top, spacing: 24) {
            ShapeEditorView(
                chordName: "Gadd9",
                instrument: .guitar,
                tuning: .standard,
                initialGuitar: Self.curated("Gadd9"),
                onSave: { _ in },
                onCancel: {},
            )
            ShapeEditorView(
                chordName: "Cmaj7",
                instrument: .piano,
                tuning: .standard,
                initialPiano: PianoVoicingGenerator.voicing(
                    for: DiagramChords.tones(0, .major7),
                    after: nil,
                ),
                onSave: { _ in },
                onCancel: {},
            )
        }
        .frame(width: 720)
        try snapshot(editors, name: "editor", scheme: scheme)
    }

    // MARK: - Pixel checks

    @Test(arguments: schemes)
    func `guitar diagram draws dots markers and nut where the geometry says`(
        scheme: ColorScheme,
    ) throws {
        let shape = Self.curated("C") // x32010
        let geometry = Self.guitarGeometry(shape)
        let image = try render(
            GuitarDiagramCanvas(geometry: geometry, shape: shape),
            scheme: scheme,
        )
        let tokens = Tokens(scheme)

        // Fretted notes are ink dots; an unused cell shows the ground.
        // Sample above the centre: regular diagrams draw the finger number in the middle.
        let above = geometry.metrics.dotSize * 0.38
        for (string, fret) in [(1, 3), (2, 2), (4, 1)] {
            let centre = geometry.noteCentre(string: string, fret: fret)
            #expect(image
                .mismatch(tokens.ink, at: CGPoint(x: centre.x, y: centre.y - above)) == nil)
        }
        let empty = geometry.noteCentre(string: 0, fret: 2)
        #expect(image.mismatch(tokens.ground, at: CGPoint(x: empty.x + 4, y: empty.y)) == nil)
        // Open G string: a hollow ring (ground centre). Muted low E: a cross (muted centre).
        #expect(image.mismatch(tokens.ground, at: geometry.markerCentre(string: 3)) == nil)
        #expect(image.mismatch(tokens.muted, at: geometry.markerCentre(string: 0)) == nil)
        // The nut is a solid ink bar.
        let nutY = geometry.gridTop - geometry.metrics.nutWidth / 2
        #expect(image.mismatch(tokens.ink, at: CGPoint(x: geometry.stringX(2) + 5, y: nutY)) == nil)
    }

    @Test(arguments: schemes)
    func `capo bar overhangs the strings and barres span them`(scheme: ColorScheme) throws {
        let tokens = Tokens(scheme)
        let gMajor = Self.curated("G")
        let capo = Self.guitarGeometry(gMajor, capoFret: 2)
        let withCapo = try render(
            GuitarDiagramCanvas(geometry: capo, shape: gMajor),
            scheme: scheme,
        )
        let overhang = CGPoint(x: capo.stringX(0) - 3, y: capo.gridTop - 3)
        #expect(withCapo.mismatch(tokens.ink, at: overhang) == nil)

        let plain = Self.guitarGeometry(gMajor)
        let withoutCapo = try render(
            GuitarDiagramCanvas(geometry: plain, shape: gMajor),
            scheme: scheme,
        )
        #expect(withoutCapo.mismatch(
            tokens.ground,
            at: CGPoint(x: plain.stringX(0) - 3, y: plain.gridTop - 3),
        ) == nil)

        let fMajor = Self.curated("F") // 133211, barre on fret 1
        let barre = Self.guitarGeometry(fMajor)
        let barred = try render(GuitarDiagramCanvas(geometry: barre, shape: fMajor), scheme: scheme)
        let between = geometry(midpointOf: barre, strings: 3, 4, fret: 1)
        #expect(barred.mismatch(tokens.ink, at: between) == nil)
    }

    @Test(arguments: schemes)
    func `piano marks chord tones the root and the bass`(scheme: ColorScheme) throws {
        let tokens = Tokens(scheme)
        // G/B: G B D over a B bass.
        let voicing = PianoVoicingGenerator.voicing(
            for: DiagramChords.tones(7, bass: 11),
            after: nil,
        )
        let geometry = PianoDiagramGeometry(metrics: .forSize(.regular))
        let image = try render(
            PianoDiagramCanvas(geometry: geometry, voicing: voicing),
            scheme: scheme,
        )

        #expect(image.mismatch(tokens.cue, at: geometry.dotCentre(PitchClass(7))) == nil)
        #expect(image.mismatch(tokens.ink, at: geometry.dotCentre(PitchClass(11))) == nil)
        #expect(image.mismatch(tokens.ink, at: geometry.dotCentre(PitchClass(2))) == nil)
        // An unplayed white key is ground; an unplayed black key is the black-key fill.
        #expect(image.mismatch(tokens.ground, at: geometry.dotCentre(PitchClass(0))) == nil)
        let blackKey = scheme == .dark ? tokens.lineStrong : tokens.ink
        #expect(image.mismatch(blackKey, at: geometry.dotCentre(PitchClass(1))) == nil)
        // The bass caret sits under B, not under the root.
        let bassX = geometry.keyCentreX(PitchClass(11))
        let caretY = geometry.inset + geometry.keyboardHeight + geometry.bassRowHeight * 0.6
        #expect(image.mismatch(tokens.ink, at: CGPoint(x: bassX, y: caretY)) == nil)
        let rootX = geometry.keyCentreX(PitchClass(7))
        #expect(image.mismatch(tokens.ground, at: CGPoint(x: rootX, y: caretY)) == nil)
    }

    @Test(arguments: schemes)
    func `a root on a black key is marked in cue and other black-key tones contrast`(
        scheme: ColorScheme,
    ) throws {
        let tokens = Tokens(scheme)
        // Bb major: Bb D F, root on a black key.
        let voicing = PianoVoicingGenerator.voicing(for: DiagramChords.tones(10), after: nil)
        let geometry = PianoDiagramGeometry(metrics: .forSize(.stage))
        let image = try render(
            PianoDiagramCanvas(geometry: geometry, voicing: voicing),
            scheme: scheme,
        )
        #expect(image.mismatch(tokens.cue, at: geometry.dotCentre(PitchClass(10))) == nil)

        // In Eb major, Bb is a black-key chord tone that is not the root.
        let eFlat = PianoVoicingGenerator.voicing(for: DiagramChords.tones(3), after: nil)
        let eFlatImage = try render(
            PianoDiagramCanvas(geometry: geometry, voicing: eFlat),
            scheme: scheme,
        )
        let toneOnBlack = scheme == .dark ? tokens.ink : tokens.ground
        #expect(eFlatImage.mismatch(toneOnBlack, at: geometry.dotCentre(PitchClass(10))) == nil)
    }

    // MARK: - Hit testing and editing

    @Test
    func `guitar cells and piano keys hit-test`() {
        let shape = Self.curated("C")
        let geometry = Self.guitarGeometry(shape)
        let cell = geometry.cell(at: geometry.noteCentre(string: 4, fret: 1))
        #expect(cell?.string == 4 && cell?.fret == 1)
        let marker = geometry.cell(at: geometry.markerCentre(string: 0))
        #expect(marker?.string == 0 && marker?.fret == 0)
        #expect(geometry.cell(at: CGPoint(x: -20, y: 30)) == nil)

        let piano = PianoDiagramGeometry(metrics: .forSize(.regular))
        for pitchClass in 0 ..< 12 {
            #expect(piano
                .pitchClass(at: piano.dotCentre(PitchClass(pitchClass))) == PitchClass(pitchClass))
        }
    }

    @Test
    func `guitar editor taps build a define`() throws {
        var draft = GuitarDraft(Self.curated("C"), stringCount: 6)
        draft.tap(string: 5, fret: 3, stringCount: 6) // add G on top: x32013
        draft.tap(string: 3, fret: 0, stringCount: 6) // mute the G string
        draft.tap(string: 1, fret: 3, stringCount: 6) // same fret again: opens the A string
        let definition = try #require(draft.definition(name: "C", stringCount: 6))
        #expect(definition.directiveValue == "C base-fret 1 frets x 0 2 x 1 3 fingers 0 0 2 0 1 3")

        var empty = GuitarDraft(nil, stringCount: 6)
        for string in 0 ..< 6 {
            empty.tap(string: string, fret: 0, stringCount: 6)
        }
        #expect(empty.definition(name: "C", stringCount: 6) == nil)
    }

    @Test
    func `piano editor toggles keys relative to the root`() throws {
        var draft = PianoDraft(PianoVoicingGenerator.voicing(
            for: DiagramChords.tones(9, .minor),
            after: nil,
        ))
        draft.toggle(PitchClass(7)) // add G: Am7
        draft.toggle(PitchClass(4)) // drop E
        let definition = try #require(draft.definition(name: "Am7"))
        #expect(definition.directiveValue == "Am7 keys 0 3 10")
        #expect(draft.voicing.root == PitchClass(9))
    }
}
