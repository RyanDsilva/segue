import Foundation

#if DEBUG
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

        /// AppKit autosaves window frames (`NSWindow Frame <name>`) into the app's standard
        /// defaults, never into the test suite, so a test launch would start from whatever frame
        /// the same bundle ID last saved (a real Personal session's 1440x900, a previous run's
        /// moved window). `-SegueResetState` forgets them so every reset launch opens at the
        /// scene's default size. Relaunches without a reset keep them: that is the restore test.
        static func forgetWindowFrames(in defaults: UserDefaults = .standard) {
            for key in defaults.dictionaryRepresentation().keys
                where key.hasPrefix("NSWindow Frame ")
            {
                defaults.removeObject(forKey: key)
            }
        }
    }
#endif
