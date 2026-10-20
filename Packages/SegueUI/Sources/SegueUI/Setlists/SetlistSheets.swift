#if os(macOS)
    import Setlists
    import Support
    import SwiftUI

    func songCount(_ count: Int) -> String {
        count == 1 ? "1 song" : "\(count) songs"
    }

    /// Names a new setlist or renames one.
    struct SetlistNameSheet: View {
        enum Purpose: Identifiable, Hashable {
            case create
            case rename(String)

            var id: Self {
                self
            }
        }

        let purpose: Purpose
        var onCommit: (String) -> Void
        @Environment(\.dismiss) private var dismiss
        @State private var name = ""

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                Text(isCreating ? "New Setlist" : "Rename Setlist")
                    .font(Theme.font.sectionHeading)
                    .foregroundStyle(Theme.color.ink)
                TextField("Name", text: $name, prompt: Text("Friday at the Blue Room"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                    .onSubmit(commit)
                    .accessibilityIdentifier(isCreating
                        ? AccessibilityID.newSetlistName
                        : AccessibilityID.setlistNameField)
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.segueSecondary)
                    Button(isCreating ? "Create" : "Rename", action: commit)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.seguePrimary)
                        .disabled(trimmedName.isEmpty)
                        .accessibilityIdentifier(isCreating
                            ? AccessibilityID.newSetlistCreate
                            : AccessibilityID.setlistNameSave)
                }
            }
            .padding(20)
            .onAppear {
                if case let .rename(current) = purpose {
                    name = current
                }
            }
        }

        private var isCreating: Bool {
            purpose == .create
        }

        private var trimmedName: String {
            name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private func commit() {
            guard !trimmedName.isEmpty else { return }
            onCommit(trimmedName)
            dismiss()
        }
    }

    /// A setlist's details (the builder header's details line): venue, date, target length
    /// and the changeover between songs (R86; "Default" follows Settings > General).
    struct SetlistDetailsEditor: View {
        let setlist: Setlist
        let onSave: (SetlistDetails) -> Void
        @Environment(\.dismiss) private var dismiss
        @AppStorage(ChangeoverSetting.defaultsKey) private var defaultChangeover = 0
        @State private var venue = ""
        @State private var hasDate = false
        @State private var date = Date.now
        @State private var target = ""
        /// -1 = the app-wide default.
        @State private var changeover = -1

        /// The changeovers the picker offers, in seconds.
        static let changeoverChoices = [0, 10, 15, 20, 30, 45, 60, 90, 120]

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                Text("Details")
                    .font(Theme.font.sectionHeading)
                    .foregroundStyle(Theme.color.ink)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        label("Venue")
                        TextField("Venue", text: $venue, prompt: Text("The Anchor"))
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier(AccessibilityID.detailsVenue)
                    }
                    GridRow {
                        label("Date")
                        HStack {
                            Toggle("Set a date", isOn: $hasDate)
                                .labelsHidden()
                                .accessibilityIdentifier(AccessibilityID.detailsHasDate)
                            DatePicker("Date", selection: $date, displayedComponents: .date)
                                .labelsHidden()
                                .disabled(!hasDate)
                                .accessibilityIdentifier(AccessibilityID.detailsDate)
                        }
                    }
                    GridRow {
                        label("Target")
                        HStack {
                            TextField("Target", text: $target, prompt: Text("45:00"))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                                .accessibilityIdentifier(AccessibilityID.detailsTarget)
                            Text(targetHint)
                                .font(.callout)
                                .foregroundStyle(Theme.color.muted)
                        }
                    }
                    GridRow {
                        label("Changeover")
                        Picker("Changeover", selection: $changeover) {
                            Text("Default (\(defaultText))").tag(-1)
                            Divider()
                            ForEach(choices, id: \.self) { seconds in
                                Text(SetlistTiming.formatChangeover(TimeInterval(seconds)))
                                    .tag(seconds)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .help("Added after every song but the last of each part")
                        .accessibilityIdentifier(AccessibilityID.detailsChangeover)
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
                        .disabled(!isTargetValid)
                        .accessibilityIdentifier(AccessibilityID.detailsSave)
                }
            }
            .padding(16)
            .frame(width: 360)
            .onAppear(perform: load)
        }

        private var isTargetValid: Bool {
            target.trimmingCharacters(in: .whitespaces).isEmpty
                || DurationText.parse(target) != nil
        }

        private var targetHint: String {
            if target.trimmingCharacters(in: .whitespaces).isEmpty {
                return "minutes, or m:ss"
            }
            return DurationText.parse(target).map { SetlistTiming.format($0) }
                ?? "Type minutes (45) or m:ss"
        }

        private var defaultText: String {
            SetlistTiming
                .formatChangeover(TimeInterval(ChangeoverSetting.clamped(defaultChangeover)))
        }

        /// The choices, plus the setlist's own value when it is not one of them.
        private var choices: [Int] {
            let own = setlist.changeoverSeconds.map { [$0] } ?? []
            return Array(Set(Self.changeoverChoices + own)).sorted()
        }

        private func label(_ text: String) -> some View {
            Text(text)
                .font(Theme.font.label)
                .foregroundStyle(Theme.color.muted)
        }

        private func load() {
            venue = setlist.venue ?? ""
            hasDate = setlist.date != nil
            date = setlist.date?.date ?? .now
            target = setlist.targetDuration.map { SetlistTiming.format($0) } ?? ""
            changeover = setlist.changeoverSeconds ?? -1
        }

        private func save() {
            let trimmed = venue.trimmingCharacters(in: .whitespacesAndNewlines)
            onSave(SetlistDetails(
                venue: trimmed.isEmpty ? nil : trimmed,
                date: hasDate ? CalendarDay(date) : nil,
                targetDuration: DurationText.parse(target),
                changeoverSeconds: changeover < 0 ? nil : changeover,
            ))
            dismiss()
        }
    }
#endif
