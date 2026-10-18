#if os(macOS)
    import Library
    import Setlists
    import SwiftUI

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
            .navigationTitle("Library")
            // The editor sets its own title; a song count under it would read as its own.
            .navigationSubtitle(model.editor == nil ? songCount(model.catalog.count) : "")
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
        @Bindable var model: LibraryViewModel
        let session: LibrarySession
        @State private var isShowingLoadIssues = false

        var body: some View {
            VStack(spacing: 0) {
                header
                Rule()
                SelectableList(items: model.results, selection: $model.listSelection) { record in
                    SongRow(record: record, stats: model.playStats[record.id])
                } menu: { record in
                    SongActions(session: session, songID: record.id)
                }
                .accessibilityIdentifier(AccessibilityID.songList)
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
                HStack(spacing: 8) {
                    SearchField(
                        text: $model.query,
                        prompt: "Search or filter",
                        accessibilityIdentifier: AccessibilityID.librarySearch,
                    )
                    Button("New song") { model.beginNewSong() }
                        .buttonStyle(.seguePrimary)
                        .help("New Song (⌘N)")
                        .accessibilityIdentifier(AccessibilityID.newSong)
                }
                FilterChipsBar(state: $model.filterState, tags: model.tags)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
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
                        Text("Write your first song in ChordPro, or drop ChordPro files here.")
                    } actions: {
                        HStack(spacing: 8) {
                            Button("New Song") { model.beginNewSong() }
                                .buttonStyle(.segueSecondary)
                            Button("Import Songs…") { Task { await session.chooseAndImport() } }
                                .buttonStyle(.segueSecondary)
                                .help("Import ChordPro or text files (⇧⌘I)")
                                .accessibilityIdentifier(AccessibilityID.importSongs)
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

        var body: some View {
            AddToSetlistMenu(session: session, songID: songID)
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

    /// A song row (layout a): title and artist, the key chip and the proficiency mark.
    private struct SongRow: View {
        let record: SongRecord
        let stats: PlayStats?

        var body: some View {
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
                    if !detail.isEmpty {
                        Text(detail)
                            .font(SchibstedGrotesk.medium.font(size: 13))
                            .foregroundStyle(Theme.color.muted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.songRow)
        }

        private var detail: String {
            [
                SongSummary.artist(record.document.metadata),
                stats.map { SongSummary.timesPlayed($0.timesPlayed) },
            ].compactMap(\.self).joined(separator: "  ·  ")
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
