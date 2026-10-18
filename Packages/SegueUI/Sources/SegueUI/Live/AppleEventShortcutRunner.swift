#if os(macOS)
    import AppKit
    import CoreServices
    import Foundation

    /// What Shortcuts Events answered a `run shortcut` Apple event with.
    public struct ShortcutsEventsReply: Equatable, Sendable {
        /// The Apple event error number; nil when the Shortcut finished without error.
        public var errorNumber: Int?
        /// The error text Shortcuts sent with it (for a failing action, the Shortcut's own
        /// message).
        public var errorMessage: String?

        public init(errorNumber: Int? = nil, errorMessage: String? = nil) {
            self.errorNumber = errorNumber
            self.errorMessage = errorMessage
        }

        /// The Shortcut ran to the end.
        public static let finished = Self()
    }

    /// The Apple-event conversation with Shortcuts Events (Path SE, docs/release/decisions.md
    /// R59), behind a seam so tests can stand in for the user's real Shortcuts.
    public protocol ShortcutsEvents: Sendable {
        /// `AEDeterminePermissionToAutomateTarget` for Shortcuts Events. With
        /// `askUserIfNeeded` the system may show its one-time Automation prompt.
        func permission(askUserIfNeeded: Bool) async -> OSStatus
        /// Sends `run shortcut "<name>"` and waits for the Shortcut to finish.
        func run(_ name: String) async -> ShortcutsEventsReply
    }

    /// Runs Gig Mode Shortcuts through Shortcuts Events (Path SE, R59): the Apple event
    /// returns when the Shortcut finished, so completion and failure are observed rather
    /// than guessed. During a show the Automation permission is only checked, never asked
    /// for; Settings > Live "Test" is where the one-time prompt appears.
    @MainActor
    public final class AppleEventShortcutRunner: ShortcutRunner {
        let events: any ShortcutsEvents

        public init(events: any ShortcutsEvents = SystemShortcutsEvents()) {
            self.events = events
        }

        public func run(_ name: String) async -> ShortcutOutcome {
            await run(name, askUserIfNeeded: false)
        }

        public func runAskingPermission(_ name: String) async -> ShortcutOutcome {
            await run(name, askUserIfNeeded: true)
        }

        private func run(_ name: String, askUserIfNeeded: Bool) async -> ShortcutOutcome {
            let status = await events.permission(askUserIfNeeded: askUserIfNeeded)
            if let refused = Self.outcome(permission: status) {
                return refused
            }
            return await Self.outcome(events.run(name))
        }

        // MARK: Mapping (probe results in docs/release/research/09-shortcut-confirmation.md)

        /// The Apple event error numbers Path SE tells apart.
        enum ErrorNumber {
            /// `errAENoSuchObject`: no Shortcut has that name.
            static let notFound = -1728
            /// `errAEEventNotPermitted`: the user turned Automation off for Segue.
            static let notPermitted = -1743
            /// `errAEEventWouldRequireUserConsent`: Automation was never asked for.
            static let needsConsent = -1744
            /// `errAETimeout`: no reply within the send timeout; it may still be running.
            static let timeout = -1712
            /// `procNotFound`: Shortcuts Events is not running.
            static let notRunning = -600
        }

        /// What the performer reads after "“<name>” failed: " (the checklist row, the
        /// Settings Test result), and where Automation is turned back on.
        public enum Message {
            public static let notPermitted = "Segue may not run Shortcuts. Turn on Shortcuts "
                + "Events for Segue in System Settings > Privacy & Security > Automation"
            static let needsConsent = "Segue has not been allowed to run Shortcuts yet. "
                + "Press Test in Settings > Live, then click OK"
            static let notFound = "there is no Shortcut with this name in the Shortcuts app"
            /// System Settings > Privacy & Security > Automation.
            public static let automationSettingsURL = URL(
                string: "x-apple.systempreferences:"
                    + "com.apple.preference.security?Privacy_Automation",
            )
        }

        /// The refusal for a permission check that did not return `noErr`; nil when the run
        /// may go ahead.
        nonisolated static func outcome(permission status: OSStatus) -> ShortcutOutcome? {
            switch Int(status) {
            case Int(noErr): nil
            case ErrorNumber.notPermitted: .failed(Message.notPermitted)
            case ErrorNumber.needsConsent: .failed(Message.needsConsent)
            case ErrorNumber.notRunning: .failed("Shortcuts Events did not start")
            default: .failed("Segue could not reach Shortcuts Events (error \(status))")
            }
        }

        /// What one reply means: success ran, `-1728` is not set up, `-1743` is not
        /// permitted, a timeout is only a hand-over, and anything else (including `-1753`,
        /// a failing action) failed with the Shortcut's own message.
        nonisolated static func outcome(_ reply: ShortcutsEventsReply) -> ShortcutOutcome {
            guard let number = reply.errorNumber else { return .completed }
            switch number {
            case ErrorNumber.notFound: return .failed(Message.notFound)
            case ErrorNumber.notPermitted: return .failed(Message.notPermitted)
            case ErrorNumber.timeout: return .handedOver
            default:
                let message = reply.errorMessage?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                guard let message, !message.isEmpty else {
                    return .failed("Shortcuts reported error \(number)")
                }
                return .failed(message)
            }
        }
    }

    /// The real Shortcuts Events (`com.apple.shortcuts.events`), reached with the
    /// `com.apple.security.scripting-targets` entitlement for `com.apple.shortcuts.run`.
    /// Every blocking call runs off the main actor.
    public struct SystemShortcutsEvents: ShortcutsEvents {
        static let bundleID = "com.apple.shortcuts.events"
        /// How long a Shortcut may run before the send gives up (it is then `.handedOver`).
        static let sendTimeout: TimeInterval = 60

        public init() {}

        public func permission(askUserIfNeeded: Bool) async -> OSStatus {
            var status = await Self.determinePermission(askUserIfNeeded: askUserIfNeeded)
            // Shortcuts Events quits when idle, and the check answers procNotFound for a
            // target that is not running (seen on macOS 26.6), so start it in the background.
            guard Int(status) == AppleEventShortcutRunner.ErrorNumber.notRunning else {
                return status
            }
            await Self.launchInBackground()
            for _ in 0 ..< 20 {
                status = await Self.determinePermission(askUserIfNeeded: askUserIfNeeded)
                guard Int(status) == AppleEventShortcutRunner.ErrorNumber.notRunning else { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            return status
        }

        public func run(_ name: String) async -> ShortcutsEventsReply {
            await Task.detached(priority: .userInitiated) { Self.send(name) }.value
        }

        private static func determinePermission(askUserIfNeeded: Bool) async -> OSStatus {
            await Task.detached(priority: .userInitiated) {
                let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
                guard let address = target.aeDesc else { return OSStatus(paramErr) }
                return AEDeterminePermissionToAutomateTarget(
                    address,
                    AEEventClass(typeWildCard),
                    AEEventID(typeWildCard),
                    askUserIfNeeded,
                )
            }.value
        }

        /// Starts Shortcuts Events hidden, without activating it or adding a recent item.
        @MainActor
        private static func launchInBackground() async {
            guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.hides = true
            configuration.addsToRecentItems = false
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
                    continuation.resume()
                }
            }
        }

        /// `run shortcut "<name>"` (class `srct`, ID `run `), sent synchronously with a reply.
        private static func send(_ name: String) -> ShortcutsEventsReply {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
            let event = NSAppleEventDescriptor(
                eventClass: fourCharCode("srct"),
                eventID: fourCharCode("run "),
                targetDescriptor: target,
                returnID: AEReturnID(kAutoGenerateReturnID),
                transactionID: AETransactionID(kAnyTransactionID),
            )
            guard let specifier = shortcutSpecifier(named: name) else {
                return ShortcutsEventsReply(errorNumber: Int(paramErr), errorMessage: nil)
            }
            event.setParam(specifier, forKeyword: AEKeyword(keyDirectObject))
            do {
                let reply = try event.sendEvent(options: [.waitForReply], timeout: sendTimeout)
                // An error can come back in the reply without sendEvent throwing (the probe
                // saw -1728 and -1753 this way), so read the reply's error keys too.
                guard let number = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber))
                else { return .finished }
                let message = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorString))
                return ShortcutsEventsReply(
                    errorNumber: Int(number.int32Value),
                    errorMessage: message?.stringValue,
                )
            } catch let error as NSError {
                return ShortcutsEventsReply(
                    errorNumber: error.code,
                    errorMessage: error.userInfo[NSLocalizedFailureReasonErrorKey] as? String,
                )
            }
        }

        /// `shortcut "<name>"`: an object specifier of class `srct`, form name, null
        /// container.
        private static func shortcutSpecifier(named name: String) -> NSAppleEventDescriptor? {
            let record = NSAppleEventDescriptor.record()
            record.setDescriptor(
                NSAppleEventDescriptor(typeCode: fourCharCode("srct")),
                forKeyword: AEKeyword(keyAEDesiredClass),
            )
            record.setDescriptor(
                NSAppleEventDescriptor(enumCode: OSType(formName)),
                forKeyword: AEKeyword(keyAEKeyForm),
            )
            record.setDescriptor(
                NSAppleEventDescriptor(string: name),
                forKeyword: AEKeyword(keyAEKeyData),
            )
            record.setDescriptor(
                NSAppleEventDescriptor.null(),
                forKeyword: AEKeyword(keyAEContainer),
            )
            return record.coerce(toDescriptorType: DescType(typeObjectSpecifier))
        }

        private static func fourCharCode(_ string: String) -> FourCharCode {
            string.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
        }
    }
#endif
