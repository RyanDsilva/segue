#if os(macOS)
    import AppKit
    import Library
    import SwiftUI

    /// The inline bar at the top of the editor when an autosave found the song changed in
    /// another app (WS2a 3.4, A19). Nothing is written until the user picks; typing goes on.
    struct SaveConflictBar: View {
        let conflict: LibraryViewModel.SaveConflict
        let resolve: (LibraryViewModel.SaveConflictChoice) -> Void

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .accessibilityHidden(true)
                Text(message)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                buttons
                    .controlSize(.small)
            }
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .bottom) { Hairline() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(message)
            .accessibilityIdentifier(AccessibilityID.editorConflictBar)
        }

        private var message: String {
            let title = conflict.songTitle
            return switch conflict.kind {
            case .sourceChanged:
                "“\(title)” was changed in another app. Your edits are not saved."
            case .deleted:
                "“\(title)” was deleted in another app. Your edits are not saved."
            case .metadataChanged:
                "The details of “\(title)” were changed in another app. "
                    + "Your edits are not saved."
            }
        }

        @ViewBuilder private var buttons: some View {
            switch conflict.kind {
            case .sourceChanged:
                reload
                Button(uiString("Overwrite")) { resolve(.overwrite) }
                    .buttonStyle(.segueSecondary)
                    .help(uiString("Replace the other app’s version with your edits"))
                    .accessibilityIdentifier(AccessibilityID.editorConflictOverwrite)
                copy("Save as Copy")
            case .deleted:
                copy("Save as New Song")
            case .metadataChanged:
                reload
                copy("Save as Copy")
            }
        }

        private var reload: some View {
            Button(uiString("Reload")) { resolve(.reload) }
                .buttonStyle(.segueSecondary)
                .help(uiString("Show the song as it is now; your edits are dropped"))
                .accessibilityIdentifier(AccessibilityID.editorConflictReload)
        }

        private func copy(_ title: String) -> some View {
            Button(title) { resolve(.saveAsCopy) }
                .buttonStyle(.seguePrimary)
                .help(uiString("Keep the other version and save your edits as a new song"))
                .accessibilityIdentifier(AccessibilityID.editorConflictCopy)
        }
    }

    /// Sets the hosting window's edited dot (`NSWindow.isDocumentEdited`).
    struct WindowDocumentEdited: NSViewRepresentable {
        let isEdited: Bool

        func makeNSView(context _: Context) -> NSView {
            NSView()
        }

        func updateNSView(_ view: NSView, context _: Context) {
            let isEdited = isEdited
            // After layout: the view may not be in its window yet on first update.
            DispatchQueue.main.async {
                view.window?.isDocumentEdited = isEdited
            }
        }

        static func dismantleNSView(_ view: NSView, coordinator _: ()) {
            view.window?.isDocumentEdited = false
        }
    }
#endif
