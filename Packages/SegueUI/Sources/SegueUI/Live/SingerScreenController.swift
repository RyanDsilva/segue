#if os(macOS)
    import AppKit
    import Foundation
    import Observation
    import Services
    import Shows
    import SwiftUI

    /// One connected display, as the Singer Screen chooses among them.
    struct SingerDisplay: Equatable, Sendable {
        /// `NSScreen.localizedName`: what the menu lists and the setting remembers.
        var name: String
        /// Its frame in AppKit screen space.
        var frame: CGRect
    }

    /// The connected displays and which one the stage is on (a fake list in tests).
    @MainActor
    protocol SingerDisplayList {
        var displays: [SingerDisplay] { get }
        /// The display the main stage covers; nil when no stage window is up.
        var stageDisplay: SingerDisplay? { get }
    }

    /// The real displays, from `NSScreen`.
    @MainActor
    struct SystemDisplayList: SingerDisplayList {
        var displays: [SingerDisplay] {
            NSScreen.screens.map(SingerDisplay.init)
        }

        var stageDisplay: SingerDisplay? {
            (StageWindowController.shared.stageWindow?.screen ?? NSScreen.main)
                .map(SingerDisplay.init)
        }

        /// The `NSScreen` for `display`, by frame then name.
        static func screen(for display: SingerDisplay) -> NSScreen? {
            NSScreen.screens.first { $0.frame == display.frame }
                ?? NSScreen.screens.first { $0.localizedName == display.name }
        }
    }

    extension SingerDisplay {
        init(_ screen: NSScreen) {
            self.init(name: screen.localizedName, frame: screen.frame)
        }
    }

    /// Which display the Singer Screen takes (P9-2c 6.13): pure.
    enum SingerScreenChoice {
        /// The displays other than the stage's, in system order.
        static func candidates(_ displays: [SingerDisplay], stage: SingerDisplay?)
            -> [SingerDisplay]
        {
            displays.filter { $0 != stage }
        }

        /// The remembered display when it is connected (and not the stage's), else the first
        /// display other than the stage's; nil with only one display.
        static func display(
            among displays: [SingerDisplay],
            stage: SingerDisplay?,
            remembered: String?,
        ) -> SingerDisplay? {
            let others = candidates(displays, stage: stage)
            return others.first { $0.name == remembered } ?? others.first
        }
    }

    /// The Singer Screen (P9-2c, R178): a second stage window, always in singer view, on
    /// another display facing the singer, following the performer's song, pass and progress
    /// while the main stage keeps its own view. No keys, no audio, no pedals, never key; it
    /// closes when the show ends or its display goes away (quietly, and it does not reopen).
    @MainActor
    @Observable
    final class SingerScreenController {
        static let shared = SingerScreenController()

        /// The open screen's follow model; nil while closed.
        private(set) var screen: SingerScreenModel?
        /// The display it is on.
        private(set) var display: SingerDisplay?

        /// Where the displays come from (a fake list in tests).
        @ObservationIgnored var displays: any SingerDisplayList = SystemDisplayList()
        /// False in in-process tests: the model runs without an AppKit window.
        @ObservationIgnored var makesWindows = true
        @ObservationIgnored private var window: NSWindow?
        @ObservationIgnored private var observer: (any NSObjectProtocol)?
        /// Bumped when displays come and go, so the Window menu re-reads them.
        private var displayRevision = 0

        private init() {
            observer = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main,
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.displaysChanged() }
            }
        }

        /// A controller for in-process tests, with a fake display list and no windows.
        init(testing displays: any SingerDisplayList) {
            self.displays = displays
            makesWindows = false
        }

        var isOpen: Bool {
            screen != nil
        }

        /// Window > Singer Screen is enabled: a Live or Rehearsal session is up and more than
        /// one display is connected.
        func canOpen(_ app: AppModel) -> Bool {
            _ = displayRevision
            return app.live != nil && displays.displays.count > 1
        }

        /// The displays the menu offers as a submenu (three or more connected): every one
        /// but the stage's.
        var choices: [SingerDisplay] {
            _ = displayRevision
            let all = displays.displays
            guard all.count >= 3 else { return [] }
            return SingerScreenChoice.candidates(all, stage: displays.stageDisplay)
        }

        /// Opens (or moves) the Singer Screen on `chosen`, else the remembered display, else
        /// the first other display; remembers the choice per machine.
        func open(_ app: AppModel, on chosen: SingerDisplay? = nil) {
            guard let live = app.live, canOpen(app),
                  let target = chosen ?? SingerScreenChoice.display(
                      among: displays.displays,
                      stage: displays.stageDisplay,
                      remembered: app.liveSettings.settings.singerScreenDisplay,
                  )
            else { return }
            closeWindow()
            let model = SingerScreenModel(live: live)
            screen = model
            display = target
            app.liveSettings.updateFromStage { $0.singerScreenDisplay = target.name }
            app.services.record(.featureUsed(.singerView, .screen))
            if makesWindows {
                present(model, on: target)
            }
        }

        /// Closes it (show end, Window > Singer Screen again, display gone).
        func close() {
            closeWindow()
            screen = nil
            display = nil
        }

        /// The displays changed: when the Singer Screen's display is gone, it closes quietly
        /// (no error) and stays closed when the display comes back.
        func displaysChanged() {
            displayRevision += 1
            guard let display, !displays.displays.contains(where: { $0.name == display.name })
            else { return }
            close()
        }

        private func present(_ model: SingerScreenModel, on display: SingerDisplay) {
            guard let screen = SystemDisplayList.screen(for: display) else { return }
            let window = SingerScreenWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
            )
            window.isReleasedWhenClosed = false
            window.title = "Singer Screen"
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(Theme.color.ground)
            window.isOpaque = true
            window.hasShadow = false
            window.collectionBehavior = [.fullScreenNone, .managed, .stationary]
            window.contentView = NSHostingView(rootView: SingerScreenView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.color.ground)
                .ignoresSafeArea()
                .environment(\.colorScheme, .dark))
            window.setFrame(screen.frame, display: true)
            // Never key: the keyboard stays with the main stage (VoiceOver drives it too).
            window.orderFront(nil)
            self.window = window
        }

        private func closeWindow() {
            window?.orderOut(nil)
            window?.close()
            window = nil
        }
    }

    /// A borderless window that never takes the keyboard or becomes main.
    final class SingerScreenWindow: NSWindow {
        override var canBecomeKey: Bool {
            false
        }

        override var canBecomeMain: Bool {
            false
        }
    }
#endif
