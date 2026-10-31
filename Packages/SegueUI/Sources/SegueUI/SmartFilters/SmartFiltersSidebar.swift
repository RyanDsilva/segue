#if os(macOS)
    import Library
    import SwiftUI

    /// The sidebar's "Smart Filters" section (P3-6): the built-in "Missing essentials" row
    /// first (hidden while no song misses an essential, R110), each saved filter with its
    /// live count, then "New Smart Filter". Right-click a filter for Edit, Rename,
    /// Duplicate, Show in Finder and Move to Trash.
    struct SmartFiltersSidebarSection: View {
        let session: LibrarySession
        @Binding var renaming: SmartFilter?

        private var model: SmartFiltersViewModel {
            session.smartFilters
        }

        var body: some View {
            Section {
                let missing = SmartFiltersViewModel
                    .missingEssentialsCount(in: session.library.catalog)
                if missing > 0 {
                    countedRow(
                        LibraryScope.missingEssentialsName,
                        systemImage: "smallcircle.filled.circle",
                        count: missing,
                    )
                    .tag(LibrarySession.Section.missingEssentials)
                    .help("Songs without a key, length or tempo (the set essentials)")
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(AccessibilityID.missingEssentialsRow)
                }
                ForEach(model.filters) { filter in
                    countedRow(
                        filter.name,
                        systemImage: "line.3.horizontal.decrease",
                        count: SmartFiltersViewModel.count(
                            of: filter,
                            in: session.library.catalog,
                            playStats: session.library.playStats,
                        ),
                    )
                    .tag(LibrarySession.Section.smartFilter(filter.id))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(AccessibilityID.sidebarSmartFilter)
                    .contextMenu { menu(filter) }
                }
                Button {
                    model.editing = .new
                } label: {
                    Label("New Smart Filter", systemImage: "plus")
                        .foregroundStyle(Theme.color.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Save a filter of songs by tags, proficiency, key, tempo or length")
                .accessibilityIdentifier(AccessibilityID.newSmartFilter)
            } header: {
                Text("Smart Filters")
                    .accessibilityIdentifier(AccessibilityID.sidebarSmartFilters)
            }
        }

        private func countedRow(_ title: String, systemImage: String, count: Int) -> some View {
            Label {
                HStack {
                    Text(title)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } icon: {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
        }

        @ViewBuilder private func menu(_ filter: SmartFilter) -> some View {
            Button("Edit Smart Filter…") { model.editing = .edit(filter.id) }
                .disabled(filter.readOnly != nil)
            Button("Rename…") { renaming = filter }
                .disabled(filter.readOnly != nil)
            Button("Duplicate") {
                Task {
                    if let copy = await model.duplicate(filter.id) {
                        session.showSmartFilter(copy.id)
                    }
                }
            }
            Divider()
            Button("Show in Finder") {
                Task {
                    if let url = await model.fileURL(for: filter.id) {
                        session.workspace.reveal([url])
                    }
                }
            }
            Button("Move to Trash") { Task { await model.delete(filter.id) } }
        }
    }

    /// A tag row's context menu in the sidebar: Rename, Merge Into and Delete, each across
    /// the whole library in one undo step (saved smart filters follow a rename or merge).
    struct SidebarTagMenu: View {
        let tag: String
        let otherTags: [String]
        @Binding var sheet: TagSheet.Purpose?
        let onDelete: () -> Void

        var body: some View {
            Button("Rename Tag…") { sheet = .rename(tag) }
            Button("Merge Into…") { sheet = .merge(tag) }
                .disabled(otherTags.isEmpty)
            Divider()
            Button("Delete Tag", role: .destructive, action: onDelete)
        }
    }

    /// Rename a tag, or pick the tag to merge it into.
    struct TagSheet: View {
        enum Purpose: Identifiable, Hashable {
            case rename(String)
            case merge(String)

            var id: Self {
                self
            }

            var tag: String {
                switch self {
                case let .merge(tag), let .rename(tag): tag
                }
            }
        }

        let purpose: Purpose
        /// The library's other tags (merge targets).
        let otherTags: [String]
        let onCommit: (String) -> Void
        @Environment(\.dismiss) private var dismiss
        @State private var text = ""

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                Text(heading)
                    .font(Theme.font.sectionHeading)
                    .foregroundStyle(Theme.color.ink)
                switch purpose {
                case .rename:
                    TextField("New name", text: $text)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                        .onSubmit(commit)
                        .accessibilityIdentifier(AccessibilityID.tagNameField)
                case .merge:
                    Picker("Merge into", selection: $text) {
                        ForEach(otherTags, id: \.self) { Text($0).tag($0) }
                    }
                    .frame(width: 300)
                    .accessibilityIdentifier(AccessibilityID.tagMergeTarget)
                }
                Text("Every song’s tag changes, and saved smart filters follow. Edit > Undo "
                    + "puts it back.")
                    .font(Theme.font.body)
                    .foregroundStyle(Theme.color.muted)
                    .frame(width: 300, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.segueSecondary)
                    Button(isMerge ? "Merge" : "Rename", action: commit)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.seguePrimary)
                        .disabled(!canCommit)
                        .accessibilityIdentifier(AccessibilityID.tagSheetCommit)
                }
            }
            .padding(20)
            .onAppear {
                text = isMerge ? otherTags.first ?? "" : purpose.tag
            }
        }

        private var isMerge: Bool {
            if case .merge = purpose {
                return true
            }
            return false
        }

        private var heading: String {
            isMerge ? "Merge “\(purpose.tag)” Into" : "Rename Tag “\(purpose.tag)”"
        }

        private var trimmed: String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private var canCommit: Bool {
            !trimmed.isEmpty && trimmed != purpose.tag
        }

        private func commit() {
            guard canCommit else { return }
            onCommit(trimmed)
            dismiss()
        }
    }

    extension View {
        /// The smart filter editor sheet and rename sheet, hosted by the sidebar.
        func smartFilterSheets(
            session: LibrarySession,
            renaming: Binding<SmartFilter?>,
        ) -> some View {
            modifier(SmartFilterSheets(session: session, renaming: renaming))
        }
    }

    private struct SmartFilterSheets: ViewModifier {
        let session: LibrarySession
        @Binding var renaming: SmartFilter?

        func body(content: Content) -> some View {
            @Bindable var model = session.smartFilters
            content
                .sheet(item: $model.editing) { request in
                    editor(request)
                }
                .sheet(item: $renaming) { filter in
                    SmartFilterRenameSheet(name: filter.name) { name in
                        Task { await model.rename(filter.id, to: name) }
                    }
                }
        }

        @ViewBuilder private func editor(_ request: SmartFiltersViewModel
            .EditorRequest) -> some View
        {
            let library = session.library
            switch request {
            case .new:
                SmartFilterEditorSheet(
                    title: "New Smart Filter",
                    saveTitle: "Save",
                    draft: SmartFilterDraft(name: "", conditions: SmartFilterConditions()),
                    libraryTags: library.tagNames,
                    libraryArtists: library.knownArtists,
                    libraryAlbums: library.knownAlbums,
                    songs: library.catalog,
                    playStats: library.playStats,
                ) { name, conditions in
                    Task { await session.createSmartFilter(name: name, conditions: conditions) }
                }
            case let .edit(id):
                if let filter = session.smartFilters.filter(id) {
                    SmartFilterEditorSheet(
                        title: "Edit Smart Filter",
                        saveTitle: "Save",
                        draft: SmartFilterDraft(name: filter.name, conditions: filter.conditions),
                        libraryTags: library.tagNames,
                        libraryArtists: library.knownArtists,
                        libraryAlbums: library.knownAlbums,
                        songs: library.catalog,
                        playStats: library.playStats,
                    ) { name, conditions in
                        let filters = session.smartFilters
                        Task { await filters.save(id, name: name, conditions: conditions) }
                    }
                }
            }
        }
    }

    /// Rename a smart filter.
    struct SmartFilterRenameSheet: View {
        let name: String
        let onCommit: (String) -> Void
        @Environment(\.dismiss) private var dismiss
        @State private var text = ""

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                Text("Rename Smart Filter")
                    .font(Theme.font.sectionHeading)
                    .foregroundStyle(Theme.color.ink)
                TextField("Name", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                    .onSubmit(commit)
                    .accessibilityIdentifier(AccessibilityID.smartFilterName)
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.segueSecondary)
                    Button("Rename", action: commit)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.seguePrimary)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .onAppear { text = name }
        }

        private func commit() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            onCommit(trimmed)
            dismiss()
        }
    }
#endif
