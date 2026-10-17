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
        let options = Self.launchOptions
        let defaults = AppStateReset.defaults(for: options, bundleID: Bundle.main.bundleIdentifier)
        if options.resetState {
            AppStateReset.wipeTestState(defaults, bundleID: Bundle.main.bundleIdentifier)
        }
        plugins = PluginRegistry()
        plugins.registerAll(Self.pluginModules)

        let clock = SystemClock()
        let dependencies = AppDependencies(
            fileSystem: LiveFileSystem(),
            clock: clock,
            ids: ULIDGenerator(clock: clock),
            location: LibraryLocation(defaults: defaults),
            libraryOverride: options.libraryPath,
            rememberLibraryOverride: options.rememberLibrary,
            shapeLibraryURL: Self.shapeLibraryURL(options),
            live: Self.liveDependencies(options, defaults: defaults),
        )
        _app = State(initialValue: AppModel(dependencies: dependencies))
    }

    /// Test-only launch arguments are honoured in Debug builds only; Release builds never
    /// let the command line redirect the library or wipe state.
    private static var launchOptions: LaunchOptions {
        #if DEBUG
            LaunchOptions(arguments: ProcessInfo.processInfo.arguments)
        #else
            LaunchOptions()
        #endif
    }

    /// The user's chord shape library: Application Support, or only the explicit test file
    /// in a test run.
    private static func shapeLibraryURL(_ options: LaunchOptions) -> URL? {
        if options.isTestRun {
            return options.shapeLibraryPath
        }
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        return AppDependencies.defaultShapeLibraryURL(bundleID: bundleID)
    }

    /// Live mode: the real Shortcut runner, system clock and Application Support bindings,
    /// or the test doubles a test run asks for.
    @MainActor
    private static func liveDependencies(_ options: LaunchOptions, defaults: UserDefaults)
        -> LiveDependencies
    {
        let settings = LiveSettingsStore(defaults: defaults)
        let shortcuts: any ShortcutRunner = options.shortcutLog.map(RecordingShortcutRunner.init)
            ?? WorkspaceShortcutRunner()
        let scrollClock: any Clock = options.liveTimeScale.map { ScaledClock(scale: $0) }
            ?? SystemClock()
        let bindings: URL? = if options.isTestRun {
            options.bindingsPath
        } else {
            Bundle.main.bundleIdentifier.map(LiveDependencies.defaultBindingsURL)
        }
        return LiveDependencies(
            settings: settings,
            shortcuts: shortcuts,
            scrollClock: scrollClock,
            bindingsURL: bindings,
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
