#if os(macOS)
    import AppKit
    import ChordPro
    import Editing
    import SwiftUI

    /// Section band gestures (P3-11): pick lines in the lane (click a band or drag), press
    /// V / C / B / I or click a chip to make or relabel a section, drag a band edge to
    /// resize it, double-click the cap to rename, right-click for the section menu.
    extension VisualEditorController {
        private func lanePoint(_ event: NSEvent) -> CGPoint {
            textView.convert(event.locationInWindow, from: nil)
        }

        // MARK: Mouse

        /// Returns true when the lane took the event.
        func bandMouseDown(_ event: NSEvent) -> Bool {
            let point = lanePoint(event)
            guard isInLane(point) else {
                if lineSelection != nil {
                    lineSelection = nil
                    redrawOverlay()
                }
                return false
            }
            textView.window?.makeFirstResponder(textView)
            selectedChord = nil
            if let hit = edgeHit(at: point) {
                bandGesture = .resizing(hit, target: nil)
                redrawOverlay()
                return true
            }
            let band = bandIndex(at: point)
            if let band, let path = noteBadgeHit(point, band: band) {
                bandGesture = nil
                model.showSectionNotes(forSectionAt: path)
                return true
            }
            if event.clickCount >= 2, let band, isOnCap(point, band: band) {
                bandGesture = nil
                beginRename(band: band)
                return true
            }
            guard let row = paragraph(atY: point.y) else { return true }
            if event.modifierFlags.contains(.shift), let current = activeLineSelection {
                let lower = min(current.lowerBound, row.index)
                let upper = max(current.upperBound, row.index)
                lineSelection = lower ... upper
                bandGesture = nil
            } else {
                bandGesture = .selecting(anchor: row.index)
                lineSelection = band.map { bands.bands[$0].paragraphs } ?? row.index ... row.index
            }
            textView.setSelectedRange(NSRange(
                location: textView.selectedRange().location,
                length: 0,
            ))
            redrawOverlay()
            return true
        }

        func bandMouseDragged(_ event: NSEvent) -> Bool {
            guard let gesture = bandGesture else { return false }
            let point = lanePoint(event)
            textView.autoscroll(with: event)
            switch gesture {
            case let .selecting(anchor):
                guard let row = paragraph(atY: point.y) else { return true }
                lineSelection = min(anchor, row.index) ... max(anchor, row.index)
            case let .resizing(hit, _):
                NSCursor.resizeUpDown.set()
                bandGesture = .resizing(hit, target: paragraph(atY: point.y)?.index)
            }
            redrawOverlay()
            return true
        }

        func bandMouseUp(_: NSEvent) -> Bool {
            guard let gesture = bandGesture else { return false }
            bandGesture = nil
            defer { redrawOverlay() }
            guard case let .resizing(hit, target?) = gesture,
                  let path = bands.bands[hit.band].sectionPath,
                  bands.paths.indices.contains(target), let line = bands.paths[target]
            else { return true }
            model.perform(.moveSectionEdge(path, edge: hit.edge, toLine: line))
            return true
        }

        /// Cursor and grip over the lane; false when the pointer is outside it.
        func bandMouseMoved(_ event: NSEvent) -> Bool {
            let point = lanePoint(event)
            let hit = edgeHit(at: point)
            if hit != hoveredEdge {
                hoveredEdge = hit
                redrawOverlay()
            }
            guard isInLane(point) else { return false }
            (hit == nil ? NSCursor.arrow : NSCursor.resizeUpDown).set()
            return true
        }

        private func isOnCap(_ point: CGPoint, band: Int) -> Bool {
            guard let frame = bandFrame(band), frame.topVisible,
                  bands.bands[band].sectionPath != nil
            else { return false }
            return point.y <= frame.rect.minY + SectionBandStyle.capHeight + 2
        }

        // MARK: Keys

        /// V / C / B / I make or relabel a section while lines are selected; Esc drops the
        /// lane selection. Any other key drops it and goes on to the text.
        func bandKeyDown(_ event: NSEvent) -> Bool {
            guard activeLineSelection != nil else { return false }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            if event.keyCode == KeyCode.escape, lineSelection != nil {
                lineSelection = nil
                redrawOverlay()
                return true
            }
            if modifiers.isEmpty, let key = event.charactersIgnoringModifiers?.lowercased(),
               let kind = SectionChip.quick.first(where: { $0.key == key })?.kind
            {
                applySection(kind)
                return true
            }
            if lineSelection != nil {
                lineSelection = nil
                redrawOverlay()
            }
            return false
        }

        // MARK: Making and relabelling

        /// Makes a section of `kind` around the selected lines, or relabels the section
        /// when the selection is exactly one section. Beeps when the lines are inside or
        /// across a section.
        @discardableResult
        func applySection(_ kind: SectionKind) -> Bool {
            guard let selection = activeLineSelection else { return false }
            let done = apply(kind, to: selection)
            if done {
                lineSelection = nil
                textView.setSelectedRange(NSRange(
                    location: textView.selectedRange().location,
                    length: 0,
                ))
            } else {
                NSSound.beep()
            }
            redrawOverlay()
            return done
        }

        private func apply(_ kind: SectionKind, to selection: ClosedRange<Int>) -> Bool {
            let path = { (index: Int) -> BlockPath? in
                self.bands.paths.indices.contains(index) ? self.bands.paths[index] : nil
            }
            let touched = Set(selection.compactMap { index in
                bands.bands.firstIndex { $0.sectionPath != nil && $0.paragraphs.contains(index) }
            })
            if let only = touched.first {
                // Exactly one whole section selected (plus, at most, rows with no source
                // line around it): relabel it. Part of a section, or several: refused.
                let band = bands.bands[only]
                let outside = selection.filter { !band.paragraphs.contains($0) && path($0) != nil }
                guard touched.count == 1, outside.isEmpty,
                      selection.contains(band.paragraphs.lowerBound),
                      selection.contains(band.paragraphs.upperBound),
                      case let .section(section, current, _, _) = band.kind
                else { return false }
                if DirectiveLine.sameSectionKind(current, kind) {
                    return true
                }
                return model.perform(.changeSectionKind(section, to: kind))
            }
            let paths = selection.compactMap(path)
            guard let first = paths.first, let last = paths.last,
                  paths.allSatisfy({ $0.item == nil })
            else { return false }
            return model.perform(.createSection(first: first, last: last, kind: kind))
        }

        /// Asks for a custom section name, then applies it.
        func applyCustomSection() {
            guard let name = askSectionName() else { return }
            applySection(SectionChip.kind(named: name))
        }

        private func askSectionName() -> String? {
            let alert = NSAlert()
            alert.messageText = "Custom Section"
            alert.informativeText = "Name the section, for example Pre-Chorus or Solo."
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
            field.placeholderString = "Section name"
            field.setAccessibilityIdentifier(AccessibilityID.sectionBandCustomField)
            alert.accessoryView = field
            alert.addButton(withTitle: "Make Section")
            alert.addButton(withTitle: "Cancel")
            alert.window.initialFirstResponder = field
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : name
        }

        // MARK: Section menu

        func bandMenu(for event: NSEvent) -> NSMenu? {
            let point = lanePoint(event)
            guard isInLane(point), let index = bandIndex(at: point) else { return nil }
            let band = bands.bands[index]
            switch band.kind {
            case .section:
                return sectionMenu(band: index, at: point)
            case .slot:
                lineSelection = band.paragraphs
                redrawOverlay()
                let menu = NSMenu(title: "Section")
                for chip in SectionChip.all {
                    menu.addItem(item("Make \(chip.title)") { [weak self] in
                        self?.applySection(chip.kind)
                    })
                }
                return menu
            case .repeatRef:
                return nil
            }
        }

        /// Rename, Change Kind, Unwrap, Split Here (at the line under the pointer), Merge
        /// with Next.
        private func sectionMenu(band index: Int, at point: CGPoint) -> NSMenu? {
            let band = bands.bands[index]
            guard let path = band.sectionPath else { return nil }
            let menu = NSMenu(title: "Section")
            menu.autoenablesItems = false
            menu.addItem(item("Rename...") { [weak self] in self?.beginRename(band: index) })
            let kinds = NSMenuItem(title: "Change Kind", action: nil, keyEquivalent: "")
            kinds.submenu = kindMenu(path)
            menu.addItem(kinds)
            menu
                .addItem(item("Unwrap") { [weak self] in
                    self?.model.perform(.unwrapSection(path))
                })
            let split = paragraph(atY: point.y).flatMap { row -> BlockPath? in
                guard bands.paths.indices.contains(row.index), let line = bands.paths[row.index],
                      line.block == path.block, (line.item ?? 0) > 0
                else { return nil }
                return line
            }
            let splitItem = item("Split Here") { [weak self] in
                if let split {
                    self?.model.perform(.splitSection(path, atLine: split))
                }
            }
            splitItem.isEnabled = split != nil
            menu.addItem(splitItem)
            let next = bands.sections(after: band).first
            let mergeItem = item("Merge with Next") { [weak self] in
                if let next {
                    self?.merge(band, with: next)
                }
            }
            mergeItem.isEnabled = next != nil
            menu.addItem(mergeItem)
            menu.addItem(.separator())
            menu.addItem(item("Section Notes...") { [weak self] in
                self?.model.showSectionNotes(forSectionAt: path)
            })
            return menu
        }

        private func kindMenu(_ path: BlockPath) -> NSMenu {
            let menu = NSMenu(title: "Change Kind")
            for chip in SectionChip.all + [SectionChip(key: "", title: "Tab", kind: .tab)] {
                menu.addItem(item(chip.title) { [weak self] in
                    self?.model.perform(.changeSectionKind(path, to: chip.kind))
                })
            }
            menu.addItem(item("Custom...") { [weak self] in
                guard let self, let name = askSectionName() else { return }
                model.perform(.changeSectionKind(path, to: SectionChip.kind(named: name)))
            })
            return menu
        }

        /// Merges two sections; asks which kind when they differ.
        func merge(_ first: SectionBand, with second: SectionBand) {
            guard case let .section(path, kind, _, _) = first.kind,
                  case let .section(nextPath, nextKind, _, _) = second.kind
            else { return }
            if DirectiveLine.sameSectionKind(kind, nextKind) {
                model.perform(.mergeSections(first: path, second: nextPath, kind: nil))
                return
            }
            let alert = NSAlert()
            alert.messageText = "Merge as which kind?"
            alert.informativeText = "\(first.title) and \(second.title) are different kinds."
            alert.addButton(withTitle: SectionLabels.displayName(kind))
            alert.addButton(withTitle: SectionLabels.displayName(nextKind))
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                model.perform(.mergeSections(first: path, second: nextPath, kind: kind))
            case .alertSecondButtonReturn:
                model.perform(.mergeSections(first: path, second: nextPath, kind: nextKind))
            default:
                break
            }
        }

        private func item(_ title: String, _ action: @escaping () -> Void) -> NSMenuItem {
            let item = ClosureMenuItem(title: title, handler: action)
            item.isEnabled = true
            return item
        }

        // MARK: Rename

        func beginRename(band index: Int) {
            guard bands.bands.indices.contains(index),
                  let path = bands.bands[index].sectionPath,
                  let frame = bandFrame(index)
            else { return }
            let band = bands.bands[index]
            let anchor = CGRect(
                x: frame.rect.minX,
                y: frame.rect.minY,
                width: frame.rect.width,
                height: SectionBandStyle.capHeight,
            )
            popover?.close()
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = false
            popover.delegate = self
            let view = SectionRenameView(initial: band.title) { [weak self, weak popover] text in
                popover?.performClose(nil)
                guard let text else { return }
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                self?.rename(path, to: trimmed.isEmpty ? nil : trimmed)
            }
            let host = NSHostingController(rootView: view)
            host.sizingOptions = [.preferredContentSize]
            popover.contentViewController = host
            self.popover = popover
            popover.show(relativeTo: anchor, of: textView, preferredEdge: .maxX)
        }

        @discardableResult
        func rename(_ path: BlockPath, to label: String?) -> Bool {
            model.perform(.setSectionLabel(path, label: label))
        }
    }

    /// One line up or down for an edge.
    struct EdgeMove {
        var edge: SectionEdge
        var delta: Int
    }

    /// An accessibility element whose press runs a closure.
    final class BandAccessibilityElement: NSAccessibilityElement {
        var press: (() -> Bool)?

        override func accessibilityPerformPress() -> Bool {
            press?() ?? false
        }
    }

    /// A menu item that runs a closure.
    final class ClosureMenuItem: NSMenuItem {
        private let handler: () -> Void

        init(title: String, handler: @escaping () -> Void) {
            self.handler = handler
            super.init(title: title, action: #selector(run), keyEquivalent: "")
            target = self
        }

        @available(*, unavailable)
        required init(coder _: NSCoder) {
            fatalError("ClosureMenuItem is not decodable")
        }

        @objc private func run() {
            handler()
        }
    }
#endif
