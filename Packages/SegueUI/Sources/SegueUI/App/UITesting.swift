import Foundation

/// Whether the app runs under the XCUITest suite (`-SegueUITesting YES`, Debug builds only).
/// Test-only instrumentation (keystroke timings, input-settings report) exists only then, so
/// release users and VoiceOver never meet it.
/// The flag string itself is compiled into Debug builds only (WS1 4.8f).
public enum UITesting {
    #if DEBUG
        public static let launchArgument = "-SegueUITesting"
    #endif

    public static let isActive: Bool = {
        #if DEBUG
            UserDefaults.standard.bool(forKey: String(launchArgument.dropFirst()))
        #else
            false
        #endif
    }()
}
