#if os(macOS)
    import Editing
    import Library
    import Services
    import SwiftUI

    /// Where the section notes sheet reads the song and sends its edits: the library detail
    /// pane (writes the files, undoable from Edit > Undo) or the open editor (its own undo
    /// stack and autosave).
    @MainActor
    struct SectionNotesHost {
        /// The song's notes as they are now.
        let notes: () -> SectionNotes
        var isReadOnly = false
        /// Stage-only notes need the sidecar (a new song has one after its first save).
        var canEditStageNotes = true
        /// Where the sheet was opened from (analytics).
        var entry: NoteEntry = .sheet
        /// Applies one edit as one undo step; nil when it did not apply.
        let apply: (SectionNoteEdit, SectionNoteEditContext) async -> SectionNoteChange?
    }

    extension SectionNotesHost {
        static func library(_ model: LibraryViewModel, id: SongID) -> Self {
            SectionNotesHost(
                notes: {
                    guard let record = model.song(id: id) else {
                        return SectionNotes(sections: [], cues: [])
                    }
                    return SectionNotes(document: record.document, cues: record.sidecar.cues)
                },
                isReadOnly: model.song(id: id)?.isReadOnly ?? true,
                entry: .library,
                apply: { await model.editSectionNotes(id: id, $0, context: $1) },
            )
        }

        static func editor(_ model: SongEditorViewModel, entry: NoteEntry = .sheet) -> Self {
            SectionNotesHost(
                notes: { model.sectionNotes },
                canEditStageNotes: model.canEditStageNotes,
                entry: entry,
                apply: { model.editSectionNotes($0, context: $1) },
            )
        }
    }

    extension View {
        /// The editor's section notes sheet (opened from the section band).
        func sectionNotesSheet(for model: SongEditorViewModel) -> some View {
            sheet(item: Binding(
                get: { model.sectionNotesRequest },
                set: { model.sectionNotesRequest = $0 },
            )) { request in
                SectionNotesSheet(
                    host: .editor(model, entry: request.entry),
                    focus: request.group,
                    placement: request.placement,
                    addsNote: request.addsNote,
                )
            }
        }
    }

    /// "Section Notes" (R87): every note of the song grouped by section. Each note shows
    /// everywhere (a `{comment}` in the chart) unless "Show on stage only" is on (a cue,
    /// live mode only); the checkbox moves it between the two. Every change applies at once
    /// as one undo step; text commits on Return or when the field loses focus.
    struct SectionNotesSheet: View {
        let host: SectionNotesHost
        /// The group to scroll to (the section band's badge).
        var focus: SectionNoteGroup.ID?
        /// A new note's placement on `focus` (the band's instance, R144); nil = the group's
        /// default (Every time, R145 question 3).
        var placement: NotePlacement?
        /// Open with a new note row on `focus` ("Add Note to Chorus #2...").
        var addsNote = false
        @Environment(\.dismiss) private var dismiss
        @State private var notes = SectionNotes(sections: [], cues: [])
        /// Text being typed into an existing note, not committed yet.
        @State private var drafts: [SectionNoteID: String] = [:]
        /// Notes being added, not committed yet.
        @State private var additions: [Addition] = []
        @State private var work: Task<Void, Never>?
        @FocusState private var focused: Field?

        private enum Field: Hashable {
            case note(SectionNoteID)
            case addition(UUID)
        }

        private struct Addition: Identifiable {
            let id = UUID()
            let group: SectionNoteGroup.ID
            var text = ""
            var stageOnly: Bool
            var placement: NotePlacement?
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                if notes.groups.isEmpty {
                    emptyState
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 18) {
                                ForEach(notes.groups) { group in
                                    groupView(group).id(group.id)
                                }
                            }
                            .padding(20)
                        }
                        .onAppear {
                            if let focus {
                                proxy.scrollTo(focus, anchor: .top)
                            }
                            if addsNote, let group = notes.group(id: focus ?? "") {
                                add(to: group, placement: placement)
                            }
                        }
                    }
                }
                Divider()
                HStack {
                    GuideHelpButton(.sectionNotes)
                    Spacer()
                    Button("Done", action: finish)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.seguePrimary)
                        .accessibilityIdentifier(AccessibilityID.sectionNotesDone)
                }
                .padding(16)
            }
            .frame(width: 560, height: 540)
            .background(Theme.color.ground)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.sectionNotesSheet)
            .onAppear { reload() }
            .onChange(of: focused) { old, _ in
                commit(old)
            }
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("Section Notes")
                    .font(Theme.font.sectionHeading)
                    .foregroundStyle(Theme.color.ink)
                Text("Notes show in the chart everywhere. “Show on stage only” keeps one off "
                    + "the chart and shows it beside its section on stage.")
                    .font(.callout)
                    .foregroundStyle(Theme.color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }

        private var emptyState: some View {
            Text("This song has no sections yet. Mark its verses and choruses in the editor, "
                + "then add notes to them here.")
                .font(.callout)
                .foregroundStyle(Theme.color.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
        }

        // MARK: Groups

        private func groupView(_ group: SectionNoteGroup) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(group.title)
                        .font(Theme.font.label)
                        .foregroundStyle(Theme.color.ink)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(AccessibilityID.sectionNotesGroup(group.title))
                    if let caption = caption(group) {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(Theme.color.muted)
                    }
                    Spacer()
                    if canAdd(to: group) {
                        Button("Add Note", systemImage: "plus") { add(to: group) }
                            .buttonStyle(.segueSecondary)
                            .controlSize(.small)
                            .accessibilityLabel("Add Note to \(group.title)")
                            .accessibilityIdentifier(AccessibilityID.sectionNotesAdd(group.title))
                    }
                }
                ForEach(group.notes) { note in
                    noteRow(note, in: group)
                }
                ForEach(additions.filter { $0.group == group.id }) { addition in
                    additionRow(addition, in: group)
                }
                if group.notes.isEmpty, !additions.contains(where: { $0.group == group.id }) {
                    Text("No notes")
                        .font(.callout)
                        .foregroundStyle(Theme.color.muted)
                }
            }
        }

        private func caption(_ group: SectionNoteGroup) -> String? {
            switch group.kind {
            case .section: group.occurrences > 1 ? "\(group.occurrences) times" : nil
            case .loose: "Outside any section"
            case .orphaned: "Not in the song any more"
            }
        }

        private func canAdd(to group: SectionNoteGroup) -> Bool {
            !host.isReadOnly
                && (group.acceptsChartNotes || (group.acceptsStageNotes && host.canEditStageNotes))
        }

        // MARK: Rows

        private func noteRow(_ note: SectionNote, in group: SectionNoteGroup) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Note", text: draftBinding(note))
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .note(note.id))
                    .onSubmit { commit(.note(note.id)) }
                    .disabled(host.isReadOnly)
                    .accessibilityLabel("Note on \(group.title)")
                    .accessibilityIdentifier(AccessibilityID.sectionNoteText)
                HStack(spacing: 12) {
                    stageToggle(note, in: group)
                    placement(note, in: group)
                    Spacer()
                    Button {
                        run(.delete(note.id))
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.color.muted)
                    .disabled(host.isReadOnly)
                    .help("Delete Note")
                    .accessibilityLabel("Delete Note")
                    .accessibilityIdentifier(AccessibilityID.sectionNoteDelete)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.color.surfaceAlt))
            .accessibilityElement(children: .contain)
        }

        private func stageToggle(_ note: SectionNote, in group: SectionNoteGroup) -> some View {
            let allowed = note.isStageOnly
                ? group.kind == .section
                : group.kind == .section && host.canEditStageNotes
            return Toggle("Show on stage only", isOn: Binding(
                get: { note.isStageOnly },
                set: { run(.setStageOnly(note.id, $0)) },
            ))
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .disabled(host.isReadOnly || !allowed)
            .help(allowed ? "" : stageHelp(group))
            .accessibilityIdentifier(AccessibilityID.sectionNoteStageOnly)
        }

        private func stageHelp(_ group: SectionNoteGroup) -> String {
            switch group.kind {
            case .loose: "Stage-only notes pin to a named section."
            case .orphaned: "Move it to a section first."
            case .section: "Stage-only notes can be added once the song is saved."
            }
        }

        /// Which occurrence a stage note shows on, or where an orphaned one goes; a chart
        /// note's occurrence is where its line sits.
        @ViewBuilder
        private func placement(_ note: SectionNote, in group: SectionNoteGroup) -> some View {
            if note.isStageOnly, group.kind == .orphaned {
                Menu("Move to") {
                    ForEach(notes.groups.filter { $0.kind == .section }) { target in
                        Button(target.title) {
                            run(.pin(note.id, section: target.title, occurrence: nil))
                        }
                    }
                }
                .fixedSize()
                .controlSize(.small)
                .disabled(host.isReadOnly)
                .accessibilityIdentifier(AccessibilityID.sectionNoteMove)
            } else if note.isStageOnly, group.hasPlacements {
                Picker("Shows", selection: Binding(
                    get: { note.occurrence },
                    set: { run(.place(note.id, $0.map(NotePlacement.instance) ?? .everyTime)) },
                )) {
                    Text("Every time").tag(Int?.none)
                    ForEach(1 ... group.occurrences, id: \.self) {
                        Text("Only #\($0)").tag(Int?.some($0))
                    }
                }
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
                .disabled(host.isReadOnly)
                .accessibilityLabel("Shows")
                .accessibilityIdentifier(AccessibilityID.sectionNoteOccurrence)
            } else if let occurrence = note.occurrence, !note.isStageOnly {
                Text("In #\(occurrence)")
                    .font(.caption)
                    .foregroundStyle(Theme.color.muted)
            }
        }

        // MARK: Edits

        private func draftBinding(_ note: SectionNote) -> Binding<String> {
            Binding(
                get: { drafts[note.id] ?? note.text },
                set: { drafts[note.id] = $0 },
            )
        }

        private func add(to group: SectionNoteGroup, placement: NotePlacement? = nil) {
            let addition = Addition(
                group: group.id,
                stageOnly: !group.acceptsChartNotes,
                placement: group.hasPlacements ? placement ?? group.defaultPlacement : nil,
            )
            additions.append(addition)
            // Focus once the new field is in the view.
            Task { @MainActor in focused = .addition(addition.id) }
        }

        /// Saves what `field` holds: a changed note's text (an emptied note is deleted), or
        /// a new note (an empty one is dropped).
        private func commit(_ field: Field?) {
            switch field {
            case let .note(id):
                guard let draft = drafts.removeValue(forKey: id),
                      let note = notes.note(id), draft != note.text
                else { return }
                let text = CommentText.clean(draft)
                run(text.isEmpty ? .delete(id) : .setText(id, text))
            case let .addition(id):
                guard let index = additions.firstIndex(where: { $0.id == id }) else { return }
                let addition = additions.remove(at: index)
                let text = CommentText.clean(addition.text)
                guard !text.isEmpty else { return }
                run(.add(
                    group: addition.group,
                    text: text,
                    stageOnly: addition.stageOnly,
                    placement: addition.placement,
                ))
            case nil:
                return
            }
        }

        /// Applies `edit` after the edits before it, then re-reads the song. The edit names
        /// its note by ID, resolved when it applies, so a queued edit never hits another note;
        /// a note whose ID the edit changed keeps its focus and draft under the new ID.
        private func run(_ edit: SectionNoteEdit) {
            let previous = work
            let context = SectionNoteEditContext(entry: host.entry)
            work = Task { @MainActor in
                await previous?.value
                let change = await host.apply(edit, context)
                reload(renaming: edit.noteID, to: change?.resultID)
            }
        }

        private func reload(renaming old: SectionNoteID? = nil, to new: SectionNoteID? = nil) {
            notes = host.notes()
            if let old, let new, old != new, focused == .note(old) {
                if let draft = drafts.removeValue(forKey: old) {
                    drafts[new] = draft
                }
                focused = .note(new)
            }
            // Typing in progress survives a reload; every other draft was committed.
            if case let .note(id) = focused, let draft = drafts[id] {
                drafts = [id: draft]
            } else {
                drafts = [:]
            }
        }

        private func finish() {
            commit(focused)
            for addition in additions {
                commit(.addition(addition.id))
            }
            let pending = work
            Task { @MainActor in
                await pending?.value
                await work?.value
                dismiss()
            }
        }
    }

    private extension SectionNoteEdit {
        /// The existing note this edit names; nil for an add.
        var noteID: SectionNoteID? {
            switch self {
            case let .delete(id), let .pin(id, _, _), let .place(id, _),
                 let .setStageOnly(id, _), let .setText(id, _):
                id
            case .add:
                nil
            }
        }
    }

    // MARK: Pending additions

    extension SectionNotesSheet {
        /// A row for one pending addition. Its bindings find the addition by id, never by
        /// position: committing one (when focus leaves it) removes it from `additions` while
        /// its row is still on screen for a pass, and a positional binding would index past
        /// the end of the shortened array.
        private func additionRow(_ addition: Addition, in group: SectionNoteGroup) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                TextField("New note", text: additionBinding(addition.id, \.text, or: ""))
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .addition(addition.id))
                    .onSubmit { commit(.addition(addition.id)) }
                    .accessibilityLabel("New note on \(group.title)")
                    .accessibilityIdentifier(AccessibilityID.sectionNoteText)
                Toggle("Show on stage only", isOn: additionBinding(
                    addition.id, \.stageOnly, or: addition.stageOnly,
                ))
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .disabled(!group.acceptsChartNotes
                    || !(group.acceptsStageNotes && host.canEditStageNotes))
                .accessibilityIdentifier(AccessibilityID.sectionNoteStageOnly)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.color.surfaceAlt))
            .accessibilityElement(children: .contain)
        }

        /// A binding to one field of the pending addition with `id`; a row that outlives its
        /// addition by a pass shows `fallback` and ignores writes.
        private func additionBinding<Value>(
            _ id: UUID,
            _ keyPath: WritableKeyPath<Addition, Value>,
            or fallback: Value,
        ) -> Binding<Value> {
            Binding(
                get: { additions.first { $0.id == id }?[keyPath: keyPath] ?? fallback },
                set: { value in
                    if let index = additions.firstIndex(where: { $0.id == id }) {
                        additions[index][keyPath: keyPath] = value
                    }
                },
            )
        }
    }
#endif
