#if os(macOS)
    import SwiftUI

    /// About Segue (WS2a 3.6) in place of the standard item.
    struct AppInfoCommands: Commands {
        var body: some Commands {
            CommandGroup(replacing: .appInfo) {
                Button(uiString("About Segue")) { AboutPanel.show() }
            }
        }
    }
#endif
