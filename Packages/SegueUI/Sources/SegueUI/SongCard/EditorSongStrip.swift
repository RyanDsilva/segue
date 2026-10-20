#if os(macOS)
    import ChordPro
    import Editing
    import Library
    import SwiftUI

    /// The song card while the editor is open (direction 2): the token strip under the top
    /// bar. Its edits go through the editor's own `perform`, the path the top bar's capo
    /// stepper uses, so both stay in sync and share one undo stack and the autosave. A new
    /// song (Start blank) shows the expanded card with Title and Artist for the whole
    /// session: collapsing it when the first autosave lands would jump the text under the
    /// caret.
    struct EditorSongStrip: View {
        let model: SongEditorViewModel
        @State private var standIn = SongID.standIn()

        var body: some View {
            SongCardView(
                host: SongCardHost(
                    document: document,
                    songID: songID,
                    perform: { _ = model.perform($0) },
                ),
                layout: model.startedAsNew ? .expanded : .strip,
            )
            .environment(\.analyticsContext, .editor)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rule() }
        }

        /// The song as it is now. Reading `renderModel` (observed, rebuilt after every
        /// edit) makes the strip follow the text; the snapshot itself is current.
        private var document: SongDocument {
            _ = model.renderModel
            return model.snapshot.document
        }

        private var songID: SongID {
            if case let .edit(id) = model.mode {
                return id
            }
            return standIn
        }
    }
#endif
