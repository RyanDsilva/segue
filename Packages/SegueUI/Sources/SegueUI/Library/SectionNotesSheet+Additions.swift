#if os(macOS)
    import Editing
    import Library
    import SwiftUI

    // MARK: Pending additions

    extension SectionNotesSheet {
        /// A row for one pending addition. Its bindings find the addition by id, never by
        /// position: committing one (when focus leaves it) removes it from `additions` while
        /// its row is still on screen for a pass, and a positional binding would index past
        /// the end of the shortened array.
        func additionRow(_ addition: Addition, in group: SectionNoteGroup) -> some View {
            let onRepeat = SectionNotesPlacement.isRepeat(addition.placement, in: group)
            return VStack(alignment: .leading, spacing: 6) {
                TextField("New note", text: additionBinding(addition.id, \.text, or: ""))
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .addition(addition.id))
                    .onSubmit { commit(.addition(addition.id)) }
                    .accessibilityLabel("New note on \(group.title)")
                    .accessibilityIdentifier(AccessibilityID.sectionNoteText)
                additionControls(addition, in: group, onRepeat: onRepeat)
                if !addition.stageOnly,
                   let hint = SectionNotesPlacement.repeatHint(for: addition.placement, in: group)
                {
                    RepeatHintView(hint: hint) {
                        if let index = pending.firstIndex(where: { $0.id == addition.id }) {
                            pending[index].placement = hint.chartPlacement
                            pending[index].stageOnly = false
                        }
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.color.surfaceAlt))
            .accessibilityElement(children: .contain)
        }

        /// "Show on stage only", the "Shows on" pop-up and the discard button of a new note.
        /// On a repeat the checkbox is on and disabled: only a stage note can go there.
        private func additionControls(
            _ addition: Addition,
            in group: SectionNoteGroup,
            onRepeat: Bool,
        ) -> some View {
            let chartAllowed = group.acceptsChartNotes
            let stageAllowed = group.acceptsStageNotes && host.canEditStageNotes
            return HStack(spacing: 8) {
                Toggle("Show on stage only", isOn: Binding(
                    get: { onRepeat || addition.stageOnly },
                    set: { setAdditionStageOnly(addition.id, $0, in: group) },
                ))
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .fixedSize()
                .disabled(onRepeat || !chartAllowed || !stageAllowed)
                .accessibilityIdentifier(AccessibilityID.sectionNoteStageOnly)
                Spacer()
                if group.hasPlacements, let current = addition.placement {
                    PlacementPicker(
                        choices: SectionNotesPlacement.choices(
                            in: group,
                            chart: chartAllowed && !addition.stageOnly,
                        ),
                        selection: Binding(
                            get: { current },
                            set: { additionBinding(addition.id, \.placement, or: nil)
                                .wrappedValue = $0
                            },
                        ),
                        identifier: AccessibilityID.sectionNoteAdditionPlacement,
                    )
                }
                Button {
                    pending.removeAll { $0.id == addition.id }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.color.muted)
                .help("Discard Note")
                .accessibilityLabel("Discard Note")
                .accessibilityIdentifier(AccessibilityID.sectionNoteDiscard)
            }
        }

        /// Turning "Show on stage only" off moves a placement a chart note cannot take (the
        /// one written-out chorus of a repeated label) to Every time.
        private func setAdditionStageOnly(
            _ id: UUID,
            _ stageOnly: Bool,
            in group: SectionNoteGroup,
        ) {
            guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
            pending[index].stageOnly = stageOnly
            if !stageOnly, let placement = pending[index].placement,
               !SectionNotesPlacement.choices(in: group, chart: true)
                   .contains(where: { $0.placement == placement })
            {
                pending[index].placement = .everyTime
            }
        }

        /// A binding to one field of the pending addition with `id`; a row that outlives its
        /// addition by a pass shows `fallback` and ignores writes.
        private func additionBinding<Value>(
            _ id: UUID,
            _ keyPath: WritableKeyPath<Addition, Value>,
            or fallback: Value,
        ) -> Binding<Value> {
            Binding(
                get: { pending.first { $0.id == id }?[keyPath: keyPath] ?? fallback },
                set: { value in
                    if let index = pending.firstIndex(where: { $0.id == id }) {
                        pending[index][keyPath: keyPath] = value
                    }
                },
            )
        }
    }
#endif
