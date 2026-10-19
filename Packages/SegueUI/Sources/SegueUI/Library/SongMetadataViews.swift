#if os(macOS)
    import Library
    import LiveLayout
    import SwiftUI

    /// The editable metadata above the chart: proficiency (Learning / Ready / Pro), tags,
    /// play history, and the notes and cues live mode shows. Every change saves to the
    /// sidecar at once through `LibraryStore.updateMetadata`.
    struct SongMetadataSection: View {
        let model: LibraryViewModel
        let record: SongRecord
        @State private var isEditingNotes = false

        var body: some View {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    label("Proficiency")
                    ProficiencyPicker(
                        selection: record.sidecar.proficiency,
                        isDisabled: record.isReadOnly,
                    ) { level in
                        save { $0.proficiency = level }
                    }
                }
                GridRow {
                    label("Tags")
                    TagEditor(
                        tags: record.sidecar.tags,
                        suggestions: model.tagNames,
                        isDisabled: record.isReadOnly,
                    ) { tags in
                        save { $0.tags = tags }
                    }
                }
                GridRow {
                    label("Played")
                    Text(playHistory)
                        .font(Theme.font.body)
                        .foregroundStyle(Theme.color.muted)
                        .accessibilityIdentifier(AccessibilityID.songPlayStats)
                }
                GridRow {
                    label("Notes")
                    notesAndCues
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.songMeta)
            .sheet(isPresented: $isEditingNotes) {
                NotesEditorSheet(
                    record: record,
                    // The labels live mode pins cues to (the gutter's label).
                    sections: SongSummary.renderModel(record).sections
                        .compactMap(RepeatCollapser.displayLabel),
                ) { notes, cues in
                    save {
                        $0.notes = notes
                        $0.cues = cues
                    }
                }
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

        private var notesAndCues: some View {
            VStack(alignment: .leading, spacing: 6) {
                let notes = record.sidecar.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let notes, !notes.isEmpty {
                    Text(notes)
                        .font(Theme.font.body)
                        .foregroundStyle(Theme.color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(AccessibilityID.songNotes)
                }
                ForEach(Array(record.sidecar.cues.enumerated()), id: \.offset) { _, cue in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Self.cueLabel(cue))
                            .font(Theme.font.label)
                            .foregroundStyle(Theme.color.muted)
                        Text(cue.text)
                            .font(Theme.font.body)
                            .foregroundStyle(Theme.color.ink)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(AccessibilityID.songCue)
                }
                Button(hasNotes ? "Edit Notes & Cues…" : "Add Notes & Cues…") {
                    isEditingNotes = true
                }
                .buttonStyle(.segueSecondary)
                .controlSize(.small)
                .disabled(record.isReadOnly)
                .accessibilityIdentifier(AccessibilityID.songEditNotes)
            }
        }

        private var hasNotes: Bool {
            !(record.sidecar.notes ?? "").isEmpty || !record.sidecar.cues.isEmpty
        }

        /// "Chorus", "Verse (2nd)".
        static func cueLabel(_ cue: SongCue) -> String {
            guard let occurrence = cue.occurrence else { return cue.section }
            return "\(cue.section) (\(occurrence.formatted(.number))\(ordinalSuffix(occurrence)))"
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
