#if os(macOS)
    import Library
    import SwiftUI

    /// New Smart Filter and Edit: a sheet with the name, then one row per condition (field,
    /// operator, value, minus / plus), like a Music smart playlist (direction A). The footer
    /// counts the songs that match as you edit; Save writes `filters/<slug>.filter.json`.
    struct SmartFilterEditorSheet: View {
        /// What Save does with the result.
        let title: String
        let saveTitle: String
        /// The library's tags (most used first) for the tag rows' completions.
        let libraryTags: [String]
        /// The songs and play history the live count is taken over.
        let songs: [SongRecord]
        let playStats: [SongID: PlayStats]
        let onSave: (String, SmartFilterConditions) -> Void
        @Environment(\.dismiss) private var dismiss
        @State private var draft: SmartFilterDraft

        init(
            title: String,
            saveTitle: String,
            draft: SmartFilterDraft,
            libraryTags: [String],
            songs: [SongRecord],
            playStats: [SongID: PlayStats],
            onSave: @escaping (String, SmartFilterConditions) -> Void,
        ) {
            self.title = title
            self.saveTitle = saveTitle
            self.libraryTags = libraryTags
            self.songs = songs
            self.playStats = playStats
            self.onSave = onSave
            _draft = State(initialValue: draft)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(Theme.font.sectionHeading)
                    .foregroundStyle(Theme.color.ink)
                HStack(spacing: 12) {
                    Text("Name")
                        .font(SchibstedGrotesk.semiBold.font(size: 13))
                        .foregroundStyle(Theme.color.muted)
                    TextField("Name", text: $draft.name, prompt: Text("Openers"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                        .accessibilityIdentifier(AccessibilityID.smartFilterName)
                }
                Text("Songs matching all of these conditions")
                    .font(SchibstedGrotesk.semiBold.font(size: 13))
                    .foregroundStyle(Theme.color.ink)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(draft.rows) { row in
                        SmartFilterConditionRow(
                            row: rowBinding(row.id, fallback: row),
                            isFirst: row.id == draft.rows.first?.id,
                            kinds: draft.unusedKinds(besides: row),
                            libraryTags: libraryTags,
                            canRemove: draft.rows.count > 1,
                            canAdd: !draft.unusedKinds().isEmpty,
                            onRemove: { draft.removeRow(row.id) },
                            onAdd: { draft.addRow(after: row.id) },
                        )
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Conditions")
                .accessibilityIdentifier(AccessibilityID.smartFilterConditions)
                Rule()
                HStack(spacing: 10) {
                    GuideHelpButton(.smartFilters)
                    Text(footer)
                        .font(Theme.font.body)
                        .foregroundStyle(draft.problem == nil ? Theme.color.muted : Theme.color.cue)
                        .accessibilityIdentifier(AccessibilityID.smartFilterMatchCount)
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.segueSecondary)
                    Button(saveTitle, action: save)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.seguePrimary)
                        .disabled(draft.problem != nil)
                        .accessibilityIdentifier(AccessibilityID.smartFilterSave)
                }
            }
            .padding(20)
            .frame(width: 780)
        }

        private var footer: String {
            if let problem = draft.problem {
                return problem
            }
            let matcher = draft.conditions.compiled(playStats: playStats)
            let count = songs.count(where: matcher.matches)
            let songsText = count == 1 ? "1 song matches." : "\(count) songs match."
            return draft.conditions.length == nil
                ? songsText
                : songsText + " Songs without a length are left out."
        }

        private func save() {
            guard draft.problem == nil else { return }
            onSave(draft.name, draft.conditions)
            dismiss()
        }
    }

    /// One condition row: "and", field popup, operator popup, value, minus / plus.
    extension SmartFilterEditorSheet {
        /// A row's binding keyed by its ID, never by position (the SEGUE-MACOS-2 shape): a
        /// field still focused in a removed row reads its last value and its writes are
        /// dropped, instead of writing through a stale index.
        private func rowBinding(
            _ id: SmartFilterDraft.Row.ID,
            fallback: SmartFilterDraft.Row,
        ) -> Binding<SmartFilterDraft.Row> {
            Self.rowBinding(in: $draft, id: id, fallback: fallback)
        }

        static func rowBinding(
            in draft: Binding<SmartFilterDraft>,
            id: SmartFilterDraft.Row.ID,
            fallback: SmartFilterDraft.Row,
        ) -> Binding<SmartFilterDraft.Row> {
            Binding(
                get: { draft.wrappedValue.rows.first { $0.id == id } ?? fallback },
                set: { value in
                    if let index = draft.wrappedValue.rows.firstIndex(where: { $0.id == id }) {
                        draft.wrappedValue.rows[index] = value
                    }
                },
            )
        }
    }

    struct SmartFilterConditionRow: View {
        @Binding var row: SmartFilterDraft.Row
        let isFirst: Bool
        /// The kinds this row may switch to (its own plus the unused ones).
        let kinds: [SmartFilterDraft.Kind]
        let libraryTags: [String]
        let canRemove: Bool
        let canAdd: Bool
        let onRemove: () -> Void
        let onAdd: () -> Void

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(isFirst ? "" : "and")
                    .font(SchibstedGrotesk.medium.font(size: 11))
                    .foregroundStyle(Theme.color.muted)
                    .frame(width: 26, alignment: .leading)
                    .accessibilityHidden(true)
                Picker("Field", selection: fieldBinding) {
                    ForEach(fields) { field in
                        Text(field.rawValue).tag(field)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 130, alignment: .leading)
                .accessibilityIdentifier(AccessibilityID.smartFilterField)
                Picker("Operator", selection: $row.kind) {
                    ForEach(kinds.filter { $0.field == row.kind.field }) { kind in
                        Text(kind.operatorTitle).tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 150, alignment: .leading)
                .accessibilityIdentifier(AccessibilityID.smartFilterOperator)
                value
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    Button(action: onRemove) {
                        Image(systemName: "minus")
                            .frame(width: 12, height: 12)
                    }
                    .disabled(!canRemove)
                    .help("Remove this condition")
                    .accessibilityLabel("Remove condition")
                    .accessibilityIdentifier(AccessibilityID.smartFilterRemoveRow)
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .frame(width: 12, height: 12)
                    }
                    .disabled(!canAdd)
                    .help("Add a condition")
                    .accessibilityLabel("Add condition")
                    .accessibilityIdentifier(AccessibilityID.smartFilterAddRow)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(row.kind.field.rawValue) \(row.kind.operatorTitle)")
            .accessibilityIdentifier(AccessibilityID.smartFilterRow)
        }

        /// Fields with at least one kind this row may take.
        private var fields: [SmartFilterDraft.Field] {
            SmartFilterDraft.Field.allCases.filter { field in
                kinds.contains { $0.field == field }
            }
        }

        /// Switching the field picks that field's first free kind and clears the value.
        private var fieldBinding: Binding<SmartFilterDraft.Field> {
            Binding(
                get: { row.kind.field },
                set: { field in
                    guard field != row.kind.field,
                          let kind = kinds.first(where: { $0.field == field })
                    else { return }
                    row = SmartFilterDraft.Row(kind: kind)
                },
            )
        }

        @ViewBuilder private var value: some View {
            switch row.kind {
            case .allTags, .anyTags, .noneTags:
                TagEditor(tags: row.tags, suggestions: libraryTags) { tags in
                    row.tags = tags
                }
            case .proficiency:
                HStack(spacing: 6) {
                    ForEach(Proficiency.allCases, id: \.self) { level in
                        let isOn = row.proficiencies.contains(level)
                        FilterChip(isOn: isOn) {
                            if isOn {
                                row.proficiencies.remove(level)
                            } else {
                                row.proficiencies.insert(level)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                ProficiencyDot(level, inverted: isOn)
                                Text(ProficiencyMark.label(level))
                            }
                        }
                        .accessibilityLabel(ProficiencyMark.label(level))
                    }
                }
            case .keys:
                keys
            case .tempo:
                range(prompt: "BPM", unit: "BPM")
            case .length:
                range(prompt: "m:ss", unit: nil)
            case .neverPlayed:
                Text("in any show")
                    .font(Theme.font.body)
                    .foregroundStyle(Theme.color.muted)
            }
        }

        private var keys: some View {
            FlowLayout(spacing: 6) {
                ForEach(row.keys, id: \.self) { key in
                    FilterChip(isOn: false) {
                        row.keys.removeAll { $0 == key }
                    } label: {
                        HStack(spacing: 4) {
                            Text(key)
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                        }
                    }
                    .accessibilityLabel("Remove key \(key)")
                }
                Menu("Add key") {
                    ForEach(freeKeys, id: \.self) { key in
                        Button(key) { row.keys.append(key) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityIdentifier(AccessibilityID.smartFilterAddKey)
            }
        }

        /// Keys not picked yet.
        private var freeKeys: [String] {
            SmartFilterDraft.keyChoices.filter { !row.keys.contains($0) }
        }

        private func range(prompt: String, unit: String?) -> some View {
            HStack(spacing: 6) {
                TextField("From", text: $row.lower, prompt: Text(prompt))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .accessibilityLabel("From")
                    .accessibilityIdentifier(AccessibilityID.smartFilterLower)
                Text("and")
                    .font(Theme.font.body)
                    .foregroundStyle(Theme.color.muted)
                TextField("To", text: $row.upper, prompt: Text(prompt))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .accessibilityLabel("To")
                    .accessibilityIdentifier(AccessibilityID.smartFilterUpper)
                if let unit {
                    Text(unit)
                        .font(Theme.font.body)
                        .foregroundStyle(Theme.color.muted)
                }
            }
        }
    }
#endif
