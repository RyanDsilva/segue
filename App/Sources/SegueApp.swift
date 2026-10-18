import Plugins
import SegueUI
import Services
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
        let ids = ULIDGenerator(clock: clock)
        #if DEBUG
            // Test-only launch arguments are honoured in Debug builds only.
            let options = LaunchOptions(arguments: ProcessInfo.processInfo.arguments)
            let dependencies = options.dependencies(
                fileSystem: options.fileSystem,
                clock: clock,
                ids: ids,
                real: Self.realLiveDependencies,
            )
        #else
            // Release never lets the command line redirect the library or wipe state, and
            // has no test hooks compiled in (WS1 4.8f).
            let services = ServicesWiring.release(defaults: .standard)
            let dependencies = AppDependencies(
                fileSystem: LiveFileSystem(),
                clock: clock,
                ids: ids,
                location: LibraryLocation(defaults: .standard),
                shapeLibraryURL: Self.realShapeLibraryURL,
                live: Self.realLiveDependencies(defaults: .standard),
                hooks: Self.hooks,
                services: services.services,
                consent: services.consent,
                diagnosticLog: services.log,
                flavor: Self.flavor,
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
            shortcuts: AppleEventShortcutRunner(),
            scrollClock: MonotonicClock(),
            bindingsURL: Bundle.main.bundleIdentifier.map(LiveDependencies.defaultBindingsURL),
        )
    }

    /// The menu hooks (WS2a 3.5.6). WS2b fills `showWelcome`, `showWhatsNew` and
    /// `exportArchive`; WS3 fills `reportProblem` and `requestFeature`. Until then the
    /// defaults fall back to the web and mail, and the optional items stay hidden.
    @MainActor
    static var hooks: AppHooks {
        AppHooks()
    }

    /// `Segue.App.launched`'s flavour (Personal also reports to its own TelemetryDeck app).
    static var flavor: AppFlavor {
        #if SEGUE_PERSONAL
            .personal
        #else
            .appStore
        #endif
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
        // One main window (A32, I-11): Window > Segue Library (Cmd-0) brings it back after
        // it was closed, instead of a second copy. The title bar shows the view's title.
        // Spike 0d: SwiftUI lists no Window menu item for it once it is closed, so the
        // scene's own commands are removed and `WindowCommands` provides the one item.
        Window("Segue Library", id: SegueRootView.windowID) {
            SegueRootView(app: app)
                .frame(minWidth: 820, minHeight: 520)
        }
        .defaultSize(width: 1120, height: 720)
        .commandsRemoved()
        .commands { SegueCommands(app: app) }

        Window("Keyboard Shortcuts", id: KeyboardShortcutsWindow.id) {
            KeyboardShortcutsWindowContent(app: app)
                .frame(minWidth: 560, idealWidth: 620, minHeight: 520, idealHeight: 720)
        }
        .defaultSize(width: 620, height: 720)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
        .commandsRemoved()

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
