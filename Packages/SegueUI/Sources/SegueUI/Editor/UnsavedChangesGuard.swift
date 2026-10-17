#if os(macOS)
    import AppKit
    import SwiftUI

    /// Quitting or closing the main window with unsaved edits asks first, with the same
    /// Save / Discard / Cancel prompt as navigating away (`LibraryViewModel.navigate`).
    @MainActor
    final class UnsavedChangesGuard {
        static let shared = UnsavedChangesGuard()

        /// The running app (registered by the main window).
        weak var app: AppModel?

        private var library: LibraryViewModel? {
            guard let library = app?.session?.library, library.hasUnsavedEdits else { return nil }
            return library
        }

        /// `applicationShouldTerminate`: on stage, quitting goes through the end-show
        /// confirmation (and quits once the run ended); otherwise prompts and answers later
        /// when edits are unsaved.
        func shouldTerminate() -> NSApplication.TerminateReply {
            if let live = app?.live, !live.isEnding {
                live.requestEnd(quitting: true)
                StageWindowController.shared.stageWindow?.makeKeyAndOrderFront(nil)
                NSApp.activate()
                return .terminateCancel
            }
            guard let library else { return .terminateNow }
            revealMainWindow()
            library.navigate {
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            onCancel: {
                NSApp.reply(toApplicationShouldTerminate: false)
            }
            return .terminateLater
        }

        /// `windowShouldClose` for the main window.
        func shouldClose(_ window: NSWindow) -> Bool {
            guard let library else { return true }
            library.navigate { [weak window] in
                // The editor is closed (saved or discarded) by now, so this closes.
                window?.close()
            }
            return false
        }

        private func revealMainWindow() {
            let window = NSApp.windows.first { $0.delegate is WindowCloseGuard }
            if let window {
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate()
        }
    }

    /// Install with `@NSApplicationDelegateAdaptor(SegueAppDelegate.self)` in the app.
    public final class SegueAppDelegate: NSObject, NSApplicationDelegate {
        /// Single instance: a second launch hands over to the running Segue and quits
        /// before it opens anything (two instances could perform the same show).
        public func applicationWillFinishLaunching(_: Notification) {
            MainActor.assumeIsolated {
                if SingleInstance.activateExisting() {
                    exit(0)
                }
            }
        }

        public func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
            MainActor.assumeIsolated {
                UnsavedChangesGuard.shared.shouldTerminate()
            }
        }
    }

    /// Wraps the main window's delegate to veto closing while edits are unsaved; every
    /// other delegate message goes to the original (SwiftUI's).
    final class WindowCloseGuard: NSObject, NSWindowDelegate {
        weak var original: (any NSWindowDelegate)?

        override func responds(to selector: Selector?) -> Bool {
            if super.responds(to: selector) {
                return true
            }
            guard let selector else { return false }
            return original?.responds(to: selector) ?? false
        }

        override func forwardingTarget(for selector: Selector?) -> Any? {
            guard let selector, original?.responds(to: selector) == true else { return nil }
            return original
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if original?.windowShouldClose?(sender) == false {
                return false
            }
            return MainActor.assumeIsolated {
                UnsavedChangesGuard.shared.shouldClose(sender)
            }
        }
    }

    /// Registers the app with the guard and wraps the hosting window's delegate. Put it in
    /// the main window's background.
    struct UnsavedChangesWindowGuard: NSViewRepresentable {
        let app: AppModel

        func makeNSView(context _: Context) -> GuardView {
            UnsavedChangesGuard.shared.app = app
            return GuardView()
        }

        func updateNSView(_ view: GuardView, context _: Context) {
            UnsavedChangesGuard.shared.app = app
            view.install()
        }

        final class GuardView: NSView {
            private let closeGuard = WindowCloseGuard()

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                install()
            }

            /// (Re)wraps the window delegate; SwiftUI may replace it.
            func install() {
                guard let window, !(window.delegate === closeGuard) else { return }
                closeGuard.original = window.delegate
                window.delegate = closeGuard
            }
        }
    }
#endif
