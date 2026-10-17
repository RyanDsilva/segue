#if os(macOS)
    import AppKit

    /// One Segue per user session: a second launch activates the first and quits.
    @MainActor
    public enum SingleInstance {
        /// The running Segue this process should hand over to: another instance of the same
        /// app (bundle identifier) that launched earlier (ties: the lower process id), so
        /// two simultaneous launches never both quit.
        static func existing(
            among running: [NSRunningApplication],
            me: NSRunningApplication = .current,
        ) -> NSRunningApplication? {
            running
                .filter { other in
                    other.processIdentifier != me.processIdentifier && !other.isTerminated
                        && launched(other, before: me)
                }
                .min { launched($0, before: $1) }
        }

        private static func launched(_ lhs: NSRunningApplication, before rhs: NSRunningApplication)
            -> Bool
        {
            let left = lhs.launchDate ?? .distantPast
            let right = rhs.launchDate ?? .distantPast
            return left != right ? left < right : lhs.processIdentifier < rhs.processIdentifier
        }

        /// Activates an earlier instance; true when there is one (this process should quit).
        @discardableResult
        public static func activateExisting() -> Bool {
            guard let bundleID = Bundle.main.bundleIdentifier else { return false }
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            guard let first = existing(among: running) else { return false }
            first.activate()
            return true
        }
    }
#endif
