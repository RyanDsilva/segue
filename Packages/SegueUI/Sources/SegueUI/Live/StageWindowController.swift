#if os(macOS)
    import AppKit
    import SwiftUI

    /// Presents the live view as the stage: a borderless window covering the entire screen,
    /// edge to edge, with the menu bar and Dock hidden while it is up. Esc (or closing the
    /// window) ends the performance.
    ///
    /// This is deliberately not native full screen (`toggleFullScreen`): on displays with a
    /// camera housing, macOS places full-screen windows below the housing and paints the
    /// strip beside it black, so the stage ground could not reach the top edge. A SwiftUI
    /// `Window` scene can't do it either: a titled window is kept below the menu bar strip,
    /// and SwiftUI's borderless (`.plain`) windows never become key, so the stage would get
    /// no arrow keys.
    @MainActor
    public final class StageWindowController: NSObject, NSWindowDelegate {
        public static let shared = StageWindowController()

        private var window: StageWindow?
        private weak var app: AppModel?
        private var savedPresentationOptions: NSApplication.PresentationOptions?
        private var observers: [any NSObjectProtocol] = []

        override private init() {}

        /// Shows `app.live` on the stage, on the screen of the current key window.
        public func present(_ app: AppModel) {
            guard let live = app.live else { return }
            window?.close()
            guard let screen = NSApp.keyWindow?.screen ?? NSScreen.main else { return }
            self.app = app

            let window = StageWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
            )
            window.isReleasedWhenClosed = false
            window.title = "Perform"
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(Theme.color.ground)
            window.isOpaque = true
            window.hasShadow = false
            window.collectionBehavior = [.fullScreenNone, .managed]
            window.delegate = self
            window.contentView = NSHostingView(rootView: stage(live, screen: screen))
            self.window = window

            hideSystemChrome()
            window.setFrame(screen.frame, display: true)
            window.makeKeyAndOrderFront(nil)
            observe(window)
        }

        /// Ends the performance and closes the stage.
        public func close() {
            window?.close()
        }

        public func windowWillClose(_: Notification) {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers = []
            if let savedPresentationOptions {
                NSApp.presentationOptions = savedPresentationOptions
                self.savedPresentationOptions = nil
            }
            window = nil
            app?.live = nil
        }

        private func stage(_ live: LiveViewModel, screen: NSScreen) -> some View {
            LiveView(model: live, topInset: screen.safeAreaInsets.top) { [weak self] in
                self?.close()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.color.ground)
            .ignoresSafeArea()
            .environment(\.colorScheme, .dark)
        }

        /// Hides the menu bar and Dock so nothing overlaps the stage. Presentation options
        /// apply only while Segue is active, so this is re-applied on activation.
        private func hideSystemChrome() {
            if savedPresentationOptions == nil {
                savedPresentationOptions = NSApp.presentationOptions
            }
            NSApp.presentationOptions = [.hideDock, .hideMenuBar]
        }

        private func observe(_ window: NSWindow) {
            let center = NotificationCenter.default
            observers = [
                center.addObserver(
                    forName: NSApplication.didChangeScreenParametersNotification,
                    object: nil,
                    queue: .main,
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refit() }
                },
                center.addObserver(
                    forName: NSApplication.didBecomeActiveNotification,
                    object: nil,
                    queue: .main,
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        if self?.window != nil {
                            self?.hideSystemChrome()
                        }
                    }
                },
            ]
        }

        /// Re-covers the screen after a display change (resolution, arrangement).
        private func refit() {
            guard let window, let live = app?.live,
                  let screen = window.screen ?? NSScreen.main
            else { return }
            window.contentView = NSHostingView(rootView: stage(live, screen: screen))
            window.setFrame(screen.frame, display: true)
        }
    }

    /// A borderless window that can take keyboard focus (borderless windows can't by
    /// default).
    final class StageWindow: NSWindow {
        override var canBecomeKey: Bool {
            true
        }

        override var canBecomeMain: Bool {
            true
        }
    }
#endif
