#if os(macOS)
    import Library
    import SwiftUI

    /// Edits a song's notes and cues (shown in live mode). A cue is pinned to a section
    /// label and, optionally, to one occurrence of it.
    struct NotesEditorSheet: View {
        let record: SongRecord
        /// The song's section labels in order (repeats included).
        let sections: [String]
        let onSave: (String?, [SongCue]) -> Void
        @Environment(\.dismiss) private var dismiss
        @State private var notes = ""
        @State private var cues: [EditableCue] = []

        private struct EditableCue: Identifiable {
            let id = UUID()
            var section: String
            var occurrence: Int?
            var text: String
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Notes & Cues")
                    .font(Theme.font.sectionHeading)
                    .foregroundStyle(Theme.color.ink)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes")
                        .font(Theme.font.label)
                        .foregroundStyle(Theme.color.muted)
                    TextEditor(text: $notes)
                        .font(Theme.font.body)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(height: 90)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Theme.color.controlBorder, lineWidth: 1)
                        }
                        .accessibilityIdentifier(AccessibilityID.notesEditorText)
                }
                cueList
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.segueSecondary)
                    Button("Save", action: save)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.seguePrimary)
                        .accessibilityIdentifier(AccessibilityID.notesEditorSave)
                }
            }
            .padding(20)
            .frame(width: 520)
            .onAppear(perform: load)
        }

        private var cueList: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cues")
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.muted)
                if cues.isEmpty {
                    Text("A cue shows beside its section on stage (“watch Ravi for the stop”).")
                        .font(.callout)
                        .foregroundStyle(Theme.color.muted)
                }
                ForEach($cues) { $cue in
                    HStack(spacing: 8) {
                        Picker("Section", selection: $cue.section) {
                            ForEach(sectionChoices(including: cue.section), id: \.self) {
                                Text($0).tag($0)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                        .accessibilityIdentifier(AccessibilityID.notesEditorCueSection)
                        Picker("Occurrence", selection: $cue.occurrence) {
                            Text("Every time").tag(Int?.none)
                            ForEach(1 ... max(occurrences(of: cue.section), 1), id: \.self) {
                                Text("Only #\($0)").tag(Int?.some($0))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                        TextField("Cue", text: $cue.text)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier(AccessibilityID.notesEditorCueText)
                        Button {
                            cues.removeAll { $0.id == cue.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.color.muted)
                        .accessibilityLabel("Remove cue")
                        .accessibilityIdentifier(AccessibilityID.notesEditorCueRemove)
                    }
                }
                Button("Add Cue", systemImage: "plus") {
                    cues.append(EditableCue(
                        section: uniqueSections.first ?? "Chorus",
                        occurrence: nil,
                        text: "",
                    ))
                }
                .buttonStyle(.segueSecondary)
                .controlSize(.small)
                .accessibilityIdentifier(AccessibilityID.notesEditorAddCue)
            }
        }

        private var uniqueSections: [String] {
            var seen = Set<String>()
            return sections.filter { seen.insert($0.lowercased()).inserted }
        }

        private func sectionChoices(including current: String) -> [String] {
            let unique = uniqueSections
            return unique.contains { $0.caseInsensitiveCompare(current) == .orderedSame }
                ? unique : unique + [current]
        }

        private func occurrences(of section: String) -> Int {
            sections.count { $0.caseInsensitiveCompare(section) == .orderedSame }
        }

        private func load() {
            notes = record.sidecar.notes ?? ""
            cues = record.sidecar.cues.map {
                EditableCue(section: $0.section, occurrence: $0.occurrence, text: $0.text)
            }
        }

        private func save() {
            let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let saved = cues.compactMap { cue -> SongCue? in
                let text = cue.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return SongCue(section: cue.section, occurrence: cue.occurrence, text: text)
            }
            onSave(trimmed.isEmpty ? nil : notes, saved)
            dismiss()
        }
    }
#endif
