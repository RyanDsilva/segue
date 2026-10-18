#if os(macOS)
    import SwiftUI

    /// Library (WS2a 3.5.4): Refresh, Rebuild Index, Show Library in Finder, Choose Library
    /// Folder….
    struct LibraryCommands: Commands {
        let app: AppModel

        var body: some Commands {
            CommandMenu("Library") {
                Button(MenuShortcuts.refresh.title) {
                    guard let session = app.session else { return }
                    Task { await session.refreshFromDisk() }
                }
                .keyboardShortcut(MenuShortcuts.refresh)
                .disabled(app.session == nil || app.isPerforming)
                Button("Rebuild Index") {
                    guard let session = app.session else { return }
                    Task { await session.library.rebuildIndex() }
                }
                .disabled(app.session == nil || app.isPerforming)
                Divider()
                Button("Show Library in Finder") { app.session?.revealLibrary() }
                    .disabled(app.session == nil)
                Button("Choose Library Folder…") {
                    let choose = { Task { await app.chooseLibrary() } }
                    if let session = app.session {
                        session.library.navigate { _ = choose() }
                    } else {
                        _ = choose()
                    }
                }
                // The show belongs to the open library: end it before switching.
                .disabled(!app.canSwitchLibrary)
                .help(app.canSwitchLibrary ? "" : "End the show before switching libraries.")
            }
        }
    }
#endif
