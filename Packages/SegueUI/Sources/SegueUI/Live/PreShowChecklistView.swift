#if os(macOS)
    import Shows
    import SwiftUI

    /// The pre-show checklist sheet (see `PreShowChecklist`).
    struct PreShowChecklistView: View {
        let checklist: PreShowChecklist

        private var noun: String {
            checklist.kind == .gig ? "Show" : "Rehearsal"
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Before you start")
                        .font(Theme.font.sectionHeading)
                        .foregroundStyle(Theme.color.ink)
                    Text(subtitle)
                        .font(Theme.font.body)
                        .foregroundStyle(Theme.color.muted)
                }
                if !checklist.missingPositions.isEmpty {
                    missingWarning
                }
                if !checklist.visibleRows.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(checklist.visibleRows, id: \.self) { item in
                            row(item)
                            if item != checklist.visibleRows.last {
                                Rectangle().fill(Theme.color.line).frame(height: 1)
                            }
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.color.line, lineWidth: 1)
                    }
                }
                HStack(spacing: 10) {
                    Spacer()
                    Button("Cancel") { checklist.answer(false) }
                        .buttonStyle(.segueSecondary)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier(AccessibilityID.checklistCancel)
                    Button("Start \(noun)") { checklist.answer(true) }
                        .buttonStyle(.seguePrimary)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier(AccessibilityID.checklistStart)
                }
                .controlSize(.large)
            }
            .padding(24)
            .frame(width: 540)
            .background(Theme.color.ground)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.checklist)
        }

        private var subtitle: String {
            let count = checklist.performableCount
            let songs = count == 1 ? "1 song" : "\(count) songs"
            return "\(checklist.setlistName)  ·  \(songs)"
        }

        private var missingWarning: some View {
            let positions = checklist.missingPositions.map { "#\($0)" }.formatted(.list(type: .and))
            let count = checklist.missingPositions.count
            let lead = count == 1 ? "1 song is missing" : "\(count) songs are missing"
            return HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.color.cueText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(lead) and will be left out")
                        .font(SchibstedGrotesk.semiBold.font(size: 15))
                        .foregroundStyle(Theme.color.ink)
                    Text("Setlist \(count == 1 ? "entry" : "entries") \(positions) "
                        + "\(count == 1 ? "is" : "are") no longer in the library folder.")
                        .font(Theme.font.label)
                        .foregroundStyle(Theme.color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.color.surfaceAlt),
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.checklistMissing)
        }

        private func row(_ item: ChecklistItem) -> some View {
            let done = checklist.isDone(item)
            return HStack(alignment: .center, spacing: 12) {
                ZStack {
                    if done {
                        Circle().fill(Theme.color.ink)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.color.ground)
                    } else {
                        Circle().strokeBorder(Theme.color.muted, lineWidth: 2)
                    }
                }
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(item))
                        .font(SchibstedGrotesk.semiBold.font(size: 15))
                        .foregroundStyle(Theme.color.ink)
                    Text(detail(item))
                        .font(SchibstedGrotesk.medium.font(size: 13))
                        .foregroundStyle(Theme.color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                rowButtons(item, done: done)
                Menu {
                    Button("Hide for This \(noun)") { checklist.dismissed.insert(item) }
                    Button("Don’t Show Again") { checklist.hideForGood(item) }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Theme.color.muted)
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Options for \(title(item))")
            }
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.checklistRow)
            .accessibilityValue(done ? "done" : "not done")
            .accessibilityLabel(title(item))
        }

        /// The row's own buttons: Done / Undo on the brightness reminder, and the Focus
        /// row's Retry and Done.
        @ViewBuilder private func rowButtons(_ item: ChecklistItem, done: Bool) -> some View {
            switch item {
            case .brightness:
                Button(done ? "Undo" : "Done") { checklist.brightnessConfirmed.toggle() }
                    .buttonStyle(.segueSecondary)
            case .focus:
                focusButtons
            case .charger:
                EmptyView()
            }
        }

        /// Retry on an observed failure; Done (Undo once pressed) when the result is unknown
        /// or a failure, the manual fallback of R35.
        @ViewBuilder private var focusButtons: some View {
            if checklist.offersFocusRetry {
                Button("Retry") { checklist.retryFocusShortcut() }
                    .buttonStyle(.segueSecondary)
                    .accessibilityIdentifier(AccessibilityID.checklistFocusRetry)
            }
            if checklist.offersFocusDone {
                Button(checklist.focusConfirmedByPerformer ? "Undo" : "Done") {
                    checklist.focusConfirmedByPerformer.toggle()
                }
                .buttonStyle(.segueSecondary)
                .accessibilityIdentifier(AccessibilityID.checklistFocusDone)
            }
        }

        private func title(_ item: ChecklistItem) -> String {
            switch item {
            case .focus: "Focus on"
            case .charger: "Charger connected"
            case .brightness: "Screen brightness up"
            }
        }

        private func detail(_ item: ChecklistItem) -> String {
            switch item {
            case .focus: focusDetail
            case .charger:
                switch checklist.charger {
                case true?: "Running on the power adapter."
                case false?: "Running on battery. Plug in for a long set."
                case nil: "The power source could not be read."
                }
            case .brightness: "Turn the screen up so the chart reads from a distance."
            }
        }

        private var focusDetail: String {
            switch checklist.focus {
            case .notConfigured: "No start Shortcut is set. Add one in Settings > Live."
            case .notRun: "Shortcuts are off for rehearsals (Settings > Live)."
            case let .running(name): "Running “\(name)”…"
            case let .ran(name): "“\(name)” ran."
            case let .unknown(name):
                "Asked Shortcuts to run “\(name)”; couldn’t confirm it finished."
            case let .failed(name, message): "“\(name)” failed: \(message)."
            }
        }
    }
#endif
