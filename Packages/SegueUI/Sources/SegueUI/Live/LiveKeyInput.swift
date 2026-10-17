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
        static func handle(_ event: NSEvent, session: LiveSession) -> Bool {
            guard let stroke = keyStroke(event) else { return false }
            switch session.overlay {
            case .search:
                return handleSearch(stroke, session: session)
            case .endConfirm:
                if stroke.key == KeyStroke.returnKey {
                    session.confirmEnd()
                    return true
                }
                if stroke.key == KeyStroke.escape {
                    session.overlay = nil
                    return true
                }
            case nil:
                if stroke.key == KeyStroke.escape {
                    session.dismissTopmost()
                    return true
                }
            }
            guard let command = session.context.bindings.command(for: .key(stroke)) else {
                // Swallow plain unbound keys on stage (no beep); let Cmd combinations
                // (Cmd-Q) reach the app.
                return stroke.modifiers.isEmpty
            }
            session.dispatch(command)
            return true
        }

        private static func handleSearch(_ stroke: KeyStroke, session: LiveSession) -> Bool {
            let search = session.search
            if search.requesting != nil {
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
                guard let song = search.selected else { return true }
                let action: LiveSession.SearchAction = if stroke.modifiers.contains(.command) {
                    .addRequest
                } else if stroke.modifiers.contains(.option) {
                    .insertNext
                } else {
                    .playNow
                }
                session.searchAction(action, song: song.id)
            default:
                return false
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
            // The character already carries Shift ("+" rather than Shift-"=").
            guard let characters = event.charactersIgnoringModifiers, characters.count == 1
            else { return nil }
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
