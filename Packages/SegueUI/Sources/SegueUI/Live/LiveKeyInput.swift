#if os(macOS)
    import AppKit
    import Shows

    /// The keyboard input source: turns key-down events on the stage window into
    /// `KeyStroke`s and the bound `LiveCommand`s (`InputBindingTable`). Installed as a local
    /// event monitor so it sees Cmd combinations before the (hidden) main menu does.
    @MainActor
    final class LiveKeyInput {
        private var monitor: Any?

        /// Starts routing key-downs on `window` to `session()`.
        func install(window: NSWindow, session: @escaping @MainActor () -> LiveSession?) {
            remove()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak window] event in
                // Local monitors run on the main thread.
                nonisolated(unsafe) let event = event
                let handled = MainActor.assumeIsolated {
                    guard let window, event.window === window, let session = session() else {
                        return false
                    }
                    return Self.handle(event, session: session)
                }
                return handled ? nil : event
            }
        }

        func remove() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        /// Handles `event`; false lets it through (typing in the search field, unbound keys).
        ///
        /// Key auto-repeat (a held key or a pedal that sticks) only repeats scrolling and
        /// zoom: a repeat never advances songs, toggles panels, confirms or plays a result.
        static func handle(_ event: NSEvent, session: LiveSession) -> Bool {
            guard let stroke = keyStroke(event) else { return false }
            let isRepeat = event.isARepeat
            if let handled = handleOverlay(stroke, isRepeat: isRepeat, session: session) {
                return handled
            }
            guard let command = session.context.bindings.command(for: .key(stroke)) else {
                // Swallow plain unbound keys on stage (no beep); let other Cmd combinations
                // reach the app. A shifted letter counts as plain.
                return stroke.modifiers.isEmpty
                    || stroke.modifiers == .shift && stroke.key.count == 1
            }
            if isRepeat, command.scope != .viewport {
                return true
            }
            session.dispatch(command)
            return true
        }

        /// Cmd-W / Cmd-Q, and keys the open overlay takes; nil when the bindings decide.
        private static func handleOverlay(
            _ stroke: KeyStroke,
            isRepeat: Bool,
            session: LiveSession,
        ) -> Bool? {
            // Closing or quitting the stage always asks first (Cmd-W, Cmd-Q).
            if stroke.modifiers == .command, stroke.key == "w" || stroke.key == "q" {
                if !isRepeat {
                    session.requestEnd(quitting: stroke.key == "q")
                }
                return true
            }
            switch (session.overlay, stroke.key) {
            case (.search, _) where session.search.refusal != nil:
                return handleRefusal(stroke, isRepeat: isRepeat, session: session)
            case (.search, _):
                return handleSearch(stroke, isRepeat: isRepeat, session: session)
            case (.endConfirm, KeyStroke.returnKey):
                if !isRepeat {
                    session.confirmEnd()
                }
                return true
            case (.endConfirm, KeyStroke.escape):
                session.cancelEnd()
                return true
            case (.keys, KeyStroke.escape), (nil, KeyStroke.escape):
                session.dismissTopmost()
                return true
            default:
                return nil
            }
        }

        private static func handleSearch(
            _ stroke: KeyStroke,
            isRepeat: Bool,
            session: LiveSession,
        ) -> Bool {
            let search = session.search
            if search.requesting != nil {
                if isRepeat, stroke.key == KeyStroke.returnKey {
                    return true
                }
                return handleRequestNote(stroke, session: session)
            }
            switch stroke.key {
            case KeyStroke.escape:
                session.overlay = nil
            case KeyStroke.downArrow:
                search.moveSelection(1)
            case KeyStroke.upArrow:
                search.moveSelection(-1)
            case KeyStroke.returnKey:
                guard !isRepeat else { return true }
                let action: LiveSession.SearchAction = if stroke.modifiers.contains(.command) {
                    .addRequest
                } else if stroke.modifiers.contains(.option) {
                    .insertNext
                } else {
                    .playNow
                }
                session.submitSearch(action)
            default:
                return false
            }
            return true
        }

        /// The R102 refusal: Return moves the song to next (or goes back when there is
        /// nothing to move), Esc goes back to the results; other keys are swallowed.
        private static func handleRefusal(
            _ stroke: KeyStroke,
            isRepeat: Bool,
            session: LiveSession,
        ) -> Bool {
            switch stroke.key {
            case KeyStroke.returnKey where !isRepeat:
                session.confirmRefusal()
            case KeyStroke.escape:
                session.cancelRefusal()
            default:
                break
            }
            return true
        }

        /// The request note: Return adds (blank = no note), Esc goes back to the results;
        /// everything else types into the note field.
        private static func handleRequestNote(_ stroke: KeyStroke, session: LiveSession) -> Bool {
            switch stroke.key {
            case KeyStroke.returnKey:
                session.commitRequest()
            case KeyStroke.escape:
                session.search.cancelRequest()
            default:
                return false
            }
            return true
        }

        /// The binding-table form of `event`; nil for events without a usable key.
        static func keyStroke(_ event: NSEvent) -> KeyStroke? {
            var modifiers: KeyModifiers = []
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) {
                modifiers.insert(.command)
            }
            if flags.contains(.option) {
                modifiers.insert(.option)
            }
            if flags.contains(.control) {
                modifiers.insert(.control)
            }
            if let name = namedKeys[event.keyCode] {
                if flags.contains(.shift) {
                    modifiers.insert(.shift)
                }
                return KeyStroke(name, modifiers: modifiers)
            }
            // The character already carries Shift ("+" rather than Shift-"="), except for a
            // letter, whose case the stroke drops (Shift-M is the metronome click).
            guard let characters = event.charactersIgnoringModifiers, characters.count == 1
            else { return nil }
            if flags.contains(.shift), characters.first?.isLetter == true {
                modifiers.insert(.shift)
            }
            return KeyStroke(characters, modifiers: modifiers)
        }

        /// Virtual key codes of the named keys (layout independent).
        private static let namedKeys: [UInt16: String] = [
            123: KeyStroke.leftArrow,
            124: KeyStroke.rightArrow,
            125: KeyStroke.downArrow,
            126: KeyStroke.upArrow,
            116: KeyStroke.pageUp,
            121: KeyStroke.pageDown,
            115: KeyStroke.home,
            119: KeyStroke.end,
            49: KeyStroke.space,
            53: KeyStroke.escape,
            36: KeyStroke.returnKey,
            76: KeyStroke.returnKey,
        ]
    }
#endif
