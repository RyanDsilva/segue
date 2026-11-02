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
        /// The message the next form starts with: the error banner's Report... fills it with
        /// what the banner said (P9-5 5, P1); Help > Report a Problem starts empty.
        private(set) var prefill = ""

        public init() {}

        public func present() {
            present(prefill: "")
        }

        /// Opens the form with `prefill` as its message.
        func present(prefill: String) {
            self.prefill = prefill
            PendingEditsGuard.shared.reopenMainWindow?()
            isPresented = true
        }

        func dismiss() {
            isPresented = false
            prefill = ""
        }
    }
#endif
