#if os(macOS)
    import AppKit
    import ChordPro
    import SwiftUI

    /// A song's artists as chips (P8-8 section 3.3): in order, the first is the primary, each
    /// with an "x"; a trailing input. Return or "," commits the typed text as one chip,
    /// exactly as typed; Backspace in an empty input selects the last chip, a second removes
    /// it; drag a chip to reorder; a chip holding a separator offers Split. Library names are
    /// suggested as you type and applied only by an explicit pick (Down then Return, Tab, or
    /// a click). Every write is one `onChange` (one undo step in the host).
    ///
    /// The input is `ComposerTextField`: spell-check, autocorrect, text replacement and
    /// every substitution off, so a romanized Hindi name is never "corrected".
    struct ArtistChipField: View {
        let artists: [String]
        /// The library's artist names, most songs first (`LibraryViewModel.knownArtists`).
        let suggestions: [String]
        /// What a chip is, for the placeholder and VoiceOver ("artist"; the smart filter's
        /// Movie / Album row says "movie or album" and offers no Split).
        var noun = "artist"
        var offersSplit = true
        /// Bumped to put the caret in the input (double-click on the heading's artists).
        var focusRequest = 0
        /// Escape with nothing to dismiss, or focus leaving the field.
        var onEndEditing: (() -> Void)?
        let onChange: (ArtistChipChange) -> Void

        @Environment(\.isEnabled) private var isEnabled
        @State private var input = ""
        @State private var selectedChip: Int?
        @State private var highlighted: Int?
        @State private var flashing: Int?
        @State private var isFocused = false

        var body: some View {
            let offered = isFocused
                ? ArtistChipEditing.suggestions(for: input, applied: artists, known: suggestions)
                : []
            VStack(alignment: .leading, spacing: 4) {
                FlowLayout(spacing: 5) {
                    ForEach(Array(artists.enumerated()), id: \.offset) { index, name in
                        chip(name, index: index)
                    }
                    inputField
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.color.ground, in: RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            isFocused ? Theme.color.cue : Theme.color.controlBorder,
                            lineWidth: 1,
                        )
                }
                .contentShape(Rectangle())
                if !offered.isEmpty {
                    SuggestionList(names: offered, highlighted: highlighted, pick: pick)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.songCardArtists)
            .onChange(of: input) { _, _ in highlighted = nil }
        }

        // MARK: Chips

        private func chip(_ name: String, index: Int) -> some View {
            let isSelected = selectedChip == index
            let canSplit = offersSplit && ArtistChipEditing.canSplit(name)
            return chipLabel(name, index: index, canSplit: canSplit)
                .padding(.leading, 9)
                .padding(.trailing, 5)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Theme.color.cue.opacity(0.16) : Theme.color.surfaceAlt),
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            isSelected || flashing == index ? Theme.color.cue
                                : Theme.color.controlBorder,
                            lineWidth: 1,
                        )
                }
                .draggable(Self.dragToken(index)) {
                    Text(name)
                        .font(SchibstedGrotesk.semiBold.font(size: 13))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let source = items.first.flatMap(Self.dragIndex),
                          let list = ArtistChipEditing.move(artists, from: source, to: index)
                    else { return false }
                    write(list, .reorder)
                    return true
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(name), \(noun) \(index + 1) of \(artists.count)")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier(AccessibilityID.songCardArtistChip)
                .accessibilityAction(named: "Remove") { remove(at: index) }
                .accessibilityAction(named: "Move Left") { move(index, by: -1) }
                .accessibilityAction(named: "Move Right") { move(index, by: 1) }
                .modifier(SplitAction(isShown: canSplit) { split(at: index) })
        }

        private func chipLabel(_ name: String, index: Int, canSplit: Bool) -> some View {
            HStack(spacing: 5) {
                Text(name)
                    .font(SchibstedGrotesk.semiBold.font(size: 13))
                    .foregroundStyle(Theme.color.ink)
                    .lineLimit(1)
                if canSplit {
                    Button("Split") { split(at: index) }
                        .buttonStyle(.plain)
                        .font(SchibstedGrotesk.semiBold.font(size: 11))
                        .foregroundStyle(Theme.color.cueText)
                        .help("Split into separate artists")
                        .accessibilityHidden(true)
                        .accessibilityIdentifier(AccessibilityID.songCardArtistSplit)
                }
                Button {
                    remove(at: index)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.color.muted)
                        .frame(width: 12, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove \(name)")
                .accessibilityHidden(true)
            }
        }

        // MARK: Input

        private var inputField: some View {
            ComposerTextField(
                text: input,
                font: Self.inputFont,
                identifier: AccessibilityID.songCardArtistInput,
                placeholder: artists.isEmpty ? "Add \(noun)" : "Add",
                accessibilityHint: "Return or comma adds one",
                focusRequest: focusRequest,
                selectAllRequest: 0,
                accessibilityLabel: "Add \(noun)",
                accessibilityValue: input,
                onChange: typed,
                onFocusChange: focusChanged,
                onCommand: command,
                onDeleteBackward: deleteBackward,
            )
            .frame(minWidth: 64, idealWidth: 140, maxWidth: .infinity)
            .frame(height: 18)
            .padding(.vertical, 2)
            .padding(.leading, 3)
        }

        private func typed(_ text: String) {
            selectedChip = nil
            if let (finished, rest) = ArtistChipEditing.commas(in: text, artists: artists) {
                input = rest
                if !finished.isEmpty {
                    write(artists + finished, .add)
                }
            } else {
                input = text
            }
        }

        private func focusChanged(_ focused: Bool) {
            isFocused = focused
            if !focused {
                selectedChip = nil
                highlighted = nil
                onEndEditing?()
            }
        }

        private func command(_ command: ComposerCommand) -> Bool {
            let offered = ArtistChipEditing.suggestions(
                for: input,
                applied: artists,
                known: suggestions,
            )
            if let handled = SuggestionKeys.handle(
                command,
                offered: offered,
                highlighted: &highlighted,
                pick: pick,
            ) {
                return handled
            }
            switch command {
            case .accept:
                commitInput()
                return true
            case .escape:
                escape()
                return true
            default:
                return false
            }
        }

        /// Escape: drops the chip selection, then the typed text, then ends editing.
        private func escape() {
            if selectedChip != nil {
                selectedChip = nil
            } else if !input.isEmpty {
                input = ""
            } else {
                onEndEditing?()
            }
        }

        /// Backspace in an empty input selects the last chip; a second one removes it.
        private func deleteBackward() -> Bool {
            guard input.isEmpty, !artists.isEmpty else { return false }
            if let selected = selectedChip {
                remove(at: selected)
            } else {
                selectedChip = artists.count - 1
            }
            return true
        }

        private func commitInput() {
            switch ArtistChipEditing.commit(input, to: artists) {
            case .empty:
                onEndEditing?()
            case let .duplicate(index):
                NSSound.beep()
                flash(index)
            case let .added(list):
                input = ""
                write(list, .add)
            }
        }

        private func pick(_ name: String) {
            input = ""
            highlighted = nil
            if case let .added(list) = ArtistChipEditing.commit(name, to: artists) {
                write(list, .add)
            }
        }

        private func flash(_ index: Int) {
            withAnimation(.easeOut(duration: 0.12)) { flashing = index }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                withAnimation(.easeOut(duration: 0.3)) { flashing = nil }
            }
        }

        // MARK: Writes

        private func remove(at index: Int) {
            guard artists.indices.contains(index) else { return }
            var list = artists
            list.remove(at: index)
            selectedChip = nil
            write(list, .remove)
        }

        private func move(_ index: Int, by offset: Int) {
            if let list = ArtistChipEditing.move(artists, from: index, by: offset) {
                write(list, .reorder)
            }
        }

        private func split(at index: Int) {
            if let list = ArtistChipEditing.split(artists, at: index) {
                write(list, .split)
            }
        }

        private func write(_ list: [String], _ edit: ArtistChipEdit) {
            guard list != artists else { return }
            onChange(ArtistChipChange(artists: list, edit: edit))
        }

        /// The input's face (Schibsted Grotesk Medium 13, as the chips' neighbours).
        static let inputFont: NSFont = {
            _ = FontRegistration.registerBundledFonts()
            return NSFont(name: SchibstedGrotesk.medium.rawValue, size: 13)
                ?? .systemFont(ofSize: 13, weight: .medium)
        }()

        private static let dragPrefix = "segue-artist-chip:"

        private static func dragToken(_ index: Int) -> String {
            dragPrefix + String(index)
        }

        private static func dragIndex(_ token: String) -> Int? {
            guard token.hasPrefix(dragPrefix) else { return nil }
            return Int(token.dropFirst(dragPrefix.count))
        }
    }

    /// The Split accessibility action, only on a chip that can split.
    private struct SplitAction: ViewModifier {
        let isShown: Bool
        let action: () -> Void

        func body(content: Content) -> some View {
            if isShown {
                content.accessibilityAction(named: "Split", action)
            } else {
                content
            }
        }
    }
#endif
