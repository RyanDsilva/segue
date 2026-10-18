import Plugins
import SegueUI
import Support
import SwiftUI
#if SEGUE_PERSONAL
    import SeguePersonalModules
#endif

/// App entry point. Kept thin: parse launch options, register plugins, wire dependencies,
/// declare scenes. Everything else lives in SegueUI / SegueCore.
@main
struct SegueApp: App {
    /// Asks before quitting with unsaved edits.
    @NSApplicationDelegateAdaptor(SegueAppDelegate.self) private var appDelegate
    @State private var app: AppModel
    private let plugins: PluginRegistry

    init() {
        Theme.registerFonts()
        plugins = PluginRegistry()
        plugins.registerAll(Self.pluginModules)

        let clock = SystemClock()
        let fileSystem = LiveFileSystem()
        let ids = ULIDGenerator(clock: clock)
        #if DEBUG
            // Test-only launch arguments are honoured in Debug builds only.
            let options = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)
            let dependencies = options.dependencies(
                fileSystem: fileSystem,
                clock: clock,
                ids: ids,
                real: Self.realLiveDependencies,
            )
        #else
            // Release never lets the command line redirect the library or wipe state, and
            // has no test hooks compiled in (WS1 4.8f).
            let dependencies = AppDependencies(
                fileSystem: fileSystem,
                clock: clock,
                ids: ids,
                location: LibraryLocation(defaults: .standard),
                shapeLibraryURL: Self.realShapeLibraryURL,
                live: Self.realLiveDependencies(defaults: .standard),
            )
        #endif
        _app = State(initialValue: AppModel(dependencies: dependencies))
    }

    /// The user's chord shape library in Application Support.
    static var realShapeLibraryURL: URL? {
        Bundle.main.bundleIdentifier.map(AppDependencies.defaultShapeLibraryURL)
    }

    /// Live mode with the real Shortcut runner, system clock and Application Support bindings.
    @MainActor
    static func realLiveDependencies(defaults: UserDefaults) -> LiveDependencies {
        LiveDependencies(
            settings: LiveSettingsStore(defaults: defaults),
            shortcuts: WorkspaceShortcutRunner(),
            scrollClock: MonotonicClock(),
            bindingsURL: Bundle.main.bundleIdentifier.map(LiveDependencies.defaultBindingsURL),
        )
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
        WindowGroup(id: "segue.main") {
            SegueRootView(app: app)
                .frame(minWidth: 820, minHeight: 520)
        }
        .defaultSize(width: 1120, height: 720)
        .commands { SegueCommands(app: app) }

        Window("Acknowledgements", id: AcknowledgementsWindow.id) {
            AcknowledgementsView()
                .frame(minWidth: 480, idealWidth: 560, minHeight: 420, idealHeight: 640)
        }
        .defaultSize(width: 560, height: 640)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
        .commandsRemoved()

        Settings {
            SegueSettingsView(app: app)
        }
    }
}
