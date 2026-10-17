#if os(macOS)
    import Library
    import Setlists
    import Shows
    import SwiftUI

    /// The setlist builder (layout a, "library to set"): the library column on the left,
    /// the set on the right with start times and the running total against the target.
    struct SetlistBuilderView: View {
        let setlist: Setlist
        let model: SetlistsViewModel
        let library: LibraryViewModel
        /// Start show (`.gig`) or Rehearse (`.rehearsal`).
        let onStart: (Setlist, ShowKind) -> Void
        @State private var naming: SetlistNameSheet.Purpose?
        @State private var isEditingDetails = false
        @State private var isConfirmingDelete = false

        var body: some View {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    BuilderLibraryColumn(setlist: setlist, library: library) { songID in
                        Task { await model.insert([songID], into: setlist.id, at: nil) }
                    }
                    // Layout a gives the library 520 of 1440pt; narrower windows keep the
                    // set column the wider of the two.
                    .frame(width: min(max(proxy.size.width * 0.36, 280), 520))
                    Rule(axis: .vertical)
                    VStack(spacing: 0) {
                        header
                        Rule()
                        SetEntriesList(setlist: setlist, model: model, library: library)
                    }
                    .frame(maxWidth: .infinity)
                    .background(Theme.color.ground)
                }
            }
            .navigationTitle(setlist.name)
            .toolbar { menu }
            .sheet(item: $naming) { purpose in
                SetlistNameSheet(purpose: purpose) { name in
                    Task { await model.rename(setlist.id, to: name) }
                }
            }
            .confirmationDialog(
                "Delete “\(setlist.name)”?",
                isPresented: $isConfirmingDelete,
            ) {
                Button("Delete Setlist", role: .destructive) {
                    Task { await model.delete(setlist.id) }
                }
                .accessibilityIdentifier(AccessibilityID.setlistDeleteAction + ".confirm")
            } message: {
                Text("Its file is deleted from the library folder. Gig log entries of shows "
                    + "that ran it keep their own copy.")
            }
        }

        private var isReadOnly: Bool {
            setlist.readOnly != nil
        }

        /// Name and details, the running total, then Rehearse / Start show; the total moves
        /// to its own line when the set column is narrow.
        private var header: some View {
            let timing = SetlistTiming(setlist: setlist, songs: library.song(id:))
            return ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 24) {
                    nameBlock
                    Spacer(minLength: 0)
                    SetlistTotalView(timing: timing)
                        .frame(width: 300)
                    startButtons
                }
                VStack(alignment: .leading, spacing: 16) {
                    nameBlock
                    HStack(alignment: .center, spacing: 24) {
                        SetlistTotalView(timing: timing)
                            .frame(minWidth: 240, maxWidth: 360)
                        Spacer(minLength: 0)
                        startButtons
                    }
                }
                VStack(alignment: .leading, spacing: 16) {
                    nameBlock
                    SetlistTotalView(timing: timing)
                        .frame(maxWidth: 420)
                    startButtons
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
        }

        private var nameBlock: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(isReadOnly ? "Setlist · read-only" : "Setlist")
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.muted)
                Text(setlist.name)
                    .font(SchibstedGrotesk.extraBold.font(size: 30))
                    .tracking(Theme.tracking.title * 30)
                    .foregroundStyle(Theme.color.ink)
                    .lineLimit(1)
                    .accessibilityIdentifier(AccessibilityID.setlistTitle)
                detailsLine
            }
            .layoutPriority(1)
        }

        private var startButtons: some View {
            HStack(spacing: 8) {
                Button("Rehearse") { onStart(setlist, .rehearsal) }
                    .buttonStyle(.segueSecondary)
                    .help("Run the set on stage to time each song (no gig log entry)")
                    .accessibilityIdentifier(AccessibilityID.setlistRehearse)
                Button("Start show") { onStart(setlist, .gig) }
                    .buttonStyle(.seguePrimary)
                    .help("Perform this setlist on stage")
                    .accessibilityIdentifier(AccessibilityID.setlistStartShow)
            }
            .controlSize(.large)
            .fixedSize()
            .disabled(setlist.entries.isEmpty)
        }

        /// "The Anchor · Fri 23 Oct 2026", or a prompt to add them. Click to edit.
        private var detailsLine: some View {
            let parts = [setlist.venue, setlist.date?.displayText].compactMap(\.self)
            return Button {
                isEditingDetails = true
            } label: {
                Text(parts.isEmpty ? "Add venue, date and target…" : parts.joined(separator: " · "))
                    .font(Theme.font.body)
                    .foregroundStyle(Theme.color.muted)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .disabled(isReadOnly)
            .help("Edit venue, date and target length")
            .accessibilityIdentifier(AccessibilityID.setlistDetailsLine)
            .popover(isPresented: $isEditingDetails, arrowEdge: .bottom) {
                SetlistDetailsEditor(setlist: setlist) { details in
                    Task { await model.updateDetails(details, of: setlist.id) }
                }
            }
        }

        @ToolbarContentBuilder private var menu: some ToolbarContent {
            ToolbarSpacer(.flexible)
            ToolbarItem(placement: .automatic) {
                Menu("Setlist", systemImage: "ellipsis") {
                    SetlistActions(
                        setlist: setlist,
                        model: model,
                        onRename: { naming = .rename(setlist.name) },
                        onDetails: { isEditingDetails = true },
                        onDelete: { isConfirmingDelete = true },
                    )
                }
                .help("Rename, duplicate or delete this setlist")
                .accessibilityIdentifier(AccessibilityID.setlistMenu)
            }
        }
    }

    /// Rename / Details / Duplicate / Delete, shared by the builder's menu and the sidebar's
    /// context menu.
    struct SetlistActions: View {
        let setlist: Setlist
        let model: SetlistsViewModel
        let onRename: () -> Void
        var onDetails: (() -> Void)?
        let onDelete: () -> Void

        var body: some View {
            Button("Rename…", action: onRename)
                .disabled(setlist.readOnly != nil)
                .accessibilityIdentifier(AccessibilityID.setlistRenameAction)
            if let onDetails {
                Button("Venue, Date and Target…", action: onDetails)
                    .disabled(setlist.readOnly != nil)
                    .accessibilityIdentifier(AccessibilityID.setlistDetailsAction)
            }
            Button("Duplicate") {
                Task { await model.duplicate(setlist.id) }
            }
            .accessibilityIdentifier(AccessibilityID.setlistDuplicateAction)
            Divider()
            Button("Delete…", role: .destructive, action: onDelete)
                .accessibilityIdentifier(AccessibilityID.setlistDeleteAction)
        }
    }

    /// Running total vs target: "38:07   target 45:00" over a 6px bar.
    struct SetlistTotalView: View {
        let timing: SetlistTiming

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(timing.totalText)
                        .font(SchibstedGrotesk.bold.font(size: 14))
                        .fixedSize()
                        .foregroundStyle(Theme.color.ink)
                        .accessibilityIdentifier(AccessibilityID.setlistTotal)
                    Spacer(minLength: 8)
                    Text(targetText)
                        .font(SchibstedGrotesk.medium.font(size: 14))
                        .truncationMode(.head)
                        .foregroundStyle(Theme.color.muted)
                        .accessibilityIdentifier(AccessibilityID.setlistTarget)
                }
                .lineLimit(1)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.color.line)
                        Capsule()
                            .fill(Theme.color.ink)
                            .frame(width: proxy.size.width * min(timing.progress ?? 0, 1))
                    }
                }
                .frame(height: 6)
                .opacity(timing.target == nil ? 0.5 : 1)
                .accessibilityHidden(true)
            }
        }

        private var targetText: String {
            guard let target = timing.target else { return "no target" }
            let over = timing.total - target
            return over > 0
                ? "\(SetlistTiming.format(over)) over \(SetlistTiming.format(target))"
                : "target \(SetlistTiming.format(target))"
        }
    }
#endif
