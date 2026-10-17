import Foundation

/// Test-only launch arguments (used by XCUITests to start from a clean baseline):
///
/// - `-SegueLibraryPath <path>`: use `<path>` as the library folder, bypassing the open panel
///   and the stored bookmark.
/// - `-SegueResetState YES`: wipe UserDefaults (including the library bookmark) at launch.
struct LaunchOptions: Sendable, Equatable {
    static let libraryPathFlag = "-SegueLibraryPath"
    static let resetStateFlag = "-SegueResetState"

    var libraryPath: URL?
    var resetState = false

    init(libraryPath: URL? = nil, resetState: Bool = false) {
        self.libraryPath = libraryPath
        self.resetState = resetState
    }

    /// Parses `arguments` (as in `ProcessInfo.arguments`; the first element is the
    /// executable). Unknown arguments are ignored; a flag without a value is ignored.
    init(arguments: [String]) {
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case Self.libraryPathFlag:
                if let value = iterator.next(), !value.isEmpty {
                    libraryPath = URL(filePath: value, directoryHint: .isDirectory)
                        .standardizedFileURL
                }
            case Self.resetStateFlag:
                if let value = iterator.next() {
                    resetState = Self.isTruthy(value)
                }
            default:
                continue
            }
        }
    }

    /// Whether any test-only argument was passed.
    var isTestRun: Bool {
        libraryPath != nil || resetState
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
