#if os(macOS)
    import Library
    import Setlists
    import SwiftUI

    /// The popover behind a set row: this slot's key (transpose), capo and note, without
    /// touching the song. Each change saves at once; "Use song's" clears the override.
    struct SetEntryEditor: View {
        let entry: SetlistEntry
        let record: SongRecord?
        let onChange: (SetlistEntry) -> Void
        /// Opens Arrange Sections (P3-16); nil when the song is missing.
        var onArrange: (() -> Void)?
        @Environment(\.dismiss) private var dismiss
        @State private var note = ""

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                Text(record.map(SongSummary.title) ?? "Missing song")
                    .font(Theme.font.sectionHeading)
                    .foregroundStyle(Theme.color.ink)
                    .lineLimit(1)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        label("Key")
                        stepper(
                            value: transposeText,
                            down: AccessibilityID.entryTransposeDown,
                            up: AccessibilityID.entryTransposeUp,
                            valueID: AccessibilityID.entryTransposeValue,
                        ) { change(transposeBy: $0) }
                    }
                    GridRow {
                        label("Capo")
                        stepper(
                            value: capoText,
                            down: AccessibilityID.entryCapoDown,
                            up: AccessibilityID.entryCapoUp,
                            valueID: AccessibilityID.entryCapoValue,
                        ) { change(capoBy: $0) }
                    }
                    GridRow {
                        label("Sections")
                        Button(arrangementText) {
                            saveNote()
                            dismiss()
                            onArrange?()
                        }
                        .buttonStyle(.segueSecondary)
                        .controlSize(.small)
                        .disabled(onArrange == nil)
                        .help("Choose which sections this slot plays for this gig")
                        .accessibilityLabel("Arrangement: \(arrangementText)")
                        .accessibilityIdentifier(AccessibilityID.arrangementOpen)
                    }
                    GridRow {
                        label("Note")
                        TextField("“start soft”", text: $note)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .onSubmit(saveNote)
                            .accessibilityIdentifier(AccessibilityID.entryNoteField)
                    }
                }
                HStack {
                    Button("Use Song’s Key and Capo") {
                        var updated = entry
                        updated.overrides = SetlistOverrides()
                        onChange(updated)
                    }
                    .buttonStyle(.segueSecondary)
                    .controlSize(.small)
                    .disabled(entry.overrides.isEmpty)
                    .accessibilityIdentifier(AccessibilityID.entryReset)
                    Spacer()
                    Button("Done") {
                        saveNote()
                        dismiss()
                    }
                    .buttonStyle(.seguePrimary)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier(AccessibilityID.entryDone)
                }
            }
            .padding(16)
            .frame(width: 340)
            .onAppear { note = entry.note ?? "" }
            .onDisappear(perform: saveNote)
        }

        /// "Full song", "Custom: 6 of 8 sections" or "Out of date: full song".
        private var arrangementText: String {
            guard let arrangement = entry.arrangement else { return "Full song…" }
            guard let record else { return "Custom…" }
            let units = SongSections.units(of: record.document)
            if ArrangementResolver.resolve(arrangement, units: units).isOutOfDate {
                return "Out of date: full song…"
            }
            let draft = ArrangementDraft(arrangement: arrangement, units: units)
            return "Custom: \(draft.playedCount) of \(draft.partCount) sections…"
        }

        private var display: SetlistEntryDisplay {
            SetlistEntryDisplay(entry: entry, record: record)
        }

        private var songTranspose: Int {
            record?.sidecar.displayPrefs.transpose ?? 0
        }

        private var songCapo: Int {
            max(record?.document.metadata.capo ?? 0, 0)
        }

        /// The key the chords show in this slot: "A · +2", or "G · as saved" when the
        /// song's own transpose applies.
        private var transposeText: String {
            let key = display.key ?? "-"
            guard let transpose = entry.overrides.transpose else { return "\(key) · as saved" }
            let sign = transpose > 0 ? "+" : transpose == 0 ? "±" : ""
            return "\(key) · \(sign)\(transpose)"
        }

        /// "Capo 4", or "Capo 2 · as saved" when the song's `{capo}` applies.
        private var capoText: String {
            let capo = entry.overrides.capo ?? songCapo
            let text = capo > 0 ? "Capo \(capo)" : "No capo"
            return entry.overrides.capo == nil ? "\(text) · as saved" : text
        }

        private func change(transposeBy step: Int) {
            var updated = entry
            let next = (entry.overrides.transpose ?? songTranspose) + step
            updated.overrides.transpose = min(max(next, -11), 11)
            onChange(updated)
        }

        private func change(capoBy step: Int) {
            var updated = entry
            let next = (entry.overrides.capo ?? songCapo) + step
            updated.overrides.capo = min(max(next, 0), 11)
            onChange(updated)
        }

        private func saveNote() {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = trimmed.isEmpty ? nil : trimmed
            guard value != entry.note else { return }
            var updated = entry
            updated.note = value
            onChange(updated)
        }

        private func label(_ text: String) -> some View {
            Text(text)
                .font(Theme.font.label)
                .foregroundStyle(Theme.color.muted)
        }

        private func stepper(
            value: String,
            down: String,
            up: String,
            valueID: String,
            step: @escaping (Int) -> Void,
        ) -> some View {
            HStack(spacing: 6) {
                Button { step(-1) } label: {
                    Image(systemName: "minus").frame(width: 12, height: 16)
                }
                .buttonStyle(.segueSecondary)
                .accessibilityLabel("Down")
                .accessibilityIdentifier(down)
                Text(value)
                    .font(SchibstedGrotesk.semiBold.font(size: 14))
                    .foregroundStyle(Theme.color.ink)
                    .frame(minWidth: 150)
                    .accessibilityIdentifier(valueID)
                Button { step(1) } label: { Image(systemName: "plus").frame(width: 12, height: 16) }
                    .buttonStyle(.segueSecondary)
                    .accessibilityLabel("Up")
                    .accessibilityIdentifier(up)
            }
        }
    }
#endif
