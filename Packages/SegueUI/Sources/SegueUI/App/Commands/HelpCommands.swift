#if os(macOS)
    import SwiftUI

    /// The Help menu (WS2a 3.5.6, I-5): the canonical list, in order, with exact names. WS2b
    /// and WS3 never edit it; they fill `AppHooks`. Welcome to Segue… is hidden until its hook
    /// is set, Rate Segue on the App Store until `SegueLinks.appStoreID` is.
    struct HelpCommands: Commands {
        let app: AppModel
        @Environment(\.openWindow) private var openWindow

        private var workspace: any WorkspaceActions {
            app.dependencies.workspace
        }

        private var hooks: AppHooks {
            app.dependencies.hooks
        }

        var body: some Commands {
            CommandGroup(replacing: .help) {
                Button(MenuShortcuts.help.title) { workspace.open(SegueLinks.help) }
                    .keyboardShortcut(MenuShortcuts.help)
                Button(MenuShortcuts.keyboardShortcuts.title) {
                    openWindow(id: KeyboardShortcutsWindow.id)
                }
                .keyboardShortcut(MenuShortcuts.keyboardShortcuts)
                if let showWelcome = hooks.showWelcome {
                    Button("Welcome to Segue…") { showWelcome(workspace) }
                        .disabled(app.isPerforming)
                }
                Button("What's New in Segue") { hooks.showWhatsNew(workspace) }
                    .disabled(app.isPerforming)
                Divider()
                Button("Report a Problem…") { hooks.reportProblem(workspace) }
                Button("Request a Feature…") { hooks.requestFeature(workspace) }
                if let review = SegueLinks.writeReview {
                    Button("Rate Segue on the App Store") { workspace.open(review) }
                }
                Divider()
                Button("Privacy Policy") { workspace.open(SegueLinks.privacy) }
                Button("Terms of Use") { workspace.open(SegueLinks.terms) }
                Button("Acknowledgements") { openWindow(id: AcknowledgementsWindow.id) }
            }
        }
    }
#endif
