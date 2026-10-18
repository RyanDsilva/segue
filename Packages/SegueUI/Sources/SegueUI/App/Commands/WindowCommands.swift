#if os(macOS)
    import SwiftUI

    /// Window > Segue Library (Cmd-0) (WS2a 3.5.5, A32, review risk F2): brings back the one
    /// main window after it was closed. Spike 0d found SwiftUI lists no item for a closed
    /// `Window` scene, so the scene's own commands are removed and this is the only one.
    struct WindowCommands: Commands {
        @Environment(\.openWindow) private var openWindow

        var body: some Commands {
            CommandGroup(before: .windowList) {
                Button(MenuShortcuts.mainWindow.title) {
                    openWindow(id: SegueRootView.windowID)
                }
                .keyboardShortcut(MenuShortcuts.mainWindow)
                Divider()
            }
        }
    }
#endif
