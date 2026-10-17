#if os(macOS)
    import AppKit
    import SwiftUI

    /// Presents the live view as the stage: a borderless window covering the entire screen,
    /// edge to edge, with the menu bar and Dock hidden while it is up. Keys reach the
    /// session through `LiveKeyInput`; the run ends with Cmd-. (confirmed), which closes it.
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
        private let keyInput = LiveKeyInput()

        override private init() {}

        /// The stage window while it is up.
        var stageWindow: NSWindow? {
            window
        }

        /// Shows `app.live` on the stage, on the screen of the current key window. Called
        /// again while a stage is up, it replaces that stage's window without ending the
        /// performance.
        public func present(_ app: AppModel) {
            guard let live = app.live else { return }
            let screen = window?.screen ?? NSApp.keyWindow?.screen ?? NSScreen.main
            guard let screen else { return }
            if let previous = window {
                // Detach first: closing it must not run `windowWillClose`, which would end
                // the performance being presented.
                previous.delegate = nil
                removeObservers()
                window = nil
                previous.close()
            }
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
            NSApp.activate()
            observe(window)
            live.begin()
            keyInput.install(window: window) { [weak app] in app?.live }
        }

        /// Ends the performance and closes the stage.
        public func close() {
            window?.close()
        }

        public func windowWillClose(_ notification: Notification) {
            guard let closing = notification.object as? NSWindow, closing === window else { return }
            removeObservers()
            keyInput.remove()
            if let savedPresentationOptions {
                NSApp.presentationOptions = savedPresentationOptions
                self.savedPresentationOptions = nil
            }
            window = nil
            if let live = app?.live {
                // Closed without ending (the run stays resumable): let go of its claim.
                if live.isEnding {
                    live.stop()
                } else {
                    live.abandon()
                }
            }
            app?.live = nil
        }

        private func removeObservers() {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers = []
        }

        private func stage(_ live: LiveSession, screen: NSScreen) -> some View {
            LiveView(session: live, topInset: screen.safeAreaInsets.top)
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
