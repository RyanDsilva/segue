import Foundation

/// Test-only launch arguments (used by XCUITests to start from a clean baseline):
///
/// - `-SegueLibraryPath <path>`: use `<path>` as the library folder, bypassing the open panel
///   and the stored bookmark.
/// - `-SegueResetState YES`: wipe UserDefaults (including the library bookmark) at launch.
/// - `-SegueRememberLibrary YES`: also store `-SegueLibraryPath` as the library bookmark (in
///   the test defaults suite), as if the user had chosen it in the open panel.
/// - `-SegueTestDefaults YES`: use the test defaults suite without any other override, so a
///   relaunch opens the library from the bookmark stored by an earlier test launch.
/// - `-SegueShapeLibraryPath <file>`: read the user chord shape library from `<file>`. Test
///   runs without it use no shape library, so they never see the user's real shapes.
/// - `-SegueShortcutLog <file>`: never open Shortcuts; record each Shortcut the app would run
///   as one line in `<file>` (live-mode E2E #9).
/// - `-SegueLiveTimeScale <n>`: auto-scroll runs `n` times faster than real time (E2E #3).
/// - `-SegueBindingsPath <file>`: read key bindings from `<file>` instead of Application
///   Support. Test runs without it use the default keys only.
struct LaunchOptions: Sendable, Equatable {
    static let libraryPathFlag = "-SegueLibraryPath"
    static let resetStateFlag = "-SegueResetState"
    static let rememberLibraryFlag = "-SegueRememberLibrary"
    static let testDefaultsFlag = "-SegueTestDefaults"
    static let shapeLibraryPathFlag = "-SegueShapeLibraryPath"
    static let shortcutLogFlag = "-SegueShortcutLog"
    static let liveTimeScaleFlag = "-SegueLiveTimeScale"
    static let bindingsPathFlag = "-SegueBindingsPath"

    var libraryPath: URL?
    var resetState = false
    var rememberLibrary = false
    var testDefaults = false
    var shapeLibraryPath: URL?
    var shortcutLog: URL?
    var liveTimeScale: Double?
    var bindingsPath: URL?

    init(
        libraryPath: URL? = nil,
        resetState: Bool = false,
        rememberLibrary: Bool = false,
        testDefaults: Bool = false,
        shapeLibraryPath: URL? = nil,
        shortcutLog: URL? = nil,
        liveTimeScale: Double? = nil,
        bindingsPath: URL? = nil,
    ) {
        self.libraryPath = libraryPath
        self.resetState = resetState
        self.rememberLibrary = rememberLibrary
        self.testDefaults = testDefaults
        self.shapeLibraryPath = shapeLibraryPath
        self.shortcutLog = shortcutLog
        self.liveTimeScale = liveTimeScale
        self.bindingsPath = bindingsPath
    }

    /// Parses `arguments` (as in `ProcessInfo.arguments`; the first element is the
    /// executable). Unknown arguments are ignored; a flag without a value is ignored.
    init(arguments: [String]) {
        // Every flag takes one value: collect the last value given for each.
        var values: [String: String] = [:]
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            guard Self.flags.contains(argument), let value = iterator.next() else { continue }
            values[argument] = value
        }
        libraryPath = Self.path(values[Self.libraryPathFlag], directoryHint: .isDirectory)
        shapeLibraryPath = Self.path(
            values[Self.shapeLibraryPathFlag],
            directoryHint: .notDirectory,
        )
        resetState = values[Self.resetStateFlag].map(Self.isTruthy) ?? false
        rememberLibrary = values[Self.rememberLibraryFlag].map(Self.isTruthy) ?? false
        testDefaults = values[Self.testDefaultsFlag].map(Self.isTruthy) ?? false
        shortcutLog = Self.path(values[Self.shortcutLogFlag], directoryHint: .notDirectory)
        bindingsPath = Self.path(values[Self.bindingsPathFlag], directoryHint: .notDirectory)
        liveTimeScale = values[Self.liveTimeScaleFlag].flatMap(Double.init).flatMap { scale in
            scale > 0 ? scale : nil
        }
    }

    private static let flags: Set = [
        libraryPathFlag, resetStateFlag, rememberLibraryFlag, testDefaultsFlag,
        shapeLibraryPathFlag, shortcutLogFlag, liveTimeScaleFlag, bindingsPathFlag,
    ]

    private static func path(_ value: String?, directoryHint: URL.DirectoryHint) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        return URL(filePath: value, directoryHint: directoryHint).standardizedFileURL
    }

    /// Whether any test-only argument was passed.
    var isTestRun: Bool {
        libraryPath != nil || resetState || rememberLibrary || testDefaults
            || shapeLibraryPath != nil || shortcutLog != nil || liveTimeScale != nil
            || bindingsPath != nil
    }

    private static func isTruthy(_ value: String) -> Bool {
        ["yes", "true", "1"].contains(value.lowercased())
    }
}

/// Where app state lives, and clearing it for `-SegueResetState`.
enum AppStateReset {
    /// Suffix of the separate defaults suite used by test runs.
    static let testSuiteSuffix = ".uitest"

    /// The defaults store for this launch. Test runs (any test launch argument) use their own
    /// suite, so running the E2E suite never touches the real library bookmark.
    static func defaults(for options: LaunchOptions, bundleID: String?) -> UserDefaults {
        guard options.isTestRun, let bundleID,
              let suite = UserDefaults(suiteName: bundleID + testSuiteSuffix)
        else { return .standard }
        return suite
    }

    /// Wipes the test suite. `-SegueResetState` always makes this a test run, so it can never
    /// clear the user's real defaults.
    static func wipeTestState(_ defaults: UserDefaults, bundleID: String?) {
        guard let bundleID else { return }
        defaults.removePersistentDomain(forName: bundleID + testSuiteSuffix)
    }
}
