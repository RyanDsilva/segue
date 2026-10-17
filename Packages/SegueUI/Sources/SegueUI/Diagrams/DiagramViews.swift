// Owner: unit B (diagram views). Frozen interface: docs/phases/1-interfaces.md.
// The views live beside this file: GuitarDiagramView, PianoDiagramView, DiagramStrip and
// ShapeEditorView. This file holds the shared size scale.

import SwiftUI

/// Diagram scale. All diagrams draw with `Canvas` and scale crisply; colours come from
/// `Theme.color` so they work in the light editor and on the dark stage.
enum DiagramSize: Sendable, Hashable {
    /// Editor diagram strip.
    case compact
    /// Popovers and the shape editor.
    case regular
    /// Live view strip.
    case stage
}

/// Point metrics for one `DiagramSize`, shared by the guitar and piano diagrams so a strip
/// mixing both lines up.
struct DiagramMetrics: Equatable {
    /// Chord name above the diagram (700, `cueText`).
    var nameSize: CGFloat
    /// Base-fret label, capo caption.
    var labelSize: CGFloat
    /// Guitar: distance between strings and between frets.
    var stringGap: CGFloat
    var fretGap: CGFloat
    /// Guitar: fretted-note dot diameter, open/muted marker size.
    var dotSize: CGFloat
    var markerSize: CGFloat
    /// Guitar: grid hairline and nut thickness.
    var lineWidth: CGFloat
    var nutWidth: CGFloat
    /// Whether finger numbers are drawn inside the dots.
    var showsFingers: Bool
    /// Piano: white-key width and height.
    var whiteKeyWidth: CGFloat
    var whiteKeyHeight: CGFloat
    /// Space between the name and the diagram.
    var nameSpacing: CGFloat

    static func forSize(_ size: DiagramSize) -> Self {
        switch size {
        case .compact:
            Self(
                nameSize: 13,
                labelSize: 9,
                stringGap: 9,
                fretGap: 11,
                dotSize: 7,
                markerSize: 5,
                lineWidth: 1,
                nutWidth: 3,
                showsFingers: false,
                whiteKeyWidth: 11,
                whiteKeyHeight: 36,
                nameSpacing: 4,
            )
        case .regular:
            Self(
                nameSize: 16,
                labelSize: 11,
                stringGap: 14,
                fretGap: 18,
                dotSize: 12,
                markerSize: 8,
                lineWidth: 1,
                nutWidth: 4,
                showsFingers: true,
                whiteKeyWidth: 15,
                whiteKeyHeight: 52,
                nameSpacing: 6,
            )
        case .stage:
            Self(
                nameSize: 22,
                labelSize: 13,
                stringGap: 17,
                fretGap: 21,
                dotSize: 13,
                markerSize: 9,
                lineWidth: 1.5,
                nutWidth: 5,
                showsFingers: false,
                whiteKeyWidth: 17,
                whiteKeyHeight: 60,
                nameSpacing: 6,
            )
        }
    }
}

/// The chord name above a diagram: chord symbols are 700 in `cueText` (brand.md section 6).
struct DiagramNameLabel: View {
    let name: String
    let metrics: DiagramMetrics

    var body: some View {
        Text(name)
            .font(SchibstedGrotesk.bold.font(size: metrics.nameSize))
            .foregroundStyle(Theme.color.cueText)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .fixedSize(horizontal: false, vertical: true)
    }
}
