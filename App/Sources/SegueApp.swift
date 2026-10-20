import FoundationModelsAdapter
import MLXAdapter
import MLXEngine
import ModelPort
import ModelStore
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
            var dependencies = options.dependencies(
                fileSystem: options.fileSystem,
                clock: clock,
                ids: ids,
                real: Self.realLiveDependencies,
            )
        #else
            // Release never lets the command line redirect the library or wipe state, and
            // has no test hooks compiled in (WS1 4.8f).
            let services = ServicesWiring.release(defaults: .standard)
            let polish = PolishDependencies(defaults: .standard)
            var dependencies = AppDependencies(
                fileSystem: LiveFileSystem(),
                clock: clock,
                ids: ids,
                location: LibraryLocation(defaults: .standard),
                shapeLibraryURL: Self.realShapeLibraryURL,
                live: Self.realLiveDependencies(defaults: .standard),
                hooks: polish.router.filling(services.hooks),
                services: services.services,
                consent: services.consent,
                diagnosticLog: services.log,
                flavor: Self.flavor,
                reportPresenter: services.reportPresenter,
                diagnostics: services.diagnostics,
                polish: polish,
            )
        #endif
        // On-device AI (P3-2, P3-3): the local MLX model when installed, else Apple Foundation
        // Models. A test run gets no providers, so every AI call keeps its deterministic result
        // and no UI test depends on a model, and a scripted model store, so no test touches
        // the network or the real shared store.
        #if DEBUG
            let aiDefaults = AppStateReset.defaults(
                for: options,
                bundleID: Bundle.main.bundleIdentifier,
            )
            dependencies.ai = options.isTestRun
                ? Self.testRunAI(defaults: aiDefaults) : Self.liveAI(defaults: aiDefaults)
        #else
            dependencies.ai = Self.liveAI(defaults: .standard)
        #endif
        // Settings > Appearance (R36) applies before the first window draws; TipKit is
        // configured before any tip view exists (WS2b 4.4).
        dependencies.polish.appearance.apply()
        SegueTips.configure(
            launch: dependencies.polish.launch,
            preferences: dependencies.polish.preferences,
        )
        _app = State(initialValue: AppModel(dependencies: dependencies))
    }

    /// The AI a real launch routes to (R63): the installed local MLX model, then Apple
    /// Foundation Models, then the deterministic converter. The model store is the app-group
    /// store both flavours share (R67, R100); custom models only in Personal (R62).
    @MainActor
    static func liveAI(defaults: UserDefaults) -> AIServices {
        let gate = AIGate()
        let store = ModelStore(
            location: .appGroup(),
            options: .init(
                appVersion: Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString",
                ) as? String ?? "0",
                allowsCustomModels: flavor == .personal,
                activeModel: .userDefaults(),
            ),
        )
        let curated = ModelStore.curatedCatalog.first?.ref
        let mlx = MLXProvider(
            engine: MLXGuidedEngine(),
            resolver: store,
            defaultModel: curated ?? ModelRef(repo: "", revision: ""),
            isShowRunning: { gate.isShowRunning },
        )
        return AIServices(
            providers: [mlx, FoundationModelsProvider()],
            gate: gate,
            defaults: defaults,
            installer: store,
        )
    }

    #if DEBUG
        /// Test runs (E2E): no providers, and the curated catalog behind a scripted store
        /// whose Download walks to installed without any network (spec 14).
        @MainActor
        static func testRunAI(defaults: UserDefaults) -> AIServices {
            AIServices(
                providers: [],
                defaults: defaults,
                installer: ScriptedModelInstaller(models: ModelStore.curatedCatalog),
            )
        }
    #endif

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

        Settings {
            SegueSettingsView(app: app)
        }
    }
}
