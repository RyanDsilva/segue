#if os(macOS)
    import SwiftUI

    /// Tags as removable chips plus an "Add tag" field (Return adds; existing tags are
    /// offered as completions). Case-insensitive duplicates are ignored.
    struct TagEditor: View {
        let tags: [String]
        let suggestions: [String]
        var isDisabled = false
        let onChange: ([String]) -> Void
        @State private var draft = ""

        var body: some View {
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag)
                        Button {
                            onChange(tags.filter { $0 != tag })
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.color.muted)
                                .frame(width: 14, height: 14)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isDisabled)
                        .accessibilityLabel("Remove \(tag)")
                        .accessibilityIdentifier(AccessibilityID.songTagRemove)
                    }
                    .font(SchibstedGrotesk.semiBold.font(size: 13))
                    .foregroundStyle(Theme.color.ink)
                    .padding(.leading, 10)
                    .padding(.trailing, 6)
                    .padding(.vertical, 4)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Theme.color.controlBorder, lineWidth: 1)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(tag)
                    .accessibilityIdentifier(AccessibilityID.songTag)
                }
                TextField("Add tag", text: $draft)
                    .textFieldStyle(.plain)
                    .font(SchibstedGrotesk.medium.font(size: 13))
                    .frame(width: 120)
                    .padding(.vertical, 4)
                    .textInputSuggestions {
                        ForEach(completions, id: \.self) { tag in
                            Text(tag).textInputCompletion(tag)
                        }
                    }
                    .onSubmit(add)
                    .disabled(isDisabled)
                    .accessibilityIdentifier(AccessibilityID.songTagField)
            }
        }

        private var completions: [String] {
            let typed = draft.trimmingCharacters(in: .whitespaces).lowercased()
            guard !typed.isEmpty else { return [] }
            return suggestions.filter { tag in
                tag.lowercased().hasPrefix(typed)
                    && !tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
            }
            .prefix(6)
            .map(\.self)
        }

        private func add() {
            let tag = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            draft = ""
            guard !tag.isEmpty,
                  !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame })
            else { return }
            onChange(tags + [tag])
        }
    }
#endif
