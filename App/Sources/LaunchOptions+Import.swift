// Debug and Personal only (P9-4 spec 15.4): Release and the App Store flavour carry neither
// the flag nor the fixtures (`check_no_test_hooks`, `make verify-appstore`).
#if DEBUG && SEGUE_PERSONAL
    import Foundation
    import Plugins
    import SeguePersonalModules

    extension LaunchOptions {
        /// `-SegueImportFixtures YES`: the web import and Find Lyrics read the saved pages of
        /// `ImportFixtureSet.e2e` instead of the network and the hidden WebKit view, so the
        /// UI test of both flows stays offline.
        static let importFixturesFlag = "-SegueImportFixtures"

        static func wantsImportFixtures(_ arguments: [String]) -> Bool {
            guard let index = arguments.firstIndex(of: importFixturesFlag),
                  arguments.indices.contains(index + 1)
            else { return false }
            return isTruthy(arguments[index + 1])
        }

        /// Registers the personal plugins over the fixtures; false when not asked for.
        static func registerImportFixtures(_ registry: PluginRegistry, arguments: [String])
            -> Bool
        {
            guard wantsImportFixtures(arguments) else { return false }
            PersonalModules.register(into: registry, fixtures: ImportFixtureSet.e2e)
            return true
        }
    }
#endif
