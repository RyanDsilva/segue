#if os(macOS)
    import AppKit
    import OSLog
    import Services

    // P9-5 section 3: the offline Apple Help Book (Derived/HelpBook/Segue.help, built from the
    // guide) opens in Tips, the macOS 26 Help Viewer. Help > Segue Help opens its home, Help
    // buttons and tips their page's anchor; when the book cannot open, the same guide page
    // opens on the web, so a Help button is never dead. Nothing opens while a show is up or
    // starting: Tips would become key and the stage would lose its keys.

    /// Opens the bundled Help Book.
    @MainActor
    public protocol HelpBookOpening: AnyObject {
        /// Opens the book's home page; false when the app has no usable book.
        func openHome() -> Bool
        /// Opens the page holding `anchor`; false when the app has no usable book.
        func open(anchor: String) -> Bool
    }

    /// The live book: `NSHelpManager` with the book named by `CFBundleHelpBookName`.
    @MainActor
    public final class SystemHelpBook: HelpBookOpening {
        private let bundle: Bundle
        private lazy var bookName: String? = Self.registeredBook(in: bundle)

        public init(bundle: Bundle = .main) {
            self.bundle = bundle
        }

        public func openHome() -> Bool {
            guard bookName != nil else { return false }
            NSApp.showHelp(nil)
            return true
        }

        public func open(anchor: String) -> Bool {
            guard let bookName else { return false }
            NSHelpManager.shared.openHelpAnchor(anchor, inBook: bookName)
            return true
        }

        /// The book's name when `bundle` declares one and Help registers it (false for a
        /// bundle without the book, such as a test runner).
        private static func registeredBook(in bundle: Bundle) -> String? {
            guard let name = bundle.object(forInfoDictionaryKey: "CFBundleHelpBookName") as? String,
                  bundle.object(forInfoDictionaryKey: "CFBundleHelpBookFolder") != nil,
                  NSHelpManager.shared.registerBooks(in: bundle)
            else {
                return nil
            }
            return name
        }
    }

    /// Routes every Help item and Help button: the book first, the web guide as the fallback,
    /// nothing while a show is up, and row 14 with the route taken.
    @MainActor
    public final class HelpRouter {
        private let book: any HelpBookOpening
        private let workspace: any WorkspaceActions
        private let isShowUp: @MainActor () -> Bool
        private let record: @MainActor (AnalyticsEvent) -> Void
        /// The fallback is logged once per launch, not shown.
        private static var loggedFallback = false
        private static let logger = Logger(subsystem: "dev.ryandsilva.segue", category: "help")

        public init(
            book: any HelpBookOpening,
            workspace: any WorkspaceActions,
            isShowUp: @escaping @MainActor () -> Bool = { false },
            record: @escaping @MainActor (AnalyticsEvent) -> Void = { _ in },
        ) {
            self.book = book
            self.workspace = workspace
            self.isShowUp = isShowUp
            self.record = record
        }

        /// A web-only router: the guide in the browser, never blocked, nothing recorded
        /// (previews and windows built without the app model).
        public static func web(_ workspace: any WorkspaceActions) -> HelpRouter {
            HelpRouter(book: NoHelpBook(), workspace: workspace)
        }

        /// Whether Help may open now (never while a show is up or starting).
        public var isAvailable: Bool {
            !isShowUp()
        }

        /// Help > Segue Help: the book's home, or the guide's home on the web.
        @discardableResult
        public func openHome() -> HelpRoute? {
            guard isAvailable else { return nil }
            let route: HelpRoute = book.openHome() ? .book : fallBack(to: SegueLinks.Guide.home)
            record(.helpOpened(.help, via: route))
            return route
        }

        /// A Help button or a tip's Learn More: the page's anchor in the book, or the page on
        /// the web.
        @discardableResult
        public func open(_ page: SegueLinks.Guide) -> HelpRoute? {
            guard isAvailable else { return nil }
            let route: HelpRoute = book.open(anchor: page.helpAnchor) ? .book : fallBack(to: page)
            record(.helpOpened(.contextHelp, via: route, page: page.analyticsPage))
            return route
        }

        private func fallBack(to page: SegueLinks.Guide) -> HelpRoute {
            if !Self.loggedFallback {
                Self.loggedFallback = true
                Self.logger.notice("Help Book unavailable; opening the guide on the web")
            }
            workspace.open(page.url)
            return .web
        }
    }

    public extension AppModel {
        /// Help for this app: the dependencies' book, the web as fallback, blocked while a
        /// show is up or starting, recorded through the services.
        var help: HelpRouter {
            HelpRouter(
                book: dependencies.helpBook,
                workspace: dependencies.workspace,
                isShowUp: { [weak self] in self?.isShowUp ?? false },
                record: { [weak self] in self?.services.record($0) },
            )
        }

        /// A show is on stage or starting (pre-show checklist included): Help, Keyboard
        /// Shortcuts and drags out of the library wait (P9-5 3.2).
        var isShowUp: Bool {
            isPerforming || isStartingShow || preShow != nil
        }
    }

    /// No book (the web-only router, in-process tests and UI test runs).
    @MainActor
    public final class NoHelpBook: HelpBookOpening {
        public init() {}

        public func openHome() -> Bool {
            false
        }

        public func open(anchor _: String) -> Bool {
            false
        }
    }

    public extension SegueLinks.Guide {
        /// Row 14's `segue.page`: the analytics case named like this one (R199).
        var analyticsPage: HelpPage? {
            HelpPage(rawValue: String(describing: self))
        }

        /// The Apple Help anchor of this page in the Help Book: the page slug, or
        /// `<slug>-<id>` for a heading (guide/scripts/helpbook.mjs writes both); the home is
        /// `index`.
        var helpAnchor: String {
            let path = url.path()
            let prefix = "/guide"
            let slug = path.hasPrefix(prefix + "/")
                ? String(path.dropFirst(prefix.count + 1)) : "index"
            guard let fragment = url.fragment(), !fragment.isEmpty else { return slug }
            return "\(slug)-\(fragment)"
        }
    }
#endif
