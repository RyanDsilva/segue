// Owner: unit B (diagram views). Frozen interface: docs/phases/1-interfaces.md.

import Diagrams
import Editing
import SwiftUI

/// All unique chords of the song, in order of first appearance, for one instrument.
/// Reads `RenderModel.diagrams`; chords without a diagram show their name only.
struct DiagramStrip: View {
    let diagrams: [RenderDiagram]
    let instrument: Instrument
    let tuning: Tuning
    var size: DiagramSize = .compact
    /// Called when the user picks a chord's diagram to customise it (editor only).
    var onCustomize: ((RenderDiagram) -> Void)?

    var body: some View {
        ScrollView(.horizontal) {
            DiagramStripContent(
                diagrams: diagrams,
                instrument: instrument,
                tuning: tuning,
                size: size,
                onCustomize: onCustomize,
            )
        }
        .scrollIndicators(.automatic)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.diagramStrip)
    }
}

/// The strip's row of cells, without the scroll view (also rendered directly by the
/// snapshot tests, since `ImageRenderer` does not draw scroll views).
struct DiagramStripContent: View {
    let diagrams: [RenderDiagram]
    let instrument: Instrument
    let tuning: Tuning
    let size: DiagramSize
    let onCustomize: ((RenderDiagram) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(diagrams) { diagram in
                cell(for: diagram)
            }
        }
        .padding(.horizontal, spacing / 2)
        .padding(.vertical, 4)
    }

    private var spacing: CGFloat {
        switch size {
        case .compact: 12
        case .regular: 16
        case .stage: 24
        }
    }

    @Environment(\.chordHearing) private var hearing

    @ViewBuilder
    private func cell(for diagram: RenderDiagram) -> some View {
        if let hearing, let bass = diagram.bass {
            // A bass cell plays its note, ⌥-click the chord with it (P8-6 10.1).
            Button {
                DiagramCellSound.play(diagram, bass: bass, hearing: hearing)
            } label: {
                DiagramStripCell(
                    diagram: diagram,
                    instrument: instrument,
                    tuning: tuning,
                    size: size,
                )
            }
            .buttonStyle(DiagramCellButtonStyle())
            .disabled(!hearing.isEnabled)
            .help(hearing.isEnabled ? "Play \(bass.note); ⌥-click plays \(bass.chordName)"
                : SoundGate.offHelp)
            .accessibilityAction(named: "Play chord \(bass.chordName)") {
                hearing.playConcert(bass.chordName)
            }
        } else if let onCustomize, diagram.bass == nil {
            Button {
                // ⌥-click plays the chord (P8-6 10.1); a plain click customises it.
                if let hearing, hearing.isEnabled, NSEvent.modifierFlags.contains(.option) {
                    hearing.playConcert(diagram.concertName)
                } else {
                    onCustomize(diagram)
                }
            } label: {
                DiagramStripCell(
                    diagram: diagram,
                    instrument: instrument,
                    tuning: tuning,
                    size: size,
                )
            }
            .buttonStyle(DiagramCellButtonStyle())
            .help("Customize \(diagram.name)")
            .contextMenu {
                Button("Customize Shape…") {
                    onCustomize(diagram)
                }
            }
        } else {
            DiagramStripCell(diagram: diagram, instrument: instrument, tuning: tuning, size: size)
        }
    }
}

/// One chord in the strip: its diagram for the instrument, or its name alone.
private struct DiagramStripCell: View {
    let diagram: RenderDiagram
    let instrument: Instrument
    let tuning: Tuning
    let size: DiagramSize

    var body: some View {
        if let bass = diagram.bass {
            // The bassist's fretboard (P8-4b section 7.2): no customise action for bass.
            BassFretboardView(diagram: bass, size: size)
        } else {
            instrumentCell
        }
    }

    @ViewBuilder private var instrumentCell: some View {
        switch (instrument, diagram.guitar, diagram.piano) {
        case let (.guitar, guitar?, _):
            GuitarDiagramView(
                name: diagram.name,
                shape: guitar.shape,
                tuning: tuning,
                capoFret: diagram.capoFret,
                size: size,
            )
        case let (.piano, _, piano?):
            // Piano diagrams are always concert pitch, so they carry the concert name.
            PianoDiagramView(name: diagram.concertName, voicing: piano, size: size)
        default:
            NameOnlyDiagram(
                name: instrument == .piano ? diagram.concertName : diagram.name,
                size: size,
            )
        }
    }
}

/// A chord with no diagram (unknown to the generator): the name over an empty frame.
private struct NameOnlyDiagram: View {
    let name: String
    let size: DiagramSize

    var body: some View {
        let metrics = DiagramMetrics.forSize(size)
        VStack(spacing: metrics.nameSpacing) {
            DiagramNameLabel(name: name, metrics: metrics)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Theme.color.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: metrics.stringGap * 5, height: metrics.fretGap * 4)
                .overlay {
                    Text("No diagram")
                        .font(SchibstedGrotesk.semiBold.font(size: metrics.labelSize))
                        .foregroundStyle(Theme.color.muted)
                        .multilineTextAlignment(.center)
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), no diagram")
    }
}

/// Hover and press feedback for a customisable diagram, without a new colour.
private struct DiagramCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DiagramCellButton(configuration: configuration)
    }
}

private struct DiagramCellButton: View {
    let configuration: ButtonStyle.Configuration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.color.surfaceAlt
                        .opacity(isHovered || configuration.isPressed ? 1 : 0))
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// What a strip cell plays (P8-6 10.1).
@MainActor
enum DiagramCellSound {
    static func play(_ diagram: RenderDiagram, bass: BassDiagram, hearing: ChordHearing) {
        guard hearing.isEnabled else { return }
        if NSEvent.modifierFlags.contains(.option) {
            hearing.playConcert(bass.chordName)
        } else if let position = bass.suggested {
            hearing.playBass(BassFretboard.pitch(position, tuning: bass.tuning))
        }
    }
}
