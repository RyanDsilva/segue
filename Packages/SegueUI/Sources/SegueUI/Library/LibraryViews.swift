#if os(macOS)
    import Library
    import Setlists
    import SwiftUI
    import TipKit

    /// The Library destination (layout a, "three pane"): the song list column beside the
    /// selected song's preview (or its editor). The sidebar is the window's first pane.
    struct LibraryPane: View {
        let session: LibrarySession
        /// A file drag is over the list or the detail pane (and import is possible).
        @State private var isDropTargeted = false

        private var model: LibraryViewModel {
            session.library
        }

        var body: some View {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    SongListView(model: model, session: session)
                        .overlay { dropHighlight }
                        .importDrop(model: model, isTargeted: $isDropTargeted)
                        // Layout a gives the list 420 of 1440pt; small windows keep the
                        // preview (or editor) the wider pane.
                        .frame(width: min(max(proxy.size.width * 0.32, 290), 420))
                    Rule(axis: .vertical)
                    LibraryDetailView(model: model, session: session)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .importDrop(model: model, isTargeted: $isDropTargeted)
                }
            }
            .sheet(isPresented: Binding(
                get: { model.walkUpsSongID != nil },
                set: {
                    if !$0 {
                        model.walkUpsSongID = nil
                    }
                },
            )) {
                if let id = model.walkUpsSongID {
                    WalkUpsSheet(source: { model.walkUpsSource(songID: id) })
                        .environment(\.walkUpAudition, model.walkUpAudition(songID: id))
                }
            }
            .navigationTitle(model.scope.title)
            // The editor sets its own title; a song count under it would read as its own.
            .navigationSubtitle(model.editor == nil ? songCount(shownCount) : "")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await model.refresh() }
                    }
                    .help("Pick up changes made in other apps (⌘R)")
                    .accessibilityIdentifier(AccessibilityID.refreshLibrary)
                }
            }
        }
    }

    extension LibraryPane {
        /// The songs the list's scope holds (every song, or a smart filter's).
        var shownCount: Int {
            model.scope.isFiltered ? model.scoped(model.catalog).count : model.catalog.count
        }

        /// The drop target highlight on the list column (A25): a 2pt cue inset border and
        /// "Drop to import".
        @ViewBuilder var dropHighlight: some View {
            if isDropTargeted {
                ZStack(alignment: .bottom) {
                    Rectangle()
                        .strokeBorder(Theme.color.cue, lineWidth: 2)
                    Label("Drop to import", systemImage: "square.and.arrow.down")
                        .font(SchibstedGrotesk.semiBold.font(size: 13))
                        .foregroundStyle(Theme.color.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 16)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    extension View {
        /// Accepts dropped files and folders for import while import is possible; refused
        /// drops show no highlight.
        func importDrop(model: LibraryViewModel, isTargeted: Binding<Bool>) -> some View {
            dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(\.isFileURL)
                guard model.canImport, !files.isEmpty else { return false }
                Task { await model.importSongs(files) }
                return true
            } isTargeted: { targeted in
                isTargeted.wrappedValue = targeted && model.canImport
            }
        }
    }

    /// The song list column: search with typed filter tokens, filter chips, "New song",
    /// then one row per song (key chip, proficiency mark).
    struct SongListView: View {
        @Environment(\.openGuide) private var openGuide
        @Bindable var model: LibraryViewModel
        let session: LibrarySession
        @State private var isShowingLoadIssues = false

        var body: some View {
            VStack(spacing: 0) {
                header
                Rule()
                SelectableList(
                    items: model.results,
                    selection: $model.multiSelection,
                    allowsMultiple: true,
                ) { record in
                    SongRow(
                        record: record,
                        stats: model.playStats[record.id],
                        isSelected: model.listSelection == record.id,
                    )
                } menu: { record in
                    // A right-click inside a multi-selection adds the whole selection.
                    SongActions(
                        session: session,
                        songID: record.id,
                        selection: model.multiSelection.contains(record.id)
                            ? model.selectedSongs : [record.id],
                    )
                }
                .onChange(of: model.results.map(\.id)) { _, ids in
                    model.multiSelection.keep(only: ids)
                }
                .accessibilityIdentifier(AccessibilityID.songList)
                // ⌘V on the list (never a text field or the editor: they take Paste first)
                // opens the review sheet on the clipboard (R75); off during a show (R109).
                .onPasteCommand(of: [.plainText, .utf8PlainText]) { _ in pasteOnList() }
                // File > Move to Trash and Show in Finder act on this only while the list
                // itself has focus (never while typing in a field or the editor), so this is
                // a focused value, not a scene value.
                .focusedValue(\.focusedSongID, model.editor == nil ? model.listSelection : nil)
                .overlay { emptyState }
                .safeAreaInset(edge: .bottom, spacing: 0) { loadIssuesFooter }
            }
            .background(Theme.color.ground)
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: 10) {
                SmartFilterListHeader(session: session)
                HStack(spacing: 8) {
                    SearchField(
                        text: $model.query,
                        prompt: "Search or filter",
                        accessibilityIdentifier: AccessibilityID.librarySearch,
                    )
                    .popoverTip(SearchAnyLineTip()) { action in
                        GuideTipAction.handle(
                            action,
                            page: SearchAnyLineTip.guidePage,
                            openGuide: openGuide,
                        )
                    }
                    Button("New song") { model.beginNewSongFlow() }
                        .buttonStyle(.seguePrimary)
                        .help(model.isPerforming ? "New Song: starts blank during a show (⌘N)"
                            : "Paste or type a new song (⌘N)")
                        .popoverTip(PasteSongTip()) { action in
                            GuideTipAction.handle(
                                action,
                                page: PasteSongTip.guidePage,
                                openGuide: openGuide,
                            )
                        }
                        .accessibilityIdentifier(AccessibilityID.newSong)
                }
                FilterChipsBar(state: $model.filterState, tags: model.tags)
                LibrarySearchChips(model: model)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
        }

        /// ⌘V on the song list: the review sheet on the clipboard; during a show, the reason.
        private func pasteOnList() {
            guard model.editor == nil else { return }
            if let reason = model.pasteUnavailableReason {
                model.flash(reason)
                return
            }
            guard let text = AppModel.clipboardText(), !text.isEmpty else {
                model.flash("The clipboard has no text to paste")
                return
            }
            model.beginPasteReview(text: text, source: .listPaste)
        }

        /// The empty library's Paste a Song.
        private func pasteFromEmptyState() {
            guard let text = AppModel.clipboardText(), !text.isEmpty else {
                model.beginNewSongFlow()
                return
            }
            model.beginPasteReview(text: text, source: .emptyState)
        }

        @ViewBuilder private var loadIssuesFooter: some View {
            if !model.loadIssues.isEmpty {
                let count = model.loadIssues.count
                Button {
                    isShowingLoadIssues = true
                } label: {
                    Label(
                        count == 1
                            ? "1 song file could not be loaded"
                            : "\(count) song files could not be loaded",
                        systemImage: "exclamationmark.triangle.fill",
                    )
                    .symbolRenderingMode(.multicolor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.callout)
                .padding(10)
                .background(.bar)
                .help("Show which files and why")
                .accessibilityIdentifier(AccessibilityID.libraryLoadIssues)
                .popover(isPresented: $isShowingLoadIssues, arrowEdge: .top) {
                    LoadIssuesList(issues: model.loadIssues)
                }
            }
        }

        @ViewBuilder private var emptyState: some View {
            if model.results.isEmpty, model.isSearching, model.isFiltering {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Searching")
                    .accessibilityIdentifier(AccessibilityID.librarySearching)
            } else if model.results.isEmpty, !model.isSearching {
                if model.isFiltering {
                    ContentUnavailableView(
                        "No Matches",
                        systemImage: "magnifyingglass",
                        description: Text("No song matches the search and filters."),
                    )
                } else if model.catalog.isEmpty {
                    ContentUnavailableView {
                        Label("No Songs Yet", systemImage: "music.note")
                    } description: {
                        Text("Paste a chord sheet, write a song, or drop song files here.")
                    } actions: {
                        VStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Button("Paste a Song") { pasteFromEmptyState() }
                                    .buttonStyle(.segueSecondary)
                                    .disabled(!model.canPaste)
                                    .help(model.pasteUnavailableReason
                                        ?? "Review the clipboard's chord sheet as a new song (⌥⌘V)")
                                    .accessibilityIdentifier(AccessibilityID.pasteFromEmptyLibrary)
                                Button("New Song") { model.beginNewSongFlow() }
                                    .buttonStyle(.segueSecondary)
                                Button("Import Songs…") { Task { await session.chooseAndImport() } }
                                    .buttonStyle(.segueSecondary)
                                    .help("Import ChordPro, text or .crd files (⇧⌘I)")
                                    .accessibilityIdentifier(AccessibilityID.importSongs)
                            }
                            if let openGuide {
                                Button("How to bring songs in") { openGuide(.pasteASong) }
                                    .buttonStyle(.link)
                                    .accessibilityIdentifier(AccessibilityID.emptyLibraryGuide)
                            }
                        }
                    }
                    .accessibilityIdentifier(AccessibilityID.libraryEmpty)
                }
            }
        }
    }

    /// A song's actions, shared by its list row's context menu and the detail pane's "…"
    /// menu: Add to Setlist ▸, Show in Finder, Move to Trash.
    struct SongActions: View {
        let session: LibrarySession
        let songID: SongID
        /// The songs Add to Setlist adds (the multi-selection); just `songID` by default.
        var selection: [SongID] = []
        @Environment(\.songSession) private var songSession

        var body: some View {
            if selection.count <= 1, let songSession {
                Button("Rehearse Song") { songSession.start(songID, .rehearsal) }
                    .disabled(!songSession.isEnabled)
                Button("Play Song Live") { songSession.start(songID, .gig) }
                    .disabled(!songSession.isEnabled)
                Divider()
            }
            if selection.count > 1 {
                AddSongsToSetlistMenu(session: session, songIDs: selection)
            } else {
                AddToSetlistMenu(session: session, songID: songID)
            }
            if selection.count <= 1, session.library.showsWalkUps {
                Button("Walk-ups\u{2026}") { session.library.walkUpsSongID = songID }
                    .accessibilityIdentifier(AccessibilityID.librarySongWalkUps)
            }
            Button("Show in Finder") { session.revealSong(songID) }
                .accessibilityIdentifier(AccessibilityID.songShowInFinder)
            Divider()
            Button("Move to Trash", role: .destructive) {
                session.requestMoveSongToTrash(songID)
            }
            .accessibilityIdentifier(AccessibilityID.songMoveToTrash)
        }
    }

    extension FocusedValues {
        /// The song selected in the focused song list (nil while an editor is open).
        @Entry var focusedSongID: SongID?
    }

    /// The files the last library scan could not load, with the reason for each.
    private struct LoadIssuesList: View {
        let issues: [LibraryLoadIssue]

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("These files were skipped. They are left untouched in the library folder.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(issues, id: \.relativePath) { issue in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.relativePath)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                        Text(issue.message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .frame(width: 360, alignment: .leading)
        }
    }

    /// A song row (layout a): title, then "A, B · Movie" and the play count, the key chip and
    /// the proficiency mark.
    private struct SongRow: View {
        let record: SongRecord
        let stats: PlayStats?
        /// The selected row offers Rehearse and Live (R150) in place of its key chip and
        /// proficiency mark, which the preview beside it shows, so the title keeps the room
        /// it has on every other row (beside all four, it was squeezed to nothing).
        var isSelected = false

        var body: some View {
            content
                .overlay(alignment: .trailing) {
                    if isSelected {
                        sessionButtons
                    }
                }
        }

        private var sessionButtons: some View {
            SongSessionButtons(songID: record.id, size: .small)
                .fixedSize()
        }

        private var content: some View {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(SongSummary.title(record))
                            .font(SchibstedGrotesk.semiBold.font(size: 15))
                            .foregroundStyle(Theme.color.ink)
                            .lineLimit(1)
                        if record.isReadOnly {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.color.muted)
                                .help("Read-only")
                        }
                    }
                    SongCreditsLine(
                        artists: record.document.metadata.artists,
                        album: record.document.metadata.album,
                        trailing: stats.map { SongSummary.timesPlayed($0.timesPlayed) },
                    )
                    .font(SchibstedGrotesk.medium.font(size: 13))
                    .foregroundStyle(Theme.color.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SongEssentialsMark(record: record)
                // The trailing slot is as wide as the wider of its two contents, so the
                // title truncates at the same point whether or not the row is selected.
                ZStack(alignment: .trailing) {
                    accessories
                        .opacity(isSelected ? 0 : 1)
                    if isSelected {
                        sessionButtons.hidden()
                    }
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.songRow)
        }

        /// The key chip and the proficiency mark.
        private var accessories: some View {
            HStack(spacing: 12) {
                if let key = SongSummary.writtenKey(record) {
                    KeyChip(key: key)
                }
                Group {
                    if let level = record.sidecar.proficiency {
                        ProficiencyMark(level)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 82, height: 16, alignment: .leading)
            }
            .fixedSize()
        }
    }

    /// The Library detail pane: the selected song, its editor, or the new-song editor.
    struct LibraryDetailView: View {
        let model: LibraryViewModel
        let session: LibrarySession

        var body: some View {
            // One branch for the editor whatever `detail` says, so a new song's first
            // autosave (which makes it the selection) never rebuilds the editor mid-typing.
            if let editor = model.editor {
                editorView(editor)
            } else if model.multiSelection.isMultiple {
                MultiSelectionPane(session: session, songIDs: model.selectedSongs)
            } else if case let .song(id) = model.detail, let record = model.song(id: id) {
                SongDetailPane(model: model, session: session, record: record)
                    .id(id)
            } else {
                noSelection
            }
        }

        private func editorView(_ editor: SongEditorViewModel) -> some View {
            SongEditorView(model: editor) {
                Task { await model.finishEditing() }
            }
            .id(ObjectIdentifier(editor))
            // The library's names for the strip's artist and album suggestions.
            .environment(\.libraryNames, LexiconCredits(
                artists: model.knownArtists,
                albums: model.knownAlbums,
            ))
            .safeAreaInset(edge: .top, spacing: 0) {
                if let conflict = model.saveConflict {
                    SaveConflictBar(conflict: conflict) { choice in
                        Task { await model.resolveSaveConflict(choice) }
                    }
                }
            }
        }

        private var noSelection: some View {
            ContentUnavailableView(
                "No Song Selected",
                systemImage: "music.note.list",
                description: Text("Choose a song from the list, or create a new one."),
            )
        }
    }
#endif
