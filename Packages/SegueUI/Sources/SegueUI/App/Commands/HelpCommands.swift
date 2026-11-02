#if os(macOS)
    import Services
    import SwiftUI

    /// The Help menu (WS2a 3.5.6, I-5): the canonical list, in order, with exact names. WS2b
    /// and WS3 never edit it; they fill `AppHooks`. Welcome to Segue… is hidden until its hook
    /// is set, Rate Segue on the App Store until `SegueLinks.appStoreID` is.
    ///
    /// The items come from `HelpMenu.items`, so what each one opens is checked in process
    /// (`HelpMenuTests`) and the E2E suite clicks only one of them (docs/test-performance.md).
    struct HelpCommands: Commands {
        let app: AppModel
        @Environment(\.openWindow) private var openWindow

        var body: some Commands {
            CommandGroup(replacing: .help) {
                ForEach(HelpMenu.items(hooks: app.dependencies.hooks)) { item in
                    if item.dividerBefore {
                        Divider()
                    }
                    Button(item.title) {
                        if let help = item.analytics {
                            app.dependencies.services.record(.helpOpened(help))
                        }
                        perform(item.action)
                    }
                    .keyboardShortcut(item.shortcut?.shortcut)
                    .disabled(item.disabledWhilePerforming && app.isPerforming)
                }
            }
        }

        private func perform(_ action: HelpMenuItem.Action) {
            switch action {
            case let .workspace(open):
                open(app.dependencies.workspace)
            case let .window(id):
                openWindow(id: id)
            }
        }
    }

    /// One Help menu item.
    struct HelpMenuItem: Identifiable {
        enum Action {
            /// Opens a page or a mail through the app's `WorkspaceActions`.
            case workspace(AppHooks.Hook)
            /// Opens one of the app's windows.
            case window(String)
        }

        let title: String
        var shortcut: MenuShortcut?
        var disabledWhilePerforming = false
        /// A separator goes above this item.
        var dividerBefore = false
        /// `Segue.Help.opened`'s `segue.item` (WS3 spec 5 row 14); nil: not counted.
        var analytics: HelpItem?
        let action: Action

        var id: String {
            title
        }
    }

    /// The Help menu's items, in order.
    @MainActor
    enum HelpMenu {
        static func items(
            hooks: AppHooks,
            writeReview: URL? = SegueLinks.writeReview,
        ) -> [HelpMenuItem] {
            help(hooks) + feedback(hooks, writeReview: writeReview) + legal
        }

        /// Help, Keyboard Shortcuts, Welcome (once its hook is set), What's New.
        private static func help(_ hooks: AppHooks) -> [HelpMenuItem] {
            var items = [
                HelpMenuItem(
                    title: MenuShortcuts.help.title,
                    shortcut: MenuShortcuts.help,
                    analytics: .help,
                    action: .workspace { $0.open(SegueLinks.help) },
                ),
                HelpMenuItem(
                    title: MenuShortcuts.keyboardShortcuts.title,
                    shortcut: MenuShortcuts.keyboardShortcuts,
                    analytics: .keyboardShortcuts,
                    action: .window(KeyboardShortcutsWindow.id),
                ),
            ]
            if let showWelcome = hooks.showWelcome {
                items.append(HelpMenuItem(
                    title: "Welcome to Segue…",
                    disabledWhilePerforming: true,
                    action: .workspace(showWelcome),
                ))
            }
            items.append(HelpMenuItem(
                title: "What's New in Segue",
                disabledWhilePerforming: true,
                analytics: .whatsNew,
                action: .workspace(hooks.showWhatsNew),
            ))
            return items
        }

        /// Report a Problem, Request a Feature, Rate (once the App Store ID is known).
        private static func feedback(_ hooks: AppHooks, writeReview: URL?) -> [HelpMenuItem] {
            var items = [
                HelpMenuItem(
                    title: "Report a Problem…",
                    dividerBefore: true,
                    analytics: .reportProblem,
                    action: .workspace(hooks.reportProblem),
                ),
                HelpMenuItem(
                    title: "Request a Feature…",
                    analytics: .requestFeature,
                    action: .workspace(hooks.requestFeature),
                ),
            ]
            if let writeReview {
                items.append(HelpMenuItem(
                    title: "Rate Segue on the App Store",
                    action: .workspace { $0.open(writeReview) },
                ))
            }
            return items
        }

        /// Privacy Policy, Terms of Use. Third-party notices live on the website (linked from
        /// both pages) and in the bundle's THIRD_PARTY_NOTICES.md, not in the menu.
        private static var legal: [HelpMenuItem] {
            [
                HelpMenuItem(
                    title: "Privacy Policy",
                    dividerBefore: true,
                    analytics: .privacyPolicy,
                    action: .workspace { $0.open(SegueLinks.privacy) },
                ),
                HelpMenuItem(
                    title: "Terms of Use",
                    analytics: .terms,
                    action: .workspace { $0.open(SegueLinks.terms) },
                ),
            ]
        }
    }
#endif
