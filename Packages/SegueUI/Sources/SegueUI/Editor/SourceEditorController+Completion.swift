#if os(macOS)
    import AppKit
    import Editing

    /// `[` chord and `{` directive completion (phase 1 spec, "Chord autocomplete").
    extension SourceEditorController {
        // MARK: Completion

        enum CompletionContext {
            case chord(prefix: String, start: Int)
            case directive(prefix: String, start: Int)
        }

        /// The `[`/`{` token the caret is in on its line, if any.
        func completionContext() -> CompletionContext? {
            let selection = textView.selectedRange()
            guard selection.length == 0 else { return nil }
            let text = textView.string as NSString
            let caret = selection.location
            let lineStart = text.lineRange(for: NSRange(location: caret, length: 0)).location
            let head = text.substring(with: NSRange(location: lineStart, length: caret - lineStart))
            if let open = head.lastIndex(of: "["), !head[open...].contains("]") {
                let prefix = String(head[head.index(after: open)...])
                guard !prefix.contains(" ") else { return nil }
                let start = lineStart + head[..<open].utf16.count
                return .chord(prefix: prefix, start: start)
            }
            if let open = head.lastIndex(of: "{"), !head[open...].contains("}"),
               !head[open...].contains(":")
            {
                let prefix = String(head[head.index(after: open)...])
                guard !prefix.contains(" ") else { return nil }
                let start = lineStart + head[..<open].utf16.count
                return .directive(prefix: prefix, start: start)
            }
            return nil
        }

        func updateCompletion(typed: String?) {
            guard let context = completionContext(), let window = textView.window else {
                completion.hide()
                return
            }
            let opening = typed == "[" || typed == "{"
            guard opening || completion.isVisible else { return }
            switch context {
            case let .chord(prefix, start):
                chordCompletions = host?.chordCompletions(prefix: prefix) ?? []
                show(.chord, items: chordCompletions.map(\.title), start: start, in: window)
            case let .directive(prefix, start):
                let open = DirectiveSuggestions.openSection(
                    in: textView.string,
                    before: start,
                )
                let items = DirectiveSuggestions.items(prefix: prefix, openSection: open)
                show(.directive, items: items.map(\.name), start: start, in: window)
            }
        }

        func show(
            _ kind: CompletionPopup.Kind,
            items: [String],
            start: Int,
            in window: NSWindow,
        ) {
            let anchor = textView.firstRect(
                forCharacterRange: NSRange(location: start, length: 1),
                actualRange: nil,
            )
            completion.show(kind: kind, items: items, below: anchor, parent: window)
        }

        func acceptCompletion(at index: Int? = nil) {
            guard let kind = completion.kind, let context = completionContext() else {
                completion.hide()
                return
            }
            let items = completion.items
            let chosen = index ?? completion.selectedIndex
            guard items.indices.contains(chosen) else { return }
            let item = items[chosen]
            let text = textView.string as NSString
            let caret = textView.selectedRange().location
            completion.hide()
            switch (kind, context) {
            case let (.chord, .chord(_, start)):
                let closes = caret < text.length && text.character(at: caret) == 0x5D // ]
                let end = closes ? caret + 1 : caret
                let chord = chordCompletions.first { $0.title == item }?.insertion ?? item
                let insertion = "[\(chord)]"
                replace(NSRange(location: start, length: end - start), with: insertion)
                textView.setSelectedRange(NSRange(
                    location: start + insertion.utf16.count,
                    length: 0,
                ))
            case let (.directive, .directive(_, start)):
                guard let directive = DirectiveSuggestions.all.first(where: { $0.name == item })
                else { return }
                let closes = caret < text.length && text.character(at: caret) == 0x7D // }
                let end = closes ? caret + 1 : caret
                let completionText = directive.completion
                replace(
                    NSRange(location: start, length: end - start),
                    with: "{" + completionText.text,
                )
                textView.setSelectedRange(NSRange(
                    location: start + 1 + completionText.caretOffset,
                    length: 0,
                ))
            default:
                return
            }
        }

        /// A user-level replacement (undoable like typing).
        func replace(_ range: NSRange, with string: String) {
            textView.breakUndoCoalescing()
            textView.insertText(string, replacementRange: range)
            textView.breakUndoCoalescing()
        }
    }
#endif
