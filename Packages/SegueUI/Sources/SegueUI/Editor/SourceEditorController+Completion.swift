#if os(macOS)
    import AppKit
    import ChordPro
    import Editing

    /// `[` chord completion, `{` directive completion and the `/` slash menu (phase 1 spec,
    /// "Chord autocomplete"; R81, spec 16.0.2).
    extension SourceEditorController {
        // MARK: Completion

        enum CompletionContext {
            case chord(prefix: String, start: Int)
            case directive(prefix: String, start: Int)
            /// `/query` at the start of a line (only whitespace before the `/`).
            case slash(query: String, start: Int)
            /// The slash menu filtering a selection it will wrap.
            case slashSelection(SlashSelectionSession)
            /// The value of `{key: `, `{time: `, `{capo: `, `{tempo: ` or `{duration: `.
            case value(name: String, prefix: String, start: Int)
        }

        /// The longest query the slash menu keeps open for (it is a menu, not a text).
        static let slashQueryLimit = 24

        /// The `[`/`{`/`/` token the caret is in on its line, if any.
        func completionContext() -> CompletionContext? {
            let selection = textView.selectedRange()
            if let session = completion.slashSelection {
                return session.selection == selection ? .slashSelection(session) : nil
            }
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
            if let value = valueContext(head: head, lineStart: lineStart) {
                return value
            }
            let indent = head.prefix { $0 == " " || $0 == "\t" }
            let rest = head.dropFirst(indent.count)
            if rest.first == "/" {
                let query = String(rest.dropFirst())
                guard !query.contains("/"), query.count <= Self.slashQueryLimit else { return nil }
                return .slash(query: query, start: lineStart + indent.utf16.count)
            }
            return nil
        }

        func updateCompletion(typed: String?) {
            guard let context = completionContext(), let window = textView.window else {
                completion.hide()
                return
            }
            let opening = typed == "[" || typed == "{" || typed == "/" || typed == ":"
            guard opening || completion.isVisible else { return }
            switch context {
            case let .chord(prefix, start):
                chordCompletions = host?.chordCompletions(prefix: prefix) ?? []
                let entries = chordCompletions.map { CompletionPopup.Entry(title: $0.title) }
                show(.chord, items: entries, start: start, in: window)
            case let .directive(prefix, start):
                let entries = directiveItems(prefix: prefix, start: start).map {
                    CompletionPopup.Entry(title: $0.title, detail: $0.detail)
                }
                show(.directive, items: entries, start: start, in: window)
            case let .slash(query, start):
                let entries = slashItems(query: query, start: start).map(Self.entry)
                show(.slash, items: entries, start: start, in: window)
            case let .value(name, prefix, start):
                let detected = host?.snapshot.document.detectedKey
                let entries = ValueSuggestions.choices(
                    for: name,
                    prefix: prefix,
                    detected: detected,
                )
                .map { CompletionPopup.Entry(title: $0.title, detail: $0.detail) }
                show(
                    .directive,
                    items: entries,
                    header: ValueSuggestions.header(for: name),
                    start: start,
                    in: window,
                )
            case let .slashSelection(session):
                let entries = SlashMenu.matches(session.query, sections: .wrapOnly).map(Self.entry)
                show(
                    .slash,
                    items: entries,
                    header: "/" + session.query,
                    start: session.selection.location,
                    in: window,
                )
            }
        }

        private static func entry(_ item: SlashMenu.Item) -> CompletionPopup.Entry {
            CompletionPopup.Entry(title: item.title, detail: item.detail)
        }

        func directiveItems(prefix: String, start: Int) -> [DirectiveSuggestions.Item] {
            let open = DirectiveSuggestions.openSection(in: textView.string, before: start)
            let document = host?.snapshot.document ?? SongDocument(blocks: [])
            return DirectiveSuggestions.items(prefix: prefix, openSection: open, document: document)
        }

        func slashItems(query: String, start: Int) -> [SlashMenu.Item] {
            let inside = DirectiveSuggestions.openSection(in: textView.string, before: start) != nil
            return SlashMenu.matches(query, sections: inside ? .noSections : .all)
        }

        func show(
            _ kind: CompletionPopup.Kind,
            items: [CompletionPopup.Entry],
            header: String? = nil,
            start: Int,
            in window: NSWindow,
        ) {
            let anchor = textView.firstRect(
                forCharacterRange: NSRange(location: start, length: 1),
                actualRange: nil,
            )
            if items.isEmpty, kind == .slash, completion.slashSelection != nil {
                // Keep the filter visible with nothing matching, so Backspace can recover.
                completion.show(
                    kind: kind,
                    items: [CompletionPopup.Entry(title: "No match")],
                    header: header,
                    below: anchor,
                    parent: window,
                )
                return
            }
            completion.show(kind: kind, items: items, header: header, below: anchor, parent: window)
        }

        func acceptCompletion(at index: Int? = nil) {
            guard let kind = completion.kind, let context = completionContext() else {
                completion.hide()
                return
            }
            let chosen = index ?? completion.selectedIndex
            guard completion.items.indices.contains(chosen) else { return }
            let item = completion.items[chosen]
            let text = textView.string as NSString
            let caret = textView.selectedRange().location
            completion.hide()
            switch (kind, context) {
            case let (.chord, .chord(_, start)):
                let closes = caret < text.length && text.character(at: caret) == 0x5D // ]
                let end = closes ? caret + 1 : caret
                let chord = chordCompletions.first { $0.title == item.title }?.insertion
                    ?? item.title
                let insertion = "[\(chord)]"
                replace(NSRange(location: start, length: end - start), with: insertion)
                textView.setSelectedRange(NSRange(
                    location: start + insertion.utf16.count,
                    length: 0,
                ))
            case (.directive, _):
                acceptDirective(context, at: chosen, caret: caret)
            case (.slash, _):
                acceptSlash(context, at: chosen, caret: caret)
            default:
                return
            }
        }

        private func acceptDirective(_ context: CompletionContext, at chosen: Int, caret: Int) {
            let text = textView.string as NSString
            switch context {
            case let .directive(prefix, start):
                let items = directiveItems(prefix: prefix, start: start)
                guard items.indices.contains(chosen) else { return }
                let closes = caret < text.length && text.character(at: caret) == 0x7D // }
                let end = closes ? caret + 1 : caret
                let completionText = items[chosen].completion
                replace(
                    NSRange(location: start, length: end - start),
                    with: "{" + completionText.text,
                )
                textView.setSelectedRange(NSRange(
                    location: start + 1 + completionText.caretOffset,
                    length: 0,
                ))
                if ValueSuggestions.names.contains(items[chosen].name),
                   items[chosen].completion.text.hasSuffix(": }")
                {
                    updateCompletion(typed: ":")
                }
            case let .value(name, prefix, start):
                let detected = host?.snapshot.document.detectedKey
                let choices = ValueSuggestions.choices(
                    for: name,
                    prefix: prefix,
                    detected: detected,
                )
                guard choices.indices.contains(chosen) else { return }
                let closes = caret < text.length && text.character(at: caret) == 0x7D // }
                replace(
                    NSRange(location: start, length: caret - start),
                    with: choices[chosen].value,
                )
                let after = start + choices[chosen].value.utf16.count + (closes ? 1 : 0)
                textView.setSelectedRange(NSRange(location: after, length: 0))
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

        // MARK: Slash menu

        private func acceptSlash(_ context: CompletionContext, at chosen: Int, caret: Int) {
            switch context {
            case let .slash(query, start):
                let items = slashItems(query: query, start: start)
                guard items.indices.contains(chosen) else { return }
                insertSlashItem(items[chosen], replacing: NSRange(
                    location: start,
                    length: caret - start,
                ))
            case let .slashSelection(session):
                let items = SlashMenu.matches(session.query, sections: .wrapOnly)
                guard items.indices.contains(chosen),
                      case let .section(kind) = items[chosen].action
                else { return }
                wrapLines(in: session.selection, kind: kind)
            default:
                return
            }
        }

        /// Called for every text change the user makes, before it happens. While the slash
        /// menu filters a selection, typing goes to its filter instead of replacing the
        /// selection; `/` typed over a selection that starts a line opens that mode.
        /// Returns true when the change was taken (the text view must not apply it).
        func interceptSlashTyping(in range: NSRange, replacement: String?) -> Bool {
            guard let replacement else { return false }
            if var session = completion.slashSelection, range == session.selection {
                if replacement.isEmpty {
                    guard !session.query.isEmpty else {
                        completion.hide()
                        return true
                    }
                    session.query.removeLast()
                } else if replacement.contains("\n") {
                    return false
                } else {
                    session.query += replacement
                }
                completion.slashSelection = session
                updateCompletion(typed: nil)
                return true
            }
            guard replacement == "/", range.length > 0, startsLine(range.location) else {
                return false
            }
            completion.slashSelection = SlashSelectionSession(selection: range)
            updateCompletion(typed: "/")
            return true
        }

        /// `{name: partial` before the caret, for a name with value help.
        private func valueContext(head: String, lineStart: Int) -> CompletionContext? {
            guard let open = head.lastIndex(of: "{"), !head[open...].contains("}"),
                  let colon = head[open...].firstIndex(of: ":")
            else { return nil }
            let name = head[head.index(after: open) ..< colon]
                .trimmingCharacters(in: .whitespaces).lowercased()
            guard ValueSuggestions.names.contains(name) else { return nil }
            let afterColon = head[head.index(after: colon)...]
            let spaces = afterColon.prefix { $0 == " " }
            let prefix = String(afterColon.dropFirst(spaces.count))
            let start = lineStart + head[..<colon].utf16.count + 1 + spaces.utf16.count
            return .value(name: name, prefix: prefix, start: start)
        }

        /// Whether only spaces or tabs precede `offset` on its line.
        private func startsLine(_ offset: Int) -> Bool {
            let text = textView.string as NSString
            let lineStart = text.lineRange(for: NSRange(location: offset, length: 0)).location
            let head = text.substring(with: NSRange(
                location: lineStart,
                length: offset - lineStart,
            ))
            return head.allSatisfy { $0 == " " || $0 == "\t" }
        }

        /// Replaces the typed `/query` with the item: a section pair with the caret on the
        /// empty line inside it, `{chorus}`, or `{comment: }` with the caret in the value.
        private func insertSlashItem(_ item: SlashMenu.Item, replacing range: NSRange) {
            let insertion: String
            let caretOffset: Int
            switch item.action {
            case let .section(kind):
                insertSectionPair(kind, replacing: range)
                return
            case .chorusRepeat:
                insertion = "{chorus}"
                caretOffset = insertion.utf16.count
            case .note:
                insertion = "{comment: }"
                caretOffset = insertion.utf16.count - 1
            case let .value(name):
                writeValueDirective(name, removing: range)
                return
            }
            replace(range, with: insertion)
            textView.setSelectedRange(NSRange(location: range.location + caretOffset, length: 0))
        }

        /// Removes the typed `/query` (its whole line when nothing else is on it) and writes
        /// `{name: }` at the top, or puts the caret on the value of the one already there,
        /// as one undo step; then opens the value choices.
        private func writeValueDirective(_ name: String, removing typed: NSRange) {
            guard let snapshot = host?.snapshot else { return }
            let text = textView.string as NSString
            let marker = "\u{FFFC}"
            guard let planned = try? DocumentEditor.change(
                for: .setDirective(name: name, value: marker),
                in: snapshot,
            ), let edit = planned.edits.first, planned.edits.count == 1,
            let markerRange = edit.replacement.range(of: marker)
            else { return }
            let line = text.lineRange(for: typed)
            let lineText = text.substring(with: line)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let slashText = text.substring(with: typed)
            let removal = lineText == slashText.trimmingCharacters(in: .whitespaces) ? line : typed
            // Keep the existing value (only the caret moves to it).
            let existing = Self.firstDirectiveValue(name, in: snapshot.document) ?? ""
            let replacement = edit.replacement.replacingOccurrences(of: marker, with: existing)
            let directive = TextEdit(range: edit.range, replacement: replacement)
            let removeEdit = TextEdit(
                range: removal.location ..< removal.location + removal.length,
                replacement: "",
            )
            guard directive.range.upperBound <= removeEdit.range.lowerBound
                || removeEdit.range.upperBound <= directive.range.lowerBound
            else { return }
            let markerOffset = edit.replacement.utf16.distance(
                from: edit.replacement.utf16.startIndex,
                to: markerRange.lowerBound.samePosition(in: edit.replacement.utf16)
                    ?? edit.replacement.utf16.startIndex,
            )
            var caret = edit.range.lowerBound + markerOffset + existing.utf16.count
            if removeEdit.range.upperBound <= directive.range.lowerBound {
                caret -= removeEdit.range.count
            }
            let edits = [directive, removeEdit].sorted { $0.range.lowerBound < $1.range.lowerBound }
            apply(SourceChange(
                edits: edits,
                actionName: planned.actionName,
                selectionAfter: caret ..< caret,
            ))
            updateCompletion(typed: ":")
        }

        private static func firstDirectiveValue(
            _ name: String,
            in document: SongDocument,
        ) -> String? {
            for case let .directive(directive) in document.blocks where directive.name == name {
                return directive.value
            }
            return nil
        }

        /// Replaces the typed `/query` with an empty `start_of_`/`end_of_` pair, the caret on
        /// the line inside, labelled by the numbering rule (`SectionLabels.proposal`): when
        /// it is the second distinct one of its kind, the existing ones get their numbers in
        /// the same undo step ("Chorus" becomes "Chorus 1", the new one "Chorus 2").
        private func insertSectionPair(_ kind: SectionKind, replacing range: NSRange) {
            guard let snapshot = host?.snapshot else { return }
            let position = snapshot.path(atSourceOffset: range.location)?.block
            let proposal = SectionLabels.proposal(
                for: kind,
                lyrics: nil,
                at: position,
                in: snapshot.document,
            )
            let start = DirectiveLine.sectionStart(kind, label: proposal.label) + "\n"
            let pair = TextEdit(
                range: range.location ..< range.location + range.length,
                replacement: start + "\n" + DirectiveLine.sectionEnd(kind),
            )
            var edits = [pair]
            for (path, label) in proposal.renames {
                guard let rename = try? DocumentEditor.change(
                    for: .setSectionLabel(path, label: label),
                    in: snapshot,
                ) else { continue }
                edits += rename.edits
            }
            edits.sort { $0.range.lowerBound < $1.range.lowerBound }
            let shift = edits.filter { $0.range.upperBound <= pair.range.lowerBound && $0 != pair }
                .reduce(0) { $0 + $1.replacement.utf16.count - $1.range.count }
            let caret = pair.range.lowerBound + shift + start.utf16.count
            apply(SourceChange(
                edits: edits,
                actionName: "New Section",
                selectionAfter: caret ..< caret,
            ))
        }

        /// Wraps the lines the selection covers (blank lines at either end left out) in a
        /// numbered section, through the section band's own operation: one undo step, no
        /// lyric change. Beeps when the lines are inside or across a section.
        private func wrapLines(in selection: NSRange, kind: SectionKind) {
            guard let snapshot = host?.snapshot,
                  let (first, last) = blockRange(of: selection, in: snapshot)
            else {
                NSSound.beep()
                return
            }
            do {
                let change = try DocumentEditor.change(
                    for: .createSection(first: first, last: last, kind: kind),
                    in: snapshot,
                )
                apply(change)
            } catch {
                NSSound.beep()
            }
        }

        /// The first and last non-blank lines' block paths within `selection`.
        private func blockRange(
            of selection: NSRange,
            in snapshot: SourceSnapshot,
        ) -> (BlockPath, BlockPath)? {
            let text = textView.string as NSString
            var paths: [BlockPath] = []
            var location = selection.location
            let end = selection.location + selection.length
            repeat {
                let line = text.lineRange(for: NSRange(location: location, length: 0))
                let content = text.substring(with: line)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !content.isEmpty, let path = snapshot.path(atSourceOffset: line.location) {
                    paths.append(path)
                }
                location = line.location + line.length
            } while location < end && location < text.length
            guard let first = paths.first, let last = paths.last else {
                return nil
            }
            return (first, last)
        }
    }
#endif
