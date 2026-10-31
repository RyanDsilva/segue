#if os(macOS)
    import Editing
    import Library
    import MusicTheory
    import SwiftUI

    /// What the key-change chips and the insert menus act on in a preview: the editor's
    /// model (nil in the library and on stage, which show neither).
    struct ChartDirectiveActions {
        let accept: @MainActor (KeyChangeSuggestion) -> Void
        let dismiss: @MainActor (KeyChangeSuggestion) -> Void
        let draft: @MainActor (ChartDirective, BlockPath) -> DirectiveDraft
        /// Inserts; returns the problem when it could not.
        let insert: @MainActor (ChartDirective, String, BlockPath) -> String?
        let sounding: @MainActor (SongKey) -> SongKey

        @MainActor init(model: SongEditorViewModel) {
            accept = { [weak model] in model?.acceptKeyChange($0) }
            dismiss = { [weak model] in model?.dismissKeyChange($0) }
            draft = { [weak model] directive, path in
                model?.directiveDraft(directive, before: path) ?? DirectiveDraft(
                    directive: directive,
                    path: path,
                    key: SongKey(canonical: PitchClass(0), mode: .major),
                    time: "4/4",
                    tempo: "",
                )
            }
            insert = { [weak model] directive, value, path in
                model?.insertDirective(directive, value: value, before: path)
            }
            sounding = { [weak model] key in model?.soundingKey(key) ?? key }
        }
    }

    extension EnvironmentValues {
        /// The editor's chip and insert actions in its text-mode preview.
        @Entry var chartDirectives: ChartDirectiveActions?
    }

    /// "Looks like a key change to A" with "Insert {key: A}" and a dismiss "x" (P8-7 section
    /// 6.2): quiet, beside the section it is about, applied only on a click.
    struct KeyChangeChip: View {
        let suggestion: KeyChangeSuggestion
        let accept: () -> Void
        let dismiss: () -> Void

        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: "music.note")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.color.muted)
                    .accessibilityHidden(true)
                Text("Looks like a key change to \(suggestion.key.name)")
                    .font(SchibstedGrotesk.semiBold.font(size: 12))
                    .foregroundStyle(Theme.color.muted)
                    .lineLimit(1)
                Button(action: accept) {
                    Text("Insert {key: \(suggestion.key.name)}")
                        .font(SchibstedGrotesk.bold.font(size: 12))
                        .foregroundStyle(Theme.color.cueText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.color.cue.opacity(0.14), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Write {key: \(suggestion.key.name)} before this section")
                .accessibilityIdentifier(AccessibilityID.keyChangeInsert)
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.color.muted)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Not a key change")
                .accessibilityLabel("Dismiss")
                .accessibilityIdentifier(AccessibilityID.keyChangeDismiss)
            }
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .padding(.vertical, 3)
            .background(Theme.color.surfaceAlt, in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.color.line, lineWidth: 1) }
            .fixedSize()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Looks like a key change to \(suggestion.key.name)")
            .accessibilityIdentifier(AccessibilityID.keyChangeChip)
        }
    }

    /// The chip in the text-mode preview, acting through the editor's actions.
    struct KeyChangeChipRow: View {
        let suggestion: KeyChangeSuggestion
        @Environment(\.chartDirectives) private var actions

        var body: some View {
            if let actions {
                KeyChangeChip(
                    suggestion: suggestion,
                    accept: { actions.accept(suggestion) },
                    dismiss: { actions.dismiss(suggestion) },
                )
            }
        }
    }

    extension View {
        /// The editor preview's "Insert Key / Time / Tempo Change Here..." context menu for a
        /// point (a section header or a lyric line); nothing outside the editor.
        func directiveInsertMenu(before path: BlockPath?) -> some View {
            modifier(DirectiveInsertMenu(path: path))
        }
    }

    private struct DirectiveInsertMenu: ViewModifier {
        let path: BlockPath?
        @Environment(\.chartDirectives) private var actions
        @State private var inserting: ChartDirective?

        func body(content: Content) -> some View {
            if let actions, let path {
                content
                    .contextMenu {
                        ForEach(ChartDirective.allCases) { directive in
                            Button(directive.menuTitle) { inserting = directive }
                        }
                    }
                    .popover(item: $inserting, arrowEdge: .bottom) { directive in
                        DirectiveInsertPopover(
                            draft: actions.draft(directive, path),
                            sounding: actions.sounding,
                            insert: { actions.insert(directive, $0, path) },
                            close: { inserting = nil },
                        )
                    }
            } else {
                content
            }
        }
    }
#endif
