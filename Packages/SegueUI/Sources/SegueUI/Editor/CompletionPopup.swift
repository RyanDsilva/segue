#if os(macOS)
    import AppKit
    import Observation
    import SwiftUI

    /// The editor's own keys, which are not menu items, for Help > Keyboard Shortcuts. Kept
    /// here, beside the completion and canvas key handling that own them.
    enum EditorKeys {
        struct Row {
            let title: String
            let keys: String
        }

        static let rows = [
            Row(title: uiString("Suggest chords (text mode)"), keys: "["),
            Row(title: uiString("Suggest directives (text mode)"), keys: "{"),
            Row(
                title: uiString("Insert a section or note (text mode, at a line start)"),
                keys: "/",
            ),
            Row(title: uiString("Choose a suggestion"), keys: "← →  ↑ ↓"),
            Row(title: uiString("Accept a suggestion"), keys: "↩  ⇥"),
            Row(title: uiString("Close suggestions, drop a picked-up chord"), keys: "⎋"),
            Row(title: uiString("Delete the selected chord pill"), keys: "⌫"),
            Row(title: uiString("Nudge the selected chord pill"), keys: "← →"),
            Row(title: uiString("Edit the selected chord pill"), keys: "↩"),
        ]
    }

    /// The `[` chord completion (a row of chips under the caret, mockup E2 a, "Chord  Em  E7
    /// Esus4") and the `{` directive and `/` slash menus (a vertical list of plain names with
    /// the directive beside each, R81). It floats in a child panel that never takes focus,
    /// so typing keeps going to the text view, which forwards ↑ ↓ (and ← → for chips),
    /// Return, Tab and Esc.
    @MainActor
    final class CompletionPopup {
        enum Kind: Equatable {
            case chord
            case directive
            case slash

            var title: String {
                switch self {
                case .chord: "Chord"
                case .directive: "Directive"
                case .slash: "Insert"
                }
            }

            /// Chips run left to right; the menus are vertical lists.
            var isList: Bool {
                self != .chord
            }
        }

        /// One row or chip: its plain name and, in the lists, what it writes.
        struct Entry: Equatable {
            let title: String
            var detail: String?
        }

        private let state = CompletionPopupState()
        /// Set while the slash menu filters a selection to wrap.
        var slashSelection: SlashSelectionSession?
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

        var items: [Entry] {
            state.items
        }

        /// Shows (or updates) the popup below `anchor` (screen coordinates, the caret rect).
        /// `header` replaces the kind's title (the slash menu's typed filter).
        func show(
            kind: Kind,
            items: [Entry],
            header: String? = nil,
            below anchor: NSRect,
            parent: NSWindow,
        ) {
            // A list with a header may show the header alone (Text mode's value hints).
            guard !items.isEmpty || (header != nil && kind.isList) else {
                hide()
                return
            }
            if state.kind != kind || state.items != items {
                state.selected = 0
            }
            state.kind = kind
            state.header = header
            state.items = items
            state.selected = max(0, min(state.selected, items.count - 1))
            let panel = panel ?? makePanel()
            self.panel = panel
            guard let content = panel.contentView else { return }
            content.layoutSubtreeIfNeeded()
            let size = content.fittingSize
            let origin = NSPoint(x: anchor.minX - 10, y: anchor.minY - size.height - 6)
            panel.setAccessibilityIdentifier(
                kind == .slash ? AccessibilityID.slashMenu : AccessibilityID.editorCompletions,
            )
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
            slashSelection = nil
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
        var items: [CompletionPopup.Entry] = []
        var header: String?
        var selected = 0
        @ObservationIgnored var onPick: ((Int) -> Void)?
    }

    /// A slash menu opened on a selection: the typed filter goes to the menu (not the
    /// text, which would replace the selection), and the selection is what gets wrapped.
    struct SlashSelectionSession: Equatable {
        /// The selection being wrapped (UTF-16).
        var selection: NSRange
        /// What has been typed after the `/`.
        var query = ""
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
            Group {
                if state.kind.isList {
                    CompletionListView(state: state)
                } else {
                    chips
                }
            }
            .background(Theme.color.ground, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.color.controlBorder, lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(uiString("\(state.kind.title) suggestions"))
        }

        private var chips: some View {
            HStack(spacing: 6) {
                Text(state.kind.title)
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.muted)
                    .padding(.trailing, 2)
                ForEach(Array(state.items.enumerated()), id: \.offset) { index, item in
                    CompletionChip(title: item.title, isSelected: index == state.selected) {
                        state.onPick?(index)
                    }
                }
            }
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    /// The vertical list variant: a small header, then one row per entry with its plain
    /// name and, muted on the right, the directive it writes; the selected row is filled.
    private struct CompletionListView: View {
        let state: CompletionPopupState

        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                Text(state.header ?? state.kind.title)
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.muted)
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
                    .padding(.bottom, 3)
                    .accessibilityIdentifier(
                        state.kind == .slash
                            ? AccessibilityID.slashMenuFilter : AccessibilityID
                            .editorCompletionsHeader,
                    )
                ForEach(Array(state.items.enumerated()), id: \.offset) { index, item in
                    CompletionRow(
                        entry: item,
                        isSelected: index == state.selected,
                        identifier: state.kind == .slash
                            ? AccessibilityID.slashMenuItem : AccessibilityID.editorCompletion,
                    ) {
                        state.onPick?(index)
                    }
                }
            }
            .padding(5)
            .frame(width: 320, alignment: .leading)
        }
    }

    private struct CompletionRow: View {
        let entry: CompletionPopup.Entry
        let isSelected: Bool
        let identifier: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 10) {
                    Text(entry.title)
                        .font(SchibstedGrotesk.semiBold.font(size: 13))
                        .foregroundStyle(isSelected ? Theme.color.ground : Theme.color.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let detail = entry.detail {
                        Text(detail)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(isSelected ? Theme.color.ground : Theme.color.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Theme.color.ink : Color.clear),
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.title)
            .accessibilityValue(entry.detail ?? "")
            .accessibilityIdentifier(identifier)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
#endif
