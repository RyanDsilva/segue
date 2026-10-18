#if os(macOS)
    import Foundation

    // WS2b: launch-time polish state (presets from the Debug switches, onboarding, What's
    // New, review prompt).

    extension AppModel {
        var polish: PolishDependencies {
            dependencies.polish
        }

        /// The Debug presets a test run asked for, before anything reads the stores.
        func applyPolishPresets() {
            let launch = polish.launch
            if let version = launch.lastSeenVersion {
                polish.whatsNew.markSeen(version)
            }
            if let gigs = launch.completedGigs {
                polish.review.presetCompletedGigs(gigs)
            }
        }
    }
#endif
