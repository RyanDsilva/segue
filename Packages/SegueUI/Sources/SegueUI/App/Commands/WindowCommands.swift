#if os(macOS)
    import SwiftUI

    /// Window > Segue Library (Cmd-0) (WS2a 3.5.5, A32, review risk F2): brings back the one
    /// main window after it was closed. Spike 0d found SwiftUI lists no item for a closed
    /// `Window` scene, so the scene's own commands are removed and this is the only one.
    /// Window > Singer Screen is P9-2c's.
    struct WindowCommands: Commands {
        let app: AppModel
        @Environment(\.openWindow) private var openWindow

        var body: some Commands {
            CommandGroup(before: .windowList) {
                Button(MenuShortcuts.mainWindow.title) {
                    openWindow(id: SegueRootView.windowID)
                }
                .keyboardShortcut(MenuShortcuts.mainWindow)
                singerScreen
                Divider()
            }
        }

        /// Window > Singer Screen (P9-2c 6.13): lyrics only on another display, facing the
        /// singer; again closes it. With three or more displays, a submenu names them.
        @ViewBuilder private var singerScreen: some View {
            let screen = SingerScreenController.shared
            let choices = screen.choices
            if choices.isEmpty || screen.isOpen {
                Toggle("Singer Screen", isOn: Binding(
                    get: { screen.isOpen },
                    set: { $0 ? screen.open(app) : screen.close() },
                ))
                .disabled(!screen.isOpen && !screen.canOpen(app))
                .help(screen.canOpen(app) || screen.isOpen
                    ? "Show the lyrics on another display, facing the singer"
                    : "Connect a second display to show a Singer Screen")
            } else {
                Menu("Singer Screen") {
                    ForEach(choices, id: \.name) { display in
                        Button(display.name) { screen.open(app, on: display) }
                    }
                }
                .disabled(!screen.canOpen(app))
            }
        }
    }
#endif
