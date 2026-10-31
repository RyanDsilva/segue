#if os(macOS)
    import AppKit
    import Editing
    import Library
    import SwiftUI

    /// The visual canvas's key-change chips and directive inserts (P8-7 sections 6.1, 6.2): a
    /// chip just above a section band when its chords look like another key,
    /// and "Insert Key / Time / Tempo Change Here..." in the band's menu.
    extension VisualEditorController {
        /// The section menu's insert items, for the section at `path` (its header).
        func directiveMenuItems(before path: BlockPath, band index: Int) -> [NSMenuItem] {
            ChartDirective.allCases.map { directive in
                ClosureMenuItem(title: directive.menuTitle) { [weak self] in
                    self?.showDirectivePopover(directive, before: path, band: index)
                }
            }
        }

        /// A separator and the insert items, at the end of a section menu.
        func addDirectiveItems(to menu: NSMenu, before path: BlockPath, band index: Int) {
            menu.addItem(.separator())
            for item in directiveMenuItems(before: path, band: index) {
                menu.addItem(item)
            }
        }

        /// The insert popover beside the band's cap (the band menu and Song > Insert).
        func showDirectivePopover(_ directive: ChartDirective, before path: BlockPath, band: Int?) {
            let anchor = if let band, let frame = bandFrame(band) {
                CGRect(
                    x: frame.rect.minX,
                    y: frame.rect.minY,
                    width: frame.rect.width,
                    height: SectionBandStyle.capHeight,
                )
            } else {
                CGRect(origin: textView.visibleRect.origin, size: CGSize(width: 1, height: 1))
                    .offsetBy(dx: 60, dy: 40)
            }
            popover?.close()
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = false
            popover.delegate = self
            let model = model
            let view = DirectiveInsertPopover(
                draft: model.directiveDraft(directive, before: path),
                sounding: { model.soundingKey($0) },
                insert: { model.insertDirective(directive, value: $0, before: path) },
                close: { [weak popover] in popover?.performClose(nil) },
            )
            let host = NSHostingController(rootView: view)
            host.sizingOptions = [.preferredContentSize]
            popover.contentViewController = host
            self.popover = popover
            popover.show(relativeTo: anchor, of: textView, preferredEdge: .maxX)
        }

        /// The band holding `path` (its header) or the selection, for Song > Insert.
        var insertionTarget: (path: BlockPath, band: Int?)? {
            if let selection = activeLineSelection,
               let band = bands.bands
                   .firstIndex(where: { $0.paragraphs.contains(selection.lowerBound) }),
               let path = bands.bands[band].sectionPath
            {
                return (path, band)
            }
            let caret = projection.paragraphs.isEmpty ? nil
                : projection.paragraphIndex(at: textView.selectedRange().location)
            guard let caret,
                  let band = bands.bands.firstIndex(where: { $0.paragraphs.contains(caret) }),
                  let path = bands.bands[band].sectionPath
            else { return nil }
            return (path, band)
        }
    }

    /// The chips on screen, one per suggested section whose band is visible: re-worked out
    /// after every reload, placed after every scroll or redraw.
    @MainActor
    final class KeyChangeChipHosts {
        private weak var controller: VisualEditorController?
        private(set) var suggestions: [KeyChangeSuggestion] = []
        private var hosts: [Int: NSHostingView<KeyChangeChip>] = [:]
        private var pending: Task<Void, Never>?

        init(controller: VisualEditorController) {
            self.controller = controller
        }

        /// The chips' sections now (tests).
        var shown: [KeyChangeSuggestion] {
            suggestions.filter { hosts[$0.section]?.isHidden == false }
        }

        /// After an edit: works the suggestions out again once typing pauses, off the
        /// keystroke path (a timeline and a key detection per section).
        func scheduleRefresh() {
            pending?.cancel()
            pending = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.settle)
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }

        /// How long typing must pause before the chips are worked out again.
        static let settle = Duration.milliseconds(350)

        /// Works the suggestions out again for the canvas's song now.
        func refresh() {
            guard let controller else { return }
            suggestions = controller.model.keyChangeSuggestions(controller.model.canvasModel)
            layout()
        }

        /// Puts each chip just above its band, or hides it.
        func layout() {
            guard let controller else { return }
            var placed = Set<Int>()
            for suggestion in suggestions {
                guard let path = suggestion.insertBefore,
                      let band = controller.bands.bands
                          .firstIndex(where: { $0.sectionPath == path }),
                      let frame = controller.bandFrame(band), frame.topVisible
                else { continue }
                let host = host(for: suggestion, in: controller)
                let fitting = host.fittingSize
                let size = CGSize(width: ceil(fitting.width), height: ceil(fitting.height))
                // In the gap above the band, where the lyrics start, as the preview has it:
                // it never covers a line.
                let corner = controller.textView.convert(
                    CGPoint(
                        x: controller.laneX.upperBound + CanvasTypesetting.bandLaneGap - 2,
                        y: frame.rect.minY - size.height - 4,
                    ),
                    to: controller.container,
                )
                let container = controller.container
                let y = container.isFlipped ? corner.y : corner.y - size.height
                host.frame = CGRect(x: corner.x, y: y, width: size.width, height: size.height)
                host.isHidden = false
                placed.insert(suggestion.section)
            }
            for (section, host) in hosts where !placed.contains(section) {
                host.isHidden = true
            }
        }

        private func host(
            for suggestion: KeyChangeSuggestion,
            in controller: VisualEditorController,
        ) -> NSHostingView<KeyChangeChip> {
            let model = controller.model
            let chip = KeyChangeChip(
                suggestion: suggestion,
                accept: { [weak model] in model?.acceptKeyChange(suggestion) },
                dismiss: { [weak self, weak model] in
                    model?.dismissKeyChange(suggestion)
                    self?.refresh()
                },
            )
            if let host = hosts[suggestion.section] {
                host.rootView = chip
                return host
            }
            let host = NSHostingView(rootView: chip)
            controller.container.addSubview(host)
            hosts[suggestion.section] = host
            return host
        }
    }
