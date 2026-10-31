#if os(macOS)
    import SwiftUI

    /// Song (P8-6 10.3): Play Along opens or closes the Play along bar of the editor, or of
    /// the library's song pane. Never on stage (Rehearsal play-along is `P`). Insert puts a
    /// key, time or tempo change at the editor's cursor line or selected band (P8-7 6.1).
    struct SongCommands: Commands {
        let app: AppModel

        var body: some Commands {
            CommandMenu("Song") {
                Button(MenuShortcuts.playAlong.title) {
                    guard let playAlong = app.menuPlayAlong else { return }
                    playAlong.setOpen(!playAlong.isOpen)
                }
                .keyboardShortcut(MenuShortcuts.playAlong)
                .disabled(app.menuPlayAlong == nil)
                Menu("Insert") {
                    ForEach(ChartDirective.allCases) { directive in
                        Button(directive.insertTitle) {
                            app.menuEditor?.beginDirectiveInsert(directive)
                        }
                    }
                }
                .disabled(app.menuEditor == nil)
            }
        }
    }

    extension AppModel {
        /// The open editor Song > Insert acts on (P8-7 section 6.1); nil on stage.
        var menuEditor: SongEditorViewModel? {
            guard let session, !isPerforming else { return nil }
            return session.library.editor
        }

        /// The Play along bar a menu command acts on: the open editor's, else the library
        /// pane's when it shows a song; nil on stage, during a gig or without sound.
        var menuPlayAlong: PlayAlong? {
            guard let session, !isPerforming, sound.isAvailable else { return nil }
            let library = session.library
            if let editor = library.editor {
                return editor.playAlong
            }
            guard session.section == .library || session.section == nil,
                  case .song = library.detail
            else { return nil }
            return library.playAlong
        }
    }
#endif
