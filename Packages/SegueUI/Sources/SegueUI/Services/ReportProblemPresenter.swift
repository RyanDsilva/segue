#if os(macOS)
    import Observation

    /// Help > Report a Problem (WS3 spec 8.1): the app's `AppHooks.reportProblem` calls
    /// `present()`, which brings the main window forward; the main window then shows
    /// `ReportProblemSheet` (never while performing, never over the consent prompt).
    @MainActor
    @Observable
    public final class ReportProblemPresenter {
        /// The sheet was asked for and not dismissed yet.
        public private(set) var isPresented = false
        /// The sheet is actually on screen (the consent prompt waits meanwhile).
        var isShowing = false

        public init() {}

        public func present() {
            PendingEditsGuard.shared.reopenMainWindow?()
            isPresented = true
        }

        func dismiss() {
            isPresented = false
        }
    }
#endif
