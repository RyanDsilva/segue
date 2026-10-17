import Foundation

/// Whether the app runs under the XCUITest suite (`-SegueUITesting YES`, Debug builds only).
/// Test-only instrumentation (keystroke timings, input-settings report) exists only then, so
/// release users and VoiceOver never meet it.
public enum UITesting {
    public static let launchArgument = "-SegueUITesting"

    public static let isActive: Bool = {
        #if DEBUG
            UserDefaults.standard.bool(forKey: String(launchArgument.dropFirst()))
        #else
            false
        #endif
    }()
}
