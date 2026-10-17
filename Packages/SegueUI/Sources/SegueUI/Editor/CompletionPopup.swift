#if os(macOS)
    import AppKit
    import Observation
    import SwiftUI

    /// The `[` chord / `{` directive completion: a row of chips under the caret (mockup E2 a,
    /// "Chord  Em  E7  Esus4"). It floats in a child panel that never takes focus, so typing
    /// keeps going to the text view, which forwards ← → ↑ ↓, Return, Tab and Esc.
    @MainActor
    final class CompletionPopup {
        enum Kind: Equatable {
            case chord
            case directive

            var title: String {
                switch self {
                case .chord: "Chord"
                case .directive: "Directive"
                }
            }
        }

        private let state = CompletionPopupState()
        private var panel: CompletionPanel?
        /// Called with the index of a clicked chip.
        var onPick: ((Int) -> Void)? {
            get { state.onPick }
            set { state.onPick = newValue }
        }

        var isVisible: Bool {
            panel?.isVisible ?? false
        }

        var kind: Kind? {
            isVisible ? state.kind : nil
        }

        var selectedIndex: Int {
            state.selected
        }

        var items: [String] {
            state.items
        }

        /// Shows (or updates) the popup below `anchor` (screen coordinates, the caret rect).
        func show(kind: Kind, items: [String], below anchor: NSRect, parent: NSWindow) {
            guard !items.isEmpty else {
                hide()
                return
            }
            if state.kind != kind || state.items != items {
                state.selected = 0
            }
            state.kind = kind
            state.items = items
            state.selected = min(state.selected, items.count - 1)
            let panel = panel ?? makePanel()
            self.panel = panel
            guard let content = panel.contentView else { return }
            content.layoutSubtreeIfNeeded()
            let size = content.fittingSize
            let origin = NSPoint(x: anchor.minX - 10, y: anchor.minY - size.height - 6)
            panel.setFrame(NSRect(origin: origin, size: size), display: false)
            if panel.parent == nil {
                parent.addChildWindow(panel, ordered: .above)
            }
            panel.orderFront(nil)
        }

        /// Builds the panel ahead of the first `[`, so opening it costs no frame.
        func prepare() {
            guard panel == nil else { return }
            let panel = makePanel()
            panel.contentView?.layoutSubtreeIfNeeded()
            self.panel = panel
        }

        func hide() {
            guard let panel, panel.isVisible else { return }
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }

        func moveSelection(by delta: Int) {
            guard !state.items.isEmpty else { return }
            let count = state.items.count
            state.selected = ((state.selected + delta) % count + count) % count
        }

        private func makePanel() -> CompletionPanel {
            let panel = CompletionPanel(
                contentRect: NSRect(x: 0, y: 0, width: 200, height: 34),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true,
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.hidesOnDeactivate = true
            panel.isReleasedWhenClosed = false
            panel.setAccessibilityIdentifier(AccessibilityID.editorCompletions)
            let host = FirstMouseHostingView(rootView: CompletionChipsView(state: state))
            host.sizingOptions = [.intrinsicContentSize]
            panel.contentView = host
            return panel
        }
    }

    @MainActor
    @Observable
    final class CompletionPopupState {
        var kind: CompletionPopup.Kind = .chord
        var items: [String] = []
        var selected = 0
        @ObservationIgnored var onPick: ((Int) -> Void)?
    }

    /// A panel that never becomes key, so the text view keeps the keyboard.
    final class CompletionPanel: NSPanel {
        override var canBecomeKey: Bool {
            false
        }

        override var canBecomeMain: Bool {
            false
        }
    }

    /// Lets a click on a chip act immediately even though its panel is not key.
    final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
        override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
            true
        }
    }

    private struct CompletionChip: View {
        let title: String
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(SchibstedGrotesk.semiBold.font(size: 13))
                    .foregroundStyle(isSelected ? Theme.color.ground : Theme.color.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(chipBackground)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.editorCompletion)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }

        private var chipBackground: some View {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isSelected ? Theme.color.ink : Color.clear)
        }
    }

    private struct CompletionChipsView: View {
        let state: CompletionPopupState

        var body: some View {
            HStack(spacing: 6) {
                Text(state.kind.title)
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.muted)
                    .padding(.trailing, 2)
                ForEach(Array(state.items.enumerated()), id: \.offset) { index, item in
                    CompletionChip(title: item, isSelected: index == state.selected) {
                        state.onPick?(index)
                    }
                }
            }
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Theme.color.ground, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.color.controlBorder, lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(state.kind.title) suggestions")
        }
    }
#endif
