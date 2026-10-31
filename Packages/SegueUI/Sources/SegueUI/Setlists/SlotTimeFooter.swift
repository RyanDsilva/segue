#if os(macOS)
    import Library
    import Setlists
    import SwiftUI

    /// Arrange Sections' footer time (P8-8 section 5.5): "Time for this gig: 2:40" from the
    /// passes the draft plays (live as passes change), or "No tempo" with "Set Tempo..."
    /// (writes the song's `{tempo}`, not the setlist).
    struct SlotTimeFooter: View {
        let time: SlotTime
        let record: SongRecord
        let library: LibraryViewModel
        let isReadOnly: Bool
        @State private var isSettingTempo = false

        var body: some View {
            HStack(spacing: 8) {
                switch time {
                case .known:
                    Text("Time for this gig: \(time.clock)")
                        .monospacedDigit()
                        .help(time.help)
                        .accessibilityLabel("Time for this gig: \(time.spoken)")
                case .unknown(.noTempo):
                    Text("No tempo")
                    Button("Set Tempo…") { isSettingTempo = true }
                        .buttonStyle(.link)
                        .font(SchibstedGrotesk.semiBold.font(size: 12))
                        .help("Sets the song's tempo")
                        .disabled(isReadOnly || record.isReadOnly)
                        .accessibilityIdentifier(AccessibilityID.arrangementSetTempo)
                        .popover(isPresented: $isSettingTempo, arrowEdge: .top) {
                            InlineTempoField { text in
                                let problem = MissingTimesList.writeTempo(
                                    text,
                                    song: record.id,
                                    library: library,
                                )
                                if problem == nil {
                                    isSettingTempo = false
                                }
                                return problem
                            }
                            .padding(12)
                        }
                case .unknown(.noChords):
                    Text("No chords to time")
                }
            }
            .lineLimit(1)
            .fixedSize()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.arrangementTime)
        }
    }
#endif
