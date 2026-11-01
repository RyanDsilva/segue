#if os(macOS)
    import Foundation
    import Support

    /// The libraries' machine state outside their folders (P9-6 5.2).
    extension AppModel {
        /// At launch: moves state directories no library has opened for 180 days to the
        /// Trash (never one whose library is open), and notes when the shared app-group
        /// location was unreachable, so the cross-flavor lock is lost.
        func prepareLibraryState() {
            let location = dependencies.libraryState
            if !location.isShared {
                diagnosticLog?.notice(.library, "state outside the app group")
            }
            let pruned = LibraryState.pruneStale(
                location: location,
                fileSystem: dependencies.fileSystem,
                clock: dependencies.clock,
            )
            if !pruned.isEmpty {
                diagnosticLog?.info(.library, "stale state pruned", ["count": .int(pruned.count)])
            }
        }
    }
#endif
