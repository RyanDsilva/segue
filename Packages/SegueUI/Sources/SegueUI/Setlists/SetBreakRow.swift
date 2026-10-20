#if os(macOS)
    import Setlists
    import SwiftUI

    /// A break row (R85, direction C): a marker in the colour of the part it opens, its
    /// label and intermission, and that part's total with its "N unknown" button. Click it
    /// to select it and edit the label and intermission.
    struct SetBreakRow: View {
        let entry: SetlistEntry
        let info: SetlistBreak
        let part: Int
        let timing: PartTiming?
        let changeoverNote: String?
        let setlist: Setlist
        let library: LibraryViewModel
        let isSelected: Bool
        let isReadOnly: Bool
        /// Returns whether the click was plain (opens the editor).
        let onSelect: () -> Bool
        let onChange: (SetlistEntry) -> Void
        let onRemove: () -> Void
        @State private var isEditing = false

        var body: some View {
            let color = PartPalette.color(part)
            HStack(spacing: 10) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text("BREAK")
                    .font(SchibstedGrotesk.extraBold.font(size: 11))
                    .tracking(0.9)
                    .foregroundStyle(color)
                Text(info.label.isEmpty ? "Break" : info.label)
                    .font(SchibstedGrotesk.bold.font(size: 15))
                    .foregroundStyle(Theme.color.ink)
                    .lineLimit(1)
                if let length = info.length, length > 0 {
                    Text("\(SetlistTiming.format(length)) break")
                        .font(SchibstedGrotesk.medium.font(size: 13))
                        .foregroundStyle(Theme.color.muted)
                }
                Spacer(minLength: 8)
                if let timing {
                    Text(timing.totalText)
                        .font(SchibstedGrotesk.semiBold.font(size: 14))
                        .foregroundStyle(Theme.color.ink)
                        .help(changeoverNote ?? "")
                        .accessibilityIdentifier(AccessibilityID.setlistBreakTotal)
                    if timing.unknownCount > 0 {
                        MissingLengthsButton(
                            count: timing.unknownCount,
                            setlist: setlist,
                            library: library,
                            within: Set(timing.songItemIds),
                        )
                    }
                }
            }
            .padding(.leading, 32)
            .padding(.trailing, 40)
            .padding(.vertical, 10)
            .background {
                LinearGradient(
                    colors: [color.opacity(isSelected ? 0.30 : 0.18), color.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing,
                )
            }
            .background(isSelected ? Theme.color.surfaceAlt : Theme.color.ground)
            .overlay(alignment: .leading) {
                Rectangle().fill(color).frame(width: 4)
            }
            .overlay(alignment: .bottom) { Rule() }
            .contentShape(Rectangle())
            .onTapGesture {
                if onSelect(), !isReadOnly {
                    isEditing = true
                }
            }
            .popover(isPresented: $isEditing, arrowEdge: .leading) {
                BreakEditor(info: info) { updated in
                    var changed = entry
                    changed.kind = .break(updated)
                    onChange(changed)
                }
            }
            .contextMenu {
                Button("Edit Break…") { isEditing = true }
                    .disabled(isReadOnly)
                Button("Remove Break", role: .destructive, action: onRemove)
                    .disabled(isReadOnly)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(timing.map { "Break, \(info.label), \($0.totalText)" }
                ?? "Break, \(info.label)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAction(named: "Edit") { isEditing = true }
            .accessibilityIdentifier(AccessibilityID.setlistBreak)
        }
    }

    /// A break's label and optional intermission (R105, counted in the whole total only).
    struct BreakEditor: View {
        let info: SetlistBreak
        let onSave: (SetlistBreak) -> Void
        @Environment(\.dismiss) private var dismiss
        @State private var label = ""
        @State private var length = ""

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Break")
                    .font(Theme.font.sectionHeading)
                    .foregroundStyle(Theme.color.ink)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Label").font(Theme.font.label).foregroundStyle(Theme.color.muted)
                        TextField("Label", text: $label, prompt: Text("Set 2"))
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier(AccessibilityID.breakLabelField)
                    }
                    GridRow {
                        Text("Break").font(Theme.font.label).foregroundStyle(Theme.color.muted)
                        HStack {
                            TextField("Length", text: $length, prompt: Text("15:00"))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .accessibilityIdentifier(AccessibilityID.breakLengthField)
                            Text("in the whole total only")
                                .font(.callout)
                                .foregroundStyle(Theme.color.muted)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.segueSecondary)
                    Button("Save", action: save)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.seguePrimary)
                        .disabled(!isLengthValid)
                }
            }
            .padding(16)
            .frame(width: 320)
            .onAppear {
                label = info.label
                length = info.length.map { SetlistTiming.format($0) } ?? ""
            }
        }

        private var isLengthValid: Bool {
            length.trimmingCharacters(in: .whitespaces).isEmpty || DurationText.parse(length) != nil
        }

        private func save() {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            onSave(SetlistBreak(
                label: trimmed.isEmpty ? info.label : trimmed,
                length: DurationText.parse(length),
            ))
            dismiss()
        }
    }
#endif
