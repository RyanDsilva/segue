#if os(macOS)
    import SwiftUI

    /// A single-selection list in the brand's quiet style (mockup L1 a): hairline `line`
    /// separators and the selected row on brand grey (`surfaceAlt`; `line` in dark), text
    /// staying in its own colours, instead of the system's accent-blue highlight with white
    /// text. Click selects;
    /// Up/Down move the selection while the list has keyboard focus, and the selected row is
    /// kept scrolled into view.
    struct SelectableList<Data: RandomAccessCollection, Row: View>: View
        where Data.Element: Identifiable
    {
        let items: Data
        @Binding var selection: Data.Element.ID?
        @ViewBuilder let row: (Data.Element) -> Row
        @FocusState private var focused: Bool
        @Environment(\.colorScheme) private var colorScheme

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
                .onKeyPress(.upArrow) { move(-1) }
                .onKeyPress(.downArrow) { move(1) }
                .onChange(of: selection) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(id)
                    }
                }
            }
        }

        private func rowView(_ item: Data.Element) -> some View {
            let isSelected = item.id == selection
            return row(item)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSelected ? selectedFill : Color.clear)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.color.line).frame(height: 1)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    focused = true
                    selection = item.id
                }
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                .accessibilityAction { selection = item.id }
                .id(item.id)
        }

        private func move(_ delta: Int) -> KeyPress.Result {
            guard !items.isEmpty else { return .ignored }
            let ids = items.map(\.id)
            let current = selection.flatMap { ids.firstIndex(of: $0) }
            let next = current.map { min(max($0 + delta, 0), ids.count - 1) }
                ?? (delta > 0 ? 0 : ids.count - 1)
            selection = ids[next]
            return .handled
        }
    }
#endif
