#if os(macOS)
    import AppKit
    import SwiftUI

    /// A list in the brand's quiet style (mockup L1 a): hairline `line` separators and the
    /// selected rows on brand grey (`surfaceAlt`; `line` in dark), text staying in its own
    /// colours, instead of the system's accent-blue highlight with white text. Click
    /// selects; Up/Down move the selection while the list has keyboard focus, and the
    /// focused row is kept scrolled into view.
    ///
    /// Single selection by default. Built with a `ListSelection` binding and
    /// `allowsMultiple`, it follows Finder's multi-selection rules (R84): ⌘-click toggles a
    /// row, ⇧-click selects a range, ⇧↑ / ⇧↓ extend it; a plain click still selects one row.
    struct SelectableList<Data: RandomAccessCollection, Row: View, Menu: View>: View
        where Data.Element: Identifiable
    {
        typealias RowID = Data.Element.ID

        let items: Data
        @Binding var selection: ListSelection<RowID>
        /// Whether ⌘-click, ⇧-click and ⇧↑ / ⇧↓ select several rows.
        var allowsMultiple = false
        @ViewBuilder let row: (Data.Element) -> Row
        /// The row's context menu, on the whole row (its hit shape), not just its content.
        @ViewBuilder var menu: (Data.Element) -> Menu
        @FocusState private var focused: Bool
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        /// `surfaceAlt` on paper; on the dark ground it is too close to tell, so `line`.
        private var selectedFill: Color {
            colorScheme == .dark ? Theme.color.line : Theme.color.surfaceAlt
        }

        var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            rowView(item)
                        }
                    }
                }
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                    let delta = press.key == .upArrow ? -1 : 1
                    return move(delta, extending: press.modifiers.contains(.shift))
                }
                .onChange(of: selection.focus) { _, id in
                    guard let id else { return }
                    // Instant with Reduce Motion (brand.md section 8).
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                        proxy.scrollTo(id)
                    }
                }
            }
        }

        private var order: [RowID] {
            items.map(\.id)
        }

        private func rowView(_ item: Data.Element) -> some View {
            let isSelected = selection.contains(item.id)
            return row(item)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSelected ? selectedFill : Color.clear)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.color.line).frame(height: 1)
                }
                .contentShape(Rectangle())
                .contextMenu { menu(item) }
                .onTapGesture {
                    focused = true
                    click(item.id, modifiers: NSEvent.modifierFlags)
                }
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                .accessibilityAction { selection.select(item.id) }
                .id(item.id)
        }

        private func click(_ id: RowID, modifiers: NSEvent.ModifierFlags) {
            guard allowsMultiple else {
                selection.select(id)
                return
            }
            if modifiers.contains(.command) {
                selection.toggle(id, in: order)
            } else if modifiers.contains(.shift) {
                selection.extend(to: id, in: order)
            } else {
                selection.select(id)
            }
        }

        private func move(_ delta: Int, extending: Bool) -> KeyPress.Result {
            guard !items.isEmpty else { return .ignored }
            selection.move(delta, in: order, extending: extending && allowsMultiple)
            return .handled
        }
    }

    extension SelectableList {
        /// A single-selection list bound to the selected row's ID.
        init(
            items: Data,
            selection: Binding<RowID?>,
            @ViewBuilder row: @escaping (Data.Element) -> Row,
            @ViewBuilder menu: @escaping (Data.Element) -> Menu,
        ) {
            self.init(
                items: items,
                selection: Binding(
                    get: { ListSelection(single: selection.wrappedValue) },
                    set: { selection.wrappedValue = $0.focus },
                ),
                row: row,
                menu: menu,
            )
        }
    }

    extension SelectableList where Menu == EmptyView {
        /// A single-selection list without context menus.
        init(
            items: Data,
            selection: Binding<RowID?>,
            @ViewBuilder row: @escaping (Data.Element) -> Row,
        ) {
            self.init(items: items, selection: selection, row: row) { _ in EmptyView() }
        }
    }
#endif
