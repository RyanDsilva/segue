#if os(macOS)
    import Library
    import Setlists
    import SwiftUI

    /// The main window's sidebar (layout a): Library and Gig log, every setlist (with
    /// "New Setlist"), the smart filters (P3-6), then the most used tags (clicking one
    /// filters the library by it; right-click to rename, merge or delete it).
    struct MainSidebar: View {
        @Bindable var session: LibrarySession
        @State private var naming: SetlistNameSheet.Purpose?
        @State private var renaming: Setlist?
        @State private var renamingFilter: SmartFilter?
        @State private var tagSheet: TagSheet.Purpose?

        var body: some View {
            List(selection: $session.sidebarSelection) {
                Label {
                    countedRow("Library", count: session.library.catalog.count)
                } icon: {
                    Image(systemName: "music.note.list")
                }
                .tag(LibrarySession.Section.library)
                .accessibilityIdentifier(AccessibilityID.sidebarLibrary)
                Label("Gig Log", systemImage: "music.mic")
                    .tag(LibrarySession.Section.gigLog)
                    .accessibilityIdentifier(AccessibilityID.sidebarGigLog)
                Section {
                    ForEach(session.setlists.setlists) { setlist in
                        setlistRow(setlist)
                    }
                    if session.setlists.setlists.isEmpty {
                        Text("No setlists yet")
                            .foregroundStyle(Theme.color.muted)
                            .selectionDisabled()
                    }
                } header: {
                    setlistsHeader
                }
                SmartFiltersSidebarSection(session: session, renaming: $renamingFilter)
                if !session.library.tags.isEmpty {
                    Section("Tags") {
                        ForEach(session.library.tags.prefix(12), id: \.tag) { tag in
                            tagRow(tag)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    loadIssuesFooter
                    newSetlistButton
                }
            }
            .smartFilterSheets(session: session, renaming: $renamingFilter)
            .sheet(item: $tagSheet) { purpose in
                TagSheet(purpose: purpose, otherTags: otherTags(than: purpose.tag)) { name in
                    Task {
                        switch purpose {
                        case let .rename(tag): await session.renameTag(tag, to: name)
                        case let .merge(tag): await session.mergeTag(tag, into: name)
                        }
                    }
                }
            }
            .sheet(item: $naming) { purpose in
                SetlistNameSheet(purpose: purpose) { name in
                    if let setlist = renaming {
                        Task { await session.setlists.rename(setlist.id, to: name) }
                    }
                }
            }
        }

        private func countedRow(_ title: String, count: Int) -> some View {
            HStack {
                Text(title)
                Spacer(minLength: 4)
                // Hierarchical, so it stays legible on the selection highlight.
                Text("\(count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }

        private var setlistsHeader: some View {
            Text("Setlists")
                .accessibilityIdentifier(AccessibilityID.sidebarSetlists)
        }

        /// "New Setlist" pinned under the sidebar list (macOS sidebar section headers do not
        /// expose their buttons to accessibility, so the action lives here).
        private var newSetlistButton: some View {
            Button {
                session.isNamingNewSetlist = true
            } label: {
                Label("New Setlist", systemImage: "plus")
                    .font(SchibstedGrotesk.semiBold.font(size: 13))
                    .foregroundStyle(Theme.color.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .help("New Setlist")
            .accessibilityIdentifier(AccessibilityID.newSetlist)
            // Its own view, so it never competes with the rename sheet. Also opened by
            // Setlist > New Setlist… (Shift-Cmd-N).
            .sheet(isPresented: $session.isNamingNewSetlist) {
                SetlistNameSheet(purpose: .create) { name in
                    Task { await session.setlists.create(name: name) }
                }
            }
        }

        private func setlistRow(_ setlist: Setlist) -> some View {
            countedRow(setlist.name, count: setlist.entries.count)
                .lineLimit(1)
                .tag(LibrarySession.Section.setlist(setlist.id))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(AccessibilityID.setlistRow)
                .contextMenu {
                    SetlistActions(
                        setlist: setlist,
                        model: session.setlists,
                        onRename: {
                            renaming = setlist
                            naming = .rename(setlist.name)
                        },
                        onReveal: { Task { await session.revealSetlist(setlist.id) } },
                    )
                }
        }

        private func tagRow(_ tag: TagCount) -> some View {
            Button {
                session.library.navigate {
                    session.library.filterState.tags = [tag.tag]
                    session.section = .library
                }
            } label: {
                HStack {
                    Text(tag.tag)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(tag.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show songs tagged “\(tag.tag)”")
            .accessibilityIdentifier(AccessibilityID.sidebarTag)
            .contextMenu {
                SidebarTagMenu(
                    tag: tag.tag,
                    otherTags: otherTags(than: tag.tag),
                    sheet: $tagSheet,
                ) {
                    Task { await session.deleteTag(tag.tag) }
                }
            }
        }

        /// Every library tag but `tag` (merge targets).
        private func otherTags(than tag: String) -> [String] {
            session.library.tags.map(\.tag).filter {
                $0.caseInsensitiveCompare(tag) != .orderedSame
            }
        }

        @ViewBuilder private var loadIssuesFooter: some View {
            let issues = session.setlists.loadIssues
            if !issues.isEmpty {
                Label(
                    issues.count == 1
                        ? "1 setlist file could not be read"
                        : "\(issues.count) setlist files could not be read",
                    systemImage: "exclamationmark.triangle.fill",
                )
                .font(.callout)
                .symbolRenderingMode(.multicolor)
                .help(issues.map { "\($0.relativePath): \($0.message)" }.joined(separator: "\n"))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
#endif