#endif

#if os(macOS)
    extension SongEditorViewModel {
        /// Song > Insert > Key / Time / Tempo Change...: at the line holding the cursor (text
        /// mode) or the selected section band (visual mode), with the same popover.
        func beginDirectiveInsert(_ directive: ChartDirective) {
            switch editorMode {
            case .visual:
                guard let target = visualEditor.insertionTarget else {
                    NSSound.beep()
                    return
                }
                visualEditor.showDirectivePopover(directive, before: target.path, band: target.band)
            case .text:
                showSourceDirectivePopover(directive)
            }
        }

        /// The insert popover at the cursor's line in the source: before that line (or before
        /// the section whose header it is).
        private func showSourceDirectivePopover(_ directive: ChartDirective) {
            let textView = sourceEditor.textView
            let location = textView.selectedRange().location
            guard let path = snapshot.path(atSourceOffset: location) else {
                NSSound.beep()
                return
            }
            let model = self
            var rect = textView.firstRect(
                forCharacterRange: NSRange(location: location, length: 0),
                actualRange: nil,
            )
            if let window = textView.window {
                rect = textView.convert(window.convertFromScreen(rect), from: nil)
            }
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = false
            let view = DirectiveInsertPopover(
                draft: model.directiveDraft(directive, before: path),
                sounding: { model.soundingKey($0) },
                insert: { model.insertDirective(directive, value: $0, before: path) },
                close: { [weak popover] in popover?.performClose(nil) },
            )
            let host = NSHostingController(rootView: view)
            host.sizingOptions = [.preferredContentSize]
            popover.contentViewController = host
            popover.show(
                relativeTo: rect.insetBy(dx: 0, dy: -2),
                of: textView,
                preferredEdge: .maxY,
            )
        }
    }
#endif
