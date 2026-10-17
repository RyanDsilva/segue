#if os(macOS)
    import SwiftUI

    /// Raw ChordPro editor (monospaced, no autocorrect) with the rendered preview below.
    struct SongEditorView: View {
        @Bindable var model: SongEditorViewModel
        var onSave: () -> Void
        var onCancel: () -> Void

        var body: some View {
            VSplitView {
                editor
                    .frame(minHeight: 160, idealHeight: 320)
                preview
                    .frame(minHeight: 140, idealHeight: 280)
            }
            .navigationTitle(model.mode == .create ? "New Song" : "Edit Song")
            .toolbar {
                // The detail column's toolbar packs items at its leading edge; the flexible
                // spacer pushes the actions to the trailing end, where macOS puts them.
                ToolbarSpacer(.flexible)
                ToolbarItem(placement: .automatic) {
                    HStack(spacing: 8) {
                        Button("Cancel", role: .cancel, action: onCancel)
                            .keyboardShortcut(.cancelAction)
                            .buttonStyle(.segueSecondary)
                            .accessibilityIdentifier(AccessibilityID.editorCancel)
                        Button("Save", action: onSave)
                            .keyboardShortcut("s", modifiers: .command)
                            .buttonStyle(.seguePrimary)
                            .disabled(!model.canSave)
                            .accessibilityIdentifier(AccessibilityID.editorSave)
                    }
                    .controlSize(.regular)
                    // Without the shared glass capsule the toolbar gives no trailing inset.
                    .padding(.trailing, 6)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }

        private var editor: some View {
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    ChordProTextView(
                        text: $model.source,
                        accessibilityIdentifier: AccessibilityID.editorText,
                        accessibilityLabel: "ChordPro source",
                    )
                    if model.source.isEmpty {
                        Text(SongEditorViewModel.placeholder)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            // Matches the text view's container inset and line fragment padding.
                            .padding(.horizontal, 17)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                statusBar
            }
            .background(Color(nsColor: .textBackgroundColor))
        }

        @ViewBuilder private var statusBar: some View {
            let message = model.errorMessage ?? diagnosticsSummary
            if let message {
                Divider()
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(model.errorMessage == nil ? Color.secondary : Color.red)
                    .symbolRenderingMode(.multicolor)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .accessibilityIdentifier(AccessibilityID.editorError)
            }
        }

        private var diagnosticsSummary: String? {
            guard let first = model.diagnostics.first else { return nil }
            let more = model.diagnostics.count > 1
                ? " (+\(model.diagnostics.count - 1) more)"
                : ""
            return "Line \(first.line), column \(first.column): \(first.message)\(more)"
        }

        private var preview: some View {
            ScrollView {
                // Same insets as the song detail page, so saving doesn't shift the layout.
                SongPageView(document: model.document)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 28)
            }
            .background(Theme.color.ground)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.editorPreview)
        }
    }
#endif
