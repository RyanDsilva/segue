#if os(macOS)
    import Library
    import Setlists
    import SwiftUI

    /// The Library column: searchable song list with a "New Song" action.
    struct SongListView: View {
        @Bindable var model: LibraryViewModel
        let setlists: SetlistsViewModel
        @State private var isShowingLoadIssues = false

        var body: some View {
            List(selection: $model.listSelection) {
                ForEach(model.results) { record in
                    SongRow(record: record)
                        .tag(record.id)
                        .contextMenu { addToSetlistMenu(record) }
                }
            }
            .accessibilityIdentifier(AccessibilityID.songList)
            .overlay { emptyState }
            .safeAreaInset(edge: .bottom, spacing: 0) { loadIssuesFooter }
            // Search belongs to this column (it filters this list), not the window toolbar.
            .safeAreaBar(edge: .top) {
                SearchField(
                    text: $model.query,
                    prompt: "Search songs",
                    accessibilityIdentifier: AccessibilityID.librarySearch,
                )
                .padding(.horizontal, 12)
                .padding(.top, 2)
                .padding(.bottom, 8)
            }
            .navigationTitle("Library")
            .navigationSubtitle(subtitle)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await model.refresh() }
                    }
                    .help("Pick up changes made in other apps (⌘R)")
                    .accessibilityIdentifier(AccessibilityID.refreshLibrary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New Song", systemImage: "square.and.pencil") {
                        model.beginNewSong()
                    }
                    .help("New Song (⌘N)")
                    .accessibilityIdentifier(AccessibilityID.newSong)
                }
            }
        }

        private var subtitle: String {
            let count = model.catalog.count
            return count == 1 ? "1 song" : "\(count) songs"
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
                    ContentUnavailableView.search(text: model.query)
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

    private struct SongRow: View {
        let record: SongRecord

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(SongSummary.title(record))
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if record.isReadOnly {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Read-only")
                    }
                }
                let detail = [
                    SongSummary.artist(record.document.metadata),
                    SongSummary.performanceLine(record.document.metadata),
                ].compactMap(\.self).joined(separator: "  ·  ")
                if !detail.isEmpty {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 3)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.songRow)
        }
    }

    /// The Library detail pane: the selected song, its editor, or the new-song editor.
    struct LibraryDetailView: View {
        let model: LibraryViewModel

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
                    SongDetailPane(model: model, record: record)
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

    private struct SongDetailPane: View {
        let model: LibraryViewModel
        let record: SongRecord

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let reason = record.readOnly {
                        notice(UserMessage.readOnlyText(reason), systemImage: "lock.fill")
                    }
                    if record.hasDerivedID {
                        notice(
                            "Segue could not read this song's ID from its metadata file, so "
                                + "setlists lose track of it if the file is renamed.",
                            systemImage: "link.badge.plus",
                        )
                    }
                    // The song as its display toggles render it (transpose, capo, Nashville,
                    // diagrams), the same model the editor and the stage use.
                    SongPageView(
                        model: SongSummary.renderModel(record),
                        fallbackTitle: SongSummary.title(record),
                    )
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.color.ground)
            .navigationTitle(SongSummary.title(record))
            .toolbar { editButton }
        }

        private func notice(_ text: String, systemImage: String) -> some View {
            Label(text, systemImage: systemImage)
                .font(.callout)
                .foregroundStyle(Theme.color.muted)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.color.surfaceAlt, in: RoundedRectangle(cornerRadius: 8))
        }

        @ToolbarContentBuilder private var editButton: some ToolbarContent {
            ToolbarSpacer(.flexible)
            ToolbarItem(placement: .automatic) {
                Button("Edit", systemImage: "pencil") {
                    model.beginEditing(record)
                }
                .help(record.isReadOnly ? "This song is read-only" : "Edit ChordPro")
                .disabled(record.isReadOnly)
                .accessibilityIdentifier(AccessibilityID.editSong)
            }
        }
    }
#endif
