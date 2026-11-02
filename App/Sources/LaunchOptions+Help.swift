#if DEBUG
    import Foundation
    import SegueUI

    /// - `-SegueHelpBook YES`: Help opens the bundled Help Book in Tips (P9-5). Other test runs
    ///   get none, so Help opens its web fallback, which `-SegueWorkspaceLog` records.
    extension LaunchOptions {
        static let helpBookFlag = "-SegueHelpBook"

        /// Whether this launch passed `-SegueHelpBook YES`.
        static func usesHelpBook(_ arguments: [String] = CommandLine.arguments) -> Bool {
            flagValues(arguments)[helpBookFlag].map(isTruthy) ?? false
        }

        /// `dependencies` with the Help Book this launch uses: the bundled one, except in a
        /// test run without `-SegueHelpBook YES`.
        @MainActor
        func withHelpBook(_ dependencies: AppDependencies) -> AppDependencies {
            guard isTestRun, !Self.usesHelpBook() else { return dependencies }
            var dependencies = dependencies
            dependencies.helpBook = NoHelpBook()
            return dependencies
        }
    }
#endif
