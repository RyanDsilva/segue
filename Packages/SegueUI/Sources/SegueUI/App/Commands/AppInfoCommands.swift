#if os(macOS)
    import SwiftUI

    /// About Segue (WS2a 3.6) in place of the standard item; Acknowledgements moved to Help.
    struct AppInfoCommands: Commands {
        var body: some Commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Segue") { AboutPanel.show() }
            }
        }
    }
#endif
