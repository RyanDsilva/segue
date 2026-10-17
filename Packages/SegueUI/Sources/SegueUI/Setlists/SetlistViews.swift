#if os(macOS)
    import Library
    import Setlists
    import SwiftUI

    /// The Setlists column: all setlists plus "New Setlist".
    struct SetlistListView: View {
        @Bindable var model: SetlistsViewModel
        @State private var isNaming = false

        var body: some View {
            List(selection: $model.selection) {
                ForEach(model.setlists) { setlist in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(setlist.name)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                        Text(songCount(setlist.entries.count))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(AccessibilityID.setlistRow)
                    .tag(setlist.id)
                }
            }
            .accessibilityIdentifier(AccessibilityID.setlistList)
            .overlay {
                if model.setlists.isEmpty {
                    ContentUnavailableView {
                        Label("No Setlists Yet", systemImage: "list.number")
                    } description: {
                        Text("Create a setlist, then add songs from your library.")
                    } actions: {
                        Button("New Setlist") { isNaming = true }
                            .buttonStyle(.segueSecondary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { loadIssuesFooter }
            .navigationTitle("Setlists")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Setlist", systemImage: "plus") { isNaming = true }
                        .help("New Setlist")
                        .accessibilityIdentifier(AccessibilityID.newSetlist)
                }
            }
            .sheet(isPresented: $isNaming) {
                NewSetlistSheet { name in
                    Task { await model.create(name: name) }
                }
            }
        }

        @ViewBuilder private var loadIssuesFooter: some View {
            if !model.loadIssues.isEmpty {
                Label(
                    "\(model.loadIssues.count) setlist file(s) could not be read",
                    systemImage: "exclamationmark.triangle.fill",
                )
                .font(.callout)
                .symbolRenderingMode(.multicolor)
                .help(model.loadIssues.map { "\($0.relativePath): \($0.message)" }
                    .joined(separator: "\n"))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
            }
        }
    }

    func songCount(_ count: Int) -> String {
        count == 1 ? "1 song" : "\(count) songs"
    }

    private struct NewSetlistSheet: View {
        var onCreate: (String) -> Void
        @Environment(\.dismiss) private var dismiss
        @State private var name = ""

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                Text("New Setlist")
                    .font(.headline)
                TextField("Name", text: $name, prompt: Text("Friday at the Blue Room"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                    .onSubmit(create)
                    .accessibilityIdentifier(AccessibilityID.newSetlistName)
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.segueSecondary)
                    Button("Create", action: create)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.seguePrimary)
                        .disabled(trimmedName.isEmpty)
                        .accessibilityIdentifier(AccessibilityID.newSetlistCreate)
                }
            }
            .padding(20)
        }

        private var trimmedName: String {
            name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private func create() {
            guard !trimmedName.isEmpty else { return }
            onCreate(trimmedName)
            dismiss()
        }
    }

    /// The selected setlist: its songs in order (drag to reorder, delete to remove), with
    /// "Add Songs" and "Perform".
    struct SetlistDetailView: View {
        let setlist: Setlist
        let model: SetlistsViewModel
        let library: LibraryViewModel
        var onPerform: (Setlist) -> Void
        @State private var isAdding = false
        @State private var selectedEntries = Set<Int>()

        var body: some View {
            List(selection: $selectedEntries) {
                ForEach(Array(setlist.entries.enumerated()), id: \.offset) { offset, entry in
                    EntryRow(position: offset + 1, record: library.song(id: entry.songId))
                        .tag(offset)
                        .contextMenu {
                            Button("Remove from Setlist", role: .destructive) {
                                remove(IndexSet(integer: offset))
                            }
                            .disabled(isReadOnly)
                        }
                }
                .onMove { source, destination in
                    Task {
                        await model.move(in: setlist.id, fromOffsets: source, toOffset: destination)
                    }
                }
                .onDelete(perform: remove)
                .moveDisabled(isReadOnly)
                .deleteDisabled(isReadOnly)
            }
            .onDeleteCommand { remove(IndexSet(selectedEntries)) }
            .accessibilityIdentifier(AccessibilityID.setlistEntries)
            .overlay { emptyState }
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .navigationTitle(setlist.name)
            .toolbar {
                // The detail column's toolbar packs items at its leading edge; the flexible
                // spacer pushes the actions to the trailing end, where macOS puts them.
                ToolbarSpacer(.flexible)
                ToolbarItem(placement: .automatic) {
                    HStack(spacing: 8) {
                        Button("Add Songs", systemImage: "plus") { isAdding = true }
                            .labelStyle(.titleAndIcon)
                            .buttonStyle(.segueSecondary)
                            .help("Add songs from your library to this setlist")
                            .accessibilityLabel("Add Songs")
                            .disabled(isReadOnly)
                            .accessibilityIdentifier(AccessibilityID.setlistAddSongs)
                        Button("Perform", systemImage: "play.fill") { onPerform(setlist) }
                            .labelStyle(.titleAndIcon)
                            .buttonStyle(.seguePrimary)
                            .help("Perform this setlist full screen")
                            .disabled(setlist.entries.isEmpty)
                            .accessibilityIdentifier(AccessibilityID.setlistPerform)
                    }
                    .controlSize(.regular)
                    // Without the shared glass capsule the toolbar gives no trailing inset.
                    .padding(.trailing, 6)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .sheet(isPresented: $isAdding) {
                AddSongsSheet(library: library, setlist: setlist) { songID in
                    Task { await model.add(songID, to: setlist.id) }
                }
            }
            .onChange(of: setlist.id) { selectedEntries = [] }
        }

        private var isReadOnly: Bool {
            setlist.readOnly != nil
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(setlist.name)
                    .font(Theme.font.title)
                    .tracking(Theme.tracking.title * 28)
                    .foregroundStyle(Theme.color.ink)
                    .lineLimit(2)
                    .accessibilityIdentifier(AccessibilityID.setlistTitle)
                Text(isReadOnly
                    ? "\(songCount(setlist.entries.count)) · read-only"
                    : songCount(setlist.entries.count))
                    .font(Theme.font.body)
                    .foregroundStyle(Theme.color.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Aligns with the list rows' leading content edge below.
            .padding(.horizontal, 30)
            .padding(.top, 18)
            .padding(.bottom, 12)
            .background(.background)
        }

        @ViewBuilder private var emptyState: some View {
            if setlist.entries.isEmpty {
                ContentUnavailableView {
                    Label("No Songs in This Setlist", systemImage: "music.note.list")
                } description: {
                    Text("Add songs from your library, then drag to set the order.")
                } actions: {
                    Button("Add Songs") { isAdding = true }
                        .buttonStyle(.segueSecondary)
                        .disabled(isReadOnly)
                }
                .accessibilityIdentifier(AccessibilityID.setlistEmpty)
            }
        }

        private func remove(_ offsets: IndexSet) {
            guard !offsets.isEmpty, !isReadOnly else { return }
            selectedEntries = []
            Task { await model.remove(in: setlist.id, atOffsets: offsets) }
        }
    }

    private struct EntryRow: View {
        let position: Int
        let record: SongRecord?

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(position)")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 22, alignment: .trailing)
                VStack(alignment: .leading, spacing: 2) {
                    if let record {
                        Text(SongSummary.title(record))
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                        if let line = SongSummary.performanceLine(record.document.metadata) {
                            Text(line)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Missing song")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("It is no longer in the library folder.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 3)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.setlistEntry)
        }
    }

    /// Picks songs from the library to append to a setlist. Filtering uses the library
    /// index (FTS plus romanized-Hindi normalization), like the Library search.
    private struct AddSongsSheet: View {
        let library: LibraryViewModel
        let setlist: Setlist
        var onAdd: (SongID) -> Void
        @Environment(\.dismiss) private var dismiss
        @State private var filter = ""
        /// Index matches for `filter`; nil until the first search completes.
        @State private var matches: [SongRecord]?

        var body: some View {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add Songs to “\(setlist.name)”")
                        .font(Theme.font.sectionHeading)
                        .foregroundStyle(Theme.color.ink)
                        .lineLimit(1)
                    SearchField(
                        text: $filter,
                        prompt: "Search by title, artist or lyrics",
                        accessibilityIdentifier: AccessibilityID.addSongsSearch,
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                Divider()
                List {
                    ForEach(songs) { record in
                        row(record)
                    }
                }
                .overlay { emptyState }
                Divider()
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.seguePrimary)
                        .accessibilityIdentifier(AccessibilityID.addSongsDone)
                }
                .padding(16)
            }
            .frame(width: 440, height: 480)
            .task(id: filter) { await runSearch() }
        }

        private var songs: [SongRecord] {
            matches ?? library.catalog
        }

        @ViewBuilder private var emptyState: some View {
            if songs.isEmpty, matches != nil || library.catalog.isEmpty {
                ContentUnavailableView(
                    library.catalog.isEmpty ? "No Songs Yet" : "No Matches",
                    systemImage: "music.note",
                    description: Text(library.catalog.isEmpty
                        ? "Create songs in the Library first."
                        : "Try a different search."),
                )
            }
        }

        private func runSearch() async {
            let query = filter
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                // Debounce typing; a newer keystroke cancels this task.
                do {
                    try await Task.sleep(for: .milliseconds(150))
                } catch {
                    return
                }
            }
            do {
                let found = try await library.search(query)
                guard !Task.isCancelled else { return }
                matches = found
            } catch {
                guard !Task.isCancelled else { return }
                library.errorMessage = UserMessage.describe(error)
            }
        }

        private func row(_ record: SongRecord) -> some View {
            let count = setlist.entries.count { $0.songId == record.id }
            return HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(SongSummary.title(record))
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if let artist = SongSummary.artist(record.document.metadata) {
                        Text(artist)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if count > 0 {
                    Text(count == 1 ? "In setlist" : "In setlist ×\(count)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Button("Add") { onAdd(record.id) }
                    .buttonStyle(.segueSecondary)
                    .controlSize(.small)
                    .accessibilityIdentifier(AccessibilityID.addSongsAdd)
            }
            .padding(.vertical, 3)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.addSongsRow)
        }
    }
#endif
