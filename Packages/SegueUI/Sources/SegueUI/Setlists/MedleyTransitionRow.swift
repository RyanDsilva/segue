#if os(macOS)
    import AppKit
    import Library
    import Setlists
    import SwiftUI

    /// The row between two members (P9-3 6.2): "↳" and the transition into the next member
    /// (a one-line field while editing, up to two lines otherwise; spell-check, autocorrect
    /// and completion off, at most 280 characters), and on its right the derived change line
    /// ("G → A · capo 2 → no capo · 96 → 120 BPM"), a capo change in the essentials colour.
    struct MedleyTransitionRow: View {
        let member: MedleyMember
        /// The member the transition leads into.
        let title: String
        let changes: [MedleyChange]
        let isReadOnly: Bool
        /// Return or focus loss: the text to save (one "Edit Transition" undo step).
        let onCommit: (String) -> Void
        @State private var draft = ""
        @State private var isEditing = false
        @FocusState private var isFocused: Bool

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Color.clear.frame(width: 32, height: 1)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("↳")
                        .font(SchibstedGrotesk.medium.font(size: 13))
                        .foregroundStyle(Theme.color.muted)
                        .accessibilityHidden(true)
                    field
                }
                .padding(.leading, MedleyMemberPlace.indent)
                .frame(maxWidth: .infinity, alignment: .leading)
                changeLine
            }
            .padding(.leading, 32 - MedleyMemberPlace.cardInset)
            .padding(.trailing, 12 - MedleyMemberPlace.cardInset + Self.trailingCells)
            .padding(.vertical, 5)
        }

        /// The lock and remove cells the member rows end with, so the change line ends where
        /// their time column does.
        private static let trailingCells: CGFloat = 20 + 8 + 20 + 8

        @ViewBuilder private var field: some View {
            if isEditing {
                TextField("Add a transition", text: $draft)
                    .textFieldStyle(.plain)
                    .font(SchibstedGrotesk.medium.font(size: 14))
                    .foregroundStyle(Theme.color.ink)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .onSubmit(commit)
                    .onExitCommand {
                        isEditing = false
                    }
                    .onChange(of: draft) { _, text in
                        if text.count > SetlistMedley.maxTransitionLength {
                            draft = String(text.prefix(SetlistMedley.maxTransitionLength))
                            NSSound.beep()
                        }
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused {
                            commit()
                        }
                    }
                    .accessibilityLabel("Transition into \(title)")
                    .accessibilityIdentifier(AccessibilityID.medleyTransition)
            } else {
                Button(action: beginEditing) {
                    Text(member.transition ?? "Add a transition")
                        .font(SchibstedGrotesk.medium.font(size: 14))
                        .foregroundStyle(member.transition == nil ? Theme.color.muted
                            : Theme.color.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isReadOnly)
                .help(isReadOnly ? "" : "What happens between the songs (click to edit)")
                .accessibilityLabel("Transition into \(title)")
                .accessibilityValue(member.transition ?? "None")
                .accessibilityIdentifier(AccessibilityID.medleyTransition)
            }
        }

        @ViewBuilder private var changeLine: some View {
            if !changes.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(changes.enumerated()), id: \.offset) { index, change in
                        if index > 0 {
                            Text("·")
                                .foregroundStyle(Theme.color.muted)
                        }
                        Text(change.text)
                            .foregroundStyle(change.isCapo ? Theme.color.cueText
                                : Theme.color.muted)
                    }
                }
                .font(SchibstedGrotesk.medium.font(size: 12))
                .lineLimit(1)
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(MedleyChanges.line(changes)
                    .replacingOccurrences(of: "→", with: "to"))
                .accessibilityIdentifier(AccessibilityID.medleyChanges)
            }
        }

        private func beginEditing() {
            guard !isReadOnly else { return }
            draft = member.transition ?? ""
            isEditing = true
            isFocused = true
        }

        private func commit() {
            guard isEditing else { return }
            isEditing = false
            let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text != (member.transition ?? "") else { return }
            onCommit(text)
        }
    }

    /// The medley header's title while renaming: Return or focus loss saves, Escape cancels.
    /// Spell-check and autocorrect are off (romanized Hindi titles).
    struct MedleyTitleField: View {
        let title: String
        let onCommit: (String) -> Void
        @State private var draft = ""
        @State private var isDone = false
        @FocusState private var isFocused: Bool

        var body: some View {
            TextField("Medley", text: $draft)
                .textFieldStyle(.plain)
                .font(SchibstedGrotesk.semiBold.font(size: 16))
                .foregroundStyle(Theme.color.ink)
                .autocorrectionDisabled()
                .focused($isFocused)
                .frame(minWidth: 120, maxWidth: 320)
                .onAppear {
                    draft = title
                    isFocused = true
                }
                .onSubmit { finish(save: true) }
                .onExitCommand { finish(save: false) }
                .onChange(of: isFocused) { _, focused in
                    if !focused {
                        finish(save: true)
                    }
                }
                .accessibilityLabel("Medley title")
                .accessibilityIdentifier(AccessibilityID.medleyTitle)
        }

        private func finish(save: Bool) {
            guard !isDone else { return }
            isDone = true
            onCommit(save ? draft.trimmingCharacters(in: .whitespacesAndNewlines) : title)
        }
    }

    /// The collapsed medley's members as one row of chips (P9-3 6.2, direction C): "3a
    /// Kesariya G", "→" between them with a speech glyph where a transition is written, and
    /// the essentials dot on a member whose capo changes.
    struct MedleyChips: View {
        let members: [MedleyMember]
        let number: Int
        let titles: [String]
        let keys: [String?]
        let capoChanges: [Bool]

        var body: some View {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(Array(members.enumerated()), id: \.element.itemId) { index, member in
                    if index > 0 {
                        joint(hasTransition: member.transition != nil)
                    }
                    chip(index)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .accessibilityIdentifier(AccessibilityID.medleyChips)
        }

        private func joint(hasTransition: Bool) -> some View {
            HStack(spacing: 3) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .semibold))
                if hasTransition {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 10, weight: .regular))
                        .help("A transition is written here")
                }
            }
            .foregroundStyle(Theme.color.muted)
            .frame(height: 22)
        }

        private func chip(_ index: Int) -> some View {
            HStack(spacing: 5) {
                Text(Setlist.memberLabel(slot: number, index: index))
                    .foregroundStyle(Theme.color.muted)
                Text(titles[index])
                    .font(SchibstedGrotesk.semiBold.font(size: 13))
                    .foregroundStyle(Theme.color.ink)
                    .lineLimit(1)
                if let key = keys[index] {
                    Text(key)
                        .foregroundStyle(Theme.color.muted)
                }
                if capoChanges[index] {
                    Circle()
                        .fill(Theme.color.cue)
                        .frame(width: 6, height: 6)
                        .help("The capo changes going into this song")
                }
            }
            .font(SchibstedGrotesk.medium.font(size: 12))
            .padding(.horizontal, 7)
            .frame(height: 22)
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Theme.color.lineStrong, lineWidth: 1)
            }
        }

        private var spoken: String {
            members.indices.map { index in
                [Setlist.memberLabel(slot: number, index: index), titles[index], keys[index]]
                    .compactMap(\.self).joined(separator: " ")
            }.joined(separator: ", then ")
        }
    }
#endif
