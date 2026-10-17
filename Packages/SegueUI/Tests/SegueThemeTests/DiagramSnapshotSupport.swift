import AppKit
import Diagrams
import Editing
import ImageIO
import MusicTheory
@testable import SegueUI
import SwiftUI
import Testing
import UniformTypeIdentifiers

/// Fixtures and rendering helpers for `DiagramSnapshotTests`.
@MainActor
extension DiagramSnapshotTests {
    // MARK: - Fixtures

    struct GuitarChord {
        let name: String
        let shape: GuitarShape
        var tuning = Tuning.standard
    }

    static func curated(_ name: String) -> GuitarShape {
        CuratedShapes.all.first { $0.name == name }?.shape ?? GuitarShape(frets: [])
    }

    static func generated(_ tones: ChordTones, _ tuning: Tuning) -> GuitarShape {
        GuitarShapeGenerator.shapes(for: tones, tuning: tuning, limit: 1)
            .first ?? GuitarShape(frets: [])
    }

    static var standardChords: [GuitarChord] {
        ["C", "F", "Bm", "Eb", "D/F#", "Dmaj7"].map { GuitarChord(name: $0, shape: curated($0)) }
            + [GuitarChord(
                name: "C7(#9)",
                shape: generated(DiagramChords.tones(0, .sharpNine), .standard),
            )]
    }

    static var alternateChords: [GuitarChord] {
        [
            GuitarChord(
                name: "D",
                shape: generated(DiagramChords.tones(2), .dropD),
                tuning: .dropD,
            ),
            GuitarChord(
                name: "G",
                shape: generated(DiagramChords.tones(7), .dadgad),
                tuning: .dadgad,
            ),
            GuitarChord(
                name: "Bm7",
                shape: generated(DiagramChords.tones(11, .minor7), .dadgad),
                tuning: .dadgad,
            ),
            GuitarChord(
                name: "C",
                shape: generated(DiagramChords.tones(0), .openG),
                tuning: .openG,
            ),
            GuitarChord(
                name: "Em",
                shape: generated(DiagramChords.tones(4, .minor), .openG),
                tuning: .openG,
            ),
            GuitarChord(
                name: "E",
                shape: generated(
                    DiagramChords.tones(4),
                    Tuning(name: "7", strings: [35] + Tuning.standard.strings),
                ),
                tuning: Tuning(name: "7", strings: [35] + Tuning.standard.strings),
            ),
        ]
    }

    static let pianoChords: [(name: String, tones: ChordTones)] = [
        ("C", DiagramChords.tones(0)), ("G/B", DiagramChords.tones(7, bass: 11)),
        ("Am7", DiagramChords.tones(9, .minor7)), (
            "F#m7b5",
            DiagramChords.tones(6, .halfDiminished),
        ),
        ("Fmaj7", DiagramChords.tones(5, .major7)), ("Bb", DiagramChords.tones(10)),
        ("Eb/G", DiagramChords.tones(3, bass: 7)), ("D9", DiagramChords.tones(2, .ninth)),
    ]

    static func guitarGeometry(
        _ shape: GuitarShape,
        capoFret: Int? = nil,
    ) -> GuitarDiagramGeometry {
        GuitarDiagramGeometry(
            metrics: .forSize(.regular),
            shape: shape,
            stringCount: 6,
            minimumFrets: 4,
            capoFret: capoFret,
        )
    }

    func geometry(
        midpointOf geometry: GuitarDiagramGeometry,
        strings first: Int,
        _ second: Int,
        fret: Int,
    )
        -> CGPoint
    {
        let left = geometry.noteCentre(string: first, fret: fret)
        let right = geometry.noteCentre(string: second, fret: fret)
        return CGPoint(x: (left.x + right.x) / 2, y: left.y)
    }

    // MARK: - Rendering

    static let scale: CGFloat = 2

    func render(_ view: some View, scheme: ColorScheme) throws -> SampledImage {
        let renderer = ImageRenderer(
            content: view.background(Theme.color.ground).environment(\.colorScheme, scheme),
        )
        renderer.scale = Self.scale
        let image = try #require(renderer.cgImage, "ImageRenderer produced no image")
        return try SampledImage(bitmap: Bitmap(image), scale: Self.scale)
    }

