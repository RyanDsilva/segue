#if os(macOS)
    import SwiftUI
    import TipKit

    // WS6 section 7: Help buttons and tips open the matching user guide page in the default
    // browser, through `WorkspaceActions` like every other link. The action travels in the
    // environment; a view with no action set (a window that never got one) shows no Help
    // button rather than a dead one.

    /// Opens a guide page.
    public struct OpenGuideAction {
        private let handler: @MainActor (SegueLinks.Guide) -> Void

        public init(_ handler: @escaping @MainActor (SegueLinks.Guide) -> Void) {
            self.handler = handler
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
        /// Lets Help buttons and tips under this view open guide pages with `workspace`.
        func guideLinks(_ workspace: any WorkspaceActions) -> some View {
            environment(\.openGuide, OpenGuideAction { workspace.open($0.url) })
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
                .help("Open “\(page.title)” in the Segue Guide")
                .accessibilityLabel("Help: \(page.title)")
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
            Tips.Action(id: learnMore, title: "Learn More")
        }

        /// Handles a tip's Learn More by opening `page`; other actions are the caller's.
        @MainActor
        static func handle(
            _ action: Tips.Action,
            page: SegueLinks.Guide,
            openGuide: OpenGuideAction?,
        ) {
            if action.id == learnMore {
                openGuide?(page)
            }
        }
    }
#endif
