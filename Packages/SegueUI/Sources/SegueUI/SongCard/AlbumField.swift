#if os(macOS)
    import AppKit
    import Library
    import SwiftUI

    /// "Movie / Album" (P8-8 section 4.1): one value, written as `{album}` when Return is
    /// pressed or focus leaves; blank clears; Escape puts back the stored value. The library's
    /// albums are suggested as you type (normalized prefix) and applied only by an explicit
    /// pick (Down then Return, Tab, or a click). Same input rules as the artist chips: no
    /// spell-check, autocorrect or substitution.
    struct AlbumField: View {
        let album: String?
        /// The library's Movie / Album values, most songs first.
        let suggestions: [String]
        var focusRequest = 0
        /// Return, Escape or focus leaving: the field is done (the heading leaves edit mode).
        var onEndEditing: (() -> Void)?
        /// Where Edit > Undo goes while typing here, when not the window's stack.
        var undoManager: (() -> UndoManager?)?
        let onCommit: (String) -> Void

        @State private var draft: String?
        @State private var highlighted: Int?
        @State private var isFocused = false

        var body: some View {
            let text = draft ?? album ?? ""
            let offered = isFocused ? Self.offered(for: text, current: album, known: suggestions)
                : []
            VStack(alignment: .leading, spacing: 4) {
                ComposerTextField(
                    text: text,
                    font: ArtistChipField.inputFont,
                    identifier: AccessibilityID.songCardAlbum,
                    placeholder: "Movie or album",
                    focusRequest: focusRequest,
                    selectAllRequest: 0,
                    accessibilityLabel: "Movie or album",
                    accessibilityValue: text,
                    onChange: { new in
                        draft = new
                        highlighted = nil
                    },
                    onFocusChange: focusChanged,
                    onCommand: { command($0, offered: offered) },
                    undoManager: undoManager,
                )
                .frame(height: 18)
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.color.ground, in: RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            isFocused ? Theme.color.cue : Theme.color.controlBorder,
                            lineWidth: 1,
                        )
                }
                if !offered.isEmpty {
                    SuggestionList(names: offered, highlighted: highlighted, pick: pick)
                }
            }
        }

        /// Up to six library albums for `typed`, by normalized prefix from any word; none when
        /// the text already equals one.
        static func offered(for typed: String, current: String?, known: [String]) -> [String] {
            let trimmed = typed.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, known.allSatisfy({ !ArtistChipEditing.same($0, trimmed) })
            else { return [] }
            return ArtistChipEditing.suggestions(for: trimmed, applied: [], known: known)
        }

        private func focusChanged(_ focused: Bool) {
            isFocused = focused
            if !focused {
                commit()
                onEndEditing?()
            }
        }

        private func command(_ command: ComposerCommand, offered: [String]) -> Bool {
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
                commit()
                onEndEditing?()
                return true
            case .escape:
                draft = nil
                onEndEditing?()
                return true
            default:
                return false
            }
        }

        private func pick(_ name: String) {
            draft = name
            highlighted = nil
            commit()
        }

        private func commit() {
            guard let draft else { return }
            self.draft = nil
            let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            if value != (album ?? "") {
                onCommit(value)
            }
        }
    }

    /// Down, Up, Tab, Return and Escape over offered suggestions (P8-8 section 3.3): Down
    /// and Up move the highlight, Return picks the highlighted name, Tab the highlighted or
    /// first one, Escape drops the highlight. Nil for a key the field handles itself.
    enum SuggestionKeys {
        static func handle(
            _ command: ComposerCommand,
            offered: [String],
            highlighted: inout Int?,
            pick: (String) -> Void,
        ) -> Bool? {
            let current = highlighted.flatMap { offered.indices.contains($0) ? $0 : nil }
            switch command {
            case .next, .previous:
                return step(command == .next, offered: offered, current: current, &highlighted)
            case .tab:
                guard let name = current.map({ offered[$0] }) ?? offered.first else {
                    return false
                }
                pick(name)
                return true
            case .accept:
                guard let current else { return nil }
                pick(offered[current])
                return true
            case .escape:
                guard current != nil else { return nil }
                highlighted = nil
                return true
            case .backtab:
                return false
            }
        }

        /// Down from nothing highlights the first name; Up from the first drops the
        /// highlight (back to the typed text).
        private static func step(
            _ down: Bool,
            offered: [String],
            current: Int?,
            _ highlighted: inout Int?,
        ) -> Bool {
            if down {
                guard !offered.isEmpty else { return false }
                highlighted = min((current ?? -1) + 1, offered.count - 1)
            } else {
                guard let current else { return false }
                highlighted = current > 0 ? current - 1 : nil
            }
            return true
        }
    }

    /// The library names offered under a chip or album field: a compact list, the
    /// highlighted row filled with the accent colour.
    struct SuggestionList: View {
        let names: [String]
        let highlighted: Int?
        let pick: (String) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                    Button {
                        pick(name)
                    } label: {
                        Text(name)
                            .font(SchibstedGrotesk.medium.font(size: 13))
                            .foregroundStyle(
                                highlighted == index ? Color.white : Theme.color.ink,
                            )
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(highlighted == index ? Color.accentColor : .clear),
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name)
                    .accessibilityIdentifier(AccessibilityID.songCardArtistSuggestion)
                }
            }
            .padding(4)
            .frame(maxWidth: 260, alignment: .leading)
            .background(Theme.color.surfaceAlt, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.color.controlBorder)
            }
        }
    }
#endif
