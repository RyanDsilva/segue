#if os(macOS)
    import Services
    import SwiftUI

    /// Song (P8-6 10.3): Play Along opens or closes the Play along bar of the editor, or of
    /// the library's song pane. Never on stage (Rehearsal play-along is `P`). Insert puts a
    /// key, time or tempo change at the editor's cursor line or selected band (P8-7 6.1). Singer
    /// Preview shows the previews lyrics only (P9-2 section 7).
    struct SongCommands: Commands {
        let app: AppModel

        /// Song > Singer Preview (P9-2 section 7): the previews' own toggle, never the
        /// stage's.
        private var singerPreview: Binding<Bool> {
            Binding(
                get: { app.previewPrefs.singer },
                set: { on in
                    guard let context = app.singerPreviewContext else { return }
                    app.previewPrefs.setSinger(on, from: context)
                },
            )
        }

        var body: some Commands {
            CommandMenu("Song") {
                Button(MenuShortcuts.playAlong.title) {
                    guard let playAlong = app.menuPlayAlong else { return }
                    playAlong.setOpen(!playAlong.isOpen)
                }
                .keyboardShortcut(MenuShortcuts.playAlong)
                .disabled(app.menuPlayAlong == nil)
                Button(MenuShortcuts.createBassFill.title) { app.createBassFill() }
                    .keyboardShortcut(MenuShortcuts.createBassFill)
                    .disabled(!app.canCreateBassFill)
                Toggle(MenuShortcuts.singerPreview.title, isOn: singerPreview)
                    .keyboardShortcut(MenuShortcuts.singerPreview)
                    .disabled(app.singerPreviewContext == nil)
                Menu(uiString("Insert")) {
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

        /// Song > Create Bass Fill... (P8-7 12.1): the open editor's span (preview, canvas or
        /// lane), else the library pane's; never on stage or during a gig.
        var canCreateBassFill: Bool {
            guard let session, !isPerforming, sound.isAvailable else { return false }
            if let editor = session.library.editor {
                return editor.canCreateFill
            }
            guard case .song = session.library.detail else { return false }
            return session.library.canCreateFill
        }

        func createBassFill() {
            guard canCreateBassFill, let session else { return }
            if let editor = session.library.editor {
                editor.createFillFromMenu()
            } else {
                session.library.createFillFromMenu()
            }
        }

        /// Where Song > Singer Preview acts: the open editor, else the library pane when it
        /// shows a song; nil on stage.
        var singerPreviewContext: FeatureContext? {
            guard let session, !isPerforming else { return nil }
            let library = session.library
            if library.editor != nil {
                return .editor
            }
            guard session.section == .library || session.section == nil,
                  case .song = library.detail
            else { return nil }
            return .library
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
