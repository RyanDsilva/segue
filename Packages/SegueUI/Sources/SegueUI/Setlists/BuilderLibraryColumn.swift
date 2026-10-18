#if os(macOS)
    import Library
    import Setlists
    import Support
    import SwiftUI

    /// A song dragged from the builder's library column: plain text "segue-song:<id>", so
    /// it needs no custom pasteboard type.
    enum SongDragPayload {
        static let prefix = "segue-song:"

        static func encode(_ id: SongID) -> String {
            prefix + id.description
        }

        static func decode(_ text: String) -> SongID? {
            guard text.hasPrefix(prefix) else { return nil }
            return ULID(string: String(text.dropFirst(prefix.count))).map(SongID.init)
        }
    }

    /// A set row dragged within the set: "segue-item:<item id>".
    enum SetDragPayload {
        static let prefix = "segue-item:"

        static func item(_ id: SetlistItemID) -> String {
            prefix + id.description
        }

        static func decodeItem(_ text: String) -> SetlistItemID? {
            guard text.hasPrefix(prefix) else { return nil }
            return ULID(string: String(text.dropFirst(prefix.count))).map(SetlistItemID.init)
        }
    }

    /// The builder's left column (layout a, "library to set"): search with typed filter
    /// tokens and chips, then every matching song with key, tempo and length. Songs already
    /// in the set are dimmed; `+` appends, or drag a row into the set.
    struct BuilderLibraryColumn: View {
        let setlist: Setlist
        let library: LibraryViewModel
        let onAdd: (SongID) -> Void
        @State private var state = SongFilterState()
        /// Matches for `state`; nil until the first search completes.
        @State private var matches: [SongRecord]?

        var body: some View {
            VStack(spacing: 0) {
                header
                Rule()
                // A plain stack, not a List: a List claims mouse drags for its own rows, so
                // `.draggable` rows inside one never start a drag.
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(songs) { record in
                            BuilderLibraryRow(
                                record: record,
                                inSetCount: setlist.entries.count { $0.songId == record.id },
                                isReadOnly: setlist.readOnly != nil,
                            ) { onAdd(record.id) }
                                .draggable(SongDragPayload.encode(record.id)) {
                                    DragPreview(title: SongSummary.title(record))
                                }
                        }
                    }
                }
                .overlay { emptyState }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(AccessibilityID.builderLibrary)
            }
            .background(Theme.color.surfaceAlt.opacity(0.45))
            .task(id: SearchKey(state: state, revision: library.catalogRevision)) {
                await runSearch()
            }
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Library")
                    .font(Theme.font.sectionHeading)
                    .foregroundStyle(Theme.color.ink)
                SearchField(
                    text: $state.query,
                    prompt: "Search or filter: ready, upbeat, key G",
                    accessibilityIdentifier: AccessibilityID.builderSearch,
                )
                FilterChipsBar(state: $state, tags: library.tags, maxTags: 6)
            }
            .padding(20)
        }

        private var songs: [SongRecord] {
            matches ?? library.catalog
        }

        @ViewBuilder private var emptyState: some View {
            if songs.isEmpty {
                ContentUnavailableView(
                    library.catalog.isEmpty ? "No Songs Yet" : "No Matches",
                    systemImage: "music.note",
                    description: Text(library.catalog.isEmpty
                        ? "Create songs in the Library first."
                        : "Try a different search or filter."),
                )
            }
        }

        private struct SearchKey: Equatable {
            var state: SongFilterState
            var revision: Int
        }

        private func runSearch() async {
            if !state.query.trimmingCharacters(in: .whitespaces).isEmpty {
                // Debounce typing; a newer keystroke cancels this task.
                do {
                    try await Task.sleep(for: .milliseconds(150))
                } catch {
                    return
                }
            }
            do {
                let found = try await library.builderSearch(state)
                guard !Task.isCancelled else { return }
                matches = found
            } catch {
                guard !Task.isCancelled else { return }
                library.errorMessage = UserMessage.describe(error)
            }
        }
    }

    /// One library song in the builder: grip, title, "G · 96 · 3:40", state, `+`.
    private struct BuilderLibraryRow: View {
        let record: SongRecord
        let inSetCount: Int
        let isReadOnly: Bool
        let onAdd: () -> Void
        @State private var isHovered = false

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.color.muted.opacity(0.45))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(SongSummary.title(record))
                        .font(SchibstedGrotesk.semiBold.font(size: 15))
                        .foregroundStyle(Theme.color.ink)
                        .lineLimit(1)
                    if !meta.isEmpty {
                        Text(meta)
                            .font(SchibstedGrotesk.medium.font(size: 13))
                            .foregroundStyle(Theme.color.muted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                stateLabel
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.color.ink)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Theme.color.ground),
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Theme.color.controlBorder, lineWidth: 1)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isReadOnly)
                .help("Add to the end of the set")
                .accessibilityLabel("Add \(SongSummary.title(record)) to setlist")
                .accessibilityIdentifier(AccessibilityID.builderAdd)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .opacity(inSetCount > 0 ? 0.55 : 1)
            .background(isHovered ? Theme.color.ground.opacity(0.7) : Color.clear)
            .overlay(alignment: .bottom) { Rule() }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(inSetCount > 0
                ? "\(SongSummary.title(record)), in set"
                : SongSummary.title(record))
            .accessibilityIdentifier(AccessibilityID.builderLibraryRow)
        }

        @ViewBuilder private var stateLabel: some View {
            if inSetCount > 0 {
                Text(inSetCount == 1 ? "In set" : "In set ×\(inSetCount)")
                    .font(SchibstedGrotesk.medium.font(size: 13))
                    .foregroundStyle(Theme.color.muted)
            } else if let level = record.sidecar.proficiency, level == .learning {
                Text(ProficiencyMark.label(level))
                    .font(SchibstedGrotesk.medium.font(size: 13))
                    .foregroundStyle(Theme.color.muted)
            }
        }

        /// "G · 96 · 3:40" (each part only when known).
        private var meta: String {
            [
                SongSummary.writtenKey(record),
                SongSummary.tempo(record),
                SetlistTiming.directiveLength(of: record).map { SetlistTiming.format($0.seconds) },
            ].compactMap(\.self).joined(separator: " · ")
        }
    }

    /// The pill that follows the pointer while a song is dragged.
    struct DragPreview: View {
        let title: String

        var body: some View {
            Text(title)
                .font(SchibstedGrotesk.semiBold.font(size: 14))
                .foregroundStyle(Theme.color.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.color.ground, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.color.controlBorder, lineWidth: 1)
                }
        }
    }
#endif
