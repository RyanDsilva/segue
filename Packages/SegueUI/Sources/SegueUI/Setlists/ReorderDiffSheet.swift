// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit D; presented by C
// (`liveModePresentations`).

#if os(macOS)
    import Setlists
    import Shows
    import SwiftUI

    /// The show-end review: planned vs performed order side by side, moved rows and inserted
    /// songs (requests, play now, insert next) marked, each inserted row with an "Add to
    /// setlist" checkbox (checked by default: decisions.md, phase 2 build rulings), except a
    /// song already in the set, which says so instead (a song is in a setlist once). Two
    /// buttons, **Save to Setlist** and **Discard**, neither preselected as the default
    /// action (decisions.md).
    public struct ReorderDiffSheet: View {
        let diff: ReorderDiff
        /// Called with the inserted item IDs the user ticked.
        let onSave: (Set<ShowItemID>) -> Void
        let onDiscard: () -> Void
        /// Non-nil when the setlist can no longer be saved (deleted or read-only during the
        /// show): Save is disabled and this says why; only Discard is offered.
        let saveDisabledReason: String?
        /// Why the last Save failed (the review stays up so it can be retried).
        let saveFailure: String?
        /// The setlist was edited after the show started: Save merges into it as it is now.
        let setlistChanged: Bool
        /// The window the sheet is presented on: the sheet never outgrows it (the rows scroll
        /// instead). Nil = no limit beyond the defaults.
        let available: CGSize?
        /// An answer is being written: Save and Discard are disabled so a double click
        /// answers once (R154).
        let isBusy: Bool
        @State private var included: Set<ShowItemID>

        public init(
            diff: ReorderDiff,
            onSave: @escaping (Set<ShowItemID>) -> Void,
            onDiscard: @escaping () -> Void,
            saveDisabledReason: String? = nil,
            saveFailure: String? = nil,
            setlistChanged: Bool = false,
            available: CGSize? = nil,
            isBusy: Bool = false,
        ) {
            self.diff = diff
            self.onSave = onSave
            self.onDiscard = onDiscard
            self.saveDisabledReason = saveDisabledReason
            self.saveFailure = saveFailure
            self.setlistChanged = setlistChanged
            self.available = available
            self.isBusy = isBusy
            _included = State(initialValue: diff.defaultIncluded)
        }

        /// Room for the header and the buttons around the scrolling rows.
        private static let chromeHeight: CGFloat = 210

        private var width: CGFloat {
            guard let available, available.width > 0 else { return 720 }
            return max(420, min(720, available.width - 48))
        }

        /// The rows' height: all of them up to 460pt, less when the window is short.
        private var rowsMaxHeight: CGFloat {
            guard let available, available.height > 0 else { return 460 }
            return max(120, min(460, available.height - 48 - Self.chromeHeight))
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Save the played order to “\(diff.setlistName)”?", bundle: #bundle)
                        .font(Theme.font.sectionHeading)
                        .foregroundStyle(Theme.color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(explanation)
                        .font(Theme.font.body)
                        .foregroundStyle(Theme.color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let warning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                            .font(Theme.font.body)
                            .foregroundStyle(Theme.color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(AccessibilityID.reorderWarning)
                    }
                }
                .padding(20)
                Rule()
                ScrollViewReader { proxy in
                    ScrollView {
                        HStack(alignment: .top, spacing: 0) {
                            column("Planned") { plannedRows }
                            Rule(axis: .vertical)
                            column("As played") { performedRows }
                        }
                    }
                    .onAppear {
                        // In a short window the changes may be below the fold: show the first.
                        if let first = firstChange {
                            proxy.scrollTo(Self.performedAnchor(first), anchor: .center)
                        }
                    }
                }
                .frame(minHeight: min(220, rowsMaxHeight), maxHeight: rowsMaxHeight)
                Rule()
                buttons
            }
            .frame(width: width)
            .background(Theme.color.ground)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.reorderSheet)
        }

        /// The scroll anchor of a performed row (planned rows share the item IDs).
        private static func performedAnchor(_ id: ShowItemID) -> String {
            "played-\(id)"
        }

        /// The first performed row that moved or was inserted.
        private var firstChange: ShowItemID? {
            diff.performed.first { $0.change != .unchanged }?.id
        }

        /// A failed save, else the "edited during the show" warning.
        private var warning: String? {
            if let saveFailure {
                return saveFailure
            }
            guard setlistChanged, saveDisabledReason == nil else { return nil }
            return "“\(diff.setlistName)” was edited during the show. Save merges the played "
                + "order into it as it is now, keeping those edits."
        }

        private var explanation: String {
            if let saveDisabledReason {
                return saveDisabledReason
            }
            return "The set ran in a different order than planned. Save it to the setlist, "
                + "or discard it and keep the setlist as it was."
        }

        private func column(
            _ title: String,
            @ViewBuilder rows: () -> some View,
        ) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.muted)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                rows()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var titles: [ShowItemID: String] {
            Dictionary(diff.performed.map { ($0.item.itemId, $0.item.title) }) { first, _ in first }
        }

        private var plannedRows: some View {
            ForEach(Array(diff.planned.enumerated()), id: \.element.itemId) { offset, entry in
                DiffRow(number: offset + 1, title: titles[entry.itemId] ?? "Unknown song") {
                    EmptyView()
                }
                .accessibilityIdentifier(AccessibilityID.reorderPlannedRow)
            }
        }

        private var performedRows: some View {
            ForEach(Array(diff.performed.enumerated()), id: \.element.id) { offset, row in
                DiffRow(
                    number: offset + 1,
                    title: row.item.title,
                    isDimmed: row.item.state == .skipped,
                ) {
                    marker(row)
                }
                .id(Self.performedAnchor(row.id))
                .accessibilityIdentifier(AccessibilityID.reorderPerformedRow)
            }
        }

        @ViewBuilder
        private func marker(_ row: ReorderDiff.Row) -> some View {
            switch row.change {
            case .unchanged:
                if row.item.state == .skipped {
                    note("skipped")
                }
            case let .moved(fromPosition):
                // `fromPosition` is the 0-based index in the plan.
                note("moved from #\(fromPosition + 1)")
            case let .inserted(origin):
                KeyChip(key: origin == .request ? "Request" : "Added")
                if diff.repeatedItemIds.contains(row.item.itemId) {
                    note("already in set")
                        .help(uiString("""
                        A song can be in a setlist only once, so Save leaves this out.
                        """))
                        .accessibilityIdentifier(AccessibilityID.reorderAlreadyInSet)
                } else {
                    includeToggle(row)
                }
            }
        }

        private func includeToggle(_ row: ReorderDiff.Row) -> some View {
            Toggle(isOn: includeBinding(row.item.itemId)) {
                Text("Add to setlist", bundle: #bundle)
            }
            .toggleStyle(.checkbox)
            .font(SchibstedGrotesk.medium.font(size: 13))
            .fixedSize()
            .disabled(saveDisabledReason != nil)
            .help(uiString("Add this song to the setlist at this position"))
            .accessibilityIdentifier(AccessibilityID.reorderInclude)
        }

        private func note(_ text: String) -> some View {
            Text(text)
                .font(SchibstedGrotesk.medium.font(size: 13))
                .foregroundStyle(Theme.color.muted)
        }

        private func includeBinding(_ id: ShowItemID) -> Binding<Bool> {
            Binding(
                get: { included.contains(id) },
                set: { isOn in
                    if isOn {
                        included.insert(id)
                    } else {
                        included.remove(id)
                    }
                },
            )
        }

        private var buttons: some View {
            HStack(spacing: 8) {
                Spacer()
                // Neither button is the default action: the choice is always deliberate.
                Button(uiString("Discard"), action: onDiscard)
                    .buttonStyle(.segueSecondary)
                    .disabled(isBusy)
                    .accessibilityIdentifier(AccessibilityID.reorderDiscard)
                Button(uiString("Save to Setlist")) { onSave(included) }
                    .buttonStyle(.segueSecondary)
                    .disabled(saveDisabledReason != nil || isBusy)
                    .accessibilityIdentifier(AccessibilityID.reorderSave)
            }
            .controlSize(.large)
            .padding(16)
        }
    }

    /// "3  Harbour Lights        moved from #5".
    private struct DiffRow<Marker: View>: View {
        let number: Int
        let title: String
        var isDimmed = false
        @ViewBuilder let marker: () -> Marker

        var body: some View {
            HStack(spacing: 8) {
                Text(verbatim: "\(number)")
                    .font(SchibstedGrotesk.medium.font(size: 14))
                    .foregroundStyle(Theme.color.muted)
                    .frame(width: 24, alignment: .leading)
                Text(title)
                    .font(SchibstedGrotesk.semiBold.font(size: 15))
                    .foregroundStyle(Theme.color.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                marker()
            }
            .opacity(isDimmed ? 0.55 : 1)
            .padding(.horizontal, 20)
            .frame(minHeight: 36)
            .overlay(alignment: .bottom) { Rule() }
            .accessibilityElement(children: .contain)
        }
    }
#endif
