#if os(macOS)
    import SwiftUI
    import TipKit

    // WS6 section 7, P9-5 section 3: Help buttons and tips open the matching page of the
    // offline Help Book, with the guide page on the web as the fallback (`HelpRouter`). The
    // action travels in the environment; a view with no action set (a window that never got
    // one) shows no Help button rather than a dead one. While a show is up or starting the
    // buttons are disabled.

    /// Opens a guide page.
    public struct OpenGuideAction {
        private let handler: @MainActor (SegueLinks.Guide) -> Void
        private let available: @MainActor () -> Bool

        public init(
            isAvailable: @escaping @MainActor () -> Bool = { true },
            _ handler: @escaping @MainActor (SegueLinks.Guide) -> Void,
        ) {
            available = isAvailable
            self.handler = handler
        }

        /// False while a show is up or starting: Help buttons are disabled.
        @MainActor
        public var isAvailable: Bool {
            available()
        }

        @MainActor
        public func callAsFunction(_ page: SegueLinks.Guide) {
            handler(page)
        }
    }

    public extension EnvironmentValues {
        @Entry var openGuide: OpenGuideAction?
    }

    public extension View {
        /// Lets Help buttons and tips under this view open guide pages through `router`
        /// (the Help Book, the web as fallback).
        func guideLinks(_ router: HelpRouter) -> some View {
            environment(\.openGuide, OpenGuideAction(
                isAvailable: { router.isAvailable },
                { router.open($0) },
            ))
        }

        /// Guide pages on the web only, with `workspace` (views built without the app).
        func guideLinks(_ workspace: any WorkspaceActions) -> some View {
            guideLinks(HelpRouter.web(workspace))
        }
    }

    /// The standard round macOS Help button, opening one guide page. `opened` runs after the
    /// page opens (a sheet that counts its Help button, e.g. `helpOpened(.pdf)`).
    struct GuideHelpButton: View {
        let page: SegueLinks.Guide
        var opened: (() -> Void)?
        @Environment(\.openGuide) private var openGuide

        init(_ page: SegueLinks.Guide, opened: (() -> Void)? = nil) {
            self.page = page
            self.opened = opened
        }

        var body: some View {
            if let openGuide {
                HelpLink {
                    openGuide(page)
                    opened?()
                }
                .disabled(!openGuide.isAvailable)
                .help(uiString("Open “\(page.title)” in Segue Help"))
                .accessibilityLabel(uiString("Help: \(page.title)"))
                .accessibilityIdentifier(AccessibilityID.guideHelp(page))
            }
        }
    }

    /// A Settings pane's Help button, the form's last item: bottom right after the last
    /// group, scrolling with the content, as in System Settings' own panes. Pinned over a
    /// scrolling form instead, it sat on top of whatever control scrolled under it.
    struct SettingsGuideHelp: View {
        let page: SegueLinks.Guide

        var body: some View {
            Section {} footer: {
                HStack {
                    Spacer()
                    GuideHelpButton(page)
                }
            }
        }
    }

    public extension AccessibilityID {
        /// A Help button that opens `page` (WS6 7.2).
        static func guideHelp(_ page: SegueLinks.Guide) -> String {
            "segue.guideHelp.\(page)"
        }

        /// Help > Keyboard Shortcuts' "All shortcuts" link.
        static let keyboardShortcutsGuide = "segue.keyboardShortcuts.guide"
        /// The empty library's "How to bring songs in" link.
        static let emptyLibraryGuide = "segue.emptyLibrary.guide"
    }

    /// The tip action every tip offers: open the guide page about it.
    enum GuideTipAction {
        static let learnMore = "learnMore"

        static var action: Tips.Action {
            Tips.Action(id: learnMore, title: uiString("Learn More"))
        }

        /// Handles a tip's Learn More by opening `page`; other actions are the caller's.
        @MainActor
        static func handle(
            _ action: Tips.Action,
            page: SegueLinks.Guide,
            openGuide: OpenGuideAction?,
        ) {
            if action.id == learnMore, openGuide?.isAvailable == true {
                openGuide?(page)
            }
        }
    }
#endif
