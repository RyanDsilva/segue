#if os(macOS)
    import AppKit
    import Editing
    import MusicTheory
    import SwiftUI

    /// Canvas gestures (phase 1 spec, "Visual mode"): click a chord slot to add a chord
    /// (popover with autocomplete, or drop the armed palette chord), drag a pill to move it
    /// with snapping, Option-drag to duplicate, Option-click to hear it (P8-6), Backspace to
    /// delete, double-click or Return to edit, ← → to nudge.
    extension VisualEditorController: CanvasGestureHandling {
        private func point(of event: NSEvent) -> CGPoint {
            textView.convert(event.locationInWindow, from: nil)
        }

        func canvasMouseDown(_ event: NSEvent) -> Bool {
            if bandMouseDown(event) {
                return true
            }
            let location = point(of: event)
            if let pill = pill(at: location) {
                textView.window?.makeFirstResponder(textView)
                if spanClick(pill, event: event) {
                    return true
                }
                selectedChord = ChordSelection(
                    path: pill.line.path,
                    offset: pill.chord.offset,
                    original: pill.chord.original,
                )
                if event.clickCount >= 2 {
                    drag = nil
                    showEditPopover(pill)
                } else {
                    drag = ChordDrag(
                        pill: pill,
                        start: location,
                        current: location,
                        duplicate: event.modifierFlags.contains(.option),
                    )
                }
                redrawOverlay()
                return true
            }
            if let target = laneTarget(at: location, laneOnly: true) {
                textView.window?.makeFirstResponder(textView)
                selectedChord = nil
                if let armed = model.armedChord {
                    insert(armed, at: target)
                    model.armedChordPlaced()
                } else {
                    showAddPopover(at: target)
                }
                redrawOverlay()
                return true
            }
            if selectedChord != nil || model.spanSelection.anchor != nil {
                selectedChord = nil
                model.spanSelection.clear()
                showSpanCapsule()
                redrawOverlay()
            }
            return false
        }

        /// Shift-click: the fill span from the last pill clicked or played (P8-7 12.1),
        /// silently (true: handled); a plain click also anchors it.
        private func spanClick(_ pill: PillLayout, event: NSEvent) -> Bool {
            guard pill.chord.kind == .chord else { return false }
            if event.modifierFlags.contains(.shift) {
                model.extendFillSpan(line: pill.line.path, offset: pill.chord.offset)
                selectedChord = nil
                showSpanCapsule()
                redrawOverlay()
                return true
            }
            model.anchorFillSpan(line: pill.line.path, offset: pill.chord.offset)
            showSpanCapsule()
            return false
        }

        func canvasMouseDragged(_ event: NSEvent) -> Bool {
            if bandMouseDragged(event) {
                return true
            }
            guard var current = drag else { return false }
            let location = point(of: event)
            current.current = location
            if !current.isDragging, hypot(
                location.x - current.start.x,
                location.y - current.start.y,
            ) > 3 {
                current.isDragging = true
            }
            if current.isDragging {
                current.duplicate = event.modifierFlags.contains(.option)
                current.target = laneTarget(at: location, laneOnly: false)
                (current.duplicate ? NSCursor.dragCopy : NSCursor.closedHand).set()
                textView.autoscroll(with: event)
            }
            drag = current
            redrawOverlay()
            return true
        }

        func canvasMouseUp(_ event: NSEvent) -> Bool {
            if bandMouseUp(event) {
                return true
            }
            guard let finished = drag else { return false }
            drag = nil
            defer { redrawOverlay() }
            // ⌥-click (no drag) plays the chord (P8-6 10.1); a plain click selects it.
            if !finished.isDragging, finished.duplicate {
                model.hearChord(written: finished.pill.chord.original)
                return true
            }
            guard finished.isDragging, let target = finished.target else { return true }
            let pill = finished.pill
            let position = LyricPosition(line: target.path, offset: target.offset)
            let moved = target.path != pill.line.path || target.offset != pill.chord.offset
            guard finished.duplicate || moved else { return true }
            selectedChord = ChordSelection(
                path: target.path,
                offset: target.offset,
                original: pill.chord.original,
            )
            if finished.duplicate {
                model.perform(.duplicateChord(pill.chord.ref, to: position))
            } else {
                if model.perform(.moveChord(pill.chord.ref, to: position)) {
                    SegueTips.chordMoved()
                }
            }
            resolveSelection()
            NSCursor.openHand.set()
            return true
        }

        func canvasMouseMoved(_ event: NSEvent) {
            guard drag == nil, bandGesture == nil else { return }
            if bandMouseMoved(event) {
                if hover != nil {
                    hover = nil
                    redrawOverlay()
                }
                return
            }
            let location = point(of: event)
            let overPill = pill(at: location) != nil
            let target = overPill ? nil : laneTarget(at: location, laneOnly: true)
            if overPill {
                NSCursor.openHand.set()
            } else if target != nil {
                NSCursor.pointingHand.set()
            }
            if target != hover {
                hover = target
                redrawOverlay()
            }
        }

        func canvasMouseExited() {
            if hover != nil || hoveredEdge != nil {
                hover = nil
                hoveredEdge = nil
                redrawOverlay()
            }
        }

        func canvasMenu(for event: NSEvent) -> NSMenu? {
            bandMenu(for: event)
        }

        func canvasDidResize() {
            redrawOverlay()
        }

        #if DEBUG
            func canvasKeystrokeTimed(_ seconds: TimeInterval, isShortcut: Bool) {
                model.recordKeystroke(seconds, isShortcut: isShortcut)
            }
        #endif

        // MARK: Keys on a selected pill

        func canvasKeyDown(_ event: NSEvent) -> Bool {
            if bandKeyDown(event) {
                return true
            }
            if model.armedChord != nil, event.keyCode == KeyCode.escape {
                model.armedChord = nil
                redrawOverlay()
                return true
            }
            guard let selection = selectedChord, let target = chord(for: selection) else {
                selectedChord = nil
                return false
            }
            switch event.keyCode {
            case KeyCode.delete, KeyCode.forwardDelete:
                selectedChord = nil
                model.perform(.deleteChord(target.chord.ref))
            case KeyCode.leftArrow:
                nudge(target.chord, on: target.line, by: -1)
            case KeyCode.rightArrow:
                nudge(target.chord, on: target.line, by: 1)
            case KeyCode.enter, KeyCode.returnKey:
                if let pill = layout(of: selection) {
                    showEditPopover(pill)
                }
            case KeyCode.escape:
                selectedChord = nil
            default:
                selectedChord = nil
                redrawOverlay()
                return false
            }
            redrawOverlay()
            return true
        }

        private func nudge(_ chord: RenderChord, on line: RenderLine, by delta: Int) {
            let offset = chord.offset + delta
            guard (0 ... line.lyricCount).contains(offset) else {
                NSSound.beep()
                return
            }
            let position = LyricPosition(line: line.path, offset: offset)
            // Select the moved chord before the edit: the canvas re-resolves the selection
            // while it reloads.
            let previous = selectedChord
            selectedChord?.offset = offset
            if !model.perform(.moveChord(chord.ref, to: position)) {
                selectedChord = previous
            }
        }

        // MARK: Accessibility actions on a pill

        /// "Move left one syllable", "Move right one syllable", "Edit chord", "Delete chord":
        /// each slot above a word is a syllable in the editor's words, so a move goes to the
        /// start of the previous or next word slot.
        func chordActions(for selection: ChordSelection) -> [NSAccessibilityCustomAction] {
            [
                NSAccessibilityCustomAction(name: "Move left one syllable") { [weak self] in
                    self?.moveChord(selection, bySlots: -1) ?? false
                },
                NSAccessibilityCustomAction(name: "Move right one syllable") { [weak self] in
                    self?.moveChord(selection, bySlots: 1) ?? false
                },
                NSAccessibilityCustomAction(name: "Edit chord") { [weak self] in
                    guard let self, let pill = layout(of: selection) else { return false }
                    selectedChord = selection
                    showEditPopover(pill)
                    return true
                },
                NSAccessibilityCustomAction(name: "Delete chord") { [weak self] in
                    guard let self, let target = chord(for: selection) else { return false }
                    selectedChord = nil
                    let deleted = model.perform(.deleteChord(target.chord.ref))
                    redrawOverlay()
                    return deleted
                },
            ]
        }

        /// Moves the chord to the start of the word slot `delta` slots away.
        func moveChord(_ selection: ChordSelection, bySlots delta: Int) -> Bool {
            guard let target = chord(for: selection) else { return false }
            let words = LyricOffsets.words(in: target.line)
            let current = words.lastIndex { $0.offsets.lowerBound <= target.chord.offset } ?? 0
            let next = current + delta
            guard words.indices.contains(next) else {
                NSSound.beep()
                return false
            }
            let offset = words[next].offsets.lowerBound
            let position = LyricPosition(line: target.line.path, offset: offset)
            selectedChord = selection
            selectedChord?.offset = offset
            let moved = model.perform(.moveChord(target.chord.ref, to: position))
            if moved {
                SegueTips.chordMoved()
            } else {
                selectedChord = selection
            }
            redrawOverlay()
            return moved
        }

        // MARK: Adding and editing chords

        /// Inserts a chord typed in the display key at a slot.
        func insert(_ displayed: String, at target: LaneTarget) {
            let source = model.inputTransform.sourceChord(fromDisplayed: displayed)
            let position = LyricPosition(line: target.path, offset: target.offset)
            model.perform(.insertChord(source, at: position))
        }

        func showAddPopover(at target: LaneTarget) {
            popoverTarget = target
            let anchor = CGRect(
                origin: target.anchor,
                size: CGSize(width: 30, height: CanvasTypesetting.pillHeight),
            )
            // A chord already on that character is replaced, never stacked.
            let existing = projection.paragraphs[target.paragraph].lyricLine?.chords
                .last { $0.offset == target.offset }
            let shown = existing.map {
                model.inputTransform.display(ChordToken(parsing: $0.original))
            }
            presentPopover(
                title: existing == nil ? "Add chord" : "Replace chord",
                initial: shown ?? "",
                anchor: anchor,
                onDelete: nil,
            ) { [weak self] text in
                // Committing the chord that is already there changes nothing.
                guard text != shown else { return }
                self?.insert(text, at: target)
            }
        }

        func showEditPopover(_ pill: PillLayout) {
            let ref = pill.chord.ref
            presentPopover(
                title: "Edit chord",
                initial: shownText(of: pill.chord),
                anchor: pill.rect,
                onDelete: { [weak self] in
                    self?.selectedChord = nil
                    self?.model.perform(.deleteChord(ref))
                },
                onCommit: { [weak self] text in
                    self?.commitEdit(of: pill.chord, on: pill.line, typed: text)
                },
            )
        }

        /// What the edit popover starts with: the chord as the view shows it.
        func shownText(of chord: RenderChord) -> String {
            model.inputTransform.display(ChordToken(parsing: chord.original))
        }

        /// The edit popover's commit. Unchanged text is a no-op: mapping it back from the
        /// display key would respell the source chord (`G#` -> `Ab`).
        func commitEdit(of chord: RenderChord, on line: RenderLine, typed displayed: String) {
            guard displayed != shownText(of: chord) else { return }
            let source = model.inputTransform.sourceChord(fromDisplayed: displayed)
            let previous = selectedChord
            selectedChord = ChordSelection(path: line.path, offset: chord.offset, original: source)
            if !model.perform(.replaceChord(chord.ref, with: source)) {
                selectedChord = previous
            }
        }

        private func presentPopover(
            title: String,
            initial: String,
            anchor: CGRect,
            onDelete: (() -> Void)?,
            onCommit: @escaping (String) -> Void,
        ) {
            popover?.close()
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = false
            popover.delegate = self
            let content = ChordPopoverView(
                title: title,
                initial: initial,
                suggestions: { [weak model] prefix in
                    model?.displayChordSuggestions(prefix: prefix) ?? []
                },
                onCommit: { [weak popover] text in
                    popover?.performClose(nil)
                    onCommit(text)
                },
                onDelete: onDelete.map { delete in
                    { [weak popover] in
                        popover?.performClose(nil)
                        delete()
                    }
                },
                onCancel: { [weak popover] in popover?.performClose(nil) },
            )
            let host = NSHostingController(rootView: content)
            host.sizingOptions = [.preferredContentSize]
            popover.contentViewController = host
            self.popover = popover
            popover.show(relativeTo: anchor, of: textView, preferredEdge: .minY)
            redrawOverlay()
        }
    }

    extension VisualEditorController: NSPopoverDelegate {
        func popoverDidClose(_: Notification) {
            popover = nil
            popoverTarget = nil
            redrawOverlay()
        }
    }

    /// Virtual key codes the canvas handles.
    enum KeyCode {
        static let returnKey: UInt16 = 36
        static let delete: UInt16 = 51
        static let escape: UInt16 = 53
        static let enter: UInt16 = 76
        static let forwardDelete: UInt16 = 117
        static let leftArrow: UInt16 = 123
        static let rightArrow: UInt16 = 124
    }
#endif
