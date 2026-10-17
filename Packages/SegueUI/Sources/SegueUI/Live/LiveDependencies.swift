#if os(macOS)
    import AppKit
    import Foundation
    import Shows
    import Support

    /// What live mode needs from the process, built by the app target.
    @MainActor
    public struct LiveDependencies {
        /// Settings > Live.
        public var settings: LiveSettingsStore
        public var shortcuts: any ShortcutRunner
        public var power: any PowerSourceReading
        /// Drives auto-scroll. The system clock, or a time-scaled one in the auto-scroll E2E
        /// (`-SegueLiveTimeScale`), so a 3-minute song scrolls in seconds.
        public var scrollClock: any Clock
        /// `bindings.json` (Application Support); nil uses the default keys only.
        public var bindingsURL: URL?

        public init(
            settings: LiveSettingsStore,
            shortcuts: any ShortcutRunner = WorkspaceShortcutRunner(),
            power: any PowerSourceReading = SystemPowerSource(),
            scrollClock: any Clock = SystemClock(),
            bindingsURL: URL? = nil,
        ) {
            self.settings = settings
            self.shortcuts = shortcuts
            self.power = power
            self.scrollClock = scrollClock
            self.bindingsURL = bindingsURL
        }

        /// `Application Support/<bundle id>/bindings.json` (inside the sandbox container).
        public static func defaultBindingsURL(bundleID: String) -> URL {
            URL.applicationSupportDirectory
                .appending(path: bundleID, directoryHint: .isDirectory)
                .appending(path: InputBindingTable.fileName, directoryHint: .notDirectory)
        }
    }

    /// A clock running `scale` times faster than real time from the moment it was made (test
    /// runs only).
    public struct ScaledClock: Clock {
        private let origin: Date
        private let scale: Double

        public init(scale: Double, origin: Date = Date()) {
            self.origin = origin
            self.scale = scale
        }

        public func now() -> Date {
            origin.addingTimeInterval(Date().timeIntervalSince(origin) * scale)
        }
    }

    /// Keeps Segue in front after a Shortcut ran: Shortcuts may activate itself a moment
    /// after the URL was handed over, so the window is re-asserted now and twice more.
    @MainActor
    enum LiveFocus {
        static func reassert(_ window: @escaping @MainActor () -> NSWindow?) {
            Task { @MainActor in
                for delay in [0, 400, 1200] {
                    if delay > 0 {
                        try? await Task.sleep(for: .milliseconds(delay))
                    }
                    NSApp.activate()
                    guard let target = window() else { continue }
                    // A sheet on it (the reorder review) keeps the keyboard.
                    if let sheet = target.attachedSheet {
                        sheet.makeKey()
                    } else if !target.isKeyWindow {
                        target.makeKeyAndOrderFront(nil)
                    }
                }
            }
        }

        /// The main (library) window.
        static func mainWindow() -> NSWindow? {
            NSApp.windows.first { window in
                window.isVisible && window !== StageWindowController.shared.stageWindow
                    && window.canBecomeMain
            }
        }
    }
#endif
