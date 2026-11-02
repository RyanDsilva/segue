#if os(macOS)
    import Foundation

    /// Slots later workstreams fill from the app target, so the menus never change when
    /// they land (WS2a 3.5.6, B-14). Each hook gets the app's `WorkspaceActions` to open
    /// links with. Hooks never run while performing (the menus are hidden on stage).
    ///
    /// - `showWelcome` (WS2b, Help > Welcome to Segue…) and `exportArchive` (WS2b, File >
    ///   Export Library Archive…) are optional: their menu items are hidden while nil.
    /// - `showWhatsNew` (WS2b), `reportProblem` and `requestFeature` (WS3) always exist; until
    ///   their owners replace them they fall back to the web or mail. The fallbacks are for
    ///   development only and are replaced before any release build.
    @MainActor
    public struct AppHooks {
        public typealias Hook = @MainActor (any WorkspaceActions) -> Void

        public var showWelcome: Hook?
        public var exportArchive: Hook?
        public var showWhatsNew: Hook
        public var reportProblem: Hook
        public var requestFeature: Hook

        public init(
            showWelcome: Hook? = nil,
            exportArchive: Hook? = nil,
            showWhatsNew: @escaping Hook = Self.openChangelog,
            reportProblem: @escaping Hook = Self.mailSupport,
            requestFeature: @escaping Hook = Self.openFeedback,
        ) {
            self.showWelcome = showWelcome
            self.exportArchive = exportArchive
            self.showWhatsNew = showWhatsNew
            self.reportProblem = reportProblem
            self.requestFeature = requestFeature
        }

        /// What's New fallback: the release notes on the web.
        public static func openChangelog(_ workspace: any WorkspaceActions) {
            workspace.open(SegueLinks.changelog)
        }

        /// Request a Feature fallback: the board.
        public static func openFeedback(_ workspace: any WorkspaceActions) {
            workspace.open(SegueLinks.feedback)
        }

        /// Report a Problem fallback: a mail to support, subject "Segue 1.0 (12) problem".
        public static func mailSupport(_ workspace: any WorkspaceActions) {
            workspace.open(problemMail(bundle: .main))
        }

        /// The fallback problem mail for the app in `bundle`.
        static func problemMail(bundle: Bundle) -> URL {
            let info = bundle.infoDictionary ?? [:]
            let version = info["CFBundleShortVersionString"] as? String ?? "?"
            let build = info["CFBundleVersion"] as? String ?? "?"
            var components = URLComponents(
                url: SegueLinks.supportEmail,
                resolvingAgainstBaseURL: false,
            )
            components?.queryItems = [
                URLQueryItem(name: "subject", value: "Segue \(version) (\(build)) problem"),
            ]
            return components?.url ?? SegueLinks.supportEmail
        }
    }
#endif
