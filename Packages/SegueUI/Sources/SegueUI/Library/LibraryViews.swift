#if os(macOS)
    import Library
    import Setlists
    import SwiftUI

    /// The Library destination (layout a, "three pane"): the song list column beside the
    /// selected song's preview (or its editor). The sidebar is the window's first pane.
    struct LibraryPane: View {
        @Bindable var model: LibraryViewModel
        let setlists: SetlistsViewModel

        var body: some View {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    SongListView(model: model, setlists: setlists)
                        // Layout a gives the list 420 of 1440pt; small windows keep the
                        // preview (or editor) the wider pane.
                        .frame(width: min(max(proxy.size.width * 0.32, 290), 420))
                    Rule(axis: .vertical)
                    LibraryDetailView(model: model, setlists: setlists)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// The song list column: search with typed filter tokens, filter chips, "New song",
    /// then one row per song (key chip, proficiency mark).
    struct SongListView: View {
        @Bindable var model: LibraryViewModel
        let setlists: SetlistsViewModel
        @State private var isShowingLoadIssues = false

        var body: some View {
            VStack(spacing: 0) {
                header
                Rule()
                List(selection: $model.listSelection) {
                    ForEach(model.results) { record in
                        SongRow(record: record, stats: model.playStats[record.id])
                            .tag(record.id)
                            .contextMenu { addToSetlistMenu(record) }
                    }
                }
                .listStyle(.plain)
                .accessibilityIdentifier(AccessibilityID.songList)
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
                        prompt: "Search or filter: ready, upbeat, key G",
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
                        Text("Write your first song in ChordPro.")
                    } actions: {
                        Button("New Song") { model.beginNewSong() }
                            .buttonStyle(.segueSecondary)
                    }
                    .accessibilityIdentifier(AccessibilityID.libraryEmpty)
                }
            }
        }

        @ViewBuilder
        private func addToSetlistMenu(_ record: SongRecord) -> some View {
            if setlists.setlists.isEmpty {
                Text("No setlists yet")
            } else {
                Menu("Add to Setlist") {
                    ForEach(setlists.setlists) { setlist in
                        Button(setlist.name) {
                            Task { await setlists.add(record.id, to: setlist.id) }
                        }
                        .disabled(setlist.readOnly != nil)
                    }
                }
            }
        }
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
        /// `.increased` while the row is selected (on the accent highlight).
        @Environment(\.backgroundProminence) private var prominence

        private var isHighlighted: Bool {
            prominence == .increased
        }

        var body: some View {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(SongSummary.title(record))
                            .font(SchibstedGrotesk.semiBold.font(size: 15))
                            .foregroundStyle(isHighlighted ? Color.white : Theme.color.ink)
                            .lineLimit(1)
                        if record.isReadOnly {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(isHighlighted ? Color.white : Theme.color.muted)
                                .help("Read-only")
                        }
                    }
                    if !detail.isEmpty {
                        Text(detail)
                            .font(SchibstedGrotesk.medium.font(size: 13))
                            .foregroundStyle(isHighlighted ? Color.white.opacity(0.8) : Theme.color
                                .muted)
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
            // On the selection highlight the token colours would not read; white does.
            .environment(\.onHighlight, isHighlighted)
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
        let setlists: SetlistsViewModel

        var body: some View {
            switch model.detail {
            case .newSong:
                if let editor = model.editor {
                    editorView(editor)
                } else {
                    noSelection
                }
            case let .song(id):
                if let editor = model.editor, editor.mode == .edit(id) {
                    editorView(editor)
                } else if let record = model.song(id: id) {
                    SongDetailPane(model: model, setlists: setlists, record: record)
                        .id(id)
                } else {
                    noSelection
                }
            case .empty:
                noSelection
            }
        }

        private func editorView(_ editor: SongEditorViewModel) -> some View {
            SongEditorView(
                model: editor,
                onSave: { Task { await model.saveEditor() } },
                onCancel: model.cancelEditing,
            )
            .id(ObjectIdentifier(editor))
            .safeAreaInset(edge: .top, spacing: 0) {
                if model.isEditingDeletedSong {
                    Label(
                        "This song's file was deleted outside Segue. "
                            + "Save to keep your edits as a new song.",
                        systemImage: "exclamationmark.triangle.fill",
                    )
                    .symbolRenderingMode(.multicolor)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.bar)
                    .accessibilityIdentifier(AccessibilityID.editorDeletedBanner)
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
