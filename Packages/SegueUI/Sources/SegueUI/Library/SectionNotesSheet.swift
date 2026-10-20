#if os(macOS)
    import Editing
    import Library
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
        /// Applies one edit as one undo step; false when it did not apply.
        let apply: (SectionNoteEdit) async -> Bool
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
                apply: { await model.editSectionNotes(id: id, $0) },
            )
        }

        static func editor(_ model: SongEditorViewModel) -> Self {
            SectionNotesHost(
                notes: { model.sectionNotes },
                canEditStageNotes: model.canEditStageNotes,
                apply: { model.editSectionNotes($0) },
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
                SectionNotesSheet(host: .editor(model), focus: request.group)
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
        @Environment(\.dismiss) private var dismiss
        @State private var notes = SectionNotes(sections: [], cues: [])
        /// Text being typed into an existing note, not committed yet.
        @State private var drafts: [SectionNote.Source: String] = [:]
        /// Notes being added, not committed yet.
        @State private var additions: [Addition] = []
        @State private var work: Task<Void, Never>?
        @FocusState private var focused: Field?

        private enum Field: Hashable {
            case note(SectionNote.Source)
            case addition(UUID)
        }

        private struct Addition: Identifiable {
            let id = UUID()
            let group: SectionNoteGroup.ID
            var text = ""
            var stageOnly: Bool
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
            .onAppear(perform: reload)
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
                ForEach($additions) { $addition in
                    if addition.group == group.id {
                        additionRow($addition, in: group)
                    }
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
                    .focused($focused, equals: .note(note.source))
                    .onSubmit { commit(.note(note.source)) }
                    .disabled(host.isReadOnly)
                    .accessibilityLabel("Note on \(group.title)")
                    .accessibilityIdentifier(AccessibilityID.sectionNoteText)
                HStack(spacing: 12) {
                    stageToggle(note, in: group)
                    placement(note, in: group)
                    Spacer()
                    Button {
                        run(.delete(note.source))
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
                set: { run(.setStageOnly(note.source, $0)) },
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
            if case .stage = note.source, group.kind == .orphaned {
                Menu("Move to") {
                    ForEach(notes.groups.filter { $0.kind == .section }) { target in
                        Button(target.title) {
                            run(.pin(note.source, section: target.title, occurrence: nil))
                        }
                    }
                }
                .fixedSize()
                .controlSize(.small)
                .disabled(host.isReadOnly)
                .accessibilityIdentifier(AccessibilityID.sectionNoteMove)
            } else if case .stage = note.source, group.occurrences > 1, let label = group.label {
                Picker("Shows", selection: Binding(
                    get: { note.occurrence },
                    set: { run(.pin(note.source, section: label, occurrence: $0)) },
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

        private func additionRow(
            _ addition: Binding<Addition>,
            in group: SectionNoteGroup,
        ) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                TextField("New note", text: addition.text)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .addition(addition.wrappedValue.id))
                    .onSubmit { commit(.addition(addition.wrappedValue.id)) }
                    .accessibilityLabel("New note on \(group.title)")
                    .accessibilityIdentifier(AccessibilityID.sectionNoteText)
                Toggle("Show on stage only", isOn: addition.stageOnly)
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

        // MARK: Edits

        private func draftBinding(_ note: SectionNote) -> Binding<String> {
            Binding(
                get: { drafts[note.source] ?? note.text },
                set: { drafts[note.source] = $0 },
            )
        }

        private func add(to group: SectionNoteGroup) {
            let addition = Addition(group: group.id, stageOnly: !group.acceptsChartNotes)
            additions.append(addition)
            // Focus once the new field is in the view.
            Task { @MainActor in focused = .addition(addition.id) }
        }

        /// Saves what `field` holds: a changed note's text (an emptied note is deleted), or
        /// a new note (an empty one is dropped).
        private func commit(_ field: Field?) {
            switch field {
            case let .note(source):
                guard let draft = drafts.removeValue(forKey: source),
                      let note = notes.note(source), draft != note.text
                else { return }
                let text = CommentText.clean(draft)
                run(text.isEmpty ? .delete(source) : .setText(source, text))
            case let .addition(id):
                guard let index = additions.firstIndex(where: { $0.id == id }) else { return }
                let addition = additions.remove(at: index)
                let text = CommentText.clean(addition.text)
                guard !text.isEmpty else { return }
                run(.add(group: addition.group, text: text, stageOnly: addition.stageOnly))
            case nil:
                return
            }
        }

        /// Applies `edit` after the edits before it, then re-reads the song.
        private func run(_ edit: SectionNoteEdit) {
            let previous = work
            work = Task { @MainActor in
                await previous?.value
                _ = await host.apply(edit)
                reload()
            }
        }

        private func reload() {
            notes = host.notes()
            // Typing in progress survives a reload; every other draft was committed.
            if case let .note(source) = focused, let draft = drafts[source] {
                drafts = [source: draft]
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
#endif
