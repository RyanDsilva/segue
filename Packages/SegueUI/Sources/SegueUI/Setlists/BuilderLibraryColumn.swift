#if os(macOS)
    import AppKit
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

    /// Pick mode's library checklist (R84, direction C): search with typed filter tokens and
    /// chips, then every matching song with a checkbox. A ticked box shows the song's
    /// number in the set; tick order is set order. Click or Space ticks the focused row,
    /// ↑ / ↓ move the focus, Return (or ↓) in the search field moves it to the first
    /// result, and ⌘A (Edit > Select All) ticks every row the filter shows. Unticking
    /// removes the song's entry. A song is in a set at most once, so a ticked row simply is
    /// in the set. Unticked rows still drag into the set.
    struct BuilderLibraryColumn: View {
        let setlist: Setlist
        /// Read here (not only through `setlist`) so a tick re-renders the checklist at once.
        let model: SetlistsViewModel
        let library: LibraryViewModel
        /// Ticks (adds) or unticks (removes) a song.
        let onToggle: (SongID) -> Void
        /// ⌘A: ticks these songs (the rows shown, in order).
        let onTickAll: ([SongID]) -> Void
        @State private var state = SongFilterState()
        /// Matches for `state`; nil until the first search completes.
        @State private var matches: [SongRecord]?
        /// The row Space ticks.
        /// The row Space ticks, shared with the rows (they read it in their own bodies).
        @State private var cursor = PickCursor()
        @FocusState private var listFocused: Bool

        private var focusedRow: SongID? {
            get { cursor.row }
            nonmutating set { cursor.row = newValue }
        }

        var body: some View {
            let rows = pickRows
            VStack(spacing: 0) {
                header
                Rule()
                // A plain stack, not a List: a List claims mouse drags for its own rows, so
                // `.draggable` rows inside one never start a drag.
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // The tick state is part of the data: a lazy stack does not
                            // re-render a row when only a value its closure captured changed.
                            ForEach(rows) { pick in
                                row(pick)
                            }
                        }
                    }
                    .focusable()
                    .focusEffectDisabled()
                    .focused($listFocused)
                    .onChange(of: listFocused, initial: true) { _, focused in
                        cursor.isActive = focused
                    }
                    .onKeyPress(.upArrow) { moveFocus(-1, proxy: proxy) }
                    .onKeyPress(.downArrow) { moveFocus(1, proxy: proxy) }
                    .onKeyPress(.space) { tickFocused() }
                    // Edit > Select All does not reach a SwiftUI list, so ⌘A arrives as a key.
                    .onKeyPress(keys: ["a"]) { press in
                        guard press.modifiers == .command else { return .ignored }
                        tickAllShown()
                        return .handled
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

        /// One checklist row: the song and its number in the set (nil when not ticked).
        private struct PickRow: Identifiable, Equatable {
            var record: SongRecord
            var number: Int?

            var id: SongID {
                record.id
            }
        }

        /// The rows shown, each with its number in the set (songs only, across parts).
        private var pickRows: [PickRow] {
            var numbers: [SongID: Int] = [:]
            let current = model.setlist(setlist.id) ?? setlist
            for (offset, song) in current.entries.compactMap(\.songId).enumerated() {
                numbers[song] = numbers[song] ?? offset + 1
            }
            return songs.map { record in
                PickRow(
                    record: record,
                    number: numbers[record.id],
                )
            }
        }

        /// A song already in the set has no drag source, so dragging it never shows a drop
        /// indicator in the set.
        @ViewBuilder
        private func row(_ pick: PickRow) -> some View {
            let record = pick.record
            let number = pick.number
            let row = BuilderLibraryRow(
                record: record,
                tick: TickSource(model: model, setlist: setlist),
                cursor: cursor,
                isReadOnly: setlist.readOnly != nil,
            ) {
                focusedRow = record.id
                listFocused = true
                onToggle(record.id)
            }
            .id(record.id)
            if number != nil {
                row
            } else {
                row.draggable(SongDragPayload.encode(record.id)) {
                    DragPreview(title: SongSummary.title(record))
                }
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
                    onSubmit: focusFirstResult,
                )
                FilterChipsBar(state: $state, tags: library.tags, maxTags: 6)
            }
            .padding(20)
        }

        private var songs: [SongRecord] {
            matches ?? library.catalog
        }

        private var isReadOnly: Bool {
            setlist.readOnly != nil
        }

        private func focusFirstResult() {
            focusedRow = songs.first?.id
            listFocused = true
        }

        private func moveFocus(_ delta: Int, proxy: ScrollViewProxy) -> KeyPress.Result {
            let ids = songs.map(\.id)
            guard !ids.isEmpty else { return .ignored }
            let current = focusedRow.flatMap { ids.firstIndex(of: $0) }
            let next = current.map { min(max($0 + delta, 0), ids.count - 1) }
                ?? (delta > 0 ? 0 : ids.count - 1)
            focusedRow = ids[next]
            proxy.scrollTo(ids[next])
            return .handled
        }

        private func tickFocused() -> KeyPress.Result {
            guard !isReadOnly, let focusedRow, songs.contains(where: { $0.id == focusedRow })
            else { return .ignored }
            onToggle(focusedRow)
            return .handled
        }

        private func tickAllShown() {
            guard !isReadOnly else { return }
            onTickAll(songs.map(\.id))
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

    /// One library song in Pick: a checkbox (the song's set number when ticked), title,
    /// "G · 96 · 3:40" and "Learning" when it applies. Clicking anywhere on the row ticks
    /// or unticks it.
    /// Pick's keyboard cursor: the row Space ticks, and whether the checklist has focus.
    @MainActor
    @Observable
    final class PickCursor {
        var row: SongID?
        var isActive = false
    }

    /// Where a row reads its tick: the setlist as the view model holds it now, read in the
    /// row's own body so a tick re-renders the row however the lazy stack caches it.
    @MainActor
    private struct TickSource {
        let model: SetlistsViewModel
        let setlist: Setlist

        func number(of song: SongID) -> Int? {
            let current = model.setlist(setlist.id) ?? setlist
            return current.entries.lazy.compactMap(\.songId).firstIndex(of: song).map { $0 + 1 }
        }
    }

    private struct BuilderLibraryRow: View {
        let record: SongRecord
        let tick: TickSource
        let cursor: PickCursor
        let isReadOnly: Bool
        let onToggle: () -> Void
        @State private var isHovered = false

        private var isInSet: Bool {
            number != nil
        }

        private var isFocused: Bool {
            cursor.isActive && cursor.row == record.id
        }

        var body: some View {
            let number = tick.number(of: record.id)
            HStack(spacing: 12) {
                checkbox(number)
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
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(background)
            .overlay(alignment: .leading) {
                if isFocused {
                    Rectangle().fill(Theme.color.ink).frame(width: 3)
                }
            }
            .overlay(alignment: .bottom) { Rule() }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture {
                if !isReadOnly {
                    onToggle()
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(isInSet
                ? "\(SongSummary.title(record)), already in set"
                : SongSummary.title(record))
            .accessibilityIdentifier(AccessibilityID.builderLibraryRow)
        }

        private var background: Color {
            if isFocused {
                return Theme.color.ground
            }
            return isHovered ? Theme.color.ground.opacity(0.7) : Color.clear
        }

        /// A box; ticked, it is filled and shows the song's number in the set. A button for
        /// VoiceOver and the keyboard ("Add Harbour Lights to setlist" / "Remove ...").
        /// The song's number in the set; nil when it is not in the set.
        private var number: Int? {
            tick.number(of: record.id)
        }

        private func checkbox(_ number: Int?) -> some View {
            Button(action: onToggle) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isInSet ? Theme.color.ink : Theme.color.ground)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(
                            isInSet ? Theme.color.ink : Theme.color.lineStrong,
                            lineWidth: 1.5,
                        )
                    if let number {
                        Text("\(number)")
                            .font(SchibstedGrotesk.extraBold.font(size: number > 99 ? 8 : 10.5))
                            .foregroundStyle(Theme.color.ground)
                            .minimumScaleFactor(0.6)
                    }
                }
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isReadOnly)
            .help(isInSet ? "In the set at #\(number ?? 0). Click to take it out."
                : "Add to the end of the set")
            .accessibilityLabel(isInSet
                ? "Remove \(SongSummary.title(record)) from setlist"
                : "Add \(SongSummary.title(record)) to setlist")
            .accessibilityValue(isInSet ? "In set at \(number ?? 0)" : "")
            .accessibilityAddTraits(isInSet ? .isSelected : [])
            .accessibilityIdentifier(isInSet ? AccessibilityID.builderInSet : AccessibilityID
                .builderAdd)
        }

        @ViewBuilder private var stateLabel: some View {
            if let level = record.sidecar.proficiency, level == .learning {
                Text(ProficiencyMark.label(level))
                    .font(SchibstedGrotesk.medium.font(size: 13))
                    .foregroundStyle(Theme.color.muted)
            }
        }

        /// "G · 96 · 3:40" (each part only when known; a missing length reads --:--).
        private var meta: String {
            [
                SongSummary.writtenKey(record),
                SongSummary.tempo(record),
                SetlistTiming.directiveLength(of: record).map { SetlistTiming.format($0.seconds) }
                    ?? SetlistTiming.unknownText,
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
