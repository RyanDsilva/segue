#if os(macOS)
    import AppKit
    import Library
    import Services

    // P3-4 entry points that need the app: the clipboard (read only when the user asks), the
    // stage-focus guard (R109: nothing about paste or import may disturb the live view) and
    // Settings > AI for the review sheet's quiet download link (R93).

    public extension AppModel {
        /// The stage window has the keyboard: library commands that would open a panel or a
        /// sheet, or move the main window, do nothing (the stage keeps its focus).
        var isStageKey: Bool {
            guard isPerforming, let stage = StageWindowController.shared.stageWindow else {
                return false
            }
            return NSApp.keyWindow === stage
        }

        /// File > New Song (R83): the paste flow's input state; during a show, Start blank.
        func newSong() {
            guard let session, !isStageKey else { return }
            if session.section == .library {
                session.library.beginNewSongFlow()
            } else {
                session.library.navigate {
                    session.section = .library
                    session.library.beginNewSongFlow()
                }
            }
        }

        /// File > New Song from Clipboard (R75): the review sheet on the clipboard's text.
        /// The clipboard is read here, when the user asked, and never before.
        func newSongFromClipboard(source: PasteSource = .clipboard) {
            guard let session, session.library.canPaste else { return }
            guard let text = Self.clipboardText(), !text.isEmpty else {
                session.library.flash("The clipboard has no text to paste")
                return
            }
            let open = { session.library.beginPasteReview(text: text, source: source) }
            if session.section == .library {
                open()
            } else {
                session.library.navigate {
                    session.section = .library
                    open()
                }
            }
        }

        /// File > Import from Web Page… (P9-4 spec 11.1, Personal build only): the New Song
        /// sheet with the web field focused.
        func importFromWebPage() {
            openLibrary { $0.beginWebImport() }
        }

        /// File > Find Lyrics… (P9-4 spec 6.4, Personal build only).
        func findLyrics() {
            openLibrary { $0.beginSongSearch() }
        }

        /// Runs `action` on the library, switching to it first (never while the stage has
        /// the keyboard, R109).
        private func openLibrary(_ action: @escaping (LibraryViewModel) -> Void) {
            guard let session, !isStageKey, session.library.canPaste else { return }
            if session.section == .library {
                action(session.library)
            } else {
                session.library.navigate {
                    session.section = .library
                    action(session.library)
                }
            }
        }

        /// The general pasteboard's plain text.
        static func clipboardText() -> String? {
            NSPasteboard.general.string(forType: .string)
        }

        /// Opens Settings on the AI pane (the review sheet's download link, the Welcome card).
        func selectAISettingsPane() {
            polish.preferences.selectedPane = SegueSettingsView.Pane.ai.rawValue
        }
    }
#endif
