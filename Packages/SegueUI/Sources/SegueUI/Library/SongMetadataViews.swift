#if os(macOS)
    import Library
    import SwiftUI

    /// The narrowest `SongMetadataSection` keeps its label column: the labels, the gap and
    /// the proficiency picker at its natural width.
    private let metadataGridMinWidth: CGFloat = 380

    /// The editable metadata above the chart: proficiency (Learning / Ready / Pro), tags,
    /// play history, the song's stage notes and its section notes (P3-13). Every change
    /// saves at once: metadata through `LibraryStore.updateMetadata`, section notes through
    /// the Section Notes sheet.
    struct SongMetadataSection: View {
        let model: LibraryViewModel
        let record: SongRecord
        @State private var isEditingSectionNotes = false
        @State private var notesDraft: String?
        @FocusState private var notesFocused: Bool
        /// Too narrow for the label column beside the proficiency picker: each label goes
        /// above its value instead.
        @State private var isNarrow = false

        var body: some View {
            Group {
                if isNarrow {
                    VStack(alignment: .leading, spacing: 14) {
                        stacked("Proficiency") { proficiency }
                        stacked("Tags") { tags }
                        stacked("Played") { played }
                        stacked("Notes") { songNotes }
                        stacked("Sections") { sectionNotes }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Grid(
                        alignment: .leadingFirstTextBaseline,
                        horizontalSpacing: 16,
                        verticalSpacing: 12,
                    ) {
                        GridRow {
                            label("Proficiency")
                            proficiency
                        }
                        GridRow {
                            label("Tags")
                            tags
                        }
                        GridRow {
                            label("Played")
                            played
                        }
                        GridRow {
                            label("Notes")
                            songNotes
                        }
                        GridRow {
                            label("Sections")
                            sectionNotes
                        }
                    }
                }
            }
            .onGeometryChange(for: Bool.self) { $0.size.width < metadataGridMinWidth } action: {
                isNarrow = $0
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.songMeta)
            .sheet(isPresented: $isEditingSectionNotes) {
                SectionNotesSheet(host: .library(model, id: record.id))
            }
            .onChange(of: notesFocused) { _, focused in
                if !focused {
                    commitNotes()
                }
            }
            .onChange(of: record.id) {
                notesDraft = nil
            }
        }

        private var proficiency: some View {
            ProficiencyPicker(
                selection: record.sidecar.proficiency,
                isDisabled: record.isReadOnly,
            ) { level in
                save { $0.proficiency = level }
            }
            .fixedSize()
        }

        private var tags: some View {
            TagEditor(
                tags: record.sidecar.tags,
                suggestions: model.tagNames,
                isDisabled: record.isReadOnly,
            ) { tags in
                save { $0.tags = tags }
            }
        }

        private var played: some View {
            Text(playHistory)
                .font(Theme.font.body)
                .foregroundStyle(Theme.color.muted)
                .accessibilityIdentifier(AccessibilityID.songPlayStats)
        }

        private func stacked(
            _ title: String,
            @ViewBuilder content: () -> some View,
        ) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.muted)
                content()
            }
        }

        private func label(_ text: String) -> some View {
            Text(text)
                .font(Theme.font.label)
                .foregroundStyle(Theme.color.muted)
                .gridColumnAlignment(.leading)
                .frame(minWidth: 76, alignment: .leading)
        }

        private var playHistory: String {
            guard let stats = model.playStats[record.id], stats.timesPlayed > 0 else {
                return "Not played at a gig yet"
            }
            let times = SongSummary.timesPlayed(stats.timesPlayed)
            guard let last = stats.lastPlayed else { return times }
            return "\(times)  ·  last \(last.formatted(date: .abbreviated, time: .omitted))"
        }

        /// The song's own notes, shown on stage above the first section: typed in place,
        /// saved on Return or when the field loses focus.
        private var songNotes: some View {
            TextField(
                "Add a note for the whole song",
                text: Binding(
                    get: { notesDraft ?? record.sidecar.notes ?? "" },
                    set: { notesDraft = $0 },
                ),
                axis: .vertical,
            )
            .textFieldStyle(.plain)
            .font(Theme.font.body)
            .foregroundStyle(Theme.color.ink)
            .lineLimit(1 ... 6)
            .focused($notesFocused)
            .onSubmit(commitNotes)
            .disabled(record.isReadOnly)
            .accessibilityLabel("Song notes")
            .accessibilityIdentifier(AccessibilityID.songNotes)
        }

        private func commitNotes() {
            guard let draft = notesDraft else { return }
            notesDraft = nil
            let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            let notes: String? = text.isEmpty ? nil : draft
            guard notes != record.sidecar.notes else { return }
            save { $0.notes = notes }
        }

        /// Every section note, chart and stage-only, with the sheet that edits them.
        private var sectionNotes: some View {
            VStack(alignment: .leading, spacing: 6) {
                let notes = SectionNotes(document: record.document, cues: record.sidecar.cues)
                ForEach(notes.groups) { group in
                    ForEach(group.notes) { note in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(Self.placeLabel(group: group, note: note))
                                .font(Theme.font.label)
                                .foregroundStyle(Theme.color.muted)
                            Text(note.text)
                                .font(Theme.font.body)
                                .foregroundStyle(Theme.color.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            if note.isStageOnly {
                                Text("Stage only")
                                    .font(.caption)
                                    .foregroundStyle(Theme.color.cueText)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Theme.color.cue.opacity(0.18)))
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(AccessibilityID.sectionNotesSummary)
                    }
                }
                Button("Section Notes…") {
                    commitNotes()
                    isEditingSectionNotes = true
                }
                .buttonStyle(.segueSecondary)
                .controlSize(.small)
                .disabled(record.isReadOnly)
                .accessibilityIdentifier(AccessibilityID.sectionNotesOpen)
            }
        }

        /// "Chorus", "Verse (2nd)", "Bridge (not in the song)".
        static func placeLabel(group: SectionNoteGroup, note: SectionNote) -> String {
            switch group.kind {
            case .orphaned:
                return "\(group.title) (not in the song)"
            case .loose:
                return group.title
            case .section:
                guard let occurrence = note.occurrence else { return group.title }
                let ordinal = occurrence.formatted(.number) + ordinalSuffix(occurrence)
                return "\(group.title) (\(ordinal))"
            }
        }

        private static func ordinalSuffix(_ value: Int) -> String {
            if (11 ... 13).contains(value % 100) {
                return "th"
            }
            return switch value % 10 {
            case 1: "st"
            case 2: "nd"
            case 3: "rd"
            default: "th"
            }
        }

        private func save(_ change: @escaping (inout SongMetadata) -> Void) {
            let id = record.id
            Task { await model.editMetadata(id: id, change) }
        }
    }
#endif