    /// Renders `view` padded on the ground and writes it as a PNG for review.
    func snapshot(_ view: some View, name: String, scheme: ColorScheme) throws {
        let content = view
            .padding(24)
            .background(Theme.color.ground)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = Self.scale
        let image = try #require(renderer.cgImage, "ImageRenderer produced no image for \(name)")
        #expect(image.width > 100 && image.height > 100)
        let suffix = scheme == .dark ? "dark" : "light"
        try Self.writePNG(
            image,
            to: Self.screenshotDirectory.appending(path: "\(name)-\(suffix).png"),
        )
    }

    /// `<repo>/.build/screenshots/diagrams`, found from this file's real location.
    static var screenshotDirectory: URL {
        var url = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
        for _ in 0 ..< 5 {
            url.deleteLastPathComponent() // file, SegueThemeTests, Tests, SegueUI, Packages
        }
        return url.appending(path: ".build/screenshots/diagrams", directoryHint: .isDirectory)
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        let destination = try #require(
            CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil,
            ),
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination), "could not write \(url.path)")
    }
}

/// The token values for one appearance, as 0xRRGGBB.
struct Tokens {
    let ink: UInt32
    let ground: UInt32
    let muted: UInt32
    let cue: UInt32
    let lineStrong: UInt32

    init(_ scheme: ColorScheme) {
        func value(_ name: String) -> UInt32 {
            let token = ColorTokenValue.all.first { $0.name == name }
            return (scheme == .dark ? token?.dark : token?.light) ?? 0
        }
        ink = value("ink")
        ground = value("ground")
        muted = value("muted")
        cue = value("cue")
        lineStrong = value("lineStrong")
    }
}

/// A rendered bitmap sampled in points.
struct SampledImage {
    let bitmap: Bitmap
    let scale: CGFloat

    /// `nil` when the pixel at `point` (in points) is within a few steps of `color`,
    /// otherwise a description of what is there.
    func mismatch(_ color: UInt32, at point: CGPoint) -> String? {
        let pixel = bitmap.rgb(x: Int(point.x * scale), y: Int(point.y * scale))
        let expected = [Int(color >> 16 & 0xFF), Int(color >> 8 & 0xFF), Int(color & 0xFF)]
        let actual = [Int(pixel.red), Int(pixel.green), Int(pixel.blue)]
        guard zip(actual, expected).contains(where: { abs($0 - $1) > 6 }) else { return nil }
        return String(
            format: "#%06X at (%.1f, %.1f), want #%06X",
            pixel.packed,
            point.x,
            point.y,
            color,
        )
    }
}

/// Hand-built chord tones for the UI tests (independent of the chord-symbol parser).
enum DiagramChords {
    enum Quality {
        case major
        case minor
        case major7
        case minor7
        case halfDiminished
        case ninth
        case add9
        case sharpNine

        var formula: ChordFormula {
            switch self {
            case .major: ChordFormula(intervals: [0, 4, 7], essential: [0, 4])
            case .minor: ChordFormula(intervals: [0, 3, 7], essential: [0, 3])
            case .major7: ChordFormula(intervals: [0, 4, 7, 11], essential: [0, 4, 11])
            case .minor7: ChordFormula(intervals: [0, 3, 7, 10], essential: [0, 3, 10])
            case .halfDiminished: ChordFormula(intervals: [0, 3, 6, 10], essential: [0, 3, 6, 10])
            case .ninth: ChordFormula(intervals: [0, 4, 7, 10, 14], essential: [0, 4, 10, 14])
            case .add9: ChordFormula(intervals: [0, 4, 7, 14], essential: [0, 4, 14])
            case .sharpNine: ChordFormula(intervals: [0, 4, 7, 10, 15], essential: [0, 4, 10, 15])
            }
        }
    }

    static func tones(_ root: Int, _ quality: Quality = .major, bass: Int? = nil) -> ChordTones {
        ChordTones(
            root: PitchClass(root),
            bass: bass.map { PitchClass($0) },
            formula: quality.formula,
        )
    }
}
