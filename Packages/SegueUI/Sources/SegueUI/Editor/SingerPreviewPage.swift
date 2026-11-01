#if os(macOS)
    import Editing
    import SwiftUI

    extension SongEditorViewModel {
        /// Whether the previews show lyrics only (P9-2 section 7).
        var showsSingerPreview: Bool {
            preview?.singer == true
        }
    }

    /// The editor's Visual mode while the previews show singer view (P9-2 section 7): a slim
    /// bar that says why nothing can be typed, then the song as a singer sees it, read-only.
    /// Editing stays in the editor's own modes: Turn Off brings the canvas back.
    struct SingerPreviewPage: View {
        let model: SongEditorViewModel

        var body: some View {
            VStack(spacing: 0) {
                bar
                ScrollView {
                    if let chart = model.renderModel {
                        SongPageView(
                            model: SingerView.model(chart),
                            selectable: false,
                            onCustomize: { _ in },
                            showsDiagrams: false,
                            singer: true,
                        )
                        .environment(\.playAlongCue, model.playAlong?.cue)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .background(Theme.color.ground)
        }

        private var bar: some View {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "music.mic")
                    .foregroundStyle(Theme.color.muted)
                    .accessibilityHidden(true)
                Text("Singer preview: chords are hidden. Turn off Singer to edit chords.")
                    .font(SchibstedGrotesk.medium.font(size: 13))
                    .foregroundStyle(Theme.color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button("Turn Off") { model.preview?.setSinger(false, from: .editor) }
                    .buttonStyle(.segueSecondary)
                    .controlSize(.small)
                    .accessibilityIdentifier(AccessibilityID.editorSingerTurnOff)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(Theme.color.surfaceAlt)
            .overlay(alignment: .bottom) { Hairline() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.editorSingerBar)
        }
    }
#endif
