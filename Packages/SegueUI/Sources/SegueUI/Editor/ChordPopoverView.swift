#if os(macOS)
    import SwiftUI

    /// The visual-mode chord popover: type a chord (letter names in the display key) with
    /// suggestions underneath (song chords, diatonic chords, extensions of the typed root).
    /// Return adds what is typed, or the suggestion picked with the arrow keys.
    struct ChordPopoverView: View {
        let title: String
        let suggestions: (String) -> [String]
        let onCommit: (String) -> Void
        let onDelete: (() -> Void)?
        let onCancel: () -> Void

        @State private var text: String
        @State private var highlighted: Int?
        @FocusState private var isFocused: Bool

        init(
            title: String,
            initial: String,
            suggestions: @escaping (String) -> [String],
            onCommit: @escaping (String) -> Void,
            onDelete: (() -> Void)?,
            onCancel: @escaping () -> Void,
        ) {
            self.title = title
            self.suggestions = suggestions
            self.onCommit = onCommit
            self.onDelete = onDelete
            self.onCancel = onCancel
            _text = State(initialValue: initial)
        }

        var body: some View {
            let items = suggestions(text.trimmingCharacters(in: .whitespaces))
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.muted)
                field(items: items)
                if !items.isEmpty {
                    LyricFlowLayout(rowSpacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            SuggestionChip(title: item, isHighlighted: index == highlighted) {
                                onCommit(item)
                            }
                            .padding(.trailing, 6)
                        }
                    }
                }
                if let onDelete {
                    Button("Remove Chord", role: .destructive, action: onDelete)
                        .buttonStyle(.segueSecondary)
                        .controlSize(.small)
                        .accessibilityIdentifier(AccessibilityID.editorChordDelete)
                }
            }
            .padding(14)
            .frame(width: 280, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.editorChordPopover)
            .onAppear { isFocused = true }
        }

        private func field(items: [String]) -> some View {
            TextField("Chord", text: $text)
                .textFieldStyle(.plain)
                .font(SchibstedGrotesk.bold.font(size: 18))
                .foregroundStyle(Theme.color.cueText)
                .autocorrectionDisabled()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.color.ground, in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Theme.color.controlBorder, lineWidth: 1)
                }
                .focused($isFocused)
                .accessibilityIdentifier(AccessibilityID.editorChordField)
                .onChange(of: text) { highlighted = nil }
                .onSubmit { commit(items) }
                .onKeyPress(keys: [.downArrow, .rightArrow]) { press in
                    guard !items.isEmpty, press.key == .downArrow || highlighted != nil else {
                        return .ignored
                    }
                    highlighted = min((highlighted ?? -1) + 1, items.count - 1)
                    return .handled
                }
                .onKeyPress(keys: [.upArrow, .leftArrow]) { press in
                    guard let current = highlighted else { return .ignored }
                    if press.key == .leftArrow, current == 0 {
                        highlighted = nil
                        return .handled
                    }
                    highlighted = current > 0 ? current - 1 : nil
                    return .handled
                }
                .onExitCommand(perform: onCancel)
        }

        private func commit(_ items: [String]) {
            if let highlighted, items.indices.contains(highlighted) {
                onCommit(items[highlighted])
                return
            }
            let typed = text.trimmingCharacters(in: .whitespaces)
            guard !typed.isEmpty else { return }
            onCommit(typed)
        }
    }

    /// A chord chip: `cueText` 15 / 700 on paper with a hairline border (mockup palette).
    struct SuggestionChip: View {
        let title: String
        var isHighlighted = false
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(SchibstedGrotesk.bold.font(size: 15))
                    .foregroundStyle(isHighlighted ? Theme.color.ground : Theme.color.cueText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(chipShape
                        .fill(isHighlighted ? Theme.color.ink : Theme.color.ground))
                    .overlay {
                        chipShape.strokeBorder(
                            isHighlighted ? Theme.color.ink : Theme.color.controlBorder,
                            lineWidth: 1,
                        )
                    }
                    .contentShape(chipShape)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.editorChordSuggestion)
        }

        private var chipShape: RoundedRectangle {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
        }
    }
#endif
