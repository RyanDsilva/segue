import Plugins
import SegueUI
import SwiftUI
#if SEGUE_PERSONAL
    import SeguePersonalModules
#endif

/// App entry point. Kept thin: parse launch options, register plugins, wire dependencies,
/// declare scenes. Everything else lives in SegueUI / SegueCore.
@main
struct SegueApp: App {
    private let environment: AppEnvironment

    init() {
        let options = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)
        if options.resetState {
            AppStateReset.wipe(defaults: .standard, bundleID: Bundle.main.bundleIdentifier)
        }
        let plugins = PluginRegistry()
        plugins.registerAll(Self.pluginModules)
        environment = AppEnvironment(launchOptions: options, plugins: plugins)
    }

    /// Plugin modules for this flavor. Only the Personal build sees the personal package.
    private static var pluginModules: [any PluginModule.Type] {
        #if SEGUE_PERSONAL
            [PersonalModules.self]
        #else
            []
        #endif
    }

    var body: some Scene {
        WindowGroup {
            SegueRootView()
                .frame(minWidth: 640, minHeight: 400)
        }
    }
}

/// Process-wide dependencies built at launch. Later stages add the library and setlist
/// stores here (opened on `launchOptions.libraryPath` or the resolved bookmark).
struct AppEnvironment: Sendable {
    let launchOptions: LaunchOptions
    let plugins: PluginRegistry
}
