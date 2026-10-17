import Plugins

/// Entry point of the restricted personal-build plugins. Registered by the app only when
/// `SEGUE_PERSONAL` is defined. Phase 0: registers nothing.
public enum PersonalModules: PluginModule {
    public static func register(into registry: PluginRegistry) {
        _ = registry
    }
}
