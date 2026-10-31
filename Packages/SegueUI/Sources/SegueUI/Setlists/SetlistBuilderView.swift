#if os(macOS)
    import Library
    import Setlists
    import Shows
    import SwiftUI
    import TipKit

    /// The setlist builder (R84, direction C). Pick: the library checklist on the left and
    /// the set on the right; Arrange: the set alone, full width. The header holds the name,
    /// details, Rehearse / Start show and the timeline strip (one coloured region per part,
    /// unknown times hatched, breaks as gaps, the target as a line).
    struct SetlistBuilderView: View {
        @Environment(\.openGuide) private var openGuide
        let setlist: Setlist
        let model: SetlistsViewModel
        let library: LibraryViewModel
        /// Show in Finder for this setlist's file.
        var onReveal: () -> Void = {}
        /// Start show (`.gig`) or Rehearse (`.rehearsal`).
        let onStart: (Setlist, ShowKind) -> Void
        /// GigModeTip's "Open Settings": Settings on the Live pane.
        var onOpenLiveSettings: () -> Void = {}
        @State private var naming: SetlistNameSheet.Purpose?
        @State private var isEditingDetails = false
        @AppStorage(ChangeoverSetting.defaultsKey) private var defaultChangeover = 0
        /// The set assistant's command bar state (P3-7), made on first appearance.
        @State private var assistant: SetAssistantModel?
        /// The window's content size: Arrange Sections fits itself to it.
        @State private var windowSize: CGSize?
        @Environment(\.smartFilterList) private var smartFilters

        var body: some View {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    if model.builderMode == .pick {
                        BuilderLibraryColumn(
                            setlist: setlist,
                            model: model,
                            library: library,
                            onToggle: { songID in
                                Task { await model.toggle(songID, in: setlist.id) }
                            },
                            onTickAll: { songs in
                                Task { await model.tickAll(songs, in: setlist.id) }
                            },
                        )
                        // Layout a gives the library 520 of 1440pt; narrower windows keep the
                        // set column the wider of the two.
                        .frame(width: min(max(proxy.size.width * 0.36, 280), 520))
                        Rule(axis: .vertical)
                    }
                    VStack(spacing: 0) {
                        // Never while performing (TipKit keeps an inline tip on screen
                        // when its rule parameters change under it).
                        if !library.isPerforming {
                            TipView(GigModeTip()) { action in
                                if action.id == GigModeTip.openSettingsAction {
                                    onOpenLiveSettings()
                                }
                                GuideTipAction.handle(
                                    action, page: GigModeTip.guidePage, openGuide: openGuide,
                                )
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                        }
                        header
                        if model.builderMode == .arrange, let assistant {
                            Rule()
                            AssistantCommandBar(
                                setlist: setlist,
                                model: assistant,
                                library: library,
                            )
                        }
                        Rule()
                        SetEntriesList(
                            setlist: setlist,
                            model: model,
                            library: library,
                            breakdowns: assistant?.breakdowns(for: setlist) ?? [:],
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .background(Theme.color.ground)
                }
            }
            .navigationTitle(setlist.name)
            .toolbar {
                ToolbarItem(placement: .principal) { modePicker }
                menu
            }
            .onChange(of: smartFilters, initial: true) {
                if assistant == nil {
                    assistant = SetAssistantModel(setlists: model, library: library)
                }
                assistant?.smartFilters = smartFilters
            }
            .onChange(of: setlist.entries.isEmpty, initial: true) { _, isEmpty in
                SegueTips.openSetlistHasEntries = !isEmpty
            }
            .environment(\.slotArrangementActions, SlotArrangementActions(
                open: { [model, setlist] item in model.openArrangement(item, in: setlist.id) },
            ))
            .sheet(item: Binding(
                get: { model.arranging.flatMap { $0.setlist == setlist.id ? $0 : nil } },
                set: { model.arranging = $0 },
            )) { slot in
                ArrangementEditorSheet(
                    slot: slot,
                    model: model,
                    library: library,
                    windowSize: windowSize,
                )
            }
            .windowContentSize($windowSize)
            .sheet(item: $naming) { purpose in
                SetlistNameSheet(purpose: purpose) { name in
                    Task { await model.rename(setlist.id, to: name) }
                }
            }
        }

        private var isReadOnly: Bool {
            setlist.readOnly != nil
        }

        /// Pick | Arrange (⌘1 / ⌘2, Setlist menu).
        private var modePicker: some View {
            Picker("Mode", selection: Binding(
                get: { model.builderMode },
                set: { model.builderMode = $0 },
            )) {
                ForEach(BuilderMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Pick songs from the library (\(MenuShortcuts.pickSongs.displayText)) or "
                + "arrange the set (\(MenuShortcuts.arrangeSet.displayText))")
            .accessibilityIdentifier(AccessibilityID.builderMode)
        }

        /// Name and details with Rehearse / Start show (stacked when narrow), then the
        /// timeline strip across the whole column.
        private var header: some View {
            let timing = SetlistTiming(
                setlist: setlist,
                library: library,
                defaultChangeover: defaultChangeover,
            )
            return VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 24) {
                        nameBlock
                        Spacer(minLength: 0)
                        startButtons
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        nameBlock
                        startButtons
                    }
                }
                SetlistTimelineView(timing: timing, setlist: setlist, library: library)
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
                    .help("Run the set on stage to time each song, no gig log entry "
                        + "(\(MenuShortcuts.rehearse.displayText))")
                    .accessibilityIdentifier(AccessibilityID.setlistRehearse)
                Button("Start show") { onStart(setlist, .gig) }
                    .buttonStyle(.seguePrimary)
                    .popoverTip(StartShowTip()) { action in
                        GuideTipAction.handle(
                            action,
                            page: StartShowTip.guidePage,
                            openGuide: openGuide,
                        )
                    }
                    .help("Perform this setlist on stage (\(MenuShortcuts.startShow.displayText))")
                    .accessibilityIdentifier(AccessibilityID.setlistStartShow)
            }
            .controlSize(.large)
            .fixedSize()
            .disabled(setlist.songCount == 0)
        }

        /// "The Anchor · Fri 23 Oct 2026", or a prompt to add them. Click to edit.
        private var detailsLine: some View {
            let parts = [setlist.venue, setlist.date?.displayText].compactMap(\.self)
            return Button {
                isEditingDetails = true
            } label: {
                Text(parts.isEmpty ? "Add details…" : parts.joined(separator: " · "))
                    .font(Theme.font.body)
                    .foregroundStyle(Theme.color.muted)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .disabled(isReadOnly)
            .help("Edit venue, date, target length and changeover")
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
                        onReveal: onReveal,
                    )
                }
                .help("Rename, duplicate, show in Finder or move this setlist to the Trash")
                // Icon-only in the toolbar: name it for VoiceOver and Voice Control.
                .accessibilityLabel("Setlist")
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
        let onReveal: () -> Void

        var body: some View {
            Button("Rename…", action: onRename)
                .disabled(setlist.readOnly != nil)
                .accessibilityIdentifier(AccessibilityID.setlistRenameAction)
            if let onDetails {
                Button("Details…", action: onDetails)
                    .disabled(setlist.readOnly != nil)
                    .accessibilityIdentifier(AccessibilityID.setlistDetailsAction)
            }
            Button("Duplicate") {
                Task { await model.duplicate(setlist.id) }
            }
            .accessibilityIdentifier(AccessibilityID.setlistDuplicateAction)
            Button("Show in Finder", action: onReveal)
                .accessibilityIdentifier(AccessibilityID.setlistRevealAction)
            Divider()
            // No confirmation: the file goes to the Trash and Edit > Undo brings it back (A23).
            Button("Move to Trash", role: .destructive) {
                Task { await model.delete(setlist.id) }
            }
            .accessibilityIdentifier(AccessibilityID.setlistDeleteAction)
        }
    }
#endif
